import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/database_service.dart';

class InsightsScreen extends StatelessWidget {
  final UserModel user;
  final _db = DatabaseService(); // This field is now used below

  InsightsScreen({super.key, required this.user});

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
      appBar: AppBar(title: const Text("Weekly Insights")),
      body: FutureBuilder<QuerySnapshot>(
        // Use Firebase directly or a method from your _db service
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

          // Calculate average calories from the fetched data
          double totalForAvg = 0;
          for (var doc in docs) {
            totalForAvg += (doc['total_calories'] ?? 0);
          }
          double average = totalForAvg / docs.length;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
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
                      ),
                      barGroups: List.generate(docs.length, (index) {
                        // Reverse the list so the most recent day is on the right
                        final data = docs[(docs.length - 1) - index].data() as Map<String, dynamic>;
                        double consumed = (data['total_calories'] as num).toDouble();
                        return _makeGroupData(index, consumed, target);
                      }),
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
                _buildStatCard("Average Consumed", "${average.toInt()} kcal"),
                _buildStatCard("Daily Target", "${target.toInt()} kcal"),
                _buildStatCard("Consistency Score", "${((average / target) * 100).clamp(0, 100).toInt()}%"),
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
          color: y > target ? Colors.redAccent : const Color(0xFF00695C),
          width: 18,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: target,
            color: Colors.grey[200],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    margin: const EdgeInsets.only(bottom: 15),
    child: ListTile(
      title: Text(label, style: const TextStyle(color: Colors.grey)),
      trailing: Text(value, 
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF00695C))),
    ),
  );
}