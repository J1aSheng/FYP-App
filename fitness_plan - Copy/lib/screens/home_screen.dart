import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

import '../models/user_model.dart' hide Exercise; 
import '../models/workout_model.dart'; 
import '../services/database_service.dart';
import '../services/groq_ai_service.dart'; // Make sure this path points to your AI service file

/// 首页组件：集成了 AI 建议（带回退机制）、动态热量监测、带正则解析的步骤展示及自动 Streak 系统[cite: 15]
class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- 外部服务实例 ---[cite: 15]
  final _ai = GroqAiService();
  final _db = DatabaseService();
  final _picker = ImagePicker();
  
  // --- 基础状态变量 ---[cite: 15]
  List<Exercise> todayWorkouts = [];
  Set<String> completedWorkouts = {}; 
  bool isLoadingWorkout = true;
  bool _isScanning = false;
  bool _isMealsExpanded = false; 

  // --- 核心历史导航：日期控制 ---[cite: 15]
  DateTime _selectedDate = DateTime.now(); 
  DateTime _viewedWeekMonday = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

  // --- 目标计算值 ---[cite: 15]
  late double dailyTarget;
  late double waterGoal;

  // --- 运动计时器状态 ---[cite: 15]
  Timer? _timer;
  int _secondsRemaining = 0;
  bool _isTimerActive = false;

  @override
  void initState() {
    super.initState();
    // 初始化计算：基于用户数据计算每日热量与饮水目标[cite: 15]
    dailyTarget = _calculateBMR(); 
    waterGoal = _calculateDynamicWaterGoal(); 
    _fetchAiWorkout(); 
  }

  @override
  void dispose() {
    _timer?.cancel(); 
    super.dispose();
  }

  // --- 1. 核心计算与 Streak 系统逻辑 ---[cite: 15]

  /// ✅ 核心修复：自动维护 Streak 状态。
  /// 修复了即使没超标也不增加 Streak 的问题。只要今天有活动且未超标即增加。[cite: 15]
  Future<void> _syncStreakStatus(int netCalories, int currentStreak, bool hasActivity) async {
    // 仅在查看“今天”的数据时执行判定
    bool isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (!isToday) {
      return;
    }

    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(widget.user.uid);
    
    DocumentSnapshot userDoc = await userRef.get();
    if (!userDoc.exists) {
      return;
    }
    String lastUpdate = (userDoc.data() as Map<String, dynamic>)['last_streak_update'] ?? "";

    // 逻辑 A：如果热量超过了每日目标，Streak 立即断掉重置为 0[cite: 15]
    if (netCalories > dailyTarget && currentStreak > 0) {
      await userRef.update({
        'streak_count': 0,
        'last_streak_update': todayStr,
      });
      debugPrint("🔥 Streak Broken: Daily calorie limit exceeded.");
    } 
    // 逻辑 B：修复点 -> 只要有任何活动记录且未超标，即增加。[cite: 15]
    else if (hasActivity && netCalories <= dailyTarget && lastUpdate != todayStr) {
      DateTime lastDate = lastUpdate.isEmpty ? DateTime(2000) : DateFormat('yyyy-MM-dd').parse(lastUpdate);
      DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
      bool wasYesterday = DateFormat('yyyy-MM-dd').format(lastDate) == DateFormat('yyyy-MM-dd').format(yesterday);
      
      // 如果昨天也达标了，则 +1，否则判定为新的一天开始计为 1[cite: 15]
      int newStreak = wasYesterday ? currentStreak + 1 : 1;
      await userRef.update({
        'streak_count': newStreak,
        'last_streak_update': todayStr,
      });
      debugPrint("🌟 Streak Increased: Goal maintained with activity.");
    }
  }

  /// ✅ 逻辑：基于 UserModel 中的 level 字段计算 TDEE[cite: 15]
  double _calculateBMR() {
    int userAge = widget.user.age == 0 ? 25 : widget.user.age;
    
    // 基础代谢计算 (Mifflin-St Jeor)[cite: 15]
    double bmr = widget.user.gender.toLowerCase() == "male" 
      ? 10 * widget.user.weight + 6.25 * widget.user.height - 5 * userAge + 5
      : 10 * widget.user.weight + 6.25 * widget.user.height - 5 * userAge - 161;
    
    // 活动系数相乘 (根据 widget.user.level)[cite: 15]
    double factor = 1.2; 
    String actLevel = widget.user.level.toLowerCase(); 
    
    if (actLevel.contains("light") || actLevel.contains("beginner")) {
      factor = 1.375;
    } else if (actLevel.contains("moderat") || actLevel.contains("intermediate")) {
      factor = 1.55;
    } else if (actLevel.contains("active") || actLevel.contains("pro")) {
      factor = 1.725;
    }
    
    bmr *= factor;

    // 根据目标调整热量[cite: 15]
    if (widget.user.goal.contains("Lose")) {
      return bmr - 500;
    }
    if (widget.user.goal.contains("Muscle")) {
      return bmr + 300;
    }
    return bmr;
  }

  /// 动态计算饮水目标[cite: 15]
  double _calculateDynamicWaterGoal() {
    double baseWater = widget.user.weight * 30.0; 
    if (widget.user.gender.toLowerCase() == "male") {
      baseWater += 400.0;
    }
    return baseWater;
  }

  /// 辅助：解析运动时长字符串[cite: 15]
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

  /// 辅助：估算热量消耗[cite: 15]
  int _estimateCalories(String duration) {
    int mins = _parseDuration(duration) ~/ 60;
    return mins * 8; 
  }

  /// 辅助：格式化剩余时间[cite: 15]
  String _formatTime(int seconds) {
    int mins = seconds ~/ 60;
    int secs = seconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  /// 颜色逻辑：热量圆环[cite: 15]
  Color _getCaloriesColor(int remaining, double target) {
    if (remaining <= 0) {
      return Colors.redAccent;
    } 
    if (remaining < target * 0.15) {
      return Colors.orangeAccent;
    } 
    return const Color(0xFF8BC34A); 
  }

  /// 颜色逻辑：单餐热量标签[cite: 15]
  Color _getMealIntensityColor(int kcal) {
    if (kcal > 500) {
      return Colors.redAccent;
    }
    if (kcal >= 200) {
      return Colors.orangeAccent;
    }
    return const Color(0xFF8BC34A);
  }

  // --- 2. 数据库与交互逻辑 ---[cite: 15]

  /// 切换周视图[cite: 15]
  void _changeViewedWeek(int days) {
    setState(() {
      _viewedWeekMonday = _viewedWeekMonday.add(Duration(days: days));
    });
  }

  /// 获取 AI 个性化运动建议[cite: 15]
  Future<void> _fetchAiWorkout() async {
    try {
      final List<Exercise> list = await _ai.generateDailyWorkout(widget.user);
      if (mounted) {
        setState(() { 
          todayWorkouts = list; 
          isLoadingWorkout = false; 
        });
      }
    } catch (e) {
      if (mounted) {
        // Fallback 机制：AI 失败时显示默认科学运动建议[cite: 15]
        setState(() {
          todayWorkouts = [
            Exercise(
              name: "Brisk Walking", 
              duration: "20 min", 
              imageAsset: "assets/images/walking.png",
              description: "Maintain a steady pace to improve heart health."
            ),
            Exercise(
              name: "Bodyweight Squats", 
              duration: "10 min", 
              imageAsset: "assets/images/squats.png",
              description: "Build lower body strength and burn fat."
            ),
            Exercise(
              name: "Full Stretching", 
              duration: "10 min", 
              imageAsset: "assets/images/stretching.png",
              description: "Increase flexibility and aid muscle recovery."
            ),
          ];
          isLoadingWorkout = false;
        });
      }
    }
  }

  /// 相机拍摄食物并 AI 分析[cite: 15]
  Future<void> _scanFood({String? manualCategory}) async {
    final photo = await _picker.pickImage(source: ImageSource.camera, maxWidth: 800, maxHeight: 800);
    if (photo == null) {
      return;
    }

    setState(() => _isScanning = true);
    try {
      final foodData = await _ai.analyzeFoodImage(File(photo.path));
      if (foodData != null && mounted) {
        final directory = await getApplicationDocumentsDirectory();
        final String permanentPath = p.join(directory.path, "${DateTime.now().millisecondsSinceEpoch}.jpg");
        await File(photo.path).copy(permanentPath);

        String dateId = DateFormat('yyyy-MM-dd').format(_selectedDate); 
        await _db.logMealWithSync(
          widget.user.uid, 
          {...foodData, 'category': manualCategory ?? "Meal", 'date_id': dateId}, 
          permanentPath
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  /// 饮水毫升更新[cite: 15]
  Future<void> _updateWater(int amount) async {
    String dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(widget.user.uid)
          .collection('daily_logs').doc(dateId)
          .set({
            'water_intake': FieldValue.increment(amount),
            'last_updated': Timestamp.now(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Water Error: $e");
    }
  }

  /// 预览餐食图片弹窗[cite: 15]
  void _showImagePreview(String imagePath, String? foodName, int calories) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: Image.file(File(imagePath), fit: BoxFit.cover),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                Text(foodName ?? "Meal", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text("$calories kcal", style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
            ),
            const SizedBox(height: 10),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white, size: 35)),
          ],
        ),
      ),
    );
  }

  // --- 3. UI 主构建 ---[cite: 15]

  @override
  Widget build(BuildContext context) {
    String dateId = DateFormat('yyyy-MM-dd').format(_selectedDate); 

    return Scaffold(
      
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users').doc(widget.user.uid)
            .collection('daily_logs').doc(dateId).snapshots(),
        builder: (context, snapshot) {
          int totalEaten = 0, burned = 0, waterIntake = 0; 
          List<dynamic> finishedActivities = [], mealsData = []; 
          
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            totalEaten = (data['total_calories'] ?? 0).toInt();
            burned = (data['total_burned'] ?? 0).toInt();
            waterIntake = (data['water_intake'] ?? 0).toInt();
            finishedActivities = data['activities'] ?? [];
            mealsData = data['meals'] ?? [];
          }

          int netCalories = totalEaten - burned;
          int remaining = (dailyTarget - netCalories).toInt();
          // ✅ 修复：用于同步计算 Streak 的活动状态位[cite: 15]
          bool hasAnyActivity = mealsData.isNotEmpty || finishedActivities.isNotEmpty;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                // ✅ 顶部 Header 逻辑中传入活动判定
                _buildTopHeader(netCalories, hasAnyActivity), 
                const SizedBox(height: 25),
                _buildCaloriesPlanCard(totalEaten, burned, remaining), 
                const SizedBox(height: 10),
                _buildProgressionCard(burned), 

                const SizedBox(height: 30),
                _buildHistoryHeader(),
                const SizedBox(height: 15),
                _buildDynamicWeeklyStrip(),

                const SizedBox(height: 30),
                _buildMealSection(mealsData), // ✅ 已按照要求移除顶部的重复相机按钮[cite: 15]
                const SizedBox(height: 30),
                _buildWaterIntakeCard(waterIntake), 
                
                const SizedBox(height: 30),
                if (finishedActivities.isNotEmpty) ...[
                  _buildSectionHeader("Recent Activities", "Today"),
                  const SizedBox(height: 10),
                  ...finishedActivities.reversed.map((data) => _buildRecentActivityItem(data)),
                  const SizedBox(height: 30),
                ],

                _buildSectionHeader("AI Activity Suggestions", "SMART"),
                _buildAiWorkoutList(),
                
                const SizedBox(height: 140), 
              ],
            ),
          );
        }
      ),
    );
  }

  // --- 4. 子组件详细实现 ---[cite: 15]

  /// ✅ 顶部 Header：显示用户名 + Stay on track，集成修复后的 Streak 逻辑
  Widget _buildTopHeader(int netCalories, bool hasActivity) {
    bool isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now());
    String historyDate = DateFormat('EEEE, d MMM yyyy').format(_selectedDate);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.user.uid).snapshots(),
      builder: (context, snapshot) {
        int streak = 0;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          streak = data['streak_count'] ?? 0;
          
          // 实时检测 Streak 状态：热量达标且有活动即增加天数[cite: 15]
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncStreakStatus(netCalories, streak, hasActivity);
          });
        }
        return Row(
          children: [
            CircleAvatar(
              radius: 28, backgroundColor: const Color(0xFFE8F5E9),
              child: Text(widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : "U", 
                style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 20)),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.user.name.isNotEmpty ? widget.user.name : "User", 
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(isToday ? "Stay on track! 🍏" : historyDate, 
                    style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (isToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department, color: Colors.orange, size: 18),
                    const SizedBox(width: 5),
                    Text("$streak Days", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            else
              ElevatedButton(
                onPressed: () => setState(() => _selectedDate = DateTime.now()),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, elevation: 0, shape: const StadiumBorder()),
                child: const Text("Today", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ],
        );
      }
    );
  }

  /// 成就卡片[cite: 15]
  Widget _buildProgressionCard(int burned) {
    const int activityGoal = 500; 
    double progress = (burned / activityGoal).clamp(0.0, 1.0);

    return SizedBox(
      width: double.infinity, 
      height: 140,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF4CAF50)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: const Color(0xFF4CAF50).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
              ),
            ),
          ),
          Positioned(right: -15, top: -15, child: CircleAvatar(radius: 50, backgroundColor: Colors.white.withOpacity(0.1))),
          Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Daily Achievement", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(15)),
                      child: const Text("Keep Going", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
                const SizedBox(height: 10),
                Text("Fuel Burned: $burned kcal", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 15),
                Stack(
                  children: [
                    Container(height: 6, width: double.infinity, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(height: 6, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    String monthYear = DateFormat('MMMM yyyy').format(_viewedWeekMonday);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Calorie History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(monthYear, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        Row(
          children: [
            IconButton(onPressed: () => _changeViewedWeek(-7), icon: const Icon(Icons.chevron_left)),
            const Text("Weeks", style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12)),
            IconButton(onPressed: () => _changeViewedWeek(7), icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ],
    );
  }

  /// 动态周条：显示星期 + 具体日期数字[cite: 15]
  Widget _buildDynamicWeeklyStrip() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(widget.user.uid)
          .collection('daily_logs').where('last_updated', isGreaterThanOrEqualTo: Timestamp.fromDate(_viewedWeekMonday))
          .get(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        List<String> dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (index) {
            DateTime dayDate = _viewedWeekMonday.add(Duration(days: index));
            String dayId = DateFormat('yyyy-MM-dd').format(dayDate);
            bool isSelected = DateFormat('yyyy-MM-dd').format(_selectedDate) == dayId;

            var dailyDoc = docs.where((doc) => doc.id == dayId);
            bool hasData = dailyDoc.isNotEmpty;
            bool exceeded = false;
            if (hasData) {
              final data = dailyDoc.first.data() as Map<String, dynamic>;
              exceeded = (data['total_calories'] ?? 0) > dailyTarget;
            }

            return GestureDetector(
              onTap: () => setState(() => _selectedDate = dayDate), 
              child: Column(
                children: [
                  Text(dayLabels[index], style: TextStyle(color: isSelected ? Colors.black : Colors.grey, fontSize: 12)),
                  Text(DateFormat('dd').format(dayDate), 
                    style: TextStyle(color: isSelected ? Colors.black : Colors.grey[400], fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: isSelected ? Border.all(color: Colors.green, width: 2) : null),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: !hasData ? Colors.grey[100] : (exceeded ? Colors.red[50] : Colors.green[50]),
                      ),
                      child: Icon(
                        !hasData ? Icons.remove : (exceeded ? Icons.close : Icons.check),
                        size: 18, color: !hasData ? Colors.grey : (exceeded ? Colors.red : Colors.green),
                      ),
                    ),
                  )
                ],
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildCaloriesPlanCard(int eaten, int burned, int remaining) {
    Color dynamicColor = _getCaloriesColor(remaining, dailyTarget);
    double progressValue = (dailyTarget > 0) ? (eaten - burned) / dailyTarget : 0.0;

    return Container(
      width: double.infinity, padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(30), 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat("Eaten", "$eaten"),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 110, width: 110, 
                child: CircularProgressIndicator(
                  value: progressValue.clamp(0.0, 1.0), 
                  strokeWidth: 10, backgroundColor: Colors.grey[100], 
                  valueColor: AlwaysStoppedAnimation<Color>(dynamicColor), 
                  strokeCap: StrokeCap.round
                )
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text("${remaining < 0 ? 0 : remaining}", 
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: dynamicColor)),
                const Text("kcal left", style: TextStyle(fontSize: 10, color: Colors.grey)),
              ])
            ],
          ),
          _buildStat("Burned", "$burned"), 
        ],
      ),
    );
  }

  // ✅ 包含了相机扫描按钮的 _buildMealSection[cite: 15]
  Widget _buildMealSection(List<dynamic> meals) {
    bool canExpand = meals.length > 3;
    final displayedMeals = _isMealsExpanded ? meals : meals.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text("Meals Logged", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (_isScanning)
                  const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32)),
                  )
                else
                  IconButton(
                    onPressed: () => _scanFood(), 
                    icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF2E7D32), size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            if (canExpand)
              TextButton(
                onPressed: () => setState(() => _isMealsExpanded = !_isMealsExpanded), 
                child: Text(_isMealsExpanded ? "Show Less" : "View All", 
                  style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold))
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (meals.isEmpty) 
          const Padding(padding: EdgeInsets.all(10), child: Text("No meals logged for this day.", style: TextStyle(color: Colors.grey)))
        else 
          ...displayedMeals.map((mealData) {
            final meal = mealData as Map<String, dynamic>;
            final int calValue = (meal['calories'] ?? 0).toInt();
            final String path = meal['image_path'] ?? "";
            Color intensityColor = _getMealIntensityColor(calValue);

            return GestureDetector(
              onTap: () => (path.isNotEmpty && File(path).existsSync()) 
                ? _showImagePreview(path, meal['food_name'], calValue) : null,
              child: Container(
                margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(22), 
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]
                ),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15), 
                    child: (path.isNotEmpty && File(path).existsSync()) 
                      ? Image.file(File(path), width: 65, height: 65, fit: BoxFit.cover) 
                      : Container(width: 65, height: 65, color: Colors.grey[100], child: const Icon(Icons.restaurant, color: Colors.grey))
                  ),
                  const SizedBox(width: 15),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(meal['food_name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(meal['category'] ?? "Meal", style: const TextStyle(color: Colors.grey, fontSize: 12))
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
                    decoration: BoxDecoration(color: intensityColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), 
                    child: Text("$calValue kcal", style: TextStyle(color: intensityColor, fontWeight: FontWeight.bold, fontSize: 14))
                  ),
                ]),
              ),
            );
          }),
      ],
    );
  }

  /// 饮水追踪卡片[cite: 15]
  Widget _buildWaterIntakeCard(int currentIntake) {
    double progress = (currentIntake / waterGoal).clamp(0.0, 1.0);
    int remaining = (waterGoal - currentIntake).toInt().clamp(0, waterGoal.toInt());

    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(25), 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichText(text: TextSpan(style: const TextStyle(color: Colors.black, fontSize: 32, fontWeight: FontWeight.bold), 
            children: [TextSpan(text: "$currentIntake "), const TextSpan(text: "ml", style: TextStyle(fontSize: 24))])),
            const SizedBox(height: 5),
            Text("${(progress * 100).toInt()}%, Remaining : $remaining ml", style: const TextStyle(color: Colors.grey, fontSize: 14))
          ]),
          ElevatedButton(
            onPressed: () => _updateWater(250), 
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEDF2FF), foregroundColor: const Color(0xFF5C7CFA), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
            child: const Text("Record Drinks", style: TextStyle(fontWeight: FontWeight.bold))
          ),
        ]),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(10), 
          child: LinearProgressIndicator(value: progress, minHeight: 12, backgroundColor: const Color(0xFFE9ECEF), color: const Color(0xFF5C7CFA))
        ),
        const SizedBox(height: 25),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [50, 150, 250, 350, 500].map((ml) => Column(children: [
          GestureDetector(
            onTap: () => _updateWater(ml), 
            child: Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Color(0xFF5C7CFA), shape: BoxShape.circle), child: const Icon(Icons.water_drop, color: Colors.white, size: 20))
          ),
          const SizedBox(height: 8),
          Text("$ml", style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))
        ])).toList()),
      ]),
    );
  }

  /// AI 建议列表：展示详细的时长与热量消耗数据[cite: 15]
  Widget _buildAiWorkoutList() {
    if (isLoadingWorkout) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    }
    return Column(children: todayWorkouts.map((e) {
      bool done = completedWorkouts.contains(e.name);
      int estBurn = _estimateCalories(e.duration);
      return GestureDetector(
        onTap: () => _showWorkoutDialog(e), 
        child: Container(
          margin: const EdgeInsets.only(top: 15), padding: const EdgeInsets.all(15), 
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20), 
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)], 
            border: done ? Border.all(color: const Color(0xFF2E7D32)) : null
          ), 
          child: ListTile(
            contentPadding: EdgeInsets.zero, 
            leading: Container(
              padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF0F4C3), borderRadius: BorderRadius.circular(15)), 
              child: Icon(e.name.contains("Breathing") ? Icons.air : Icons.nature_people, color: const Color(0xFF2E7D32))
            ), 
            title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
            subtitle: Text("${e.duration} • 🔥 -$estBurn kcal"), // ✅ 显示时长与消耗数据
            trailing: const Icon(Icons.chevron_right, size: 16)
          )
        )
      );
    }).toList());
  }

  /// ✅ 运动计时弹窗：集成了正则步骤分割逻辑，解决 AI 生成“乱到完”的问题[cite: 15]
  void _showWorkoutDialog(Exercise workout) {
    _secondsRemaining = _parseDuration(workout.duration); 
    int estBurn = _estimateCalories(workout.duration); 
    _isTimerActive = false;
    
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        void startCountdown() { 
          _timer?.cancel(); 
          setDialogState(() => _isTimerActive = true); 
          _timer = Timer.periodic(const Duration(seconds: 1), (timer) { 
            if (_secondsRemaining > 0) {
              setDialogState(() { _secondsRemaining--; });
            } else { 
              _timer?.cancel(); 
              setDialogState(() { _isTimerActive = false; }); 
            } 
          }); 
        }

        // ✅ 核心修复：使用正则表达式分割 AI 生成的长段落描述[cite: 15]
        final List<String> steps = workout.description
            .split(RegExp(r'\n|(?=Step \d+[:\s])'))
            .where((s) => s.trim().isNotEmpty)
            .toList();
        
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)), 
          title: Text(workout.name, style: const TextStyle(fontWeight: FontWeight.bold)), 
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_formatTime(_secondsRemaining), 
              style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: Color(0xFF2E7D32))), 
            const SizedBox(height: 10), 
            Text("Est. Burn: $estBurn kcal", style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)), 
            const Divider(height: 40), 
            SizedBox(
              height: 120, // 限制描述区高度并允许滚动
              child: SingleChildScrollView(
                child: Column(
                  children: steps.map((step) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(step.trim(), style: const TextStyle(fontSize: 13, height: 1.4)))
                    ]),
                  )).toList(),
                ),
              ),
            ),
          ]), 
          actions: [
            TextButton(onPressed: () { _timer?.cancel(); Navigator.pop(context); }, child: const Text("Exit")), 
            ElevatedButton(
              onPressed: _isTimerActive ? null : startCountdown, 
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
              child: const Text("Start Workout", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
            ), 
            if (_secondsRemaining == 0) 
              ElevatedButton(
                onPressed: () async { 
                  setState(() => completedWorkouts.add(workout.name)); 
                  String dateId = DateFormat('yyyy-MM-dd').format(_selectedDate); 
                  try { 
                    await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).collection('daily_logs').doc(dateId).set({
                      'total_burned': FieldValue.increment(estBurn), 
                      'activities': FieldValue.arrayUnion([{'activity_name': workout.name, 'calories_burned': estBurn, 'logged_at': Timestamp.now()}]), 
                      'last_updated': Timestamp.now()
                    }, SetOptions(merge: true)); 
                    if (!context.mounted) return; 
                    Navigator.pop(context); 
                  } catch (e) { debugPrint("Record Save Error: $e"); } 
                }, 
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent), 
                child: const Text("Finish & Save", style: TextStyle(color: Colors.white))
              )
          ]
        );
      })
    );
  }

  // --- 5. 辅助 UI 工具组件 ---[cite: 15]

  Widget _buildStat(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))
    ]);
  }

  Widget _buildSectionHeader(String title, String sub) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      Text(sub, style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 12, fontWeight: FontWeight.bold))
    ]);
  }

  Widget _buildRecentActivityItem(dynamic activityData) {
    String name = "Activity"; String info = "";
    if (activityData is Map) {
      name = activityData['activity_name'] ?? "Unknown";
      if (activityData['calories_burned'] != null) {
        info = "${activityData['calories_burned']} kcal burned";
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(15), 
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), 
      child: Row(children: [
        const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (info.isNotEmpty) Text(info, style: const TextStyle(color: Colors.grey, fontSize: 11))
        ])),
        const Text("Completed", style: TextStyle(color: Colors.grey, fontSize: 11))
      ]),
    );
  }
}