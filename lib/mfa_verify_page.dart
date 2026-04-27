import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Ecrã de verificação MFA (aparece após login quando MFA está ativo)
// ─────────────────────────────────────────────────────────────────────────────

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
    const primary = kPrimary;

    return Scaffold(
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
                    color: primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_outlined, size: 40, color: primary),
                ),
              ),
              const SizedBox(height: 24),

              const Center(
                child: Text(
                  'Verificação em dois passos',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Introduz o código de 6 dígitos da tua app autenticadora',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
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
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Verificar', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),

              // Cancelar / sair
              Center(
                child: TextButton(
                  onPressed: widget.onCancel,
                  child: Text(
                    'Cancelar e terminar sessão',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Ajuda
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Abre o Google Authenticator ou Microsoft Authenticator '
                        'e usa o código de 6 dígitos para AVERIS. '
                        'O código muda a cada 30 segundos.',
                        style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
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
// Widget: 6 caixas de dígito (estilo app bancária)
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
    // Limpar caixas quando o parent reseta o valor
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
    const primary = kPrimary;
    final code = widget.value;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Caixas visuais
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final isFilled = i < code.length;
                final isActive = i == code.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 46,
                  height: 58,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: isFilled
                        ? primary.withValues(alpha: 0.07)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.errorText != null
                          ? Colors.red
                          : isActive
                              ? primary
                              : isFilled
                                  ? primary.withValues(alpha: 0.5)
                                  : Colors.grey.shade300,
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
                            color: primary,
                          ),
                        )
                      : null,
                );
              }),
            ),

            // Campo de texto invisível por cima — captura o teclado
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
