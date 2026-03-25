import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_page.dart';
import 'services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // AuthGate ouve authStateChanges e trata da navegação — aqui só fazemos login.
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );
      // AuthGate detecta a mudança de estado e navega automaticamente.
    } on FirebaseAuthException catch (e) {
      String message = 'Ocorreu um erro. Tente novamente.';
      switch (e.code) {
        case 'user-not-found':
          message = 'Não existe utilizador com esse email.';
          break;
        case 'wrong-password':
        case 'invalid-credential':
          message = 'Email ou password incorretos.';
          break;
        case 'invalid-email':
          message = 'Email inválido.';
          break;
        case 'user-disabled':
          message = 'Esta conta foi desativada.';
          break;
        case 'network-request-failed':
          message = 'Sem ligação à internet.';
          break;
      }
      if (mounted) setState(() => _errorText = message);
    } catch (_) {
      if (mounted) setState(() => _errorText = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _errorText = null;
    });

    try {
      await AuthService.signInWithGoogle();
      // AuthGate detecta a mudança de estado e navega automaticamente.
    } catch (e) {
      if (e.toString().contains('cancelled')) return;
      if (mounted) setState(() => _errorText = 'Não foi possível entrar com o Google.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      setState(() => _errorText = 'Introduza o seu email primeiro.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _errorText = 'Introduza um email válido.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      _passwordCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email de redefinição enviado! Verifique a sua caixa de entrada.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Erro ao enviar email.';
      switch (e.code) {
        case 'invalid-email':
          message = 'Email inválido.';
          break;
        case 'user-not-found':
          message = 'Nenhum utilizador encontrado com este email.';
          break;
        default:
          message = 'Erro: ${e.message}';
      }
      if (mounted) setState(() => _errorText = message);
    } catch (_) {
      if (mounted) setState(() => _errorText = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const primaryColor = Color(0xFF38A3F1);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    SizedBox(
                      height: 120,
                      child: FittedBox(
                        child: Text(
                          'AVERIS',
                          style: theme.textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gestão de Energia Doméstica',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Email', style: theme.textTheme.bodyMedium),
                    UnderlineInput(
                      controller: _emailCtrl,
                      hintText: 'Introduza o seu email',
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'O email é obrigatório.';
                        }
                        if (!value.contains('@')) {
                          return 'Introduza um email válido.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('Password', style: theme.textTheme.bodyMedium),
                    UnderlineInput(
                      controller: _passwordCtrl,
                      hintText: 'Introduza a sua password',
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'A password é obrigatória.';
                        }
                        if (value.length < 6) {
                          return 'A password deve ter pelo menos 6 caracteres.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading ? null : _resetPassword,
                  child: const Text('Esqueceu a sua password?', style: TextStyle(fontSize: 13)),
                ),
              ),

              if (_errorText != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorText!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Botão principal: entrar com email
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: (_isLoading || _isGoogleLoading) ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Entrar', style: TextStyle(color: Colors.white)),
                ),
              ),

              const SizedBox(height: 16),

              // Divisor
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('ou', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 16),

              // Botão Google
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: (_isLoading || _isGoogleLoading) ? null : _loginWithGoogle,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: _isGoogleLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            GoogleIcon(),
                            SizedBox(width: 10),
                            Text('Continuar com Google'),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Sem conta?'),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterPage()),
                    ),
                    child: const Text('Criar conta'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GoogleIcon — "G" do Google desenhado com Flutter puro, sem assets
// ─────────────────────────────────────────────────────────────────────────────

class GoogleIcon extends StatelessWidget {
  const GoogleIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDDDDDD)),
        color: Colors.white,
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

// ─────────────────────────────────────────────────────────────────────────────
// UnderlineInput
// ─────────────────────────────────────────────────────────────────────────────

class UnderlineInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const UnderlineInput({
    super.key,
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        border: const UnderlineInputBorder(),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black87, width: 1.2),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
      ),
    );
  }
}
