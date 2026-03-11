import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'settings_page.dart';

// ─────────────────────────────────────────────
// Sistema de Níveis XP
// ─────────────────────────────────────────────
class XpLevel {
  final int nivel;
  final String nome;
  final String emoji;
  final Color cor;
  final int xpMinimo;
  final int xpMaximo; // -1 = sem limite (último nível)
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

XpLevel xpLevelForPontos(int pontos) {
  for (int i = kNiveis.length - 1; i >= 0; i--) {
    if (pontos >= kNiveis[i].xpMinimo) return kNiveis[i];
  }
  return kNiveis.first;
}

double xpProgress(int pontos, XpLevel nivel) {
  if (nivel.xpMaximo == -1) return 1.0;
  final range = nivel.xpMaximo - nivel.xpMinimo + 1;
  final dentro = pontos - nivel.xpMinimo;
  return (dentro / range).clamp(0.0, 1.0);
}

// ─────────────────────────────────────────────
// Conquistas
// ─────────────────────────────────────────────
class _Conquista {
  final String key;
  final String label;
  final String descricao;
  final IconData icon;
  final Color cor;

  const _Conquista({
    required this.key,
    required this.label,
    required this.descricao,
    required this.icon,
    required this.cor,
  });
}

const List<_Conquista> kConquistas = [
  _Conquista(
    key: 'firstSaving',
    label: 'Primeira Poupança',
    descricao: 'Poupaste energia pela primeira vez.',
    icon: Icons.eco,
    cor: Color(0xFF66BB6A),
  ),
  _Conquista(
    key: 'sevenDaysBelowAverage',
    label: '7 Dias Abaixo da Média',
    descricao: 'Consumiste menos do que a tua média durante 7 dias seguidos.',
    icon: Icons.trending_down,
    cor: Color(0xFF42A5F5),
  ),
  _Conquista(
    key: 'topTenPercentMonth',
    label: 'Top 10% do Mês',
    descricao: 'Estiveste no top 10% de utilizadores mais eficientes.',
    icon: Icons.workspace_premium,
    cor: Color(0xFFFFCA28),
  ),
  _Conquista(
    key: 'reachedLevel3',
    label: 'Nível Eficiente',
    descricao: 'Atingiste o nível 3 – Eficiente.',
    icon: Icons.bolt,
    cor: Color(0xFFFFB300),
  ),
  _Conquista(
    key: 'savedInWeekend',
    label: 'Fim de Semana Verde',
    descricao: 'Poupaste energia nos dois dias do fim de semana.',
    icon: Icons.weekend,
    cor: Color(0xFF26A69A),
  ),
  _Conquista(
    key: 'reachedLevel5',
    label: 'Mestre da Energia',
    descricao: 'Atingiste o nível 5 – Mestre.',
    icon: Icons.emoji_events,
    cor: Color(0xFF7E57C2),
  ),
];

// ═══════════════════════════════════════════════════════════════
// PROFILE PAGE
// ═══════════════════════════════════════════════════════════════

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final uid = user!.uid;

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: Text('Dados de perfil não encontrados.'),
              );
            }

            final raw = snapshot.data!.data() as Map;
            final data = Map<String, dynamic>.from(raw);

            final name = data['name'] ?? user.displayName ?? 'Utilizador';
            final email = data['email'] ?? user.email ?? 'sem email';
            final photoUrl = data['photoUrl'] as String?;

            final pontos = (data['pontos'] ?? 0) as int;
            final nivel = xpLevelForPontos(pontos);
            final progress = xpProgress(pontos, nivel);
            final proximoNivel = nivel.nivel < kNiveis.length
                ? kNiveis[nivel.nivel] // índice = nivel - 1, próximo = nivel
                : null;

            final achievements = Map<String, dynamic>.from(
              data['achievements'] ?? {},
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Cabeçalho ───────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Perfil',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Avatar + nome + email + editar ───────────────────
                  _ProfileHeader(
                    uid: uid,
                    name: name,
                    email: email,
                    photoUrl: photoUrl,
                  ),
                  const SizedBox(height: 24),

                  // ── Card XP / Nível ──────────────────────────────────
                  _XpCard(
                    pontos: pontos,
                    nivel: nivel,
                    progress: progress,
                    proximoNivel: proximoNivel,
                  ),
                  const SizedBox(height: 24),

                  // ── Conquistas ───────────────────────────────────────
                  _ConquistasCard(achievements: achievements),
                  const SizedBox(height: 24),

                  // ── Níveis disponíveis ───────────────────────────────
                  _NiveisCard(nivelAtual: nivel),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PROFILE HEADER — avatar, nome editável, email
// ═══════════════════════════════════════════════════════════════

class _ProfileHeader extends StatefulWidget {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;

  const _ProfileHeader({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
  });

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  bool _editing = false;
  late TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
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
    final theme = Theme.of(context);

    return Column(
      children: [
        // Avatar
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundImage: widget.photoUrl != null
                  ? NetworkImage(widget.photoUrl!)
                  : null,
              child: widget.photoUrl == null
                  ? const Icon(Icons.person, size: 44)
                  : null,
            ),
            // Botão editar foto (futuro)
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.blue.shade600,
              child: const Icon(
                Icons.camera_alt,
                size: 14,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Nome — visualização ou edição
        if (_editing)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => _saveName(),
                ),
              ),
              const SizedBox(width: 8),
              _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: _saveName,
                    ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () {
                  setState(() {
                    _editing = false;
                    _nameController.text = widget.name;
                  });
                },
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() => _editing = true),
                child: Icon(Icons.edit, size: 16, color: Colors.grey[500]),
              ),
            ],
          ),

        const SizedBox(height: 4),
        Text(
          widget.email,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// XP CARD
// ═══════════════════════════════════════════════════════════════

class _XpCard extends StatelessWidget {
  final int pontos;
  final XpLevel nivel;
  final double progress;
  final XpLevel? proximoNivel;

  const _XpCard({
    required this.pontos,
    required this.nivel,
    required this.progress,
    this.proximoNivel,
  });

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final isMaxLevel = proximoNivel == null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [nivel.cor.withOpacity(0.15), nivel.cor.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: nivel.cor.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: nivel.cor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título do nível
          Row(
            children: [
              Text(nivel.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: nivel.cor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Nível ${nivel.nivel}',
                          style: txt.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nivel.nome,
                    style: txt.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            nivel.descricao,
            style: txt.bodySmall?.copyWith(color: Colors.grey[700]),
          ),
          const SizedBox(height: 16),

          // Barra de progresso
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 14,
              backgroundColor: nivel.cor.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(nivel.cor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$pontos XP', style: txt.bodySmall),
              if (isMaxLevel)
                Text('Nível máximo! 🎉', style: txt.bodySmall)
              else
                Text(
                  'Próximo nível: ${proximoNivel!.xpMinimo} XP',
                  style: txt.bodySmall,
                ),
            ],
          ),

          // Como ganhar XP
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Como ganhar XP',
            style: txt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _xpDica(context, '⚡', 'Dia abaixo da média de consumo', '+5 XP'),
          _xpDica(context, '📅', 'Meta semanal atingida', '+20 XP'),
          _xpDica(context, '🏅', 'Meta mensal atingida', '+50 XP'),
          _xpDica(context, '🌍', '1 kWh poupado vs. média', '+2 XP'),
        ],
      ),
    );
  }

  Widget _xpDica(BuildContext context, String emoji, String label, String xp) {
    final txt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(emoji),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: txt.bodySmall)),
          Text(
            xp,
            style: txt.bodySmall?.copyWith(
              color: nivel.cor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// CONQUISTAS CARD
// ═══════════════════════════════════════════════════════════════

class _ConquistasCard extends StatelessWidget {
  final Map<String, dynamic> achievements;

  const _ConquistasCard({required this.achievements});

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final desbloqueadas = achievements.values.where((v) => v == true).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Conquistas',
                  style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '$desbloqueadas/${kConquistas.length}',
                  style: txt.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...kConquistas.map((c) {
              final unlocked = achievements[c.key] == true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: unlocked
                            ? c.cor.withOpacity(0.15)
                            : Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        unlocked ? c.icon : Icons.lock_outline,
                        size: 20,
                        color: unlocked ? c.cor : Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.label,
                            style: txt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: unlocked ? null : Colors.grey.shade500,
                            ),
                          ),
                          Text(
                            c.descricao,
                            style: txt.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (unlocked)
                      Icon(Icons.check_circle, size: 18, color: c.cor),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// NÍVEIS CARD — tabela de todos os níveis
// ═══════════════════════════════════════════════════════════════

class _NiveisCard extends StatelessWidget {
  final XpLevel nivelAtual;

  const _NiveisCard({required this.nivelAtual});

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Todos os Níveis',
              style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...kNiveis.map((n) {
              final isAtual = n.nivel == nivelAtual.nivel;
              final bloqueado = n.nivel > nivelAtual.nivel;
              final xpRange = n.xpMaximo == -1
                  ? '${n.xpMinimo}+ XP'
                  : '${n.xpMinimo}–${n.xpMaximo} XP';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isAtual
                      ? n.cor.withOpacity(0.12)
                      : bloqueado
                      ? Colors.grey.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: isAtual ? Border.all(color: n.cor, width: 1.5) : null,
                ),
                child: Row(
                  children: [
                    Text(
                      bloqueado ? '🔒' : n.emoji,
                      style: TextStyle(
                        fontSize: 22,
                        color: bloqueado ? null : null,
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
                                'Nível ${n.nivel} · ${n.nome}',
                                style: txt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: bloqueado
                                      ? Colors.grey.shade400
                                      : null,
                                ),
                              ),
                              if (isAtual) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: n.cor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Atual',
                                    style: txt.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            xpRange,
                            style: txt.bodySmall?.copyWith(
                              color: bloqueado
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
