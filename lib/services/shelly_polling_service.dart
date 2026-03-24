import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'shelly_api.dart';
import 'user_service.dart';

class ShellyPollingService {
  ShellyPollingService._();

  static Timer? _timer;
  static const _interval = Duration(seconds: 30);

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

    try {
      final metrics = await ShellyApi.getMetrics(ip);

      // ✅ Passa uid para saveReading
      await UserService.saveReading(
        uid: uid,
        deviceId: deviceId,
        powerW: metrics.powerW,
        voltageV: metrics.voltageV,
        currentMa: metrics.currentMa,
        frequencyHz: metrics.frequencyHz,
        totalWh: metrics.totalWh,
      );

      // ✅ users/{uid}/devices/{deviceId}
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
    } catch (_) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceId)
          .update({'online': false});
    }
  }
}
