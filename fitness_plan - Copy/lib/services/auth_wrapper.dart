import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/main_screen.dart'; 
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

        if (!authSnapshot.hasData) return const LoginScreen();

        return FutureBuilder<UserModel?>(
          future: DatabaseService().getUserProfile(authSnapshot.data!.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // PROFILE EXISTS: Go to Main Dashboard
            if (profileSnapshot.hasData && profileSnapshot.data != null) {
              return MainScreen(user: profileSnapshot.data!);
            } 
            // NO PROFILE: Go to Profile Setup
            else {
              return ProfileScreen(userName: authSnapshot.data?.displayName ?? "User"); 
            }
          },
        );
      },
    );
  }
}