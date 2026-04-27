import 'dart:convert';
import 'package:http/http.dart' as http;
import 'shelly_api.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ShellyCloudService — integração com a Shelly Cloud API v2
//
// Usado como fallback quando o dispositivo não é acessível localmente.
// O utilizador configura o auth_key e o server_uri nas Definições.
//
// Documentação: https://shelly-api-docs.shelly.cloud/cloud-control-api/
// ─────────────────────────────────────────────────────────────────────────────

class ShellyCloudService {
  ShellyCloudService._();

  // POST https://{serverUri}/v2/devices/api/GET?auth_key={key}
  // Body: { "devices": ["{deviceId}"] }
  static Future<ShellyMetrics> getDeviceMetrics(
    String serverUri,
    String authKey,
    String deviceId,
  ) async {
    final uri = Uri.https(
      serverUri,
      '/v2/devices/api/GET',
      {'auth_key': authKey},
    );
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'devices': [deviceId]}),
        )
        .timeout(const Duration(seconds: 8));

    if (res.statusCode != 200) throw Exception('Shelly Cloud HTTP ${res.statusCode}');

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final devicesStatus = (body['data']?['devices_status'] as Map?)
        ?.cast<String, dynamic>();
    final status = devicesStatus?[deviceId] as Map<String, dynamic>?;
    if (status == null) throw Exception('Dispositivo não encontrado na cloud');

    return _parseMetrics(status);
  }

  // POST https://{serverUri}/v2/devices/api/SET/switch?auth_key={key}
  // Body: { "id": "{deviceId}", "channel": 0, "on": true/false }
  static Future<bool> setRelay(
    String serverUri,
    String authKey,
    String deviceId,
    bool on,
  ) async {
    final uri = Uri.https(
      serverUri,
      '/v2/devices/api/SET/switch',
      {'auth_key': authKey},
    );
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'id': deviceId, 'channel': 0, 'on': on}),
        )
        .timeout(const Duration(seconds: 8));

    return res.statusCode == 200;
  }

  // Interpreta a resposta da cloud — suporta Gen 2/3 (switch:0) e Gen 1 (meters[])
  static ShellyMetrics _parseMetrics(Map<String, dynamic> status) {
    // Gen 2 / Gen 3: campo "switch:0"
    final sw = status['switch:0'] as Map<String, dynamic>?;
    if (sw != null) {
      final aenergy = sw['aenergy'] as Map<String, dynamic>?;
      return ShellyMetrics(
        powerW: (sw['apower'] as num?)?.toDouble() ?? 0.0,
        voltageV: (sw['voltage'] as num?)?.toDouble() ?? 230.0,
        currentA: (sw['current'] as num?)?.toDouble() ?? 0.0,
        frequencyHz: (sw['pfreq'] as num?)?.toDouble() ?? 50.0,
        totalWh: (aenergy?['total'] as num?)?.toDouble() ?? 0.0,
        isOn: sw['output'] == true,
      );
    }

    // Gen 1: campo "meters" (array) + "ison"
    final meters = status['meters'] as List?;
    final meter = (meters?.isNotEmpty == true ? meters![0] : null)
        as Map<String, dynamic>?;
    return ShellyMetrics(
      powerW: (meter?['power'] as num?)?.toDouble() ?? 0.0,
      voltageV: 230.0,
      currentA: 0.0,
      frequencyHz: 50.0,
      totalWh: (meter?['total'] as num?)?.toDouble() ?? 0.0,
      isOn: status['ison'] == true,
    );
  }
}
