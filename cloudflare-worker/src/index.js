// =============================================================================
// AVERIS – Cloudflare Worker
//
// Corre a cada 5 minutos (cron trigger).
// Para cada utilizador com token FCM:
//   • Verifica consumo elevado
//   • Verifica meta atingida
//   • Verifica subida de nível
//   • Verifica dispositivos offline
// Envia notificações push via Firebase Cloud Messaging (FCM HTTP v1).
//
// Secrets necessários (wrangler secret put <NAME>):
//   FIREBASE_CLIENT_EMAIL  — client_email do service account
//   FIREBASE_PRIVATE_KEY   — private_key do service account
//
// Variável de ambiente (wrangler.toml [vars]):
//   FIREBASE_PROJECT_ID    — project_id do Firebase
// =============================================================================

export default {
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(runChecks(env));
  },
};

// ── Autenticação Google (JWT → OAuth2 access token) ──────────────────────────

async function getAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);

  const headerB64 = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payloadB64 = b64url(
    JSON.stringify({
      iss: env.FIREBASE_CLIENT_EMAIL,
      scope: [
        'https://www.googleapis.com/auth/datastore',
        'https://www.googleapis.com/auth/firebase.messaging',
      ].join(' '),
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );

  const signingInput = `${headerB64}.${payloadB64}`;
  const key = await importPrivateKey(env.FIREBASE_PRIVATE_KEY);
  const sigBytes = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );

  const jwt = `${signingInput}.${b64urlBytes(sigBytes)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  const { access_token } = await res.json();
  return access_token;
}

async function importPrivateKey(pem) {
  const cleaned = pem
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');

  const binary = atob(cleaned);
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    'pkcs8',
    bytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

// ── Helpers Base64url ─────────────────────────────────────────────────────────

function b64url(str) {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function b64urlBytes(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

// ── Firestore: conversão de tipos ─────────────────────────────────────────────

// Converte um valor Firestore (ex: { stringValue: "x" }) para JS nativo
function fromFs(value) {
  if (!value) return undefined;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('nullValue' in value) return null;
  if ('mapValue' in value) {
    const result = {};
    for (const [k, v] of Object.entries(value.mapValue.fields ?? {})) {
      result[k] = fromFs(v);
    }
    return result;
  }
  if ('arrayValue' in value) {
    return (value.arrayValue.values ?? []).map(fromFs);
  }
  return undefined;
}

// Converte um valor JS nativo para o formato Firestore
function toFs(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (typeof val === 'number') {
    return Number.isInteger(val)
      ? { integerValue: String(val) }
      : { doubleValue: val };
  }
  if (typeof val === 'string') return { stringValue: val };
  if (typeof val === 'object') {
    const fields = {};
    for (const [k, v] of Object.entries(val)) {
      fields[k] = toFs(v);
    }
    return { mapValue: { fields } };
  }
  return { nullValue: null };
}

// Converte um documento Firestore completo em objeto JS simples
function docToObj(doc) {
  const obj = {};
  for (const [k, v] of Object.entries(doc.fields ?? {})) {
    obj[k] = fromFs(v);
  }
  return obj;
}

// ── Firestore: REST API ───────────────────────────────────────────────────────

const fsBase = (projectId) =>
  `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

// Faz uma query estruturada numa coleção com filtro de igualdade
async function fsQuery(token, projectId, collectionId, field, value) {
  const res = await fetch(`${fsBase(projectId)}:runQuery`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId }],
        where: {
          fieldFilter: {
            field: { fieldPath: field },
            op: 'EQUAL',
            value: { stringValue: value },
          },
        },
      },
    }),
  });
  return res.ok ? res.json() : [];
}

