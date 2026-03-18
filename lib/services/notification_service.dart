import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AVERIS – NotificationService
//
// Responsabilidades:
//   • Inicializar o plugin flutter_local_notifications
//   • Mostrar notificações locais (foreground e background)
//   • Escutar o Firestore em tempo-real (foreground)
//   • Verificar horário silencioso antes de notificar
//
// Uso:
//   1. Chama NotificationService.init() em main.dart após Firebase.initializeApp()
//   2. Chama NotificationService.startListeners(uid) após login
//   3. Chama NotificationService.stopListeners() após logout
// ─────────────────────────────────────────────────────────────────────────────

class NotificationService {
  NotificationService._();

  // ── Plugin ────────────────────────────────────────────────────────────────
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'averis_channel';
  static const _channelName = 'AVERIS Alertas';

  // ── Subscrições ativas ────────────────────────────────────────────────────
  static StreamSubscription<QuerySnapshot>? _devicesSub;
  static StreamSubscription<DocumentSnapshot>? _userSub;

  // Estado anterior dos dispositivos (para detetar online → offline)
  static final Map<String, bool> _deviceOnlineState = {};

  // Guarda o último nível XP conhecido para detetar subida
  static int? _lastKnownLevel;

  // Guarda se a meta estava atingida para evitar notificações repetidas
  static bool? _lastGoalState;

  // ── Inicialização ─────────────────────────────────────────────────────────

