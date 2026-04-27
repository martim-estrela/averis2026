// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../add_device_page.dart';
import '../settings_page.dart';
import '../services/prefs_service.dart';

// ── Constants ──────────────────────────────────────────────────────────────────

const _kAccent  = Color(0xFF38d9a9);
const _kCard    = Color(0xFF0f1e3d);
const _kBorder  = Color(0xFF1e3a6e);

// ── Step state ─────────────────────────────────────────────────────────────────

enum _StepState { done, active, todo }

// ══════════════════════════════════════════════════════════════════════════════
// SetupChecklist
// ══════════════════════════════════════════════════════════════════════════════

class SetupChecklist extends StatefulWidget {
  final String uid;
  final VoidCallback onSetupComplete;

  const SetupChecklist({
    super.key,
    required this.uid,
    required this.onSetupComplete,
  });

  @override
  State<SetupChecklist> createState() => _SetupChecklistState();
}

class _SetupChecklistState extends State<SetupChecklist> {
  final _db = FirebaseFirestore.instance;

  StreamSubscription? _devicesSub;
  StreamSubscription? _userSub;

  bool _hasDevices      = false;
  bool _hasGoal         = false;
  bool _hasCustomTariff = false;
  bool _completionFired = false;

  @override
  void initState() {
    super.initState();
    _listenDevices();
    _listenUser();
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }

  void _listenDevices() {
    _devicesSub = _db
        .collection('users')
        .doc(widget.uid)
        .collection('devices')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _hasDevices = snap.docs.isNotEmpty);
      _checkCompletion();
    });
  }

  void _listenUser() {
    _userSub = _db
        .collection('users')
        .doc(widget.uid)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final data = snap.data()!;
      final kwh =
          (data['goals']?['monthlyKwhTarget'] as num?)?.toDouble() ?? 0.0;
      final price =
          (data['settings']?['energyPrice'] as num?)?.toDouble() ?? 0.22;
      final tipo =
          (data['settings']?['energyContract']?['tipo'] as String?) ??
              'simples';
      setState(() {
        _hasGoal = kwh > 0;
        _hasCustomTariff = price != 0.22 || tipo != 'simples';
      });
      _checkCompletion();
    });
  }

  void _checkCompletion() async {
    if (_completionFired) return;
    if (!_hasDevices || !_hasGoal || !_hasCustomTariff) return;
    _completionFired = true;
    await PrefsService.setSetupDone();
    await _db.collection('users').doc(widget.uid).update({
      'pontos':      FieldValue.increment(50),
      'pontosTotal': FieldValue.increment(50),
    });
    if (mounted) widget.onSetupComplete();
  }

  int get _completedSteps =>
      1 + (_hasDevices ? 1 : 0) + (_hasGoal ? 1 : 0) + (_hasCustomTariff ? 1 : 0);

  _StepState _state2() =>
      _hasDevices ? _StepState.done : _StepState.active;

  _StepState _state3() {
    if (_hasGoal) return _StepState.done;
    if (_hasDevices) return _StepState.active;
    return _StepState.todo;
  }

  _StepState _state4() {
    if (_hasCustomTariff) return _StepState.done;
    if (_hasGoal) return _StepState.active;
    return _StepState.todo;
  }

  // ── Step actions ────────────────────────────────────────────────────────────

  void _onStep2(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddDevicePage()),
    );
  }

  void _onStep3(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GoalSheet(uid: widget.uid),
    );
  }

  void _onStep4(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = _completedSteps;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Configuração inicial',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$done / 4 completo',
                    style: const TextStyle(
                      color: _kAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: done / 4,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(_kAccent),
                minHeight: 6,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Steps
          _SetupRow(
            label: 'Criar conta',
            state: _StepState.done,
          ),
          _SetupRow(
            label: 'Adicionar o primeiro dispositivo',
            state: _state2(),
            onTap: _state2() != _StepState.done
                ? () => _onStep2(context)
                : null,
          ),
          _SetupRow(
            label: 'Definir meta de consumo',
            state: _state3(),
            onTap: _state3() == _StepState.active
                ? () => _onStep3(context)
                : null,
          ),
          _SetupRow(
            label: 'Configurar tarifa de energia',
            state: _state4(),
            isLast: true,
            onTap: _state4() == _StepState.active
                ? () => _onStep4(context)
                : null,
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SetupRow
// ══════════════════════════════════════════════════════════════════════════════

class _SetupRow extends StatelessWidget {
  final String label;
  final _StepState state;
  final VoidCallback? onTap;
  final bool isLast;

  const _SetupRow({
    required this.label,
    required this.state,
    this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget leading;
    TextStyle labelStyle;
    double opacity = 1.0;

    switch (state) {
      case _StepState.done:
        leading = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Colors.green, size: 14),
        );
        labelStyle = TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 13,
          decoration: TextDecoration.lineThrough,
          decorationColor: Colors.white.withValues(alpha: 0.3),
        );

      case _StepState.active:
        leading = _PulsingDot();
        labelStyle = const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        );

      case _StepState.todo:
        leading = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
            ),
            shape: BoxShape.circle,
          ),
        );
        labelStyle = const TextStyle(color: Colors.white, fontSize: 13);
        opacity = 0.5;
    }

    return Opacity(
      opacity: opacity,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: state == _StepState.active
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border(
                    bottom: isLast
                        ? BorderSide.none
                        : BorderSide(
                            color: Colors.white.withValues(alpha: 0.06)),
                  ),
                )
              : BoxDecoration(
                  border: Border(
                    bottom: isLast
                        ? BorderSide.none
                        : BorderSide(
                            color: Colors.white.withValues(alpha: 0.06)),
                  ),
                ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: labelStyle)),
              if (onTap != null)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: _kAccent.withValues(alpha: 0.7),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PulsingDot — animated dot for active steps
// ══════════════════════════════════════════════════════════════════════════════

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: _kAccent.withValues(alpha: 0.20),
          shape: BoxShape.circle,
          border: Border.all(color: _kAccent, width: 1.5),
        ),
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: _kAccent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _GoalSheet — quick goal-setter bottom sheet
// ══════════════════════════════════════════════════════════════════════════════

class _GoalSheet extends StatefulWidget {
  final String uid;
  const _GoalSheet({required this.uid});

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  double _kwh   = 150;
  bool _saving  = false;

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
                color: _kAccent,
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
            activeColor: _kAccent,
            inactiveColor: Colors.white.withValues(alpha: 0.15),
            onChanged: (v) => setState(() => _kwh = v),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
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
