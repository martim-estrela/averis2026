// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'services/gamification_service.dart';
import 'services/shelly_provisioning_service.dart';
import 'services/user_service.dart';

// ── Constants ──────────────────────────────────────────────────────────────────

const _kNav    = Color(0xFF0f1e3d);
const _kAccent = Color(0xFF38d9a9);
const _kBg     = Color(0xFFF4F6FB);

const _kColorHexes = [
  '38d9a9', '378add', 'ef9f27', 'e24b4a', '7f77dd', 'd85a30',
];

Color _hexToColor(String hex) => Color(int.parse('FF$hex', radix: 16));

// ── Data model ─────────────────────────────────────────────────────────────────

class _FoundDevice {
  final String ip;
  final String shellyName; // name from device info
  final String mac;

  const _FoundDevice({
    required this.ip,
    required this.shellyName,
    required this.mac,
  });
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
  // ── Scan state ────────────────────────────────────────────────────────────
  bool _scanning        = false;
  final List<_FoundDevice> _found = [];
  int _scanned          = 0;
  static const _kTotal  = 254;

  // ── WiFi info ─────────────────────────────────────────────────────────────
  String _homeSsid = '';

  // ── Manual form ───────────────────────────────────────────────────────────
  bool _manualExpanded      = false;
  final _manualFormKey      = GlobalKey<FormState>();
  final _manualNameCtrl     = TextEditingController();
  final _manualIpCtrl       = TextEditingController();
  int  _manualColorIdx      = 0;
  bool _manualLoading       = false;

  @override
  void initState() {
    super.initState();
    _loadHomeSsid();
    _scanNetwork();
  }

  @override
  void dispose() {
    _manualNameCtrl.dispose();
    _manualIpCtrl.dispose();
    super.dispose();
  }

  // ── Load home SSID ────────────────────────────────────────────────────────

  Future<void> _loadHomeSsid() async {
    try {
      final raw = await NetworkInfo().getWifiName() ?? '';
      if (mounted) setState(() => _homeSsid = raw.replaceAll('"', ''));
    } catch (_) {}
  }

  // ── Network scan ──────────────────────────────────────────────────────────

  Future<void> _scanNetwork() async {
    setState(() {
      _scanning = true;
      _scanned  = 0;
      _found.clear();
    });

    try {
      final wifiIp = await NetworkInfo().getWifiIP();
      if (wifiIp == null) {
        if (mounted) setState(() => _scanning = false);
        return;
      }
      final subnet = wifiIp.split('.').take(3).join('.');

      await Future.wait(List.generate(_kTotal, (i) async {
        final ip = '$subnet.${i + 1}';
        try {
          final uri = Uri.parse('http://$ip/rpc/Shelly.GetDeviceInfo');
          final res =
              await http.get(uri).timeout(const Duration(milliseconds: 800));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final sName = (data['name'] as String?) ?? 'Shelly';
            final mac   = (data['mac'] as String?) ?? '';
            if (mounted) {
              setState(() => _found.add(
                _FoundDevice(ip: ip, shellyName: sName, mac: mac),
              ));
            }
          }
        } catch (_) {}
        if (mounted) setState(() => _scanned++);
      }));
    } catch (_) {}

