import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart' show GoogleIcon;
import 'services/auth_service.dart';
import 'services/user_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      // 1. Cria a conta no Firebase Auth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );

      // 2. Atualiza o displayName no Auth
      await cred.user?.updateDisplayName(_nameCtrl.text.trim());

      // 3. ✅ Cria o documento no Firestore com a estrutura completa
      //    Passa o displayName explicitamente porque updateDisplayName
      //    pode ainda não estar refletido em cred.user no mesmo tick
      await UserService.initUser(
        cred.user!,
        displayName: _nameCtrl.text.trim(),
      );

      // 4. Envia email de verificação
      await cred.user?.sendEmailVerification();

      if (!mounted) return;
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      String message = 'Ocorreu um erro ao criar a conta.';
      switch (e.code) {
        case 'email-already-in-use':
          message = 'Já existe uma conta com este email.';
          break;
        case 'weak-password':
          message = 'A password é demasiado fraca (mínimo 6 caracteres).';
          break;
        case 'invalid-email':
          message = 'Email inválido.';
          break;
        case 'network-request-failed':
          message = 'Sem ligação à internet.';
          break;
      }
      setState(() => _errorText = message);
    } catch (_) {
      setState(() => _errorText = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _errorText = null;
    });
    try {
      await AuthService.signInWithGoogle();
      // AuthGate trata da navegação automaticamente.
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (e.toString().contains('cancelled')) return;
      if (mounted) setState(() => _errorText = 'Não foi possível entrar com o Google.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
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
              const SizedBox(height: 32),

              Text(
                'Registo',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

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

                    Text('Nome', style: theme.textTheme.bodyMedium),
                    UnderlineInput(
                      controller: _nameCtrl,
                      hintText: 'Introduza o seu nome',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'O nome é obrigatório.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    Text('Password', style: theme.textTheme.bodyMedium),
                    UnderlineInput(
                      controller: _passwordCtrl,
                      hintText: 'Crie uma password',
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

              const SizedBox(height: 24),

              if (_errorText != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
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
                const SizedBox(height: 8),
              ],

              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
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
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Criar Conta',
                          style: TextStyle(color: Colors.white),
                        ),
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
                  onPressed: (_isLoading || _isGoogleLoading) ? null : _registerWithGoogle,
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

              const SizedBox(height: 24),

              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Já tens uma conta? Iniciar sessão'),
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
// UnderlineInput — campo de texto com borda inferior
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
        hintText: hintText,
        isDense: true,
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
