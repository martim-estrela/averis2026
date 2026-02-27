import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  Future<void> _addDevice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      // Cria o dispositivo no Firestore

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .doc(
            'device_${DateTime.now().millisecondsSinceEpoch}',
          ) // ✅ ID fixo e único
          .set({
            // ✅ .set() em vez de .add()
            'name': _nameController.text.trim(),
            'ip': _ipController.text.trim(),
            'status': 'off',
            'type': 'shelly-plug',
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      // Sucesso!
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispositivo adicionado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );

      // Volta para trás (Dashboard atualiza automaticamente)
      Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: ${e.message}')));
    } catch (e) {
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
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
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
                          'O dispositivo será adicionado e aparecerá no Dashboard. Podes ligar/desligar e ver o consumo em tempo real.',
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
