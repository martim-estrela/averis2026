import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_device_page.dart';
import 'services/gamification_service.dart';
import 'services/shelly_api.dart';
import 'services/smart_plug_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const _kNavColor = Color(0xFF0f1e3d);
const _kAddColor = Color(0xFF38d9a9);
const _kIconColors = [
  Color(0xFF38d9a9),
  Color(0xFF378add),
  Color(0xFFef9f27),
  Color(0xFFe24b4a),
  Color(0xFF7f77dd),
  Color(0xFFd85a30),
];

// ─────────────────────────────────────────────────────────────────────────────
// DevicesPage
// ─────────────────────────────────────────────────────────────────────────────

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final Map<String, bool> _expanded = {};
  final Map<String, bool> _toggleState = {};
  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  Future<void> _toggle(
    String deviceId,
    String ip,
    String type,
    bool newValue,
  ) async {
    setState(() => _toggleState[deviceId] = newValue);
    final success =
        await SmartPlugService.toggle(_uid, deviceId, ip, type, newValue);
    if (!mounted) return;
    if (success) {
      GamificationService.awardActionPoints(uid: _uid, points: 2);
      setState(() => _toggleState.remove(deviceId));
    } else {
      setState(() => _toggleState.remove(deviceId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não foi possível contactar o dispositivo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _kNavColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Dispositivos',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddDevicePage()),
            ),
            icon: const Icon(Icons.add, color: _kAddColor, size: 20),
            label: const Text(
              'Adicionar',
              style: TextStyle(
                  color: _kAddColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('devices')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return _buildEmptyState(context);

          final online = <QueryDocumentSnapshot>[];
          final offline = <QueryDocumentSnapshot>[];
          final indexMap = <String, int>{};

          for (var i = 0; i < docs.length; i++) {
            indexMap[docs[i].id] = i;
            final data = docs[i].data() as Map<String, dynamic>;
            if (data['online'] == true) {
              online.add(docs[i]);
            } else {
              offline.add(docs[i]);
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(devices: docs, userId: _uid),
              const SizedBox(height: 16),
              if (online.isNotEmpty) ...[
                _SectionHeader('Online', online.length),
                const SizedBox(height: 8),
                ...online.map(
                    (doc) => _buildCard(doc, indexMap[doc.id] ?? 0)),
              ],
              if (offline.isNotEmpty) ...[
                if (online.isNotEmpty) const SizedBox(height: 12),
                _SectionHeader('Offline', offline.length),
                const SizedBox(height: 8),
                ...offline.map(
                    (doc) => _buildCard(doc, indexMap[doc.id] ?? 0)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot doc, int colorIndex) {
    final data = doc.data() as Map<String, dynamic>;
    final isOn = _toggleState.containsKey(doc.id)
        ? _toggleState[doc.id]!
        : data['status'] == 'on';
    final isExpanded = _expanded[doc.id] ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _DeviceCard(
        key: ValueKey(doc.id),
        doc: doc,
        data: data,
        userId: _uid,
        colorIndex: colorIndex,
        isExpanded: isExpanded,
        isOn: isOn,
        onExpandToggle: () =>
            setState(() => _expanded[doc.id] = !isExpanded),
        onToggle: (v) {
          final ip = (data['ip'] as String?) ?? '';
          final type = (data['type'] as String?) ?? 'shelly-plug';
          _toggle(doc.id, ip, type, v);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.electrical_services_outlined,
                size: 72, color: Colors.grey[300]),
            const SizedBox(height: 20),
            Text(
              'Sem dispositivos',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Adiciona o teu primeiro Smart Plug para começar a monitorizar.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600], height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddDevicePage()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar o primeiro'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kNavColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary card
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatefulWidget {
  final List<QueryDocumentSnapshot> devices;
  final String userId;

  const _SummaryCard({required this.devices, required this.userId});

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  double _todayKwh = 0;
  bool _fetched = false;

  @override
  void initState() {
    super.initState();
    _fetchKwh();
  }

  @override
  void didUpdateWidget(_SummaryCard old) {
    super.didUpdateWidget(old);
    if (old.devices.length != widget.devices.length) _fetchKwh();
  }

  Future<void> _fetchKwh() async {
    final today = _dateKey(DateTime.now());
    final snaps = await Future.wait(
      widget.devices.map((doc) => FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('devices')
          .doc(doc.id)
          .collection('dailyStats')
          .doc(today)
          .get()),
    );
    final total = snaps.fold<double>(
      0,
      (acc, snap) =>
          acc + ((snap.data()?['estimatedKwh'] as num?)?.toDouble() ?? 0),
    );
    if (mounted) setState(() { _todayKwh = total; _fetched = true; });
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    int onlineCount = 0;
    double totalPower = 0;
    for (final doc in widget.devices) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['online'] == true) onlineCount++;
      final m = (data['lastMetrics'] as Map?)?.cast<String, dynamic>();
      totalPower += (m?['powerW'] as num?)?.toDouble() ?? 0;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          _SumItem(
            label: 'Total',
            value: '${widget.devices.length}',
            icon: Icons.devices,
            color: const Color(0xFF378add),
          ),
          _SumDivider(),
          _SumItem(
            label: 'Online',
            value: '$onlineCount',
            icon: Icons.wifi,
            color: _kAddColor,
          ),
          _SumDivider(),
          _SumItem(
            label: 'Potência',
            value: '${totalPower.toStringAsFixed(0)} W',
            icon: Icons.bolt,
            color: const Color(0xFFef9f27),
          ),
          _SumDivider(),
          _SumItem(
            label: 'Hoje',
            value: _fetched
                ? '${_todayKwh.toStringAsFixed(2)} kWh'
                : '… kWh',
            icon: Icons.today,
            color: const Color(0xFF7f77dd),
          ),
        ],
      ),
    );
  }
}

class _SumItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SumItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _SumDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 40, color: Colors.grey[200]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader(this.title, this.count);

  @override
  Widget build(BuildContext context) {
    final isOnline = title == 'Online';
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: isOnline ? _kAddColor : Colors.grey,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _kNavColor,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceCard
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;
  final String userId;
  final int colorIndex;
  final bool isExpanded;
  final bool isOn;
  final VoidCallback onExpandToggle;
  final ValueChanged<bool> onToggle;

  const _DeviceCard({
    super.key,
    required this.doc,
    required this.data,
    required this.userId,
    required this.colorIndex,
    required this.isExpanded,
    required this.isOn,
    required this.onExpandToggle,
    required this.onToggle,
  });

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  double _kwhToday = 0;
  double _costToday = 0;
  bool _detailsLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.isExpanded) _fetchDetails();
  }

  @override
  void didUpdateWidget(_DeviceCard old) {
    super.didUpdateWidget(old);
    if (!old.isExpanded && widget.isExpanded && !_detailsLoaded) {
      _fetchDetails();
    }
  }

  Future<void> _fetchDetails() async {
    final today = _dateKey(DateTime.now());
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('devices')
        .doc(widget.doc.id)
        .collection('dailyStats')
        .doc(today)
        .get();
    final d = snap.data();
    if (mounted) {
      setState(() {
        _kwhToday = (d?['estimatedKwh'] as num?)?.toDouble() ?? 0;
        _costToday = (d?['estimatedCost'] as num?)?.toDouble() ?? 0;
        _detailsLoaded = true;
      });
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _formatLastSeen(dynamic ts) {
    if (ts == null) return 'desconhecido';
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'agora mesmo';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showMoreOptions(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    final capturedContext = context;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _DeviceBottomSheet(
        doc: widget.doc,
        data: widget.data,
        onEditName: () {
          Navigator.pop(sheetCtx);
          _editName(capturedContext);
        },
        onReboot: () {
          Navigator.pop(sheetCtx);
          _reboot(messenger);
        },
        onDelete: () {
          Navigator.pop(sheetCtx);
          _confirmDelete(capturedContext);
        },
      ),
    );
  }

  void _editName(BuildContext ctx) {
    final controller = TextEditingController(
      text: (widget.data['name'] as String?) ?? '',
    );
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Editar nome'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome do dispositivo'),
          onSubmitted: (_) => Navigator.pop(dCtx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await widget.doc.reference.update({'name': name});
              }
              if (dCtx.mounted) Navigator.pop(dCtx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _reboot(ScaffoldMessengerState messenger) async {
    final ip = (widget.data['ip'] as String?) ?? '';
    if (ip.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('IP do dispositivo desconhecido.')));
      return;
    }
    try {
      await ShellyApi.reboot(ip);
      messenger.showSnackBar(
          const SnackBar(content: Text('Dispositivo a reiniciar…')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(
              content: Text('Não foi possível reiniciar o dispositivo.')));
    }
  }

  void _confirmDelete(BuildContext ctx) {
    final name = (widget.data['name'] as String?) ?? 'dispositivo';
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Eliminar dispositivo'),
        content: Text('Tem a certeza que quer eliminar "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              await widget.doc.reference.delete();
              if (dCtx.mounted) Navigator.pop(dCtx);
            },
            child: const Text('Eliminar',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.data['name'] as String?) ?? 'Dispositivo';
    final ip = (widget.data['ip'] as String?) ?? '—';
    final type = (widget.data['type'] as String?) ?? 'shelly-plug';
    final isOnline = widget.data['online'] == true;
    final m =
        (widget.data['lastMetrics'] as Map?)?.cast<String, dynamic>();
    final powerW = (m?['powerW'] as num?)?.toDouble() ?? 0.0;
    final accent = _kIconColors[widget.colorIndex % _kIconColors.length];

    return Opacity(
      opacity: isOnline ? 1.0 : 0.6,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Collapsed header ─────────────────────────────────────────
            InkWell(
              onTap: widget.onExpandToggle,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.electrical_services,
                          color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$ip · $type',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!isOnline)
                            Text(
                              'último contacto: ${_formatLastSeen(widget.data['lastSeenAt'])}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.red[400]),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isOnline)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${powerW.toStringAsFixed(0)} W',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: powerW > 0
                                  ? const Color(0xFFef9f27)
                                  : Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 2),
                          _StatusDot(online: true),
                        ],
                      )
                    else
                      _StatusDot(online: false),
                    Switch(
                      value: widget.isOn,
                      onChanged: isOnline ? widget.onToggle : null,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                    Icon(
                      widget.isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            // ── Expanded section ─────────────────────────────────────────
            if (widget.isExpanded) ...[
              const Divider(height: 1, indent: 14, endIndent: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: _DeviceMetricsGrid(
                  data: widget.data,
                  kwhToday: _kwhToday,
                  costToday: _costToday,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Últimas 2h',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 90,
                      child: _DeviceMiniChart(
                        deviceId: widget.doc.id,
                        userId: widget.userId,
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _showMoreOptions(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Mais opções',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 13),
                      ),
                      Icon(Icons.chevron_right,
                          color: Colors.grey[400], size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool online;
  const _StatusDot({required this.online});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: online ? _kAddColor : Colors.red,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          online ? 'Online' : 'Offline',
          style: TextStyle(
            fontSize: 11,
            color: online ? _kAddColor : Colors.red,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceMetricsGrid
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceMetricsGrid extends StatelessWidget {
  final Map<String, dynamic> data;
  final double kwhToday;
  final double costToday;

  const _DeviceMetricsGrid({
    required this.data,
    required this.kwhToday,
    required this.costToday,
  });

  @override
  Widget build(BuildContext context) {
    final m = (data['lastMetrics'] as Map?)?.cast<String, dynamic>();
    final powerW = (m?['powerW'] as num?)?.toDouble() ?? 0.0;
    final voltageV = (m?['voltageV'] as num?)?.toDouble() ?? 0.0;
    final currentA =
        ((m?['currentMa'] as num?)?.toDouble() ?? 0.0) / 1000;
    // Support both totalKwh (kWh) and totalWh (Wh) field names
    final rawTotal = (m?['totalKwh'] as num?)?.toDouble() ??
        ((m?['totalWh'] as num?)?.toDouble() ?? 0.0) / 1000;

    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _MetricTile(
            label: 'Potência',
            value: powerW.toStringAsFixed(1),
            unit: 'W',
            color: const Color(0xFFef9f27)),
        _MetricTile(
            label: 'Tensão',
            value: voltageV.toStringAsFixed(1),
            unit: 'V',
            color: const Color(0xFF378add)),
        _MetricTile(
            label: 'Corrente',
            value: currentA.toStringAsFixed(2),
            unit: 'A',
            color: const Color(0xFF7f77dd)),
        _MetricTile(
            label: 'kWh hoje',
            value: kwhToday.toStringAsFixed(3),
            unit: 'kWh',
            color: _kAddColor),
        _MetricTile(
            label: 'Custo hoje',
            value: costToday.toStringAsFixed(2),
            unit: '€',
            color: Colors.green),
        _MetricTile(
            label: 'Total acum.',
            value: rawTotal.toStringAsFixed(2),
            unit: 'kWh',
            color: const Color(0xFFd85a30)),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500),
          ),
          RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: color),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceMiniChart
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceMiniChart extends StatelessWidget {
  final String deviceId;
  final String userId;

  const _DeviceMiniChart({
    required this.deviceId,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .doc(deviceId)
          .collection('readings')
          .orderBy('timestamp', descending: true)
          .limit(24)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'Sem dados de consumo',
              style: TextStyle(color: Colors.grey[400], fontSize: 11),
            ),
          );
        }

        final docs = snap.data!.docs.reversed.toList();
        final spots = <FlSpot>[];
        for (var i = 0; i < docs.length; i++) {
          final d = docs[i].data() as Map<String, dynamic>;
          spots.add(FlSpot(
              i.toDouble(), (d['powerW'] as num?)?.toDouble() ?? 0));
        }

        if (spots.length < 2) {
          return Center(
            child: Text(
              'A recolher dados…',
              style: TextStyle(color: Colors.grey[400], fontSize: 11),
            ),
          );
        }

        final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
        final niceMax = maxY < 10
            ? 10.0
            : maxY < 500
                ? (maxY / 50).ceil() * 50.0
                : (maxY / 200).ceil() * 200.0;

        return LineChart(
          LineChartData(
            minY: 0,
            maxY: niceMax,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(
              leftTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: _kNavColor,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: _kNavColor.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceBottomSheet
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceBottomSheet extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;
  final VoidCallback onEditName;
  final VoidCallback onReboot;
  final VoidCallback onDelete;

  const _DeviceBottomSheet({
    required this.doc,
    required this.data,
    required this.onEditName,
    required this.onReboot,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] as String?) ?? 'Dispositivo';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar nome'),
              onTap: onEditName,
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reiniciar dispositivo'),
              onTap: onReboot,
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Eliminar dispositivo',
                  style: TextStyle(color: Colors.red)),
              onTap: onDelete,
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
