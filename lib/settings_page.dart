import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
      Navigator.of(context).pop(); // AuthGate trata do resto
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

            // ---------- LEITURA SEGURA DO DOCUMENTO ----------
            final data =
                (snapshot.data!.data() as Map?)?.cast<String, dynamic>() ?? {};
            final settings =
                (data['settings'] as Map?)?.cast<String, dynamic>() ?? {};
            final notifications =
                (settings['notifications'] as Map?)?.cast<String, dynamic>() ??
                {};
            final automations =
                (settings['automations'] as Map?)?.cast<String, dynamic>() ??
                {};

            // sem tema
            final language = (settings['language'] as String?) ?? 'pt';
            final energyPrice = (settings['energyPrice'] is num)
                ? (settings['energyPrice'] as num).toDouble()
                : 0.22;
            final includeTax = settings['includeTax'] == true;

            final deviceOffline = notifications['deviceOffline'] == true;
            final highConsumption = notifications['highConsumption'] == true;
            final goalReached = notifications['goalReached'] == true;

            final quiet =
                (notifications['quietHours'] as Map?)
                    ?.cast<String, dynamic>() ??
                {};
            final quietEnabled = quiet['enabled'] == true;
            final quietStart = (quiet['start'] as String?) ?? '22:00';
            final quietEnd = (quiet['end'] as String?) ?? '07:00';

            final weekdayMorning =
                (automations['weekdayMorningOn'] as Map?)
                    ?.cast<String, dynamic>() ??
                {};
            final turnAllOffAtMidnight =
                automations['turnAllOffAtMidnight'] == true;
            final morningEnabled = weekdayMorning['enabled'] == true;
            final morningTime = (weekdayMorning['time'] as String?) ?? '07:00';

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AppSection(
                    languageValue: language,
                    energyPrice: energyPrice,
                    includeTax: includeTax,
                    onChanged: (newLang, newPrice, newIncludeTax) {
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({
                            'settings.language': newLang,
                            'settings.energyPrice': newPrice,
                            'settings.includeTax': newIncludeTax,
                          });
                    },
                  ),
                  const SizedBox(height: 24),
                  _NotificationsSection(
                    deviceOffline: deviceOffline,
                    highConsumption: highConsumption,
                    goalReached: goalReached,
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
                  _AutomationsSection(
                    turnAllOffAtMidnight: turnAllOffAtMidnight,
                    morningEnabled: morningEnabled,
                    morningTime: morningTime,
                    onChanged: (map) {
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({'settings.automations': map});
                    },
                  ),
                  const SizedBox(height: 24),

                  // Alterar senha
                  Center(
                    child: ElevatedButton(
                      onPressed: _isChangingPassword ? null : _changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade400,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _isChangingPassword
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Alterar senha'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Terminar sessão
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _isLoggingOut ? null : _logout,
                      icon: const Icon(Icons.logout),
                      label: _isLoggingOut
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Terminar sessão'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Divider(),
                  const SizedBox(height: 16),

                  // Sobre & suporte
                  const _AboutSection(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ===================== APP SECTION (SEM TEMA) =====================

class _AppSection extends StatefulWidget {
  final String languageValue;
  final double energyPrice;
  final bool includeTax;
  final void Function(String language, double energyPrice, bool includeTax)
  onChanged;

  const _AppSection({
    required this.languageValue,
    required this.energyPrice,
    required this.includeTax,
    required this.onChanged,
  });

  @override
  State<_AppSection> createState() => _AppSectionState();
}

class _AppSectionState extends State<_AppSection> {
  late String _language;
  late TextEditingController _priceController;
  late bool _includeTax;

  @override
  void initState() {
    super.initState();
    _language = widget.languageValue;
    _priceController = TextEditingController(
      text: widget.energyPrice.toStringAsFixed(3),
    );
    _includeTax = widget.includeTax;
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _emit() {
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '.')) ??
        widget.energyPrice;
    widget.onChanged(_language, price, _includeTax);
  }

  @override
  Widget build(BuildContext context) {
    final themeText = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aplicação',
              style: themeText.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text('Idioma'),
            const SizedBox(height: 4),
            DropdownButton<String>(
              value: _language,
              items: const [
                DropdownMenuItem(value: 'pt', child: Text('Português')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _language = value);
                _emit();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Preço da energia (€/kWh)',
              ),
              onChanged: (_) => _emit(),
            ),
            SwitchListTile(
              title: const Text('Incluir impostos no cálculo'),
              value: _includeTax,
              onChanged: (v) {
                setState(() => _includeTax = v);
                _emit();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== NOTIFICATIONS SECTION =====================

class _NotificationsSection extends StatefulWidget {
  final bool deviceOffline;
  final bool highConsumption;
  final bool goalReached;
  final bool quietEnabled;
  final String quietStart;
  final String quietEnd;
  final void Function(Map<String, dynamic>) onChanged;

  const _NotificationsSection({
    required this.deviceOffline,
    required this.highConsumption,
    required this.goalReached,
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
  late bool _quietEnabled;
  late TextEditingController _startController;
  late TextEditingController _endController;

  @override
  void initState() {
    super.initState();
    _deviceOffline = widget.deviceOffline;
    _highConsumption = widget.highConsumption;
    _goalReached = widget.goalReached;
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
              title: const Text('Dispositivo ficou offline'),
              value: _deviceOffline,
              onChanged: (v) {
                setState(() => _deviceOffline = v);
                _emit();
              },
            ),
            SwitchListTile(
              title: const Text('Consumo diário acima do limite'),
              value: _highConsumption,
              onChanged: (v) {
                setState(() => _highConsumption = v);
                _emit();
              },
            ),
            SwitchListTile(
              title: const Text('Meta de poupança atingida'),
              value: _goalReached,
              onChanged: (v) {
                setState(() => _goalReached = v);
                _emit();
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Horário silencioso'),
              subtitle: const Text('Não enviar notificações neste período'),
              value: _quietEnabled,
              onChanged: (v) {
                setState(() => _quietEnabled = v);
                _emit();
              },
            ),
            if (_quietEnabled) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startController,
                      decoration: const InputDecoration(
                        labelText: 'Início (HH:MM)',
                      ),
                      onChanged: (_) => _emit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _endController,
                      decoration: const InputDecoration(
                        labelText: 'Fim (HH:MM)',
                      ),
                      onChanged: (_) => _emit(),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===================== AUTOMATIONS SECTION =====================

class _AutomationsSection extends StatefulWidget {
  final bool turnAllOffAtMidnight;
  final bool morningEnabled;
  final String morningTime;
  final void Function(Map<String, dynamic>) onChanged;

  const _AutomationsSection({
    required this.turnAllOffAtMidnight,
    required this.morningEnabled,
    required this.morningTime,
    required this.onChanged,
  });

  @override
  State<_AutomationsSection> createState() => _AutomationsSectionState();
}

class _AutomationsSectionState extends State<_AutomationsSection> {
  late bool _turnAllOffAtMidnight;
  late bool _morningEnabled;
  late TextEditingController _timeController;

  @override
  void initState() {
    super.initState();
    _turnAllOffAtMidnight = widget.turnAllOffAtMidnight;
    _morningEnabled = widget.morningEnabled;
    _timeController = TextEditingController(text: widget.morningTime);
  }

  @override
  void dispose() {
    _timeController.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged({
      'turnAllOffAtMidnight': _turnAllOffAtMidnight,
      'weekdayMorningOn': {
        'enabled': _morningEnabled,
        'time': _timeController.text,
        'deviceIds': <String>[],
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
              'Automatismos',
              style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              title: const Text('Desligar todas as tomadas às 00:00'),
              value: _turnAllOffAtMidnight,
              onChanged: (v) {
                setState(() => _turnAllOffAtMidnight = v);
                _emit();
              },
            ),
            SwitchListTile(
              title: const Text('Ligar tomadas de manhã (dias úteis)'),
              value: _morningEnabled,
              onChanged: (v) {
                setState(() => _morningEnabled = v);
                _emit();
              },
            ),
            if (_morningEnabled)
              TextField(
                controller: _timeController,
                decoration: const InputDecoration(labelText: 'Hora (HH:MM)'),
                onChanged: (_) => _emit(),
              ),
          ],
        ),
      ),
    );
  }
}

// ===================== ABOUT SECTION =====================

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Sobre o SIGED',
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
