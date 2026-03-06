import 'dart:async';

import 'package:flutter/material.dart';
import 'profile_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'devices_page.dart';
import 'readings_chart_painter.dart';
import 'historic_page.dart';
import 'services/readings_service.dart';
import 'services/shelly_api.dart';

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
        onTap: (index) {
          setState(() => _selectedIndex = index);
        },
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

class _DashboardView extends StatefulWidget {
  const _DashboardView();
  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  String? _selectedDeviceId;

  @override
  void dispose() {
    ReadingsService.stop();
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
          return const Center(child: Text('Sem dispositivos'));
        }

        final devices = snapshot.data!.docs;
        final firstDevice = devices.first;

        // Inicia captura automática (só 1x)
        if (_selectedDeviceId == null) {
          _selectedDeviceId = firstDevice.id;

          // Monta lista de TODOS devices com IP
          final allDevices = devices
              .map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return {'id': doc.id, 'ip': data['ip'] as String?};
              })
              .where((d) => d['ip'] != null)
              .cast<Map<String, String>>()
              .toList();

          if (allDevices.isNotEmpty) {
            ReadingsService.startAutoCapture(
              userId: userId,
              devices: allDevices,
            );
          }
        }

        final selectedDevice = devices.firstWhere(
          (d) => d.id == _selectedDeviceId!,
          orElse: () => devices.first, // fallback
        );
        final deviceData = selectedDevice.data() as Map<String, dynamic>;
        final ip = deviceData['ip'] as String?;

        return Column(
          children: [
            // Dropdown para trocar device
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Dispositivo',
                  border: OutlineInputBorder(),
                ),
                value: _selectedDeviceId,
                items: devices.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Text(data['name'] ?? 'Sem nome'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDeviceId = value;
                  });
                },
              ),
            ),

            // Live Metrics
            Expanded(
              child: _LiveMetricsCard(
                deviceId: selectedDevice.id,
                shellyIp: ip ?? '',
                userId: userId,
              ),
            ),

            // Gráfico histórico
            Expanded(
              child: _ReadingsChart(
                deviceId: selectedDevice.id,
                userId: userId,
              ),
            ),
          ],
        );
      },
    );
  }
}

// Card com métricas LIVE da Shelly
class _LiveMetricsCard extends StatefulWidget {
  final String deviceId, userId, shellyIp;
  const _LiveMetricsCard({
    required this.deviceId,
    required this.userId,
    required this.shellyIp,
  });

  @override
  State<_LiveMetricsCard> createState() => _LiveMetricsCardState();
}

class _LiveMetricsCardState extends State<_LiveMetricsCard> {
  ShellyMetrics metrics = ShellyMetrics.empty();
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _fetchLive();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLive());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLive() async {
    if (widget.shellyIp.isEmpty) return;
    try {
      final newMetrics = await ShellyApi.getMetrics(widget.shellyIp);
      if (mounted) {
        setState(() => metrics = newMetrics);
        // Grava no Firestore também
        await ReadingsService.capture(
          userId: widget.userId,
          deviceId: widget.deviceId,
          shellyIp: widget.shellyIp,
        );
      }
    } catch (e) {
      print('Live metrics error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayKwh = (metrics.totalKwh / 1000).clamp(0.0, double.infinity);
    final monthKwh = todayKwh * 30; // estimativa
    final cost = todayKwh * 0.22;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Dashboard',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Cards principais
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Atual',
                  value: '${metrics.powerW.toStringAsFixed(0)} W',
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
                  value: '${metrics.voltageV.toStringAsFixed(0)} V',
                  icon: Icons.flashlight_on,
                  iconColor: Colors.deepPurple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'mA',
                  value: '${metrics.currentMa.toStringAsFixed(0)} mA',
                  icon: Icons.trending_up,
                  iconColor: Colors.green,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          _DetailRow(
            'Frequência',
            '${metrics.frequencyHz.toStringAsFixed(1)} Hz',
            Icons.speed,
          ),
          _DetailRow(
            'Total',
            '${metrics.totalKwh.toStringAsFixed(2)} kWh',
            Icons.electrical_services,
          ),
        ],
      ),
    );
  }
}

// Gráfico histórico (usa dados do Firestore)
class _ReadingsChart extends StatelessWidget {
  final String deviceId, userId;
  const _ReadingsChart({required this.deviceId, required this.userId});

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
          .limit(48)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('Sem dados ainda...')),
          );
        }

        final readings = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'powerW': data['powerW'] ?? 0.0,
            'timestamp':
                (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          };
        }).toList();

        return Container(
          height: 240,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
            ],
          ),
          child: CustomPaint(
            painter: ReadingsChartPainter(
              readings.cast<Map<String, dynamic>>(),
            ),
          ),
        );
      },
    );
  }
}

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

class _SimpleLineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintAxis = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1;
    final paintLine = Paint()
      ..color = const Color(0xFF38A3F1)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Eixos
    canvas.drawLine(
      Offset(24, size.height - 24),
      Offset(size.width - 8, size.height - 24),
      paintAxis,
    );
    canvas.drawLine(Offset(24, 8), Offset(24, size.height - 24), paintAxis);

    // Pontos
    final points = <Offset>[
      Offset(24, size.height - 80),
      Offset(size.width * 0.25, size.height - 140),
      Offset(size.width * 0.45, size.height - 90),
      Offset(size.width * 0.7, size.height - 120),
      Offset(size.width * 0.9, size.height - 60),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Adiciona no FINAL do ficheiro, após _ReadingsChart
class _DetailRow extends StatelessWidget {
  final String label, value;
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

class _HistoricoView extends StatelessWidget {
  const _HistoricoView();
  @override
  Widget build(BuildContext context) {
    return const HistoricoPage();
  }
}

class _DispositivosView extends StatelessWidget {
  const _DispositivosView();

  @override
  Widget build(BuildContext context) {
    return const DevicesPage();
  }
}

class _PerfilView extends StatelessWidget {
  const _PerfilView();

  @override
  Widget build(BuildContext context) {
    return const ProfilePage();
  }
}
