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
          Exercise(
            name: "Mountain Pose",
            reps: "-",
            duration: "2 Min",
            caloriesBurned: 15,
            instructions: [
              "Stand tall with feet together and arms at your sides.",
              "Root down through your feet and lengthen your spine.",
              "Breathe steadily for the full duration.",
            ],
          ),
          Exercise(
            name: "Child's Pose",
            reps: "-",
            duration: "3 Min",
            caloriesBurned: 20,
            instructions: [
              "Kneel and sit back onto your heels.",
              "Fold forward and reach your arms out in front of you.",
              "Relax your shoulders and hold, breathing deeply.",
            ],
          ),
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
        exercises: [
          Exercise(
            name: "Sun Salutation A",
            reps: "3 rounds",
            duration: "5 Min",
            caloriesBurned: 45,
            instructions: [
              "Start in Mountain Pose, then sweep arms overhead.",
              "Fold forward, step or jump back to a plank, then lower down.",
              "Flow through Upward Dog into Downward Dog, and repeat.",
            ],
          ),
        ],
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
          Exercise(
            name: "Forward Lunges",
            reps: "3 sets x 12",
            duration: "5 Min",
            caloriesBurned: 60,
            instructions: [
              "Step forward and lower your back knee toward the floor.",
              "Keep your front knee over your ankle, not past your toes.",
              "Push through your front heel to return to standing.",
            ],
          ),
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
        exercises: [
          Exercise(
            name: "Standard Glute Bridge",
            reps: "3 sets x 15",
            duration: "4 Min",
            caloriesBurned: 40,
            instructions: [
              "Lie on your back with knees bent and feet flat on the floor.",
              "Squeeze your glutes and lift your hips toward the ceiling.",
              "Hold briefly at the top, then lower with control.",
            ],
          ),
        ],
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
        exercises: [
          Exercise(
            name: "Classic Bicep Curl",
            reps: "3 sets x 12",
            duration: "4 Min",
            caloriesBurned: 45,
            instructions: [
              "Hold a weight in each hand with arms extended down.",
              "Curl the weights up toward your shoulders, keeping elbows still.",
              "Lower back down slowly with control.",
            ],
          ),
        ],
      ),
      WorkoutPlan(
        title: "Tricep Dips",
        subtitle: "Using bodyweight to strengthen your arms.",
        category: "Arm",
        minutes: 10,
        calories: 75,
        level: WorkoutLevel.intermediate,
        imagePath: "assets/arm_dips.png",
        exercises: [
          Exercise(
            name: "Chair Dips",
            reps: "3 sets x 10",
            duration: "3 Min",
            caloriesBurned: 35,
            instructions: [
              "Sit on the edge of a chair with hands beside your hips.",
              "Slide off the edge and lower your body by bending your elbows.",
              "Push back up through your palms to the starting position.",
            ],
          ),
        ],
      ),

      // --- PLANK CATEGORY ---
      WorkoutPlan(
        title: "Core Stability",
        subtitle: "Hold steady to build deep abdominal strength.",
        category: "Plank",
        minutes: 5,
        calories: 50,
        level: WorkoutLevel.advanced,
        imagePath: "assets/plank_core.png",
        exercises: [
          Exercise(
            name: "Standard Plank",
            reps: "-",
            duration: "60 Sec",
            caloriesBurned: 50,
            instructions: [
              "Rest on your forearms and toes, body in a straight line.",
              "Brace your core and squeeze your glutes.",
              "Hold the position without letting your hips sag.",
            ],
          ),
        ],
      ),

      // --- CARDIO CATEGORY ---
      WorkoutPlan(
        title: "Jumping Jacks",
        subtitle: "Classic cardio to get your heart rate up.",
        category: "Cardio",
        minutes: 15,
        calories: 150,
        level: WorkoutLevel.beginner,
        imagePath: "assets/cardio_jacks.png",
        exercises: [
          Exercise(
            name: "Speed Jumping Jacks",
            reps: "4 sets x 30 sec",
            duration: "3 Min",
            caloriesBurned: 60,
            instructions: [
              "Start standing with feet together and arms at your sides.",
              "Jump feet apart while raising your arms overhead.",
              "Jump back to start and repeat at a quick, steady pace.",
            ],
          ),
        ],
      ),
      WorkoutPlan(
        title: "Burpee Blast",
        subtitle: "Full body high-intensity interval training.",
        category: "Cardio",
        minutes: 10,
        calories: 200,
        level: WorkoutLevel.advanced,
        imagePath: "assets/cardio_burpees.png",
        exercises: [
          Exercise(
            name: "Full Burpees",
            reps: "4 sets x 10",
            duration: "4 Min",
            caloriesBurned: 90,
            instructions: [
              "Drop into a squat and place your hands on the floor.",
              "Kick your feet back into a plank, then do a push-up.",
              "Jump feet back in and explode upward into a jump.",
            ],
          ),
        ],
      ),

      // --- STRETCH CATEGORY ---
      WorkoutPlan(
        title: "Morning Stretch",
        subtitle: "Wake up your body with light movements.",
        category: "Stretch",
        minutes: 8,
        calories: 40,
        level: WorkoutLevel.beginner,
        imagePath: "assets/stretch_morning.png",
        exercises: [
          Exercise(
            name: "Cat-Cow Stretch",
            reps: "-",
            duration: "2 Min",
            caloriesBurned: 15,
            instructions: [
              "Start on your hands and knees in a tabletop position.",
              "Arch your back and drop your belly for Cow, inhaling.",
              "Round your spine toward the ceiling for Cat, exhaling.",
            ],
          ),
        ],
      ),
    ];
  }

  static List<String> getCategories() => [
    "Yoga", 
    "Leg", 
    "Arm", 
    "Plank", 
    "Cardio", 
    "Stretch"
  ];
}