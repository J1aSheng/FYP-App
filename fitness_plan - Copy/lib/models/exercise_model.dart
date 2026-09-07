class Exercise {
  final String name;
  final String reps;
  final String duration;
  final int caloriesBurned; // Smart metric: How much it burns
  final List<String> instructions; // Smart guideline: Step-by-step steps

  Exercise({
    required this.name,
    required this.reps,
    required this.duration,
    required this.caloriesBurned,
    required this.instructions,
  });

  // Optional: Add a factory to handle data from your AI service or Firestore
  factory Exercise.fromMap(Map<String, dynamic> map) {
    return Exercise(
      name: map['name'] ?? '',
      reps: map['reps'] ?? '',
      duration: map['duration'] ?? '',
      caloriesBurned: map['caloriesBurned'] ?? 0,
      instructions: List<String>.from(map['instructions'] ?? []),
    );
  }
}