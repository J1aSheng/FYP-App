import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/gamification_model.dart';
import '../models/workout_model.dart';

/// Handles streaks, XP/leveling, and the "smart" suggestion logic that
/// backs the workout plan screen's dashboard. Reads/writes are kept in the
/// same style as the existing `daily_logs` usage on the plan screen.
class GamificationService {
  final _firestore = FirebaseFirestore.instance;

  DocumentReference _progressDoc(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('meta')
      .doc('gamification');

  /// Live stream of streak/XP/level for the dashboard header + badges row.
  Stream<UserProgress> watchProgress(String uid) {
    return _progressDoc(uid).snapshots().map((snap) {
      if (!snap.exists) return const UserProgress();
      return UserProgress.fromMap(snap.data() as Map<String, dynamic>?);
    });
  }

  /// Call this after a workout is logged (e.g. from the timer screen's
  /// completion flow) to award XP and extend/reset the streak.
  Future<void> recordWorkoutCompletion({
    required String uid,
    required int caloriesBurned,
  }) async {
    final docRef = _progressDoc(uid);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final current = UserProgress.fromMap(
        snap.exists ? snap.data() as Map<String, dynamic>? : null,
      );

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final last = current.lastCompletedDate;
      final lastDay =
          last != null ? DateTime(last.year, last.month, last.day) : null;

      int newStreak;
      if (lastDay == null) {
        newStreak = 1;
      } else {
        final diff = today.difference(lastDay).inDays;
        if (diff == 0) {
          newStreak = current.currentStreak; // already logged today
        } else if (diff == 1) {
          newStreak = current.currentStreak + 1;
        } else {
          newStreak = 1; // streak broken, restart
        }
      }

      final earnedXp = 30 + (caloriesBurned ~/ 5);
      final resetWeekly =
          lastDay != null && today.difference(lastDay).inDays > 7;

      tx.set(
        docRef,
        {
          'xp': current.xp + earnedXp,
          'currentStreak': newStreak,
          'longestStreak':
              newStreak > current.longestStreak ? newStreak : current.longestStreak,
          'lastCompletedDate': Timestamp.fromDate(today),
          'totalWorkoutsCompleted': current.totalWorkoutsCompleted + 1,
          'workoutsThisWeek': resetWeekly ? 1 : current.workoutsThisWeek + 1,
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Picks a short "time-crunch" alternative from [allPlans] — used when the
  /// user hasn't logged anything today and it's getting late. Prefers a plan
  /// in [preferredCategory] under [maxMinutes] long, at the user's level.
  WorkoutPlan? findQuickAlternative({
    required List<WorkoutPlan> allPlans,
    required WorkoutLevel level,
    String? preferredCategory,
    int maxMinutes = 15,
  }) {
    final candidates = allPlans
        .where((p) => p.level == level && p.minutes <= maxMinutes)
        .toList();
    if (candidates.isEmpty) return null;

    if (preferredCategory != null) {
      final match = candidates.where(
          (p) => p.category.toLowerCase() == preferredCategory.toLowerCase());
      if (match.isNotEmpty) return match.first;
    }
    candidates.sort((a, b) => a.minutes.compareTo(b.minutes));
    return candidates.first;
  }

  /// Finds the gentlest (lowest-calorie) plan at the same level, excluding
  /// the one the user just tapped — used to offer an easier swap on
  /// low/medium energy days. Deliberately category-agnostic: since plan
  /// categories are now freely chosen by the AI rather than a fixed list,
  /// "gentler" is judged by calories instead of matching a category name.
  WorkoutPlan? findGentlerAlternative({
    required List<WorkoutPlan> allPlans,
    required WorkoutLevel level,
    required WorkoutPlan excluding,
  }) {
    final candidates = allPlans
        .where((p) => p.level == level && p.title != excluding.title)
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.calories.compareTo(b.calories));
    return candidates.first;
  }

  /// Fetches which days in [month] had a completed workout, keyed by the
  /// total calories burned that day. Reads the same `daily_logs` collection
  /// the dashboard's "today's progress" card already uses.
  Future<Map<DateTime, int>> fetchMonthHistory(String uid, DateTime month) async {
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('daily_logs')
        .get();

    final Map<DateTime, int> result = {};
    for (final doc in snap.docs) {
      DateTime date;
      try {
        date = DateTime.parse(doc.id);
      } catch (_) {
        continue;
      }
      if (date.year != month.year || date.month != month.month) continue;

      final data = doc.data();
      final burned = (data['total_burned'] ?? 0) as int;
      if (burned > 0) {
        result[DateTime(date.year, date.month, date.day)] = burned;
      }
    }
    return result;
  }
}