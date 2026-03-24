import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/shelly_polling_service.dart';
import 'services/user_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Inicializa notificações locais e serviço de background
  /*await NotificationService.init();
  await BackgroundService.init();*/

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
// AuthGate — gere o ciclo de vida dos serviços consoante o estado de auth
// ─────────────────────────────────────────────────────────────────────────────

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();

    // Escuta mudanças de autenticação e gere os serviços automaticamente.
    // Isto cobre dois casos:
    //   1. App aberta de novo com sessão já ativa → arranca serviços
    //   2. Login / Logout feito na app → arranca ou para serviços
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        await UserService.ensureUserExists(user);
        /*NotificationService.startListeners(user.uid);
        await BackgroundService.start();*/
        await ShellyPollingService.start(user.uid);
      } else {
        /*NotificationService.stopListeners();
        await BackgroundService.stop();*/
        ShellyPollingService.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const HomePage();
        }

        return const LoginPage();
      },
    );
  }
}
