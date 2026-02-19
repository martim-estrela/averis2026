import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ShellyService {
  static const double kwhPrice = 0.22; // €/kWh

  // Lê consumo atual do Shelly e guarda no Firestore
  static Future<Map<String, dynamic>?> readAndStore(
    String deviceIp,
    String deviceId,
    String userId,
  ) async {
    try {
      // 1. Lê status do Shelly
      final statusUrl = Uri.parse('http://$deviceIp/status');
      final statusResponse = await http
          .get(statusUrl)
          .timeout(const Duration(seconds: 5));

      if (statusResponse.statusCode != 200) return null;

      final statusData = json.decode(statusResponse.body);
      final meters = statusData['meters'] as List?;

      if (meters == null || meters.isEmpty) return null;

      final meter = meters[0];
      final powerW = (meter['power'] ?? 0).toDouble();
      final totalKwh =
          (meter['total'] ?? 0).toDouble() / 1000; // Shelly dá em Wh

      // 2. Guarda no Firestore (subcoleção readings)
      final readingRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .doc(deviceId)
          .collection('readings')
          .doc(DateTime.now().millisecondsSinceEpoch.toString());

      await readingRef.set({
        'powerW': powerW,
        'totalKwh': totalKwh,
        'voltage': meter['voltage'] ?? 0.0,
        'timestamp': FieldValue.serverTimestamp(),
        'custoDia': totalKwh * kwhPrice,
      });

      return {
        'powerW': powerW,
        'totalKwh': totalKwh,
        'voltage': meter['voltage'] ?? 0.0,
      };
    } catch (e) {
      print('Erro Shelly $deviceIp: $e');
      return null;
    }
  }

  // Liga/desliga Shelly
  static Future<bool> toggle(String deviceIp, bool turnOn) async {
    try {
      final url = Uri.parse(
        'http://$deviceIp/relay/0?turn=${turnOn ? "on" : "off"}',
      );
      final response = await http.get(url);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
