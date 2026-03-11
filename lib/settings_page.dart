import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────
// Tipos de contrato de energia em Portugal
// Fonte: ERSE – tarifas reguladas 2024/2025
// ─────────────────────────────────────────────
enum TipoContrato { simples, biHorario, triHorario }

extension TipoContratoLabel on TipoContrato {
  String get label {
    switch (this) {
      case TipoContrato.simples:
        return 'Simples (tarifa única)';
      case TipoContrato.biHorario:
        return 'Bi-horário (vazio / fora de vazio)';
      case TipoContrato.triHorario:
        return 'Tri-horário (ponta / cheias / vazio)';
    }
  }

  String get descricao {
    switch (this) {
      case TipoContrato.simples:
        return 'Um único preço em qualquer hora do dia.';
      case TipoContrato.biHorario:
        return 'Vazio: 22h–8h (dias úteis) e fim-de-semana.\nFora de vazio: restantes horas.';
      case TipoContrato.triHorario:
        return 'Ponta: horas de maior consumo nacional.\nCheias: períodos intermédios.\nVazio: noite e fins-de-semana.';
    }
  }

  /// Preços de referência ERSE 2024 com IVA 23% (€/kWh)
  Map<String, double> get precosReferencia {
    switch (this) {
      case TipoContrato.simples:
        return {'simples': 0.2134};
      case TipoContrato.biHorario:
        return {'foraVazio': 0.2134, 'vazio': 0.1076};
      case TipoContrato.triHorario:
        return {'ponta': 0.2534, 'cheias': 0.1987, 'vazio': 0.1076};
    }
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isChangingPassword = false;
  bool _isLoggingOut = false;

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum utilizador autenticado.')),
      );
      return;
    }
    setState(() => _isChangingPassword = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email para alterar senha enviado.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível enviar o email de alteração de senha.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao terminar sessão.')));
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Definições'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
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
              return const Center(child: Text('Definições não encontradas.'));
            }

            final data =
                (snapshot.data!.data() as Map?)?.cast<String, dynamic>() ?? {};
            final settings =
                (data['settings'] as Map?)?.cast<String, dynamic>() ?? {};
            final notifications =
                (settings['notifications'] as Map?)?.cast<String, dynamic>() ??
                {};
            final energyContract =
                (settings['energyContract'] as Map?)?.cast<String, dynamic>() ??
                {};

            // Notificações
            final deviceOffline = notifications['deviceOffline'] == true;
            final highConsumption = notifications['highConsumption'] == true;
            final goalReached = notifications['goalReached'] == true;
            final levelUp = notifications['levelUp'] == true;

            final quiet =
                (notifications['quietHours'] as Map?)
                    ?.cast<String, dynamic>() ??
                {};
            final quietEnabled = quiet['enabled'] == true;
            final quietStart = (quiet['start'] as String?) ?? '22:00';
            final quietEnd = (quiet['end'] as String?) ?? '07:00';

            // Contrato de energia
            final tipoStr = (energyContract['tipo'] as String?) ?? 'simples';
            final tipoContrato = TipoContrato.values.firstWhere(
              (t) => t.name == tipoStr,
              orElse: () => TipoContrato.simples,
            );
            final precos =
                (energyContract['precos'] as Map?)?.cast<String, double>() ??
                tipoContrato.precosReferencia;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Energia ──────────────────────────────────────────
                  _EnergiaSection(
                    tipoContrato: tipoContrato,
                    precos: precos,
                    onChanged: (tipo, novosPrecos) {
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({
                            'settings.energyContract.tipo': tipo.name,
                            'settings.energyContract.precos': novosPrecos,
                          });
                    },
                  ),
                  const SizedBox(height: 24),

                  // ── Notificações ─────────────────────────────────────
                  _NotificationsSection(
                    deviceOffline: deviceOffline,
                    highConsumption: highConsumption,
                    goalReached: goalReached,
                    levelUp: levelUp,
                    quietEnabled: quietEnabled,
                    quietStart: quietStart,
                    quietEnd: quietEnd,
                    onChanged: (map) {
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({'settings.notifications': map});
                    },
                  ),
                  const SizedBox(height: 24),

                  // ── Conta ─────────────────────────────────────────────
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Conta',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isChangingPassword
                                  ? null
                                  : _changePassword,
                              icon: _isChangingPassword
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.lock_outline),
                              label: const Text('Alterar senha'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isLoggingOut ? null : _logout,
                              icon: _isLoggingOut
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.logout),
                              label: const Text('Terminar sessão'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade400,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Sobre ────────────────────────────────────────────
                  const _AboutSection(),
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
// SECÇÃO ENERGIA — tipo de contrato + preços por período
// ═══════════════════════════════════════════════════════════════

class _EnergiaSection extends StatefulWidget {
  final TipoContrato tipoContrato;
  final Map<String, double> precos;
  final void Function(TipoContrato tipo, Map<String, double> precos) onChanged;

  const _EnergiaSection({
    required this.tipoContrato,
    required this.precos,
    required this.onChanged,
  });

  @override
  State<_EnergiaSection> createState() => _EnergiaSectionState();
}

class _EnergiaSectionState extends State<_EnergiaSection> {
  late TipoContrato _tipo;
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _tipo = widget.tipoContrato;
    _initControllers(widget.precos);
  }

  void _initControllers(Map<String, double> precos) {
    _controllers = precos.map(
      (key, value) =>
          MapEntry(key, TextEditingController(text: value.toStringAsFixed(4))),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTipoChanged(TipoContrato novoTipo) {
    for (final c in _controllers.values) {
      c.dispose();
    }
    setState(() {
      _tipo = novoTipo;
      _initControllers(novoTipo.precosReferencia);
    });
    _emit();
  }

  void _emit() {
    final precos = _controllers.map(
      (key, c) =>
          MapEntry(key, double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0),
    );
    widget.onChanged(_tipo, precos);
  }

  String _labelForKey(String key) {
    switch (key) {
      case 'simples':
        return 'Tarifa única (€/kWh)';
      case 'foraVazio':
        return 'Fora de vazio (€/kWh)';
      case 'vazio':
        return 'Vazio (€/kWh)';
      case 'ponta':
        return 'Ponta (€/kWh)';
      case 'cheias':
        return 'Cheias (€/kWh)';
      default:
        return key;
    }
  }

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
              'Contrato de Energia',
              style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Escolhe o tipo de contrato que tens com o teu comercializador.',
              style: txt.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),

            // Seletor de tipo
            ...TipoContrato.values.map((tipo) {
              return RadioListTile<TipoContrato>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tipo.label),
                subtitle: Text(
                  tipo.descricao,
                  style: txt.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
                value: tipo,
                groupValue: _tipo,
                onChanged: (v) {
                  if (v != null) _onTipoChanged(v);
                },
              );
            }),

            const Divider(height: 24),

            // Campos de preço
            Text(
              'Preços (€/kWh com IVA)',
              style: txt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Pré-preenchido com tarifas de referência ERSE 2024. '
              'Ajusta ao teu contrato se necessário.',
              style: txt.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            ..._controllers.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: entry.value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _labelForKey(entry.key),
                    prefixText: '€ ',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _emit(),
                ),
              );
            }),

            // Info tarifas
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Os preços são usados para calcular a tua fatura estimada '
                      'e os pontos XP de poupança.',
                      style: txt.bodySmall?.copyWith(
                        color: Colors.blue.shade800,
                      ),
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

