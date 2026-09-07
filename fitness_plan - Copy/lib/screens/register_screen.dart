import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  
  final AuthService _auth = AuthService();
  bool isLoading = false;

  void register() async {
    String name = nameController.text.trim();
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in Name, Email, and Password"), backgroundColor: Color(0xFF2E7D32))
      );
      return;
    }

    setState(() => isLoading = true);
    
    // 创建基础账号[cite: 3]
    final errorMessage = await _auth.register(
      email, 
      password, 
      name,
      extraData: {} // 物理数据移至 ProfileScreen 处理[cite: 3]
    );
    
    if (!mounted) return; 
    setState(() => isLoading = false);

    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.redAccent)
      );
    } else {
      // 注册成功，跳转到图片样式的 Profile 页面[cite: 3]
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (_) => ProfileScreen(userName: name))
      ); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFDFA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                child: const Icon(Icons.person_add_rounded, color: Color(0xFF2E7D32), size: 40),
              ),
              const SizedBox(height: 30),
              const Text("Create Account", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF191C19))),
              const SizedBox(height: 8),
              const Text("Step 1: Set up your login credentials", style: TextStyle(color: Color(0xFF747972), fontSize: 14)),
              const SizedBox(height: 40),
              
              _buildCleanField("NAME", nameController, icon: Icons.person_outline_rounded),
              const SizedBox(height: 20),
              _buildCleanField("EMAIL", emailController, icon: Icons.email_outlined),
              const SizedBox(height: 20),
              _buildCleanField("PASSWORD", passwordController, icon: Icons.lock_outline_rounded, isPass: true),
              
              const SizedBox(height: 50),
              ElevatedButton(
                onPressed: isLoading ? null : register, 
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 65),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: isLoading 
                  ? const SizedBox(height: 25, width: 25, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : const Text("CONTINUE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCleanField(String label, TextEditingController controller, {required IconData icon, bool isPass = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF747972), letterSpacing: 1)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: TextField(
            controller: controller,
            obscureText: isPass,
            style: const TextStyle(color: Color(0xFF191C19), fontWeight: FontWeight.w600, fontSize: 15),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: const Color(0xFF2E7D32), size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        ),
      ],
    );
  }
}