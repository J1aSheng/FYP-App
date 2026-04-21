import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/user_model.dart';
import 'database_service.dart'; // Added to allow CameraTab to save data

class GeminiAiService {
  final _model = GenerativeModel(
    model: 'gemini-3-flash-preview', // Updated to a stable version
    apiKey: 'AIzaSyB9TDChx2b_oQ4ntM_MGjOYGM27UGAjZCE',
    // Added safety settings to prevent "No Content" errors on food images
    safetySettings: [
      SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
      SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
    ],
  );

  Future<List<Exercise>> generateDailyWorkout(UserModel user) async {
    try {
      final prompt = "Create a ${user.level} workout for someone who wants to ${user.goal} at ${user.location}. "
          "Return ONLY a list of exercises in this format: Name|Reps|Duration. No extra text.";
      
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? "";

      return text.split('\n').where((line) => line.contains('|')).map((line) {
        final parts = line.split('|');
        return Exercise(name: parts[0].trim(), reps: parts[1].trim(), duration: parts[2].trim());
      }).toList();
    } catch (e) {
      return [Exercise(name: "Walk", reps: "1", duration: "30 mins")];
    }
  }

  /// Unified Food Analysis (Returns JSON)
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

      // Clean AI response from markdown characters
      final jsonString = response.text!.replaceAll('```json', '').replaceAll('```', '').trim();
      return jsonDecode(jsonString);
    } catch (e) {
      debugPrint("AI Image Analysis Error: $e");
      return null;
    }
  }
}

class CameraTab extends StatefulWidget {
  final String uid; // Added UID to save to the correct user account
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
      // Use the centralized logic from GeminiAiService
      final foodData = await _aiService.analyzeFoodImage(_capturedImage!);

      if (foodData != null && mounted) {
        // Save to Firestore immediately so it appears on the dashboard
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
      appBar: AppBar(title: const Text("AI Food Scanner")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 300, width: 300,
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15)),
              child: _scanning
                  ? const Center(child: CircularProgressIndicator())
                  : (_capturedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.file(_capturedImage!, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.camera_alt, size: 100, color: Colors.grey)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _scanning ? null : _takePhotoAndScan,
              icon: const Icon(Icons.camera),
              label: const Text("Capture Food"),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_result!, style: const TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.bold)),
              )
          ],
        ),
      ),
    );
  }
}