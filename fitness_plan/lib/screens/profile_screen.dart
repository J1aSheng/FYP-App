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
  final _weightController = TextEditingController(text: "65");
  final _heightController = TextEditingController(text: "175");
  final _ageController = TextEditingController(text: "21");

  String gender = "Male";
  String goal = "Lose Weight";
  String level = "Beginner";
  String location = "Home";
  double activityValue = 0.7; // For the activity slider
  bool isSaving = false;

  void proceed() async {
    final double? weight = double.tryParse(_weightController.text);
    final double? height = double.tryParse(_heightController.text);
    final int? age = int.tryParse(_ageController.text);

    if (weight == null || height == null || age == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields correctly")));
      return;
    }

    setState(() => isSaving = true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception("No authenticated user found.");

      UserModel user = UserModel(
        uid: currentUser.uid,
        name: _nameController.text.isEmpty ? "User" : _nameController.text.trim(),
        gender: gender,
        weight: weight,
        height: height,
        age: age,
        goal: goal,
        level: level,
        location: location,
      );

      await DatabaseService().saveUserProfile(user);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(user: user)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Critical Error: $e")));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              if (isSaving) const LinearProgressIndicator(),
              const Text("Let's Setup\nYour Profile", 
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),

              // Gender Toggle
              Row(
                children: [
                  Expanded(child: _buildToggleBtn("Male", gender == "Male", () => setState(() => gender = "Male"))),
                  const SizedBox(width: 15),
                  Expanded(child: _buildToggleBtn("Female", gender == "Female", () => setState(() => gender = "Female"))),
                ],
              ),
              const SizedBox(height: 25),

              // Weight/Height Metric Cards
              Row(
                children: [
                  Expanded(child: _buildMetricCard("Weight", _weightController, "kg")),
                  const SizedBox(width: 15),
                  Expanded(child: _buildMetricCard("Height", _heightController, "cm")),
                ],
              ),
              const SizedBox(height: 30),

              // Activity Slider
              const Align(alignment: Alignment.centerLeft, child: Text("Activity Level", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              Slider(
                value: activityValue,
                activeColor: const Color(0xFFF4D160),
                onChanged: (v) => setState(() => activityValue = v),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text("Sedentary", style: TextStyle(color: Colors.grey)), Text("Active", style: TextStyle(color: Colors.grey))],
              ),
              const SizedBox(height: 30),

              // Goal Toggle
              const Align(alignment: Alignment.centerLeft, child: Text("Goal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildToggleBtn("Lose Weight", goal == "Lose Weight", () => setState(() => goal = "Lose Weight"))),
                  const SizedBox(width: 15),
                  Expanded(child: _buildToggleBtn("Build Muscle", goal == "Build Muscle", () => setState(() => goal = "Build Muscle"))),
                ],
              ),

              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: isSaving ? null : proceed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE57373),
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("Generate AI Plan", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleBtn(String label, bool active, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF43855B) : Colors.white,
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildMetricCard(String label, TextEditingController ctrl, String unit) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          TextField(
            controller: ctrl,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            decoration: InputDecoration(suffixText: unit, border: InputBorder.none, isDense: true),
          ),
        ],
      ),
    );
  }
}