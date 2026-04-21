import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart'; 
import 'package:path/path.dart' as p;            


// Logic & Screen Imports
import 'home_screen.dart';
import '../models/user_model.dart' hide Exercise;
import '../services/database_service.dart';
import '../services/gemini_ai_service.dart';

class MainScreen extends StatefulWidget {
  final UserModel user;
  const MainScreen({super.key, required this.user});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isScanning = false;

  final _ai = GeminiAiService();
  final _db = DatabaseService();
  final _picker = ImagePicker();

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(user: widget.user),
      const Center(child: Text("Calendar Screen")),
      const Center(child: Text("Insights Screen")),
      const Center(child: Text("Profile Screen")),
    ];
  }

  // ✅ Camera Logic moved here for the Center Button
  Future<void> _scanFood() async {
    final photo = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1024, imageQuality: 70);
    if (photo != null) {
      setState(() => _isScanning = true);
      try {
        final directory = await getApplicationDocumentsDirectory();
        final String fileName = "${DateTime.now().millisecondsSinceEpoch}${p.extension(photo.path)}";
        final String permanentPath = p.join(directory.path, fileName);
        
        final File savedImage = await File(photo.path).copy(permanentPath); 
        final foodData = await _ai.analyzeFoodImage(savedImage);
        
        if (foodData != null) {
          await _db.logMealWithSync(widget.user.uid, foodData, permanentPath);
          _showSnack("Meal recorded successfully! 🥗");
        }
      } catch (e) {
        debugPrint("Scan Error: $e");
        _showSnack("Identification failed. Try again.");
      } finally {
        if (mounted) setState(() => _isScanning = false);
      }
    }
  }

  // ✅ Fix: Notification at the top so the camera doesn't move
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2E7D32),
        duration: const Duration(seconds: 2),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 140, // Pushes to top
          left: 20,
          right: 20,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Body flows under the notched bar
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),

      // ✅ Centered Camera Button
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? null : _scanFood,
        backgroundColor: const Color(0xFF2E7D32),
        elevation: 4,
        shape: const CircleBorder(),
        child: _isScanning 
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Icon(Icons.camera_alt, color: Colors.white),
      ),
      
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // ✅ Notched Navigation Bar
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildNavItem(0, Icons.home_outlined, Icons.home, "Home"),
                  _buildNavItem(1, Icons.calendar_month_outlined, Icons.calendar_month, "Calendar"),
                ],
              ),
              Row(
                children: [
                  _buildNavItem(2, Icons.bar_chart_outlined, Icons.bar_chart, "Insights"),
                  _buildNavItem(3, Icons.person_outline, Icons.person, "Profile"),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    bool isActive = _currentIndex == index;
    return MaterialButton(
      minWidth: 40,
      onPressed: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isActive ? activeIcon : icon, color: isActive ? const Color(0xFF2E7D32) : Colors.black26),
          Text(label, style: TextStyle(fontSize: 10, color: isActive ? const Color(0xFF2E7D32) : Colors.black26)),
        ],
      ),
    );
  }
}