import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AVERIS – NotificationService
//
// Responsabilidades:
//   • Inicializar o plugin flutter_local_notifications
//   • Registar o handler FCM para background/terminated
//   • Mostrar notificações locais quando a app está em foreground
//
// Uso:
//   1. Chama NotificationService.init() em main.dart após Firebase.initializeApp()
//   As notificações em background/terminated são tratadas automaticamente pelo FCM.
// ─────────────────────────────────────────────────────────────────────────────

// ⚠️ Top-level — obrigatório para o FCM conseguir invocar em isolate separado
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  // O FCM mostra a notificação automaticamente em background/terminated.
  // Este handler existe apenas para processar mensagens de dados (data-only)
  // se necessário no futuro.
}

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'averis_channel';
  static const _channelName = 'AVERIS Alertas';

  // ── Inicialização ─────────────────────────────────────────────────────────

  /// Deve ser chamado uma vez em main.dart, após Firebase.initializeApp().
  static Future<void> init() async {
    // Regista o handler para mensagens FCM recebidas com app em background/terminated
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

    // Pede permissão FCM (iOS + Android 13+)
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Inicializa o plugin de notificações locais (usado em foreground)
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Cria o canal de notificações no Android (necessário para Android 8+)
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Alertas do sistema AVERIS',
            importance: Importance.high,
          ),
        );

    // Quando a app está em foreground, o FCM não mostra a notificação
    // automaticamente — fazemo-lo nós via flutter_local_notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        showLocalNotification(
          title: notification.title ?? 'AVERIS',
          body: notification.body ?? '',
        );
      }
    });
  }

  // ── Mostrar notificação local ─────────────────────────────────────────────

  /// Apresenta uma notificação local imediata.
  /// Usado para mensagens FCM recebidas em foreground.
  static Future<void> showLocalNotification({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
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
