/*

import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> seedDatabase() async {
  // Inicializa Firebase
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;

  // USER 1: Martim (tu)
  await firestore.collection('users').doc('martim_test').set({
    'name': 'Martim Estrela',
    'email': 'martim.estrela@gmail.com',
    'createdAt': FieldValue.serverTimestamp(),
    'settings': {'theme': 'light', 'notifications': true, 'autoRefresh': 30},
  });

  // DEVICE 1: Tomada Sala
  await firestore
      .collection('users')
      .doc('martim_test')
      .collection('devices')
      .doc('sala_tomada1')
      .set({
        'name': 'Tomada Sala',
        'type': 'shelly-plug',
        'location': 'Sala de Estar',
        'ip': '192.168.1.45',
        'status': 'online',
        'createdAt': FieldValue.serverTimestamp(),
      });

  // SENSOR 1: Power do Tomada Sala
  await firestore
      .collection('users')
      .doc('martim_test')
      .collection('devices')
      .doc('sala_tomada1')
      .collection('sensors')
      .doc('power_sensor')
      .set({
        'name': 'Consumo Elétrico',
        'type': 'power',
        'unit': 'W',
        'createdAt': FieldValue.serverTimestamp(),
      });

  // 5 LEITURAS RECENTES (últimas 5h)
  final now = DateTime.now();
  for (int i = 0; i < 5; i++) {
    await firestore
        .collection('users')
        .doc('martim_test')
        .collection('devices')
        .doc('sala_tomada1')
        .collection('sensors')
        .doc('power_sensor')
        .collection('readings')
        .add({
          'timestamp': Timestamp.fromDate(now.subtract(Duration(hours: i))),
          'value': 45.2 + (i * 12.5), // 45W → 122W
          'voltage': 230.4,
          'current': 0.21,
        });
  }

  // DEVICE 2: Tomada Cozinha
  await firestore
      .collection('users')
      .doc('martim_test')
      .collection('devices')
      .doc('cozinha_tomada1')
      .set({
        'name': 'Tomada Cozinha',
        'type': 'shelly-plug',
        'location': 'Cozinha',
        'ip': '192.168.1.46',
        'status': 'online',
        'createdAt': FieldValue.serverTimestamp(),
      });

  print('✅ SEED COMPLETO!');
  print('👤 User: martim_test');
  print('🔌 Devices: sala_tomada1, cozinha_tomada1');
  print('📊 Leituras criadas: 5 power readings');
}


*/
