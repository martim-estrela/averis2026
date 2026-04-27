import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

double _niceYInterval(double maxVal) {
  if (maxVal <= 0) return 1.0;
  const steps = [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0];
  final target = maxVal / 4;
  return steps.firstWhere((s) => s >= target, orElse: () => 500.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _HistoricData {
  final Map<String, double> current;
  final Map<String, double> previous;
  final Map<String, double> curMonth;
  final Map<String, double> prevMonth;
  final List<_DeviceStat> deviceTotals;

  const _HistoricData({
    required this.current,
    required this.previous,
    required this.curMonth,
    required this.prevMonth,
    required this.deviceTotals,
  });

  factory _HistoricData.empty() => const _HistoricData(
        current: {},
        previous: {},
        curMonth: {},
        prevMonth: {},
        deviceTotals: [],
      );
}

class _DeviceStat {
  final String name;
  final double kwh;
  const _DeviceStat({required this.name, required this.kwh});
}

// ─────────────────────────────────────────────────────────────────────────────
// Period
// ─────────────────────────────────────────────────────────────────────────────

enum _Period { dias7, mesAtual, mesAnterior, meses3, personalizado }

extension _PeriodLabel on _Period {
  String get label => switch (this) {
        _Period.dias7 => '7 dias',
        _Period.mesAtual => 'Este mês',
        _Period.mesAnterior => 'Mês anterior',
        _Period.meses3 => '3 meses',
        _Period.personalizado => 'Personalizado',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  _Period _period = _Period.mesAtual;
  DateTime _dataInicio = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _dataFim = DateTime.now();
  String _selectedDeviceId = 'todos';
  double _energyPrice = 0.22;
  double _monthlyKwhTarget = 0.0;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _devices = [];
  bool _tableExpanded = false;
  Future<_HistoricData> _dataFuture = Future.value(_HistoricData.empty());

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final results = await Future.wait([
      FirebaseFirestore.instance.collection('users').doc(uid).get(),
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .get(),
    ]);

    final userSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final devicesSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;

    if (!mounted) return;
    setState(() {
      _energyPrice =
          (userSnap.data()?['settings']?['energyPrice'] as num?)?.toDouble() ??
              0.22;
      _monthlyKwhTarget =
          (userSnap.data()?['goals']?['monthlyKwhTarget'] as num?)
                  ?.toDouble() ??
              0.0;
      _devices = devicesSnap.docs;
    });
    _reload();
  }

  void _reload() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _tableExpanded = false;
      _dataFuture = _fetchData(uid);
    });
  }

  Future<void> _setPeriod(_Period p) async {
    final now = DateTime.now();
    DateTime start, end;

    switch (p) {
      case _Period.dias7:
        end = now;
        start = now.subtract(const Duration(days: 6));
      case _Period.mesAtual:
        start = DateTime(now.year, now.month, 1);
        end = now;
      case _Period.mesAnterior:
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(now.year, now.month, 0);
      case _Period.meses3:
        start = DateTime(now.year, now.month - 2, 1);
        end = now;
      case _Period.personalizado:
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: now,
          initialDateRange: DateTimeRange(start: _dataInicio, end: _dataFim),
        );
        if (range == null || !mounted) return;
        start = range.start;
        end = range.end;
    }

    setState(() {
      _period = p;
      _dataInicio = start;
      _dataFim = DateTime(end.year, end.month, end.day, 23, 59, 59);
    });
    _reload();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int _daysBetween(DateTime a, DateTime b) => b.difference(a).inDays + 1;

  // ── Data fetching ─────────────────────────────────────────────────────────

  Future<Map<String, double>> _fetchKwhByDate(
    String uid,
    String deviceId,
    String startKey,
    String endKey,
  ) async {
    final db = FirebaseFirestore.instance;
    final result = <String, double>{};
    final ids = deviceId == 'todos'
        ? _devices.map((d) => d.id).toList()
        : [deviceId];

    for (final did in ids) {
      final snap = await db
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(did)
          .collection('dailyStats')
          .orderBy(FieldPath.documentId)
          .startAt([startKey])
          .endAt([endKey])
          .get();

      for (final doc in snap.docs) {
        final kwh =
            (doc.data()['estimatedKwh'] as num?)?.toDouble() ?? 0.0;
        result[doc.id] = (result[doc.id] ?? 0.0) + kwh;
      }
    }
    return result;
  }

  Future<List<_DeviceStat>> _fetchDeviceTotals(
    String uid,
    String startKey,
    String endKey,
  ) async {
    final db = FirebaseFirestore.instance;
    final result = <_DeviceStat>[];

    for (final deviceDoc in _devices) {
      final snap = await db
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceDoc.id)
          .collection('dailyStats')
          .orderBy(FieldPath.documentId)
          .startAt([startKey])
          .endAt([endKey])
          .get();

      final kwh = snap.docs.fold(
        0.0,
        (s, d) => s + ((d.data()['estimatedKwh'] as num?)?.toDouble() ?? 0.0),
      );
      if (kwh > 0) {
        final name = deviceDoc.data()['name'] as String? ?? 'Sem nome';
        result.add(_DeviceStat(name: name, kwh: kwh));
      }
    }
    result.sort((a, b) => b.kwh.compareTo(a.kwh));
    return result;
  }

  Future<_HistoricData> _fetchData(String uid) async {
    if (_devices.isEmpty && _selectedDeviceId == 'todos') {
      return _HistoricData.empty();
    }

    final startKey = _dateKey(_dataInicio);
    final endKey = _dateKey(_dataFim);

    // Previous period (same number of days)
    final days = _daysBetween(_dataInicio, _dataFim);
    final prevEnd = _dataInicio.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: days - 1));

    // Always this month / last month for chart 2
    final now = DateTime.now();
    final curMonthStart = DateTime(now.year, now.month, 1);
    final prevMonthEnd = DateTime(now.year, now.month, 0);
    final prevMonthStart = DateTime(prevMonthEnd.year, prevMonthEnd.month, 1);

    final fetched = await Future.wait([
      _fetchKwhByDate(uid, _selectedDeviceId, startKey, endKey),
      _fetchKwhByDate(
          uid, _selectedDeviceId, _dateKey(prevStart), _dateKey(prevEnd)),
      _fetchKwhByDate(
          uid, _selectedDeviceId, _dateKey(curMonthStart), _dateKey(now)),
      _fetchKwhByDate(uid, _selectedDeviceId, _dateKey(prevMonthStart),
          _dateKey(prevMonthEnd)),
    ]);

    final deviceTotals = _selectedDeviceId == 'todos'
        ? await _fetchDeviceTotals(uid, startKey, endKey)
        : <_DeviceStat>[];

    return _HistoricData(
      current: fetched[0],
      previous: fetched[1],
      curMonth: fetched[2],
      prevMonth: fetched[3],
      deviceTotals: deviceTotals,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          TextButton.icon(
            onPressed: () => _exportPdf(context),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('PDF'),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: FutureBuilder<_HistoricData>(
              future: _dataFuture,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData) {
                  return const Center(child: Text('Sem dados'));
                }
                return _buildContent(snap.data!);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Period chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: _Period.values.map((p) {
              final sel = _period == p;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(p.label),
                  selected: sel,
                  onSelected: (_) => _setPeriod(p),
                  selectedColor: const Color(0xFF0f1e3d),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: sel ? Colors.white : null,
                    fontWeight: sel ? FontWeight.w600 : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Date pickers
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _DatePickerButton(
                  label: 'De',
                  date: _dataInicio,
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _dataInicio,
                      firstDate: DateTime(2020),
                      lastDate: _dataFim,
                    );
                    if (d != null && mounted) {
                      setState(() {
                        _period = _Period.personalizado;
                        _dataInicio = d;
                      });
                      _reload();
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
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _dataFim,
                      firstDate: _dataInicio,
                      lastDate: DateTime.now(),
                    );
                    if (d != null && mounted) {
                      setState(() {
                        _period = _Period.personalizado;
                        _dataFim =
                            DateTime(d.year, d.month, d.day, 23, 59, 59);
                      });
                      _reload();
                    }
                  },
                ),
              ),
            ],
          ),
        ),

        // Device chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              _DeviceChip(
                label: 'Todos',
                selected: _selectedDeviceId == 'todos',
                onTap: () {
                  setState(() => _selectedDeviceId = 'todos');
                  _reload();
                },
              ),
              ..._devices.map((d) {
                final name = d.data()['name'] as String? ?? 'Sem nome';
                return _DeviceChip(
                  label: name,
                  selected: _selectedDeviceId == d.id,
                  onTap: () {
                    setState(() => _selectedDeviceId = d.id);
                    _reload();
                  },
                );
              }),
            ],
          ),
        ),

        const Divider(height: 1),
      ],
    );
  }

  // ── Content ───────────────────────────────────────────────────────────────

  Widget _buildContent(_HistoricData data) {
    final totalKwh = data.current.values.fold(0.0, (a, b) => a + b);
    final prevTotalKwh = data.previous.values.fold(0.0, (a, b) => a + b);
    final custoTotal = totalKwh * _energyPrice;
    final prevCusto = prevTotalKwh * _energyPrice;
    final days = _daysBetween(_dataInicio, _dataFim);
    final mediaDiaria = days > 0 ? totalKwh / days : 0.0;
    final prevMedia = days > 0 ? prevTotalKwh / days : 0.0;

    double picoKwh = 0;
    String picoLabel = '—';
    for (final e in data.current.entries) {
      if (e.value > picoKwh) {
        picoKwh = e.value;
        final d = DateTime.parse(e.key);
        picoLabel = '${d.day}/${d.month}';
      }
    }

    final daysInMonth =
        DateTime(_dataInicio.year, _dataInicio.month + 1, 0).day;
    final dailyTarget =
        _monthlyKwhTarget > 0 ? _monthlyKwhTarget / daysInMonth : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // KPI grid
        _buildKpiGrid(
          totalKwh: totalKwh,
          prevTotalKwh: prevTotalKwh,
          custoTotal: custoTotal,
          prevCusto: prevCusto,
          mediaDiaria: mediaDiaria,
          prevMedia: prevMedia,
          picoKwh: picoKwh,
          picoLabel: picoLabel,
        ),
        const SizedBox(height: 20),

        // Chart 1 — Daily bars
        const _SectionTitle('Consumo diário (kWh)'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 240,
          child: _buildDailyBarsChart(data.current, dailyTarget),
        ),
        const SizedBox(height: 20),

        // Chart 2 — Month comparison
        const _SectionTitle('Comparação de meses'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 200,
          child: _buildMonthCompareChart(data.curMonth, data.prevMonth),
        ),

        // Chart 3 — Donut (only "Todos")
        if (_selectedDeviceId == 'todos' && data.deviceTotals.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _SectionTitle('Consumo por dispositivo'),
          const SizedBox(height: 8),
          _ChartCard(
            height: 220,
            child: _buildDonutChart(data.deviceTotals, totalKwh),
          ),
        ],
        const SizedBox(height: 20),

        // Chart 4 — Accumulated cost
        const _SectionTitle('Custo acumulado (€)'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 265,
          child: _buildCostLineChart(data.current),
        ),
        const SizedBox(height: 20),

        // Daily table
        _buildDailyTable(data.current),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── KPI grid ──────────────────────────────────────────────────────────────

  Widget _buildKpiGrid({
    required double totalKwh,
    required double prevTotalKwh,
    required double custoTotal,
    required double prevCusto,
    required double mediaDiaria,
    required double prevMedia,
    required double picoKwh,
    required String picoLabel,
  }) {
    double var_(double c, double p) =>
        p > 0 ? (c - p) / p * 100 : 0.0;

    return Column(
      children: [
        Row(children: [
          Expanded(
            child: _KpiCard(
              title: 'Consumo total',
              value: '${totalKwh.toStringAsFixed(2)} kWh',
              variation: var_(totalKwh, prevTotalKwh),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _KpiCard(
              title: 'Custo estimado',
              value: '${custoTotal.toStringAsFixed(2)} €',
              variation: var_(custoTotal, prevCusto),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _KpiCard(
              title: 'Média diária',
              value: '${mediaDiaria.toStringAsFixed(2)} kWh/dia',
              variation: var_(mediaDiaria, prevMedia),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _KpiCard(
              title: 'Pico de consumo',
              value: '${picoKwh.toStringAsFixed(2)} kWh',
              subtitle: picoLabel,
            ),
          ),
        ]),
      ],
    );
  }

  // ── Chart 1: Daily bars ───────────────────────────────────────────────────

  Widget _buildDailyBarsChart(Map<String, double> data, double dailyTarget) {
    if (data.isEmpty) {
      return const Center(
          child: Text('Sem dados', style: TextStyle(color: Colors.grey)));
    }

    final days = <DateTime>[];
    var d = _dataInicio;
    while (!d.isAfter(_dataFim)) {
      days.add(d);
      d = d.add(const Duration(days: 1));
    }

    final maxKwh = data.values.fold(0.0, (a, b) => a > b ? a : b);
    final yInterval = _niceYInterval(
        dailyTarget > maxKwh ? dailyTarget * 1.2 : maxKwh * 1.2);

    final barW = days.length > 60
        ? 3.0
        : days.length > 30
            ? 5.0
            : days.length > 20
                ? 6.0
                : days.length > 10
                    ? 10.0
                    : 16.0;
    final labelStep = days.length > 60
        ? 14
        : days.length > 30
            ? 7
            : days.length > 14
                ? 5
                : days.length > 7
                    ? 3
                    : 1;

    final barGroups = days.asMap().entries.map((e) {
      final kwh = data[_dateKey(e.value)] ?? 0.0;
      final isAbove = dailyTarget > 0 && kwh > dailyTarget;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: kwh,
            color: isAbove ? Colors.red.shade400 : const Color(0xFF0f1e3d),
            width: barW,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        barGroups: barGroups,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) {
              final day = days[group.x];
              return BarTooltipItem(
                '${day.day}/${day.month}\n${rod.toY.toStringAsFixed(2)} kWh',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: yInterval,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i % labelStep != 0 || i >= days.length) {
                  return const SizedBox.shrink();
                }
                final day = days[i];
                return Text(
                  '${day.day}/${day.month}',
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: dailyTarget > 0
              ? [
                  HorizontalLine(
                    y: dailyTarget,
                    color: Colors.red.shade300,
                    strokeWidth: 1.5,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.only(left: 4),
                      style: TextStyle(
                          fontSize: 9, color: Colors.red.shade400),
                      labelResolver: (_) => 'meta',
                    ),
                  ),
                ]
              : const [],
        ),
      ),
    );
  }

  // ── Chart 2: Month comparison ─────────────────────────────────────────────

  Widget _buildMonthCompareChart(
    Map<String, double> curMonth,
    Map<String, double> prevMonth,
  ) {
    final curTotal = curMonth.values.fold(0.0, (a, b) => a + b);
    final prevTotal = prevMonth.values.fold(0.0, (a, b) => a + b);
    final now = DateTime.now();
    final prevMonthDate = DateTime(now.year, now.month - 1, 1);
    const months = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];
    final curLabel = months[now.month - 1];
    final prevLabel = months[prevMonthDate.month - 1];
    final diff = prevTotal > 0 ? (curTotal - prevTotal) / prevTotal * 100 : 0.0;
    final isUp = diff > 0;

    final maxVal = prevTotal > curTotal ? prevTotal : curTotal;
    final yInterval = _niceYInterval(maxVal * 1.2);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: BarChart(
            BarChartData(
              barGroups: [
                BarChartGroupData(x: 0, barRods: [
                  BarChartRodData(
                    toY: prevTotal,
                    color: Colors.grey.shade400,
                    width: 40,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                  ),
                ]),
                BarChartGroupData(x: 1, barRods: [
                  BarChartRodData(
                    toY: curTotal,
                    color: const Color(0xFF0f1e3d),
                    width: 40,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                  ),
                ]),
              ],
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                    '${group.x == 0 ? prevLabel : curLabel}\n'
                    '${rod.toY.toStringAsFixed(2)} kWh',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yInterval,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.grey.shade200, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: yInterval,
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(1),
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, _) {
                      if (v == 0) {
                        return Text(prevLabel,
                            style: const TextStyle(fontSize: 11));
                      }
                      if (v == 1) {
                        return Text(curLabel,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold));
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LegendItem(
                color: Colors.grey.shade400,
                label: prevLabel,
                value: '${prevTotal.toStringAsFixed(2)} kWh',
              ),
              const SizedBox(height: 12),
              _LegendItem(
                color: const Color(0xFF0f1e3d),
                label: '$curLabel (atual)',
                value: '${curTotal.toStringAsFixed(2)} kWh',
              ),
              if (prevTotal > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(
                    isUp ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 13,
                    color: isUp ? Colors.red : const Color(0xFF38d9a9),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${diff.abs().toStringAsFixed(1)}% vs mês ant.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isUp ? Colors.red : const Color(0xFF38d9a9),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Chart 3: Donut ────────────────────────────────────────────────────────

  static const List<Color> _donutColors = [
    Color(0xFF0f1e3d),
    Color(0xFF38A3F1),
    Color(0xFF38d9a9),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
    Color(0xFFE91E63),
    Color(0xFF009688),
  ];

  Widget _buildDonutChart(List<_DeviceStat> devices, double totalKwh) {
    if (totalKwh == 0) {
      return const Center(
          child: Text('Sem dados', style: TextStyle(color: Colors.grey)));
    }

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: devices.asMap().entries.map((e) {
                    final color = _donutColors[e.key % _donutColors.length];
                    final pct = e.value.kwh / totalKwh * 100;
                    final showLabel = pct >= 7;
                    return PieChartSectionData(
                      value: e.value.kwh,
                      color: color,
                      radius: 48,
                      title: showLabel ? '${pct.toStringAsFixed(0)}%' : '',
                      titleStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  centerSpaceRadius: 32,
                  sectionsSpace: 2,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    totalKwh.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0f1e3d),
                    ),
                  ),
                  const Text(
                    'kWh',
                    style: TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total: ${totalKwh.toStringAsFixed(2)} kWh',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ...devices.asMap().entries.map((e) {
                final color = _donutColors[e.key % _donutColors.length];
                final pct = e.value.kwh / totalKwh * 100;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e.value.name,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${pct.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                  ]),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // ── Chart 4: Accumulated cost ─────────────────────────────────────────────

  Widget _buildCostLineChart(Map<String, double> data) {
    if (data.isEmpty) {
      return const Center(
          child: Text('Sem dados', style: TextStyle(color: Colors.grey)));
    }

    final days = <DateTime>[];
    var d = _dataInicio;
    while (!d.isAfter(_dataFim)) {
      days.add(d);
      d = d.add(const Duration(days: 1));
    }

    final now = DateTime.now();
    double cumCost = 0;
    final actualSpots = <FlSpot>[];

    for (int i = 0; i < days.length; i++) {
      if (days[i].isAfter(now)) break;
      cumCost += (data[_dateKey(days[i])] ?? 0.0) * _energyPrice;
      actualSpots.add(FlSpot(i.toDouble(), cumCost));
    }

    if (actualSpots.isEmpty) {
      return const Center(
          child: Text('Sem dados', style: TextStyle(color: Colors.grey)));
    }

    // Projection from today to end of period
    final showProjection = _dataFim.isAfter(now) && actualSpots.length >= 2;
    final projectionSpots = <FlSpot>[];
    if (showProjection) {
      final avgDaily = actualSpots.last.y / actualSpots.length;
      projectionSpots.add(actualSpots.last);
      for (int i = actualSpots.length; i < days.length; i++) {
        projectionSpots.add(FlSpot(
          i.toDouble(),
          actualSpots.last.y + avgDaily * (i - actualSpots.length + 1),
        ));
      }
    }

    final rawMaxY = showProjection && projectionSpots.isNotEmpty
        ? projectionSpots.last.y * 1.12
        : actualSpots.last.y * 1.12;
    final maxY = rawMaxY <= 0 ? 1.0 : rawMaxY;
    final yInterval = _niceYInterval(maxY);

    final todayX = days.indexWhere(
        (d) => d.year == now.year && d.month == now.month && d.day == now.day);

    final labelInterval =
        (days.length > 20 ? 7 : days.length > 10 ? 3 : 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (ts) => ts.map((s) {
                    final i = s.x.toInt();
                    final label = i < days.length
                        ? '${days[i].day}/${days[i].month}'
                        : '';
                    return LineTooltipItem(
                      '$label\n${s.y.toStringAsFixed(2)} €',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: actualSpots,
                  isCurved: true,
                  color: const Color(0xFF0f1e3d),
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFF0f1e3d).withValues(alpha: 0.08),
                  ),
                ),
                if (showProjection && projectionSpots.length >= 2)
                  LineChartBarData(
                    spots: projectionSpots,
                    isCurved: false,
                    color: Colors.grey,
                    barWidth: 1.5,
                    dotData: const FlDotData(show: false),
                    dashArray: [6, 4],
                  ),
              ],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yInterval,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.grey.shade200, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: yInterval,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toStringAsFixed(2)}€',
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: labelInterval,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i >= days.length) return const SizedBox.shrink();
                      return Text(
                        '${days[i].day}/${days[i].month}',
                        style:
                            const TextStyle(fontSize: 9, color: Colors.grey),
                      );
                    },
                  ),
                ),
              ),
              extraLinesData: ExtraLinesData(
                verticalLines: todayX >= 0
                    ? [
                        VerticalLine(
                          x: todayX.toDouble(),
                          color: Colors.red.shade300,
                          strokeWidth: 1.5,
                          dashArray: [5, 4],
                          label: VerticalLineLabel(
                            show: true,
                            alignment: Alignment.topLeft,
                            style: TextStyle(
                                fontSize: 9, color: Colors.red.shade400),
                            labelResolver: (_) => 'hoje',
                          ),
                        ),
                      ]
                    : const [],
              ),
            ),
          ),
        ),
        if (showProjection) ...[
          const SizedBox(height: 6),
          Row(children: [
            Container(
              width: 22,
              height: 2,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: Colors.grey, width: 1.5,
                      style: BorderStyle.solid),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Text('Projeção',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(width: 16),
            Container(width: 22, height: 2, color: const Color(0xFF0f1e3d)),
            const SizedBox(width: 6),
            const Text('Real',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
          ]),
        ],
      ],
    );
  }

  // ── Daily table ───────────────────────────────────────────────────────────

  Widget _buildDailyTable(Map<String, double> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    final mediaKwh = data.values.fold(0.0, (a, b) => a + b) / data.length;
    final rows = data.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final displayed = _tableExpanded ? rows : rows.take(7).toList();

    const months = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];

    String fmtDate(String key) {
      final d = DateTime.parse(key);
      return '${d.day} ${months[d.month - 1]}';
    }

    Color vsColor(double kwh) {
      if (mediaKwh == 0) return Colors.grey;
      final r = kwh / mediaKwh;
      if (r <= 1.0) return const Color(0xFF38d9a9);
      if (r <= 1.2) return Colors.amber.shade700;
      return Colors.red;
    }

    int estimateXp(double kwh) {
      if (mediaKwh == 0) return 0;
      final saving = (mediaKwh - kwh) / mediaKwh;
      if (saving >= 0.30) return 50;
      if (saving >= 0.15) return 25;
      if (saving >= 0.05) return 15;
      if (saving > 0) return 5;
      return 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Detalhe por dia'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8)
            ],
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: const [
                  Expanded(
                      flex: 3,
                      child: Text('Dia',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.grey))),
                  Expanded(
                      flex: 2,
                      child: Text('kWh',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.grey))),
                  Expanded(
                      flex: 2,
                      child: Text('€',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.grey))),
                  Expanded(
                      flex: 2,
                      child: Text('vs média',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.grey))),
                  Expanded(
                      flex: 2,
                      child: Text('XP est.',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.grey))),
                ]),
              ),
              const Divider(height: 1),

              // Rows
              ...displayed.asMap().entries.map((e) {
                final i = e.key;
                final kwh = e.value.value;
                final cost = kwh * _energyPrice;
                final diff = mediaKwh > 0
                    ? (kwh - mediaKwh) / mediaKwh * 100
                    : 0.0;
                final col = vsColor(kwh);
                final xp = estimateXp(kwh);

                return Container(
                  color: i % 2 == 0 ? null : Colors.grey.shade50,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Expanded(
                        flex: 3,
                        child: Text(fmtDate(e.value.key),
                            style: const TextStyle(fontSize: 13))),
                    Expanded(
                        flex: 2,
                        child: Text(kwh.toStringAsFixed(2),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 13))),
                    Expanded(
                        flex: 2,
                        child: Text(cost.toStringAsFixed(2),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 13))),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: col.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: col,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        xp > 0 ? '+$xp' : '—',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          color: xp > 0
                              ? const Color(0xFF38d9a9)
                              : Colors.grey,
                          fontWeight: xp > 0 ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ]),
                );
              }),

              if (rows.length > 7) ...[
                const Divider(height: 1),
                TextButton(
                  onPressed: () =>
                      setState(() => _tableExpanded = !_tableExpanded),
                  child: Text(_tableExpanded
                      ? 'Mostrar menos'
                      : 'Ver tudo (${rows.length} dias)'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── PDF export ────────────────────────────────────────────────────────────

  Future<void> _exportPdf(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('A gerar PDF...'),
        ]),
      ),
    );

    try {
      final data = await _fetchData(uid);
      final totalKwh = data.current.values.fold(0.0, (a, b) => a + b);
      final custoTotal = totalKwh * _energyPrice;
      final days = _daysBetween(_dataInicio, _dataFim);
      final mediaKwh = days > 0 ? totalKwh / days : 0.0;
      final rows = data.current.entries.toList()
        ..sort((a, b) => b.key.compareTo(a.key));

      String fmtDate(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

      final pdf = pw.Document();
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Relatório de Consumo',
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900)),
                    pw.Text('AVERIS',
                        style: const pw.TextStyle(
                            fontSize: 13, color: PdfColors.grey600)),
                  ]),
              pw.Divider(color: PdfColors.blue900, thickness: 1.5),
              pw.SizedBox(height: 4),
            ]),
        build: (_) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Período',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey600)),
                        pw.Text(
                            '${fmtDate(_dataInicio)}  →  ${fmtDate(_dataFim)}',
                            style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold)),
                      ]),
                  pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Gerado em',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey600)),
                        pw.Text(fmtDate(DateTime.now()),
                            style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold)),
                      ]),
                ]),
          ),
          pw.SizedBox(height: 20),
          pw.Text('Resumo',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Row(children: [
            _pdfBox('Consumo total', '${totalKwh.toStringAsFixed(2)} kWh'),
            pw.SizedBox(width: 10),
            _pdfBox('Custo estimado', '${custoTotal.toStringAsFixed(2)} €'),
            pw.SizedBox(width: 10),
            _pdfBox('Média diária', '${mediaKwh.toStringAsFixed(2)} kWh/dia'),
            pw.SizedBox(width: 10),
            _pdfBox('Dias com dados', '${data.current.length}'),
          ]),
          pw.SizedBox(height: 24),
          pw.Text('Consumo por dia',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            pw.Text('Sem dados.',
                style: const pw.TextStyle(color: PdfColors.grey600))
          else
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.blue900),
                    children: [
                      _pdfTh('Dia'),
                      _pdfTh('kWh'),
                      _pdfTh('€'),
                      _pdfTh('vs média'),
                    ]),
                ...rows.asMap().entries.map((e) {
                  final i = e.key;
                  final d = DateTime.parse(e.value.key);
                  final kwh = e.value.value;
                  final diff = mediaKwh > 0
                      ? (kwh - mediaKwh) / mediaKwh * 100
                      : 0.0;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                        color: i % 2 == 0
                            ? PdfColors.white
                            : PdfColors.grey100),
                    children: [
                      _pdfTd('${d.day}/${d.month}/${d.year}'),
                      _pdfTd(kwh.toStringAsFixed(2)),
                      _pdfTd((kwh * _energyPrice).toStringAsFixed(2)),
                      _pdfTd(
                        '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}%',
                        color: diff > 0 ? PdfColors.red700 : PdfColors.green700,
                      ),
                    ],
                  );
                }),
                pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.blue50),
                    children: [
                      _pdfTd('Total', bold: true),
                      _pdfTd(totalKwh.toStringAsFixed(2), bold: true),
                      _pdfTd(custoTotal.toStringAsFixed(2), bold: true),
                      _pdfTd('—', bold: true),
                    ]),
              ],
            ),
          pw.SizedBox(height: 16),
          pw.Divider(color: PdfColors.grey400),
          pw.Text('Tarifa: ${_energyPrice.toStringAsFixed(2)} €/kWh',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ],
      ));

      if (context.mounted) Navigator.pop(context);
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            'averis_${fmtDate(_dataInicio).replaceAll('/', '-')}_${fmtDate(_dataFim).replaceAll('/', '-')}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao gerar PDF: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  pw.Widget _pdfBox(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.blue200),
              borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600)),
                pw.SizedBox(height: 4),
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ]),
        ),
      );

  pw.Widget _pdfTh(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white)),
      );

  pw.Widget _pdfTd(String text, {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color ?? PdfColors.black)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0f1e3d),
            ),
      );
}

