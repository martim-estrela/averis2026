import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AVERIS – BackgroundService (WorkManager)
//
// Responsabilidades:
//   • Registar tarefas periódicas que correm mesmo com a app fechada
//   • Verificar consumo, meta e nível XP em background
//   • Respeitar as preferências de notificação do utilizador
//
// ⚠️  IMPORTANTE:
//   • callbackDispatcher TEM DE SER uma função top-level (fora de qualquer classe)
//   • No iOS o intervalo mínimo real é ~15 min (limitação do sistema)
//   • No Android funciona de forma fiável
//
// Uso em main.dart:
//   await BackgroundService.init();
//   await BackgroundService.registerTasks();  ← após login
//   await BackgroundService.cancelTasks();    ← após logout
// ─────────────────────────────────────────────────────────────────────────────

// Nomes das tarefas — usar constantes evita typos
const _kTaskConsumo = 'averis.checkConsumo';
const _kTaskDispositivos = 'averis.checkDispositivos';

// ─────────────────────────────────────────────────────────────────────────────
// ⚠️  TOP-LEVEL — NÃO mover para dentro de nenhuma classe
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // O Firebase precisa de ser reinicializado em processos isolados
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Já inicializado — ignorar
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true; // Utilizador não autenticado, sai sem erro

    // Inicializa o plugin de notificações locais
    await NotificationService.init();

    // Lê o documento do utilizador
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (!snap.exists) return true;

    final data = (snap.data() as Map?)?.cast<String, dynamic>() ?? {};
    final notifSettings =
        (data['settings']?['notifications'] as Map?)
            ?.cast<String, dynamic>() ??
        {};

    // Verifica horário silencioso
    if (_isQuietHours(notifSettings)) return true;

    switch (taskName) {
      case _kTaskConsumo:
        await _runCheckConsumo(data, notifSettings, uid);
        break;
      case _kTaskDispositivos:
        await _runCheckDispositivos(data, notifSettings, uid);
        break;
    }

    return true; // true = sucesso | false = retry automático
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Classe de gestão
// ─────────────────────────────────────────────────────────────────────────────

class BackgroundService {
  BackgroundService._();

  /// Inicializa o WorkManager. Chamar uma vez em main.dart.
  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // muda para true durante o desenvolvimento
    );
  }

  /// Regista as tarefas periódicas. Chamar após o utilizador fazer login.
  static Future<void> registerTasks() async {
    // Verifica consumo a cada hora
    await Workmanager().registerPeriodicTask(
      _kTaskConsumo,
      _kTaskConsumo,
      frequency: const Duration(hours: 1),
      initialDelay: const Duration(minutes: 5),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    // Verifica dispositivos offline a cada 15 minutos
    await Workmanager().registerPeriodicTask(
      _kTaskDispositivos,
      _kTaskDispositivos,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 2),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// Cancela todas as tarefas. Chamar quando o utilizador faz logout.
  static Future<void> cancelTasks() async {
    await Workmanager().cancelAll();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lógica das tarefas (funções privadas top-level para o isolate)
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _runCheckConsumo(
  Map<String, dynamic> data,
  Map<String, dynamic> settings,
  String uid,
) async {
  // ── Consumo elevado ──────────────────────────────────────────────────────
  if (settings['highConsumption'] == true) {
    final consumo = (data['consumoHoje'] as num?)?.toDouble() ?? 0;
    final limite =
        (data['settings']?['consumoLimiteDiario'] as num?)?.toDouble() ?? 10.0;

    if (consumo > limite) {
      await NotificationService.showLocalNotification(
        title: '⚡ Consumo elevado',
        body:
            'Já consumiste ${consumo.toStringAsFixed(1)} kWh hoje '
            '(limite: ${limite.toStringAsFixed(1)} kWh).',
      );
    }
  }

  // ── Meta de poupança ─────────────────────────────────────────────────────
  if (settings['goalReached'] == true) {
    final goalReached = data['meta']?['atingida'] == true;

    // Lê o estado anterior guardado no Firestore para evitar repetições
    final lastGoal = data['_notifState']?['lastGoal'] == true;

    if (goalReached && !lastGoal) {
      await NotificationService.showLocalNotification(
        title: '🎯 Meta atingida!',
        body: 'Parabéns! Atingiste a tua meta de poupança de energia.',
      );

      // Guarda o estado para não repetir
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'_notifState.lastGoal': true});
    } else if (!goalReached && lastGoal) {
      // Reset quando a meta é renovada
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'_notifState.lastGoal': false});
    }
  }

  // ── Nível XP ─────────────────────────────────────────────────────────────
  if (settings['levelUp'] == true) {
    final currentLevel = (data['xp']?['nivel'] as num?)?.toInt() ?? 1;
    final lastLevel =
        (data['_notifState']?['lastLevel'] as num?)?.toInt() ?? currentLevel;

    if (currentLevel > lastLevel) {
      await NotificationService.showLocalNotification(
        title: '🏆 Subiste de nível!',
        body: 'Chegaste ao nível $currentLevel. Continua assim!',
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'_notifState.lastLevel': currentLevel});
    }
  }
}

Future<void> _runCheckDispositivos(
  Map<String, dynamic> data,
  Map<String, dynamic> settings,
  String uid,
) async {
  if (settings['deviceOffline'] != true) return;

  final devicesSnap = await FirebaseFirestore.instance
      .collection('devices')
      .where('userId', isEqualTo: uid)
      .get();

  // Estado anterior guardado no Firestore (necessário porque o WorkManager
  // não tem memória entre execuções)
  final lastStates =
      (data['_notifState']?['deviceStates'] as Map?)
          ?.cast<String, bool>() ??
      {};

  final newStates = <String, bool>{};

  for (final doc in devicesSnap.docs) {
    final deviceData = doc.data();
    final deviceId = doc.id;
    final isOnline = deviceData['online'] == true;
    final deviceName = (deviceData['name'] as String?) ?? 'Dispositivo';

    newStates[deviceId] = isOnline;

    // Só notifica se tinha estado online antes e agora está offline
    final wasOnline = lastStates[deviceId];
    if (wasOnline == true && !isOnline) {
      await NotificationService.showLocalNotification(
        title: '⚠️ Dispositivo offline',
        body: '$deviceName ficou sem ligação.',
      );
    }
  }

  // Persiste o novo estado no Firestore
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .update({'_notifState.deviceStates': newStates});
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: horário silencioso (duplicado aqui pois o isolate não partilha memória)
// ─────────────────────────────────────────────────────────────────────────────

bool _isQuietHours(Map<String, dynamic> settings) {
  final quiet =
      (settings['quietHours'] as Map?)?.cast<String, dynamic>() ?? {};
  if (quiet['enabled'] != true) return false;

  final startStr = (quiet['start'] as String?) ?? '22:00';
  final endStr = (quiet['end'] as String?) ?? '07:00';

  final now = DateTime.now();
  final current = now.hour * 60 + now.minute;

  final startParts = startStr.split(':');
  final endParts = endStr.split(':');

  final start = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
  final end = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

  if (start > end) {
    return current >= start || current <= end;
  }
  return current >= start && current <= end;
}
