import 'dart:convert';
import 'package:http/http.dart' as http;

class ShellyApi {
  // Gen1 (Shelly Plug S) – controlar relé
  static Future<void> setRelay(String ip, bool on) async {
    final uri = Uri.parse('http://$ip/relay/0?turn=${on ? 'on' : 'off'}');
    final res = await http.get(uri).timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) {
      throw Exception('Falha ao controlar Shelly ($ip): ${res.statusCode}');
    }
  }

  static Future<void> toggleRelay(String ip) async {
    final uri = Uri.parse('http://$ip/relay/0?turn=toggle');
    final res = await http.get(uri).timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) {
      throw Exception('Falha ao controlar Shelly ($ip): ${res.statusCode}');
    }
  }

  // Ler potência atual (W) – Gen1 usa /status com campo meters[0].power
  static Future<double> getCurrentPower(String ip) async {
    final uri = Uri.parse('http://$ip/status');
    final res = await http.get(uri).timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) {
      throw Exception('Erro ao obter consumo ($ip): ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final meters = data['meters'] as List<dynamic>?;
    final power = (meters != null && meters.isNotEmpty)
        ? (meters[0]['power'] as num?)?.toDouble() ?? 0.0
        : 0.0;
    return power;
  }
}
