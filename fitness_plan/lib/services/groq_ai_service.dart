import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'database_service.dart';
import '../models/user_model.dart';
import '../models/workout_model.dart';

class GroqAiService {
  // TODO: move this to --dart-define / a secrets manager instead of hardcoding.
  static const String _apiKey = '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';
  static const String _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';

  // Fast general-purpose text model for chat + plan generation.
  // Note: llama-3.3-70b-versatile is also on Groq's deprecation list —
  // migrated to their recommended replacement.
  static const String _textModel = 'openai/gpt-oss-120b';
  // Vision-capable model for the food-photo scanner.
  // Note: meta-llama/llama-4-scout-17b-16e-instruct was deprecated by Groq
  // on June 17, 2026 (this is what was causing the 404 errors). gpt-oss-120b
  // is Groq's suggested general migration target but is TEXT-ONLY — it
  // can't accept images — so the vision-capable replacement is Qwen3.6 27B.
  // Groq currently marks this as a preview model, so double-check
  // console.groq.com/docs/vision for the latest recommendation.
  static const String _visionModel = 'qwen/qwen3.6-27b';

  Future<Map<String, dynamic>> _chat({
    required List<Map<String, dynamic>> messages,
    required String model,
    bool jsonMode = false,
  }) async {
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        if (jsonMode) 'response_format': {'type': 'json_object'},
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Groq API error ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<String?> getChatResponse(String prompt) async {
    try {
      final data = await _chat(
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        model: _textModel,
      );
      return data['choices'][0]['message']['content'] as String?;
    } catch (e) {
      debugPrint("AI Chat Error: $e");
      return null;
    }
  }

  Future<List<Exercise>> generateDailyWorkout(UserModel user) async {
    try {
      final prompt =
          "Create 5 exercises for ${user.goal}. Return ONLY this pipe-delimited format, one exercise per line, "
          "no extra commentary: Name | Reps | Duration | CaloriesBurned | Step1; Step2; Step3";
      final data = await _chat(
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        model: _textModel,
      );
      final String text = data['choices'][0]['message']['content'];
      final lines = text.split('\n').where((l) => l.contains('|'));

      return lines.map((line) {
        final parts = line.split('|');
        final instructionsRaw = parts.length > 4 ? parts[4] : '';
        final instructions = instructionsRaw
            .split(';')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        return Exercise(
          name: parts[0].trim(),
          reps: parts.length > 1 ? parts[1].trim() : '-',
          duration: parts.length > 2 ? parts[2].trim() : '-',
          caloriesBurned: parts.length > 3 ? int.tryParse(parts[3].trim()) ?? 0 : 0,
          instructions: instructions.isNotEmpty ? instructions : ["Maintain steady form."],
        );
      }).toList();
    } catch (e) {
      return [
        Exercise(
          name: "Stretching",
          reps: "-",
          duration: "10 min",
          caloriesBurned: 20,
          instructions: ["Relax and breathe steadily."],
        ),
      ];
    }
  }

  /// Generates personalized workout plans via Groq, using JSON mode
  /// instead of manual ```json fence-stripping.
  Future<List<WorkoutPlan>> generatePersonalizedPlans(
    UserModel user,
  ) async {
    try {
      final prompt = """
Act as a certified personal trainer.

Create a personalized workout library for this user.

USER PROFILE
- Weight: ${user.weight} kg
- Goal: ${user.goal}
- Current fitness level: ${user.level}

STRICT STRUCTURE

Generate EXACTLY 15 workout plans total.

There are exactly 3 fitness levels:
- Beginner = level 0
- Intermediate = level 1
- Advanced = level 2

For EACH fitness level, generate EXACTLY ONE plan for EACH
of these 5 categories:

1. Cardio
2. Strength
3. Mobility
4. Core
5. Full Body

The result MUST therefore be:

BEGINNER
- 1 Cardio plan
- 1 Strength plan
- 1 Mobility plan
- 1 Core plan
- 1 Full Body plan

INTERMEDIATE
- 1 Cardio plan
- 1 Strength plan
- 1 Mobility plan
- 1 Core plan
- 1 Full Body plan

ADVANCED
- 1 Cardio plan
- 1 Strength plan
- 1 Mobility plan
- 1 Core plan
- 1 Full Body plan

TOTAL = 15 PLANS.

ONE PLAN = ONE WORKOUT VIDEO

Every plan must contain EXACTLY ONE activity in its
"exercises" array.

The single activity represents the COMPLETE workout session.
The app will use that activity name to search for ONE
YouTube follow-along workout video.

Do NOT create multiple exercises inside a plan.
Do NOT create multiple plans for the same category and level.

DURATION
- Every plan must be suitable for a 10-15 minute video.
- "minutes" must be an integer from 10 through 15.
- The single activity duration must match the plan minutes.

PERSONALIZATION
- Personalize workout titles and activity names for the user's goal: ${user.goal}.
- Use the user's weight (${user.weight} kg) for sensible calorie estimates.
- Beginner should be easier.
- Intermediate should be moderate.
- Advanced should be more challenging.
- Keep all workouts realistic and safe.
- Activity names should be useful YouTube search phrases.

CALORIES
- Estimate calories realistically.
- The single activity's caloriesBurned must equal the plan's calories.

REPS
Always use:
"reps": "Follow video"

INSTRUCTIONS
Return exactly 3 short safety/form instructions for the single activity.

Return ONLY one valid JSON object with this structure:

{
  "plans": [
    {
      "title": "Personalized Cardio Workout",
      "subtitle": "Short personalized description",
      "category": "Cardio",
      "minutes": 12,
      "calories": 100,
      "level": 0,
      "exercises": [
        {
          "name": "Low Impact Cardio Workout",
          "reps": "Follow video",
          "duration": "12 min",
          "caloriesBurned": 100,
          "instructions": [
            "Follow the video at a controlled pace.",
            "Maintain good form throughout.",
            "Stop and rest if you feel unwell."
          ]
        }
      ]
    }
  ]
}
""";

      final data = await _chat(
        messages: [
          {
            'role': 'system',
            'content':
                'Return one valid JSON object only. Follow every requested count exactly.',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
        model: _textModel,
        jsonMode: true,
      );

      final rawText =
          data['choices'][0]['message']['content']
              as String;

      final decoded =
          jsonDecode(rawText)
              as Map<String, dynamic>;

      final rawPlans = decoded['plans'];

      if (rawPlans is! List ||
          rawPlans.length != 15) {
        throw FormatException(
          'Expected exactly 15 plans.',
        );
      }

      const categories = [
        'Cardio',
        'Strength',
        'Mobility',
        'Core',
        'Full Body',
      ];

      final plans = <WorkoutPlan>[];

      for (final rawPlan in rawPlans) {
        final item =
            Map<String, dynamic>.from(
          rawPlan as Map,
        );

        final category =
            item['category']?.toString().trim() ??
                '';

        final levelIndex =
            (item['level'] as num?)?.toInt() ??
                -1;

        if (!categories.contains(category)) {
          throw FormatException(
            'Unexpected category: $category',
          );
        }

        if (levelIndex < 0 ||
            levelIndex >
                WorkoutLevel.values.length - 1) {
          throw FormatException(
            'Invalid workout level.',
          );
        }

        final rawExercises =
            item['exercises'];

        if (rawExercises is! List ||
            rawExercises.length != 1) {
          throw const FormatException(
            'Each plan must contain exactly one activity.',
          );
        }

        final exercise =
            Map<String, dynamic>.from(
          rawExercises.first as Map,
        );

        final minutes =
            ((item['minutes'] as num?)
                        ?.toInt() ??
                    12)
                .clamp(10, 15);

        final calories =
            (item['calories'] as num?)
                    ?.toInt() ??
                0;

        final instructions =
            (exercise['instructions'] as List?)
                    ?.map(
                      (value) =>
                          value.toString().trim(),
                    )
                    .where(
                      (value) => value.isNotEmpty,
                    )
                    .take(3)
                    .toList() ??
                <String>[];

        while (instructions.length < 3) {
          instructions.add(
            'Maintain controlled form and steady breathing.',
          );
        }

        plans.add(
          WorkoutPlan(
            title:
                item['title']?.toString() ??
                    '$category Workout',
            subtitle:
                item['subtitle']?.toString() ??
                    'Personalized workout for ${user.goal}.',
            category: category,
            minutes: minutes,
            calories: calories,
            level:
                WorkoutLevel.values[levelIndex],
            imagePath: 'assets/ai_gen.png',
            exercises: [
              Exercise(
                name:
                    exercise['name']?.toString() ??
                        '$category Workout',
                reps: 'Follow video',
                duration: '$minutes min',
                caloriesBurned: calories,
                instructions: instructions,
              ),
            ],
          ),
        );
      }

      // Enforce exactly ONE plan for every level/category pair.
      // 3 levels x 5 categories = 15 unique plans.
      for (final level in WorkoutLevel.values) {
        for (final category in categories) {
          final count = plans.where(
            (plan) =>
                plan.level == level &&
                plan.category == category,
          ).length;

          if (count != 1) {
            throw FormatException(
              'Expected exactly one $category plan for ${level.name}.',
            );
          }
        }
      }

      return plans;
    } catch (e) {
      debugPrint(
        'AI workout generation error: $e. Using fallback.',
      );

      return _getFallbackPlans(user);
    }
  }

  List<WorkoutPlan> _getFallbackPlans(
    UserModel user,
  ) {
    const categories = [
      'Cardio',
      'Strength',
      'Mobility',
      'Core',
      'Full Body',
    ];

    final plans = <WorkoutPlan>[];

    for (final level in WorkoutLevel.values) {
      for (final category in categories) {
        final minutes =
            _fallbackMinutes(level);

        final calories =
            _fallbackCalories(
          weightKg: user.weight,
          level: level,
          category: category,
          minutes: minutes,
        );

        plans.add(
          WorkoutPlan(
            title: _fallbackTitle(
              category,
              level,
              user.goal,
            ),
            subtitle:
                'Personalized ${level.name} $category workout for ${user.goal}.',
            category: category,
            minutes: minutes,
            calories: calories,
            level: level,
            imagePath: 'assets/ai_gen.png',
            exercises: [
              Exercise(
                name: _fallbackActivityName(
                  category,
                  level,
                ),
                reps: 'Follow video',
                duration: '$minutes min',
                caloriesBurned: calories,
                instructions: const [
                  'Follow the workout video at a controlled pace.',
                  'Maintain good form and steady breathing.',
                  'Stop and rest if you feel pain or dizziness.',
                ],
              ),
            ],
          ),
        );
      }
    }

    return plans;
  }

  int _fallbackMinutes(
    WorkoutLevel level,
  ) {
    switch (level) {
      case WorkoutLevel.beginner:
        return 10;
      case WorkoutLevel.intermediate:
        return 12;
      case WorkoutLevel.advanced:
        return 15;
    }
  }

  String _fallbackTitle(
    String category,
    WorkoutLevel level,
    String goal,
  ) {
    final levelName =
        level.name[0].toUpperCase() +
            level.name.substring(1);

    return '$levelName $category Session';
  }

  String _fallbackActivityName(
    String category,
    WorkoutLevel level,
  ) {
    final levelName =
        level.name[0].toUpperCase() +
            level.name.substring(1);

    switch (category) {
      case 'Strength':
        return '$levelName Full Body Strength Workout';
      case 'Mobility':
        return '$levelName Full Body Mobility Workout';
      case 'Core':
        return '$levelName Core Workout';
      case 'Full Body':
        return '$levelName Full Body Fitness Workout';
      case 'Cardio':
      default:
        return '$levelName Cardio Workout';
    }
  }

  int _fallbackCalories({
    required double weightKg,
    required WorkoutLevel level,
    required String category,
    required int minutes,
  }) {
    final safeWeight =
        weightKg <= 0 ? 65.0 : weightKg;

    double met;

    switch (category) {
      case 'Strength':
        met = 5.0;
        break;
      case 'Mobility':
        met = 3.0;
        break;
      case 'Core':
        met = 4.5;
        break;
      case 'Full Body':
        met = 6.0;
        break;
      case 'Cardio':
      default:
        met = 7.0;
        break;
    }

    switch (level) {
      case WorkoutLevel.beginner:
        met *= 0.80;
        break;
      case WorkoutLevel.intermediate:
        break;
      case WorkoutLevel.advanced:
        met *= 1.20;
        break;
    }

    return (
      met *
      3.5 *
      safeWeight /
      200 *
      minutes
    ).round();
  }

  /// Sends an image to a Groq vision model as a base64 data URI,
  /// mirroring the OpenAI-style multimodal message format.
  Future<Map<String, dynamic>?> analyzeFoodImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final data = await _chat(
        messages: [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Identify the food in this image. Reply ONLY with JSON in exactly this shape: {"food_name": "string", "calories": 123, "portion": "string"}'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
              },
            ],
          },
        ],
        model: _visionModel,
        jsonMode: true,
      );

