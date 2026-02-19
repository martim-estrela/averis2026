import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'add_device_page.dart';
import 'dart:convert';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AddDevicePage()));
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('devices')
            .orderBy('createdAt', descending: true)
            .snapshots(),

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.electrical_services_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sem dispositivos',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Adiciona o teu primeiro Smart Plug',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddDevicePage()),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar Dispositivo'),
                  ),
                ],
              ),
            );
          }

          final devices = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final deviceDoc = devices[index];
              final deviceData = deviceDoc.data() as Map<String, dynamic>;

              return DeviceCard(
                deviceDoc: deviceDoc,
                deviceData: deviceData,
                onNameChanged: (newName) async {
                  await deviceDoc.reference.update({
                    'name': newName,
                  }); // ← OK aqui
                },
                onToggle: (isOn) async {
                  // ← AQUI CORRIGIR
                  final ip = deviceData['ip'] as String;
                  final deviceRef = deviceDoc.reference;
                  final userId = FirebaseAuth.instance.currentUser!.uid;

                  // Liga/desliga Shelly
                  final success = await _toggleShelly(ip, isOn);

                  if (success) {
                    // Atualiza status no Firestore
                    await deviceRef.update({'status': isOn ? 'on' : 'off'});

                    // Guarda reading (sem widget!)
                    await _saveReading(ip, deviceDoc.id, userId);
                  }
                },

                onDelete: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Eliminar dispositivo'),
                      content: Text(
                        'Tem a certeza que quer eliminar "${deviceData['name']}"?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            'Eliminar',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await deviceDoc.reference.delete();
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<bool> _toggleShelly(String ip, bool turnOn) async {
    try {
      final url = Uri.parse('http://$ip/relay/0?turn=${turnOn ? "on" : "off"}');
      final response = await http.get(url);
      return response.statusCode == 200;
    } catch (e) {
      print('Erro Shelly $ip: $e');
      return false;
    }
  }

  Future<void> _saveReading(String ip, String deviceId, String userId) async {
    try {
      final statusUrl = Uri.parse('http://$ip/status');
      final statusResponse = await http.get(statusUrl);

      if (statusResponse.statusCode == 200) {
        final statusData = json.decode(statusResponse.body);
        final meters = statusData['meters'] as List?;

        if (meters != null && meters.isNotEmpty) {
          final meter = meters[0];
          final powerW = (meter['power'] ?? 0).toDouble();
          final totalKwh = (meter['total'] ?? 0).toDouble() / 1000;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('devices')
              .doc(deviceId)
              .collection('readings')
              .doc(DateTime.now().millisecondsSinceEpoch.toString())
              .set({
                'powerW': powerW,
                'totalKwh': totalKwh,
                'voltage': meter['voltage'] ?? 0.0,
                'timestamp': FieldValue.serverTimestamp(),
              });
        }
      }
    } catch (e) {
      print('Erro reading $ip: $e');
    }
  }
}

class DeviceCard extends StatefulWidget {
  final QueryDocumentSnapshot deviceDoc;
  final Map<String, dynamic> deviceData;
  final Function(String) onNameChanged;
  final Function(bool) onToggle;
  final VoidCallback onDelete;

  const DeviceCard({
    super.key,
    required this.deviceDoc,
    required this.deviceData,
    required this.onNameChanged,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  bool _isEditingName = false;
  late TextEditingController _nameController;
  bool _deviceOn = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.deviceData['name']);
    _deviceOn = widget.deviceData['status'] == 'on';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ip = widget.deviceData['ip'] ?? 'Sem IP';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho com nome editável
            Row(
              children: [
                Expanded(
                  child: _isEditingName
                      ? TextFormField(
                          controller: _nameController,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Nome do dispositivo',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onFieldSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              widget.onNameChanged(value.trim());
                            }
                            setState(() => _isEditingName = false);
                          },
                        )
                      : GestureDetector(
                          onTap: () => setState(() => _isEditingName = true),
                          child: Text(
                            widget.deviceData['name'] ?? 'Sem nome',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => setState(() => _isEditingName = true),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Informações do dispositivo
            Row(
              children: [
                Icon(Icons.router, color: Colors.blue[600], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('IP: $ip', style: theme.textTheme.bodyMedium),
                      Text(
                        'Tipo: ${widget.deviceData['type'] ?? 'Desconhecido'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Toggle principal
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _deviceOn ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _deviceOn ? 'Ligado' : 'Desligado',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _deviceOn,
                  onChanged: (value) {
                    setState(() => _deviceOn = value);
                    widget.onToggle(value);
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Botões de ação
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Eliminar',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      // TODO: Ver consumo atual via http://IP/meter/0
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'A verificar consumo em ${widget.deviceData['ip']}...',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bolt),
                    label: const Text('Consumo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
