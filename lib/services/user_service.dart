import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DeviceAlreadyExistsException implements Exception {
  final String existingDeviceId;
  DeviceAlreadyExistsException(this.existingDeviceId);

  @override
  String toString() => 'Dispositivo já existe (id: $existingDeviceId)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AVERIS – UserService
//
// Estrutura Firestore:
//   users/{uid}/
//     devices/{deviceId}/
//       readings/{readingId}
//       dailyStats/{YYYY-MM-DD}
// ─────────────────────────────────────────────────────────────────────────────

class UserService {
  UserService._();

  static final _db = FirebaseFirestore.instance;

  // ── Referências base ──────────────────────────────────────────────────────

  static DocumentReference _userRef(String uid) =>
      _db.collection('users').doc(uid);

  static CollectionReference _devicesRef(String uid) =>
      _userRef(uid).collection('devices');

  static DocumentReference _deviceRef(String uid, String deviceId) =>
      _devicesRef(uid).doc(deviceId);

  // ── Criar utilizador após registo ─────────────────────────────────────────

  static Future<void> initUser(User user, {String? displayName}) async {
    await _userRef(user.uid).set(
      _buildUserDocument(user, displayName: displayName),
      SetOptions(merge: true),
    );
  }

  static Future<void> ensureUserExists(User user) async {
    final snap = await _userRef(user.uid).get();
    if (!snap.exists) {
      await _userRef(user.uid).set(_buildUserDocument(user));
    }
    // Se o documento já existe não toca em nada — impede reset de pontos/nível.
  }

  // ── Estrutura do documento do utilizador ─────────────────────────────────

  static Map<String, dynamic> _buildUserDocument(User user,
      {String? displayName}) {
    return {
      'name': displayName ?? user.displayName ?? '',
      'email': user.email ?? '',
      'photoUrl': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
      'nivel': 1,
      'pontos': 0,
      'pontosTotal': 0,
      'consumoMes': 0.0,
      'goals': {
        'monthlyKwhTarget': 0.0,
        'monthlyCostTarget': 0.0,
        'focus': 'cost',
      },
      'achievements': {
        'firstSaving': false,
        'streak3Days': false,
        'sevenDaysBelowAverage': false,
        'reachedLevel3': false,
        'savedInWeekend': false,
        'reachedLevel5': false,
      },
      'privacy': {'shareAnonymous': false},
      'settings': {
        'energyPrice': 0.22,
        'includeTax': true,
        'energyContract': {
          'tipo': 'simples',
          'precos': {'simples': 0.2134},
        },
        'notifications': {
          'deviceOffline': true,
          'highConsumption': true,
          'goalReached': true,
          'levelUp': true,
          'quietHours': {
            'enabled': false,
            'start': '22:00',
            'end': '07:00',
          },
        },
        'automations': {
          'turnAllOffAtMidnight': false,
          'weekdayMorningOn': {
            'enabled': false,
            'time': '07:00',
            'deviceIds': [],
          },
        },
      },
      '_notifState': {
        'lastGoal': false,
        'lastLevel': 1,
        'deviceStates': {},
      },
    };
  }

  // ── Criar dispositivo ─────────────────────────────────────────────────────

  /// Verifica se já existe dispositivo com o mesmo MAC ou IP.
  /// Retorna o deviceId existente, ou null se não existir.
  static Future<String?> findExistingDevice({
    required String uid,
    required String ip,
    String mac = '',
  }) async {
    final snap = await _devicesRef(uid).get();
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final existingMac = data['mac'] as String? ?? '';
      final existingIp = data['ip'] as String? ?? '';
      if (mac.isNotEmpty && existingMac == mac) return doc.id;
      if (existingIp == ip) return doc.id;
    }
    return null;
  }

  /// Cria um novo dispositivo em users/{uid}/devices/{deviceId}.
  /// Lança [DeviceAlreadyExistsException] se já existir dispositivo com o mesmo IP ou MAC.
  static Future<String> addDevice({
    required String uid,
    required String name,
    required String ip,
    String mac = '',
    String type = 'shelly-plug',
    bool online = false,
    String? iconColor,
  }) async {
    final existing = await findExistingDevice(uid: uid, ip: ip, mac: mac);
    if (existing != null) {
      throw DeviceAlreadyExistsException(existing);
    }

    final devRef = _devicesRef(uid).doc();

    final data = <String, dynamic>{
      'name': name,
      'ip': ip,
      'mac': mac,
      'status': 'off',
      'type': type,
      'online': online,
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeenAt': online ? FieldValue.serverTimestamp() : null,
      'lastMetrics': {
        'powerW': 0.0,
        'totalKwh': 0.0,
        'voltageV': 0.0,
        'currentMa': 0.0,
        'timestamp': FieldValue.serverTimestamp(),
      },
    };
    if (iconColor != null) data['iconColor'] = iconColor;

    await devRef.set(data);

    return devRef.id;
  }

  /// Atualiza o IP de um dispositivo existente e marca-o como online.
  static Future<void> updateDeviceIp({
    required String uid,
    required String deviceId,
    required String ip,
  }) async {
    await _deviceRef(uid, deviceId).update({
      'ip': ip,
      'online': true,
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Gravar leitura do dispositivo ─────────────────────────────────────────

  /// Grava uma leitura e atualiza lastMetrics + dailyStats.
  /// Requer uid para construir o caminho users/{uid}/devices/{deviceId}
  static Future<void> saveReading({
    required String uid,
    required String deviceId,
    required double powerW,
    required double voltageV,
    required double currentMa,
    required double frequencyHz,
    required double totalWh,
  }) async {
    final totalKwh = totalWh / 1000;
    final now = FieldValue.serverTimestamp();
    final devRef = _deviceRef(uid, deviceId);
    final batch = _db.batch();

    // Nova leitura na subcoleção
    batch.set(devRef.collection('readings').doc(), {
      'powerW': powerW,
      'voltageV': voltageV,
      'currentMa': currentMa,
      'frequencyHz': frequencyHz,
      'totalWh': totalWh,
      'totalKwh': totalKwh,
      'timestamp': now,
    });

    // Atualiza lastMetrics e online
    batch.update(devRef, {
      'online': true,
      'lastSeenAt': now,
      'lastMetrics.powerW': powerW,
      'lastMetrics.totalKwh': totalKwh,
      'lastMetrics.voltageV': voltageV,
      'lastMetrics.currentMa': currentMa,
      'lastMetrics.timestamp': now,
    });

    await batch.commit();

    // Atualiza estatísticas diárias (transação separada)
    await _updateDailyStats(uid: uid, deviceId: deviceId, powerW: powerW);
  }

  // ── Estatísticas diárias ──────────────────────────────────────────────────

  static Future<void> _updateDailyStats({
    required String uid,
    required String deviceId,
    required double powerW,
  }) async {
    final today = _todayKey();
    final statRef = _deviceRef(uid, deviceId).collection('dailyStats').doc(today);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(statRef);

      if (!snap.exists) {
        tx.set(statRef, {
          'sumPowerW': powerW,
          'count': 1,
          'avgPowerW': powerW,
          'peakPowerW': powerW,
          'estimatedKwh': 0.0,
          'estimatedCost': 0.0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final data = snap.data()!;
        final newSum = (data['sumPowerW'] as num).toDouble() + powerW;
        final newCount = (data['count'] as num).toInt() + 1;
        final newAvg = newSum / newCount;
        final currentPeak = (data['peakPowerW'] as num).toDouble();

        tx.update(statRef, {
          'sumPowerW': newSum,
          'count': newCount,
          'avgPowerW': newAvg,
          'peakPowerW': powerW > currentPeak ? powerW : currentPeak,
          'estimatedKwh': newAvg * (newCount / 120),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
