import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class SmartPlugService {
  static const double kwhPrice = 0.22; // €/kWh

  // Toggle multi-marca
  static Future<bool> toggle(
    String deviceIp,
    String deviceType,
    bool turnOn,
  ) async {
    try {
      switch (deviceType.toLowerCase()) {
        case 'shelly':
        case 'shelly-plug': // ← garante que o tipo gravado no Firestore também apanha aqui
          return await _toggleShelly(deviceIp, turnOn);
        case 'tplink':
          return await _toggleTPLink(deviceIp, turnOn);
        case 'sonoff':
          return await _toggleSonoff(deviceIp, turnOn);
        case 'tuya':
          return await _toggleTuya(deviceIp, turnOn);
        default:
          // Fallback para Shelly (mais comum)
          return await _toggleShelly(deviceIp, turnOn);
      }
    } catch (e) {
      print('Erro toggle $deviceType $deviceIp: $e');
      return false;
    }
  }

  // Lê consumo multi-marca
  static Future<Map<String, dynamic>?> readAndStore(
    String deviceIp,
    String deviceId,
    String userId,
    String deviceType,
  ) async {
    try {
      switch (deviceType.toLowerCase()) {
        case 'shelly':
        case 'shelly-plug':
          return await _readShellyAndStore(deviceIp, deviceId, userId);
        case 'tplink':
          return await _readTPLinkAndStore(deviceIp, deviceId, userId);
        default:
          // fallback Shelly
          return await _readShellyAndStore(deviceIp, deviceId, userId);
      }
    } catch (e) {
      print('Erro reading $deviceType $deviceIp: $e');
      return null;
    }
  }

  // === SHELLY ===
  static Future<bool> _toggleShelly(String ip, bool turnOn) async {
    final url = Uri.parse('http://$ip/relay/0?turn=${turnOn ? "on" : "off"}');
    final response = await http.get(url);
    return response.statusCode == 200;
  }

  static Future<Map<String, dynamic>?> _readShellyAndStore(
    String ip,
    String deviceId,
    String userId,
  ) async {
    final meterUrl = Uri.parse('http://$ip/meter/0');
    final response = await http
        .get(meterUrl)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return null;

    final data = json.decode(response.body) as Map<String, dynamic>;

    // Para /meter/0 o formato é diferente:
    final powerW = (data['0']['power'] ?? 0).toDouble();
    final totalKwh = (data['0']['total'] ?? 0).toDouble() / 1000;
    final voltage = (data['0']['voltage'] ?? 0).toDouble();

    await _saveReading(deviceId, userId, powerW, totalKwh, voltage);

    return {'powerW': powerW, 'totalKwh': totalKwh, 'voltage': voltage};
  }

  // === TP-LINK ===
  static Future<bool> _toggleTPLink(String ip, bool turnOn) async {
    final url = Uri.parse(
      'http://$ip/lighting_set.htm?switch=${turnOn ? 1 : 0}',
    );
    final response = await http.get(url);
    return response.statusCode == 200;
  }

  static Future<Map<String, dynamic>?> _readTPLinkAndStore(
    String ip,
    String deviceId,
    String userId,
  ) async {
    final url = Uri.parse('http://$ip/report');
    final response = await http.get(url).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return null;

    final data = json.decode(response.body) as Map<String, dynamic>;
    final emeter =
        (data['emeter'] as Map<String, dynamic>?)?['get_realtime']
            as Map<String, dynamic>? ??
        {};
    final powerW = (emeter['power'] ?? 0).toDouble();
    final totalKwh = (emeter['total'] ?? 0).toDouble();

    await _saveReading(deviceId, userId, powerW, totalKwh, 230.0);

    return {'powerW': powerW, 'totalKwh': totalKwh, 'voltage': 230.0};
  }

  // === SONOFF ===
  static Future<bool> _toggleSonoff(String ip, bool turnOn) async {
    final url = Uri.parse('http://$ip/relay/1?turn=${turnOn ? "on" : "off"}');
    final response = await http.get(url);
    return response.statusCode == 200;
  }

  // === TUYA ===
  static Future<bool> _toggleTuya(String ip, bool turnOn) async {
    // Tuya API mais complexa (futura implementação)
    return await _toggleShelly(ip, turnOn); // fallback
  }

  // Salva reading no Firestore (universal)
  static Future<void> _saveReading(
    String deviceId,
    String userId,
    double powerW,
    double totalKwh,
    double voltage,
  ) async {
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
      'voltage': voltage,
      'timestamp': FieldValue.serverTimestamp(),
      'custoDia': totalKwh * kwhPrice,
    });
  }
}
