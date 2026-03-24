import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:http/http.dart' as http;

class AutoDetectPage extends StatefulWidget {
  const AutoDetectPage({super.key});

  @override
  State<AutoDetectPage> createState() => _AutoDetectPageState();
}

class _AutoDetectPageState extends State<AutoDetectPage> {
  final List<SmartPlugDevice> _foundDevices = [];
  bool _isScanning = false;
  int _scanned = 0; // progresso para a barra
  static const int _totalIps = 254;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Procurar Smart Plugs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade400, Colors.blue.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ✅ Barra de progresso real durante o scan
            LinearProgressIndicator(
              value: _isScanning ? (_scanned / _totalIps).clamp(0.0, 1.0) : 0,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            ),
            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Icon(Icons.wifi_find, size: 64, color: Colors.blue.shade600),
                  const SizedBox(height: 16),
                  Text(
                    'Procurar na rede',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isScanning
                        ? 'A verificar $_scanned de $_totalIps endereços...'
                        : 'A app vai escanear a tua rede Wi-Fi à procura de Smart Plugs',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _scanNetwork,
                icon: _isScanning
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(_isScanning ? 'Escaneando...' : 'Explorar Rede'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            Expanded(
              child: _foundDevices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.electrical_services_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Sem dispositivos encontrados',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: Text(
                              'Toca em "Explorar Rede" para procurar Smart '
                              'Plugs na tua rede Wi-Fi local.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green.shade600,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${_foundDevices.length} dispositivo(s) encontrado(s)',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _foundDevices.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final device = _foundDevices[index];
                              return Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(20),
                                  leading: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.blue.shade100,
                                          Colors.blue.shade200,
                                        ],
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.outlet,
                                      color: Colors.blue.shade700,
                                      size: 28,
                                    ),
                                  ),
                                  title: Text(
                                    device.name,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    'IP: ${device.ip}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  trailing: ElevatedButton.icon(
                                    onPressed: () => _selectDevice(device),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Selecionar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade600,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanNetwork() async {
    setState(() {
      _isScanning = true;
      _scanned = 0;
      _foundDevices.clear();
    });

    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();

      if (wifiIP == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Liga o Wi-Fi primeiro!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final baseIP = wifiIP.substring(0, wifiIP.lastIndexOf('.'));

      // ✅ Timeout global de 30 segundos para o scan completo
      final foundDevices = <SmartPlugDevice>[];

      await Future.wait(
        List.generate(_totalIps, (i) async {
          final testIP = '$baseIP.${i + 1}';
          final device = await _testSmartPlug(testIP);
          if (mounted) setState(() => _scanned++);
          if (device != null) foundDevices.add(device);
        }),
      );

      if (mounted) {
        setState(() => _foundDevices.addAll(foundDevices));

        if (foundDevices.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhum Smart Plug encontrado na rede'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro no scan: $e')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<SmartPlugDevice?> _testSmartPlug(String ip) async {
    // ✅ Timeout curto por IP — o timeout global é 30s
    const timeout = Duration(milliseconds: 800);

    final endpoints = [
      ('http://$ip/rpc/Shelly.GetDeviceInfo', 'shelly'),
      ('http://$ip/rpc/Shelly.GetStatus', 'shelly'),
      ('http://$ip/status', 'shelly'),
      ('http://$ip/api/system/get_sysinfo', 'tplink'),
    ];

    for (final (endpoint, _) in endpoints) {
      try {
        final res = await http.get(Uri.parse(endpoint)).timeout(timeout);

        if (res.statusCode == 200) {
          final body = res.body.toLowerCase();

          if (body.contains('shelly') ||
              body.contains('restart_required') ||
              body.contains('switch:0')) {
            return SmartPlugDevice(
              ip: ip,
              name: 'Shelly Plug S',
              type: 'shelly-plug',
            );
          }
          if (body.contains('tp-link') || body.contains('kasa')) {
            return SmartPlugDevice(
              ip: ip,
              name: 'TP-Link Kasa',
              type: 'tplink',
            );
          }
          if (body.contains('sonoff') || body.contains('itead')) {
            return SmartPlugDevice(ip: ip, name: 'Sonoff', type: 'sonoff');
          }
        }
      } catch (_) {
        // IP não responde neste endpoint — tenta o próximo
      }
    }
    return null;
  }

  void _selectDevice(SmartPlugDevice device) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context, device);
    }
  }
}

class SmartPlugDevice {
  final String ip;
  final String name;
  final String type;

  const SmartPlugDevice({
    required this.ip,
    required this.name,
    required this.type,
  });
}
