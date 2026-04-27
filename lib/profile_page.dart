// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'settings_page.dart';

// ── Constants ──────────────────────────────────────────────────────────────────

const _kNavColor = Color(0xFF0f1e3d);
const _kAccent = Color(0xFF38d9a9);

// ── XP Level model ─────────────────────────────────────────────────────────────

class XpLevel {
  final int nivel;
  final String nome;
  final String emoji;
  final Color cor;
  final int xpMinimo;
  final int xpMaximo; // -1 = no upper limit (last level)
  final String descricao;

  const XpLevel({
    required this.nivel,
    required this.nome,
    required this.emoji,
    required this.cor,
    required this.xpMinimo,
    required this.xpMaximo,
    required this.descricao,
  });
}

const List<XpLevel> kNiveis = [
  XpLevel(
    nivel: 1,
    nome: 'Aprendiz',
    emoji: '🌱',
    cor: Color(0xFF78C850),
    xpMinimo: 0,
    xpMaximo: 99,
    descricao: 'Estás a dar os primeiros passos na poupança de energia.',
  ),
  XpLevel(
    nivel: 2,
    nome: 'Poupador',
    emoji: '💡',
    cor: Color(0xFF4FC3F7),
    xpMinimo: 100,
    xpMaximo: 299,
    descricao: 'Já tens bons hábitos de consumo.',
  ),
  XpLevel(
    nivel: 3,
    nome: 'Eficiente',
    emoji: '⚡',
    cor: Color(0xFFFFB300),
    xpMinimo: 300,
    xpMaximo: 599,
    descricao: 'Consomes menos do que a média. Muito bem!',
  ),
  XpLevel(
    nivel: 4,
    nome: 'Expert',
    emoji: '🔋',
    cor: Color(0xFFFF7043),
    xpMinimo: 600,
    xpMaximo: 1099,
    descricao: 'Dominas a gestão de energia em casa.',
  ),
  XpLevel(
    nivel: 5,
    nome: 'Mestre',
    emoji: '🏆',
    cor: Color(0xFF7E57C2),
    xpMinimo: 1100,
    xpMaximo: 1999,
    descricao: 'És um exemplo de eficiência energética.',
  ),
  XpLevel(
    nivel: 6,
    nome: 'Lenda',
    emoji: '🌟',
    cor: Color(0xFFF06292),
    xpMinimo: 2000,
    xpMaximo: -1,
    descricao: 'Nível máximo. És uma inspiração para todos!',
  ),
];

XpLevel xpLevelForPontos(int pontosTotal) {
  for (int i = kNiveis.length - 1; i >= 0; i--) {
    if (pontosTotal >= kNiveis[i].xpMinimo) return kNiveis[i];
  }
  return kNiveis.first;
}

double xpProgress(int pontosTotal, XpLevel nivel) {
  if (nivel.xpMaximo == -1) return 1.0;
  final range = nivel.xpMaximo - nivel.xpMinimo + 1;
  return ((pontosTotal - nivel.xpMinimo) / range).clamp(0.0, 1.0);
}

// ── Conquistas ─────────────────────────────────────────────────────────────────

class Conquista {
  final String key;
  final String label;
  final String descricao;
  final IconData icon;
  final Color cor;

  const Conquista({
    required this.key,
    required this.label,
    required this.descricao,
    required this.icon,
    required this.cor,
  });
}

const List<Conquista> kConquistas = [
  Conquista(
    key: 'firstSaving',
    label: 'Primeira Poupança',
    descricao: 'Poupaste ≥5% abaixo da tua média num dia.',
    icon: Icons.eco,
    cor: Color(0xFF66BB6A),
  ),
  Conquista(
    key: 'sevenDaysBelowAverage',
    label: '7 Dias Abaixo da Média',
    descricao: 'Consumiste abaixo da média 7 dias consecutivos.',
    icon: Icons.trending_down,
    cor: Color(0xFF42A5F5),
  ),
  Conquista(
    key: 'streak3Days',
    label: '3 Dias Consecutivos',
    descricao: 'Consumiste abaixo da média 3 dias seguidos.',
    icon: Icons.local_fire_department,
    cor: Color(0xFFFF7043),
  ),
  Conquista(
    key: 'reachedLevel3',
    label: 'Nível Eficiente',
    descricao: 'Atingiste o nível 3 – Eficiente.',
    icon: Icons.bolt,
    cor: Color(0xFFFFB300),
  ),
  Conquista(
    key: 'savedInWeekend',
    label: 'Fim de Semana Verde',
    descricao: 'Poupaste ≥5% abaixo da média num fim de semana.',
    icon: Icons.weekend,
    cor: Color(0xFF26A69A),
  ),
  Conquista(
    key: 'reachedLevel5',
    label: 'Mestre da Energia',
    descricao: 'Atingiste o nível 5 – Mestre.',
    icon: Icons.emoji_events,
    cor: Color(0xFF7E57C2),
  ),
];

