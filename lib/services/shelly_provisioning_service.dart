import 'dart:convert';
import 'package:http/http.dart' as http;

class ShellyProvisioningService {
  static const String _shellyApIp =
      '192.168.33.1'; // IP padrão do AP do Shelly Gen 3

  /// Passo 1: Obter info do dispositivo (quando ligado ao AP do Shelly)
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final uri = Uri.parse('http://$_shellyApIp/rpc/Shelly.GetDeviceInfo');
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('Não foi possível comunicar com o Shelly');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Passo 2: Configurar Wi-Fi da casa no Shelly
  static Future<void> setWifiConfig({
    required String ssid,
    required String password,
  }) async {
    final uri = Uri.parse('http://$_shellyApIp/rpc/WiFi.SetConfig');
    final body = jsonEncode({
      "config": {
        "sta": {"ssid": ssid, "pass": password, "enable": true},
      },
    });

    final res = await http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 5));

    if (res.statusCode != 200) throw Exception('Falha ao configurar Wi-Fi');
  }

  /// Passo 3: Reboot do Shelly
  static Future<void> reboot() async {
    final uri = Uri.parse('http://$_shellyApIp/rpc/Shelly.Reboot');
    await http.get(uri).timeout(const Duration(seconds: 3)).catchError((_) {
      // É normal dar timeout aqui — o Shelly está a reiniciar
    });
  }

  /// Passo 4: Descobrir o novo IP do Shelly na rede (após reboot)
  /// Faz scan de IPs na subnet e testa o /rpc/Shelly.GetDeviceInfo
  static Future<String?> discoverShellyIp({
    required String subnet, // ex: "192.168.1"
    String? expectedMac,
  }) async {
    final futures = List.generate(254, (i) async {
      final ip = '$subnet.${i + 1}';
      try {
        final uri = Uri.parse('http://$ip/rpc/Shelly.GetDeviceInfo');
        final res = await http
            .get(uri)
            .timeout(const Duration(milliseconds: 800));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (expectedMac == null) return ip;
          // Normalizar ambos os MACs antes de comparar (remove separadores, maiúsculas)
          final foundMac = (data['mac'] as String? ?? '')
              .replaceAll(RegExp(r'[^a-fA-F0-9]'), '')
              .toUpperCase();
          if (foundMac == expectedMac) return ip;
        }
      } catch (_) {}
      return null;
    });

    final results = await Future.wait(futures);
    return results.firstWhere((ip) => ip != null, orElse: () => null);
  }
}
