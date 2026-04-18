import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final AuthService _auth = AuthService();
  bool isLoading = false;

  void register() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();
    String confirm = confirmPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty || confirm.isEmpty) {
      showSnackBar("Please fill all fields");
      return;
    }

    if (password != confirm) {
      showSnackBar("Passwords do not match");
      return;
    }

    setState(() => isLoading = true);
    final errorMessage = await _auth.register(email, password);
    if (mounted) setState(() => isLoading = false);

    if (errorMessage != null) {
      showSnackBar(errorMessage);
    }
    // AuthWrapper will detect the new user and show the Profile Screen automatically.
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Account")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder())),
              const SizedBox(height: 15),
              TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder())),
              const SizedBox(height: 15),
              TextField(controller: confirmPasswordController, obscureText: true, decoration: const InputDecoration(labelText: "Confirm Password", border: OutlineInputBorder())),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: isLoading ? null : register, 
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: isLoading 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}