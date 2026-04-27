import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens centralizados — toda a app deve usar estas constantes
// ─────────────────────────────────────────────────────────────────────────────

// Cor primária da marca. Igual ao seedColor em main.dart.
const kPrimary = Color(0xFF38A3F1);

class AppRadius {
  AppRadius._();
  static const double input = 8.0;
  static const double card = 12.0;
  static const double chip = 20.0;
  static const double button = 12.0;
}

class AppShadows {
  AppShadows._();
  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
}

class AppDecorations {
  AppDecorations._();

  static BoxDecoration card({Color? color}) => BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      );

  static BoxDecoration errorBanner() => BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: Colors.red.shade200),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Campo de texto partilhado — usado no login, registo e MFA
// ─────────────────────────────────────────────────────────────────────────────

class AppTextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const AppTextInput({
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
      decoration: InputDecoration(hintText: hintText, isDense: true),
    );
  }
}
