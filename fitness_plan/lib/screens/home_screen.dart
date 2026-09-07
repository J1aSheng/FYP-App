import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

import '../models/user_model.dart';
import '../models/workout_model.dart';
import '../services/database_service.dart';
import '../services/groq_ai_service.dart'; // Make sure this path points to your AI service file
import '../theme/app_theme.dart';

/// 首页组件：集成了 AI 建议（带回退机制）、动态热量监测、带正则解析的步骤展示及自动 Streak 系统
class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- 外部服务实例 ---
  final _ai = GroqAiService();
  final _db = DatabaseService();
  final _picker = ImagePicker();

  // --- 基础状态变量 ---
  List<Exercise> todayWorkouts = [];
  Set<String> completedWorkouts = {};
  bool isLoadingWorkout = true;
  bool _isScanning = false;
  bool _isMealsExpanded = false;

  // --- 核心历史导航：日期控制 ---
  DateTime _selectedDate = DateTime.now();
  DateTime _viewedWeekMonday = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

  // --- 目标计算值 ---
  late double dailyTarget;
  late double waterGoal;

  // --- 运动计时器状态 ---
  Timer? _timer;
  int _secondsRemaining = 0;
  bool _isTimerActive = false;

  @override
  void initState() {
    super.initState();
    // 初始化计算：基于用户数据计算每日热量与饮水目标
    dailyTarget = _calculateBMR();
    waterGoal = _calculateDynamicWaterGoal();
    _fetchAiWorkout();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // --- 1. 核心计算与 Streak 系统逻辑 ---
  // (unchanged from original — business logic only, no layout here)

  Future<void> _syncStreakStatus(int netCalories, int currentStreak, bool hasActivity) async {
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

    if (netCalories > dailyTarget && currentStreak > 0) {
      await userRef.update({
        'streak_count': 0,
        'last_streak_update': todayStr,
      });
      debugPrint("🔥 Streak Broken: Daily calorie limit exceeded.");
    } else if (hasActivity && netCalories <= dailyTarget && lastUpdate != todayStr) {
      DateTime lastDate = lastUpdate.isEmpty ? DateTime(2000) : DateFormat('yyyy-MM-dd').parse(lastUpdate);
      DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
      bool wasYesterday = DateFormat('yyyy-MM-dd').format(lastDate) == DateFormat('yyyy-MM-dd').format(yesterday);

      int newStreak = wasYesterday ? currentStreak + 1 : 1;
      await userRef.update({
        'streak_count': newStreak,
        'last_streak_update': todayStr,
      });
      debugPrint("🌟 Streak Increased: Goal maintained with activity.");
    }
  }

  double _calculateBMR() {
    int userAge = widget.user.age == 0 ? 25 : widget.user.age;

    double bmr = widget.user.gender.toLowerCase() == "male"
        ? 10 * widget.user.weight + 6.25 * widget.user.height - 5 * userAge + 5
        : 10 * widget.user.weight + 6.25 * widget.user.height - 5 * userAge - 161;

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

    if (widget.user.goal.contains("Lose")) {
      return bmr - 500;
    }
    if (widget.user.goal.contains("Muscle")) {
      return bmr + 300;
    }
    return bmr;
  }

  double _calculateDynamicWaterGoal() {
    double baseWater = widget.user.weight * 30.0;
    if (widget.user.gender.toLowerCase() == "male") {
      baseWater += 400.0;
    }
    return baseWater;
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

  int _estimateCalories(String duration) {
    int mins = _parseDuration(duration) ~/ 60;
    return mins * 8;
  }

  String _formatTime(int seconds) {
    int mins = seconds ~/ 60;
    int secs = seconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  Color _getCaloriesColor(int remaining, double target) {
    if (remaining <= 0) {
      return AppColors.danger;
    }
    if (remaining < target * 0.15) {
      return AppColors.warning;
    }
    return AppColors.accentGreen;
  }

  Color _getMealIntensityColor(int kcal) {
    if (kcal > 500) {
      return AppColors.danger;
    }
    if (kcal >= 200) {
      return AppColors.warning;
    }
    return AppColors.accentGreen;
  }

  // --- 2. 数据库与交互逻辑 --- (unchanged)

  void _changeViewedWeek(int days) {
    setState(() {
      _viewedWeekMonday = _viewedWeekMonday.add(Duration(days: days));
    });
  }

  Future<void> _fetchAiWorkout() async {
    if (mounted) {
      setState(() => isLoadingWorkout = true);
    }
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
        setState(() {
          todayWorkouts = [
            Exercise(
              name: "Brisk Walking",
              reps: "-",
              duration: "20 min",
              caloriesBurned: 160,
              instructions: [
                "Warm up with a slow 2-minute walk.",
                "Pick up the pace to a brisk, steady stride.",
                "Cool down by slowing your pace for the last minute.",
              ],
            ),
            Exercise(
              name: "Bodyweight Squats",
              reps: "3 sets x 15",
              duration: "10 min",
              caloriesBurned: 80,
              instructions: [
                "Stand with feet shoulder-width apart.",
                "Lower your hips back and down as if sitting in a chair.",
                "Push through your heels to return to standing.",
              ],
            ),
            Exercise(
              name: "Full Stretching",
              reps: "-",
              duration: "10 min",
              caloriesBurned: 40,
              instructions: [
                "Start with gentle neck and shoulder rolls.",
                "Move through hamstring, quad, and hip stretches.",
                "Hold each stretch for 20-30 seconds, breathing steadily.",
              ],
            ),
          ];
          isLoadingWorkout = false;
        });
      }
    }
  }

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
          permanentPath,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _updateWater(int amount) async {
    String dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('daily_logs')
          .doc(dateId)
          .set({
        'water_intake': FieldValue.increment(amount),
        'last_updated': Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Water Error: $e");
    }
  }

  void _showImagePreview(String imagePath, String? foodName, int calories) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Image.file(File(imagePath), fit: BoxFit.cover),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              radius: AppRadius.lg,
              child: Column(children: [
                Text(foodName ?? "Meal", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.xs),
                Text("$calories kcal", style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
            ),
            const SizedBox(height: AppSpacing.sm),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white, size: 35)),
          ],
        ),
      ),
    );
  }

  // --- 3. UI 主构建 ---

  @override
  Widget build(BuildContext context) {
    String dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      backgroundColor: AppColors.background,
      // SafeArea replaces the old hardcoded `SizedBox(height: 60)` hack —
      // it correctly adapts to notches / status bar height on every device.
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.user.uid)
              .collection('daily_logs')
              .doc(dateId)
              .snapshots(),
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
            bool hasAnyActivity = mealsData.isNotEmpty || finishedActivities.isNotEmpty;

            return RefreshIndicator(
              color: AppColors.primary,
              // Firestore data is already live via the stream above, so pull-
              // to-refresh's job is just to retry the one thing that ISN'T
              // reactive: the AI workout suggestions.
              onRefresh: _fetchAiWorkout,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopHeader(netCalories, hasAnyActivity),
                    const SizedBox(height: AppSpacing.xl),
                    _buildCaloriesPlanCard(totalEaten, burned, remaining),
                    const SizedBox(height: AppSpacing.sm),
                    _buildProgressionCard(burned),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildHistoryHeader(),
                    const SizedBox(height: AppSpacing.md),
                    _buildDynamicWeeklyStrip(),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildMealSection(mealsData),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildWaterIntakeCard(waterIntake),
                    const SizedBox(height: AppSpacing.xxl),
                    if (finishedActivities.isNotEmpty) ...[
                      const AppSectionHeader(title: "Recent Activities", subtitle: "Today"),
                      const SizedBox(height: AppSpacing.md),
                      ...finishedActivities.reversed.map((data) => _buildRecentActivityItem(data)),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                    const AppSectionHeader(title: "AI Activity Suggestions", subtitle: "SMART"),
                    // Bug fix: original was missing this gap, so the list
                    // sat flush against the header instead of matching the
                    // spacing every other section uses.
                    const SizedBox(height: AppSpacing.md),
                    _buildAiWorkoutList(),
                    const SizedBox(height: 140),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- 4. 子组件详细实现 ---

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

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncStreakStatus(netCalories, streak, hasActivity);
          });
        }
        return Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primaryLight,
              child: Text(
                widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : "U",
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
            const SizedBox(width: AppSpacing.lg - 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.user.name.isNotEmpty ? widget.user.name : "User",
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    isToday ? "Stay on track! 🍏" : historyDate,
                    style: const TextStyle(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (isToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
                child: const Text("Today", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ],
        );
      },
    );
  }

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
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadius.xxl),
                boxShadow: [BoxShadow(color: AppColors.gradientEnd.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
              ),
            ),
          ),
          Positioned(right: -15, top: -15, child: CircleAvatar(radius: 50, backgroundColor: Colors.white.withValues(alpha: 0.1))),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
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
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(AppRadius.md)),
                      child: const Text("Keep Going", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text("Fuel Burned: $burned kcal", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: AppSpacing.md),
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
          const Text("Calorie History", style: AppText.sectionTitle),
          Text(monthYear, style: AppText.muted),
        ]),
        Row(
          children: [
            IconButton(onPressed: () => _changeViewedWeek(-7), icon: const Icon(Icons.chevron_left)),
            const Text("Weeks", style: AppText.sectionSub),
            IconButton(onPressed: () => _changeViewedWeek(7), icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ],
    );
  }

  Widget _buildDynamicWeeklyStrip() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('daily_logs')
          .where('last_updated', isGreaterThanOrEqualTo: Timestamp.fromDate(_viewedWeekMonday))
          .get(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        List<String> dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

        // Wrapped in a horizontally scrollable row so 7 day-columns never
        // overflow on narrow phones — the original Row(spaceBetween) had
        // no overflow protection at all.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
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

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedDate = dayDate),
                  child: Column(
                    children: [
                      Text(dayLabels[index], style: TextStyle(color: isSelected ? AppColors.textPrimary : AppColors.textMuted, fontSize: 12)),
                      Text(
                        DateFormat('dd').format(dayDate),
                        style: TextStyle(
                          color: isSelected ? AppColors.textPrimary : Colors.grey[400],
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
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
                            size: 18,
                            color: !hasData ? Colors.grey : (exceeded ? Colors.red : Colors.green),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildCaloriesPlanCard(int eaten, int burned, int remaining) {
    Color dynamicColor = _getCaloriesColor(remaining, dailyTarget);
    double progressValue = (dailyTarget > 0) ? (eaten - burned) / dailyTarget : 0.0;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat("Eaten", "$eaten"),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 110,
                width: 110,
                child: CircularProgressIndicator(
                  value: progressValue.clamp(0.0, 1.0),
                  strokeWidth: 10,
                  backgroundColor: Colors.grey[100],
                  valueColor: AlwaysStoppedAnimation<Color>(dynamicColor),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text("${remaining < 0 ? 0 : remaining}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: dynamicColor)),
                const Text("kcal left", style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ])
            ],
          ),
          _buildStat("Burned", "$burned"),
        ],
      ),
    );
  }

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
                const Text("Meals Logged", style: AppText.sectionTitle),
                const SizedBox(width: AppSpacing.sm),
                if (_isScanning)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                else
                  IconButton(
                    onPressed: () => _scanFood(),
                    icon: const Icon(Icons.camera_alt_outlined, color: AppColors.primary, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            if (canExpand)
              TextButton(
                onPressed: () => setState(() => _isMealsExpanded = !_isMealsExpanded),
                child: Text(_isMealsExpanded ? "Show Less" : "View All", style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (meals.isEmpty)
          const AppEmptyState(icon: Icons.restaurant_outlined, message: "No meals logged for this day.")
        else
          ...displayedMeals.map((mealData) {
            final meal = mealData as Map<String, dynamic>;
            final int calValue = (meal['calories'] ?? 0).toInt();
            final String path = meal['image_path'] ?? "";
            Color intensityColor = _getMealIntensityColor(calValue);

            return GestureDetector(
              onTap: () => (path.isNotEmpty && File(path).existsSync()) ? _showImagePreview(path, meal['food_name'], calValue) : null,
              child: AppCard(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                radius: AppRadius.lg + 2,
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: (path.isNotEmpty && File(path).existsSync())
                        ? Image.file(File(path), width: 65, height: 65, fit: BoxFit.cover)
                        : Container(width: 65, height: 65, color: Colors.grey[100], child: const Icon(Icons.restaurant, color: Colors.grey)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(meal['food_name'] ?? "Unknown", style: AppText.cardTitle),
                      const SizedBox(height: AppSpacing.xs),
                      Text(meal['category'] ?? "Meal", style: AppText.muted),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
                    decoration: BoxDecoration(color: intensityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
                    child: Text("$calValue kcal", style: TextStyle(color: intensityColor, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ]),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildWaterIntakeCard(int currentIntake) {
    double progress = (currentIntake / waterGoal).clamp(0.0, 1.0);
    int remaining = (waterGoal - currentIntake).toInt().clamp(0, waterGoal.toInt());

    return AppCard(
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.bold),
                children: [TextSpan(text: "$currentIntake "), const TextSpan(text: "ml", style: TextStyle(fontSize: 24))],
              ),
            ),
            const SizedBox(height: 5),
            Text("${(progress * 100).toInt()}%, Remaining : $remaining ml", style: AppText.muted),
          ]),
          ElevatedButton(
            onPressed: () => _updateWater(250),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.waterLight,
              foregroundColor: AppColors.water,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            child: const Text("Record Drinks", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: AppSpacing.lg),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm - 2),
          child: LinearProgressIndicator(value: progress, minHeight: 12, backgroundColor: const Color(0xFFE9ECEF), color: AppColors.water),
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [50, 150, 250, 350, 500]
              .map((ml) => Column(children: [
                    GestureDetector(
                      onTap: () => _updateWater(ml),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md - 3),
                        decoration: const BoxDecoration(color: AppColors.water, shape: BoxShape.circle),
                        child: const Icon(Icons.water_drop, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text("$ml", style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
                  ]))
              .toList(),
        ),
      ]),
    );
  }

  Widget _buildAiWorkoutList() {
    if (isLoadingWorkout) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    }
    if (todayWorkouts.isEmpty) {
      // Previously: a blank gap if both the AI call and the fallback
      // list somehow ended up empty. Now the user gets an explanation
      // and a way to retry.
      return Column(
        children: [
          const AppEmptyState(icon: Icons.fitness_center_outlined, message: "No suggestions available right now."),
          TextButton(onPressed: _fetchAiWorkout, child: const Text("Retry", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
        ],
      );
    }
    return Column(
      children: todayWorkouts.map((e) {
        bool done = completedWorkouts.contains(e.name);
        int estBurn = _estimateCalories(e.duration);
        return GestureDetector(
          onTap: () => _showWorkoutDialog(e),
          child: AppCard(
            margin: const EdgeInsets.only(top: AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.md),
            radius: AppRadius.lg,
            border: done ? Border.all(color: AppColors.primary) : null,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(color: const Color(0xFFF0F4C3), borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Icon(e.name.contains("Breathing") ? Icons.air : Icons.nature_people, color: AppColors.primary),
              ),
              title: Text(e.name, style: AppText.cardTitle),
              subtitle: Text("${e.duration} • 🔥 -$estBurn kcal"),
              trailing: const Icon(Icons.chevron_right, size: 16),
            ),
          ),
        );
      }).toList(),
    );
  }

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

        // instructions is a real array on Exercise now — no more regex-splitting
        // a description blob to fake step-by-step text.
        final List<String> steps = workout.instructions;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
          title: Text(workout.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_formatTime(_secondsRemaining), style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: AppColors.primary)),
            const SizedBox(height: AppSpacing.sm),
            Text("Est. Burn: $estBurn kcal", style: const TextStyle(color: AppColors.textMuted, fontSize: 14, fontWeight: FontWeight.bold)),
            const Divider(height: 40),
            SizedBox(
              height: 120,
              child: SingleChildScrollView(
                child: Column(
                  children: steps
                      .map((step) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                              Expanded(child: Text(step.trim(), style: const TextStyle(fontSize: 13, height: 1.4))),
                            ]),
                          ))
                      .toList(),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                _timer?.cancel();
                Navigator.pop(context);
              },
              child: const Text("Exit"),
            ),
            ElevatedButton(
              onPressed: _isTimerActive ? null : startCountdown,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm - 2))),
              child: const Text("Start Workout", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            if (_secondsRemaining == 0)
              ElevatedButton(
                onPressed: () async {
                  setState(() => completedWorkouts.add(workout.name));
                  String dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);
                  try {
                    await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).collection('daily_logs').doc(dateId).set({
                      'total_burned': FieldValue.increment(estBurn),
                      'activities': FieldValue.arrayUnion([
                        {'activity_name': workout.name, 'calories_burned': estBurn, 'logged_at': Timestamp.now()}
                      ]),
                      'last_updated': Timestamp.now(),
                    }, SetOptions(merge: true));
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  } catch (e) {
                    debugPrint("Record Save Error: $e");
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.info),
                child: const Text("Finish & Save", style: TextStyle(color: Colors.white)),
              )
          ],
        );
      }),
    );
  }

  // --- 5. 辅助 UI 工具组件 ---

  Widget _buildStat(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: AppSpacing.xs),
      Text(label, style: AppText.muted),
    ]);
  }

  Widget _buildRecentActivityItem(dynamic activityData) {
    String name = "Activity";
    String info = "";
    if (activityData is Map) {
      name = activityData['activity_name'] ?? "Unknown";
      if (activityData['calories_burned'] != null) {
        info = "${activityData['calories_burned']} kcal burned";
      }
    }
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg - 5),
      radius: AppRadius.lg,
      child: Row(children: [
        const Icon(Icons.check_circle, color: AppColors.primary),
        const SizedBox(width: AppSpacing.lg - 5),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (info.isNotEmpty) Text(info, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
        ),
        const Text("Completed", style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ]),
    );
  }
}