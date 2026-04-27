// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/shelly_polling_service.dart';
import 'mfa_setup_page.dart';

// ── Constants ──────────────────────────────────────────────────────────────────

const _kNavColor = Color(0xFF0f1e3d);
const _kAccent = Color(0xFF38d9a9);

// ── TipoContrato (referenced by ShellyPollingService + SmartPlugService) ───────

enum TipoContrato { simples, biHorario, triHorario }

extension TipoContratoLabel on TipoContrato {
  String get label => switch (this) {
    TipoContrato.simples => 'Simples (tarifa única)',
    TipoContrato.biHorario => 'Bi-horário (vazio / fora de vazio)',
    TipoContrato.triHorario => 'Tri-horário (ponta / cheias / vazio)',
  };

  String get descricao => switch (this) {
    TipoContrato.simples => 'Um único preço em qualquer hora do dia.',
    TipoContrato.biHorario =>
      'Vazio: 22h–8h (dias úteis) e fim-de-semana.\nFora de vazio: restantes horas.',
    TipoContrato.triHorario =>
      'Ponta: horas de maior consumo nacional.\nCheias: períodos intermédios.\nVazio: noite e fins-de-semana.',
  };

  Map<String, double> get precosReferencia => switch (this) {
    TipoContrato.simples => {'simples': 0.2134},
    TipoContrato.biHorario => {'foraVazio': 0.2134, 'vazio': 0.1076},
    TipoContrato.triHorario => {
      'ponta': 0.2534,
      'cheias': 0.1987,
      'vazio': 0.1076,
    },
  };
}

// ── Inline level helpers (avoids circular import with profile_page.dart) ───────

String _levelLabel(int pontosTotal) {
  if (pontosTotal >= 2000) return '🌟 Nível 6 — Lenda';
  if (pontosTotal >= 1100) return '🏆 Nível 5 — Mestre';
  if (pontosTotal >= 600) return '🔋 Nível 4 — Expert';
  if (pontosTotal >= 300) return '⚡ Nível 3 — Eficiente';
  if (pontosTotal >= 100) return '💡 Nível 2 — Poupador';
  return '🌱 Nível 1 — Aprendiz';
}

Color _levelColor(int pontosTotal) {
  if (pontosTotal >= 2000) return const Color(0xFFF06292);
  if (pontosTotal >= 1100) return const Color(0xFF7E57C2);
  if (pontosTotal >= 600) return const Color(0xFFFF7043);
  if (pontosTotal >= 300) return const Color(0xFFFFB300);
  if (pontosTotal >= 100) return const Color(0xFF4FC3F7);
  return const Color(0xFF78C850);
}

