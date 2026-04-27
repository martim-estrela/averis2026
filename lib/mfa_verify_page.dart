import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Ecrã de verificação MFA (aparece após login quando MFA está ativo)
// ─────────────────────────────────────────────────────────────────────────────

const _kBg      = Color(0xFF0a1628);
const _kSurface = Color(0xFF0f1e3d);
const _kAccent  = Color(0xFF38d9a9);
const _kField   = Color(0xFF1a2e52);
const _kBorder  = Color(0xFF2a4070);

class MfaVerifyPage extends StatefulWidget {
  final String uid;
  final Future<void> Function() onVerified;
  final VoidCallback onCancel;

  const MfaVerifyPage({
    super.key,
    required this.uid,
    required this.onVerified,
    required this.onCancel,
  });

  @override
  State<MfaVerifyPage> createState() => _MfaVerifyPageState();
}

class _MfaVerifyPageState extends State<MfaVerifyPage> {
  String _code = '';
  bool _isVerifying = false;
  String? _errorText;

  Future<void> _verify() async {
    if (_code.length != 6) return;

    setState(() {
      _isVerifying = true;
      _errorText = null;
    });

    try {
      final ok = await AuthService.verifyMfaCode(widget.uid, _code);
      if (!mounted) return;

      if (ok) {
        await widget.onVerified();
      } else {
        setState(() {
          _errorText = 'Código inválido. Verifica a tua app autenticadora.';
          _code = '';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _errorText = 'Erro ao verificar. Tenta novamente.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // Ícone
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _kSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: _kAccent.withValues(alpha: 0.4), width: 2),
                  ),
                  child: const Icon(Icons.shield_outlined, size: 40, color: _kAccent),
                ),
              ),
              const SizedBox(height: 24),

              const Center(
                child: Text(
                  'Verificação em dois passos',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Introduz o código de 6 dígitos da tua app autenticadora',
                  style: TextStyle(color: Color(0x80FFFFFF), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 48),

              // Input de 6 dígitos
              _SixDigitInput(
                value: _code,
                errorText: _errorText,
                onChanged: (v) {
                  setState(() {
                    _code = v;
                    _errorText = null;
                  });
                  if (v.length == 6) _verify();
                },
              ),
              const SizedBox(height: 40),

              // Botão verificar
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: (_code.length == 6 && !_isVerifying) ? _verify : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: const Color(0xFF04342c),
                    disabledBackgroundColor: _kAccent.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF04342c),
                          ),
                        )
                      : const Text(
                          'Verificar',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Cancelar
              Center(
                child: TextButton(
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0x66FFFFFF),
                  ),
                  child: const Text(
                    'Cancelar e terminar sessão',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Ajuda
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: _kAccent),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Abre o Google Authenticator ou Microsoft Authenticator '
                        'e usa o código de 6 dígitos para AVERIS. '
                        'O código muda a cada 30 segundos.',
                        style: TextStyle(fontSize: 13, color: Color(0xB3FFFFFF)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: 6 caixas de dígito (estilo app bancária) — tema escuro
// ─────────────────────────────────────────────────────────────────────────────

class _SixDigitInput extends StatefulWidget {
  final String value;
  final String? errorText;
  final void Function(String) onChanged;

  const _SixDigitInput({
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  @override
  State<_SixDigitInput> createState() => _SixDigitInputState();
}

class _SixDigitInputState extends State<_SixDigitInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void didUpdateWidget(_SixDigitInput old) {
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

            // Campo invisível que captura o teclado
            Opacity(
              opacity: 0.0,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
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
