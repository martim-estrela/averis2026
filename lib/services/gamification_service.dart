import 'package:cloud_firestore/cloud_firestore.dart';

class GamificationService {
  GamificationService._();

  static final _db = FirebaseFirestore.instance;
  static const int _maxNivel = 6;

  static int pontosParaProximoNivel(int nivelAtual) => nivelAtual * 100;

  // ── Chamado 1x/dia pelo dashboard ─────────────────────────────────────────

  /// Lê os dados do utilizador e dos dispositivos, calcula kwhHoje e mediaKwh,
  /// e chama [processDailySaving]. Só executa uma vez por dia (via lastDailyProcessed).
  static Future<void> processDailyForUser(String uid) async {
    final userRef = _db.collection('users').doc(uid);
    final snap = await userRef.get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final today = _dateKey(DateTime.now());
    if ((data['lastDailyProcessed'] as String?) == today) return;

    // Marcar logo para evitar chamadas concorrentes
    await userRef.update({'lastDailyProcessed': today});

    final devicesSnap =
        await _db.collection('users').doc(uid).collection('devices').get();
    if (devicesSnap.docs.isEmpty) return;

    double kwhHoje = 0;
    final Map<String, double> kwhPorDia = {};
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

    for (final deviceDoc in devicesSnap.docs) {
      final statsRef = deviceDoc.reference.collection('dailyStats');

      // kWh de hoje
      final todayDoc = await statsRef.doc(today).get();
      if (todayDoc.exists) {
        kwhHoje +=
            (todayDoc.data()!['estimatedKwh'] as num?)?.toDouble() ?? 0.0;
      }

      // Últimos 30 dias para calcular média (exclui hoje)
      final histSnap = await statsRef
          .where(FieldPath.documentId,
              isGreaterThanOrEqualTo: _dateKey(thirtyDaysAgo))
          .where(FieldPath.documentId, isLessThan: today)
          .get();
      for (final doc in histSnap.docs) {
        final kwh = (doc.data()['estimatedKwh'] as num?)?.toDouble() ?? 0.0;
        kwhPorDia[doc.id] = (kwhPorDia[doc.id] ?? 0) + kwh;
      }
    }

    if (kwhPorDia.isEmpty) return;
    final mediaKwh =
        kwhPorDia.values.reduce((a, b) => a + b) / kwhPorDia.length;

    await processDailySaving(
      uid: uid,
      kwhHoje: kwhHoje,
      mediaKwh: mediaKwh,
      dia: DateTime.now(),
    );
  }

  // ── Lógica principal de pontos diários ────────────────────────────────────

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

    // Level-up em loop (suporta múltiplos níveis por chamada)
    int novoNivel = nivelAtual;
    int pontosRestantes = pontosAtuais + pontosGanhos;
    while (pontosRestantes >= pontosParaProximoNivel(novoNivel) &&
        novoNivel < _maxNivel) {
      pontosRestantes -= pontosParaProximoNivel(novoNivel);
      novoNivel++;
    }

    final Map<String, dynamic> updates = {
      'nivel': novoNivel,
      'pontos': pontosRestantes,
      'pontosTotal': pontosTotal + pontosGanhos,
    };

    // Streak de poupança
    final poupancaPct = (mediaKwh - kwhHoje) / mediaKwh * 100;
    final today = _dateKey(dia);
    final yesterday = _dateKey(dia.subtract(const Duration(days: 1)));
    final lastStreakDate = (data['lastStreakDate'] as String?) ?? '';
    final currentStreak = (data['streakDias'] as num?)?.toInt() ?? 0;

    int novoStreak;
    if (poupancaPct >= 5) {
      if (lastStreakDate == today) {
        novoStreak = currentStreak; // já atualizado hoje
      } else if (lastStreakDate == yesterday) {
        novoStreak = currentStreak + 1; // continua streak
      } else {
        novoStreak = 1; // começa streak nova
      }
    } else {
      novoStreak = 0;
    }
    updates['streakDias'] = novoStreak;
    updates['lastStreakDate'] = today;

    // Conquistas
    final achievementUpdates = await _checkAchievements(
      uid: uid,
      achievements: achievements,
      poupancaPct: poupancaPct,
      novoNivel: novoNivel,
      dia: dia,
      mediaKwh: mediaKwh,
    );
    updates.addAll(achievementUpdates);

    await userRef.update(updates);
  }

  // ── Pontos por ação imediata (toggle, adicionar dispositivo, etc.) ─────────

  static Future<void> awardActionPoints({
    required String uid,
    required int points,
  }) async {
    if (points <= 0) return;
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      if (!snap.exists) return;
      final data = snap.data()!;
      final nivelAtual = (data['nivel'] as num?)?.toInt() ?? 1;
      final pontosAtuais = (data['pontos'] as num?)?.toInt() ?? 0;
      final pontosTotal = (data['pontosTotal'] as num?)?.toInt() ?? 0;

      int novoNivel = nivelAtual;
      int pontosRestantes = pontosAtuais + points;
      while (pontosRestantes >= pontosParaProximoNivel(novoNivel) &&
          novoNivel < _maxNivel) {
        pontosRestantes -= pontosParaProximoNivel(novoNivel);
        novoNivel++;
      }

      tx.update(userRef, {
        'nivel': novoNivel,
        'pontos': pontosRestantes,
        'pontosTotal': pontosTotal + points,
      });
    });
  }

  // ── Cálculo de pontos ─────────────────────────────────────────────────────

  static int _calcularPontos(double kwhHoje, double mediaKwh) {
    if (mediaKwh <= 0 || kwhHoje >= mediaKwh) return 0;
    final poupancaPct = (mediaKwh - kwhHoje) / mediaKwh * 100;
    if (poupancaPct < 5) return 0;
    if (poupancaPct < 10) return 5;
    if (poupancaPct < 20) return 15;
    if (poupancaPct < 30) return 25;
    return 50;
  }

  // ── Conquistas ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _checkAchievements({
    required String uid,
    required Map<String, dynamic> achievements,
    required double poupancaPct,
    required int novoNivel,
    required DateTime dia,
    required double mediaKwh,
  }) async {
    final Map<String, dynamic> updates = {};

    // firstSaving: requer >=5% de poupança (evita desbloqueio trivial)
    if (achievements['firstSaving'] != true && poupancaPct >= 5) {
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
      if (isWeekend && poupancaPct >= 5) {
        updates['achievements.savedInWeekend'] = true;
      }
    }
    if (achievements['sevenDaysBelowAverage'] != true) {
      final hasStreak = await _checkSevenDayStreak(uid, mediaKwh);
      if (hasStreak) updates['achievements.sevenDaysBelowAverage'] = true;
    }

    return updates;
  }

  static Future<bool> _checkSevenDayStreak(
      String uid, double mediaKwh) async {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));

    final devicesSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('devices')
        .get();
    if (devicesSnap.docs.isEmpty) return false;

    final Map<String, double> kwhPorDia = {};

    for (final deviceDoc in devicesSnap.docs) {
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
