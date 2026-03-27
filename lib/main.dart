import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'mfa_verify_page.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/shelly_polling_service.dart';
import 'services/user_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AVERIS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF38A3F1)),
      ),
      home: const AuthGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthGate — máquina de estados de autenticação + MFA
// ─────────────────────────────────────────────────────────────────────────────

enum _AuthState { loading, unauthenticated, mfaPending, authenticated }

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  _AuthState _state = _AuthState.loading;
  User? _user;
  String? _mfaVerifiedUid; // uid que já passou MFA nesta sessão

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
    _setupFcmTokenRefresh();
  }

  // Atualiza o token FCM no Firestore sempre que o FCM o renovar
  void _setupFcmTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'fcmToken': token});
      }
    });
  }

  Future<void> _onAuthChanged(User? user) async {
    if (!mounted) return;

    // Logout
    if (user == null) {
      ShellyPollingService.stop();
      setState(() {
        _state = _AuthState.unauthenticated;
        _user = null;
        _mfaVerifiedUid = null;
      });
      return;
    }

    _user = user;

    // Já passou MFA nesta sessão — ir direto para a app
    if (_mfaVerifiedUid == user.uid) {
      setState(() => _state = _AuthState.authenticated);
      return;
    }

    // Verificar se MFA está ativo
    final mfaEnabled = await AuthService.isMfaEnabled(user.uid);
    if (!mounted) return;

    if (mfaEnabled) {
      setState(() => _state = _AuthState.mfaPending);
    } else {
      await _completeLogin(user);
    }
  }

  /// Chamado depois de MFA verificado (ou quando MFA não está ativo).
  Future<void> _completeLogin(User user) async {
    _mfaVerifiedUid = user.uid;
    await UserService.ensureUserExists(user);
    await ShellyPollingService.start(user.uid);

    // Guarda o token FCM no Firestore para o Cloudflare Worker poder enviar notificações
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'fcmToken': token});
    }

    if (mounted) setState(() => _state = _AuthState.authenticated);
  }

  Future<void> _onMfaVerified() async {
    if (_user != null) await _completeLogin(_user!);
  }

  void _onMfaCancel() {
    FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _AuthState.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case _AuthState.unauthenticated:
        return const LoginPage();
      case _AuthState.mfaPending:
        return MfaVerifyPage(
          uid: _user!.uid,
          onVerified: _onMfaVerified,
          onCancel: _onMfaCancel,
        );
      case _AuthState.authenticated:
        return const HomePage();
    }
  }
}
