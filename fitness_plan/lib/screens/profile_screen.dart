import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/database_service.dart';
import 'home_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _ageController = TextEditingController();

  String gender = "Male";
  String goal = "Lose Weight";
  String level = "Beginner";
  String location = "Home";
  bool isSaving = false;

  void proceed() async {
    // 1. Validate inputs to prevent "Format Exception" errors
    final double? weight = double.tryParse(_weightController.text);
    final double? height = double.tryParse(_heightController.text);
    final int? age = int.tryParse(_ageController.text);

    if (_nameController.text.isEmpty || weight == null || height == null || age == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields correctly (numbers only for weight/height/age)")),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      
      // 2. Check Authentication
      if (currentUser == null) {
        throw Exception("No authenticated user found. Please log in again.");
      }

      // 3. Create non-hardcoded user object
      UserModel user = UserModel(
        uid: currentUser.uid,
        name: _nameController.text.trim(),
        gender: gender,
        weight: weight,
        height: height,
        age: age,
        goal: goal,
        level: level,
        location: location,
      );

      // 4. Save to Firestore (DatabaseService handles the logic)
      await DatabaseService().saveUserProfile(user);

      if (!mounted) return;

      // 5. Navigate to Dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
      );
    } catch (e) {
      // FIXED: Shows you exactly why it failed (Rules, Network, etc.)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Critical Error: $e")),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile Setup")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (isSaving) const LinearProgressIndicator(),
            const SizedBox(height: 20),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Full Name")),
            const SizedBox(height: 10),
            // UPDATED: Now passing the current state variable 'gender'
            _buildDropdown("Gender", ["Male", "Female"], gender, (v) => gender = v),
            const SizedBox(height: 10),
            TextField(controller: _heightController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Height (cm)")),
            const SizedBox(height: 10),
            TextField(controller: _weightController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Weight (kg)")),
            const SizedBox(height: 10),
            TextField(controller: _ageController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Age")),
            const SizedBox(height: 10),
            // UPDATED: Now passing the current state variable 'goal'
            _buildDropdown("Goal", ["Lose Weight", "Build Muscle", "Stay Healthy"], goal, (v) => goal = v),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: isSaving ? null : proceed,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55), backgroundColor: Colors.teal),
              child: const Text("Generate My AI Plan", style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  // FIXED: Added 'currentValue' parameter and replaced 'value' with 'initialValue'
  Widget _buildDropdown(String label, List<String> items, String currentValue, Function(String) onChanged) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: label),
      initialValue: currentValue, // FIXED: Resolved 'deprecated_member_use' warning
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
      onChanged: (v) => setState(() => onChanged(v!)),
    );
  }
}