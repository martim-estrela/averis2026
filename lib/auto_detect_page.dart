import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AutoDetectPage extends StatefulWidget {
  const AutoDetectPage({super.key});

  @override
  State<AutoDetectPage> createState() => _AutoDetectPageState();
}

class _AutoDetectPageState extends State<AutoDetectPage> {
  final List<ShellyDevice> _finalShellyDevices = [];
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detetar Smart Plugs'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: _isScanning ? null : 0,
            backgroundColor: Colors.grey[300],
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.all(16.0),
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
                  : const Icon(Icons.wifi_find),
              label: Text(_isScanning ? 'Explorando...' : 'Explorar Rede'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ),

          Expanded(
            child: _finalShellyDevices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.outlet, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Sem Smart Plugs detetados',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toca em "Explorar Rede" para procurar Smart Plugs',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _finalShellyDevices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final device = _finalShellyDevices[index];
                      return Card(
                        elevation: 2,
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.electrical_services,
                              color: Colors.blue,
                              size: 28,
                            ),
                          ),
                          title: Text(
                            device.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('IP: ${device.ip}'),
                          trailing: ElevatedButton(
                            onPressed: () => _addShelly(device),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Adicionar'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _scanNetwork() async {
    setState(() {
      _isScanning = true;
      _finalShellyDevices.clear();
    });

    try {
      // 1. Pega subnet da rede
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      if (wifiIP == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Liga WiFi primeiro!')));
        }
        return;
      }

      final baseIP = wifiIP.substring(0, wifiIP.lastIndexOf('.'));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Escaneando $baseIP.1-254...')));

      // 2. Testa IPs 1-254 (simples mas eficaz)
      final List<ShellyDevice> foundDevices = [];

      await Future.wait(
        List.generate(254, (i) async {
          final testIP = '$baseIP.${i + 1}';
          final shelly = await _testShelly(testIP);
          if (shelly != null) {
            foundDevices.add(shelly);
          }
        }),
        eagerError: true,
      );

      if (mounted) {
        setState(() {
          _finalShellyDevices.addAll(foundDevices);
        });

        if (foundDevices.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhuma smart plug encontrada na rede'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Encontrados ${_finalShellyDevices.length} Smart Plugs!',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<ShellyDevice?> _testShelly(String ip) async {
    try {
      // Testa endpoints típicos do Shelly
      final endpoints = [
        'http://$ip/rpc/Shelly.GetStatus',
        'http://$ip/status',
        'http://$ip/meta',
      ];

      for (final endpoint in endpoints) {
        try {
          final response = await http
              .get(
                Uri.parse(endpoint),
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(const Duration(seconds: 1));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            // Verifica se é Shelly
            if (data['restart_required'] != null ||
                data['auth_req'] == false ||
                data['mac'] != null ||
                response.body.contains('shelly') ||
                response.body.contains('Shelly')) {
              return ShellyDevice(ip: ip, name: 'Shelly ${ip.split('.').last}');
            }
          }
        } catch (e) {
          // Endpoint não responde, continua
        }
      }
    } catch (e) {
      // IP não responde, continua
    }
    return null;
  }

  Future<void> _addShelly(ShellyDevice device) async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .add({
            'name': device.name,
            'ip': device.ip,
            'status': 'off',
            'type': 'shelly-plug',
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${device.name} adicionado!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao adicionar: $e')));
      }
    }
  }
}

class ShellyDevice {
  final String ip;
  final String name;

  ShellyDevice({required this.ip, required this.name});
}