  /// Deve ser chamado uma vez em main.dart, após Firebase.initializeApp().
  static Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // Pede permissão no Android 13+ (API 33+)
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Cria o canal de notificações no Android
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Alertas do sistema AVERIS',
            importance: Importance.high,
          ),
        );
  }

  // ── Listeners em tempo-real (foreground) ──────────────────────────────────

  /// Inicia os listeners do Firestore.
  /// Chama após o utilizador fazer login.
  static void startListeners(String uid) {
    stopListeners(); // garante que não há duplicados

    _listenDevices(uid);
    _listenUserDoc(uid);
  }

  /// Para todos os listeners.
  /// Chama quando o utilizador faz logout.
  static void stopListeners() {
    _devicesSub?.cancel();
    _devicesSub = null;
    _userSub?.cancel();
    _userSub = null;
    _deviceOnlineState.clear();
    _lastKnownLevel = null;
    _lastGoalState = null;
  }

  // ── Listener: dispositivos offline ────────────────────────────────────────

  static void _listenDevices(String uid) {
    _devicesSub = FirebaseFirestore.instance
        .collection('devices')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snap) async {
      // Lê as definições atuais do utilizador
      final settings = await _getNotifSettings(uid);
      if (settings['deviceOffline'] != true) return;
      if (_isQuietHours(settings)) return;

      for (final change in snap.docChanges) {
        final deviceId = change.doc.id;
        final data = change.doc.data();
        if (data == null) continue;

        final isOnline = data['online'] == true;
        final deviceName = (data['name'] as String?) ?? 'Dispositivo';

        // Inicializa o estado na primeira leitura (sem notificar)
        if (!_deviceOnlineState.containsKey(deviceId)) {
          _deviceOnlineState[deviceId] = isOnline;
          continue;
        }

        final wasOnline = _deviceOnlineState[deviceId]!;

        // Só notifica na transição online → offline
        if (wasOnline && !isOnline) {
          await showLocalNotification(
            title: '⚠️ Dispositivo offline',
            body: '$deviceName ficou sem ligação.',
          );
        }

        _deviceOnlineState[deviceId] = isOnline;
      }
    });
  }

  // ── Listener: consumo, meta e nível XP ───────────────────────────────────

  static void _listenUserDoc(String uid) {
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) async {
      if (!snap.exists) return;
      final data = (snap.data() as Map?)?.cast<String, dynamic>() ?? {};
      final notifSettings =
          (data['settings']?['notifications'] as Map?)
              ?.cast<String, dynamic>() ??
          {};

      if (_isQuietHours(notifSettings)) return;

      await _checkHighConsumption(data, notifSettings);
      await _checkGoalReached(data, notifSettings);
      await _checkLevelUp(data, notifSettings);
    });
  }

  // ── Verificação: consumo elevado ──────────────────────────────────────────

  static Future<void> _checkHighConsumption(
    Map<String, dynamic> data,
    Map<String, dynamic> settings,
  ) async {
    if (settings['highConsumption'] != true) return;

    // Ajusta o campo ao nome real que usas no Firestore
    final consumoHoje = (data['consumoHoje'] as num?)?.toDouble() ?? 0;
    final limite =
        (data['settings']?['consumoLimiteDiario'] as num?)?.toDouble() ?? 10.0;

    if (consumoHoje > limite) {
      await showLocalNotification(
        title: '⚡ Consumo elevado',
        body:
            'Já consumiste ${consumoHoje.toStringAsFixed(1)} kWh hoje '
            '(limite: ${limite.toStringAsFixed(1)} kWh).',
      );
    }
  }

  // ── Verificação: meta de poupança ─────────────────────────────────────────

  static Future<void> _checkGoalReached(
    Map<String, dynamic> data,
    Map<String, dynamic> settings,
  ) async {
    if (settings['goalReached'] != true) return;

    // Ajusta o campo ao nome real que usas no Firestore
    final goalReached = data['meta']?['atingida'] == true;

    // Só notifica na transição false → true
    if (goalReached && _lastGoalState == false) {
      await showLocalNotification(
        title: '🎯 Meta atingida!',
        body: 'Parabéns! Atingiste a tua meta de poupança de energia.',
      );
    }

    _lastGoalState = goalReached;
  }

  // ── Verificação: subida de nível XP ──────────────────────────────────────

  static Future<void> _checkLevelUp(
    Map<String, dynamic> data,
    Map<String, dynamic> settings,
  ) async {
    if (settings['levelUp'] != true) return;

    // Ajusta o campo ao nome real que usas no Firestore
    final level = (data['xp']?['nivel'] as num?)?.toInt() ?? 1;

    if (_lastKnownLevel != null && level > _lastKnownLevel!) {
      await showLocalNotification(
        title: '🏆 Subiste de nível!',
        body: 'Chegaste ao nível $level. Continua assim!',
      );
    }

    _lastKnownLevel = level;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Lê apenas o sub-mapa de notificações para não carregar o doc inteiro
  /// quando já temos o doc no listener (método auxiliar para os outros contextos).
  static Future<Map<String, dynamic>> _getNotifSettings(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = (snap.data() as Map?)?.cast<String, dynamic>() ?? {};
    return (data['settings']?['notifications'] as Map?)
            ?.cast<String, dynamic>() ??
        {};
  }

  /// Verifica se estamos dentro do horário silencioso.
  static bool _isQuietHours(Map<String, dynamic> settings) {
    final quiet =
        (settings['quietHours'] as Map?)?.cast<String, dynamic>() ?? {};
    if (quiet['enabled'] != true) return false;

    final startStr = (quiet['start'] as String?) ?? '22:00';
    final endStr = (quiet['end'] as String?) ?? '07:00';

    final now = DateTime.now();
    final current = now.hour * 60 + now.minute;

    final startParts = startStr.split(':');
    final endParts = endStr.split(':');

    final start =
        int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final end = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

    // Trata períodos que passam a meia-noite (ex: 22:00 → 07:00)
    if (start > end) {
      return current >= start || current <= end;
    }
    return current >= start && current <= end;
  }

  // ── Mostrar notificação local ─────────────────────────────────────────────

  /// Pode ser chamado de qualquer lado, incluindo do WorkManager (background).
  static Future<void> showLocalNotification({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      // ID único baseado no tempo para evitar substituição de notificações
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
