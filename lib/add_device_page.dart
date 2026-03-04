import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'multicast_dns.dart';
import 'shelly_discovery.dart';

class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  bool _isLoading = false;

  // descoberta automática
  bool _isScanning = false;
  List<DiscoveredShelly> _found = [];
  final ShellyDiscovery _discovery = MdnsShellyDiscovery();

  Future<void> _scanShellys() async {
    setState(() {
      _isScanning = true;
      _found = [];
    });
    try {
      final devices = await _discovery.discover(
        timeout: const Duration(seconds: 8),
      );
      setState(() {
        _found = devices;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao procurar dispositivos Shelly.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _addDevice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .doc('device_${DateTime.now().millisecondsSinceEpoch}')
          .set({
            'name': _nameController.text.trim(),
            'ip': _ipController.text.trim(),
            'status': 'off',
            'type': 'shelly-plug',
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispositivo adicionado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: ${e.message}')));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro inesperado. Tente novamente.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar Dispositivo'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.add_circle_outline,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 16),
                Text(
                  'Novo Smart Plug',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Adiciona um novo dispositivo para monitorizar o consumo de energia.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // botão de descoberta automática
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _scanShellys,
                  icon: _isScanning
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    _isScanning ? 'A procurar...' : 'Procurar Shelly na rede',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade100,
                    foregroundColor: Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 16),

                // Nome do dispositivo
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do dispositivo',
                    hintText: 'Ex: Tomada Cozinha, Frigorífico',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'O nome é obrigatório.';
                    }
                    if (value.trim().length < 3) {
                      return 'O nome deve ter pelo menos 3 caracteres.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // IP do Shelly
                TextFormField(
                  controller: _ipController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Endereço IP do Shelly',
                    hintText: 'Ex: 192.168.1.64',
                    prefixIcon: const Icon(Icons.router),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.help_outline),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Como descobrir o IP?'),
                            content: const Text(
                              '1. Liga o Shelly à tua rede WiFi\n'
                              '2. Vai ao Router (normalmente 192.168.1.1)\n'
                              '3. Procura "shellyplug-xxx" na lista de dispositivos\n'
                              '4. Copia o IP (ex: 192.168.1.64)',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'O IP é obrigatório.';
                    }
                    final ipRegex = RegExp(
                      r'^(\d{1,3}\.){3}\d{1,3}$',
                      unicode: true,
                    );
                    if (!ipRegex.hasMatch(value.trim())) {
                      return 'Introduza um IP válido (ex: 192.168.1.64)';
                    }
                    return null;
                  },
                ),

                // lista de dispositivos encontrados
                if (_found.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Dispositivos encontrados:',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _found.length,
                    itemBuilder: (context, index) {
                      final d = _found[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.power),
                          title: Text(d.name),
                          subtitle: Text(d.ip),
                          trailing: const Icon(Icons.add),
                          onTap: () {
                            _nameController.text = d.name;
                            _ipController.text = d.ip;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Shelly selecionada: ${d.name}'),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 24),

                // Botão adicionar
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _addDevice,
                  icon: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(
                    _isLoading ? 'A adicionar...' : 'Adicionar Dispositivo',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Dica rápida
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Colors.amber.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'O dispositivo será adicionado e aparecerá no Dashboard. '
                          'Podes ligar/desligar e ver o consumo em tempo real.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.amber.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
