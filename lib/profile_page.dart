import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'settings_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    // Aqui podes buscar estes valores de Firestore; por enquanto, são mocks:
    const int nivelAtual = 2;
    const int pontosAtuais = 800;
    const int pontosMeta = 1000;

    final double progress = pontosMeta == 0
        ? 0
        : (pontosAtuais / pontosMeta).clamp(0.0, 1.0);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Perfil',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // Avatar
              const Center(
                child: CircleAvatar(
                  radius: 40,
                  child: Icon(Icons.person, size: 40),
                ),
              ),
              const SizedBox(height: 24),

              // Nome e email
              Center(
                child: Column(
                  children: [
                    Text(
                      'Nome: ${user?.displayName ?? 'Utilizador'}',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Email: ${user?.email ?? 'sem email'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Card de nível / pontos
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
                            '$nivelAtual',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Nível $nivelAtual',
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
                          '$pontosAtuais pontos',
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

              const SizedBox(height: 32),

              // Botão Definições
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
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
        ),
      ),
    );
  }
}
