import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ✅ Models and Services
import '../models/user_model.dart' hide Exercise; 
import '../models/exercise_model.dart'; 
import '../services/gemini_ai_service.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ai = GeminiAiService();
  
  List<Exercise> todayWorkouts = [];
  Set<String> completedWorkouts = {}; 
  bool isLoadingWorkout = true;
  late double dailyTarget;

  // Timer Variables
  Timer? _timer;
  int _secondsRemaining = 0;
  bool _isTimerActive = false;

  @override
  void initState() {
    super.initState();
    dailyTarget = _calculateBMR();
    _fetchAiWorkout();
  }

  @override
  void dispose() {
    _timer?.cancel(); 
    super.dispose();
  }

  // --- CORE LOGIC ---

  double _calculateBMR() {
    double bmr = widget.user.gender.toLowerCase() == "male" 
      ? 10 * widget.user.weight + 6.25 * widget.user.height - 5 * widget.user.age + 5
      : 10 * widget.user.weight + 6.25 * widget.user.height - 5 * widget.user.age - 161;
    
    if (widget.user.goal.contains("Lose")) {
      return bmr - 500;
    }
    if (widget.user.goal.contains("Muscle")) {
      return bmr + 300;
    }
    return bmr;
  }

  int _parseDuration(String duration) {
    final parts = duration.toLowerCase().split(' ');
    if (parts.length < 2) {
      return 60;
    }
    int value = int.tryParse(parts[0]) ?? 1;
    if (parts[1].contains('min')) {
      return value * 60;
    }
    return value;
  }

  String _formatTime(int seconds) {
    int mins = seconds ~/ 60;
    int secs = seconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  Future<void> _fetchAiWorkout() async {
    final list = await _ai.generateDailyWorkout(widget.user);
    if (mounted) {
      setState(() { todayWorkouts = list; isLoadingWorkout = false; });
    }
  }

  Future<void> _incrementWater() async {
    String todayId = DateTime.now().toString().split(' ')[0];
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(widget.user.uid)
          .collection('daily_logs').doc(todayId)
          .set({
            'water_glasses': FieldValue.increment(1),
            'last_updated': Timestamp.now(),
          }, SetOptions(merge: true));
      _showSnack("Water glass added! 💧");
    } catch (e) {
      debugPrint("Water Update Error: $e");
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- UI BUILDER ---

  @override
  Widget build(BuildContext context) {
    String todayId = DateTime.now().toString().split(' ')[0];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users').doc(widget.user.uid)
              .collection('daily_logs').doc(todayId).snapshots(),
          builder: (context, snapshot) {
            int totalEaten = 0;
            int burned = 0;
            int waterGlasses = 0; 
            List<dynamic> finishedActivities = [];
            
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>;
              totalEaten = data['total_calories'] ?? 0;
              burned = data['burned_calories'] ?? 0;
              waterGlasses = data['water_glasses'] ?? 0; 
              finishedActivities = data['activities'] ?? [];
            }

            int netCalories = totalEaten - burned;
            int remaining = (dailyTarget - netCalories).toInt().clamp(0, dailyTarget.toInt());

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopHeader(),
                  const SizedBox(height: 25),
                  _buildCaloriesPlanCard(totalEaten, burned, remaining), 
                  const SizedBox(height: 30),
                  _buildSectionHeader("Calorie History", "This Week"),
                  const SizedBox(height: 15),
                  _buildDynamicWeeklyStrip(), 
                  const SizedBox(height: 30),
                  
                  _buildWaterIntakeCard(waterGlasses), 
                  const SizedBox(height: 30),

                  if (finishedActivities.isNotEmpty) ...[
                    _buildSectionHeader("Recent Activities", "Today"),
                    const SizedBox(height: 10),
                    ...finishedActivities.reversed.map((name) => _buildRecentActivityItem(name)),
                    const SizedBox(height: 30),
                  ],

                  _buildSectionHeader("AI Activity Suggestions", "SMART"),
                  _buildAiWorkoutList(),
                  const SizedBox(height: 120),
                ],
              ),
            );
          }
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 25, backgroundColor: const Color(0xFFE8F5E9),
          child: Text(widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : "U", 
            style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text("Stay on track! 🍏", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        const Icon(Icons.search, size: 28),
        const SizedBox(width: 15),
        const Icon(Icons.notifications_none_outlined, size: 28),
      ],
    );
  }

  Widget _buildCaloriesPlanCard(int eaten, int burned, int remaining) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat("Eaten", "$eaten"),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 100, width: 100,
                child: CircularProgressIndicator(
                  value: (eaten - burned) / dailyTarget,
                  strokeWidth: 10, backgroundColor: Colors.grey[100],
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC6FF00)),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("$remaining", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const Text("kcal", style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              )
            ],
          ),
          _buildStat("Burned", "$burned"), 
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildDynamicWeeklyStrip() {
    DateTime now = DateTime.now();
    DateTime monday = now.subtract(Duration(days: now.weekday - 1));

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(widget.user.uid)
          .collection('daily_logs').where('last_updated', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(monday.year, monday.month, monday.day)))
          .get(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        List<String> dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (index) {
            DateTime dayDate = monday.add(Duration(days: index));
            var dailyDoc = docs.where((doc) {
              DateTime d = (doc['last_updated'] as Timestamp).toDate();
              return d.day == dayDate.day && d.month == dayDate.month && d.year == dayDate.year;
            });

            bool hasData = dailyDoc.isNotEmpty;
            bool exceeded = hasData ? (dailyDoc.first['total_calories'] as num) > dailyTarget : false;

            return Column(
              children: [
                Text(dayLabels[index], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !hasData ? Colors.grey[100] : (exceeded ? Colors.red[50] : Colors.green[50]),
                  ),
                  child: Icon(
                    !hasData ? Icons.remove : (exceeded ? Icons.close : Icons.check),
                    size: 18, color: !hasData ? Colors.grey : (exceeded ? Colors.red : Colors.green),
                  ),
                )
              ],
            );
          }),
        );
      },
    );
  }

  Widget _buildWaterIntakeCard(int glasses) {
    int visibleFilledCount = glasses.clamp(0, 6);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(30)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.water_drop, color: Color(0xFF42A5F5), size: 24),
              ),
              const SizedBox(width: 15),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Water Intake", style: TextStyle(color: Color(0xFF2E7D32), fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("Stay hydrated—drink more water!", style: TextStyle(color: Color(0xFF2E7D32), fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              if (index < 6) {
                return _buildGlassContainer(isFilled: index < visibleFilledCount);
              } else {
                return _buildAddWaterButton();
              }
            }),
          ),
          const SizedBox(height: 20),
          // ✅ FIX 1: Removed 'const' keyword to allow dynamic variable $glasses
          RichText(text: TextSpan(
            style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 14),
            children: [
              const TextSpan(text: "Today you drink only "),
              TextSpan(text: "$glasses ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFE65100))),
              const TextSpan(text: "glass of water."),
            ]
          )),
        ],
      ),
    );
  }

  Widget _buildGlassContainer({required bool isFilled}) {
    return Container(
      height: 45, width: 35,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border.all(color: Colors.black12),
      ),
      alignment: Alignment.bottomCenter,
      child: isFilled 
        ? Container(
            height: 30, width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF42A5F5),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
            ),
          )
        : null,
    );
  }

  Widget _buildAddWaterButton() {
    return GestureDetector(
      onTap: _incrementWater,
      child: Container(
        height: 45, width: 35,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          border: Border.all(color: Colors.black12),
        ),
        child: const Center(
          child: CircleAvatar(
            radius: 12, backgroundColor: Colors.white,
            child: Icon(Icons.add, color: Color(0xFFE65100), size: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivityItem(String name) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
          const SizedBox(width: 15),
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          const Text("Completed", style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildAiWorkoutList() {
    if (isLoadingWorkout) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    }
    return Column(
      children: todayWorkouts.map((e) {
        bool done = completedWorkouts.contains(e.name);
        return GestureDetector(
          onTap: () => _showWorkoutDialog(e),
          child: Container(
            margin: const EdgeInsets.only(top: 15),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
              border: done ? Border.all(color: const Color(0xFF2E7D32)) : null,
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF0F4C3), borderRadius: BorderRadius.circular(15)),
                child: Icon(e.name.contains("Breathing") ? Icons.air : Icons.nature_people, color: const Color(0xFF2E7D32)),
              ),
              title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text("${e.duration} • 🔥 -${e.caloriesBurned} kcal"),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.chevron_right, size: 16),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showWorkoutDialog(Exercise workout) {
    _secondsRemaining = _parseDuration(workout.duration);
    _isTimerActive = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          void startCountdown() {
            _timer?.cancel();
            setDialogState(() => _isTimerActive = true);
            _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
              // ✅ FIX 2: Added curly braces to if-else block
              if (_secondsRemaining > 0) {
                setDialogState(() {
                  _secondsRemaining--;
                });
              } else {
                _timer?.cancel();
                setDialogState(() {
                  _isTimerActive = false;
                });
              }
            });
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(workout.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_formatTime(_secondsRemaining), 
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.local_fire_department, size: 16, color: Colors.orange),
                    const SizedBox(width: 5),
                    Text("Est. Burn: ${workout.caloriesBurned} kcal", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
                const Divider(height: 30),
                ...workout.instructions.take(3).map((step) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [const Text("• "), Expanded(child: Text(step, style: const TextStyle(fontSize: 12)))],
                  ),
                )),
              ],
            ),
            actions: [
              TextButton(onPressed: () { _timer?.cancel(); Navigator.pop(context); }, child: const Text("Exit")),
              ElevatedButton(
                onPressed: _isTimerActive ? null : startCountdown,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                child: const Text("Start", style: TextStyle(color: Colors.white)),
              ),
              if (_secondsRemaining == 0)
                ElevatedButton(
                  onPressed: () async { 
                    setState(() => completedWorkouts.add(workout.name)); 
                    String todayId = DateTime.now().toString().split(' ')[0];
                    try {
                      await FirebaseFirestore.instance
                          .collection('users').doc(widget.user.uid)
                          .collection('daily_logs').doc(todayId)
                          .set({
                            'burned_calories': FieldValue.increment(workout.caloriesBurned),
                            'activities': FieldValue.arrayUnion([workout.name]),
                            'last_updated': Timestamp.now(),
                          }, SetOptions(merge: true));
                      
                      // ✅ FIX 3: Correct mounted check for context safety
                      if (!context.mounted) return;
                      Navigator.pop(context); 
                    } catch (e) { debugPrint("Record Error: $e"); }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: const Text("Finish", style: TextStyle(color: Colors.white)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, String sub) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(sub, style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}