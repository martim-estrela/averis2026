import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:otp/otp.dart';

class AuthService {
  AuthService._();

  static final _db = FirebaseFirestore.instance;

  // ── Google Sign-In ─────────────────────────────────────────────────────────

  /// Lança o flow de Google Sign-In e autentica no Firebase.
  /// Lança Exception('cancelled') se o utilizador fechar o popup.
  static Future<UserCredential> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw Exception('cancelled');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  // ── MFA ────────────────────────────────────────────────────────────────────

  /// Verifica se o utilizador tem MFA ativo.
  static Future<bool> isMfaEnabled(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data()?['mfaEnabled'] == true;
  }

  /// Gera um novo segredo TOTP, guarda-o no Firestore (não confirmado ainda)
  /// e devolve o segredo em base32 para gerar o QR code.
  static Future<String> generateMfaSecret(String uid) async {
    final secret = _generateBase32Secret();
    await _db.collection('users').doc(uid).update({
      'mfaSecret': secret,
      'mfaEnabled': false,
    });
    return secret;
  }

  /// Confirma o setup de MFA verificando o código introduzido.
  /// Se correto, ativa o MFA no Firestore.
  static Future<bool> confirmMfaSetup(String uid, String code) async {
    final snap = await _db.collection('users').doc(uid).get();
    final secret = snap.data()?['mfaSecret'] as String?;
    if (secret == null) return false;
    if (!_verifyCode(secret, code)) return false;

    await _db.collection('users').doc(uid).update({
      'mfaEnabled': true,
      'mfaEnabledAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Verifica o código TOTP durante o login.
  static Future<bool> verifyMfaCode(String uid, String code) async {
    final snap = await _db.collection('users').doc(uid).get();
    final secret = snap.data()?['mfaSecret'] as String?;
    if (secret == null) return false;
    return _verifyCode(secret, code);
  }

  /// Desativa o MFA após verificar o código atual.
  static Future<bool> disableMfa(String uid, String code) async {
    final snap = await _db.collection('users').doc(uid).get();
    final secret = snap.data()?['mfaSecret'] as String?;
    if (secret == null) return false;
    if (!_verifyCode(secret, code)) return false;

    await _db.collection('users').doc(uid).update({
      'mfaEnabled': false,
      'mfaSecret': FieldValue.delete(),
    });
    return true;
  }

  /// Constrói o URI otpauth:// para gerar o QR code.
  static String buildOtpAuthUri(String secret, String email) {
    final label = Uri.encodeComponent('AVERIS:$email');
    return 'otpauth://totp/$label'
        '?secret=$secret'
        '&issuer=AVERIS'
        '&algorithm=SHA1'
        '&digits=6'
        '&period=30';
  }

  // ── Helpers privados ──────────────────────────────────────────────────────

  /// Verifica o código TOTP com tolerância de ±1 janela de 30s (para desfasamentos de relógio).
  static bool _verifyCode(String secret, String code) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (int delta = -1; delta <= 1; delta++) {
      final t = now + delta * 30000;
      final expected = OTP.generateTOTPCodeString(
        secret,
        t,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      if (expected == code) return true;
    }
    return false;
  }

  /// Gera um segredo aleatório de 32 caracteres no alfabeto BASE32.
  static String _generateBase32Secret() {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final rng = Random.secure();
    return List.generate(32, (_) => alphabet[rng.nextInt(alphabet.length)])
        .join();
  }
}
