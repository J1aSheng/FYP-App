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
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      showSnackBar("Fill all fields");
      return;
    }

    setState(() => isLoading = true);

    // After this call, AuthWrapper will see the change and navigate for you
    final error = await _auth.login(
        emailController.text.trim(), passwordController.text.trim());

    if (mounted) {
      setState(() => isLoading = false);
      if (error != null) {
        showSnackBar(error);
      }
    }
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
            const Text("Login", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(controller: emailController, decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder())),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : login, 
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: isLoading 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                : const Text("Login"),
            ),
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