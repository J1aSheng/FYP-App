import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
// Removed DatabaseService import if not used elsewhere to keep code clean

class InsightsScreen extends StatelessWidget {
  final UserModel user;

  const InsightsScreen({super.key, required this.user});

  // Calculate the target calories based on user profile
  double _getDailyTarget() {
    double bmr = user.gender.toLowerCase() == "male" 
      ? 10 * user.weight + 6.25 * user.height - 5 * user.age + 5
      : 10 * user.weight + 6.25 * user.height - 5 * user.age - 161;
    
    if (user.goal.contains("Lose")) return bmr - 500;
    if (user.goal.contains("Muscle")) return bmr + 300;
    return bmr;
  }

  @override
  Widget build(BuildContext context) {
    final double target = _getDailyTarget();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text("Weekly Insights", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('daily_logs')
            .orderBy('last_updated', descending: true)
            .limit(7)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          
          if (docs.isEmpty) {
            return const Center(
              child: Text("No logs found. Start scanning meals!", 
                style: TextStyle(color: Colors.grey))
            );
          }

          // Calculate average calories
          double totalForAvg = 0;
          for (var doc in docs) {
            totalForAvg += (doc['total_calories'] ?? 0);
          }
          double average = totalForAvg / docs.length;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Calorie Trends (Last 7 Days)", 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                
                AspectRatio(
                  aspectRatio: 1.5,
                  child: BarChart(
                    BarChartData(
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
                      ),
                      barGroups: List.generate(docs.length, (index) {
                        final data = docs[(docs.length - 1) - index].data() as Map<String, dynamic>;
                        double consumed = (data['total_calories'] as num).toDouble();
                        return _makeGroupData(index, consumed, target);
                      }),
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
                const Text("Statistics", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                _buildStatCard("Average Consumed", "${average.toInt()} kcal", const Color(0xFF2E7D32)),
                _buildStatCard("Daily Target", "${target.toInt()} kcal", Colors.blueGrey),
                _buildStatCard(
                  "Consistency Score", 
                  "${((average / target) * 100).clamp(0, 100).toInt()}%",
                  const Color(0xFFE57373) // Salmon color from design
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  BarChartGroupData _makeGroupData(int x, double y, double target) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          // Green if under target, Red/Salmon if over
          color: y > target ? const Color(0xFFE57373) : const Color(0xFF2E7D32),
          width: 20,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: target,
            color: Colors.grey.withValues(alpha: 0.1), // Modern non-deprecated opacity
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      title: Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
      trailing: Text(value, 
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
    ),
  );
}