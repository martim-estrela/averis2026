// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart';
import 'services/user_service.dart';

// ── Constants ──────────────────────────────────────────────────────────────────

const _kBg         = Color(0xFF0a1628);
const _kCard       = Color(0xFF0f1e3d);
const _kAccent     = Color(0xFF38d9a9);
const _kField      = Color(0xFF1a2e52);
const _kFieldBorder = Color(0xFF2a4070);
const _kErr        = Color(0xFFE24B4A);

// ── Firebase error mapping ─────────────────────────────────────────────────────

String _mapError(String code) => switch (code) {
  'email-already-in-use'   => 'Já existe uma conta com este email.',
  'weak-password'          => 'A password é demasiado fraca.',
  'invalid-email'          => 'Endereço de email inválido.',
  'network-request-failed' => 'Sem ligação à internet.',
  _                        => 'Ocorreu um erro. Tente novamente.',
};

// ── Password strength ──────────────────────────────────────────────────────────

enum _Strength { none, weak, medium, good, strong }

_Strength _passwordStrength(String p) {
  if (p.length < 6) return _Strength.none;
  final hasLetters = RegExp(r'[a-zA-Z]').hasMatch(p);
  final hasDigits  = RegExp(r'[0-9]').hasMatch(p);
  final hasSymbols = RegExp(r'[^a-zA-Z0-9]').hasMatch(p);
  if (!hasLetters || !hasDigits) return _Strength.weak;
  if (p.length < 8)              return _Strength.medium;
  if (!hasSymbols)               return _Strength.good;
  return _Strength.strong;
}

// ══════════════════════════════════════════════════════════════════════════════
// RegisterPage
// ══════════════════════════════════════════════════════════════════════════════

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _confCtrl  = TextEditingController();

  bool _obscurePass    = true;
  bool _obscureConf    = true;
  bool _loading        = false;
  String? _error;
  _Strength _strength  = _Strength.none;
  bool _confirmMismatch = false;
  bool _done           = false;
  String _doneName     = '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameCtrl.text.trim().length >= 2 &&
      _emailCtrl.text.trim().contains('@') &&
      _strength.index >= _Strength.medium.index &&
      !_confirmMismatch &&
      _confCtrl.text.isNotEmpty;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_canSubmit) return;

    setState(() {
      _loading = true;
      _error   = null;
    });

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email:    _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      final user = cred.user!;
      await user.updateDisplayName(_nameCtrl.text.trim());
      await UserService.initUser(user, displayName: _nameCtrl.text.trim());

      if (!mounted) return;
      final name = _nameCtrl.text.trim();
      setState(() {
        _doneName = name;
        _done     = true;
        _loading  = false;
      });

      // AuthGate will navigate to HomePage via authStateChanges.
      // Explicit push after 2s acts as a fallback.
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomePage()),
          (_) => false,
        );
      });
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _mapError(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = 'Ocorreu um erro. Tente novamente.');
    } finally {
      if (mounted && !_done) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          // ── Logo zone with back button ─────────────────────────────────────
          SizedBox(
            height: screenH * 0.28,
            child: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  const Center(child: _LogoZone()),
                  Positioned(
                    top: 8,
                    left: 16,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Form card ─────────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  28,
                  24,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: _done
                    ? _SuccessContent(name: _doneName)
                    : _buildForm(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Criar conta',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Começa a monitorizar a tua energia',
          style: TextStyle(color: Color(0x73FFFFFF), fontSize: 12),
        ),
        const SizedBox(height: 24),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name
              _DarkInputField(
                label: 'Nome completo',
                hint: 'O teu nome',
                icon: Icons.person_outline,
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'O nome é obrigatório.';
                  if (v.trim().length < 2) return 'Mínimo 2 caracteres.';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Email
              _DarkInputField(
                label: 'Email',
                hint: 'O teu email',
                icon: Icons.mail_outline,
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'O email é obrigatório.';
                  if (!v.trim().contains('@')) return 'Endereço de email inválido.';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Password + strength bar
              _DarkInputField(
                label: 'Password',
                hint: 'Cria uma password',
                icon: Icons.lock_outline,
                controller: _passCtrl,
                obscure: _obscurePass,
                onObscureToggle: () => setState(() => _obscurePass = !_obscurePass),
                onChanged: (v) => setState(() {
                  _strength       = _passwordStrength(v);
                  _confirmMismatch =
                      _confCtrl.text.isNotEmpty && _confCtrl.text != v;
                }),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'A password é obrigatória.';
                  if (_strength.index < _Strength.medium.index) {
                    return 'A password é demasiado fraca.';
                  }
                  return null;
                },
              ),
              _PasswordStrengthBar(strength: _strength),
              const SizedBox(height: 14),

              // Confirm password
              _DarkInputField(
                label: 'Confirmar password',
                hint: 'Repete a password',
                icon: Icons.lock_outline,
                controller: _confCtrl,
                obscure: _obscureConf,
                onObscureToggle: () => setState(() => _obscureConf = !_obscureConf),
                hasError: _confirmMismatch,
                onChanged: (v) => setState(() {
                  _confirmMismatch = v.isNotEmpty && v != _passCtrl.text;
                }),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Confirma a password.';
                  if (v != _passCtrl.text) return 'As passwords não coincidem.';
                  return null;
                },
              ),
              if (_confirmMismatch)
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    'As passwords não coincidem.',
                    style: TextStyle(color: _kErr, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Terms
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(
              color: Color(0x73FFFFFF),
              fontSize: 11,
              height: 1.5,
            ),
            children: [
              TextSpan(text: 'Ao criar conta aceitas os '),
              TextSpan(
                text: 'Termos de Utilização',
                style: TextStyle(color: _kAccent),
              ),
              TextSpan(text: ' e a '),
              TextSpan(
                text: 'Política de Privacidade',
                style: TextStyle(color: _kAccent),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Error box
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x1FE24B4A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x4DE24B4A)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: _kErr,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: _kErr, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Submit button
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: (_loading || !_canSubmit) ? null : _register,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: const Color(0xFF04342c),
              disabledBackgroundColor: _kAccent.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
              padding: EdgeInsets.zero,
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF04342c),
                    ),
                  )
                : const Text(
                    'Criar conta',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 24),

        // Login link
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Já tens conta? ',
              style: TextStyle(color: Color(0x80FFFFFF), fontSize: 13),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Text(
                'Iniciar sessão',
                style: TextStyle(
                  color: _kAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SuccessContent
// ══════════════════════════════════════════════════════════════════════════════

class _SuccessContent extends StatelessWidget {
  final String name;
  const _SuccessContent({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.green,
              size: 42,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Conta criada!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bem-vindo ao AVERIS, $name.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0x80FFFFFF),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
            ),
            child: const Text(
              '🌱 Aprendiz · Nível 1',
              style: TextStyle(
                color: _kAccent,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _DarkInputField — reutilizável, estilo dark idêntico ao login
// ══════════════════════════════════════════════════════════════════════════════

class _DarkInputField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool obscure;
  final VoidCallback? onObscureToggle;
  final void Function(String)? onChanged;
  final TextInputType? keyboardType;
  final bool hasError;

  const _DarkInputField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.validator,
    this.obscure = false,
    this.onObscureToggle,
    this.onChanged,
    this.keyboardType,
    this.hasError = false,
  });

  InputDecoration _deco() => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0x66FFFFFF), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0x66FFFFFF), size: 20),
        suffixIcon: onObscureToggle != null
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0x66FFFFFF),
                  size: 20,
                ),
                onPressed: onObscureToggle,
              )
            : null,
        filled: true,
        fillColor: _kField,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? _kErr : _kFieldBorder,
            width: hasError ? 1.0 : 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? _kErr : _kFieldBorder,
            width: hasError ? 1.0 : 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? _kErr : _kAccent,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kErr, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kErr, width: 1.5),
        ),
        errorStyle: const TextStyle(color: _kErr, fontSize: 11),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          onChanged: onChanged,
          keyboardType: keyboardType,
          autocorrect: false,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          validator: validator,
          decoration: _deco(),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PasswordStrengthBar
