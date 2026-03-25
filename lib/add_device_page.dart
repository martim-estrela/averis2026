import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'services/gamification_service.dart';
import 'services/shelly_provisioning_service.dart';
import 'services/user_service.dart';

// ── Modelos ────────────────────────────────────────────────────────────────

enum _DeviceMode { factory, network }

class _FoundDevice {
  final String displayName;
  final _DeviceMode mode;
  final String? ssid; // factory mode
  final String? ip; // network mode

  const _FoundDevice({
    required this.displayName,
    required this.mode,
    this.ssid,
    this.ip,
  });
}

// ── Página principal ───────────────────────────────────────────────────────

class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  bool _isScanning = false;
  List<_FoundDevice> _factoryDevices = [];
  List<_FoundDevice> _networkDevices = [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _isScanning = true;
      _factoryDevices = [];
      _networkDevices = [];
    });

    await Future.wait([_scanForFactoryDevices(), _scanNetwork()]);

    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _scanForFactoryDevices() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) return;
    try {
      final can = await WiFiScan.instance.canStartScan();
      if (can == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
      }
      final results = await WiFiScan.instance.getScannedResults();
      final shellyNets = results
          .where((ap) => ap.ssid.startsWith('Shelly'))
          .toList();
      if (mounted) {
        setState(() {
          _factoryDevices = shellyNets
              .map(
                (ap) => _FoundDevice(
                  displayName: ap.ssid,
                  mode: _DeviceMode.factory,
                  ssid: ap.ssid,
                ),
              )
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _scanNetwork() async {
    try {
      final wifiIp = await NetworkInfo().getWifiIP();
      if (wifiIp == null) return;
      final subnet = wifiIp.split('.').take(3).join('.');

      final futures = List.generate(254, (i) async {
        final ip = '$subnet.${i + 1}';
        try {
          final res = await http
              .get(Uri.parse('http://$ip/rpc/Shelly.GetDeviceInfo'))
              .timeout(const Duration(milliseconds: 800));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final model = data['model'] as String? ?? 'Shelly';
            return _FoundDevice(
              displayName: model,
              mode: _DeviceMode.network,
              ip: ip,
            );
          }
        } catch (_) {}
        return null;
      });

      final results = await Future.wait(futures);
      if (mounted) {
        setState(
          () => _networkDevices = results.whereType<_FoundDevice>().toList(),
        );
      }
    } catch (_) {}
  }

  Future<void> _onTap(_FoundDevice device) async {
    if (device.mode == _DeviceMode.factory) {
      final creds = await _askWifiCredentials(device.displayName);
      if (creds == null || !mounted) return;
      await _runProvisioning(device, creds.$1, creds.$2);
    } else {
      await _addNetworkDevice(device);
    }
  }

  Future<(String, String)?> _askWifiCredentials(String deviceName) async {
    // Ler o SSID atual do telemóvel antes de abrir o diálogo
    final rawSsid = await NetworkInfo().getWifiName() ?? '';
    final currentSsid = rawSsid.replaceAll('"', ''); // Android adiciona aspas

    final ssidCtrl = TextEditingController(text: currentSsid);
    final passCtrl = TextEditingController();
    bool obscure = true;

    if (!mounted) return null;

    return showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Configurar $deviceName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Insere as credenciais do teu WiFi de casa para configurar o Shelly.',
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'O Shelly só suporta WiFi 2.4 GHz.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ssidCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome do WiFi (SSID) *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Password do WiFi',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setSt(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (ssidCtrl.text.trim().isNotEmpty) {
                  Navigator.pop(ctx, (ssidCtrl.text.trim(), passCtrl.text));
                }
              },
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runProvisioning(
    _FoundDevice device,
    String ssid,
    String password,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ProvisioningDialog(
        shellySSID: device.ssid!,
        homeSsid: ssid,
        homePassword: password,
      ),
    );

    if (!mounted) return;
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dispositivo adicionado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _addNetworkDevice(_FoundDevice device) async {
    final nameCtrl = TextEditingController(text: device.displayName);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar dispositivo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'IP: ${device.ip}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nome do dispositivo',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await UserService.addDevice(
        uid: uid,
        name: nameCtrl.text.trim(),
        ip: device.ip!,
      );
      GamificationService.awardActionPoints(uid: uid, points: 5);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispositivo adicionado!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } on DeviceAlreadyExistsException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispositivo já existe na app.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _addManually() async {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar manualmente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome do dispositivo *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Endereço IP *',
                hintText: '192.168.1.10',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.router),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty &&
                  ipCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await UserService.addDevice(
        uid: uid,
        name: nameCtrl.text.trim(),
        ip: ipCtrl.text.trim(),
      );
      GamificationService.awardActionPoints(uid: uid, points: 5);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dispositivo adicionado!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } on DeviceAlreadyExistsException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispositivo já existe na app.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAny = _factoryDevices.isNotEmpty || _networkDevices.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar Dispositivo'),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _scan,
            tooltip: 'Procurar novamente',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _scan,
        child: CustomScrollView(
          slivers: [
            if (_isScanning && !hasAny)
              const SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('A procurar dispositivos...'),
                    ],
                  ),
                ),
              )
            else if (!_isScanning && !hasAny)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.devices_other,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhum dispositivo encontrado',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Certifica-te que o dispositivo está ligado\ne na mesma rede.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (_factoryDevices.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    icon: Icons.add_circle_outline,
                    label: 'Para configurar',
                    color: Colors.orange,
                    subtitle: 'Dispositivos novos ou com reset de fábrica',
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _DeviceTile(
                      device: _factoryDevices[i],
                      onTap: () => _onTap(_factoryDevices[i]),
                    ),
                    childCount: _factoryDevices.length,
                  ),
                ),
              ],
              if (_networkDevices.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    icon: Icons.wifi,
                    label: 'Já na rede',
                    color: Colors.green,
                    subtitle: 'Dispositivos encontrados na tua rede local',
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _DeviceTile(
                      device: _networkDevices[i],
                      onTap: () => _onTap(_networkDevices[i]),
                    ),
                    childCount: _networkDevices.length,
                  ),
                ),
              ],
              if (_isScanning)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'A continuar a procura...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: OutlinedButton.icon(
            onPressed: _addManually,
            icon: const Icon(Icons.edit),
            label: const Text('Adicionar manualmente'),
          ),
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final _FoundDevice device;
  final VoidCallback onTap;

  const _DeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFactory = device.mode == _DeviceMode.factory;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isFactory
            ? Colors.orange.shade50
            : Colors.green.shade50,
        child: Icon(
          isFactory ? Icons.settings_remote : Icons.power,
          color: isFactory ? Colors.orange : Colors.green,
        ),
      ),
      title: Text(device.displayName),
      subtitle: Text(
        isFactory ? 'Toca para configurar o WiFi' : device.ip ?? '',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}