// ═══════════════════════════════════════════════════════════════
// SECÇÃO NOTIFICAÇÕES
// ═══════════════════════════════════════════════════════════════

class _NotificationsSection extends StatefulWidget {
  final bool deviceOffline;
  final bool highConsumption;
  final bool goalReached;
  final bool levelUp;
  final bool quietEnabled;
  final String quietStart;
  final String quietEnd;
  final void Function(Map<String, dynamic>) onChanged;

  const _NotificationsSection({
    required this.deviceOffline,
    required this.highConsumption,
    required this.goalReached,
    required this.levelUp,
    required this.quietEnabled,
    required this.quietStart,
    required this.quietEnd,
    required this.onChanged,
  });

  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  late bool _deviceOffline;
  late bool _highConsumption;
  late bool _goalReached;
  late bool _levelUp;
  late bool _quietEnabled;
  late TextEditingController _startController;
  late TextEditingController _endController;

  @override
  void initState() {
    super.initState();
    _deviceOffline = widget.deviceOffline;
    _highConsumption = widget.highConsumption;
    _goalReached = widget.goalReached;
    _levelUp = widget.levelUp;
    _quietEnabled = widget.quietEnabled;
    _startController = TextEditingController(text: widget.quietStart);
    _endController = TextEditingController(text: widget.quietEnd);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged({
      'deviceOffline': _deviceOffline,
      'highConsumption': _highConsumption,
      'goalReached': _goalReached,
      'levelUp': _levelUp,
      'quietHours': {
        'enabled': _quietEnabled,
        'start': _startController.text,
        'end': _endController.text,
      },
    });
  }

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
              'Notificações',
              style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.wifi_off_outlined),
              title: const Text('Dispositivo ficou offline'),
              value: _deviceOffline,
              onChanged: (v) {
                setState(() => _deviceOffline = v);
                _emit();
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.bolt),
              title: const Text('Consumo diário acima do limite'),
              value: _highConsumption,
              onChanged: (v) {
                setState(() => _highConsumption = v);
                _emit();
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.flag_outlined),
              title: const Text('Meta de poupança atingida'),
              value: _goalReached,
              onChanged: (v) {
                setState(() => _goalReached = v);
                _emit();
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.emoji_events_outlined),
              title: const Text('Subida de nível XP'),
              subtitle: const Text('Avisa quando passas para um novo nível'),
              value: _levelUp,
              onChanged: (v) {
                setState(() => _levelUp = v);
                _emit();
              },
            ),
            const Divider(),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.bedtime_outlined),
              title: const Text('Horário silencioso'),
              subtitle: const Text('Não enviar notificações neste período'),
              value: _quietEnabled,
              onChanged: (v) {
                setState(() => _quietEnabled = v);
                _emit();
              },
            ),
            if (_quietEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startController,
                      decoration: const InputDecoration(
                        labelText: 'Início (HH:MM)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _emit(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _endController,
                      decoration: const InputDecoration(
                        labelText: 'Fim (HH:MM)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _emit(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SECÇÃO SOBRE
// ═══════════════════════════════════════════════════════════════

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Sobre o AVERIS',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text('Versão 2.0.0'),
              SizedBox(height: 4),
              Text('Sistema Inteligente de Gestão de Energia Doméstica.'),
            ],
          ),
        ),
      ],
    );
  }
}
