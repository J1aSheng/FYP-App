import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
// ✅ FIXED: Using only the external wrapper to avoid conflicts
import 'services/auth_wrapper.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); 
  runApp(const FitnessPlanApp());
}

class FitnessPlanApp extends StatelessWidget {
  const FitnessPlanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Fitness Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAF9),
      ),
      home: const AuthWrapper(), 
    );
  }
}