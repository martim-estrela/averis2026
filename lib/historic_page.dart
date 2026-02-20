import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;

class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  String _periodo = 'mes'; // hoje, 7dias, mes
  String _deviceId = 'todos';
  final DateTime _inicioPeriodo = DateTime(2026, 2, 1); // mock

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _showExportDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltros(userId),
          Expanded(child: _buildConteudo(userId)),
        ],
      ),
    );
  }

  Widget _buildFiltros(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .snapshots(),
      builder: (context, snapshot) {
        final devices = snapshot.data?.docs ?? [];
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'hoje', label: Text('Hoje')),
                  ButtonSegment(value: '7dias', label: Text('7 dias')),
                  ButtonSegment(value: 'mes', label: Text('Mês')),
                ],
                selected: {_periodo},
                onSelectionChanged: (selection) =>
                    setState(() => _periodo = selection.first),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'todos', label: Text('Todos')),
                  ...devices.map(
                    (doc) => ButtonSegment(
                      value: doc.id,
                      label: Text(
                        (doc.data() as Map<String, dynamic>)['name'] ??
                            'Sem nome',
                      ),
                    ),
                  ),
                ],
                selected: {_deviceId},
                onSelectionChanged: (selection) =>
                    setState(() => _deviceId = selection.first),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConteudo(String userId) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(icon: Icon(Icons.show_chart), text: 'Gráfico'),
              Tab(icon: Icon(Icons.list), text: 'Dias'),
              Tab(icon: Icon(Icons.trending_up), text: 'Ranking'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildGraficoTab(userId),
                _buildDiasTab(userId),
                _buildRankingTab(userId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraficoTab(String userId) {
    return StreamBuilder<List<DailyStats>>(
      stream: _getDailyStatsStream(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Sem dados para mostrar'));
        }

        final dailyStats = snapshot.data!;
        final totalKwh = dailyStats.map((d) => d.kwh).reduce((a, b) => a + b);
        final baselineKwh = totalKwh * 1.2; // 20% mais seria "normal"
        final poupancaKwh = baselineKwh - totalKwh;
        final poupancaPercent = (poupancaKwh / baselineKwh * 100).clamp(
          0.0,
          100.0,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    'Total',
                    '${totalKwh.toStringAsFixed(1)} kWh',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    'Poupança',
                    '${poupancaKwh.toStringAsFixed(1)} kWh',
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: CustomPaint(
                painter: DailyChartPainter(dailyStats, baselineKwh),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDiasTab(String userId) {
    return StreamBuilder<List<DailyStats>>(
      stream: _getDailyStatsStream(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final dias = snapshot.data!;
        if (dias.isEmpty) return const Center(child: Text('Sem dados'));

        final mediaKwh =
            dias.map((d) => d.kwh).reduce((a, b) => a + b) / dias.length;

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: dias.length,
          itemBuilder: (context, i) {
            final dia = dias[i];
            final isAboveMedia = dia.kwh > mediaKwh;
            final pontos = _calculatePontos(dia.kwh, mediaKwh);

            return Card(
              color: isAboveMedia ? Colors.red.shade50 : null,
              child: ListTile(
                leading: CircleAvatar(child: Text('${dia.diaDia}')),
                title: Text('${dia.kwh.toStringAsFixed(1)} kWh'),
                subtitle: Text(
                  '${(dia.kwh * 0.22).toStringAsFixed(2)} € • +${pontos.round()} pts',
                ),
                trailing: isAboveMedia
                    ? const Chip(
                        label: Text(
                          '↑ Acima média',
                          style: TextStyle(fontSize: 10),
                        ),
                        backgroundColor: Colors.red,
                      )
                    : null,
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 8),
        );
      },
    );
  }

  Widget _buildRankingTab(String userId) {
    return StreamBuilder<List<DeviceStats>>(
      stream: _getDeviceRankingStream(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final ranking = snapshot.data!;

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: ranking.length,
          itemBuilder: (context, i) {
            final device = ranking[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(device.name),
                trailing: Text(
                  '${device.kwh.toStringAsFixed(1)} kWh\n${device.percent?.toStringAsFixed(1)}%',
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 8),
        );
      },
    );
  }

  Stream<List<DailyStats>> _getDailyStatsStream(String userId) {
    return FirebaseFirestore.instance
        .collectionGroup('readings')
        .where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_getInicioPeriodo()),
        )
        .snapshots()
        .asyncMap((snapshot) async {
          final readings = snapshot.docs.map((doc) {
            final data = doc.data();
            return Reading(
              powerW: (data['powerW'] ?? 0).toDouble(),
              timestamp:
                  (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            );
          }).toList();

          return _aggregateByDay(readings);
        });
  }

  Stream<List<DeviceStats>> _getDeviceRankingStream(String userId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('devices')
        .snapshots()
        .asyncMap((devicesSnapshot) async {
          final devices = devicesSnapshot.docs;
          final List<DeviceStats> stats = [];

          for (final deviceDoc in devices) {
            final deviceData = deviceDoc.data();
            final deviceName = deviceData['name'] ?? 'Sem nome';

            final readingsSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('devices')
                .doc(deviceDoc.id)
                .collection('readings')
                .where(
                  'timestamp',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(
                    _getInicioPeriodo(),
                  ),
                )
                .get();

            final totalKwh = readingsSnapshot.docs
                .map((doc) => (doc.data()['totalKwh'] ?? 0).toDouble())
                .reduce((a, b) => a + b);

            stats.add(DeviceStats(name: deviceName, kwh: totalKwh));
          }

          final totalGeral = stats.map((d) => d.kwh).reduce((a, b) => a + b);
          return stats
            ..sort((a, b) => b.kwh.compareTo(a.kwh))
            ..asMap().entries.map((e) {
              final device = e.value;
              device.percent = totalGeral > 0
                  ? (device.kwh / totalGeral * 100)
                  : 0;
              return device;
            }).toList();
        });
  }

  DateTime _getInicioPeriodo() {
    final now = DateTime.now();
    switch (_periodo) {
      case 'hoje':
        return DateTime(now.year, now.month, now.day);
      case '7dias':
        return now.subtract(const Duration(days: 7));
      case 'mes':
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  List<DailyStats> _aggregateByDay(List<Reading> readings) {
    final Map<String, List<Reading>> days = {};

    for (final reading in readings) {
      final dayKey =
          '${reading.timestamp.year}-${reading.timestamp.month}-${reading.timestamp.day}';
      days.putIfAbsent(dayKey, () => []).add(reading);
    }

    final List<DailyStats> result = [];
    days.forEach((dayKey, dayReadings) {
      final totalPower = dayReadings
          .map((r) => r.powerW)
          .reduce((a, b) => a + b);
      final avgPower = totalPower / dayReadings.length;
      final dia = DateTime.parse(dayKey);

      result.add(
        DailyStats(
          diaDia: dia.day,
          kwh: avgPower * 24 / 1000, // aproximação
        ),
      );
    });

    return result..sort((a, b) => b.diaDia.compareTo(a.diaDia));
  }

  int _calculatePontos(double kwhAtual, double mediaMensal) {
    final poupancaKwh = (mediaMensal - kwhAtual).clamp(0.0, double.infinity);
    final percentReducao = (poupancaKwh / mediaMensal * 100).clamp(0.0, 100.0);
    return (percentReducao * 1.0).round(); // fator = 1
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exportar'),
        content: const Text('Funcionalidade em desenvolvimento'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// Models
class Reading {
  final double powerW;
  final DateTime timestamp;
  Reading({required this.powerW, required this.timestamp});
}

class DailyStats {
  final int diaDia;
  final double kwh;
  DailyStats({required this.diaDia, required this.kwh});
}

class DeviceStats {
  String name;
  double kwh;
  double? percent;
  DeviceStats({required this.name, required this.kwh});
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? color;

  const _StatCard(this.title, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    );
  }
}

class DailyChartPainter extends CustomPainter {
  final List<DailyStats> dailyStats;
  final double baselineKwh;

  DailyChartPainter(this.dailyStats, this.baselineKwh);

  @override
  void paint(Canvas canvas, Size size) {
    if (dailyStats.isEmpty) return;

    final maxKwh = math.max(
      baselineKwh,
      dailyStats.map((d) => d.kwh).reduce(math.max),
    );

    // Baseline
    final baselineY =
        size.height * 0.7 - (baselineKwh / maxKwh * size.height * 0.5);
    canvas.drawLine(
      Offset(40, baselineY),
      Offset(size.width - 20, baselineY),
      Paint()
        ..color = Colors.grey
        ..strokeWidth = 2,
    );

    // Barras e pontos
    for (int i = 0; i < dailyStats.length; i++) {
      final stat = dailyStats[i];
      final x = 40 + i * ((size.width - 60) / (dailyStats.length - 1));
      final y = size.height * 0.7 - (stat.kwh / maxKwh * size.height * 0.5);

      // Barra
      canvas.drawRect(
        Rect.fromLTWH(x - 15, y, 30, size.height * 0.7 - y),
        Paint()..color = Colors.blue.withOpacity(0.7),
      );

      // Ponto
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = Colors.blue);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
