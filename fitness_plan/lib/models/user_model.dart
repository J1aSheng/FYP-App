class UserModel {
  final String uid, name, gender, goal, level, location;
  final double weight, height;
  final int age, currentStreak;

  UserModel({
    required this.uid, required this.name, required this.gender,
    required this.weight, required this.height, required this.age,
    required this.goal, required this.level, required this.location,
    this.currentStreak = 0,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String id) {
    return UserModel(
      uid: id,
      name: data['name'] ?? 'User',
      gender: data['gender'] ?? 'male',
      weight: (data['weight'] as num).toDouble(),
      height: (data['height'] as num).toDouble(),
      age: (data['age'] as num).toInt(),
      goal: data['goal'] ?? 'Stay Healthy',
      level: data['level'] ?? 'Beginner',
      location: data['location'] ?? 'Home',
      currentStreak: data['currentStreak'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name, 'gender': gender, 'weight': weight, 'height': height,
    'age': age, 'goal': goal, 'level': level, 'location': location,
    'currentStreak': currentStreak,
  };
}

class MealPlan {
  final String id, name, imageUrl;
  final int calories;
  
  MealPlan({required this.id, required this.name, required this.calories, required this.imageUrl});
}

// Exercise used to be defined here too — it's now only in exercise_model.dart
// (see WorkoutPlan in workout_model.dart, which exports it) so every screen
// works with one Exercise shape instead of three incompatible ones.