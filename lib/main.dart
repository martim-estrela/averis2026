import 'package:flutter/material.dart';
import 'seed.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SEED A BASE DE DADOS (só uma vez!)
  print('🌱 Iniciando seed da base de dados...');
  await seedDatabase();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Averis - Seed Completo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SeedComplete(),
    );
  }
}

class SeedComplete extends StatelessWidget {
  const SeedComplete({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Averis')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 100, color: Colors.green),
            SizedBox(height: 20),
            Text(
              'SEED COMPLETO! ✅',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              'Agora vê no Firebase Console:',
              style: TextStyle(fontSize: 16),
            ),
            Text('users/martim_test/devices/...'),
            SizedBox(height: 40),
            Text(
              'Executa: flutter run',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
