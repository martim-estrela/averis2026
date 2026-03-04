import 'dart:convert';
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
            // Barra de progresso
            LinearProgressIndicator(
              value: _isScanning ? null : 0,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            ),
            const SizedBox(height: 24),

            // Título e instruções
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
                    'A app vai escanear a tua rede Wi-Fi à procura de Smart Plugs',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Botão principal
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
                  elevation: 2,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Conteúdo principal
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
                              'Toca em "Explorar Rede" para procurar Smart Plugs na tua rede Wi-Fi local.',
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
                            separatorBuilder: (_, __) =>
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
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
      _foundDevices.clear();
    });

    try {
      // 1. Obtém subnet da rede Wi-Fi
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Escaneando $baseIP.1-254...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // 2. Scan paralelo de toda a sub-rede
      final List<SmartPlugDevice> foundDevices = [];

      await Future.wait(
        List.generate(254, (i) async {
          final testIP = '$baseIP.${i + 1}';
          final smartPlug = await _testSmartPlug(testIP);
          if (smartPlug != null) {
            foundDevices.add(smartPlug);
          }
        }),
        eagerError: true,
      );

      if (mounted) {
        setState(() {
          _foundDevices.addAll(foundDevices);
        });

        if (foundDevices.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhum Smart Plug encontrado na rede'),
              backgroundColor: Color.fromARGB(255, 248, 36, 58),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Encontrados ${_foundDevices.length} dispositivo(s)!',
              ),
              backgroundColor: Colors.green.shade100,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro no scan: $e'),
            backgroundColor: Colors.red.shade100,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<SmartPlugDevice?> _testSmartPlug(String ip) async {
    try {
      final endpoints = [
        // Shelly
        'http://$ip/rpc/Shelly.GetStatus',
        'http://$ip/status',
        // TP-Link
        'http://$ip/api/system/get_sysinfo',
        // Sonoff
        'http://$ip/app?typ=login',
        // Genéricos
        'http://$ip/',
        'http://$ip/meta',
      ];

      for (final endpoint in endpoints) {
        try {
          final response = await http
              .get(Uri.parse(endpoint))
              .timeout(const Duration(seconds: 1));

          if (response.statusCode == 200) {
            final body = response.body.toLowerCase();

            // Identifica marcas
            if (body.contains('shelly') || body.contains('restart_required')) {
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
              return SmartPlugDevice(
                ip: ip,
                name: 'Sonoff Basic',
                type: 'sonoff',
              );
            }
          }
        } catch (e) {
          // Endpoint falhou, continua
        }
      }
    } catch (e) {
      // IP não responde
    }
    return null;
  }

  // ✅ CRÍTICO: Devolve o device ao invés de adicionar ao Firestore
  void _selectDevice(SmartPlugDevice device) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context, device); // ← VOLTA COM O DEVICE PARA AddDevicePage
    }
  }
}

class SmartPlugDevice {
  final String ip;
  final String name;
  final String type;

  SmartPlugDevice({required this.ip, required this.name, required this.type});
}
