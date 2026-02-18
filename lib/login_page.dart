import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_page.dart';

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
  String? _errorText;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

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

      // TODO: Navegar para o dashboard principal
      // Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      String message = 'Ocorreu um erro. Tente novamente.';
      if (e.code == 'user-not-found') {
        message = 'Não existe utilizador com esse email.';
      } else if (e.code == 'wrong-password') {
        message = 'Password incorreta.';
      } else if (e.code == 'invalid-email') {
        message = 'Email inválido.';
      }
      setState(() => _errorText = message);
    } catch (_) {
      setState(() => _errorText = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();

    // Validação rápida
    if (email.isEmpty) {
      setState(() => _errorText = 'Por favor, introduza o seu email primeiro.');
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
      // ENVIA O EMAIL DE REDEFINIÇÃO
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      // MOSTRA CONFIRMAÇÃO
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Email de redefinição enviado! Verifique a sua caixa de entrada.',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );

      // Limpa o campo de password
      _passwordCtrl.clear();
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

      if (mounted) {
        setState(() => _errorText = message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = 'Erro inesperado. Tente novamente.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = const Color(0xFF38A3F1);

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
                          'SIGED',
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
                  onPressed: _isLoading
                      ? null
                      : _resetPassword, // ← FUNCIONA AQUI
                  child: const Text(
                    'Esqueceu a sua password?',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),

              if (_errorText != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],

              const SizedBox(height: 16),

              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
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
                      : const Text('Entrar'),
                ),
              ),

              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Sem conta?'),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RegisterPage()),
                      );
                    },
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
      ),
    );
  }
}
