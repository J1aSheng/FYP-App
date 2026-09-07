import 'package:flutter/material.dart';
import '../models/workout_model.dart';
import '../models/user_model.dart' hide Exercise; 
import 'workout_timer_screen.dart'; 

class WorkoutDetailScreen extends StatelessWidget {
  final WorkoutPlan plan;
  final UserModel user; 

  const WorkoutDetailScreen({super.key, required this.plan, required this.user});

  // --- ✅ 邏輯完全保留自 Source 10 ---
  String _getLevelText(WorkoutLevel level) {
    switch (level) {
      case WorkoutLevel.beginner: return "Beginner";
      case WorkoutLevel.intermediate: return "Intermediate";
      case WorkoutLevel.advanced: return "Advanced";
    }
  }

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
        padding: const EdgeInsets.all(24),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFDFA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: const Color(0xFFF1F8F1), 
                child: Center(
                  child: Icon(
                    Icons.fitness_center_rounded, 
                    size: 80, 
                    color: const Color(0xFF2E7D32).withOpacity(0.2)
                  ),
                ),
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.title, 
                              style: const TextStyle(color: Color(0xFF191C19), fontSize: 28, fontWeight: FontWeight.w900)
                            ),
                            Text(
                              plan.subtitle, 
                              style: const TextStyle(color: Color(0xFF747972), fontSize: 14, fontWeight: FontWeight.w500)
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32), 
                          borderRadius: BorderRadius.circular(15)
                        ),
                        child: Text(
                          "${plan.minutes} MIN", 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 25),
                  
                  Row(
                    children: [
                      _buildInfoChip(icon: Icons.bar_chart, label: _getLevelText(plan.level), color: const Color(0xFF747972)),
                      const SizedBox(width: 15),
                      _buildInfoChip(icon: Icons.local_fire_department, label: "${plan.calories} kcal", color: Colors.orange),
                    ],
                  ),
                  
                  const SizedBox(height: 40),
                  const Text(
                    "Workout Steps", 
                    style: TextStyle(color: Color(0xFF191C19), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5)
                  ),
                  const SizedBox(height: 20),
                  
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: plan.exercises.length,
                    itemBuilder: (context, index) {
                      final exercise = plan.exercises[index];
                      // ✅ 修复逻辑：使用正则表达式分割 AI 生成的步骤[cite: 10]
                      final List<String> steps = exercise.description
                          .split(RegExp(r'\n|(?=Step \d+[:\s])'))
                          .where((s) => s.trim().isNotEmpty)
                          .toList();

                      return _buildCleanCard(
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  exercise.name, 
                                  style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w800, fontSize: 18)
                                ),
                                const Spacer(),
                                Text(
                                  exercise.duration, 
                                  style: const TextStyle(color: Color(0xFF747972), fontSize: 12, fontWeight: FontWeight.bold)
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 15),
                              child: Divider(color: Color(0xFFF0F0F0), height: 1),
                            ),
                            ...steps.map((step) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF2E7D32)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      step.trim(), 
                                      style: const TextStyle(color: Color(0xFF191C19), fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)
                                    )
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 120), 
                ],
              ),
            ),
          ),
        ],
      ),
      
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(25, 0, 25, 40),
        decoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => WorkoutTimerScreen(plan: plan, user: user)));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            minimumSize: const Size(double.infinity, 65),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 8,
            shadowColor: const Color(0xFF2E7D32).withOpacity(0.3),
          ),
          child: const Text(
            "START WORKOUT", 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4EF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE8F5E9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }
}