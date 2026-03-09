import 'dart:convert';
import 'package:http/http.dart' as http;

class ShellyApi {
  static Future<void> setRelay(String ip, bool on) async {
    final uri = Uri.parse(
      'http://$ip/rpc/Switch.Set?id=0&on=${on ? 'true' : 'false'}',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) throw Exception('Falha Shelly ($ip)');
  }

  static Future<ShellyMetrics> getMetrics(String ip) async {
    final uri = Uri.parse('http://$ip/rpc/Switch.GetStatus?id=0');
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return ShellyMetrics.empty();

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ShellyMetrics(
      powerW: (data['apower'] as num?)?.toDouble() ?? 0.0,
      voltageV: (data['voltage'] as num?)?.toDouble() ?? 230.0,
      currentA: (data['current'] as num?)?.toDouble() ?? 0.0,
      frequencyHz: (data['pfreq'] as num?)?.toDouble() ?? 50.0,
      totalWh: (data['total_energy'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ShellyMetrics {
  final double powerW, voltageV, currentA, frequencyHz, totalWh;

  ShellyMetrics({
    required this.powerW,
    required this.voltageV,
    required this.currentA,
    required this.frequencyHz,
    required this.totalWh,
  });

  factory ShellyMetrics.empty() => ShellyMetrics(
    powerW: 0,
    voltageV: 230,
    currentA: 0,
    frequencyHz: 50,
    totalWh: 0,
  );

  double get currentMa => currentA * 1000;
  double get totalKwh => totalWh / 1000;
}