// ── Diálogo de provisioning ────────────────────────────────────────────────

enum _ProvStep {
  connecting,
  identifying,
  configuringWifi,
  rebooting,
  discovering,
  saving,
  done,
  error,
}

class _ProvisioningDialog extends StatefulWidget {
  final String shellySSID;
  final String homeSsid;
  final String homePassword;

  const _ProvisioningDialog({
    required this.shellySSID,
    required this.homeSsid,
    required this.homePassword,
  });

  @override
  State<_ProvisioningDialog> createState() => _ProvisioningDialogState();
}

class _ProvisioningDialogState extends State<_ProvisioningDialog> {
  _ProvStep _step = _ProvStep.connecting;
  String? _error;

  static const _progressSteps = [
    _ProvStep.connecting,
    _ProvStep.identifying,
    _ProvStep.configuringWifi,
    _ProvStep.rebooting,
    _ProvStep.discovering,
    _ProvStep.saving,
    _ProvStep.done,
  ];

  static String _label(_ProvStep s) => switch (s) {
    _ProvStep.connecting => 'Ligar ao Shelly',
    _ProvStep.identifying => 'Identificar dispositivo',
    _ProvStep.configuringWifi => 'Configurar WiFi',
    _ProvStep.rebooting => 'Aguardar reboot (~25s)',
    _ProvStep.discovering => 'Descobrir IP na rede',
    _ProvStep.saving => 'Guardar na app',
    _ProvStep.done => 'Concluído',
    _ProvStep.error => '',
  };

