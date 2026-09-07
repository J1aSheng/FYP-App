import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';

class InsightsScreen extends StatelessWidget {
  final UserModel user;

  const InsightsScreen({super.key, required this.user});

  // 核心计算逻辑：获取每日目标热量
  double _getDailyTarget() {
    int userAge = user.age == 0 ? 25 : user.age;
    double bmr = user.gender.toLowerCase() == "male" 
      ? 10 * user.weight + 6.25 * user.height - 5 * userAge + 5
      : 10 * user.weight + 6.25 * user.height - 5 * userAge - 161;
    
    if (user.goal.contains("Lose")) return bmr - 500;
    if (user.goal.contains("Muscle")) return bmr + 300;
    return bmr;
  }

  Widget _buildPremiumCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double target = _getDailyTarget();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9F6),
      appBar: AppBar(
        title: const Text("WEEKLY INSIGHTS", style: TextStyle(color: Color(0xFF191C19), fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(user.uid)
            .collection('daily_logs').orderBy('last_updated', descending: true).limit(14).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
          }

          final docs = snapshot.data?.docs ?? [];
          
          // --- ✅ 核心改进：补全所有天数，不跳过无数据日期 ---
          List<double> eatenList = [];
          List<double> burnedList = [];
          List<String> dayLabels = [];
          double totalEaten = 0;
          double totalBurned = 0;

          Map<String, dynamic> dataMap = {for (var d in docs) d.id: d.data() as Map<String, dynamic>};

          for (int i = 6; i >= 0; i--) {
            DateTime date = DateTime.now().subtract(Duration(days: i));
            String dateId = DateFormat('yyyy-MM-dd').format(date);
            
            dayLabels.add(DateFormat('E').format(date)); // 固定显示 Mon, Tue...

            if (dataMap.containsKey(dateId)) {
              double eaten = (dataMap[dateId]['total_calories'] ?? 0).toDouble();
              double burned = (dataMap[dateId]['total_burned'] ?? 0).toDouble();
              eatenList.add(eaten);
              burnedList.add(burned);
              totalEaten += eaten;
              totalBurned += burned;
            } else {
              eatenList.add(0.0); // 无数据天数填充 0，不 skip
              burnedList.add(0.0);
            }
          }

          double avgEaten = totalEaten / 7;
          double avgBurned = totalBurned / 7;
          int healthScore = _calculateHealthScore(avgEaten, target, avgBurned);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildScoreCard(healthScore),
                const SizedBox(height: 30),

                _buildSectionHeader("Nutritional Intake", "kcal"),
                _buildPremiumCard(
                  child: Column(
                    children: [
                      _buildChartLegend("Avg Consumed", "${avgEaten.toInt()}", const Color(0xFF2E7D32)),
                      const SizedBox(height: 25),
                      SizedBox(height: 200, child: _buildLineChart(eatenList, dayLabels, target)),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                _buildSectionHeader("Activity Burned", "kcal"),
                _buildPremiumCard(
                  child: Column(
                    children: [
                      _buildChartLegend("Avg Burned", "${avgBurned.toInt()}", Colors.orange),
                      const SizedBox(height: 25),
                      SizedBox(height: 160, child: _buildBarChart(burnedList, dayLabels)),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                _buildSectionHeader("Statistical Summary", "Weekly"),
                _buildStatsGrid(avgEaten, avgBurned, target),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- ✅ 核心逻辑：美化交互与防止负数下沉 ---
  Widget _buildLineChart(List<double> data, List<String> labels, double target) {
    return LineChart(
      LineChartData(
        minY: 0,
        clipData: const FlClipData.all(), // 强制裁剪，防止线条超出范围
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => const Color(0xFF1B5E20), // 深色森林绿气泡
            tooltipBorderRadius: BorderRadius.circular(10), // ✅ Fixed: Used tooltipBorderRadius instead of tooltipRoundedRadius
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((spot) => LineTooltipItem(
                '${spot.y.toInt()} kcal',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              )).toList();
            },
          ),
          handleBuiltInTouches: true,
          getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
            return spotIndexes.map((index) => TouchedSpotIndicatorData(
              FlLine(color: const Color(0xFF2E7D32).withOpacity(0.1), strokeWidth: 3),
              FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 6, color: const Color(0xFF2E7D32), strokeWidth: 3, strokeColor: Colors.white,
              )),
            )).toList();
          },
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey[100], strokeWidth: 1)),
        titlesData: _buildTitles(labels),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(y: target, color: Colors.orange.withOpacity(0.2), strokeWidth: 2, dashArray: [5, 5]),
        ]),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), data[i])),
            isCurved: true,
            preventCurveOverShooting: true, // ✅ 防止曲线在 0 位值以下产生负数视觉效果
            color: const Color(0xFF2E7D32),
            barWidth: 5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: const Color(0xFF2E7D32).withOpacity(0.05)),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<double> data, List<String> labels) {
    return BarChart(
      BarChartData(
        minY: 0,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => Colors.orange, 
            tooltipBorderRadius: BorderRadius.circular(8), // ✅ Fixed: Used tooltipBorderRadius instead of tooltipRoundedRadius
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: _buildTitles(labels),
        barGroups: List.generate(data.length, (i) => BarChartGroupData(x: i, barRods: [
          BarChartRodData(toY: data[i], color: Colors.orange, width: 14, borderRadius: BorderRadius.circular(6), backDrawRodData: BackgroundBarChartRodData(show: true, toY: 600, color: Colors.grey[50])),
        ])),
      ),
    );
  }

  // --- 辅助 UI 组件 (保留原风格) ---
  FlTitlesData _buildTitles(List<String> labels) {
    return FlTitlesData(
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) {
        int i = v.toInt();
        return i >= 0 && i < labels.length ? Padding(padding: const EdgeInsets.only(top: 10), child: Text(labels[i], style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold))) : const Text('');
      })),
    );
  }

  int _calculateHealthScore(double avgEaten, double target, double avgBurned) {
    if (target == 0) return 0;
    double ratio = avgEaten / target;
    double score = 90; 
    if (ratio > 1.0) {
      score -= (ratio - 1.0) * 50;
    } else {
      score -= (1.0 - ratio) * 30;
    }
    if (avgBurned > 300) score += 10;
    return score.clamp(0, 100).toInt();
  }

  Widget _buildScoreCard(int score) {
    return _buildPremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Performance", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(score > 80 ? "Top Fitness! 🚀" : "Consistent Flow 🌊", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ]),
          Stack(alignment: Alignment.center, children: [
            SizedBox(width: 65, height: 65, child: CircularProgressIndicator(value: score/100, strokeWidth: 7, backgroundColor: Colors.grey[100], valueColor: const AlwaysStoppedAnimation(Color(0xFF2E7D32)), strokeCap: StrokeCap.round)),
            Text("$score", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF2E7D32))),
          ]),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(double eaten, double burned, double target) {
    double net = eaten - burned;
    String balanceText = net >= 0 ? "Surplus" : "Deficit";
    return GridView.count(
      crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.4,
      children: [
        _buildGridItem("Diet Goal", "${target.toInt()}", Icons.adjust, Colors.blue),
        _buildGridItem("Net $balanceText", "${net.abs().toInt()}", Icons.bolt, net >= 0 ? Colors.orange : const Color(0xFF2E7D32)),
        _buildGridItem("Avg Eaten", "${eaten.toInt()}", Icons.fastfood_outlined, Colors.grey),
        _buildGridItem("Avg Burned", "${burned.toInt()}", Icons.fitness_center, Colors.orange),
      ],
    );
  }

  Widget _buildGridItem(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const Spacer(),
        Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _buildSectionHeader(String title, String sub) {
    return Padding(padding: const EdgeInsets.only(bottom: 12, left: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
    ]));
  }

  Widget _buildChartLegend(String label, String value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
      ]),
      Text("$value kcal", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
    ]);
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.query_stats, size: 80, color: Colors.grey[200]),
      const SizedBox(height: 15),
      const Text("No Logs Yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
    ]));
  }
}