// Atualiza um campo de topo (ex: '_notifState') num documento
async function fsPatch(token, projectId, docPath, fieldName, jsValue) {
  const res = await fetch(
    `${fsBase(projectId)}/${docPath}?updateMask.fieldPaths=${encodeURIComponent(fieldName)}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        fields: { [fieldName]: toFs(jsValue) },
      }),
    },
  );
  return res.ok;
}

// ── FCM: enviar notificação push ──────────────────────────────────────────────

async function sendFcm(token, projectId, fcmToken, title, body) {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body },
          android: { priority: 'high' },
          apns: { payload: { aps: { sound: 'default', badge: 1 } } },
        },
      }),
    },
  );

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    // Token inválido/expirado — o Worker não apaga o token (a app trata isso)
    console.warn(`FCM falhou para token ${fcmToken.slice(0, 10)}…:`, err?.error?.status);
  }

  return res.ok;
}

// ── Horário silencioso ────────────────────────────────────────────────────────

function isQuietHours(notifSettings) {
  const quiet = notifSettings?.quietHours;
  if (!quiet?.enabled) return false;

  // Usa a hora de Lisboa (UTC+0 ou UTC+1 conforme horário de verão)
  const now = new Date();
  const lisbon = new Intl.DateTimeFormat('pt-PT', {
    timeZone: 'Europe/Lisbon',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(now);

  const [h, m] = lisbon.split(':').map(Number);
  const current = h * 60 + m;

  const [startH, startM] = (quiet.start ?? '22:00').split(':').map(Number);
  const [endH, endM] = (quiet.end ?? '07:00').split(':').map(Number);
  const start = startH * 60 + startM;
  const end = endH * 60 + endM;

  return start > end
    ? current >= start || current <= end
    : current >= start && current <= end;
}

// ── Lógica principal ──────────────────────────────────────────────────────────

async function runChecks(env) {
  const token = await getAccessToken(env);
  const projectId = env.FIREBASE_PROJECT_ID;

  // Vai buscar todos os utilizadores (máx 100 por página)
  const res = await fetch(`${fsBase(projectId)}/users?pageSize=100`, {
    headers: { Authorization: `Bearer ${token}` },
  });

  const data = await res.json();
  if (!data.documents?.length) return;

  for (const userDoc of data.documents) {
    try {
      await processUser(userDoc, token, projectId);
    } catch (e) {
      console.error(`Erro no utilizador ${userDoc.name.split('/').pop()}:`, e);
    }
  }
}

async function processUser(userDoc, token, projectId) {
  const uid = userDoc.name.split('/').pop();
  const data = docToObj(userDoc);

  // Sem token FCM = não pode receber notificações
  const fcmToken = data.fcmToken;
  if (!fcmToken) return;

  const notifSettings = data.settings?.notifications ?? {};
  if (isQuietHours(notifSettings)) return;

  // Estado anterior guardado (evita notificações duplicadas entre execuções)
  const prevState = data._notifState ?? {};
  const newState = { ...prevState }; // copia para modificar
  const notifications = [];

  // ── Consumo elevado ──────────────────────────────────────────────────────
  if (notifSettings.highConsumption === true) {
    const consumoHoje = Number(data.consumoHoje ?? 0);
    const limite = Number(data.settings?.consumoLimiteDiario ?? 10);

    if (consumoHoje > limite) {
      notifications.push({
        title: '⚡ Consumo elevado',
        body: `Já consumiste ${consumoHoje.toFixed(1)} kWh hoje (limite: ${limite.toFixed(1)} kWh).`,
      });
    }
  }

  // ── Meta de poupança ─────────────────────────────────────────────────────
  if (notifSettings.goalReached === true) {
    const goalKwh = Number(data.goals?.monthlyKwhTarget ?? 0);
    const consumoMes = Number(data.consumoMes ?? 0);
    const goalReached = goalKwh > 0 && consumoMes <= goalKwh;
    const lastGoal = prevState.lastGoal === true;

    if (goalReached && !lastGoal) {
      notifications.push({
        title: '🎯 Meta atingida!',
        body: 'Parabéns! Atingiste a tua meta de poupança de energia.',
      });
      newState.lastGoal = true;
    } else if (!goalReached && lastGoal) {
      // Reset quando o mês muda e a meta deixa de estar atingida
      newState.lastGoal = false;
    }
  }

  // ── Subida de nível ──────────────────────────────────────────────────────
  if (notifSettings.levelUp === true) {
    const currentLevel = Number(data.nivel ?? 1);
    const lastLevel = Number(prevState.lastLevel ?? currentLevel);

    if (currentLevel > lastLevel) {
      notifications.push({
        title: '🏆 Subiste de nível!',
        body: `Chegaste ao nível ${currentLevel}. Continua assim!`,
      });
    }
    newState.lastLevel = currentLevel;
  }

  // ── Dispositivos offline ─────────────────────────────────────────────────
  if (notifSettings.deviceOffline === true) {
    const lastDeviceStates = prevState.deviceStates ?? {};
    const newDeviceStates = {};

    const queryResult = await fsQuery(token, projectId, 'devices', 'userId', uid);

    for (const item of queryResult) {
      if (!item.document) continue;

      const devId = item.document.name.split('/').pop();
      const dev = docToObj(item.document);
      const isOnline = dev.online === true;
      const devName = dev.name ?? 'Dispositivo';

      newDeviceStates[devId] = isOnline;

      // Notifica apenas na transição online → offline
      if (lastDeviceStates[devId] === true && !isOnline) {
        notifications.push({
          title: '⚠️ Dispositivo offline',
          body: `${devName} ficou sem ligação.`,
        });
      }
    }

    newState.deviceStates = newDeviceStates;
  }

  // ── Enviar notificações FCM ──────────────────────────────────────────────
  for (const { title, body } of notifications) {
    await sendFcm(token, projectId, fcmToken, title, body);
  }

  // ── Persistir novo estado no Firestore ───────────────────────────────────
  // Só escreve se o estado mudou (evita writes desnecessários)
  const stateChanged =
    JSON.stringify(newState) !== JSON.stringify(prevState);

  if (stateChanged) {
    await fsPatch(token, projectId, `users/${uid}`, '_notifState', newState);
  }
}