  /// Normaliza MAC para comparação: remove separadores e converte para maiúsculas.
  /// Ex: "aa:bb:cc:dd:ee:ff" → "AABBCCDDEEFF"
  static String _normalizeMac(String mac) =>
      mac.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toUpperCase();

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _step = _ProvStep.connecting;
      _error = null;
    });

    String? discoveredIp;

    try {
      // 1. Ligar ao AP do Shelly
      await WiFiForIoTPlugin.connect(
        widget.shellySSID,
        security: NetworkSecurity.NONE,
        joinOnce: true,
        withInternet: false,
      );
      await Future.delayed(const Duration(seconds: 2));
      await WiFiForIoTPlugin.forceWifiUsage(true);

      // 2. Identificar dispositivo
      setState(() => _step = _ProvStep.identifying);
      final info = await ShellyProvisioningService.getDeviceInfo();
      final rawMac = info['mac'] as String? ?? '';
      final normalizedMac = rawMac.isNotEmpty ? _normalizeMac(rawMac) : null;
      final model = info['model'] as String? ?? 'Shelly';

      // 3. Configurar WiFi
      setState(() => _step = _ProvStep.configuringWifi);
      await ShellyProvisioningService.setWifiConfig(
        ssid: widget.homeSsid,
        password: widget.homePassword,
      );

      // 4. Reboot — desligar do AP e aguardar que o Shelly ligue ao WiFi de casa
      setState(() => _step = _ProvStep.rebooting);
      await ShellyProvisioningService.reboot();
      await WiFiForIoTPlugin.forceWifiUsage(false);
      await WiFiForIoTPlugin.disconnect();

      // Aguardar 25s (reboot do Shelly) e garantir que o telemóvel voltou ao WiFi de casa
      await Future.delayed(const Duration(seconds: 25));

      // 5. Descobrir IP — aguardar reconexão ao WiFi de casa e tentar até 3 vezes
      setState(() => _step = _ProvStep.discovering);

      // Garantir que o telemóvel voltou ao WiFi de casa
      String? subnet;
      for (int i = 0; i < 8; i++) {
        final wifiIp = await NetworkInfo().getWifiIP();
        if (wifiIp != null && !wifiIp.startsWith('192.168.33.')) {
          subnet = wifiIp.split('.').take(3).join('.');
          break;
        }
        await Future.delayed(const Duration(seconds: 3));
      }
      if (subnet == null) {
        throw Exception(
          'Telemóvel não voltou ao WiFi de casa. Verifica a ligação.',
        );
      }

      // Tentar descobrir o Shelly até 3 vezes (a cada 10s)
      for (int attempt = 0; attempt < 3 && discoveredIp == null; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(seconds: 10));
        discoveredIp = await ShellyProvisioningService.discoverShellyIp(
          subnet: subnet,
          expectedMac: normalizedMac,
        );
      }
      if (discoveredIp == null) {
        throw Exception(
          'Shelly não encontrado na rede após 3 tentativas.\n'
          'Verifica se o WiFi é 2.4 GHz e se a password está correta.',
        );
      }

      // Confirmar que o Shelly responde antes de guardar
      try {
        await http
            .get(Uri.parse('http://$discoveredIp/rpc/Shelly.GetDeviceInfo'))
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Se não responder agora, guardamos na mesma — o polling vai confirmar
      }

      // 6. Guardar
      setState(() => _step = _ProvStep.saving);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await UserService.addDevice(
        uid: uid,
        name: model,
        ip: discoveredIp,
        mac: rawMac,
        type: 'shelly-plug',
        online: true,
      );
      GamificationService.awardActionPoints(uid: uid, points: 5);

      setState(() => _step = _ProvStep.done);
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop(true);
    } on DeviceAlreadyExistsException catch (e) {
      // Dispositivo já existe (tentativa anterior) — atualizar IP com o recém-descoberto
      final uid = FirebaseAuth.instance.currentUser!.uid;
      if (discoveredIp != null) {
        await UserService.updateDeviceIp(
          uid: uid,
          deviceId: e.existingDeviceId,
          ip: discoveredIp,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      await WiFiForIoTPlugin.forceWifiUsage(false);
      setState(() {
        _step = _ProvStep.error;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('A configurar Shelly...'),
      content: _step == _ProvStep.error
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Erro desconhecido',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: _progressSteps.map((s) {
                final currentIdx = _progressSteps.indexOf(_step);
                final sIdx = _progressSteps.indexOf(s);
                final isDone = sIdx < currentIdx;
                final isCurrent = s == _step;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: isDone
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 20,
                              )
                            : isCurrent
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Icon(
                                Icons.radio_button_unchecked,
                                color: Colors.grey,
                                size: 20,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _label(s),
                        style: TextStyle(
                          color: isDone
                              ? Colors.green
                              : isCurrent
                              ? null
                              : Colors.grey,
                          fontWeight: isCurrent ? FontWeight.bold : null,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
      actions: _step == _ProvStep.error
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Fechar'),
              ),
              ElevatedButton(
                onPressed: _run,
                child: const Text('Tentar novamente'),
              ),
            ]
          : null,
    );
  }
}
