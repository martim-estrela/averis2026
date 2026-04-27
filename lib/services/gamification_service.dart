import 'package:cloud_firestore/cloud_firestore.dart';
import 'notif_repository.dart';

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
    final achievementUpdates = _checkAchievements(
      achievements: achievements,
      poupancaPct: poupancaPct,
      novoNivel: novoNivel,
      dia: dia,
      novoStreak: novoStreak,
    );
    updates.addAll(achievementUpdates);

    await userRef.update(updates);

    // Notificação de level-up
    if (novoNivel > nivelAtual) {
      await NotifRepository.write(
        uid: uid,
        type: 'level_up',
        title: 'Subiste de nível!',
        body: 'Parabéns! Atingiste o nível $novoNivel.',
        metadata: {'nivel': novoNivel},
      );
    }

    // Notificações de conquistas desbloqueadas
    const achievementLabels = <String, String>{
      'achievements.firstSaving': 'Primeira Poupança',
      'achievements.reachedLevel3': 'Nível 3 Atingido',
      'achievements.reachedLevel5': 'Nível 5 Atingido',
      'achievements.savedInWeekend': 'Poupança ao Fim de Semana',
      'achievements.streak3Days': '3 Dias Seguidos',
      'achievements.sevenDaysBelowAverage': '7 Dias Abaixo da Média',
    };
    for (final key in achievementUpdates.keys) {
      final label = achievementLabels[key];
      if (label != null) {
        await NotifRepository.write(
          uid: uid,
          type: 'achievement',
          title: 'Conquista desbloqueada!',
          body: label,
          metadata: {'achievement': key.replaceFirst('achievements.', '')},
        );
      }
    }
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

  static Map<String, dynamic> _checkAchievements({
    required Map<String, dynamic> achievements,
    required double poupancaPct,
    required int novoNivel,
    required DateTime dia,
    required int novoStreak,
  }) {
    final Map<String, dynamic> updates = {};

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
    if (achievements['streak3Days'] != true && novoStreak >= 3) {
      updates['achievements.streak3Days'] = true;
    }
    if (achievements['sevenDaysBelowAverage'] != true && novoStreak >= 7) {
      updates['achievements.sevenDaysBelowAverage'] = true;
    }

    return updates;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
