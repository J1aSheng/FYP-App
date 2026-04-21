import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'database_service.dart'; 
import '../models/user_model.dart' hide Exercise; // ✅ Prevents name conflict
import '../models/exercise_model.dart';           // ✅ Uses the Smart Model

class GeminiAiService {
  final _model = GenerativeModel(
    model: 'gemini-1.5-flash', 
    apiKey: 'AQ.Ab8RN6JSRtfLVlFsUVywnfm6YM5u8K8BIAo37X_aFJE7kYtpsA',
    safetySettings: [
      SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
      SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
    ],
  );

  /// SMART WORKOUT GENERATION
  /// Fetches name, reps, duration, calories, and instructions dynamically
  Future<List<Exercise>> generateDailyWorkout(UserModel user) async {
    try {
      // ✅ Prompt configured for 5 to 7 different exercises to fill the dashboard
      final prompt = "Create a list of 5 to 7 different ${user.level} exercises for someone who wants to ${user.goal} at ${user.location}. "
          "Return ONLY a list of exercises in this exact format: "
          "Name | Reps | Duration | CaloriesBurned (integer) | Instruction1, Instruction2, Instruction3. "
          "No extra text.";
      
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? "";

      // Logic to parse the AI text into Smart Exercise objects
      return text.split('\n').where((line) => line.contains('|')).map((line) {
        final parts = line.split('|');
        
        return Exercise(
          name: parts[0].trim(),
          reps: parts[1].trim(),
          duration: parts[2].trim(),
          // ✅ SMART METRIC: Parse calorie number
          caloriesBurned: int.tryParse(parts[3].trim()) ?? 100, 
          // ✅ SMART GUIDELINE: Convert comma-separated text to a List
          instructions: parts[4].split(',').map((s) => s.trim()).toList(),
        );
      }).toList();
    } catch (e) {
      debugPrint("AI Workout Error: $e");
      // ✅ FALLBACK: Provides a full object if AI fails, preventing crashes
      return [
        Exercise(
          name: "Home Stretching", 
          reps: "1", 
          duration: "15 mins", 
          caloriesBurned: 80, 
          instructions: ["Find a quiet space", "Reach for your toes", "Hold each stretch for 20 seconds"]
        )
      ];
    }
  }

  /// AI Food Analysis (Returns JSON)
  Future<Map<String, dynamic>?> analyzeFoodImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final content = [
        Content.multi([
          TextPart("Identify food and calories. Reply ONLY in this JSON format: {\"name\": \"food name\", \"calories\": 123}"),
          DataPart('image/jpeg', bytes),
        ])
      ];

      final response = await _model.generateContent(content);
      
      if (response.text == null || response.text!.isEmpty) return null;

      final jsonString = response.text!.replaceAll('```json', '').replaceAll('```', '').trim();
      return jsonDecode(jsonString);
    } catch (e) {
      debugPrint("AI Image Analysis Error: $e");
      return null;
    }
  }
}

// --- CameraTab Implementation ---

class CameraTab extends StatefulWidget {
  final String uid; 
  final Function(int) onFoodDetected;

  const CameraTab({super.key, required this.onFoodDetected, required this.uid});

  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> {
  bool _scanning = false;
  String? _result;
  File? _capturedImage;
  final ImagePicker _picker = ImagePicker();
  final _aiService = GeminiAiService();
  final _dbService = DatabaseService();

  Future<void> _takePhotoAndScan() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (photo == null) return;

    setState(() {
      _scanning = true;
      _capturedImage = File(photo.path);
    });

    try {
      final foodData = await _aiService.analyzeFoodImage(_capturedImage!);

      if (foodData != null && mounted) {
        // Saves to permanent storage via the db service
        await _dbService.logMealWithSync(widget.uid, foodData, photo.path);

        setState(() {
          _scanning = false;
          _result = "${foodData['name']}: ${foodData['calories']} kcal saved!";
        });
        widget.onFoodDetected(foodData['calories']);
      } else {
        throw Exception("AI response was empty");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _result = "Error identifying food. Please try again.";
        });
      }
      debugPrint("Scan Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Food Scanner"),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 300, width: 300,
              decoration: BoxDecoration(
                color: Colors.black12, 
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[300]!)
              ),
              child: _scanning
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
                  : (_capturedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(19),
                          child: Image.file(_capturedImage!, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.camera_alt, size: 80, color: Colors.grey)),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _scanning ? null : _takePhotoAndScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              icon: const Icon(Icons.camera),
              label: const Text("Capture & Analyze", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10)),
                  child: Text(_result!, style: const TextStyle(fontSize: 16, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
                ),
              )
          ],
        ),
      ),
    );
  }
}