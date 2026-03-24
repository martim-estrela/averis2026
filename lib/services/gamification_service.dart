import 'package:cloud_firestore/cloud_firestore.dart';

class GamificationService {
  GamificationService._();

  static final _db = FirebaseFirestore.instance;

  static int pontosParaProximoNivel(int nivelAtual) => nivelAtual * 100;

  static Future<void> processDailySaving({
    required String uid,
    required double kwhHoje,
    required double mediaKwh,
    required DateTime dia,
  }) async {
    if (mediaKwh <= 0) return;

    final userRef = _db.collection('users').doc(uid);
    final snap = await userRef.get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final nivelAtual = (data['nivel'] as num?)?.toInt() ?? 1;
    final pontosAtuais = (data['pontos'] as num?)?.toInt() ?? 0;
    final pontosTotal = (data['pontosTotal'] as num?)?.toInt() ?? 0;
    final achievements =
        (data['achievements'] as Map?)?.cast<String, dynamic>() ?? {};

    final pontosGanhos = _calcularPontos(kwhHoje, mediaKwh);
    if (pontosGanhos <= 0) return;

    final novosPontos = pontosAtuais + pontosGanhos;
    final novosPontosTotal = pontosTotal + pontosGanhos;
    final limiteNivel = pontosParaProximoNivel(nivelAtual);

    int novoNivel = nivelAtual;
    int pontosRestantes = novosPontos;

    if (novosPontos >= limiteNivel) {
      novoNivel = nivelAtual + 1;
      pontosRestantes = novosPontos - limiteNivel;
    }

    final Map<String, dynamic> updates = {
      'nivel': novoNivel,
      'pontos': pontosRestantes,
      'pontosTotal': novosPontosTotal,
    };

    final achievementUpdates = await _checkAchievements(
      uid: uid,
      achievements: achievements,
      kwhHoje: kwhHoje,
      mediaKwh: mediaKwh,
      novoNivel: novoNivel,
      dia: dia,
    );
    updates.addAll(achievementUpdates);

    await userRef.update(updates);
  }

  static int _calcularPontos(double kwhHoje, double mediaKwh) {
    if (mediaKwh <= 0 || kwhHoje >= mediaKwh) return 0;
    final poupancaPct = (mediaKwh - kwhHoje) / mediaKwh * 100;
    if (poupancaPct < 5) return 0;
    if (poupancaPct < 10) return 5;
    if (poupancaPct < 20) return 15;
    if (poupancaPct < 30) return 25;
    return 50;
  }

  static Future<Map<String, dynamic>> _checkAchievements({
    required String uid,
    required Map<String, dynamic> achievements,
    required double kwhHoje,
    required double mediaKwh,
    required int novoNivel,
    required DateTime dia,
  }) async {
    final Map<String, dynamic> updates = {};

    if (achievements['firstSaving'] != true && kwhHoje < mediaKwh) {
      updates['achievements.firstSaving'] = true;
    }
    if (achievements['reachedLevel3'] != true && novoNivel >= 3) {
      updates['achievements.reachedLevel3'] = true;
    }
    if (achievements['reachedLevel5'] != true && novoNivel >= 5) {
      updates['achievements.reachedLevel5'] = true;
    }
    if (achievements['savedInWeekend'] != true) {
      final isWeekend = dia.weekday == DateTime.saturday ||
          dia.weekday == DateTime.sunday;
      if (isWeekend && kwhHoje < mediaKwh) {
        updates['achievements.savedInWeekend'] = true;
      }
    }
    if (achievements['sevenDaysBelowAverage'] != true) {
      final hasStreak = await _checkSevenDayStreak(uid, mediaKwh);
      if (hasStreak) {
        updates['achievements.sevenDaysBelowAverage'] = true;
      }
    }

    return updates;
  }

  static Future<bool> _checkSevenDayStreak(
      String uid, double mediaKwh) async {
    final sevenDaysAgo =
        DateTime.now().subtract(const Duration(days: 7));

    // ✅ users/{uid}/devices
    final devicesSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('devices')
        .get();

    if (devicesSnap.docs.isEmpty) return false;

    final Map<String, double> kwhPorDia = {};

    for (final deviceDoc in devicesSnap.docs) {
      // ✅ users/{uid}/devices/{id}/dailyStats
      final statsSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceDoc.id)
          .collection('dailyStats')
          .where(FieldPath.documentId,
              isGreaterThanOrEqualTo: _dateKey(sevenDaysAgo))
          .get();

      for (final doc in statsSnap.docs) {
        final kwh =
            (doc.data()['estimatedKwh'] as num?)?.toDouble() ?? 0.0;
        kwhPorDia[doc.id] = (kwhPorDia[doc.id] ?? 0) + kwh;
      }
    }

    if (kwhPorDia.length < 7) return false;
    return kwhPorDia.values.every((kwh) => kwh < mediaKwh);
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
