import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';

IOClient _shellyClient() {
  final httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..badCertificateCallback = (_, _, _) => true;
  return IOClient(httpClient);
}

class ShellyProvisioningService {
  static const String _apIp = '192.168.33.1';

  /// GET /rpc/Shelly.GetDeviceInfo — chamado enquanto ligado ao AP do Shelly
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final client = _shellyClient();
    try {
      final res = await client
          .get(Uri.parse('http://$_apIp/rpc/Shelly.GetDeviceInfo'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw Exception('O Shelly não respondeu (${res.statusCode}).');
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  /// POST /rpc/WiFi.SetConfig — envia as credenciais WiFi da casa
  static Future<void> setWifiConfig({
    required String ssid,
    required String password,
  }) async {
    final client = _shellyClient();
    try {
      final body = jsonEncode({
        'config': {
          'sta': {'ssid': ssid, 'pass': password, 'enable': true},
        },
      });
      final res = await client
          .post(
            Uri.parse('http://$_apIp/rpc/WiFi.SetConfig'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw Exception('Falha ao enviar configuração WiFi (${res.statusCode}).');
      }
    } finally {
      client.close();
    }
  }

  /// GET /rpc/Shelly.Reboot — reinicia; timeout normal porque o Shelly desaparece
  static Future<void> reboot() async {
    final client = _shellyClient();
    try {
      await client
          .get(Uri.parse('http://$_apIp/rpc/Shelly.Reboot'))
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // É normal dar timeout — o Shelly está a reiniciar
    } finally {
      client.close();
    }
  }

  /// Scan paralelo da subnet para encontrar o Shelly depois do reboot
  static Future<String?> discoverShellyIp({
    required String subnet,
    String? expectedMac,
  }) async {
    const batchSize = 30;
    for (int start = 1; start <= 254; start += batchSize) {
      final end = (start + batchSize - 1).clamp(1, 254);
      final futures = List.generate(end - start + 1, (i) async {
        final ip = '$subnet.${start + i}';
        final client = _shellyClient();
        try {
          final res = await client
              .get(Uri.parse('http://$ip/rpc/Shelly.GetDeviceInfo'))
              .timeout(const Duration(milliseconds: 900));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            if (expectedMac == null) return ip;
            final found = (data['mac'] as String? ?? '')
                .replaceAll(RegExp(r'[^a-fA-F0-9]'), '')
                .toUpperCase();
            if (found == expectedMac) return ip;
          }
        } catch (_) {
        } finally {
          client.close();
        }
        return null;
      });
      final results = await Future.wait(futures);
      final found = results.firstWhere((r) => r != null, orElse: () => null);
      if (found != null) return found;
    }
    return null;
  }
}
