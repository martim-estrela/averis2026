import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'shelly_cloud_service.dart';

class SmartPlugService {
  SmartPlugService._();

  /// Toggle on/off com fallback para Shelly Cloud se a rede local falhar.
  static Future<bool> toggle(
    String uid,
    String deviceId,
    String deviceIp,
    String deviceType,
    bool turnOn, {
    String? cloudServerUri,
    String? cloudAuthKey,
    String? shellyCloudId,
  }) async {
    try {
      bool success = false;

      // 1. Tentar rede local
      try {
        switch (deviceType.toLowerCase()) {
          case 'shelly':
          case 'shelly-plug':
            success = await _toggleShelly(deviceIp, turnOn);
            break;
          case 'tplink':
            success = await _toggleTPLink(deviceIp, turnOn);
            break;
          case 'sonoff':
            success = await _toggleSonoff(deviceIp, turnOn);
            break;
          default:
            success = await _toggleShelly(deviceIp, turnOn);
        }
      } catch (_) {
        // local falhou — tentar cloud
      }

      // 2. Fallback para Shelly Cloud
      if (!success &&
          cloudServerUri != null &&
          cloudAuthKey != null &&
          shellyCloudId != null) {
        success = await ShellyCloudService.setRelay(
            cloudServerUri, cloudAuthKey, shellyCloudId, turnOn);
      }

      if (success) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('devices')
            .doc(deviceId)
            .update({
          'status': turnOn ? 'on' : 'off',
          'online': true,
          'lastSeenAt': FieldValue.serverTimestamp(),
        });
      }

      return success;
    } catch (_) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceId)
          .update({'online': false});
      return false;
    }
  }

  static Future<bool> _toggleShelly(String ip, bool turnOn) async {
    final uri = Uri.parse(
        'http://$ip/rpc/Switch.Set?id=0&on=${turnOn ? 'true' : 'false'}');
    final res = await http.get(uri).timeout(const Duration(seconds: 4));
    return res.statusCode == 200;
  }

  static Future<bool> _toggleTPLink(String ip, bool turnOn) async {
    final uri = Uri.parse(
        'http://$ip/lighting_set.htm?switch=${turnOn ? 1 : 0}');
    final res = await http.get(uri).timeout(const Duration(seconds: 4));
    return res.statusCode == 200;
  }

  static Future<bool> _toggleSonoff(String ip, bool turnOn) async {
    final uri = Uri.parse(
        'http://$ip/relay/1?turn=${turnOn ? 'on' : 'off'}');
    final res = await http.get(uri).timeout(const Duration(seconds: 4));
    return res.statusCode == 200;
  }
}
