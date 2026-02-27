import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  static Future<void> ensureUserDocument(User user) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    final snap = await docRef.get();
    if (snap.exists) return; // já tem tudo, não mexe

    await docRef.set({
      'name': user.displayName ?? 'Utilizador',
      'email': user.email,
      'photoUrl': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
      'nivel': 1,
      'pontos': 0,
      'goals': {'monthlyKwhTarget': 0, 'monthlyCostTarget': 0, 'focus': 'cost'},
      'privacy': {'shareAnonymous': false},
      'achievements': {
        'firstSaving': false,
        'sevenDaysBelowAverage': false,
        'topTenPercentMonth': false,
      },
      'settings': {
        'theme': 'system',
        'language': 'pt',
        'energyPrice': 0.22,
        'includeTax': true,
        'notifications': {
          'deviceOffline': true,
          'highConsumption': true,
          'goalReached': true,
          'quietHours': {'enabled': false, 'start': '22:00', 'end': '07:00'},
        },
        'automations': {
          'turnAllOffAtMidnight': false,
          'weekdayMorningOn': {
            'enabled': false,
            'time': '07:00',
            'deviceIds': <String>[],
          },
        },
      },
    });
  }
}
