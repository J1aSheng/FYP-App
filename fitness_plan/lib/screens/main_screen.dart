import 'dart:io';
import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';
import 'insights_screen.dart';
import 'ai_coach_screen.dart';
import 'user_profile_screen.dart'; 
import 'workout_plan_screen.dart'; 

import '../models/user_model.dart'; 
import '../services/database_service.dart';
import '../services/groq_ai_service.dart';

class MainScreen extends StatefulWidget {
  final UserModel user;
  const MainScreen({super.key, required this.user});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isScanning = false;
  bool _isBubbleVisible = true; 
  bool _bubbleExpired = false; 
  Timer? _hideTimer; 

  final _ai = GroqAiService();
  final _db = DatabaseService();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isBubbleVisible = false;
          _bubbleExpired = true; 
        });
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel(); 
    super.dispose();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2E7D32),
        margin: const EdgeInsets.only(bottom: 120, left: 20, right: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  // 全局相机扫描功能
  Future<void> _scanFood() async {
    final photo = await _picker.pickImage(source: ImageSource.camera, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (photo == null) return;
    setState(() => _isScanning = true);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String permanentPath = p.join(directory.path, "${DateTime.now().millisecondsSinceEpoch}${p.extension(photo.path)}");
      final File savedImage = await File(photo.path).copy(permanentPath);
      final foodData = await _ai.analyzeFoodImage(savedImage);
      if (foodData != null) {
        await _db.logMealWithSync(widget.user.uid, foodData, permanentPath);
        _showSnack("Logged: ${foodData['food_name'] ?? 'meal'} recorded! 🥗");
      }
    } catch (e) {
      _showSnack("Scan Error: $e");
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.user.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32))));
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final updatedUser = UserModel.fromMap(userData, widget.user.uid);

        final List<Widget> screens = [
          HomeScreen(user: updatedUser),              
          WorkoutPlanScreen(user: updatedUser), 
          InsightsScreen(user: updatedUser),          
          ProfileScreen(user: updatedUser), 
          AiCoachScreen(user: updatedUser),           
        ];

        return Scaffold(
          backgroundColor: const Color(0xFFFBFDFA),
          extendBody: true,
          body: NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (notification.direction == ScrollDirection.reverse) {
                if (_isBubbleVisible) setState(() => _isBubbleVisible = false);
              } else if (notification.direction == ScrollDirection.forward) {
                if (!_isBubbleVisible && !_bubbleExpired) {
                  setState(() => _isBubbleVisible = true);
                }
              }
              return true;
            },
            child: Stack(
              children: [
                SafeArea(
                  bottom: false,
                  child: IndexedStack(index: _currentIndex, children: screens),
                ),
                
                // AI Coach 快捷入口气泡
                if (_currentIndex != 4 && _isBubbleVisible) 
                  Positioned(
                    bottom: 125, 
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () {
                        _hideTimer?.cancel();
                        setState(() {
                          _currentIndex = 4;
                          _isBubbleVisible = false;
                          _bubbleExpired = true;
                        });
                      },
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                                border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.1)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome, color: Color(0xFF2E7D32), size: 14),
                                  SizedBox(width: 8),
                                  Text("Ask AI Coach", style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ),
                            CustomPaint(
                              size: const Size(12, 6), 
                              painter: TrianglePainter(color: const Color(0xFFE8F5E9))
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 相机扫描浮动按钮
                if (_currentIndex != 4)
                  Positioned(
                    bottom: 115,
                    right: 25,
                    child: FloatingActionButton(
                      heroTag: "main_fab", 
                      onPressed: _isScanning ? null : _scanFood,
                      backgroundColor: const Color(0xFF2E7D32),
                      elevation: 6,
                      shape: const CircleBorder(),
                      child: _isScanning 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                        : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 26),
                    ),
                  ),
              ],
            ),
          ),
          
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 30), 
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20)],
                border: Border.all(color: const Color(0xFFF0F0F0)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, "HOME"),
                  _buildNavItem(1, Icons.fitness_center_outlined, Icons.fitness_center_rounded, "PLAN"),
                  _buildCircularAiIcon(4),
                  _buildNavItem(2, Icons.bar_chart_outlined, Icons.bar_chart_rounded, "INSIGHTS"),
                  _buildNavItem(3, Icons.person_outline_rounded, Icons.person_rounded, "PROFILE"),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem(int index, IconData i, IconData ai, String l) {
    bool active = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? ai : i, color: active ? const Color(0xFF2E7D32) : const Color(0xFF747972), size: 26),
            const SizedBox(height: 4),
            Text(l, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: active ? const Color(0xFF2E7D32) : const Color(0xFF747972))),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularAiIcon(int index) {
    bool active = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2E7D32) : const Color(0xFFF0F4EF),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.auto_awesome_rounded, color: active ? Colors.white : const Color(0xFF2E7D32), size: 28),
      ),
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}