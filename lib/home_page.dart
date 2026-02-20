import 'package:flutter/material.dart';
import 'profile_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'devices_page.dart';
import 'readings_chart_painter.dart';
import 'historic_page.dart';

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

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices') // ← subcoleção
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Sem dispositivos configurados.'));
        }

        final devices = snapshot.data!.docs;
        final firstDevice = devices.first;
        final firstDeviceData = firstDevice.data() as Map<String, dynamic>;

        // MOCK dados - depois vens buscar ao Shelly ou coleção measurements
        const int currentPowerW = 500;
        const double todayKwh = 2.4;
        const double todayCost = 0.52;
        const double monthKwh = 45.0;
        const double monthCost = 9.80;
        const double baselineMonthKwh = 60.0;
        const int monthlyPoints = 820;
        const int monthlyPointsGoal = 1000;
        const bool deviceOn = true;

        final double savingsKwh = (baselineMonthKwh - monthKwh).clamp(
          0.0,
          baselineMonthKwh,
        );
        final double savingsPercent = baselineMonthKwh == 0
            ? 0
            : (savingsKwh / baselineMonthKwh * 100);
        final double pointsProgress = monthlyPointsGoal == 0
            ? 0
            : (monthlyPoints / monthlyPointsGoal).clamp(0.0, 1.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Resumo em tempo real dos teus dispositivos.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),

              // Dropdown dispositivos
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Dispositivo',
                  border: OutlineInputBorder(),
                ),
                initialValue: firstDevice.id,
                items: devices.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Text(data['name'] ?? 'Sem nome'),
                  );
                }).toList(),
                onChanged: (_) {},
              ),

              const SizedBox(height: 16),

              // Cards métricas
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: 'Atual',
                      value: '$currentPowerW W',
                      icon: Icons.bolt,
                      iconColor: Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: 'Hoje',
                      value: '${todayKwh.toStringAsFixed(2)} kWh',
                      subtitle: '≈ ${todayCost.toStringAsFixed(2)} €',
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
                      title: 'Mês',
                      value: '${monthKwh.toStringAsFixed(1)} kWh',
                      subtitle: '≈ ${monthCost.toStringAsFixed(2)} €',
                      icon: Icons.calendar_month,
                      iconColor: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: 'Poupança',
                      value: '${savingsKwh.toStringAsFixed(1)} kWh',
                      subtitle: '${savingsPercent.toStringAsFixed(0)} %',
                      icon: Icons.trending_down,
                      iconColor: Colors.green,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Gráfico de consumo das últimas 24h
              Text(
                'Consumo últimas 24h',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('devices')
                    .doc(firstDevice.id)
                    .collection('readings')
                    .orderBy('timestamp', descending: true)
                    .limit(24)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(child: Text('Sem dados')),
                    );
                  }

                  final readings = snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return {
                      'powerW': data['powerW'] ?? 0.0,
                      'timestamp':
                          (data['timestamp'] as Timestamp?)?.toDate() ??
                          DateTime.now(),
                    };
                  }).toList();

                  return Container(
                    height: 200,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: CustomPaint(
                      painter: ReadingsChartPainter(
                        readings.cast<Map<String, dynamic>>(),
                      ),
                    ),
                  );
                },
              ),

              // Pontos
              Text(
                'Pontos este mês',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contributo do ${firstDeviceData['name'] ?? 'dispositivo'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: pointsProgress,
                        minHeight: 14,
                        backgroundColor: Colors.blue[100],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.blue.shade400,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$monthlyPoints pts'),
                        Text('Meta: $monthlyPointsGoal pts'),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],
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