// ══════════════════════════════════════════════════════════════════════════════

class _PasswordStrengthBar extends StatelessWidget {
  final _Strength strength;
  const _PasswordStrengthBar({required this.strength});

  @override
  Widget build(BuildContext context) {
    final segments = switch (strength) {
      _Strength.none   => 0,
      _Strength.weak   => 1,
      _Strength.medium => 2,
      _Strength.good   => 3,
      _Strength.strong => 4,
    };
    final segColor = switch (strength) {
      _Strength.none   => const Color(0xFF2a4070),
      _Strength.weak   => _kErr,
      _Strength.medium => const Color(0xFFEF9F27),
      _Strength.good   => const Color(0xFFFFD43B),
      _Strength.strong => _kAccent,
    };
    final label = switch (strength) {
      _Strength.none   => '',
      _Strength.weak   => 'Fraca — usa letras e números',
      _Strength.medium => 'Média — adiciona mais caracteres',
      _Strength.good   => 'Boa — adiciona um símbolo para ser Forte',
      _Strength.strong => 'Forte',
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (i) {
              final active = i < segments;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: active ? segColor : const Color(0xFF2a4070),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: segColor, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _LogoZone — duplicated from login_page (painter is private there)
// ══════════════════════════════════════════════════════════════════════════════

class _LogoZone extends StatelessWidget {
  const _LogoZone();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF1e3a6e)),
          ),
          child: const CustomPaint(painter: _AverisLogoPainter()),
        ),
        const SizedBox(height: 14),
        const Text(
          'AVERIS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'ENERGIA DOMÉSTICA',
          style: TextStyle(
            color: Color(0x66FFFFFF),
            fontSize: 12,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _AverisLogoPainter — 4 bars + lightning bolt (duplicated, painter is private)
// ══════════════════════════════════════════════════════════════════════════════

class _AverisLogoPainter extends CustomPainter {
  const _AverisLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final barPaint = Paint()
      ..color = _kAccent
      ..style = PaintingStyle.fill;

    const heightRatios = [0.38, 0.62, 0.82, 0.50];
    final barW = w * 0.13;
    final gap  = w * 0.065;
    final totalBarsW = barW * 4 + gap * 3;
    var barX = (w - totalBarsW) / 2;
    final baseY = h * 0.85;

    for (final ratio in heightRatios) {
      final barH = h * 0.50 * ratio;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, baseY - barH, barW, barH),
          const Radius.circular(2.5),
        ),
        barPaint,
      );
      barX += barW + gap;
    }

    final boltPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final cx = w * 0.50;
    final s  = w * 0.10;
    final ty = h * 0.09;

    final bolt = Path()
      ..moveTo(cx + s, ty)
      ..lineTo(cx - s * 0.15, ty + s * 1.6)
      ..lineTo(cx + s * 0.35, ty + s * 1.6)
      ..lineTo(cx - s, ty + s * 3.2)
      ..lineTo(cx + s * 0.15, ty + s * 1.3)
      ..lineTo(cx - s * 0.35, ty + s * 1.3)
      ..close();
    canvas.drawPath(bolt, boltPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
