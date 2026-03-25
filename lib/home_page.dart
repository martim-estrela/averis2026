import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_page.dart';
import 'devices_page.dart';
import 'historic_page.dart';
import 'services/gamification_service.dart';
import 'services/shelly_api.dart';
import 'services/shelly_polling_service.dart';
import 'services/smart_plug_service.dart';
import 'services/user_service.dart';

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
      const _DashboardView(),
      const _HistoricoView(),
      const _DispositivosView(),
      const _PerfilView(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
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
// Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  String? _selectedDeviceId;

  @override
  void dispose() {
    ShellyPollingService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Sessão inválida'));
    }

    return StreamBuilder<QuerySnapshot>(
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
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.electrical_services_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text('Sem dispositivos'),
                SizedBox(height: 8),
                Text(
                  'Adiciona um Smart Plug no separador Dispositivos',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final devices = snapshot.data!.docs;
        final docList = devices
            .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();

        // Seleciona o dispositivo atual ou o primeiro da lista
        final selectedDevice = docList.firstWhere(
          (d) => d.id == _selectedDeviceId,
          orElse: () => docList.first,
        );
        final deviceData = selectedDevice.data();
        final ip = (deviceData['ip'] as String?) ?? '';
        final deviceType = (deviceData['type'] as String?) ?? 'shelly-plug';

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Dispositivo',
                  border: OutlineInputBorder(),
                ),
                initialValue: _selectedDeviceId ?? docList.first.id,
                items: devices.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final isOnline = data['online'] == true;
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text((data['name'] as String?) ?? 'Sem nome'),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedDeviceId = value),
              ),
            ),

            // Métricas em tempo real
            Expanded(
              child: _LiveMetricsCard(
                deviceId: selectedDevice.id,
                shellyIp: ip,
                userId: userId,
                deviceType: deviceType,
              ),
            ),

            // Gráfico histórico
            Expanded(child: _ReadingsChart(deviceId: selectedDevice.id)),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card com métricas LIVE
// ─────────────────────────────────────────────────────────────────────────────

class _LiveMetricsCard extends StatefulWidget {
  final String deviceId;
  final String userId;
  final String shellyIp;
  final String deviceType;

  const _LiveMetricsCard({
    required this.deviceId,
    required this.userId,
    required this.shellyIp,
    required this.deviceType,
  });

  @override
  State<_LiveMetricsCard> createState() => _LiveMetricsCardState();
}

