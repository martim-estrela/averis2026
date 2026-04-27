import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notif_repository.dart';
import 'shelly_api.dart';
import 'user_service.dart';

class ShellyPollingService {
  ShellyPollingService._();

  static Timer? _timer;
  static const _interval = Duration(seconds: 30);
  static final Map<String, bool> _highConsumptionNotified = {};

  static Future<void> start(String uid) async {
    stop();
    await _pollAllDevices(uid);
    _timer = Timer.periodic(_interval, (_) => _pollAllDevices(uid));
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _pollAllDevices(String uid) async {
    // ✅ users/{uid}/devices
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('devices')
        .get();

    await Future.wait(
      snap.docs.map((doc) => _pollDevice(uid, doc.id, doc.data())),
    );
  }

  static Future<void> _pollDevice(
    String uid,
    String deviceId,
    Map<String, dynamic> deviceData,
  ) async {
    final ip = deviceData['ip'] as String?;
    if (ip == null || ip.isEmpty) return;

    final wasOnline = deviceData['online'] == true;
    final deviceName = (deviceData['name'] as String?) ?? 'Dispositivo';

    try {
      final metrics = await ShellyApi.getMetrics(ip);

      await UserService.saveReading(
        uid: uid,
        deviceId: deviceId,
        powerW: metrics.powerW,
        voltageV: metrics.voltageV,
        currentMa: metrics.currentMa,
        frequencyHz: metrics.frequencyHz,
        totalWh: metrics.totalWh,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceId)
          .update({
        'online': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'status': metrics.isOn ? 'on' : 'off',
      });

      if (!wasOnline) {
        await NotifRepository.write(
          uid: uid,
          type: 'device_online',
          title: '$deviceName voltou a estar online',
          body: 'O dispositivo está acessível novamente.',
          metadata: {'deviceId': deviceId},
        );
      }

      if (metrics.powerW > 2000 &&
          _highConsumptionNotified[deviceId] != true) {
        _highConsumptionNotified[deviceId] = true;
        await NotifRepository.write(
          uid: uid,
          type: 'high_consumption',
          title: 'Consumo elevado detetado',
          body:
              '$deviceName está a consumir ${metrics.powerW.toStringAsFixed(0)} W.',
          metadata: {'deviceId': deviceId, 'powerW': metrics.powerW},
        );
      } else if (metrics.powerW <= 2000) {
        _highConsumptionNotified.remove(deviceId);
      }
    } catch (_) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceId)
          .update({'online': false});

      if (wasOnline) {
        await NotifRepository.write(
          uid: uid,
          type: 'device_offline',
          title: '$deviceName ficou offline',
          body: 'Não foi possível contactar o dispositivo.',
          metadata: {'deviceId': deviceId},
        );
      }
    }
  }
}
