import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auto_detect_page.dart';
import 'shelly_provisioning_page.dart';
import 'services/user_service.dart';

class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  String _deviceType = 'shelly-plug';
  bool _isLoading = false;

  Future<void> _addDevice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;

      // ✅ Usa UserService — cria em devices/{deviceId} (coleção raiz)
      //    com a estrutura completa (lastMetrics, online, etc.)
      await UserService.addDevice(
        uid: userId,
        name: _nameController.text.trim(),
        ip: _ipController.text.trim(),
        type: _deviceType,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dispositivo adicionado!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
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
                  'Adiciona um novo dispositivo para monitorizar o consumo.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Botão provisioning (Shelly de fábrica)
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<Map<String, dynamic>>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ShellyProvisioningPage(),
                      ),
                    );
                    if (result != null && mounted) {
                      _nameController.text = result['model'] ?? 'Shelly Plug S';
                      _ipController.text = result['ip'] ?? '';
                      setState(() => _deviceType = 'shelly-plug');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ Shelly encontrado em ${result['ip']}',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.add_link),
                  label: const Text('Configurar novo Shelly (de fábrica)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Botão auto-deteção
                ElevatedButton.icon(
                  onPressed: () async {
                    final device = await Navigator.push<SmartPlugDevice>(
                      context,
                      MaterialPageRoute(builder: (_) => const AutoDetectPage()),
                    );
                    if (device != null && mounted) {
                      _nameController.text = device.name;
                      _ipController.text = device.ip;
                      setState(() => _deviceType = device.type);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ ${device.name} selecionada'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Procurar Shelly na rede'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Nome
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do dispositivo *',
                    hintText: 'Ex: Tomada Cozinha',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Nome obrigatório.'
                      : null,
                ),
                const SizedBox(height: 16),

                // IP
                TextFormField(
                  controller: _ipController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Endereço IP *',
                    hintText: '192.168.1.10',
                    prefixIcon: Icon(Icons.router),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'IP obrigatório.';
                    if (!RegExp(
                      r'^(\d{1,3}\.){3}\d{1,3}$',
                    ).hasMatch(v.trim())) {
                      return 'IP inválido.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

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
                    _isLoading ? 'Adicionar...' : 'Adicionar Dispositivo',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Clica "Procurar Shelly na rede" para detetar '
                          'automaticamente. Depois só confirma e adiciona!',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.blue.shade800,
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
