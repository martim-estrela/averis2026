import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// AVERIS – ShellyApi
//
// Suporta Shelly Gen 2 e Gen 3 (mesma API RPC).
// Endpoint: /rpc/Switch.GetStatus?id=0
//
// Estrutura da resposta do Gen 3:
// {
//   "id": 0,
//   "source": "timer",
//   "output": true,
//   "apower": 120.5,       ← potência ativa (W)
//   "voltage": 229.8,      ← tensão (V)
//   "current": 0.524,      ← corrente (A)
//   "pfreq": 50.0,         ← frequência (Hz)
//   "aenergy": {
//     "total": 14320.0,    ← ✅ energia total (Wh) — campo ANINHADO
//     "by_minute": [...],
//     "minute_ts": ...
//   }
// }
// ─────────────────────────────────────────────────────────────────────────────

class ShellyApi {
  /// Liga ou desliga o relay do Shelly Gen 2/3.
  static Future<void> setRelay(String ip, bool on) async {
    final uri = Uri.parse(
      'http://$ip/rpc/Switch.Set?id=0&on=${on ? 'true' : 'false'}',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) throw Exception('Falha Shelly ($ip)');
  }

  /// Lê as métricas de consumo do Shelly Gen 2/3.
  static Future<ShellyMetrics> getMetrics(String ip) async {
    final uri = Uri.parse('http://$ip/rpc/Switch.GetStatus?id=0');
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return ShellyMetrics.empty();

    final data = jsonDecode(res.body) as Map<String, dynamic>;

    // ✅ aenergy.total — campo aninhado no Gen 2 e Gen 3
    final aenergy = data['aenergy'] as Map<String, dynamic>?;
    final totalWh = (aenergy?['total'] as num?)?.toDouble() ?? 0.0;

    return ShellyMetrics(
      powerW: (data['apower'] as num?)?.toDouble() ?? 0.0,
      voltageV: (data['voltage'] as num?)?.toDouble() ?? 230.0,
      currentA: (data['current'] as num?)?.toDouble() ?? 0.0,
      frequencyHz: (data['pfreq'] as num?)?.toDouble() ?? 50.0,
      totalWh: totalWh,
      isOn: data['output'] == true,
    );
  }

  /// Verifica se o Shelly está acessível na rede.
  static Future<bool> isReachable(String ip) async {
    try {
      final uri = Uri.parse('http://$ip/rpc/Shelly.GetDeviceInfo');
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ShellyMetrics — modelo de dados de uma leitura
// ─────────────────────────────────────────────────────────────────────────────

class ShellyMetrics {
  final double powerW;
  final double voltageV;
  final double currentA;
  final double frequencyHz;
  final double totalWh;
  final bool isOn;

  const ShellyMetrics({
    required this.powerW,
    required this.voltageV,
    required this.currentA,
    required this.frequencyHz,
    required this.totalWh,
    required this.isOn,
  });

  factory ShellyMetrics.empty() => const ShellyMetrics(
    powerW: 0,
    voltageV: 230,
    currentA: 0,
    frequencyHz: 50,
    totalWh: 0,
    isOn: false,
  );

  double get currentMa => currentA * 1000;
  double get totalKwh => totalWh / 1000;
}
