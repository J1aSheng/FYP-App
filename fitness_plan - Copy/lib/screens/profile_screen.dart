import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart'; //[cite: 6, 12]
import '../services/database_service.dart'; //[cite: 12]
import 'main_screen.dart'; //[cite: 12]

class ProfileScreen extends StatefulWidget {
  final String userName;
  const ProfileScreen({super.key, required this.userName});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // --- 控制器：获取年龄、体重、身高 ---[cite: 12]
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();

  String gender = "Male";
  String goal = "Stay Healthy"; // 默认设为 Stay Healthy 以对齐模型[cite: 6, 12]
  String level = "Beginner";
  String location = "Home";
  
  double activityValue = 3.0; 
  bool isSaving = false;

  // 根据滑动条值动态计算颜色[cite: 12]
  Color _getActivityColor() {
    if (activityValue <= 3) {
      double t = (activityValue - 1) / (3 - 1);
      return Color.lerp(const Color(0xFF747972), const Color(0xFF2E7D32), t) ?? const Color(0xFF747972);
    } else {
      double t = (activityValue - 3) / (5 - 3);
      return Color.lerp(const Color(0xFF2E7D32), Colors.green, t) ?? const Color(0xFF2E7D32);
    }
  }

  // 保存数据并跳转[cite: 12]
  void proceed() async {
    final int? age = int.tryParse(_ageController.text);
    final double? weight = double.tryParse(_weightController.text);
    final double? height = double.tryParse(_heightController.text);

    if (age == null || weight == null || height == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter valid Age, Weight and Height"))
      );
      return;
    }

    setState(() => isSaving = true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception("No authenticated user found.");

      // 使用提供的 UserModel 结构进行实例化[cite: 6, 12]
      UserModel user = UserModel(
        uid: currentUser.uid,
        name: widget.userName, 
        gender: gender,
        weight: weight,
        height: height,
        age: age, 
        goal: goal, 
        level: level,
        location: location,
        currentStreak: 0,
      );

      await DatabaseService().saveUserProfile(user); //[cite: 12]
      if (!mounted) return;

      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (_) => MainScreen(user: user))
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color dynamicColor = _getActivityColor();

    return Scaffold(
      backgroundColor: const Color(0xFFFBFDFA), //[cite: 12]
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
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            children: [
              if (isSaving) LinearProgressIndicator(color: dynamicColor, backgroundColor: const Color(0xFFF0F4EF)),
              const SizedBox(height: 10),
              
              const Text("Create Your Profile", textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF191C19), letterSpacing: 0.5)),
              const SizedBox(height: 8),
              const Text("We customize your plan based on these details", textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF747972), fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 35),
              
              // 性别选择 (两列)[cite: 12]
              Row(
                children: [
                  Expanded(child: _buildToggleBtn("Male", gender == "Male", () => setState(() => gender = "Male"))),
                  const SizedBox(width: 15),
                  Expanded(child: _buildToggleBtn("Female", gender == "Female", () => setState(() => gender = "Female"))),
                ],
              ),
              const SizedBox(height: 20),
              
              // 身体指标卡片[cite: 12]
              Row(
                children: [
                  Expanded(child: _buildMetricCard("Age", _ageController, "yrs")),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricCard("Weight", _weightController, "kg")),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricCard("Height", _heightController, "cm")),
                ],
              ),
              const SizedBox(height: 25),
              
              // 活动量滑块[cite: 12]
              _buildCleanSection(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Activity Level", style: TextStyle(color: Color(0xFF191C19), fontWeight: FontWeight.w800, fontSize: 16)),
                        Text("Level ${activityValue.toInt()}", style: TextStyle(color: dynamicColor, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    Slider(
                      value: activityValue, min: 1, max: 5, divisions: 4,
                      activeColor: dynamicColor, inactiveColor: const Color(0xFFF0F4EF),
                      onChanged: (v) => setState(() => activityValue = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              const Align(alignment: Alignment.centerLeft,
                child: Padding(padding: EdgeInsets.only(left: 5, bottom: 12),
                  child: Text("Your Fitness Goal", style: TextStyle(color: Color(0xFF191C19), fontWeight: FontWeight.w800, fontSize: 16)))),
              
              // ✅ 核心修改：两列布局展示 4 个目标按钮[cite: 6, 12]
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildToggleBtn("Lose Weight", goal == "Lose Weight", () => setState(() => goal = "Lose Weight"))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildToggleBtn("Maintain Weight", goal == "Maintain Weight", () => setState(() => goal = "Maintain Weight"))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildToggleBtn("Build Muscle", goal == "Build Muscle", () => setState(() => goal = "Build Muscle"))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildToggleBtn("Stay Healthy", goal == "Stay Healthy", () => setState(() => goal = "Stay Healthy"))),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 45),
              ElevatedButton(
                onPressed: isSaving ? null : proceed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 65),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text("GENERATE AI PLAN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI 子组件 ---[cite: 12]
  Widget _buildCleanSection({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: child,
    );
  }

  Widget _buildToggleBtn(String label, bool active, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2E7D32) : Colors.white,
          border: Border.all(color: active ? const Color(0xFF2E7D32) : const Color(0xFFF0F0F0)),
          borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.center,
        child: Text(label, textAlign: TextAlign.center, 
          style: TextStyle(fontSize: 13, color: active ? Colors.white : const Color(0xFF747972), fontWeight: active ? FontWeight.w900 : FontWeight.w600)),
      ),
    );
  }

  Widget _buildMetricCard(String label, TextEditingController ctrl, String unit) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF0F0F0))),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF747972), fontSize: 10)),
          const SizedBox(height: 5),
          TextField(
            controller: ctrl, textAlign: TextAlign.center, keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF191C19)),
            decoration: InputDecoration(hintText: "0", suffixText: unit, suffixStyle: const TextStyle(fontSize: 10), border: InputBorder.none, isDense: true),
          ),
        ],
      ),
    );
  }
}