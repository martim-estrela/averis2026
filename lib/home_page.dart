import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  String _selectedDevice = 'Dispositivo 1';

  final _devices = <String>['Dispositivo 1', 'Dispositivo 2', 'Dispositivo 3'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardView(
        selectedDevice: _selectedDevice,
        devices: _devices,
        onDeviceChanged: (value) {
          setState(() => _selectedDevice = value);
        },
      ),
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
  final String selectedDevice;
  final List<String> devices;
  final ValueChanged<String> onDeviceChanged;

  const _DashboardView({
    required this.selectedDevice,
    required this.devices,
    required this.onDeviceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const currentPower = 500; // valor mock

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dashboard',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Dropdown Dispositivo
          DropdownButton<String>(
            value: selectedDevice,
            underline: const SizedBox.shrink(),
            items: devices
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (value) {
              if (value != null) onDeviceChanged(value);
            },
          ),

          const SizedBox(height: 16),

          // Card Consumo Atual
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Consumo Atual', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Text(
                      '$currentPower W',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Icon(Icons.bolt, size: 32, color: Colors.amber),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Gráfico placeholder
          Container(
            height: 200,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CustomPaint(painter: _SimpleLineChartPainter()),
          ),
        ],
      ),
    );
  }
}

/// Placeholder de gráfico simples (para não depender de libs externas).
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

    // Eixos simples
    canvas.drawLine(
      Offset(24, size.height - 24),
      Offset(size.width - 8, size.height - 24),
      paintAxis,
    );
    canvas.drawLine(Offset(24, 8), Offset(24, size.height - 24), paintAxis);

    // Pontos mock
    final points = <Offset>[
      Offset(24, size.height - 80),
      Offset(size.width * 0.35, size.height - 140),
      Offset(size.width * 0.5, size.height - 60),
      Offset(size.width * 0.7, size.height - 90),
      Offset(size.width * 0.9, size.height - 40),
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

// Vistas placeholder para as outras abas
class _HistoricoView extends StatelessWidget {
  const _HistoricoView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Histórico (a implementar)'));
  }
}

class _DispositivosView extends StatelessWidget {
  const _DispositivosView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Dispositivos (a implementar)'));
  }
}

class _PerfilView extends StatelessWidget {
  const _PerfilView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Perfil (a implementar)'));
  }
}
