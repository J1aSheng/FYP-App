import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart'; //[cite: 6, 7]

class EditProfileScreen extends StatefulWidget {
  final UserModel user;
  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // 定义文本控制器[cite: 6, 7, 13]
  late TextEditingController _nameController;
  late TextEditingController _ageController;
  late TextEditingController _weightController;
  late TextEditingController _heightController;
  late TextEditingController _locationController;

  // 下拉菜单变量
  late String _selectedGender;
  late String _selectedGoal;
  late String _selectedLevel;

  bool _isSaving = false;
  final Color accentColor = const Color(0xFF2E7D32); // 森林绿[cite: 7, 8, 13]

  @override
  void initState() {
    super.initState();
    // 初始化控制器并填入当前数据
    _nameController = TextEditingController(text: widget.user.name);
    _ageController = TextEditingController(text: widget.user.age.toString());
    _weightController = TextEditingController(text: widget.user.weight.toString());
    _heightController = TextEditingController(text: widget.user.height.toString());
    _locationController = TextEditingController(text: widget.user.location);
    
    // 初始化下拉菜单选中的值[cite: 13]
    _selectedGender = widget.user.gender.toLowerCase(); 
    _selectedGoal = widget.user.goal;
    _selectedLevel = widget.user.level;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // ✅ 功能：更新 Firebase 数据[cite: 8, 10, 13]
  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({
        'name': _nameController.text.trim(),
        'age': int.tryParse(_ageController.text) ?? widget.user.age,
        'weight': double.tryParse(_weightController.text) ?? widget.user.weight,
        'height': double.tryParse(_heightController.text) ?? widget.user.height,
        'location': _locationController.text.trim(),
        'gender': _selectedGender, 
        'goal': _selectedGoal,
        'level': _selectedLevel,
      });

      if (mounted) {
        Navigator.pop(context); // 成功后返回[cite: 10, 13]
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile Updated! ✅"), behavior: SnackBarBehavior.floating)
        );
      }
    } catch (e) {
      debugPrint("Save Error: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFDFA),
      appBar: AppBar(
        title: const Text("EDIT PROFILE", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
        centerTitle: true,
        actions: [
          if (_isSaving) 
            const Center(child: Padding(padding: EdgeInsets.only(right: 15), child: CircularProgressIndicator(strokeWidth: 2)))
          else 
            IconButton(onPressed: _saveChanges, icon: const Icon(Icons.check, color: Color(0xFF2E7D32)))
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(25),
        children: [
          _buildInput(_nameController, "Full Name", Icons.person_outline),
          _buildInput(_ageController, "Age", Icons.cake_outlined, isNum: true),
          _buildInput(_locationController, "Location", Icons.location_on_outlined),
          
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildInput(_weightController, "Weight (kg)", Icons.monitor_weight_outlined, isNum: true)),
              const SizedBox(width: 15),
              Expanded(child: _buildInput(_heightController, "Height (cm)", Icons.height, isNum: true)),
            ],
          ),
          
          const Divider(height: 40),
          
          _buildDropdown("Gender", _selectedGender, ["male", "female"], (val) => setState(() => _selectedGender = val!)),
          
          // ✅ 修复核心：加入了 "Maintain Weight" 和 "Stay Healthy"[cite: 6, 13]
          _buildDropdown(
            "Fitness Goal", 
            _selectedGoal, 
            ["Lose Weight", "Maintain Weight", "Build Muscle", "Stay Healthy"], 
            (val) => setState(() => _selectedGoal = val!)
          ),
          
          _buildDropdown("Experience Level", _selectedLevel, ["Beginner", "Intermediate", "Pro"], (val) => setState(() => _selectedLevel = val!)),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon, {bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: controller,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20, color: accentColor),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFF0F0F0))),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        initialValue: value, 
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        ),
        items: items.map((e) => DropdownMenuItem(
          value: e, 
          child: Text(e) 
        )).toList(),
        onChanged: onChanged,
      ),
    );
  }
}