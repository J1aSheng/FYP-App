import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'database_service.dart';
import '../models/user_model.dart' hide Exercise;
import '../models/workout_model.dart';

class GroqAiService {
  // TODO: move this to --dart-define / a secrets manager instead of hardcoding.
  static const String _apiKey = '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';
  static const String _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';

  // Fast general-purpose text model for chat + plan generation.
  static const String _textModel = 'llama-3.3-70b-versatile';
  // Vision-capable model for the food-photo scanner.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
  static const String _visionModel = 'meta-llama/llama-4-scout-17b-16e-instruct';

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
          "Create 5 exercises for ${user.goal}. Return ONLY format: Name | Duration | Description.";
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
        return Exercise(
          name: parts[0].trim(),
          duration: parts[1].trim(),
          imageAsset: "assets/exercise.png",
          description: parts[2].trim(),
        );
      }).toList();
    } catch (e) {
      return [Exercise(name: "Stretching", duration: "10 min", imageAsset: "", description: "Relax.")];
    }
  }

  /// Generates personalized workout plans via Groq, using JSON mode
  /// instead of manual ```json fence-stripping.
  Future<List<WorkoutPlan>> generatePersonalizedPlans(UserModel user) async {
    try {
      final prompt = """
      Act as a professional fitness coach. Generate exactly 15 workout plans.
      User Profile: ${user.weight}kg, Goal: ${user.goal}.

      STRICT DATA RULES:
      1. Category Set: Yoga, Cardio, Arm, Leg, Plank (3 levels each: 0, 1, 2).
      2. TIME MATCH: The sum of durations of all exercises MUST equal the total 'minutes' of the plan.
      3. CALORIE MATCH: Use MET values (Cardio=8, Yoga=3, Plank/Strength=5) to calculate calories for a ${user.weight}kg person.
      4. INSTRUCTIONS: For each exercise, provide 3 clear, step-by-step instructions.

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
            "exercises": [{"name": "String", "duration": "String", "description": "Step 1... Step 2... Step 3..."}]
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
        exercises: (item['exercises'] as List).map((e) => Exercise(
          name: e['name'],
          duration: e['duration'],
          imageAsset: "assets/exercise.png",
          description: e['description'] ?? "Maintain steady form.",
        )).toList(),
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
            duration: "10 Min",
            imageAsset: "",
            description: "1. Stand with feet shoulder-width apart.\n2. Gently rotate your neck clockwise.\n3. Reach for your toes and hold for 10 seconds.",
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
              {'type': 'text', 'text': 'Identify food/calories. Reply ONLY JSON: {"name": "name", "calories": 123}'},
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
      return jsonDecode(text);
    } catch (e) {
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
