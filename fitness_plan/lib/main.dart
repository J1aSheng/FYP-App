import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart'; // Ensure this name matches your file
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      // The app now starts at the AuthWrapper
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
        
        // 1. Check if the user is even logged in
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!authSnapshot.hasData) {
          // No user found -> Go to Login
          return const LoginScreen();
        }

        // 2. User is logged in, now check if they have a Profile in Firestore
        return FutureBuilder<UserModel?>(
          future: DatabaseService().getUserProfile(authSnapshot.data!.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // 3. Conditional Routing
            if (profileSnapshot.hasData && profileSnapshot.data != null) {
              // PROFILE EXISTS: Go straight to the Dashboard
              return HomeScreen(user: profileSnapshot.data!);
            } else {
              // NO PROFILE: Go to the Profile Setup Screen
              return const ProfileScreen();
            }
          },
        );
      },
    );
  }
}