import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'shelly_api.dart';

class ReadingsService {
  static Timer? _timer;

  static void startAutoCapture({
    required String userId,
    required List<Map<String, String>> devices, // ← recebe TODOS devices
  }) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      // Grava TODOS os devices de uma vez
      for (final device in devices) {
        try {
          await capture(
            userId: userId,
            deviceId: device['id']!,
            shellyIp: device['ip']!,
          );
        } catch (e) {
          print('Erro ${device['id']}: $e');
        }
      }
    });
  }

  static Future<void> capture({
    required String userId,
    required String deviceId,
    required String shellyIp,
  }) async {
    final metrics = await ShellyApi.getMetrics(shellyIp);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(deviceId)
        .collection('readings')
        .add({
          'powerW': metrics.powerW,
          'voltageV': metrics.voltageV,
          'currentMa': metrics.currentMa,
          'frequencyHz': metrics.frequencyHz,
          'totalWh': metrics.totalWh,
          'totalKwh': metrics.totalKwh,
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  static void stop() => _timer?.cancel();
}