    if (mounted) setState(() => _scanning = false);
  }

  // ── Add discovered device ─────────────────────────────────────────────────

  void _openAddFoundSheet(_FoundDevice device) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddFoundSheet(
        device: device,
        onAdd: (name, colorHex) async {
          Navigator.of(context).pop();
          final uid = FirebaseAuth.instance.currentUser!.uid;
          try {
            await UserService.addDevice(
              uid: uid,
              name: name,
              ip: device.ip,
              mac: device.mac,
              type: 'shelly-plug',
              online: true,
              iconColor: colorHex,
            );
            await GamificationService.awardActionPoints(
                uid: uid, points: 5);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Dispositivo adicionado!'),
              backgroundColor: Colors.green,
            ));
            Navigator.of(context).pop();
          } on DeviceAlreadyExistsException {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Dispositivo com esse IP já existe.'),
              backgroundColor: Colors.orange,
            ));
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro: $e')),
            );
          }
        },
      ),
    );
  }

  // ── Configure new Shelly (provisioning) ──────────────────────────────────

  void _openConfigureNewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ConfigureNewSheet(
        homeSsid: _homeSsid,
        onStart: (name, ssid, password, colorHex) {
          Navigator.of(context).pop(); // close sheet
          showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _ProvisioningDialog(
              deviceName: name,
              homeSsid: ssid,
              homePassword: password,
              iconColor: colorHex,
            ),
          ).then((ok) {
            if (ok == true && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Shelly configurado e adicionado!'),
                backgroundColor: Colors.green,
              ));
              Navigator.of(context).pop();
            }
          });
        },
      ),
    );
  }

  // ── Manual submit ─────────────────────────────────────────────────────────

  Future<void> _submitManual() async {
    if (!_manualFormKey.currentState!.validate()) return;
    setState(() => _manualLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await UserService.addDevice(
        uid: uid,
        name: _manualNameCtrl.text.trim(),
        ip: _manualIpCtrl.text.trim(),
        iconColor: _kColorHexes[_manualColorIdx],
      );
      await GamificationService.awardActionPoints(uid: uid, points: 5);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Dispositivo adicionado!'),
        backgroundColor: Colors.green,
      ));
      Navigator.of(context).pop();
    } on DeviceAlreadyExistsException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Dispositivo com esse IP já existe na app.'),
        backgroundColor: Colors.orange,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _manualLoading = false);
    }
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
          'Adicionar dispositivo',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Network scan section ─────────────────────────────────────
            _ScanSection(
              scanning: _scanning,
              found: _found,
              scanned: _scanned,
              total: _kTotal,
              homeSsid: _homeSsid,
              onRefresh: _scanNetwork,
              onDeviceTap: _openAddFoundSheet,
            ),

            const SizedBox(height: 16),

            // ── Configure new Shelly ─────────────────────────────────────
            _ConfigureNewCard(onTap: _openConfigureNewSheet),

            const SizedBox(height: 16),

            // ── Manual entry ─────────────────────────────────────────────
            _ManualSection(
              expanded: _manualExpanded,
              onToggle: () =>
                  setState(() => _manualExpanded = !_manualExpanded),
              formKey: _manualFormKey,
              nameCtrl: _manualNameCtrl,
              ipCtrl: _manualIpCtrl,
              selectedColorIdx: _manualColorIdx,
              onColorSelect: (i) =>
                  setState(() => _manualColorIdx = i),
              loading: _manualLoading,
              onSubmit: _submitManual,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _ScanSection
// ══════════════════════════════════════════════════════════════════════════════

class _ScanSection extends StatelessWidget {
  final bool scanning;
  final List<_FoundDevice> found;
  final int scanned;
  final int total;
  final String homeSsid;
  final VoidCallback onRefresh;
  final void Function(_FoundDevice) onDeviceTap;

  const _ScanSection({
    required this.scanning,
    required this.found,
    required this.scanned,
    required this.total,
    required this.homeSsid,
    required this.onRefresh,
    required this.onDeviceTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.wifi_find, color: _kNav, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Dispositivos na rede',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kNav,
                    ),
                  ),
                ),
                if (homeSsid.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      homeSsid,
                      style: const TextStyle(
                        color: _kAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: scanning ? null : onRefresh,
                  color: _kNav,
                  tooltip: 'Atualizar',
                ),
              ],
            ),
          ),

          // Progress bar
          if (scanning) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (scanned / total).clamp(0.0, 1.0),
                      backgroundColor:
                          Colors.grey.withValues(alpha: 0.15),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(_kAccent),
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A verificar $scanned de $total endereços…',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Results
          if (found.isEmpty && !scanning)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.grey[400], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      scanning
                          ? 'A procurar…'
                          : 'Nenhum dispositivo encontrado na rede.\n'
                              'Se tens um Shelly novo, usa "Configurar novo Shelly" abaixo.',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...found.map((d) => _DeviceCard(
                  device: d,
                  onTap: () => onDeviceTap(d),
                )),

          if (found.isNotEmpty) const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Found device card ─────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final _FoundDevice device;
  final VoidCallback onTap;

  const _DeviceCard({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.electrical_services,
                  color: _kAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.shellyName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    device.ip,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _kNav,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Adicionar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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
// _ConfigureNewCard
// ══════════════════════════════════════════════════════════════════════════════

class _ConfigureNewCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ConfigureNewCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0f1e3d), Color(0xFF1a3366)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0f1e3d).withValues(alpha: 0.30),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.wifi_tethering,
                color: _kAccent,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configurar novo Shelly',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Dispositivo novo · A app faz tudo automaticamente',
                    style: TextStyle(
                      color: Color(0x99FFFFFF),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Color(0x66FFFFFF),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _ManualSection
// ══════════════════════════════════════════════════════════════════════════════

class _ManualSection extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController ipCtrl;
  final int selectedColorIdx;
  final void Function(int) onColorSelect;
  final bool loading;
  final VoidCallback onSubmit;

  const _ManualSection({
    required this.expanded,
    required this.onToggle,
    required this.formKey,
    required this.nameCtrl,
    required this.ipCtrl,
    required this.selectedColorIdx,
    required this.onColorSelect,
    required this.loading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Toggle row
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lan, size: 20,
                        color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Adicionar por IP',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Já conheces o endereço IP do dispositivo',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded form
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome do dispositivo',
                        prefixIcon: Icon(Icons.label_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Campo obrigatório'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: ipCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Endereço IP',
                        hintText: '192.168.1.10',
                        prefixIcon: Icon(Icons.router),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Campo obrigatório';
                        }
                        if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$')
                            .hasMatch(v.trim())) {
                          return 'IP inválido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _ColorPicker(
                      selectedIndex: selectedColorIdx,
                      onSelect: onColorSelect,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: loading ? null : onSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kNav,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Adicionar',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _AddFoundSheet — name + color for a device already on the network
// ══════════════════════════════════════════════════════════════════════════════

class _AddFoundSheet extends StatefulWidget {
  final _FoundDevice device;
  final Future<void> Function(String name, String colorHex) onAdd;

  const _AddFoundSheet({required this.device, required this.onAdd});

  @override
  State<_AddFoundSheet> createState() => _AddFoundSheetState();
}

class _AddFoundSheetState extends State<_AddFoundSheet> {
  final _nameCtrl = TextEditingController();
  int _colorIdx   = 0;
  bool _loading   = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.device.shellyName;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Adicionar dispositivo',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: 4),
          Text(
            'IP: ${widget.device.ip}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome do dispositivo',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          _ColorPicker(
            selectedIndex: _colorIdx,
            onSelect: (i) => setState(() => _colorIdx = i),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _loading ||
                      _nameCtrl.text.trim().isEmpty
                  ? null
                  : () async {
                      setState(() => _loading = true);
                      await widget.onAdd(
                        _nameCtrl.text.trim(),
                        _kColorHexes[_colorIdx],
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: const Color(0xFF04342c),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF04342c),
                      ),
                    )
                  : const Text(
                      'Adicionar',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _ConfigureNewSheet — name + password for a new Shelly in AP mode
// ══════════════════════════════════════════════════════════════════════════════

class _ConfigureNewSheet extends StatefulWidget {
  final String homeSsid;
  final void Function(
          String name, String ssid, String password, String colorHex)
      onStart;

  const _ConfigureNewSheet({
    required this.homeSsid,
    required this.onStart,
  });

  @override
  State<_ConfigureNewSheet> createState() => _ConfigureNewSheetState();
}

class _ConfigureNewSheetState extends State<_ConfigureNewSheet> {
  final _nameCtrl  = TextEditingController();
  final _ssidCtrl  = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure    = true;
  int  _colorIdx   = 0;
  final _formKey   = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _ssidCtrl.text = widget.homeSsid;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Configurar novo Shelly',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Info box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: Colors.green, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Coloca o Shelly em modo AP: segura o botão '
                    '10 s até o LED piscar vermelho. '
                    'A app liga-se automaticamente.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nome do dispositivo',
                    prefixIcon: Icon(Icons.label_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Campo obrigatório'
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ssidCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome do WiFi (SSID)',
                    prefixIcon: Icon(Icons.wifi),
                    border: OutlineInputBorder(),
                    helperText: 'Preenchido automaticamente',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Campo obrigatório'
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password do WiFi',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 2.4 GHz warning
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.amber, size: 15),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'O Shelly só suporta WiFi 2.4 GHz.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          _ColorPicker(
            selectedIndex: _colorIdx,
            onSelect: (i) => setState(() => _colorIdx = i),
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                widget.onStart(
                  _nameCtrl.text.trim(),
                  _ssidCtrl.text.trim(),
                  _passCtrl.text,
                  _kColorHexes[_colorIdx],
                );
              },
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text(
                'Configurar automaticamente',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kNav,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _ColorPicker
// ══════════════════════════════════════════════════════════════════════════════

class _ColorPicker extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onSelect;

  const _ColorPicker({required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cor do ícone',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(_kColorHexes.length, (i) {
            final color    = _hexToColor(_kColorHexes[i]);
            final selected = selectedIndex == i;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: selected
                        ? Border.all(color: _kNav, width: 2.5)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: selected
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 16)
                      : null,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _ProvisioningDialog — fully automated: WiFi switch → config → reboot → discover
// ══════════════════════════════════════════════════════════════════════════════

enum _ProvStep {
  scanningAp,
  connectingAp,
  identifying,
  configuringWifi,
  rebooting,
  reconnecting,
  discovering,
  saving,
  done,
  error,
}

class _ProvisioningDialog extends StatefulWidget {
  final String deviceName;
  final String homeSsid;
  final String homePassword;
  final String iconColor;

  const _ProvisioningDialog({
    required this.deviceName,
    required this.homeSsid,
    required this.homePassword,
    required this.iconColor,
  });

  @override
  State<_ProvisioningDialog> createState() => _ProvisioningDialogState();
}

class _ProvisioningDialogState extends State<_ProvisioningDialog> {
  _ProvStep _step = _ProvStep.scanningAp;
  String?   _error;

  static const _kProgressSteps = [
    _ProvStep.scanningAp,
    _ProvStep.connectingAp,
    _ProvStep.identifying,
    _ProvStep.configuringWifi,
    _ProvStep.rebooting,
    _ProvStep.reconnecting,
    _ProvStep.discovering,
    _ProvStep.saving,
    _ProvStep.done,
  ];

  static String _label(_ProvStep s) => switch (s) {
    _ProvStep.scanningAp     => 'Procurar Shelly em modo AP',
    _ProvStep.connectingAp   => 'Ligar ao Shelly',
    _ProvStep.identifying    => 'Identificar dispositivo',
    _ProvStep.configuringWifi => 'Configurar WiFi no Shelly',
    _ProvStep.rebooting      => 'Reiniciar Shelly',
    _ProvStep.reconnecting   => 'Voltar ao WiFi de casa',
    _ProvStep.discovering    => 'Descobrir IP na rede',
    _ProvStep.saving         => 'Guardar na app',
    _ProvStep.done           => 'Concluído',
    _ProvStep.error          => '',
  };

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _step  = _ProvStep.scanningAp;
      _error = null;
    });

    String? discoveredIp;
    String rawMac = '';

    try {
      // ── 1. Scan for Shelly AP ─────────────────────────────────────────────
      await WiFiScan.instance.startScan();
      final networks = await WiFiScan.instance.getScannedResults();
      final shellyNet = networks.firstWhere(
        (n) => n.ssid.toLowerCase().startsWith('shelly'),
        orElse: () => throw Exception(
          'Nenhum Shelly encontrado nas redes WiFi disponíveis.\n'
          'Certifica-te que o dispositivo está em modo AP '
          '(LED vermelho piscante).',
        ),
      );

      // ── 2. Connect to Shelly AP ───────────────────────────────────────────
      setState(() => _step = _ProvStep.connectingAp);
      final connected = await WiFiForIoTPlugin.connect(
        shellyNet.ssid,
        joinOnce: true,
        security: NetworkSecurity.NONE,
        withInternet: false,
      );
      if (!connected) {
        throw Exception(
          'Não foi possível ligar ao WiFi do Shelly.\n'
          'Verifica se o dispositivo está em modo AP.',
        );
      }
      // Give Android time to settle on the new network
      await Future.delayed(const Duration(seconds: 2));

      // ── 3. Identify device ────────────────────────────────────────────────
      setState(() => _step = _ProvStep.identifying);
      final info = await ShellyProvisioningService.getDeviceInfo();
      rawMac = (info['mac'] as String?) ?? '';
      final normalizedMac = rawMac
          .replaceAll(RegExp(r'[^a-fA-F0-9]'), '')
          .toUpperCase();

      // ── 4. Configure home WiFi ────────────────────────────────────────────
      setState(() => _step = _ProvStep.configuringWifi);
      await ShellyProvisioningService.setWifiConfig(
        ssid: widget.homeSsid,
        password: widget.homePassword,
      );

      // ── 5. Reboot ─────────────────────────────────────────────────────────
      setState(() => _step = _ProvStep.rebooting);
      await ShellyProvisioningService.reboot();

      // ── 6. Reconnect phone to home WiFi ───────────────────────────────────
      setState(() => _step = _ProvStep.reconnecting);
      await WiFiForIoTPlugin.connect(
        widget.homeSsid,
        password: widget.homePassword.isNotEmpty ? widget.homePassword : null,
        security: widget.homePassword.isNotEmpty
            ? NetworkSecurity.WPA
            : NetworkSecurity.NONE,
        joinOnce: false,
        withInternet: true,
      );
      // Wait for Shelly to reboot and join home network
      await Future.delayed(const Duration(seconds: 12));

      // ── 7. Discover Shelly on home network ────────────────────────────────
      setState(() => _step = _ProvStep.discovering);
      final wifiIp = await NetworkInfo().getWifiIP();
      if (wifiIp == null) {
        throw Exception('Não foi possível obter o IP da rede local.');
      }
      final subnet = wifiIp.split('.').take(3).join('.');

      for (int attempt = 0; attempt < 3 && discoveredIp == null; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(seconds: 8));
        discoveredIp = await ShellyProvisioningService.discoverShellyIp(
          subnet: subnet,
          expectedMac:
              normalizedMac.isNotEmpty ? normalizedMac : null,
        );
      }

      if (discoveredIp == null) {
        throw Exception(
          'Shelly não encontrado na rede.\n'
          'Verifica se a password é correta e se o WiFi é 2.4 GHz.',
        );
      }

      // ── 8. Save ───────────────────────────────────────────────────────────
      setState(() => _step = _ProvStep.saving);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await UserService.addDevice(
        uid: uid,
        name: widget.deviceName,
        ip: discoveredIp,
        mac: rawMac,
        type: 'shelly-plug',
        online: true,
        iconColor: widget.iconColor,
      );
      await GamificationService.awardActionPoints(uid: uid, points: 5);

      setState(() => _step = _ProvStep.done);
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop(true);
    } on DeviceAlreadyExistsException catch (e) {
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
      setState(() {
        _step  = _ProvStep.error;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.wifi_tethering, size: 20),
          const SizedBox(width: 8),
          const Text('A configurar Shelly…',
              style: TextStyle(fontSize: 16)),
        ],
      ),
      content: _step == _ProvStep.error
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.red, size: 48),
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
              children: _kProgressSteps.map((s) {
                final idx        = _kProgressSteps.indexOf(s);
                final currentIdx = _kProgressSteps.indexOf(_step);
                final isDone     =
                    _step == _ProvStep.done || idx < currentIdx;
                final isCurrent  =
                    s == _step && _step != _ProvStep.done;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: isDone
                            ? const Icon(Icons.check_circle,
                                color: Colors.green, size: 20)
                            : isCurrent
                                ? const CircularProgressIndicator(
                                    strokeWidth: 2)
                                : const Icon(
                                    Icons.radio_button_unchecked,
                                    color: Colors.grey,
                                    size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _label(s),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDone
                              ? Colors.green
                              : isCurrent
                                  ? null
                                  : Colors.grey,
                          fontWeight:
                              isCurrent ? FontWeight.bold : null,
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kNav,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Tentar novamente'),
              ),
            ]
          : null,
    );
  }
}
