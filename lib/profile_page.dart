import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'settings_page.dart';

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

            final nivel = (data['nivel'] ?? 1) as int;
            final pontos = (data['pontos'] ?? 0) as int;
            final int pontosMeta = (nivel + 1) * 100; // exemplo simples
            final double progress = pontosMeta == 0
                ? 0
                : (pontos / pontosMeta).clamp(0.0, 1.0);

            final goals = Map<String, dynamic>.from(data['goals'] ?? {});
            final double monthlyKwhTarget = (goals['monthlyKwhTarget'] ?? 0)
                .toDouble();
            final double monthlyCostTarget = (goals['monthlyCostTarget'] ?? 0)
                .toDouble();
            final String focus = goals['focus'] ?? 'cost';

            final privacy = Map<String, dynamic>.from(data['privacy'] ?? {});
            final bool shareAnonymous = privacy['shareAnonymous'] ?? false;

            final achievements = Map<String, dynamic>.from(
              data['achievements'] ?? {},
            );
            final bool firstSaving = achievements['firstSaving'] ?? false;
            final bool sevenDaysBelowAverage =
                achievements['sevenDaysBelowAverage'] ?? false;
            final bool topTenPercentMonth =
                achievements['topTenPercentMonth'] ?? false;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Título + botão definições
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
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Avatar
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        // TODO: permitir alterar foto
                      },
                      child: CircleAvatar(
                        radius: 40,
                        backgroundImage: photoUrl != null
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl == null
                            ? const Icon(Icons.person, size: 40)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Nome e email
                  Center(
                    child: Column(
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Card nível / pontos (gamificação – parte 1)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F6FF),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.blue[700],
                              child: Text(
                                '$nivel',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Nível $nivel',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 16,
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
                            Text(
                              '$pontos pontos',
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              'Meta: $pontosMeta',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Os pontos são calculados com base na poupança de energia mensal em relação ao teu consumo médio.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Gamificação – conquistas (parte 2)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Conquistas',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _badge(
                                label: 'Primeira poupança',
                                unlocked: firstSaving,
                              ),
                              _badge(
                                label: '7 dias abaixo da média',
                                unlocked: sevenDaysBelowAverage,
                              ),
                              _badge(
                                label: 'Top 10% do mês',
                                unlocked: topTenPercentMonth,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Privacidade (ponto 4)
                  Card(
                    child: SwitchListTile(
                      title: const Text('Partilhar dados anonimamente'),
                      subtitle: const Text(
                        'Permite aparecer em rankings e estatísticas globais sem mostrar o teu nome.',
                      ),
                      value: shareAnonymous,
                      onChanged: (value) {
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .update({'privacy.shareAnonymous': value});
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Metas de energia + foco (parte 2 – preferências)
                  _GoalsSection(
                    monthlyKwhTarget: monthlyKwhTarget,
                    monthlyCostTarget: monthlyCostTarget,
                    focus: focus,
                    onSave: (kwh, cost, newFocus) {
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({
                            'goals.monthlyKwhTarget': kwh,
                            'goals.monthlyCostTarget': cost,
                            'goals.focus': newFocus,
                          });
                    },
                  ),

                  const SizedBox(height: 32),

                  // Botão Definições (atalho claro)
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('Definições'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade400,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _badge({required String label, required bool unlocked}) {
    return Chip(
      avatar: Icon(
        unlocked ? Icons.lock_open : Icons.lock,
        size: 18,
        color: unlocked ? Colors.green : Colors.grey,
      ),
      label: Text(label),
      backgroundColor: unlocked ? Colors.green.shade50 : Colors.grey.shade200,
    );
  }
}

// Secção de metas + foco (reutilizada da resposta anterior, adaptada)
class _GoalsSection extends StatefulWidget {
  final double monthlyKwhTarget;
  final double monthlyCostTarget;
  final String focus;
  final void Function(double kwh, double cost, String focus) onSave;

  const _GoalsSection({
    required this.monthlyKwhTarget,
    required this.monthlyCostTarget,
    required this.focus,
    required this.onSave,
  });

  @override
  State<_GoalsSection> createState() => _GoalsSectionState();
}

class _GoalsSectionState extends State<_GoalsSection> {
  late TextEditingController _kwhController;
  late TextEditingController _costController;
  late String _focus;

  @override
  void initState() {
    super.initState();
    _kwhController = TextEditingController(
      text: widget.monthlyKwhTarget > 0
          ? widget.monthlyKwhTarget.toStringAsFixed(0)
          : '',
    );
    _costController = TextEditingController(
      text: widget.monthlyCostTarget > 0
          ? widget.monthlyCostTarget.toStringAsFixed(0)
          : '',
    );
    _focus = widget.focus;
  }

  @override
  void dispose() {
    _kwhController.dispose();
    _costController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Metas de energia',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _kwhController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Meta mensal de consumo (kWh)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _costController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Meta mensal de custo (€)',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'O que é mais importante para ti?',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cost', label: Text('Conta (€)')),
                ButtonSegment(value: 'co2', label: Text('CO₂')),
                ButtonSegment(value: 'competition', label: Text('Competição')),
              ],
              selected: {_focus},
              onSelectionChanged: (sel) {
                setState(() => _focus = sel.first);
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () {
                  final kwh =
                      double.tryParse(
                        _kwhController.text.replaceAll(',', '.'),
                      ) ??
                      0;
                  final cost =
                      double.tryParse(
                        _costController.text.replaceAll(',', '.'),
                      ) ??
                      0;
                  widget.onSave(kwh, cost, _focus);
                },
                child: const Text('Guardar metas'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
