import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
// FIXED: Changed from profile_setup_screen.dart to profile_screen.dart
import '../screens/profile_screen.dart'; 
import 'database_service.dart';
import '../models/user_model.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 1. If no user is logged into Firebase Auth
        if (!authSnapshot.hasData) {
          return const LoginScreen();
        }

        // 2. User is logged in, now check Firestore for their profile
        return FutureBuilder<UserModel?>(
          future: DatabaseService().getUserProfile(authSnapshot.data!.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // 3. Conditional Routing Logic
            if (profileSnapshot.hasData && profileSnapshot.data != null) {
              // User has data saved -> Dashboard
              return HomeScreen(user: profileSnapshot.data!);
            } else {
              // User is new/no data -> Profile Setup
              return const ProfileScreen(); 
            }
          },
        );
      },
    );
  }
}