// ══════════════════════════════════════════════════════════════════════════════
// SettingsPage
// ══════════════════════════════════════════════════════════════════════════════

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final uid = user.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: _kNavColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Definições',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !(snap.data?.exists ?? false)) {
            return const Center(child: Text('Definições não encontradas.'));
          }

          final data = snap.data!.data()!;
          final settings =
              (data['settings'] as Map?)?.cast<String, dynamic>() ?? {};
          final goals =
              (data['goals'] as Map?)?.cast<String, dynamic>() ?? {};
          final notifMap =
              (settings['notifications'] as Map?)?.cast<String, dynamic>() ??
              {};
          final contractMap =
              (settings['energyContract'] as Map?)?.cast<String, dynamic>() ??
              {};
          final quietMap =
              (notifMap['quietHours'] as Map?)?.cast<String, dynamic>() ?? {};

          final name = (data['name'] as String?)?.trim().isNotEmpty == true
              ? data['name'] as String
              : user.displayName ?? 'Utilizador';
          final email = (data['email'] as String?) ?? user.email ?? '';
          final photoUrl = data['photoUrl'] as String?;
          final pontosTotal = (data['pontosTotal'] as num?)?.toInt() ?? 0;

          final kwhTarget =
              (goals['monthlyKwhTarget'] as num?)?.toDouble() ?? 0.0;
          final costTarget =
              (goals['monthlyCostTarget'] as num?)?.toDouble() ?? 0.0;

          final tipoStr = (contractMap['tipo'] as String?) ?? 'simples';
          final tipoContrato = TipoContrato.values.firstWhere(
            (t) => t.name == tipoStr,
            orElse: () => TipoContrato.simples,
          );
          final rawPrecos = contractMap['precos'] as Map?;
          final precos = rawPrecos != null
              ? rawPrecos.map(
                  (k, v) => MapEntry(k as String, (v as num).toDouble()),
                )
              : tipoContrato.precosReferencia;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ContaSection(
                  uid: uid,
                  name: name,
                  email: email,
                  photoUrl: photoUrl,
                  pontosTotal: pontosTotal,
                ),
                const SizedBox(height: 14),
                const _SegurancaSection(),
                const SizedBox(height: 14),
                _MetasSection(
                  uid: uid,
                  kwhTarget: kwhTarget,
                  costTarget: costTarget,
                ),
                const SizedBox(height: 14),
                _EnergiaSection(
                  uid: uid,
                  tipoContrato: tipoContrato,
                  precos: precos,
                ),
                const SizedBox(height: 14),
                _NotificacoesSection(
                  uid: uid,
                  deviceOffline: notifMap['deviceOffline'] == true,
                  highConsumption: notifMap['highConsumption'] == true,
                  goalReached: notifMap['goalReached'] == true,
                  levelUp: notifMap['levelUp'] == true,
                  quietEnabled: quietMap['enabled'] == true,
                  quietStart: (quietMap['start'] as String?) ?? '22:00',
                  quietEnd: (quietMap['end'] as String?) ?? '07:00',
                ),
                const SizedBox(height: 14),
                _SessaoSection(uid: uid),
                const SizedBox(height: 14),
                const _SobreSection(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Shared card container ──────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _kNavColor,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Reusable tappable row ──────────────────────────────────────────────────────

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.subtitle,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? const Color(0xFF6B7280)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null) ...[
              Text(
                value!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(width: 4),
            ],
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _ContaSection
// ══════════════════════════════════════════════════════════════════════════════

class _ContaSection extends StatefulWidget {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final int pontosTotal;

  const _ContaSection({
    required this.uid,
    required this.name,
    required this.email,
    required this.pontosTotal,
    this.photoUrl,
  });

  @override
  State<_ContaSection> createState() => _ContaSectionState();
}

class _ContaSectionState extends State<_ContaSection> {
  bool _sendingReset = false;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _resetPassword() async {
    if (widget.email.isEmpty) return;
    setState(() => _sendingReset = true);
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email de redefinição enviado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível enviar o email: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final levelColor = _levelColor(widget.pontosTotal);
    final levelText = _levelLabel(widget.pontosTotal);

    return _SectionCard(
      title: 'Conta',
      child: Column(
        children: [
          // Profile row — tapping goes back to ProfilePage
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: _kNavColor,
                    backgroundImage: widget.photoUrl != null
                        ? NetworkImage(widget.photoUrl!)
                        : null,
                    child: widget.photoUrl == null
                        ? Text(
                            _initials(widget.name),
                            style: const TextStyle(
                              color: _kAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          widget.email,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: levelColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            levelText,
                            style: TextStyle(
                              fontSize: 11,
                              color: levelColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF9CA3AF),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 20),
          // Password reset row
          InkWell(
            onTap: _sendingReset ? null : _resetPassword,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_reset,
                    size: 20,
                    color: Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alterar senha',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Recebe um email de redefinição',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_sendingReset)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Color(0xFF9CA3AF),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SegurancaSection  (MFA / autenticação em dois passos)
// ══════════════════════════════════════════════════════════════════════════════

class _SegurancaSection extends StatelessWidget {
  const _SegurancaSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Segurança',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Protege a tua conta com verificação em dois passos (TOTP). '
            'Ao ativar, será pedido um código gerado pelo teu autenticador '
            'sempre que fizeres login.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: Icons.shield_outlined,
            label: 'Verificação em dois passos',
            subtitle: 'Configurar autenticador TOTP',
            iconColor: _kNavColor,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MfaSetupPage()),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _MetasSection
// ══════════════════════════════════════════════════════════════════════════════

class _MetasSection extends StatelessWidget {
  final String uid;
  final double kwhTarget;
  final double costTarget;

  const _MetasSection({
    required this.uid,
    required this.kwhTarget,
    required this.costTarget,
  });

  void _openEditor(BuildContext context, {required bool isKwh}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GoalBottomSheet(
        uid: uid,
        isKwh: isKwh,
        current: isKwh ? kwhTarget : costTarget,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Metas de consumo',
      child: Column(
        children: [
          _SettingsRow(
            icon: Icons.bolt_outlined,
            label: 'Meta mensal (kWh)',
            value: kwhTarget > 0
                ? '${kwhTarget.toStringAsFixed(0)} kWh'
                : 'Sem meta',
            onTap: () => _openEditor(context, isKwh: true),
          ),
          const Divider(height: 8),
          _SettingsRow(
            icon: Icons.euro_outlined,
            label: 'Meta mensal (€)',
            value: costTarget > 0
                ? '${costTarget.toStringAsFixed(0)} €'
                : 'Sem meta',
            onTap: () => _openEditor(context, isKwh: false),
          ),
        ],
      ),
    );
  }
}

class _GoalBottomSheet extends StatefulWidget {
  final String uid;
  final bool isKwh;
  final double current;

  const _GoalBottomSheet({
    required this.uid,
    required this.isKwh,
    required this.current,
  });

  @override
  State<_GoalBottomSheet> createState() => _GoalBottomSheetState();
}

class _GoalBottomSheetState extends State<_GoalBottomSheet> {
  late double _value;
  late TextEditingController _textCtrl;
  bool _saving = false;

  double get _maxVal => widget.isKwh ? 500.0 : 200.0;
  String get _unit => widget.isKwh ? 'kWh' : '€';
  String get _fieldKey =>
      widget.isKwh ? 'monthlyKwhTarget' : 'monthlyCostTarget';

  @override
  void initState() {
    super.initState();
    _value = widget.current > 0
        ? widget.current.clamp(0.0, _maxVal)
        : (widget.isKwh ? 100.0 : 30.0);
    _textCtrl = TextEditingController(text: _value.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _onSlider(double v) {
    setState(() {
      _value = v;
      _textCtrl.text = v.toStringAsFixed(0);
    });
  }

  void _onText(String v) {
    final parsed = double.tryParse(v);
    if (parsed != null && parsed >= 0 && parsed <= _maxVal) {
      setState(() => _value = parsed);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .update({'goals.$_fieldKey': _value});
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isKwh ? 'Meta mensal (kWh)' : 'Meta mensal (€)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _value.clamp(0.0, _maxVal),
                  min: 0,
                  max: _maxVal,
                  divisions: widget.isKwh ? 60 : 100,
                  activeColor: _kNavColor,
                  onChanged: _onSlider,
                ),
              ),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _textCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  decoration: InputDecoration(
                    suffixText: _unit,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onText,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              '0 – ${_maxVal.toStringAsFixed(0)} $_unit',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kNavColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _EnergiaSection  (expandable)
// ══════════════════════════════════════════════════════════════════════════════

class _EnergiaSection extends StatefulWidget {
  final String uid;
  final TipoContrato tipoContrato;
  final Map<String, double> precos;

  const _EnergiaSection({
    required this.uid,
    required this.tipoContrato,
    required this.precos,
  });

  @override
  State<_EnergiaSection> createState() => _EnergiaSectionState();
}

class _EnergiaSectionState extends State<_EnergiaSection> {
  bool _expanded = false;
  late TipoContrato _tipo;
  late Map<String, TextEditingController> _ctrls;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tipo = widget.tipoContrato;
    _initCtrls(widget.precos);
  }

  void _initCtrls(Map<String, double> precos) {
    _ctrls = precos.map(
      (k, v) => MapEntry(k, TextEditingController(text: v.toStringAsFixed(4))),
    );
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _changeTipo(TipoContrato novo) {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    setState(() {
      _tipo = novo;
      _initCtrls(novo.precosReferencia);
    });
  }

  static String _keyLabel(String key) => switch (key) {
    'simples' => 'Tarifa única (€/kWh)',
    'foraVazio' => 'Fora de vazio (€/kWh)',
    'vazio' => 'Vazio (€/kWh)',
    'ponta' => 'Ponta (€/kWh)',
    'cheias' => 'Cheias (€/kWh)',
    _ => key,
  };

  Future<void> _save() async {
    final precos = _ctrls.map(
      (k, c) =>
          MapEntry(k, double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0),
    );
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({
        'settings.energyContract.tipo': _tipo.name,
        'settings.energyContract.precos': precos,
        'settings.energyPrice': precos.values.first,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contrato guardado'),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — always visible
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(14))
                : BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.electric_bolt_outlined,
                    color: _kNavColor,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contrato de energia',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _kNavColor,
                          ),
                        ),
                        Text(
                          _tipo.label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF9CA3AF),
                  ),
                ],
              ),
            ),
          ),

          // Expandable body
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tipo de contrato',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 4),
                  RadioGroup<TipoContrato>(
                    groupValue: _tipo,
                    onChanged: (v) {
                      if (v != null) _changeTipo(v);
                    },
                    child: Column(
                      children: TipoContrato.values.map((t) {
                        return RadioListTile<TipoContrato>(
                          value: t,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            t.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            t.descricao,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Preços (€/kWh com IVA)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pré-preenchido com tarifas ERSE 2024. Ajusta ao teu contrato se necessário.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._ctrls.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: e.value,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _keyLabel(e.key),
                          prefixText: '€ ',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 15,
                          color: Color(0xFF3B82F6),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Os preços são usados para estimar a tua fatura e calcular pontos XP.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kNavColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Guardar',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _NotificacoesSection
// ══════════════════════════════════════════════════════════════════════════════

class _NotificacoesSection extends StatefulWidget {
  final String uid;
  final bool deviceOffline;
  final bool highConsumption;
  final bool goalReached;
  final bool levelUp;
  final bool quietEnabled;
  final String quietStart;
  final String quietEnd;

  const _NotificacoesSection({
    required this.uid,
    required this.deviceOffline,
    required this.highConsumption,
    required this.goalReached,
    required this.levelUp,
    required this.quietEnabled,
    required this.quietStart,
    required this.quietEnd,
  });

  @override
  State<_NotificacoesSection> createState() => _NotificacoesSectionState();
}

class _NotificacoesSectionState extends State<_NotificacoesSection> {
  late bool _deviceOffline;
  late bool _highConsumption;
  late bool _goalReached;
  late bool _levelUp;
  late bool _quietEnabled;
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;
  Timer? _quietDebounce;

  static final _timeRegex = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  @override
  void initState() {
    super.initState();
    _deviceOffline = widget.deviceOffline;
    _highConsumption = widget.highConsumption;
    _goalReached = widget.goalReached;
    _levelUp = widget.levelUp;
    _quietEnabled = widget.quietEnabled;
    _startCtrl = TextEditingController(text: widget.quietStart);
    _endCtrl = TextEditingController(text: widget.quietEnd);
  }

  @override
  void dispose() {
    _quietDebounce?.cancel();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    final start = _startCtrl.text.trim();
    final end = _endCtrl.text.trim();
    if (_quietEnabled) {
      if (!_timeRegex.hasMatch(start) || !_timeRegex.hasMatch(end)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Formato de hora inválido (use HH:MM)'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .update({
      'settings.notifications': {
        'deviceOffline': _deviceOffline,
        'highConsumption': _highConsumption,
        'goalReached': _goalReached,
        'levelUp': _levelUp,
        'quietHours': {
          'enabled': _quietEnabled,
          'start': start,
          'end': end,
        },
      },
    });
  }

  Widget _buildSwitch({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF6B7280)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: _kAccent,
            activeTrackColor: _kAccent.withValues(alpha: 0.45),
            onChanged: (v) {
              setState(() => onChanged(v));
              _persist();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Notificações',
      child: Column(
        children: [
          _buildSwitch(
            icon: Icons.wifi_off_outlined,
            title: 'Dispositivo offline',
            value: _deviceOffline,
            onChanged: (v) => _deviceOffline = v,
          ),
          _buildSwitch(
            icon: Icons.bolt,
            title: 'Consumo acima do limite',
            value: _highConsumption,
            onChanged: (v) => _highConsumption = v,
          ),
          _buildSwitch(
            icon: Icons.flag_outlined,
            title: 'Meta de poupança atingida',
            value: _goalReached,
            onChanged: (v) => _goalReached = v,
          ),
          _buildSwitch(
            icon: Icons.emoji_events_outlined,
            title: 'Subida de nível XP',
            subtitle: 'Avisa quando passas para um novo nível',
            value: _levelUp,
            onChanged: (v) => _levelUp = v,
          ),
          const Divider(height: 20),
          _buildSwitch(
            icon: Icons.bedtime_outlined,
            title: 'Horário silencioso',
            subtitle: 'Não enviar notificações neste período',
            value: _quietEnabled,
            onChanged: (v) => _quietEnabled = v,
          ),
          if (_quietEnabled) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Início (HH:MM)',
                      hintText: '22:00',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _quietDebounce?.cancel();
                      _quietDebounce = Timer(
                        const Duration(milliseconds: 800),
                        _persist,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Fim (HH:MM)',
                      hintText: '07:00',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _quietDebounce?.cancel();
                      _quietDebounce = Timer(
                        const Duration(milliseconds: 800),
                        _persist,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SessaoSection
// ══════════════════════════════════════════════════════════════════════════════

class _SessaoSection extends StatefulWidget {
  final String uid;

  const _SessaoSection({required this.uid});

  @override
  State<_SessaoSection> createState() => _SessaoSectionState();
}

class _SessaoSectionState extends State<_SessaoSection> {
  bool _loggingOut = false;
  bool _deleting = false;

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      ShellyPollingService.stop();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao terminar sessão: $e')),
      );
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmCtrl = TextEditingController();
    bool confirmed = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Eliminar conta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta ação é irreversível. Todos os teus dados (dispositivos, leituras, histórico) serão apagados permanentemente.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text(
                'Escreve ELIMINAR para confirmar:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: 'ELIMINAR',
                ),
                onChanged: (_) => setSt(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: confirmCtrl.text == 'ELIMINAR'
                  ? () {
                      confirmed = true;
                      Navigator.of(ctx).pop();
                    }
                  : null,
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );

    if (!confirmed || !mounted) return;
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    setState(() => _deleting = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final db = FirebaseFirestore.instance;
      final uid = widget.uid;

      final devicesSnap = await db
          .collection('users')
          .doc(uid)
          .collection('devices')
          .get();
      final notifsSnap = await db
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .get();

      // Fetch device subcollections in parallel so they are also deleted
      final subSnaps = await Future.wait(
        devicesSnap.docs.expand((d) => [
          db.collection('users').doc(uid)
              .collection('devices').doc(d.id)
              .collection('dailyStats').get(),
          db.collection('users').doc(uid)
              .collection('devices').doc(d.id)
              .collection('readings').get(),
        ]),
      );

      final toDelete = <DocumentReference>[
        ...subSnaps.expand((s) => s.docs.map((d) => d.reference)),
        ...devicesSnap.docs.map((d) => d.reference),
        ...notifsSnap.docs.map((d) => d.reference),
        db.collection('users').doc(uid),
      ];

      // Commit in batches of 400 (Firestore hard limit is 500)
      for (var i = 0; i < toDelete.length; i += 400) {
        final batch = db.batch();
        for (final ref in toDelete.skip(i).take(400)) {
          batch.delete(ref);
        }
        await batch.commit();
      }

      ShellyPollingService.stop();
      await user.delete();
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      final isReauth =
          e.toString().contains('requires-recent-login');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isReauth
                ? 'Faz login novamente antes de eliminar a conta.'
                : 'Erro ao eliminar conta: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Sessão',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _loggingOut ? null : _logout,
            icon: _loggingOut
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            label: const Text('Terminar sessão'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kNavColor,
              side: const BorderSide(color: _kNavColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _deleting ? null : _confirmDelete,
            icon: _deleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.red,
                    ),
                  )
                : const Icon(Icons.delete_forever_outlined, color: Colors.red),
            label: const Text(
              'Eliminar conta',
              style: TextStyle(color: Colors.red),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              backgroundColor: Colors.red.withValues(alpha: 0.05),
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SobreSection
// ══════════════════════════════════════════════════════════════════════════════

class _SobreSection extends StatelessWidget {
  const _SobreSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _kNavColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline, color: _kNavColor, size: 22),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AVERIS v2.0.0',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              SizedBox(height: 2),
              Text(
                'Sistema Inteligente de Gestão de Energia Doméstica',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