class _LiveMetricsCardState extends State<_LiveMetricsCard> {
  ShellyMetrics _metrics = ShellyMetrics.empty();
  Timer? _timer;
  int _lastFirestoreWrite = 0;
  double _energyPrice = 0.22;
  int _streakDias = 0;
  bool _isOnline = false;
  bool _isToggling = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchLive();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLive());
    // Processar gamificação diária (só executa uma vez por dia)
    GamificationService.processDailyForUser(widget.userId);
  }

  Future<void> _loadUserData() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    final data = snap.data();
    final price =
        (data?['settings']?['energyPrice'] as num?)?.toDouble() ?? 0.22;
    final streak = (data?['streakDias'] as num?)?.toInt() ?? 0;
    if (mounted) {
      setState(() {
        _energyPrice = price;
        _streakDias = streak;
      });
    }
  }

  Future<void> _fetchLive() async {
    if (widget.shellyIp.isEmpty) return;
    try {
      final newMetrics = await ShellyApi.getMetrics(widget.shellyIp);
      if (!mounted) return;
      setState(() {
        _metrics = newMetrics;
        _isOnline = true;
      });

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastFirestoreWrite > 30000) {
        _lastFirestoreWrite = now;
        await UserService.saveReading(
          uid: widget.userId,
          deviceId: widget.deviceId,
          powerW: newMetrics.powerW,
          voltageV: newMetrics.voltageV,
          currentMa: newMetrics.currentMa,
          frequencyHz: newMetrics.frequencyHz,
          totalWh: newMetrics.totalWh,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isOnline = false);
    }
  }

  Future<void> _toggle() async {
    if (_isToggling || !_isOnline) return;
    setState(() => _isToggling = true);
    try {
      await SmartPlugService.toggle(
        widget.userId,
        widget.deviceId,
        widget.shellyIp,
        widget.deviceType,
        !_metrics.isOn,
      );
      // +2 XP por interagir com o dispositivo via app
      GamificationService.awardActionPoints(uid: widget.userId, points: 2);
      await _fetchLive();
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todayKwh = _metrics.totalKwh.clamp(0.0, double.infinity);
    final cost = todayKwh * _energyPrice;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Título + badge online/offline
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isOnline
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isOnline ? Colors.green : Colors.red,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _isOnline ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isOnline ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Banner de streak (só aparece quando streak >= 2)
          if (_streakDias >= 2) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    '$_streakDias dias consecutivos abaixo da média!',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.deepOrange,
                    ),
                  ),
                ],
              ),
            ),
          ],

          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Atual',
                  value: '${_metrics.powerW.toStringAsFixed(0)} W',
                  icon: Icons.bolt,
                  iconColor: Colors.amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Hoje',
                  value: '${todayKwh.toStringAsFixed(2)} kWh',
                  subtitle: '${cost.toStringAsFixed(2)} €',
                  icon: Icons.today,
                  iconColor: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Volts',
                  value: '${_metrics.voltageV.toStringAsFixed(0)} V',
                  icon: Icons.flashlight_on,
                  iconColor: Colors.deepPurple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Corrente',
                  value: '${_metrics.currentMa.toStringAsFixed(0)} mA',
                  icon: Icons.trending_up,
                  iconColor: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DetailRow(
            'Frequência',
            '${_metrics.frequencyHz.toStringAsFixed(1)} Hz',
            Icons.speed,
          ),
          _DetailRow(
            'Total acumulado',
            '${_metrics.totalKwh.toStringAsFixed(2)} kWh',
            Icons.electrical_services,
          ),
          const SizedBox(height: 16),

          // Botão ligar/desligar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isOnline && !_isToggling ? _toggle : null,
              icon: _isToggling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_metrics.isOn ? Icons.power_off : Icons.power),
              label: Text(_metrics.isOn ? 'Desligar' : 'Ligar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _metrics.isOn ? Colors.red[400] : Colors.green[500],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gráfico histórico
// ─────────────────────────────────────────────────────────────────────────────

class _ReadingsChart extends StatelessWidget {
  final String deviceId;

  const _ReadingsChart({required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('devices')
          .doc(deviceId)
          .collection('readings')
          .orderBy('timestamp', descending: true)
          .limit(24)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            height: 200,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('Sem dados de consumo')),
          );
        }

        final readings = snapshot.data!.docs
            .map(
              (doc) =>
                  ((doc.data() as Map<String, dynamic>)['powerW'] as num?)
                      ?.toDouble() ??
                  0.0,
            )
            .toList()
            .reversed
            .toList();

        return Container(
          height: 240,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
            ],
          ),
          child: CustomPaint(
            size: Size.infinite,
            painter: PowerChartPainter(readings),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PowerChartPainter
// ─────────────────────────────────────────────────────────────────────────────

class PowerChartPainter extends CustomPainter {
  final List<double> powerReadings;

  PowerChartPainter(this.powerReadings);

  @override
  void paint(Canvas canvas, Size size) {
    if (powerReadings.isEmpty) return;

    final paintLine = Paint()
      ..color = Colors.blue.shade400
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final paintFill = Paint()
      ..color = Colors.blue.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final paintGrid = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    final maxPower = powerReadings.reduce(math.max).clamp(1.0, double.infinity);
    const padding = EdgeInsets.fromLTRB(40, 20, 20, 40);

    // Grid horizontal
    for (int i = 0; i <= 4; i++) {
      final y = padding.top + (size.height - padding.vertical) * (1 - i / 4);
      canvas.drawLine(
        Offset(padding.left, y),
        Offset(size.width - padding.right, y),
        paintGrid,
      );
    }

    // Caso especial: só 1 leitura
    if (powerReadings.length == 1) {
      final x = padding.left + (size.width - padding.horizontal) / 2;
      final y =
          padding.top +
          (size.height - padding.vertical) *
              (1 - (powerReadings[0] / maxPower).clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(x, y),
        4,
        Paint()
          ..color = Colors.blue.shade400
          ..style = PaintingStyle.fill,
      );
    } else {
      final path = Path();
      final fillPath = Path();

      for (int i = 0; i < powerReadings.length; i++) {
        final x =
            padding.left +
            (size.width - padding.horizontal) * i / (powerReadings.length - 1);
        final y =
            padding.top +
            (size.height - padding.vertical) *
                (1 - (powerReadings[i] / maxPower).clamp(0.0, 1.0));

        if (i == 0) {
          path.moveTo(x, y);
          fillPath.moveTo(x, y);
        } else {
          path.lineTo(x, y);
          fillPath.lineTo(x, y);
        }
      }

      fillPath.lineTo(size.width - padding.right, size.height - padding.bottom);
      fillPath.lineTo(padding.left, size.height - padding.bottom);
      fillPath.close();

      canvas.drawPath(fillPath, paintFill);
      canvas.drawPath(path, paintLine);
    }

    // Label eixo Y
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${maxPower.round()}W',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(5, padding.top - 5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets auxiliares
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;

  const _StatCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: iconColor.withOpacity(0.15),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailRow(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vistas do BottomNavigationBar
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
