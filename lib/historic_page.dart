import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  // Intervalo de datas — por defeito o mês atual
  DateTime _dataInicio = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _dataFim = DateTime.now();
  String _deviceId = 'todos';

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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Intervalo de datas
              Row(
                children: [
                  Expanded(
                    child: _DatePickerButton(
                      label: 'De',
                      date: _dataInicio,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dataInicio,
                          firstDate: DateTime(2020),
                          lastDate: _dataFim,
                        );
                        if (picked != null) {
                          setState(() => _dataInicio = picked);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DatePickerButton(
                      label: 'Até',
                      date: _dataFim,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dataFim,
                          firstDate: _dataInicio,
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          // Inclui o dia completo (até às 23:59:59)
                          setState(
                            () => _dataFim = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              23,
                              59,
                              59,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Dropdown dispositivos
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Dispositivo',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                initialValue: _deviceId,
                items: [
                  const DropdownMenuItem(value: 'todos', child: Text('Todos')),
                  ...devices.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return DropdownMenuItem<String>(
                      value: doc.id,
                      child: Text(data['name'] ?? 'Sem nome'),
                    );
                  }),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _deviceId = value);
                },
              ),
              const SizedBox(height: 4),
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
          const TabBar(
            tabs: [
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
        final baselineKwh = totalKwh * 1.2;
        final poupancaKwh = baselineKwh - totalKwh;

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
                size: Size.infinite,
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
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

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
          // FIX 2: Parâmetros do separatorBuilder eram ambos '_', o que é
          // inválido em Dart — dois parâmetros não podem ter o mesmo nome.
          // Corrigido para '(_, __)'.
          separatorBuilder: (_, _) => const SizedBox(height: 8),
        );
      },
    );
  }

  Widget _buildRankingTab(String userId) {
    return StreamBuilder<List<DeviceStats>>(
      stream: _getDeviceRankingStream(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
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
          // FIX 2 (cont.): mesmo problema no ranking
          separatorBuilder: (_, _) => const SizedBox(height: 8),
        );
      },
    );
  }

  Stream<List<DailyStats>> _getDailyStatsStream(String userId) {
    final inicio = Timestamp.fromDate(_dataInicio);
    final fim = Timestamp.fromDate(_dataFim);

    if (_deviceId == 'todos') {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .snapshots()
          .asyncMap((devicesSnap) async {
            final List<Reading> allReadings = [];
            for (final deviceDoc in devicesSnap.docs) {
              final snap = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('devices')
                  .doc(deviceDoc.id)
                  .collection('readings')
                  .where('timestamp', isGreaterThanOrEqualTo: inicio)
                  .where('timestamp', isLessThanOrEqualTo: fim)
                  .get();

              for (final doc in snap.docs) {
                final data = doc.data();
                allReadings.add(
                  Reading(
                    powerW: (data['powerW'] ?? 0).toDouble(),
                    timestamp:
                        (data['timestamp'] as Timestamp?)?.toDate() ??
                        DateTime.now(),
                  ),
                );
              }
            }
            return _aggregateByDay(allReadings);
          });
    } else {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .doc(_deviceId)
          .collection('readings')
          .where('timestamp', isGreaterThanOrEqualTo: inicio)
          .where('timestamp', isLessThanOrEqualTo: fim)
          .snapshots()
          .map((snap) {
            final readings = snap.docs.map((doc) {
              final data = doc.data();
              return Reading(
                powerW: (data['powerW'] ?? 0).toDouble(),
                timestamp:
                    (data['timestamp'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
              );
            }).toList();
            return _aggregateByDay(readings);
          });
    }
  }

  Stream<List<DeviceStats>> _getDeviceRankingStream(String userId) {
    final inicio = Timestamp.fromDate(_dataInicio);
    final fim = Timestamp.fromDate(_dataFim);

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
                .where('timestamp', isGreaterThanOrEqualTo: inicio)
                .where('timestamp', isLessThanOrEqualTo: fim)
                .get();

            final totalKwh = readingsSnapshot.docs.isEmpty
                ? 0.0
                : readingsSnapshot.docs
                      .map((doc) => (doc.data()['totalKwh'] ?? 0).toDouble())
                      .fold(0.0, (a, b) => a + b);

            stats.add(DeviceStats(name: deviceName, kwh: totalKwh));
          }

          final totalGeral = stats.isEmpty
              ? 0.0
              : stats.fold(0.0, (sum, d) => sum + d.kwh);

          stats.sort((a, b) => b.kwh.compareTo(a.kwh));

          for (final device in stats) {
            device.percent = totalGeral > 0
                ? (device.kwh / totalGeral * 100)
                : 0.0;
          }

          return stats;
        });
  }

  List<DailyStats> _aggregateByDay(List<Reading> readings) {
    final Map<String, List<Reading>> days = {};

    for (final reading in readings) {
      final dayKey =
          '${reading.timestamp.year}-${reading.timestamp.month.toString().padLeft(2, '0')}-${reading.timestamp.day.toString().padLeft(2, '0')}';
      days.putIfAbsent(dayKey, () => []).add(reading);
    }

    final List<DailyStats> result = [];
    days.forEach((dayKey, dayReadings) {
      final totalPower = dayReadings
          .map((r) => r.powerW)
          .fold(0.0, (a, b) => a + b);
      final avgPower = totalPower / dayReadings.length;
      final dia = DateTime.parse(dayKey);

      result.add(DailyStats(diaDia: dia.day, kwh: avgPower * 24 / 1000));
    });

    // Ordenação ascendente para o gráfico ficar cronológico (dia 1 → dia 31)
    return result..sort((a, b) => a.diaDia.compareTo(b.diaDia));
  }

  int _calculatePontos(double kwhAtual, double mediaMensal) {
    if (mediaMensal == 0) return 0;
    final poupancaKwh = (mediaMensal - kwhAtual).clamp(0.0, double.infinity);
    final percentReducao = (poupancaKwh / mediaMensal * 100).clamp(0.0, 100.0);
    return (percentReducao * 1.0).round();
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exportar relatório'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Exportar PDF'),
              subtitle: const Text('Partilhar ou guardar no dispositivo'),
              onTap: () {
                Navigator.pop(context);
                _exportPdf(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    // Mostra loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('A gerar PDF...'),
          ],
        ),
      ),
    );

    try {
      // Recolhe os dados do período selecionado
      final inicio = Timestamp.fromDate(_dataInicio);
      final fim = Timestamp.fromDate(_dataFim);

      final List<Reading> allReadings = [];
      List<String> deviceNames = [];

      // Busca devices
      final devicesSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .get();

      for (final deviceDoc in devicesSnap.docs) {
        final deviceData = deviceDoc.data();
        final name = deviceData['name'] ?? 'Sem nome';

        if (_deviceId != 'todos' && deviceDoc.id != _deviceId) continue;

        deviceNames.add(name);

        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('devices')
            .doc(deviceDoc.id)
            .collection('readings')
            .where('timestamp', isGreaterThanOrEqualTo: inicio)
            .where('timestamp', isLessThanOrEqualTo: fim)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          allReadings.add(
            Reading(
              powerW: (data['powerW'] ?? 0).toDouble(),
              timestamp:
                  (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            ),
          );
        }
      }

      final dailyStats = _aggregateByDay(allReadings);
      final totalKwh = dailyStats.isEmpty
          ? 0.0
          : dailyStats.map((d) => d.kwh).fold(0.0, (a, b) => a + b);
      final custoTotal = totalKwh * 0.22;
      final mediaKwh = dailyStats.isEmpty ? 0.0 : totalKwh / dailyStats.length;

      // Formata datas
      String fmtDate(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

      // Gera o PDF
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Relatório de Consumo',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                  pw.Text(
                    'Averis',
                    style: pw.TextStyle(fontSize: 14, color: PdfColors.grey600),
                  ),
                ],
              ),
              pw.Divider(color: PdfColors.blue800, thickness: 1.5),
              pw.SizedBox(height: 4),
            ],
          ),
          build: (context) => [
            // Info do período
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Período',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        '${fmtDate(_dataInicio)}  →  ${fmtDate(_dataFim)}',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Dispositivo(s)',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        deviceNames.isEmpty ? 'Todos' : deviceNames.join(', '),
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Gerado em',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        fmtDate(DateTime.now()),
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Resumo
            pw.Text(
              'Resumo',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                _pdfStatBox(
                  'Total Consumido',
                  '${totalKwh.toStringAsFixed(2)} kWh',
                ),
                pw.SizedBox(width: 12),
                _pdfStatBox(
                  'Custo Estimado',
                  '${custoTotal.toStringAsFixed(2)} €',
                ),
                pw.SizedBox(width: 12),
                _pdfStatBox(
                  'Média Diária',
                  '${mediaKwh.toStringAsFixed(2)} kWh/dia',
                ),
                pw.SizedBox(width: 12),
                _pdfStatBox('Dias com dados', '${dailyStats.length}'),
              ],
            ),

            pw.SizedBox(height: 24),

            // Tabela por dia
            pw.Text(
              'Consumo por Dia',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),

            if (dailyStats.isEmpty)
              pw.Text(
                'Sem dados para o período selecionado.',
                style: const pw.TextStyle(color: PdfColors.grey600),
              )
            else
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                },
                children: [
                  // Cabeçalho
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.blue800,
                    ),
                    children: [
                      _pdfTableHeader('Dia'),
                      _pdfTableHeader('Consumo (kWh)'),
                      _pdfTableHeader('Custo (€)'),
                      _pdfTableHeader('vs Média'),
                    ],
                  ),
                  // Linhas de dados
                  ...dailyStats.asMap().entries.map((entry) {
                    final i = entry.key;
                    final d = entry.value;
                    final diffPct = mediaKwh > 0
                        ? ((d.kwh - mediaKwh) / mediaKwh * 100)
                        : 0.0;
                    final isAbove = d.kwh > mediaKwh;
                    final bgColor = i % 2 == 0
                        ? PdfColors.white
                        : PdfColors.grey100;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: bgColor),
                      children: [
                        _pdfTableCell('Dia ${d.diaDia}'),
                        _pdfTableCell(d.kwh.toStringAsFixed(3)),
                        _pdfTableCell((d.kwh * 0.22).toStringAsFixed(2)),
                        _pdfTableCell(
                          '${isAbove ? '+' : ''}${diffPct.toStringAsFixed(1)}%',
                          color: isAbove
                              ? PdfColors.red700
                              : PdfColors.green700,
                        ),
                      ],
                    );
                  }),
                  // Totais
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                    children: [
                      _pdfTableCell('Total', bold: true),
                      _pdfTableCell(totalKwh.toStringAsFixed(3), bold: true),
                      _pdfTableCell(custoTotal.toStringAsFixed(2), bold: true),
                      _pdfTableCell('—', bold: true),
                    ],
                  ),
                ],
              ),

            pw.SizedBox(height: 24),

            // Nota de rodapé
            pw.Divider(color: PdfColors.grey400),
            pw.Text(
              'Nota: O custo é calculado com base na tarifa de 0,22 €/kWh. '
              'Os valores de consumo são estimativas baseadas na potência média registada.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
      );

      if (context.mounted) Navigator.pop(context); // fecha loading

      // Partilha o PDF
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            'averis_consumo_${fmtDate(_dataInicio).replaceAll('/', '-')}_${fmtDate(_dataFim).replaceAll('/', '-')}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // fecha loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helpers para células da tabela PDF
  pw.Widget _pdfStatBox(String label, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.blue200),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _pdfTableCell(String text, {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
        ),
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
        color: color != null ? color!.withOpacity(0.1) : Colors.blue.shade50,
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

class _DatePickerButton extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DatePickerButton({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final formatted =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(formatted, style: Theme.of(context).textTheme.bodyMedium),
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

    // FIX 6: Divisão por zero quando dailyStats.length == 1.
    // A expressão '(size.width - 60) / (dailyStats.length - 1)' = 0/0 = NaN.
    // Quando há apenas 1 barra, centramo-la; caso contrário usamos o spread normal.
    for (int i = 0; i < dailyStats.length; i++) {
      final stat = dailyStats[i];
      final double x;
      if (dailyStats.length == 1) {
        x = size.width / 2;
      } else {
        x = 40 + i * ((size.width - 60) / (dailyStats.length - 1));
      }
      final y = size.height * 0.7 - (stat.kwh / maxKwh * size.height * 0.5);

      canvas.drawRect(
        Rect.fromLTWH(x - 15, y, 30, size.height * 0.7 - y),
        Paint()..color = Colors.blue.withOpacity(0.7),
      );

      canvas.drawCircle(Offset(x, y), 5, Paint()..color = Colors.blue);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
