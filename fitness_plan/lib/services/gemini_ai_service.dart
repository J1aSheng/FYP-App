import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart'; // REQUIRED: For StatefulWidget, Text, Colors, etc.
import 'package:image_picker/image_picker.dart'; // REQUIRED: For ImagePicker, XFile, etc.
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/user_model.dart';

/// 1. The Service Class (This is what HomeScreen is trying to use)
class GeminiAiService {
  final _model = GenerativeModel(
    model: 'gemini-3-flash-preview', // Use the stable flash model
    apiKey: 'AIzaSyB9TDChx2b_oQ4ntM_MGjOYGM27UGAjZCE', // Your provided key
  );

  /// Generates a workout list based on the user's profile
  Future<List<Exercise>> generateDailyWorkout(UserModel user) async {
    try {
      final prompt = "Create a ${user.level} workout for someone who wants to ${user.goal} at ${user.location}. "
          "Return ONLY a list of exercises in this format: Name|Reps|Duration. No extra text.";
      
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? "";

      // Simple parsing logic (assuming AI returns "Pushups|15 reps|5 mins")
      return text.split('\n').where((line) => line.contains('|')).map((line) {
        final parts = line.split('|');
        return Exercise(name: parts[0], reps: parts[1], duration: parts[2]);
      }).toList();
    } catch (e) {
      // Fallback if AI fails
      return [Exercise(name: "Walk", reps: "1", duration: "30 mins")];
    }
  }

  /// Analyzes a food photo and returns Name and Calories
  Future<Map<String, dynamic>?> analyzeFoodImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final content = [
        Content.multi([
          TextPart("Identify food and total calories. Reply ONLY in this JSON format: {\"name\": \"food name\", \"calories\": 123}"),
          DataPart('image/jpeg', bytes),
        ])
      ];

      final response = await _model.generateContent(content);
      final jsonString = response.text?.replaceAll('```json', '').replaceAll('```', '').trim();
      
      if (jsonString != null) {
        return jsonDecode(jsonString);
      }
    } catch (e) {
      debugPrint("AI Image Analysis Error: $e");
    }
    return null;
  }
}

/// 2. The CameraTab Widget (Fixing your syntax errors)
class CameraTab extends StatefulWidget {
  final Function(int) onFoodDetected;

  const CameraTab({super.key, required this.onFoodDetected});

  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> {
  bool _scanning = false;
  String? _result;
  File? _capturedImage;
  final ImagePicker _picker = ImagePicker();
  
  final _model = GenerativeModel(
    model: 'gemini-3-flash-preview',
    apiKey: 'AIzaSyB9TDChx2b_oQ4ntM_MGjOYGM27UGAjZCE',
  );

  Future<void> _takePhotoAndScan() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (photo == null) return;

    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      _scanning = true;
      _capturedImage = File(photo.path);
    });

    try {
      final bytes = await photo.readAsBytes();
      final content = [
        Content.multi([
          TextPart("Identify food and total calories. Reply ONLY in this format: Food: [name], Calories: [number] kcal"),
          DataPart('image/jpeg', bytes),
        ])
      ];

      final response = await _model.generateContent(content);
      final responseText = response.text ?? "Unknown";

      final regExp = RegExp(r'(\d+)');
      final match = regExp.firstMatch(responseText);
      int detectedCalories = match != null ? int.parse(match.group(0)!) : 0;

      if (mounted) {
        setState(() {
          _scanning = false;
          _result = responseText;
        });
        widget.onFoodDetected(detectedCalories);
      }
    } catch (e) {
      if (mounted) setState(() => _scanning = false);
      debugPrint("Error: $e");
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
              height: 300,
              width: 300,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(15),
              ),
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
              label: const Text("Capture Real Food"),
            ),
            if (_result != null)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(top: 20, left: 20, right: 20),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_result!, style: const TextStyle(fontSize: 16, color: Colors.green)),
              )
          ],
        ),
      ),
    );
  }
}