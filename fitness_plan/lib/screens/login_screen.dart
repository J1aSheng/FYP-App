import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'register_screen.dart'; 

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final AuthService _auth = AuthService();
  bool isLoading = false;

  void login() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      showSnackBar("Please fill all fields");
      return;
    }

    setState(() => isLoading = true);

    final errorMessage = await _auth.login(email, password);

    if (mounted) setState(() => isLoading = false);

    if (errorMessage != null) {
      showSnackBar(errorMessage);
    }
    // No "Navigator.push" needed here. AuthWrapper will handle it automatically.
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("AI Fitness Planner", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.teal)),
            const SizedBox(height: 30),
            TextField(controller: emailController, decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder())),
            const SizedBox(height: 15),
            TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder())),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: isLoading ? null : login, 
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: isLoading 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text("Login"),
            ),
            const SizedBox(height: 15),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
              child: const Text("Don't have an account? Register here"),
            ),
          ],
        ),
      ),
    );
  }
}