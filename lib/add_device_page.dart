// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/io_client.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'services/gamification_service.dart';
import 'services/shelly_api.dart';
import 'services/shelly_provisioning_service.dart';
import 'services/user_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────

const _kBg      = Color(0xFF0a1628);
const _kNav     = Color(0xFF0f1e3d);
const _kAccent  = Color(0xFF38d9a9);
const _kSurface = Color(0xFF132040);
const _kBorder  = Color(0xFF1e3a6e);

// ── Enum ─────────────────────────────────────────────────────────────────────

enum AddMethod { provisioning, scan, manual }

// ── Model ─────────────────────────────────────────────────────────────────────

class _ShellyFound {
  final String ip;
  final String model;
  final String mac;
  const _ShellyFound({required this.ip, required this.model, required this.mac});
}

// ── HTTP helper ───────────────────────────────────────────────────────────────

IOClient _wifiClient() {
  final httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..badCertificateCallback = (_, _, _) => true;
  return IOClient(httpClient);
}

// ══════════════════════════════════════════════════════════════════════════════
// AddDevicePage
// ══════════════════════════════════════════════════════════════════════════════

class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  AddMethod _method = AddMethod.provisioning;
  bool _showSuccess = false;
  String _successName = '';

  // ── Provisioning controllers ───────────────────────────────────────────────
  final _provNameCtrl = TextEditingController();
  final _provSsidCtrl = TextEditingController();
  final _provPassCtrl = TextEditingController();
  bool _provObscure = true;

  // ── Scan state ─────────────────────────────────────────────────────────────
  bool _scanning = false;
  int _scanProgress = 0;
  final List<_ShellyFound> _scanResults = [];
  _ShellyFound? _selectedDevice;
  final _scanNameCtrl = TextEditingController();

  // ── Manual controllers ─────────────────────────────────────────────────────
  final _manNameCtrl = TextEditingController();
  final _manIpCtrl   = TextEditingController();

  @override
  void dispose() {
    _provNameCtrl.dispose();
    _provSsidCtrl.dispose();
    _provPassCtrl.dispose();
    _scanNameCtrl.dispose();
    _manNameCtrl.dispose();
    _manIpCtrl.dispose();
    super.dispose();
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  void _reset() {
    setState(() {
      _showSuccess = false;
      _successName = '';
      _method = AddMethod.provisioning;
      _provNameCtrl.clear();
      _provSsidCtrl.clear();
      _provPassCtrl.clear();
      _scanning = false;
      _scanProgress = 0;
      _scanResults.clear();
      _selectedDevice = null;
      _scanNameCtrl.clear();
      _manNameCtrl.clear();
      _manIpCtrl.clear();
    });
  }

  // ── SSID auto-fill ────────────────────────────────────────────────────────

  Future<void> _fillSsid() async {
    try {
      final raw = await NetworkInfo().getWifiName() ?? '';
      final ssid = raw.replaceAll('"', '');
      if (ssid.isNotEmpty && mounted) {
        setState(() => _provSsidCtrl.text = ssid);
      }
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MÉTODO 1 — Provisioning
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _doProvisioning() async {
    final name     = _provNameCtrl.text.trim();
    final ssid     = _provSsidCtrl.text.trim();
    final password = _provPassCtrl.text;

    if (name.isEmpty) {
      _snackError('Introduz um nome para o dispositivo.');
      return;
    }
    if (ssid.isEmpty) {
      _snackError('Introduz o nome da rede WiFi (SSID).');
      return;
    }

    _LoadingDialog.show(context, 'A ligar ao Shelly…');

    try {
      // 1. Identificar o dispositivo
      Map<String, dynamic> info;
      try {
        info = await ShellyProvisioningService.getDeviceInfo();
      } catch (_) {
        _LoadingDialog.hide(context);
        _snackError(
          'Não foi possível ligar ao Shelly.\n'
          'Confirma que estás ligado ao WiFi ShellyPlugSG3-…',
        );
        return;
      }

      final mac = (info['mac'] as String? ?? '')
          .replaceAll(RegExp(r'[^a-fA-F0-9]'), '')
          .toUpperCase();

      // 2. Enviar configuração WiFi
      _LoadingDialog.update(context, 'A enviar configuração WiFi…');
      try {
        await ShellyProvisioningService.setWifiConfig(
            ssid: ssid, password: password);
      } catch (_) {
        _LoadingDialog.hide(context);
        _snackError('Falha ao enviar configuração WiFi.');
        return;
      }

      // 3. Reboot
      _LoadingDialog.update(context, 'A reiniciar o dispositivo…');
      await ShellyProvisioningService.reboot();

      // 4. Aguardar reconexão
      _LoadingDialog.update(context, 'A aguardar reconexão à rede…');
      await Future.delayed(const Duration(seconds: 6));

      // 5. Descobrir IP
      _LoadingDialog.update(context, 'A procurar o dispositivo na rede…');
      final wifiIp = await NetworkInfo().getWifiIP();
      if (wifiIp == null) {
        _LoadingDialog.hide(context);
        _snackError('Não foi possível obter o IP da rede local.');
        return;
      }
      final subnet = wifiIp.substring(0, wifiIp.lastIndexOf('.'));
      final discoveredIp = await ShellyProvisioningService.discoverShellyIp(
        subnet: subnet,
        expectedMac: mac.isNotEmpty ? mac : null,
      );

      if (discoveredIp == null) {
        _LoadingDialog.hide(context);
        _snackError(
          'O Shelly não foi encontrado na rede após configuração.\n'
          'Verifica as credenciais WiFi.',
        );
        return;
      }

      // 6. Guardar
      _LoadingDialog.update(context, 'A guardar dispositivo…');
      final uid = FirebaseAuth.instance.currentUser!.uid;
      try {
        await UserService.addDevice(
          uid: uid,
          name: name,
          ip: discoveredIp,
          mac: mac,
          type: 'shelly-plug',
          online: true,
        );
        await GamificationService.awardActionPoints(uid: uid, points: 5);
      } on DeviceAlreadyExistsException catch (e) {
        await UserService.updateDeviceIp(
          uid: uid,
          deviceId: e.existingDeviceId,
          ip: discoveredIp,
        );
      }

      _LoadingDialog.hide(context);
      setState(() {
        _showSuccess = true;
        _successName = name;
      });
    } catch (e) {
      _LoadingDialog.hide(context);
      _snackError('Erro inesperado: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MÉTODO 2 — Scan
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _doScan() async {
    final result = await Connectivity().checkConnectivity();
    if (!result.contains(ConnectivityResult.wifi)) {
      _snackError('Não estás ligado a uma rede WiFi.');
      return;
    }

    final wifiIp = await NetworkInfo().getWifiIP();
    if (wifiIp == null) {
      _snackError('Não foi possível obter o IP da rede.');
      return;
    }
    final subnet = wifiIp.substring(0, wifiIp.lastIndexOf('.'));

    setState(() {
      _scanning = true;
      _scanProgress = 0;
      _scanResults.clear();
      _selectedDevice = null;
      _scanNameCtrl.clear();
    });

    const batchSize = 20;
    for (int start = 1; start <= 254 && _scanning; start += batchSize) {
      final end = min(start + batchSize - 1, 254);
      final futures = List.generate(end - start + 1, (i) async {
        final ip = '$subnet.${start + i}';
        final client = _wifiClient();
        try {
          final res = await client
              .get(Uri.parse('http://$ip/rpc/Shelly.GetDeviceInfo'))
              .timeout(const Duration(milliseconds: 600));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            return _ShellyFound(
              ip: ip,
              model: (data['model'] as String?) ?? 'Shelly',
              mac: (data['mac'] as String?) ?? '',
            );
          }
        } catch (_) {
        } finally {
          client.close();
        }
        return null;
      });

      final batch = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        for (final d in batch) {
          if (d != null) _scanResults.add(d);
        }
        _scanProgress = min(end, 254);
      });
    }

    if (!mounted) return;
    setState(() => _scanning = false);

    if (_scanResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum Shelly encontrado na rede atual.'),
          backgroundColor: Colors.grey,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _stopScan() => setState(() => _scanning = false);

  Future<void> _doAddScanned() async {
    final device = _selectedDevice;
    final name   = _scanNameCtrl.text.trim();
    if (device == null) {
      _snackError('Seleciona um dispositivo da lista.');
      return;
    }
    if (name.isEmpty) {
      _snackError('Introduz um nome para o dispositivo.');
      return;
    }

    _LoadingDialog.show(context, 'A guardar dispositivo…');
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      try {
        await UserService.addDevice(
          uid: uid,
          name: name,
          ip: device.ip,
          mac: device.mac,
          type: 'shelly-plug',
          online: true,
        );
        await GamificationService.awardActionPoints(uid: uid, points: 5);
      } on DeviceAlreadyExistsException {
        _LoadingDialog.hide(context);
        _snackError('Este dispositivo já está adicionado.');
        return;
      }
      _LoadingDialog.hide(context);
      setState(() {
        _showSuccess = true;
        _successName = name;
      });
    } catch (e) {
      _LoadingDialog.hide(context);
      _snackError('Erro ao guardar: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MÉTODO 3 — Manual
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _doManual() async {
    final name = _manNameCtrl.text.trim();
    final ip   = _manIpCtrl.text.trim();

    if (name.isEmpty) {
      _snackError('Introduz um nome para o dispositivo.');
      return;
    }
    if (!RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(ip)) {
      _snackError('Endereço IP inválido.');
      return;
    }

    _LoadingDialog.show(context, 'A verificar dispositivo…');
    try {
      bool reachable;
      try {
        reachable = await ShellyApi.isReachable(ip)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        reachable = false;
      }

      if (!reachable) {
        _LoadingDialog.hide(context);
        _snackError(
          'Não foi possível ligar a $ip.\n'
          'Confirma que o dispositivo está online e na mesma rede.',
        );
        return;
      }

      _LoadingDialog.update(context, 'A guardar dispositivo…');
      final uid = FirebaseAuth.instance.currentUser!.uid;
      try {
        await UserService.addDevice(
          uid: uid,
          name: name,
          ip: ip,
          type: 'shelly-plug',
          online: true,
        );
        await GamificationService.awardActionPoints(uid: uid, points: 5);
      } on DeviceAlreadyExistsException {
        _LoadingDialog.hide(context);
        _snackError('Já existe um dispositivo com esse IP.');
        return;
      }

      _LoadingDialog.hide(context);
      setState(() {
        _showSuccess = true;
        _successName = name;
      });
    } catch (e) {
      _LoadingDialog.hide(context);
      _snackError('Erro inesperado: $e');
    }
  }

  // ── Error helper ──────────────────────────────────────────────────────────

  void _snackError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kNav,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Novo dispositivo',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _showSuccess
          ? _SuccessView(
              deviceName: _successName,
              onViewDevices: () => Navigator.of(context).pop(true),
              onAddAnother: _reset,
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MethodSelector(
                    selected: _method,
                    onSelect: (m) => setState(() => _method = m),
                  ),
                  const SizedBox(height: 24),
                  if (_method == AddMethod.provisioning) _buildProvForm(),
                  if (_method == AddMethod.scan) _buildScanForm(),
                  if (_method == AddMethod.manual) _buildManualForm(),
                ],
              ),
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Form: Provisioning
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildProvForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepsList(steps: const [
          'Liga o Shelly à tomada — LED deve piscar laranja',
          'Vai às Definições de WiFi do telemóvel',
          'Liga-te à rede  ShellyPlugSG3-XXXXXX',
          'Volta aqui e clica em "Ligar ao Shelly"',
        ]),
        const SizedBox(height: 20),
        _DarkTextField(
          label: 'Nome do dispositivo',
          hint: 'ex: Sala TV, Computador…',
          controller: _provNameCtrl,
        ),
        const SizedBox(height: 12),
        _DarkTextField(
          label: 'Rede WiFi (SSID)',
          hint: 'Nome da tua rede WiFi',
          controller: _provSsidCtrl,
          suffix: IconButton(
            icon: const Icon(Icons.wifi_find, color: _kAccent, size: 20),
            tooltip: 'Detetar WiFi atual',
            onPressed: _fillSsid,
          ),
        ),
        const SizedBox(height: 12),
        _DarkTextField(
          label: 'Password WiFi',
          hint: '••••••••',
          controller: _provPassCtrl,
          obscure: _provObscure,
          suffix: IconButton(
            icon: Icon(
              _provObscure ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey,
              size: 20,
            ),
            onPressed: () => setState(() => _provObscure = !_provObscure),
          ),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'Ligar ao Shelly',
          icon: Icons.wifi_tethering,
          onPressed: _doProvisioning,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Form: Scan
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildScanForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_scanning && _scanResults.isEmpty)
          _PrimaryButton(
            label: 'Iniciar scan',
            icon: Icons.search,
            onPressed: _doScan,
          ),

        if (_scanning) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'A procurar dispositivos… ($_scanProgress/254)',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                    GestureDetector(
                      onTap: _stopScan,
                      child: const Text(
                        'Parar',
                        style: TextStyle(
                            color: _kAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _scanProgress / 254,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF2d5fa6)),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_scanResults.isNotEmpty) ...[
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Encontrados até agora:',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ..._scanResults.map((d) => _ScanResultCard(
                device: d,
                selected: _selectedDevice?.ip == d.ip,
                onSelect: () => setState(() {
                  _selectedDevice = d;
                  _scanNameCtrl.text = 'Shelly @ ${d.ip}';
                }),
              )),
          const SizedBox(height: 16),
          if (_selectedDevice != null) ...[
            _DarkTextField(
              label: 'Nome do dispositivo',
              hint: 'ex: Sala TV, Computador…',
              controller: _scanNameCtrl,
            ),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: Row(children: [
                const Icon(Icons.router, color: Colors.grey, size: 16),
                const SizedBox(width: 8),
                Text(
                  _selectedDevice!.ip,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(width: 8),
                const Text(
                  '(preenchido automaticamente)',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _PrimaryButton(
              label: 'Adicionar dispositivo selecionado',
              icon: Icons.add_circle_outline,
              onPressed: _doAddScanned,
            ),
          ],
          if (!_scanning) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: _doScan,
                icon: const Icon(Icons.refresh,
                    color: _kAccent, size: 16),
                label: const Text(
                  'Fazer novo scan',
                  style: TextStyle(color: _kAccent, fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Form: Manual
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildManualForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DarkTextField(
          label: 'Nome do dispositivo',
          hint: 'ex: Sala TV, Computador…',
          controller: _manNameCtrl,
        ),
        const SizedBox(height: 12),
        _DarkTextField(
          label: 'Endereço IP',
          hint: 'ex: 192.168.1.162',
          controller: _manIpCtrl,
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'Verificar e adicionar',
          icon: Icons.check_circle_outline,
          onPressed: _doManual,
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _MethodSelector
// ══════════════════════════════════════════════════════════════════════════════

class _MethodSelector extends StatelessWidget {
  final AddMethod selected;
  final void Function(AddMethod) onSelect;

  const _MethodSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _MethodCard(
          method: AddMethod.provisioning,
          selected: selected,
          onTap: () => onSelect(AddMethod.provisioning),
          icon: Icons.wifi_tethering,
          color: _kAccent,
          label: 'Configurar Shelly',
          desc: 'Device de fábrica',
        ),
        _MethodCard(
          method: AddMethod.scan,
          selected: selected,
          onTap: () => onSelect(AddMethod.scan),
          icon: Icons.search,
          color: const Color(0xFF2d5fa6),
          label: 'Detetar na rede',
          desc: 'Scan automático',
        ),
        _MethodCard(
          method: AddMethod.manual,
          selected: selected,
          onTap: () => onSelect(AddMethod.manual),
          icon: Icons.edit_outlined,
          color: const Color(0xFFf4a234),
          label: 'IP manual',
          desc: 'Já na rede',
        ),
      ],
    );
  }
}

class _MethodCard extends StatelessWidget {
  final AddMethod method;
  final AddMethod selected;
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  final String label;
  final String desc;

  const _MethodCard({
    required this.method,
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.color,
    required this.label,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = method == selected;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 100,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : _kBorder,
            width: isSelected ? 2.0 : 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _StepsList
// ══════════════════════════════════════════════════════════════════════════════

class _StepsList extends StatelessWidget {
  final List<String> steps;
  const _StepsList({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: steps.asMap().entries.map((e) {
          return Padding(
            padding: EdgeInsets.only(bottom: e.key < steps.length - 1 ? 10 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _kNav,
                    shape: BoxShape.circle,
                    border: Border.all(color: _kBorder),
                  ),
                  child: Center(
                    child: Text(
                      '${e.key + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.value,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _DarkTextField
// ══════════════════════════════════════════════════════════════════════════════

class _DarkTextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboard;

  const _DarkTextField({
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.suffix,
    this.keyboard,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            suffixIcon: suffix,
            filled: true,
            fillColor: _kSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PrimaryButton
// ══════════════════════════════════════════════════════════════════════════════

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kNav,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _ScanResultCard
// ══════════════════════════════════════════════════════════════════════════════

class _ScanResultCard extends StatelessWidget {
  final _ShellyFound device;
  final bool selected;
  final VoidCallback onSelect;

  const _ScanResultCard({
    required this.device,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? _kAccent.withValues(alpha: 0.08)
              : _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _kAccent : _kBorder,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2d5fa6).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.electrical_services,
                  color: Color(0xFF2d5fa6), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.model.isNotEmpty ? device.model : 'Shelly',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    device.ip,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? _kAccent : _kNav,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                selected ? 'Selecionado' : 'Selecionar',
                style: TextStyle(
                  color: selected ? const Color(0xFF04342c) : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _LoadingDialog — estático show/update/hide
// ══════════════════════════════════════════════════════════════════════════════

class _LoadingDialog {
  static void show(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LoadingDialogContent(message: message),
    );
  }

  static void update(BuildContext context, String message) {
    // Fechar o atual e abrir novo com mensagem atualizada
    Navigator.of(context, rootNavigator: true).pop();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LoadingDialogContent(message: message),
    );
  }

  static void hide(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

class _LoadingDialogContent extends StatelessWidget {
  final String message;
  const _LoadingDialogContent({required this.message});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _kAccent),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SuccessView
// ══════════════════════════════════════════════════════════════════════════════

class _SuccessView extends StatelessWidget {
  final String deviceName;
  final VoidCallback onViewDevices;
  final VoidCallback onAddAnother;

  const _SuccessView({
    required this.deviceName,
    required this.onViewDevices,
    required this.onAddAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 80,
              color: _kAccent,
            ),
            const SizedBox(height: 20),
            const Text(
              'Dispositivo adicionado!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              deviceName,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onViewDevices,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: const Color(0xFF04342c),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Ver os meus dispositivos',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onAddAnother,
              child: const Text(
                'Adicionar outro',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
