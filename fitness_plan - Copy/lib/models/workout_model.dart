enum WorkoutLevel { beginner, intermediate, advanced }

class Exercise {
  final String name;
  final String duration;
  final String imageAsset;
  final String description;

  Exercise({
    required this.name,
    required this.duration,
    required this.imageAsset,
    this.description = "Focus on your form and maintain steady breathing.",
  });
}

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