      final String text = data['choices'][0]['message']['content'];
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      // Defensive: if the model ever omits food_name/calories despite the
      // prompt, fail loudly here instead of returning a silently-broken map.
      if (decoded['food_name'] == null || decoded['calories'] == null) {
        debugPrint("Food Scan Warning: unexpected shape from model: $decoded");
      }
      return decoded;
    } catch (e) {
      // ✅ Previously this only logged the exception message, which for a
      // FormatException from jsonDecode doesn't show what the model
      // actually replied with — making it impossible to tell whether the
      // API call failed, the key was invalid, or the model just didn't
      // follow the JSON instruction.
      debugPrint("Food Scan Error: $e");
      return null;
    }
  }
}

// --- CameraTab Implementation (unchanged logic, updated class refs) ---
class CameraTab extends StatefulWidget {
  final String uid;
  final Function(int) onFoodDetected;
  const CameraTab({super.key, required this.onFoodDetected, required this.uid});
  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> {
  bool _scanning = false;
  File? _capturedImage;
  final ImagePicker _picker = ImagePicker();
  final _aiService = GroqAiService();
  final _dbService = DatabaseService();

  Future<void> _takePhotoAndScan() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1024);
    if (photo == null) return;
    setState(() { _scanning = true; _capturedImage = File(photo.path); });
    try {
      final foodData = await _aiService.analyzeFoodImage(_capturedImage!);
      if (foodData != null && mounted) {
        await _dbService.logMealWithSync(widget.uid, foodData, photo.path);
        setState(() => _scanning = false);
        widget.onFoodDetected(foodData['calories']);
      }
    } catch (e) { setState(() => _scanning = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI Food Scanner"), backgroundColor: const Color(0xFF2E7D32)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 300, width: 300,
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(20)),
              child: _scanning
                  ? const Center(child: CircularProgressIndicator())
                  : (_capturedImage != null
                      ? ClipRRect(borderRadius: BorderRadius.circular(19), child: Image.file(_capturedImage!, fit: BoxFit.cover))
                      : const Icon(Icons.camera_alt, size: 80, color: Colors.grey)),
            ),
            const SizedBox(height: 30),
            ElevatedButton(onPressed: _scanning ? null : _takePhotoAndScan, child: const Text("Capture & Analyze")),
          ],
        ),
      ),
    );
  }
}