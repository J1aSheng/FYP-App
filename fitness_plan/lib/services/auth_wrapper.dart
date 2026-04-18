import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
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

        // 1. If no user is logged in, show Login Screen
        if (!authSnapshot.hasData) {
          return const LoginScreen();
        }

        // 2. User is logged in, check Firestore for their profile data
        return FutureBuilder<UserModel?>(
          future: DatabaseService().getUserProfile(authSnapshot.data!.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // 3. Routing Logic: If profile exists, go to Home. Otherwise, setup Profile.
            if (profileSnapshot.hasData && profileSnapshot.data != null) {
              return HomeScreen(user: profileSnapshot.data!);
            } else {
              return const ProfileScreen(); 
            }
          },
        );
      },
    );
  }
}