// ══════════════════════════════════════════════════════════════════════════════
// ProfilePage
// ══════════════════════════════════════════════════════════════════════════════

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final uid = user.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: _kNavColor,
        foregroundColor: Colors.white,
        tooltip: 'Definições',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        ),
        child: const Icon(Icons.settings),
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
            return const Center(child: Text('Perfil não encontrado.'));
          }

          final data = snap.data!.data()!;
          final name = (data['name'] as String?)?.trim().isNotEmpty == true
              ? data['name'] as String
              : user.displayName ?? 'Utilizador';
          final email = (data['email'] as String?) ?? user.email ?? '';
          final photoUrl = data['photoUrl'] as String?;
          final pontosTotal = (data['pontosTotal'] as num?)?.toInt() ?? 0;
          final streakDias = (data['streakDias'] as num?)?.toInt() ?? 0;
          final goals =
              (data['goals'] as Map?)?.cast<String, dynamic>() ?? {};
          final achievements =
              (data['achievements'] as Map?)?.cast<String, dynamic>() ?? {};
          final nivel = xpLevelForPontos(pontosTotal);

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroSection(
                  uid: uid,
                  name: name,
                  email: email,
                  photoUrl: photoUrl,
                  nivel: nivel,
                  pontosTotal: pontosTotal,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _XpCard(
                        uid: uid,
                        pontosTotal: pontosTotal,
                        streakDias: streakDias,
                        nivel: nivel,
                      ),
                      const SizedBox(height: 16),
                      _GoalsRow(uid: uid, goals: goals, data: data),
                      const SizedBox(height: 16),
                      _AchievementsGrid(achievements: achievements),
                      const SizedBox(height: 16),
                      _NiveisSection(nivelAtual: nivel),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _HeroSection
// ══════════════════════════════════════════════════════════════════════════════

class _HeroSection extends StatefulWidget {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final XpLevel nivel;
  final int pontosTotal;

  const _HeroSection({
    required this.uid,
    required this.name,
    required this.email,
    required this.nivel,
    required this.pontosTotal,
    this.photoUrl,
  });

  @override
  State<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<_HeroSection> {
  bool _editing = false;
  late TextEditingController _nameCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
  }

  @override
  void didUpdateWidget(_HeroSection old) {
    super.didUpdateWidget(old);
    if (!_editing && old.name != widget.name) {
      _nameCtrl.text = widget.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _saveName() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({'name': newName});
      await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
      if (mounted) setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.nivel;
    return Container(
      color: _kNavColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            children: [
              // Avatar
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _kAccent, width: 3),
                    ),
                    child: ClipOval(
                      child: widget.photoUrl != null
                          ? Image.network(
                              widget.photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _InitialsCircle(_initials(widget.name)),
                            )
                          : _InitialsCircle(_initials(widget.name)),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Funcionalidade em breve')),
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: _kAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 15,
                        color: _kNavColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Name (editable)
              if (_editing)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _nameCtrl,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: _kAccent),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: _kAccent, width: 2),
                          ),
                        ),
                        onSubmitted: (_) => _saveName(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_saving)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _kAccent,
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _saveName,
                        child: const Icon(
                          Icons.check_circle,
                          color: _kAccent,
                          size: 26,
                        ),
                      ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => setState(() {
                        _editing = false;
                        _nameCtrl.text = widget.name;
                      }),
                      child: const Icon(
                        Icons.cancel,
                        color: Colors.white54,
                        size: 26,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() => _editing = true),
                      child: const Icon(
                        Icons.edit,
                        size: 16,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 4),
              Text(
                widget.email,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 12),

              // Level badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: n.cor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: n.cor.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  '${n.emoji}  Nível ${n.nivel} — ${n.nome} · ${widget.pontosTotal} XP',
                  style: TextStyle(
                    color: n.cor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InitialsCircle extends StatelessWidget {
  final String initials;
  const _InitialsCircle(this.initials);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kNavColor,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: _kAccent,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _XpCard
// ══════════════════════════════════════════════════════════════════════════════

class _XpCard extends StatelessWidget {
  final String uid;
  final int pontosTotal;
  final int streakDias;
  final XpLevel nivel;

  const _XpCard({
    required this.uid,
    required this.pontosTotal,
    required this.streakDias,
    required this.nivel,
  });

  @override
  Widget build(BuildContext context) {
    final isMaxLevel = nivel.xpMaximo == -1;
    final progress = xpProgress(pontosTotal, nivel);
    final proximoNivel =
        nivel.nivel < kNiveis.length ? kNiveis[nivel.nivel] : null;
    final paraSubir = isMaxLevel ? 0 : (nivel.xpMaximo + 1) - pontosTotal;

    return Container(
      decoration: BoxDecoration(
        color: _kNavColor,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nível ${nivel.nivel} — ${nivel.nome}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                isMaxLevel
                    ? '$pontosTotal XP'
                    : '$pontosTotal / ${nivel.xpMaximo} XP',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(nivel.cor),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isMaxLevel
                ? 'Nível máximo! 🎉'
                : '$paraSubir XP para ${proximoNivel!.nome}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // Stats grid
          Row(
            children: [
              _XpStatCell(label: 'XP total', value: '$pontosTotal'),
              _XpStatCell(
                label: 'Sequência',
                value: '$streakDias 🔥',
              ),
              _XpStatCell(
                label: 'Para subir',
                value: isMaxLevel ? '—' : '+$paraSubir',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _XpStatCell extends StatelessWidget {
  final String label;
  final String value;

  const _XpStatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _GoalsRow
// ══════════════════════════════════════════════════════════════════════════════

class _GoalsRow extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> goals;
  final Map<String, dynamic> data;

  const _GoalsRow({
    required this.uid,
    required this.goals,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final kwhTarget = (goals['monthlyKwhTarget'] as num?)?.toDouble() ?? 0.0;
    final costTarget = (goals['monthlyCostTarget'] as num?)?.toDouble() ?? 0.0;
    final consumoMes = (data['consumoMes'] as num?)?.toDouble() ?? 0.0;
    final energyPrice =
        ((data['settings'] as Map?)?['energyPrice'] as num?)?.toDouble() ??
            0.22;
    final custoMes = consumoMes * energyPrice;

    return Row(
      children: [
        Expanded(
          child: _GoalCard(
            uid: uid,
            label: 'Meta kWh',
            unit: 'kWh',
            current: consumoMes,
            target: kwhTarget,
            color: _kAccent,
            fieldKey: 'monthlyKwhTarget',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GoalCard(
            uid: uid,
            label: 'Meta €',
            unit: '€',
            current: custoMes,
            target: costTarget,
            color: const Color(0xFF4FC3F7),
            fieldKey: 'monthlyCostTarget',
          ),
        ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  final String uid;
  final String label;
  final String unit;
  final double current;
  final double target;
  final Color color;
  final String fieldKey;

  const _GoalCard({
    required this.uid,
    required this.label,
    required this.unit,
    required this.current,
    required this.target,
    required this.color,
    required this.fieldKey,
  });

  void _openEditor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _GoalEditorSheet(
        uid: uid,
        label: label,
        unit: unit,
        current: target,
        color: color,
        fieldKey: fieldKey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTarget = target > 0;
    final progress =
        hasTarget ? (current / target).clamp(0.0, 1.0) : 0.0;
    final overBudget = hasTarget && current > target;

    return GestureDetector(
      onTap: () => _openEditor(context),
      child: Container(
        padding: const EdgeInsets.all(14),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF374151),
                  ),
                ),
                Icon(Icons.edit, size: 14, color: Colors.grey.shade400),
              ],
            ),
            const SizedBox(height: 6),
            if (!hasTarget)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sem meta definida',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => _openEditor(context),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: color,
                    ),
                    child: const Text(
                      'Definir meta',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              )
            else ...[
              Text(
                '${current.toStringAsFixed(1)} / ${target.toStringAsFixed(0)} $unit',
                style: TextStyle(
                  fontSize: 12,
                  color: overBudget ? Colors.red : const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    overBudget ? Colors.red : color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GoalEditorSheet extends StatefulWidget {
  final String uid;
  final String label;
  final String unit;
  final double current;
  final Color color;
  final String fieldKey;

  const _GoalEditorSheet({
    required this.uid,
    required this.label,
    required this.unit,
    required this.current,
    required this.color,
    required this.fieldKey,
  });

  @override
  State<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<_GoalEditorSheet> {
  late double _value;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _value = widget.current > 0 ? widget.current : 50;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .update({'goals.${widget.fieldKey}': _value});
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isKwh = widget.unit == 'kWh';
    final maxVal = isKwh ? 500.0 : 200.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Editar ${widget.label}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              '${_value.toStringAsFixed(0)} ${widget.unit}',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: widget.color,
              ),
            ),
          ),
          Slider(
            value: _value.clamp(0, maxVal),
            min: 0,
            max: maxVal,
            divisions: isKwh ? 100 : 200,
            activeColor: widget.color,
            onChanged: (v) => setState(() => _value = v),
          ),
          const SizedBox(height: 12),
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
// _AchievementsGrid
// ══════════════════════════════════════════════════════════════════════════════

class _AchievementsGrid extends StatelessWidget {
  final Map<String, dynamic> achievements;

  const _AchievementsGrid({required this.achievements});

  void _showDetail(BuildContext context, Conquista c, bool unlocked) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: unlocked
                    ? c.cor.withValues(alpha: 0.15)
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                unlocked ? c.icon : Icons.lock_outline,
                size: 32,
                color: unlocked ? c.cor : Colors.grey,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              c.label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              c.descricao,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: unlocked
                    ? c.cor.withValues(alpha: 0.12)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                unlocked ? 'Desbloqueada ✓' : 'Ainda não desbloqueada',
                style: TextStyle(
                  color: unlocked ? c.cor : Colors.grey,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unlocked =
        kConquistas.where((c) => achievements[c.key] == true).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Conquistas',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _kNavColor,
                ),
              ),
              Text(
                '$unlocked / ${kConquistas.length}',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.9,
            children: kConquistas.map((c) {
              final isUnlocked = achievements[c.key] == true;
              return _AchievementTile(
                conquista: c,
                unlocked: isUnlocked,
                onTap: () => _showDetail(context, c, isUnlocked),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final Conquista conquista;
  final bool unlocked;
  final VoidCallback onTap;

  const _AchievementTile({
    required this.conquista,
    required this.unlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: unlocked ? 1.0 : 0.4,
        child: Container(
          decoration: BoxDecoration(
            color: unlocked
                ? conquista.cor.withValues(alpha: 0.12)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                unlocked ? conquista.icon : Icons.lock_outline,
                color: unlocked ? conquista.cor : Colors.grey,
                size: 28,
              ),
              const SizedBox(height: 6),
              Text(
                conquista.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color:
                      unlocked ? conquista.cor : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _NiveisSection
// ══════════════════════════════════════════════════════════════════════════════

class _NiveisSection extends StatelessWidget {
  final XpLevel nivelAtual;

  const _NiveisSection({required this.nivelAtual});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            'Todos os Níveis',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _kNavColor,
            ),
          ),
          const SizedBox(height: 12),
          ...kNiveis.map((n) => _NivelItem(
                nivel: n,
                isAtual: n.nivel == nivelAtual.nivel,
                bloqueado: n.nivel > nivelAtual.nivel,
              )),
        ],
      ),
    );
  }
}

class _NivelItem extends StatelessWidget {
  final XpLevel nivel;
  final bool isAtual;
  final bool bloqueado;

  const _NivelItem({
    required this.nivel,
    required this.isAtual,
    required this.bloqueado,
  });

  @override
  Widget build(BuildContext context) {
    final xpRange = nivel.xpMaximo == -1
        ? '${nivel.xpMinimo}+ XP'
        : '${nivel.xpMinimo}–${nivel.xpMaximo} XP';

    return Opacity(
      opacity: bloqueado ? 0.4 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isAtual
              ? nivel.cor.withValues(alpha: 0.08)
              : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: isAtual
              ? Border.all(color: _kAccent, width: 2)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            // Level circle
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: nivel.cor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${nivel.nivel}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${nivel.emoji} ${nivel.nome}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (isAtual) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Atual',
                            style: TextStyle(
                              color: _kNavColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    xpRange,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