class _ChartCard extends StatelessWidget {
  final Widget child;
  final double height;
  const _ChartCard({required this.child, required this.height});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
          ],
        ),
        child: child,
      );
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final double? variation;
  final String? subtitle;

  const _KpiCard({
    required this.title,
    required this.value,
    this.variation,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final v = variation;
    final hasVar = v != null && v != 0;
    final isUp = (v ?? 0) > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0f1e3d))),
          if (subtitle != null)
            Text(subtitle!,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          if (hasVar) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(
                isUp ? Icons.arrow_upward : Icons.arrow_downward,
                size: 11,
                color: isUp ? Colors.red : const Color(0xFF38d9a9),
              ),
              const SizedBox(width: 2),
              Text(
                '${v.abs().toStringAsFixed(1)}% vs período ant.',
                style: TextStyle(
                    fontSize: 10,
                    color: isUp ? Colors.red : const Color(0xFF38d9a9)),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _DeviceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DeviceChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: const Color(0xFF38A3F1),
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? Colors.white : null,
            fontWeight: selected ? FontWeight.w600 : null,
          ),
        ),
      );
}

class _DatePickerButton extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DatePickerButton(
      {required this.label, required this.date, required this.onTap});

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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(formatted,
            style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem(
      {required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
        ),
      ]);
}
