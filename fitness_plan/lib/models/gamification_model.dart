import 'package:cloud_firestore/cloud_firestore.dart';

/// Self-reported energy level, collected before a workout is started.
enum EnergyLevel { low, medium, high }

/// Definition of a single unlockable badge.
class BadgeDef {
  final String id;
  final String title;
  final String description;
  final int Function(UserProgress progress) currentValue;
  final int target;

  const BadgeDef({
    required this.id,
    required this.title,
    required this.description,
    required this.currentValue,
    required this.target,
  });

  bool isUnlocked(UserProgress progress) => currentValue(progress) >= target;
}

/// Aggregated gamification state for a single user.
/// Stored at: users/{uid}/meta/gamification
class UserProgress {
  final int xp;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastCompletedDate;
  final int totalWorkoutsCompleted;
  final int workoutsThisWeek;

  const UserProgress({
    this.xp = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastCompletedDate,
    this.totalWorkoutsCompleted = 0,
    this.workoutsThisWeek = 0,
  });

  int get level => (xp / 100).floor() + 1;
  int get xpIntoLevel => xp % 100;
  double get levelProgress => xpIntoLevel / 100;

  factory UserProgress.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserProgress();
    return UserProgress(
      xp: (map['xp'] ?? 0) as int,
      currentStreak: (map['currentStreak'] ?? 0) as int,
      longestStreak: (map['longestStreak'] ?? 0) as int,
      lastCompletedDate: map['lastCompletedDate'] != null
          ? (map['lastCompletedDate'] as Timestamp).toDate()
          : null,
      totalWorkoutsCompleted: (map['totalWorkoutsCompleted'] ?? 0) as int,
      workoutsThisWeek: (map['workoutsThisWeek'] ?? 0) as int,
    );
  }
}

/// Static catalog of badges the plan screen can display. Extend freely —
/// each entry just needs a way to read its progress value off [UserProgress].
final List<BadgeDef> kBadgeCatalog = [
  BadgeDef(
    id: 'first_step',
    title: 'First Step',
    description: 'Complete your first workout',
    currentValue: (p) => p.totalWorkoutsCompleted,
    target: 1,
  ),
  BadgeDef(
    id: 'consistent',
    title: 'Consistent',
    description: 'Log 5 workouts in a week',
    currentValue: (p) => p.workoutsThisWeek,
    target: 5,
  ),
  BadgeDef(
    id: 'streak_master',
    title: 'Streak Master',
    description: 'Hit a 7 day streak',
    currentValue: (p) => p.longestStreak,
    target: 7,
  ),
  BadgeDef(
    id: 'dedicated',
    title: 'Dedicated',
    description: 'Complete 20 workouts total',
    currentValue: (p) => p.totalWorkoutsCompleted,
    target: 20,
  ),
];