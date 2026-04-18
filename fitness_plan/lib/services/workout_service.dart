class WorkoutService {
  final List<Map<String, String>> allExercises = [
    {"name": "Push Up", "level": "beginner", "location": "home"},
    {"name": "Squat", "level": "beginner", "location": "home"},
    {"name": "Plank", "level": "beginner", "location": "home"},
    {"name": "Bench Press", "level": "intermediate", "location": "gym"},
    {"name": "Deadlift", "level": "advanced", "location": "gym"},
  ];

  List<String> generateWorkout(String level, String location) {
    return allExercises
        .where((exercise) {
          bool levelMatch =
              exercise["level"] == level || level == "advanced";
          bool locationMatch = exercise["location"] == location;
          return levelMatch && locationMatch;
        })
        .map((e) => e["name"]!)
        .toList();
  }
}