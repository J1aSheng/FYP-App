import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_model.dart';
import '../models/user_model.dart' hide Exercise; 
import '../services/groq_ai_service.dart'; 
import 'workout_detail_screen.dart';

class WorkoutPlanScreen extends StatefulWidget {
  final UserModel user;
  const WorkoutPlanScreen({super.key, required this.user});

  @override
  State<WorkoutPlanScreen> createState() => _WorkoutPlanScreenState();
}

class _WorkoutPlanScreenState extends State<WorkoutPlanScreen> {
  // --- ✅ 核心邏輯 (完全保留自 Source 15) ---
  final _ai = GroqAiService();
  late Future<List<WorkoutPlan>> _aiPlans;
  late WorkoutLevel _selectedLevel; 

  @override
  void initState() {
    super.initState();
    _selectedLevel = _parseLevel(widget.user.level); 
    _aiPlans = _ai.generatePersonalizedPlans(widget.user);
  }

  WorkoutLevel _parseLevel(String levelStr) {
    return WorkoutLevel.values.firstWhere(
      (e) => e.name.toLowerCase() == levelStr.toLowerCase(),
      orElse: () => WorkoutLevel.beginner,
    );
  }

  // ✅ 統一清新亮色卡片組件
  Widget _buildCleanCard({required Widget child, EdgeInsets? margin}) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFFF0F0F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String todayId = DateTime.now().toString().split(' ')[0];
    final userCurrentLevel = _parseLevel(widget.user.level);

    return Scaffold(
      backgroundColor: const Color(0xFFFBFDFA), // ✅ 統一清新亮色背景
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "AI PERSONAL PLANNER", 
          style: TextStyle(color: Color(0xFF191C19), fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2)
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF2E7D32)), // ✅ 森林綠
            onPressed: () {
              setState(() {
                _aiPlans = _ai.generatePersonalizedPlans(widget.user);
              });
            },
          )
        ],
      ),
      body: FutureBuilder<List<WorkoutPlan>>(
        future: _aiPlans,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
          }

          final allPlans = snapshot.data ?? [];
          final categories = ["Yoga", "Cardio", "Arm", "Leg", "Plank"];

          return Column(
            children: [
              _buildBurnedSummaryHeader(todayId),
              
              // ✅ 亮色版級別選擇器
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: WorkoutLevel.values.map((level) {
                    bool isSelected = _selectedLevel == level;
                    bool isLocked = level.index > userCurrentLevel.index; 

                    return GestureDetector(
                      onTap: isLocked ? null : () => setState(() => _selectedLevel = level),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF2E7D32) : (isLocked ? const Color(0xFFF0F0F0) : Colors.white),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isSelected ? Colors.transparent : const Color(0xFFF0F0F0)),
                        ),
                        child: Row(
                          children: [
                            if (isLocked) const Padding(
                              padding: EdgeInsets.only(right: 5),
                              child: Icon(Icons.lock_rounded, size: 14, color: Color(0xFF747972)),
                            ),
                            Text(
                              level.name.toUpperCase(), 
                              style: TextStyle(
                                color: isSelected ? Colors.white : (isLocked ? const Color(0xFF747972) : const Color(0xFF191C19)), 
                                fontSize: 10, 
                                fontWeight: FontWeight.w900
                              )
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              Expanded(
                child: allPlans.isEmpty 
                ? const Center(child: Text("No activities found.", style: TextStyle(color: Color(0xFF747972))))
                : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    
                    // ✅ 過濾邏輯
                    final displayPlans = allPlans.where((p) => 
                      p.category.toLowerCase() == cat.toLowerCase() && 
                      p.level == _selectedLevel
                    ).toList();

                    if (displayPlans.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Text(
                            cat, 
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF2E7D32))
                          ),
                        ),
                        ...displayPlans.map((plan) => _buildActivityCard(plan)),
                        const SizedBox(height: 10),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ✅ 清新風格今日進度
  Widget _buildBurnedSummaryHeader(String todayId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.user.uid).collection('daily_logs').doc(todayId).snapshots(),
      builder: (context, snapshot) {
        int burned = 0;
        if (snapshot.hasData && snapshot.data!.exists) {
          burned = (snapshot.data!.data() as Map<String, dynamic>)['total_burned'] ?? 0;
        }
        return Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(children: [
              const Icon(Icons.local_fire_department_rounded, color: Color(0xFF2E7D32), size: 40),
              const SizedBox(width: 15),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Today's Progress", style: TextStyle(color: Color(0xFF747972), fontSize: 12, fontWeight: FontWeight.w600)),
                Text("$burned kcal burned", style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w900, fontSize: 20)),
              ]),
            ]),
          ),
        );
      },
    );
  }

  // ✅ 清新風格計畫卡片
  Widget _buildActivityCard(WorkoutPlan plan) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => WorkoutDetailScreen(plan: plan, user: widget.user))),
      child: _buildCleanCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12), 
            decoration: BoxDecoration(color: const Color(0xFFFFF8E1), shape: BoxShape.circle), 
            child: const Icon(Icons.bolt_rounded, color: Colors.orange, size: 22)
          ),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plan.title, style: const TextStyle(color: Color(0xFF191C19), fontWeight: FontWeight.w800)),
            Text("${plan.calories} kcal • ${plan.minutes} Min", style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 12, fontWeight: FontWeight.w900)),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFF0F0F0), size: 16),
        ]),
      ),
    );
  }
}