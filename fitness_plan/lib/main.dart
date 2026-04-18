import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/auth_wrapper.dart'; // This imports your logic from the other file

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase before the app starts
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      // The app starts at the AuthWrapper, which handles all routing logic
      home: const AuthWrapper(), 
    );
  }
}