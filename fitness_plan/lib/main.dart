import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Ensure these paths match your project structure
import 'screens/login_screen.dart';
import 'screens/main_screen.dart'; // Import the new navigation wrapper
import 'screens/profile_screen.dart'; 
import 'services/database_service.dart';
import 'models/user_model.dart';

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
        // Using the Green theme color from your design
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAF9),
      ),
      home: const AuthWrapper(), 
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // Listen to the Firebase Authentication state
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        
        // 1. Loading State
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2. Not Logged In
        if (!authSnapshot.hasData) {
          return const LoginScreen(); //
        }

        // 3. Logged In: Check for Firestore Profile
        return FutureBuilder<UserModel?>(
          future: DatabaseService().getUserProfile(authSnapshot.data!.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // PROFILE EXISTS: Go to MainScreen (which has the Bottom Nav Bar)
            if (profileSnapshot.hasData && profileSnapshot.data != null) {
              return MainScreen(user: profileSnapshot.data!); //
            } 
            
            // NO PROFILE: Go to Profile Setup to "Generate AI Plan"
            else {
              return const ProfileScreen(); //
            }
          },
        );
      },
    );
  }
}