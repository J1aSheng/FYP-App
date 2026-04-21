import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart'; // Ensure correct path

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameController = TextEditingController(); 
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final dobController = TextEditingController(); 
  final AuthService _auth = AuthService();
  bool isLoading = false;

  void register() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      showSnackBar("Please fill all fields");
      return;
    }

    setState(() => isLoading = true);
    
    // The async gap starts here
    final errorMessage = await _auth.register(email, password);
    
    // ✅ FIX: Check if the widget is still in the tree before using context
    if (!mounted) return; 

    setState(() => isLoading = false);

    if (errorMessage != null) {
      showSnackBar(errorMessage);
    } else {
      // Navigate to profile setup after successful registration
      // Navigator now safely uses context because of the 'mounted' check above
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (_) => const ProfileScreen())
      ); 
    }
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              const SizedBox(height: 50),
              const Text("Create New\nAccount", 
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
              const SizedBox(height: 10),
              const Text("Already Registered? Log in here.", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),
              
              _buildStyledField("NAME", nameController),
              _buildStyledField("EMAIL", emailController),
              _buildStyledField("PASSWORD", passwordController, isPass: true),
              _buildStyledField("DATE OF BIRTH", dobController),
              
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: isLoading ? null : register, 
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF4D160),
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 0,
                ),
                child: isLoading 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text("Sign up", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              const SizedBox(height: 20),
              const Text("Already Registered? Log in here", style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStyledField(String label, TextEditingController controller, {bool isPass = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: isPass,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[200],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        ],
      ),
    );
  }
}