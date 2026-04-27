import 'dart:async';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_page.dart';
import 'devices_page.dart';
import 'historic_page.dart';
import 'settings_page.dart';
import 'services/gamification_service.dart';
import 'services/prefs_service.dart';
import 'services/shelly_polling_service.dart';
import 'services/smart_plug_service.dart';
import 'widgets/setup_checklist.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Root – BottomNavigationBar shell
// ─────────────────────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardView(
        onNavigateToDevices: () => setState(() => _selectedIndex = 2),
      ),
      const _HistoricoView(),
      const _DispositivosView(),
      const _PerfilView(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'Histórico',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.devices_other_outlined),
            activeIcon: Icon(Icons.devices_other),
            label: 'Dispositivos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI data model
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardStats {
  final double todayKwh;
  final double monthKwh;
  final double energyPrice;

  const _DashboardStats({
    required this.todayKwh,
    required this.monthKwh,
    required this.energyPrice,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard view
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardView extends StatefulWidget {
  final VoidCallback? onNavigateToDevices;
  const _DashboardView({this.onNavigateToDevices});

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  final _db = FirebaseFirestore.instance;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  StreamSubscription? _devicesSub;
  StreamSubscription? _userSub;
  StreamSubscription? _notifSub;
  Timer? _chartTimer;

  bool _devicesLoaded   = false;
  List<QueryDocumentSnapshot> _devices = [];
  Map<String, dynamic> _userData = {};
  List<QueryDocumentSnapshot> _notifDocs = [];

  final List<FlSpot> _chartSpots = [];
  double _chartX = 0;
  static const int _maxChartSpots = 20;

  final Map<String, bool> _optimisticOn = {};
  Future<_DashboardStats>? _statsFuture;

  // ── Setup / celebration state ─────────────────────────────────────────────
  bool _setupDone        = true;  // default true avoids flash on load
  bool _showCelebration  = false;
  bool _dismissedBanner  = false;

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid == null) return;
    ShellyPollingService.start(uid);
    GamificationService.processDailyForUser(uid);
    _statsFuture = _fetchStats(uid);
    _subscribeDevices(uid);
    _subscribeUser(uid);
    _subscribeNotifications(uid);
    _chartTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _sampleChart(),
    );
    _loadSetupDone();
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _userSub?.cancel();
    _notifSub?.cancel();
    _chartTimer?.cancel();
    ShellyPollingService.stop();
    super.dispose();
  }

  Future<void> _loadSetupDone() async {
    final done = await PrefsService.isSetupDone();
    if (mounted) setState(() => _setupDone = done);
  }

  void _onSetupComplete() {
    setState(() {
      _setupDone       = true;
      _showCelebration = true;
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showCelebration = false);
    });
  }

  void _subscribeDevices(String uid) {
    _devicesSub = _db
        .collection('users')
        .doc(uid)
        .collection('devices')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _devices = snap.docs;
        _devicesLoaded = true;
        for (final doc in snap.docs) {
          final data = doc.data();
          if (_optimisticOn[doc.id] == (data['status'] == 'on')) {
            _optimisticOn.remove(doc.id);
          }
        }
      });
    });
  }

  void _subscribeUser(String uid) {
    _userSub = _db.collection('users').doc(uid).snapshots().listen((snap) {
      if (!mounted || !snap.exists) return;
      setState(() => _userData = snap.data()!);
    });
  }

  void _subscribeNotifications(String uid) {
    _notifSub = _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _notifDocs = snap.docs);
    });
  }

  void _sampleChart() {
    if (!mounted || _devices.isEmpty) return;
    double total = 0;
    for (final doc in _devices) {
      final data = doc.data() as Map<String, dynamic>;
      final m = (data['lastMetrics'] as Map?)?.cast<String, dynamic>();
      total += (m?['powerW'] as num?)?.toDouble() ?? 0;
    }
    setState(() {
      _chartSpots.add(FlSpot(_chartX, total));
      _chartX += 1;
      if (_chartSpots.length > _maxChartSpots) _chartSpots.removeAt(0);
    });
  }

  Future<_DashboardStats> _fetchStats(String uid) async {
    final now        = DateTime.now();
    final today      = _dateKey(now);
    final monthStart =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-01';

    final userSnap = await _db.collection('users').doc(uid).get();
    final energyPrice =
        (userSnap.data()?['settings']?['energyPrice'] as num?)?.toDouble() ??
            0.22;

    final devicesSnap =
        await _db.collection('users').doc(uid).collection('devices').get();

    double todayKwh = 0;
    double monthKwh = 0;

    await Future.wait(devicesSnap.docs.map((deviceDoc) async {
      final statsSnap = await deviceDoc.reference
          .collection('dailyStats')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: monthStart)
          .where(FieldPath.documentId, isLessThanOrEqualTo: today)
          .get();
      for (final stat in statsSnap.docs) {
        final kwh = (stat.data()['estimatedKwh'] as num?)?.toDouble() ?? 0;
        monthKwh += kwh;
        if (stat.id == today) todayKwh += kwh;
      }
    }));

    return _DashboardStats(
      todayKwh: todayKwh,
      monthKwh: monthKwh,
      energyPrice: energyPrice,
    );
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _toggle(
      String deviceId, String ip, String type, bool newValue) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _optimisticOn[deviceId] = newValue);
    try {
      await SmartPlugService.toggle(uid, deviceId, ip, type, newValue);
      GamificationService.awardActionPoints(uid: uid, points: 2);
    } catch (_) {
      if (mounted) setState(() => _optimisticOn.remove(deviceId));
    }
  }

  Future<void> _markAllRead() async {
    final batch = _db.batch();
    for (final doc in _notifDocs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['read'] != true) {
        batch.update(doc.reference, {'read': true});
      }
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) return const Center(child: Text('Sessão inválida'));
    if (!_devicesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_devices.isEmpty) return _buildEmptyState(context);
    return _buildDashboard(context);
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Column(
      children: [
        _TopBar(
          devices: const [],
          userData: _userData,
          isEmpty: true,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SetupChecklist(
                  uid: _uid!,
                  onSetupComplete: _onSetupComplete,
                ),
                const SizedBox(height: 16),
                _EmptyDashboard(
                  onAddDevice: widget.onNavigateToDevices,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Full dashboard ─────────────────────────────────────────────────────────

  Widget _buildDashboard(BuildContext context) {
    final activeCount =
        _devices.where((d) => (d.data() as Map)['status'] == 'on').length;

    return Column(
      children: [
        _TopBar(devices: _devices, userData: _userData),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Celebration banner
                if (_showCelebration) ...[
                  _SetupCompleteCelebration(
                    onDismiss: () =>
                        setState(() => _showCelebration = false),
                  ),
                  const SizedBox(height: 16),
                ],

                // Setup incomplete banner
                if (!_setupDone && !_dismissedBanner) ...[
                  _SetupBanner(
                    userData: _userData,
                    uid: _uid!,
                    onDismiss: () =>
                        setState(() => _dismissedBanner = true),
                  ),
                  const SizedBox(height: 16),
                ],

                FutureBuilder<_DashboardStats>(
                  future: _statsFuture,
                  builder: (context, snap) => _KpiGrid(
                    stats: snap.data ??
                        const _DashboardStats(
                          todayKwh: 0,
                          monthKwh: 0,
                          energyPrice: 0.22,
                        ),
                    activeDevices: activeCount,
                  ),
                ),
                const SizedBox(height: 16),
                _RealtimeChart(spots: List.of(_chartSpots)),
                const SizedBox(height: 16),
                _DeviceList(
                  devices: _devices,
                  optimisticOn: _optimisticOn,
                  onToggle: _toggle,
                ),
                const SizedBox(height: 16),
                _XpCard(userData: _userData),
                if (_notifDocs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _AlertsCard(
                    notifDocs: _notifDocs,
                    onMarkAllRead: _markAllRead,
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TopBar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final List<QueryDocumentSnapshot> devices;
  final Map<String, dynamic> userData;
  final bool isEmpty;

  const _TopBar({
    required this.devices,
    required this.userData,
    this.isEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting =
        now.hour < 12 ? 'Bom dia' : now.hour < 18 ? 'Boa tarde' : 'Boa noite';
    final firstName =
        (FirebaseAuth.instance.currentUser?.displayName ?? '').split(' ').first;

    double totalPower = 0;
    for (final doc in devices) {
      final data = doc.data() as Map<String, dynamic>;
      final m = (data['lastMetrics'] as Map?)?.cast<String, dynamic>();
      totalPower += (m?['powerW'] as num?)?.toDouble() ?? 0;
    }

    final streakDias = (userData['streakDias'] as num?)?.toInt() ?? 0;

    return Container(
      color: const Color(0xFF0f1e3d),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstName.isNotEmpty ? '$greeting, $firstName' : greeting,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isEmpty
                          ? '— W'
                          : '${totalPower.toStringAsFixed(0)} W',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        'consumo total agora',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Sem dispositivos',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.greenAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              if (streakDias >= 2) ...[
                const SizedBox(height: 6),
                Text(
                  '🔥 $streakDias dias',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI grid
// ─────────────────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final _DashboardStats stats;
  final int activeDevices;

  const _KpiGrid({required this.stats, required this.activeDevices});

  @override
  Widget build(BuildContext context) {
    final costToday = stats.todayKwh * stats.energyPrice;
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _KpiCard(
          label: 'Hoje',
          value: '${stats.todayKwh.toStringAsFixed(2)} kWh',
          icon: Icons.today,
          iconColor: Colors.blue,
        ),
        _KpiCard(
          label: 'Custo hoje',
          value: '${costToday.toStringAsFixed(2)} €',
          icon: Icons.euro,
          iconColor: Colors.green,
        ),
        _KpiCard(
          label: 'Ativos agora',
          value: '$activeDevices',
          icon: Icons.power,
          iconColor: Colors.orange,
        ),
        _KpiCard(
          label: 'Este mês',
          value: '${stats.monthKwh.toStringAsFixed(1)} kWh',
          icon: Icons.calendar_month,
          iconColor: const Color(0xFF7C3AED),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Real-time power chart
// ─────────────────────────────────────────────────────────────────────────────

class _RealtimeChart extends StatelessWidget {
  final List<FlSpot> spots;

  const _RealtimeChart({required this.spots});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              'Potência em tempo real (W)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
            ),
          ),
          SizedBox(
            height: 160,
            child: spots.length >= 2
                ? LineChart(_buildChartData())
                : Center(
                    child: Text(
                      'A recolher dados…',
                      style:
                          TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  LineChartData _buildChartData() {
    final maxY = spots
        .map((s) => s.y)
        .reduce(math.max)
        .clamp(1.0, double.infinity);
    final niceMax = maxY < 10
        ? 10.0
        : maxY < 500
            ? (maxY / 50).ceil() * 50.0
            : (maxY / 200).ceil() * 200.0;

    final firstX = spots.first.x;
    final lastX  = spots.last.x;

    return LineChartData(
      minY: 0,
      maxY: niceMax,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: niceMax / 4,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (ts) => ts.map((s) => LineTooltipItem(
            '${s.y.toStringAsFixed(0)} W',
            const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          )).toList(),
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            interval: niceMax / 4,
            getTitlesWidget: (v, _) => Text(
              v.toInt().toString(),
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 16,
            interval: 1,
            getTitlesWidget: (v, _) {
              if ((v - lastX).abs() < 0.5) {
                return Text('agora',
                    style: TextStyle(fontSize: 9, color: Colors.grey[500]));
              }
              if ((v - firstX).abs() < 0.5) {
                final secs = ((lastX - firstX) * 10).round();
                final mins = (secs / 60).ceil();
                return Text('-${mins}m',
                    style: TextStyle(fontSize: 9, color: Colors.grey[500]));
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: const Color(0xFF0f1e3d),
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF0f1e3d).withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Device list
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceList extends StatelessWidget {
  final List<QueryDocumentSnapshot> devices;
  final Map<String, bool> optimisticOn;
  final Future<void> Function(String, String, String, bool) onToggle;

  const _DeviceList({
    required this.devices,
    required this.optimisticOn,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Dispositivos',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        ...devices.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final isOn = optimisticOn.containsKey(doc.id)
              ? optimisticOn[doc.id]!
              : data['status'] == 'on';
          return _DeviceRow(
            deviceId: doc.id,
            data: data,
            isOn: isOn,
            onToggle: onToggle,
          );
        }),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final String deviceId;
  final Map<String, dynamic> data;
  final bool isOn;
  final Future<void> Function(String, String, String, bool) onToggle;

  const _DeviceRow({
    required this.deviceId,
    required this.data,
    required this.isOn,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final name     = (data['name'] as String?) ?? 'Dispositivo';
    final isOnline = data['online'] == true;
    final ip       = (data['ip'] as String?) ?? '';
    final type     = (data['type'] as String?) ?? 'shelly-plug';
    final m        = (data['lastMetrics'] as Map?)?.cast<String, dynamic>();
    final powerW   = (m?['powerW'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isOn
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.electrical_services,
              color: isOn ? Colors.green[700] : Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      isOnline
                          ? (isOn
                              ? '${powerW.toStringAsFixed(0)} W'
                              : 'Desligado')
                          : 'Offline',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Switch(
            value: isOn,
            onChanged:
                isOnline ? (v) => onToggle(deviceId, ip, type, v) : null,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// XP progress card
// ─────────────────────────────────────────────────────────────────────────────

class _XpCard extends StatelessWidget {
  final Map<String, dynamic> userData;

  const _XpCard({required this.userData});

  @override
  Widget build(BuildContext context) {
    final nivel      = (userData['nivel'] as num?)?.toInt() ?? 1;
    final pontos     = (userData['pontos'] as num?)?.toInt() ?? 0;
    final pontosTotal = (userData['pontosTotal'] as num?)?.toInt() ?? 0;
    final streakDias = (userData['streakDias'] as num?)?.toInt() ?? 0;
    final maxPontos  = GamificationService.pontosParaProximoNivel(nivel);
    final progress   =
        maxPontos > 0 ? (pontos / maxPontos).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0f1e3d), Color(0xFF1a3366)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$nivel',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nível $nivel',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '$pontos / $maxPontos XP',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (streakDias >= 2)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        '$streakDias dias',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.amber),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'XP total: $pontosTotal',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11),
              ),
              Text(
                nivel < 6
                    ? 'Faltam ${maxPontos - pontos} XP'
                    : 'Nível máximo!',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Alerts card
// ─────────────────────────────────────────────────────────────────────────────

class _AlertsCard extends StatelessWidget {
  final List<QueryDocumentSnapshot> notifDocs;
  final VoidCallback onMarkAllRead;

  const _AlertsCard({
    required this.notifDocs,
    required this.onMarkAllRead,
  });

  IconData _icon(String type) {
    switch (type) {
      case 'level_up':
        return Icons.emoji_events;
      case 'achievement':
        return Icons.star;
      case 'device_offline':
        return Icons.wifi_off;
      case 'device_online':
        return Icons.wifi;
      case 'high_consumption':
        return Icons.warning_amber;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'level_up':
        return Colors.amber;
      case 'achievement':
        return const Color(0xFF7C3AED);
      case 'device_offline':
        return Colors.red;
      case 'device_online':
        return Colors.green;
      case 'high_consumption':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread =
        notifDocs.where((d) => (d.data() as Map)['read'] != true).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Text(
                  'Alertas',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (unread > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
                const Spacer(),
                if (unread > 0)
                  TextButton(
                    onPressed: onMarkAllRead,
                    child: const Text('Marcar lidos',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...notifDocs.map((doc) {
            final n     = doc.data() as Map<String, dynamic>;
            final type  = (n['type'] as String?) ?? '';
            final title = (n['title'] as String?) ?? '';
            final body  = (n['body'] as String?) ?? '';
            final isRead = n['read'] == true;
            final c = _color(type);

            return Container(
              color: isRead ? null : c.withValues(alpha: 0.04),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_icon(type), color: c, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                fontWeight: isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                              ),
                        ),
                        Text(
                          body,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmptyDashboard — card shown below SetupChecklist when no devices
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyDashboard extends StatelessWidget {
  final VoidCallback? onAddDevice;
  const _EmptyDashboard({this.onAddDevice});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF38d9a9).withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.electrical_services_outlined,
              size: 32,
              color: Color(0xFF38d9a9),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nenhum dispositivo ainda',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Adiciona o teu Shelly Plug S Gen 3 para começar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onAddDevice,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('+ Adicionar dispositivo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38d9a9),
                foregroundColor: const Color(0xFF04342c),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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

// ─────────────────────────────────────────────────────────────────────────────
// _SetupBanner — shown at top of dashboard when setup not done
// ─────────────────────────────────────────────────────────────────────────────

class _SetupBanner extends StatelessWidget {
  final Map<String, dynamic> userData;
  final String uid;
  final VoidCallback onDismiss;

  const _SetupBanner({
    required this.userData,
    required this.uid,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final goalKwh =
        (userData['goals']?['monthlyKwhTarget'] as num?)?.toDouble() ?? 0.0;
    final price =
        (userData['settings']?['energyPrice'] as num?)?.toDouble() ?? 0.22;
    final tipo =
        (userData['settings']?['energyContract']?['tipo'] as String?) ??
            'simples';

    final goalDone   = goalKwh > 0;
    final tariffDone = price != 0.22 || tipo != 'simples';

    final doneCount  = 2 + (goalDone ? 1 : 0) + (tariffDone ? 1 : 0);
    final remaining  = 4 - doneCount;

    if (remaining <= 0) return const SizedBox.shrink();

    final nextLabel  = !goalDone
        ? 'Definir meta de consumo'
        : 'Configurar tarifa de energia';
    final actionLabel = !goalDone ? 'Definir' : 'Configurar';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0f1e3d),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1e3a6e)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF38d9a9).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: Color(0xFF38d9a9),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Falta só $remaining passo${remaining == 1 ? '' : 's'}!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  nextLabel,
                  style: const TextStyle(
                    color: Color(0x80FFFFFF),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _handleAction(context, goalDone),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF38d9a9),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                color: Color(0x66FFFFFF),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, bool goalDone) {
    if (!goalDone) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF0f1e3d),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _QuickGoalSheet(uid: uid),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsPage()),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _QuickGoalSheet — inline goal-setter for the setup banner
// ─────────────────────────────────────────────────────────────────────────────

class _QuickGoalSheet extends StatefulWidget {
  final String uid;
  const _QuickGoalSheet({required this.uid});

  @override
  State<_QuickGoalSheet> createState() => _QuickGoalSheetState();
}

class _QuickGoalSheetState extends State<_QuickGoalSheet> {
  double _kwh  = 150;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .update({'goals.monthlyKwhTarget': _kwh});
    if (mounted) Navigator.of(context).pop();
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Meta de consumo mensal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    color: Color(0x66FFFFFF), size: 20),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '${_kwh.toStringAsFixed(0)} kWh / mês',
              style: const TextStyle(
                color: Color(0xFF38d9a9),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Slider(
            value: _kwh,
            min: 0,
            max: 300,
            divisions: 60,
            activeColor: const Color(0xFF38d9a9),
            inactiveColor: Colors.white.withValues(alpha: 0.15),
            onChanged: (v) => setState(() => _kwh = v),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38d9a9),
                foregroundColor: const Color(0xFF04342c),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF04342c),
                      ),
                    )
                  : const Text(
                      'Guardar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SetupCompleteCelebration — shown for 5s when all setup steps done
// ─────────────────────────────────────────────────────────────────────────────

class _SetupCompleteCelebration extends StatefulWidget {
  final VoidCallback onDismiss;
  const _SetupCompleteCelebration({required this.onDismiss});

  @override
  State<_SetupCompleteCelebration> createState() =>
      _SetupCompleteCelebrationState();
}

class _SetupCompleteCelebrationState
    extends State<_SetupCompleteCelebration> {
  double _opacity = 1.0;

  @override
  void initState() {
    super.initState();
    // Begin fade-out at 4s so the widget visually fades before being removed
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _opacity = 0.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 800),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0f3d1f), Color(0xFF0f2847)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.green.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configuração completa! 🎉',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Ganhou +50 XP de bónus de boas-vindas',
                    style: TextStyle(
                      color: Color(0x80FFFFFF),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: widget.onDismiss,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  color: Color(0x66FFFFFF),
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab wrappers
// ─────────────────────────────────────────────────────────────────────────────

class _HistoricoView extends StatelessWidget {
  const _HistoricoView();
  @override
  Widget build(BuildContext context) => const HistoricoPage();
}

class _DispositivosView extends StatelessWidget {
  const _DispositivosView();
  @override
  Widget build(BuildContext context) => const DevicesPage();
}

class _PerfilView extends StatelessWidget {
  const _PerfilView();
  @override
  Widget build(BuildContext context) => const ProfilePage();
}
