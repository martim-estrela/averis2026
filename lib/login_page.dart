// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_page.dart';
import 'services/auth_service.dart';

// ── Constants ──────────────────────────────────────────────────────────────────

const _kBg = Color(0xFF0a1628);
const _kCard = Color(0xFF0f1e3d);
const _kAccent = Color(0xFF38d9a9);
const _kField = Color(0xFF1a2e52);
const _kFieldBorder = Color(0xFF2a4070);

// ── Firebase error mapping ─────────────────────────────────────────────────────

String _mapError(String code) => switch (code) {
  'user-not-found' => 'Não existe conta com este email.',
  'wrong-password' => 'Email ou password incorretos.',
  'invalid-credential' => 'Email ou password incorretos.',
  'invalid-email' => 'Endereço de email inválido.',
  'user-disabled' => 'Esta conta foi desativada.',
  'network-request-failed' => 'Sem ligação à internet.',
  _ => 'Ocorreu um erro. Tente novamente.',
};

// ══════════════════════════════════════════════════════════════════════════════
// LoginPage
// ══════════════════════════════════════════════════════════════════════════════

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // AuthGate listens to authStateChanges and handles navigation + MFA.
  // Login page only triggers sign-in; AuthGate does the rest.
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _mapError(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = 'Ocorreu um erro. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await AuthService.signInWithGoogle();
    } catch (e) {
      if (e.toString().contains('cancelled')) return;
      if (mounted) {
        setState(() => _error = 'Não foi possível entrar com o Google.');
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Introduz o teu email primeiro.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Introduz um email válido.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PasswordResetConfirmPage(email: email),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _mapError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _fieldDeco({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0x66FFFFFF), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0x66FFFFFF), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _kField,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kFieldBorder, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kFieldBorder, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE24B4A), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE24B4A), width: 1.5),
      ),
      errorStyle: const TextStyle(color: Color(0xFFE24B4A), fontSize: 11),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final busy = _loading || _googleLoading;

    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          // ── Logo zone ────────────────────────────────────────────────────
          SizedBox(
            height: screenH * 0.30,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: Column(
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
                ),
              ),
            ),
          ),

          // ── Form card ────────────────────────────────────────────────────
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Bem-vindo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Inicia sessão para continuar',
                      style: TextStyle(color: Color(0x73FFFFFF), fontSize: 12),
                    ),
                    const SizedBox(height: 24),

                    // Form
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            decoration: _fieldDeco(
                              hint: 'O teu email',
                              icon: Icons.mail_outline,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'O email é obrigatório.';
                              }
                              if (!v.contains('@')) return 'Email inválido.';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscurePass,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            decoration: _fieldDeco(
                              hint: 'A tua password',
                              icon: Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(
                                  _obscurePass
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: const Color(0x66FFFFFF),
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePass = !_obscurePass,
                                ),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'A password é obrigatória.'
                                : null,
                          ),
                        ],
                      ),
                    ),

                    // Forgot password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy ? null : _resetPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: _kAccent,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Esqueceu a password?',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),

                    // Error box
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x1FE24B4A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x4DE24B4A)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFE24B4A),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFE24B4A),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Login button
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: busy ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: const Color(0xFF04342c),
                          disabledBackgroundColor: _kAccent.withValues(
                            alpha: 0.45,
                          ),
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
                                'Entrar',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Divider
                    Row(
                      children: [
                        const Expanded(
                          child: Divider(color: Color(0xFF1e3a6e)),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'ou',
                            style: TextStyle(
                              color: Color(0x66FFFFFF),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Divider(color: Color(0xFF1e3a6e)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Google button
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: busy ? null : _loginWithGoogle,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: _kField,
                          side: const BorderSide(
                            color: _kFieldBorder,
                            width: 0.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: _googleLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _GoogleIcon(),
                                  SizedBox(width: 10),
                                  Text(
                                    'Continuar com Google',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Register link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Sem conta? ',
                          style: TextStyle(
                            color: Color(0x80FFFFFF),
                            fontSize: 13,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RegisterPage(),
                            ),
                          ),
                          child: const Text(
                            'Criar conta',
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PasswordResetConfirmPage
// ══════════════════════════════════════════════════════════════════════════════

class _PasswordResetConfirmPage extends StatelessWidget {
  final String email;
  const _PasswordResetConfirmPage({required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.mark_email_read_outlined,
                    color: Colors.green,
                    size: 42,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Email enviado!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Verifica a tua caixa de entrada em\n$email',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0x80FFFFFF),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kAccent,
                  side: const BorderSide(color: _kAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Voltar ao login',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _AverisLogoPainter — bars + lightning bolt (CustomPaint, no assets)
// ══════════════════════════════════════════════════════════════════════════════

class _AverisLogoPainter extends CustomPainter {
  const _AverisLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 4 vertical bars (energy chart)
    final barPaint = Paint()
      ..color = _kAccent
      ..style = PaintingStyle.fill;

    const heightRatios = [0.38, 0.62, 0.82, 0.50];
    final barW = w * 0.13;
    final gap = w * 0.065;
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

    // Lightning bolt (white, upper-center)
    final boltPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final cx = w * 0.50;
    final s = w * 0.10;
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

// ══════════════════════════════════════════════════════════════════════════════
// _GoogleIcon — "G" drawn in Flutter, no assets
// ══════════════════════════════════════════════════════════════════════════════

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }
}
