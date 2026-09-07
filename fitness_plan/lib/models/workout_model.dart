// The Exercise class used to be defined in this file (with different fields
// than the one in exercise_model.dart, and yet another version in
// user_model.dart) — all three had the same name and different shapes, which
// only worked because every screen imported user_model.dart with `hide
// Exercise`. Now there's one Exercise, defined in exercise_model.dart and
// re-exported here so existing `import '../models/workout_model.dart'`
// statements keep working without changes.
export 'exercise_model.dart';
import 'exercise_model.dart';

enum WorkoutLevel { beginner, intermediate, advanced }

class WorkoutPlan {
  final String title;
  final String subtitle;
  final String category;
  final int minutes;
  final int calories;
  final WorkoutLevel level;
  final String imagePath;
  final List<Exercise> exercises;

  WorkoutPlan({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.minutes,
    required this.calories,
    required this.level,
    required this.imagePath,
    required this.exercises,
  });
}