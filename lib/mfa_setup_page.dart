import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Ecrã de configuração MFA (ativar/desativar, acessível a partir das Definições)
// ─────────────────────────────────────────────────────────────────────────────

const _kBg      = Color(0xFF0a1628);
const _kSurface = Color(0xFF0f1e3d);
const _kAccent  = Color(0xFF38d9a9);
const _kField   = Color(0xFF1a2e52);
const _kBorder  = Color(0xFF2a4070);

class MfaSetupPage extends StatefulWidget {
  const MfaSetupPage({super.key});

  @override
  State<MfaSetupPage> createState() => _MfaSetupPageState();
}

class _MfaSetupPageState extends State<MfaSetupPage> {
  bool _loading = true;
  bool _mfaEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final enabled = await AuthService.isMfaEnabled(uid);
    if (mounted) {
      setState(() {
        _mfaEnabled = enabled;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Verificação em dois passos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : _mfaEnabled
              ? _DisableMfaView(onDisabled: () => setState(() => _mfaEnabled = false))
              : _EnableMfaView(onEnabled: () => setState(() => _mfaEnabled = true)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vista: Ativar MFA (QR code + confirmação)
// ─────────────────────────────────────────────────────────────────────────────

class _EnableMfaView extends StatefulWidget {
  final VoidCallback onEnabled;
  const _EnableMfaView({required this.onEnabled});

  @override
  State<_EnableMfaView> createState() => _EnableMfaViewState();
}

class _EnableMfaViewState extends State<_EnableMfaView> {
  String? _secret;
  String? _qrUri;
  String _code = '';
  bool _loading = true;
  bool _confirming = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _generateSecret();
  }

  Future<void> _generateSecret() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final secret = await AuthService.generateMfaSecret(user.uid);
    final uri = AuthService.buildOtpAuthUri(secret, user.email ?? user.uid);
    if (mounted) {
      setState(() {
        _secret = secret;
        _qrUri = uri;
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    if (_code.length != 6) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _confirming = true;
      _errorText = null;
    });

    try {
      final ok = await AuthService.confirmMfaSetup(uid, _code);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verificação em dois passos ativada!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onEnabled();
      } else {
        setState(() {
          _errorText = 'Código inválido. Verifica a tua app autenticadora.';
          _code = '';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _errorText = 'Erro ao confirmar. Tenta novamente.');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Passo 1
          _StepHeader(step: 1, title: 'Instala uma app autenticadora'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: const Text(
              'Instala o Google Authenticator ou Microsoft Authenticator '
              'no teu telemóvel. Estas apps são gratuitas.',
              style: TextStyle(fontSize: 14, color: Color(0xB3FFFFFF)),
            ),
          ),
          const SizedBox(height: 28),

          // Passo 2
          _StepHeader(step: 2, title: 'Escaneia o QR code'),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: QrImageView(
                data: _qrUri!,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Código manual
          Center(
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _secret!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Código copiado!')),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _kField,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _secret!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                        color: _kAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy, size: 16, color: _kAccent),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'Ou insere o código manualmente na app (toca para copiar)',
              style: TextStyle(fontSize: 12, color: Color(0x80FFFFFF)),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 28),

          // Passo 3
          _StepHeader(step: 3, title: 'Confirma com o primeiro código'),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Introduz o código de 6 dígitos que aparece na app',
              style: TextStyle(color: Color(0x80FFFFFF), fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),

          _SetupCodeInput(
            value: _code,
            errorText: _errorText,
            onChanged: (v) {
              setState(() {
                _code = v;
                _errorText = null;
              });
              if (v.length == 6) _confirm();
            },
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: (_code.length == 6 && !_confirming) ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: const Color(0xFF04342c),
                disabledBackgroundColor: _kAccent.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _confirming
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF04342c),
                      ),
                    )
                  : const Text(
                      'Ativar',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vista: Desativar MFA
// ─────────────────────────────────────────────────────────────────────────────

class _DisableMfaView extends StatefulWidget {
  final VoidCallback onDisabled;
  const _DisableMfaView({required this.onDisabled});

  @override
  State<_DisableMfaView> createState() => _DisableMfaViewState();
}

class _DisableMfaViewState extends State<_DisableMfaView> {
  String _code = '';
  bool _disabling = false;
  String? _errorText;

  Future<void> _disable() async {
    if (_code.length != 6) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _disabling = true;
      _errorText = null;
    });

    try {
      final ok = await AuthService.disableMfa(uid, _code);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verificação em dois passos desativada.'),
          ),
        );
        widget.onDisabled();
      } else {
        setState(() {
          _errorText = 'Código inválido.';
          _code = '';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _errorText = 'Erro ao desativar. Tenta novamente.');
    } finally {
      if (mounted) setState(() => _disabling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Estado ativo
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user, color: Colors.green.shade400),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verificação em dois passos ativa',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'A tua conta está protegida com TOTP.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0x80FFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'Para desativar, confirma com o código atual da tua app autenticadora:',
            style: TextStyle(fontSize: 14, color: Color(0xB3FFFFFF)),
          ),
          const SizedBox(height: 20),

          _SetupCodeInput(
            value: _code,
            errorText: _errorText,
            onChanged: (v) {
              setState(() {
                _code = v;
                _errorText = null;
              });
              if (v.length == 6) _disable();
            },
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: (_code.length == 6 && !_disabling) ? _disable : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.red.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _disabling
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Desativar',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets auxiliares
// ─────────────────────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  final int step;
  final String title;

  const _StepHeader({required this.step, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: _kAccent,
          child: Text(
            '$step',
            style: const TextStyle(
              color: Color(0xFF04342c),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// Reutiliza o mesmo widget de 6 caixas
// (pode ser extraído para ficheiro comum se necessário)
class _SetupCodeInput extends StatefulWidget {
  final String value;
  final String? errorText;
  final void Function(String) onChanged;

  const _SetupCodeInput({
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  @override
  State<_SetupCodeInput> createState() => _SetupCodeInputState();
}

class _SetupCodeInputState extends State<_SetupCodeInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void didUpdateWidget(_SetupCodeInput old) {
    super.didUpdateWidget(old);
    if (widget.value.isEmpty && _controller.text.isNotEmpty) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.value;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final isFilled = i < code.length;
                final isActive = i == code.length;
                final hasError = widget.errorText != null;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 46,
                  height: 58,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: isFilled ? _kAccent.withValues(alpha: 0.12) : _kField,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasError
                          ? Colors.red.shade400
                          : isActive
                              ? _kAccent
                              : isFilled
                                  ? _kAccent.withValues(alpha: 0.5)
                                  : _kBorder,
                      width: isActive ? 2.0 : 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: isFilled
                      ? Text(
                          code[i],
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _kAccent,
                          ),
                        )
                      : null,
                );
              }),
            ),
            Opacity(
              opacity: 0.0,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: ''),
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            widget.errorText!,
            style: const TextStyle(color: Colors.red, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
