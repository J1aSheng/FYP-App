import '../models/workout_model.dart';

class WorkoutService {
  static List<WorkoutPlan> getWorkoutPlans() {
    return [
      // --- YOGA CATEGORY ---
      WorkoutPlan(
        title: "Hatha Yoga",
        subtitle: "Slow-paced stretching and breathing exercises.",
        category: "Yoga",
        minutes: 20,
        calories: 100,
        level: WorkoutLevel.beginner,
        imagePath: "assets/yoga_hatha.png",
        exercises: [
          Exercise(name: "Mountain Pose", duration: "2 Min", imageAsset: "assets/pose1.png"),
          Exercise(name: "Child's Pose", duration: "3 Min", imageAsset: "assets/pose2.png"),
        ],
      ),
      WorkoutPlan(
        title: "Vinyasa Flow",
        subtitle: "Fluid transitions between different poses.",
        category: "Yoga",
        minutes: 30,
        calories: 180,
        level: WorkoutLevel.intermediate,
        imagePath: "assets/yoga_vinyasa.png",
        exercises: [],
      ),

      // --- LEG CATEGORY ---
      WorkoutPlan(
        title: "Power Lunges",
        subtitle: "Build lower body strength and stability.",
        category: "Leg",
        minutes: 15,
        calories: 120,
        level: WorkoutLevel.intermediate,
        imagePath: "assets/leg_lunges.png",
        exercises: [
          Exercise(name: "Forward Lunges", duration: "5 Min", imageAsset: "assets/ex_lunge.png"),
        ],
      ),
      WorkoutPlan(
        title: "Glute Bridge",
        subtitle: "Targeting your glutes and core muscles.",
        category: "Leg",
        minutes: 10,
        calories: 80,
        level: WorkoutLevel.beginner,
        imagePath: "assets/leg_glute.png",
        exercises: [],
      ),

      // --- ARM CATEGORY ---
      WorkoutPlan(
        title: "Bicep Curls",
        subtitle: "Isolate your arm muscles for definition.",
        category: "Arm",
        minutes: 12,
        calories: 90,
        level: WorkoutLevel.beginner,
        imagePath: "assets/arm_curls.png",
        exercises: [],
      ),
      WorkoutPlan(
        title: "Tricep Dips",
        subtitle: "Using bodyweight to strengthen your arms.",
        category: "Arm",
        minutes: 10,
        calories: 75,
        level: WorkoutLevel.intermediate,
        imagePath: "assets/arm_dips.png",
        exercises: [],
      ),

      // --- PLANK CATEGORY ---[cite: 6]
      WorkoutPlan(
        title: "Core Stability",
        subtitle: "Hold steady to build deep abdominal strength.",
        category: "Plank",
        minutes: 5,
        calories: 50,
        level: WorkoutLevel.advanced,
        imagePath: "assets/plank_core.png",
        exercises: [
          Exercise(name: "Standard Plank", duration: "60 Sec", imageAsset: "assets/plank1.png"),
        ],
      ),

      // --- NEW: CARDIO CATEGORY ---[cite: 6]
      WorkoutPlan(
        title: "Jumping Jacks",
        subtitle: "Classic cardio to get your heart rate up.",
        category: "Cardio",
        minutes: 15,
        calories: 150,
        level: WorkoutLevel.beginner,
        imagePath: "assets/cardio_jacks.png",
        exercises: [],
      ),
      WorkoutPlan(
        title: "Burpee Blast",
        subtitle: "Full body high-intensity interval training.",
        category: "Cardio",
        minutes: 10,
        calories: 200,
        level: WorkoutLevel.advanced,
        imagePath: "assets/cardio_burpees.png",
        exercises: [],
      ),

      // --- NEW: STRETCH CATEGORY ---[cite: 6]
      WorkoutPlan(
        title: "Morning Stretch",
        subtitle: "Wake up your body with light movements.",
        category: "Stretch",
        minutes: 8,
        calories: 40,
        level: WorkoutLevel.beginner,
        imagePath: "assets/stretch_morning.png",
        exercises: [],
      ),
    ];
  }

  // ✅ Automatically updated categories list
  static List<String> getCategories() => [
    "Yoga", 
    "Leg", 
    "Arm", 
    "Plank", 
    "Cardio", 
    "Stretch"
  ];
}