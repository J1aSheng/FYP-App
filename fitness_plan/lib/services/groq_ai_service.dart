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
  Future<List<WorkoutPlan>> generatePersonalizedPlans(UserModel user) async {
    try {
      // The old prompt only passed weight + goal to the model, then let it
      // pick levels for all 15 plans on its own — nothing tied plan
      // difficulty back to the user's actual level. This anchors both the
      // exercise selection language and the level distribution to it.
      final levelIndex = WorkoutLevel.values.indexWhere(
        (e) => e.name.toLowerCase() == user.level.toLowerCase(),
      );
      final safeLevelIndex = levelIndex == -1 ? 0 : levelIndex;

      final prompt = """
      Act as a certified personal trainer creating a fully personalized workout program for one specific client.

      CLIENT PROFILE
      - Weight: ${user.weight}kg
      - Goal: ${user.goal}
      - Current fitness level: ${user.level} (level index $safeLevelIndex, where 0=beginner, 1=intermediate, 2=advanced)

      PERSONALIZATION RULES
      1. Level distribution: at least 9 of the 15 plans MUST have "level": $safeLevelIndex (the client's current level). Spread the remaining plans across the other levels, but do not skip generating plans for levels above the client's — the app shows those as locked/upcoming goals.
      2. Match intensity language in each exercise's steps to the plan's own level — e.g. beginner steps should cue more rest, simpler ranges of motion, and form basics; advanced steps should cue tempo, reduced rest, and harder variations of the same movement.
      3. Skew exercise choice toward the stated goal (${user.goal}) — e.g. a fat-loss-leaning goal gets more Cardio/Plank volume, a muscle- or strength-leaning goal gets more Arm/Leg work, a mobility/wellness goal gets more Yoga.
      4. Never generate two plans in the same category + level that are near-duplicates of each other — vary the exercise selection even when the category/level repeats.

      STRICT DATA RULES
      1. CATEGORY: Freely choose a short, natural category label for each plan (e.g. "Cardio", "Strength", "Mobility", "HIIT", "Core", "Recovery") based on whatever best fits the exercises in it — do not restrict yourself to any fixed list. Generate exactly 15 plans total.
      2. TIME MATCH: The sum of durations of all exercises MUST equal the total 'minutes' of the plan.
      3. CALORIE MATCH: Use MET values (Cardio=8, Yoga=3, Plank/Strength=5) to calculate the plan's total calories for a ${user.weight}kg person.
      4. PER-EXERCISE CALORIES: For each exercise, also estimate "caloriesBurned" as its proportional share of the plan total, based on the same MET calculation and that exercise's share of the plan's total duration.
      5. REPS: For each exercise, give a realistic "reps" value (e.g. "12 reps", "3 sets x 10", or "-" for time-based holds like planks).
      6. INSTRUCTIONS: Return "instructions" as a JSON array of exactly 3 short, clear steps — each its own string, not one combined blob of text.

      Return ONLY a JSON object shaped exactly like this:
      {
        "plans": [
          {
            "title": "String",
            "subtitle": "String",
            "category": "String",
            "minutes": int,
            "calories": int,
            "level": int,
            "exercises": [
              {
                "name": "String",
                "reps": "String",
                "duration": "String",
                "caloriesBurned": int,
                "instructions": ["Step 1 text", "Step 2 text", "Step 3 text"]
              }
            ]
          }
        ]
      }
      """;

      final data = await _chat(
        messages: [
          {'role': 'system', 'content': 'You always respond with a single valid JSON object, no extra commentary.'},
          {'role': 'user', 'content': prompt},
        ],
        model: _textModel,
        jsonMode: true,
      );

      final String rawText = data['choices'][0]['message']['content'];
      final Map<String, dynamic> decoded = jsonDecode(rawText);
      final List<dynamic> plans = decoded['plans'] ?? [];

      return plans.map((item) => WorkoutPlan(
        title: item['title'],
        subtitle: item['subtitle'],
        category: item['category'],
        minutes: item['minutes'],
        calories: item['calories'],
        level: WorkoutLevel.values[item['level'] ?? 0],
        imagePath: "assets/ai_gen.png",
        exercises: (item['exercises'] as List).map((e) {
          final instructions = (e['instructions'] as List?)
                  ?.map((s) => s.toString())
                  .where((s) => s.trim().isNotEmpty)
                  .toList() ??
              [];
          return Exercise(
            name: e['name'],
            reps: e['reps'] ?? '-',
            duration: e['duration'],
            caloriesBurned: (e['caloriesBurned'] as num?)?.toInt() ?? 0,
            instructions: instructions.isNotEmpty ? instructions : ["Maintain steady form."],
          );
        }).toList(),
      )).toList();
    } catch (e) {
      debugPrint("AI Error: $e. Returning Detailed Fallback.");
      return _getFallbackPlans();
    }
  }

  List<WorkoutPlan> _getFallbackPlans() {
    List<String> categories = ["Yoga", "Cardio", "Arm", "Leg", "Plank"];
    return categories.expand((cat) => [
      WorkoutPlan(
        title: "$cat Beginner Basics",
        subtitle: "Safe entry-level movements.",
        category: cat,
        minutes: 10, calories: 60,
        level: WorkoutLevel.beginner,
        imagePath: "assets/ai_gen.png",
        exercises: [
          Exercise(
            name: "Warm up Stretch",
            reps: "-",
            duration: "10 Min",
            caloriesBurned: 60,
            instructions: [
              "Stand with feet shoulder-width apart.",
              "Gently rotate your neck clockwise.",
              "Reach for your toes and hold for 10 seconds.",
            ],
          ),
        ],
      ),
    ]).toList();
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