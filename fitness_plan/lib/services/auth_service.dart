import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Login function returns null on success, or an error message on failure
  Future<String?> login(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return null; // No error
    } on FirebaseAuthException catch (e) {
      return e.message ?? "An error occurred during login.";
    } catch (e) {
      return "An unexpected error occurred.";
    }
  }

  // Registration function returns null on success, or an error message on failure
  Future<String?> register(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return null; // No error
    } on FirebaseAuthException catch (e) {
      return e.message ?? "An error occurred during registration.";
    } catch (e) {
      return "An unexpected error occurred.";
    }
  }

  // Logout function
  Future<void> logout() async {
    await _auth.signOut();
  }
}