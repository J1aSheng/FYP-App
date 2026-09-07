import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'register_screen.dart'; 

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // --- ✅ 邏輯完全保留自 Source 5 ---
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

    final error = await _auth.login(
        emailController.text.trim(), passwordController.text.trim());

    if (mounted) {
      setState(() => isLoading = false);
      if (error != null) {
        showSnackBar(error);
      }
    }
  }

  // ✅ 忘記密碼邏輯 //[cite: 5]
  void forgotPassword() async {
    String email = emailController.text.trim();
    if (email.isEmpty) {
      showSnackBar("Please enter your email address first");
      return;
    }

    setState(() => isLoading = true);
    // 现在 AuthService 中已定义 sendPasswordReset //[cite: 6]
    final error = await _auth.sendPasswordReset(email); 
    
    if (mounted) {
      setState(() => isLoading = false);
      if (error == null) {
        showSnackBar("Password reset link sent to your email");
      } else {
        showSnackBar(error);
      }
    }
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ 修复：将引用标记移入注释，解决 image_62b787.png 中的编译错误[cite: 7]
      backgroundColor: const Color(0xFFFBFDFA), //[cite: 5]
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F5E9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt_rounded, color: Color(0xFF2E7D32), size: 50),
                ),
                const SizedBox(height: 30),
                
                const Text(
                  "Welcome Back", 
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF191C19), letterSpacing: 0.5)
                ),
                const SizedBox(height: 8),
                const Text(
                  "Log in to continue your fitness journey", 
                  style: TextStyle(color: Color(0xFF747972), fontSize: 14, fontWeight: FontWeight.w500)
                ),
                const SizedBox(height: 50),
                
                _buildCleanTextField(
                  controller: emailController,
                  label: "Email Address",
                  icon: Icons.email_outlined,
                ),
                const SizedBox(height: 20),
                _buildCleanTextField(
                  controller: passwordController,
                  label: "Password",
                  icon: Icons.lock_outline_rounded,
                  isPass: true,
                ),

                // 忘記密碼按鈕 //[cite: 5]
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: isLoading ? null : forgotPassword,
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                ElevatedButton(
                  onPressed: isLoading ? null : login, 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32), 
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 65),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  child: isLoading 
                    ? const SizedBox(height: 25, width: 25, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)) 
                    : const Text(
                        "LOG IN", 
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)
                      ),
                ),
                
                const SizedBox(height: 30),
                
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: RichText(
                    text: const TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(color: Color(0xFF747972), fontWeight: FontWeight.w500),
                      children: [
                        TextSpan(
                          text: "Sign Up",
                          style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ 清新風格輸入框組件 //[cite: 5]
  Widget _buildCleanTextField({
    required TextEditingController controller, 
    required String label, 
    required IconData icon, 
    bool isPass = false
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [
          BoxShadow(
            // ✅ 已修复：使用 .withValues(alpha: ...) 消除过时警告并保留原有数值
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: isPass,
        style: const TextStyle(color: Color(0xFF191C19), fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF747972), fontSize: 13, fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, color: const Color(0xFF2E7D32), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        ),
      ),
    );
  }
}