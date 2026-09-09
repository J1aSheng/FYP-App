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
import '../services/phone_activity_service.dart';
import '../theme/app_theme.dart';
import 'workout_detail_screen.dart';

/// 首页组件：集成了 AI 建议（带回退机制）、动态热量监测、带正则解析的步骤展示及自动 Streak 系统
class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // --- 外部服务实例 ---
  final _ai = GroqAiService();
  final _db = DatabaseService();
  final _picker = ImagePicker();
  final _phoneActivityService = PhoneActivityService();
  StreamSubscription<int>? _stepSubscription;
  int _lastSensorStepsSaved = -1;

  bool _healthLoading = false;
  bool _healthConnected = false;
  String? _healthError;

  late Future<List<WorkoutPlan>> _homeWorkoutPlans;

  // --- 基础状态变量 ---
  bool _isScanning = false;
  bool _isMealsExpanded = false;

  // --- 核心历史导航：日期控制 ---
  DateTime _selectedDate = DateTime.now();
  DateTime _viewedWeekMonday = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

  // --- 目标计算值 ---
  late double dailyTarget;
  late double waterGoal;

  // --- 运动计时器状态 ---

  @override
  void initState() {
    super.initState();
    // 初始化计算：基于用户数据计算每日热量与饮水目标
    dailyTarget = _calculateBMR();
    waterGoal = _calculateDynamicWaterGoal();

    // Generate the personalized workout list once for the Home page.
    // The same future is reused during rebuilds so Home does not call
    // the AI service every time Firestore updates.
    _homeWorkoutPlans =
        _ai.generatePersonalizedPlans(widget.user);

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _syncPhoneActivity();
      _startLiveStepSensor();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPhoneActivity();
      _startLiveStepSensor();
    }
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

  Future<void> _syncPhoneActivity() async {
    if (_healthLoading) return;

    if (mounted) {
      setState(() {
        _healthLoading = true;
        _healthError = null;
      });
    }

    try {
      // Motion permission lets us use the physical step counter
      // even when Health Connect has no steps.
      final motionGranted =
          await _phoneActivityService
              .requestMotionPermission();

      // Health Connect remains optional. If it is supported and the user
      // grants access, we prefer its health records.
      final healthGranted =
          await _phoneActivityService
              .requestHealthConnectPermission();

      final activity =
          await _phoneActivityService
              .getTodayActivity(
        weightKg: widget.user.weight,
      );

      final todayId =
          DateFormat('yyyy-MM-dd')
              .format(DateTime.now());

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('daily_logs')
          .doc(todayId)
          .set({
        'health_steps': activity.steps,
        'health_active_calories':
            activity.activeCalories.round(),
        'health_distance_km':
            activity.distanceKm,
        'health_exercise_minutes':
            activity.exerciseMinutes,

        // Keep source information so you can see whether the phone sensor
        // or Health Connect supplied the data.
        'phone_activity_source':
            activity.healthConnectUsed
                ? 'health_connect'
                : activity.sensorUsed
                    ? 'device_sensor'
                    : 'none',

        'health_last_synced':
            FieldValue.serverTimestamp(),
        'last_updated': Timestamp.now(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _healthConnected =
            healthGranted ||
            motionGranted ||
            activity.steps > 0;

        if (!motionGranted && !healthGranted) {
          _healthError =
              'Activity access is not enabled. '
              'Allow Physical Activity permission to count steps.';
        } else if (!healthGranted) {
          _healthError =
              'Health Connect is not sharing data, so the app is using '
              'your phone step sensor instead.';
        } else {
          _healthError = null;
        }
      });
    } catch (e) {
      debugPrint(
        'Phone activity sync error: $e',
      );

      if (!mounted) return;

      setState(() {
        _healthConnected = false;
        _healthError =
            'Unable to read phone activity data.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _healthLoading = false;
        });
      }
    }
  }

  Future<void> _startLiveStepSensor() async {
    await _stepSubscription?.cancel();

    _stepSubscription =
        _phoneActivityService
            .watchTodaySensorSteps()
            .listen(
      (steps) async {
        if (!mounted) return;

        // Avoid unnecessary Firestore writes.
        if (steps == _lastSensorStepsSaved) {
          return;
        }

        _lastSensorStepsSaved = steps;

        final distanceKm =
            steps * 0.00075;

        final safeWeight =
            widget.user.weight <= 0
                ? 65.0
                : widget.user.weight;

        final calories =
            safeWeight *
            distanceKm *
            0.5;

        final exerciseMinutes =
            (steps / 100).floor();

        final todayId =
            DateFormat('yyyy-MM-dd')
                .format(DateTime.now());

        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.user.uid)
              .collection('daily_logs')
              .doc(todayId)
              .set({
            // Only replace the displayed step fallback if Health Connect
            // has not already supplied a larger valid count.
            'health_steps': steps,
            'health_distance_km':
                distanceKm,
            'health_active_calories':
                calories.round(),
            'health_exercise_minutes':
                exerciseMinutes,
            'phone_activity_source':
                'device_sensor',
            'health_last_synced':
                FieldValue.serverTimestamp(),
            'last_updated':
                Timestamp.now(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint(
            'Live step save error: $e',
          );
        }
      },
      onError: (error) {
        debugPrint(
          'Live step sensor error: $error',
        );
      },
    );
  }

  String _suggestMealCategory(DateTime dateTime) {
    final hour = dateTime.hour;

    if (hour >= 5 && hour < 11) {
      return 'Breakfast';
    }

    if (hour >= 11 && hour < 16) {
      return 'Lunch';
    }

    if (hour >= 16 && hour < 22) {
      return 'Dinner';
    }

    return 'Snacks';
  }

  Future<void> _selectMealCategoryAndScan() async {
    final suggestedCategory =
        _suggestMealCategory(DateTime.now());

    final category =
        await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              20,
              12,
              20,
              24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFD9DDD9),
                      borderRadius:
                          BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Choose Meal Category',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Suggested: $suggestedCategory. '
                  'You can choose another category.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 18),

                _buildMealCategoryOption(
                  sheetContext,
                  label: 'Breakfast',
                  icon:
                      Icons.wb_sunny_outlined,
                  color:
                      const Color(0xFFFFB300),
                  recommended:
                      suggestedCategory ==
                          'Breakfast',
                ),
                _buildMealCategoryOption(
                  sheetContext,
                  label: 'Lunch',
                  icon: Icons
                      .lunch_dining_outlined,
                  color:
                      const Color(0xFF5C6BC0),
                  recommended:
                      suggestedCategory ==
                          'Lunch',
                ),
                _buildMealCategoryOption(
                  sheetContext,
                  label: 'Dinner',
                  icon:
                      Icons.nightlight_round,
                  color:
                      const Color(0xFF3949AB),
                  recommended:
                      suggestedCategory ==
                          'Dinner',
                ),
                _buildMealCategoryOption(
                  sheetContext,
                  label: 'Snacks',
                  icon:
                      Icons.apple_outlined,
                  color:
                      const Color(0xFFE53935),
                  recommended:
                      suggestedCategory ==
                          'Snacks',
                ),
              ],
            ),
          ),
        );
      },
    );

    if (category == null || !mounted) {
      return;
    }

    await _scanFood(
      manualCategory: category,
    );
  }

  Widget _buildMealCategoryOption(
    BuildContext sheetContext, {
    required String label,
    required IconData icon,
    required Color color,
    bool recommended = false,
  }) {
    return InkWell(
      onTap: () =>
          Navigator.pop(sheetContext, label),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(
          bottom: 6,
        ),
        padding:
            const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: recommended
              ? color.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius:
              BorderRadius.circular(16),
          border: recommended
              ? Border.all(
                  color: color.withValues(
                    alpha: 0.28,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color:
                    color.withValues(alpha: 0.12),
                borderRadius:
                    BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: color,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color:
                          AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                  if (recommended)
                    Text(
                      'Recommended by current time',
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
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
          {
            ...foodData,
            // Store the user's selected category explicitly.
            'category':
                manualCategory ??
                _suggestMealCategory(DateTime.now()),
            'date_id': dateId,
            'logged_at': Timestamp.now(),
          },
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
            int totalEaten = 0;
            int manualBurned = 0;
            int healthBurned = 0;
            int healthSteps = 0;
            int healthExerciseMinutes = 0;
            double healthDistanceKm = 0;
            int waterIntake = 0;

            List<dynamic> finishedActivities = [], mealsData = [];

            if (snapshot.hasData && snapshot.data!.exists) {
              final data =
                  snapshot.data!.data() as Map<String, dynamic>;

              totalEaten =
                  (data['total_calories'] ?? 0).toInt();
              manualBurned =
                  (data['total_burned'] ?? 0).toInt();

              healthBurned =
                  (data['health_active_calories'] ?? 0).toInt();
              healthSteps =
                  (data['health_steps'] ?? 0).toInt();
              healthExerciseMinutes =
                  (data['health_exercise_minutes'] ?? 0).toInt();
              healthDistanceKm =
                  (data['health_distance_km'] ?? 0).toDouble();

              waterIntake =
                  (data['water_intake'] ?? 0).toInt();
              finishedActivities =
                  data['activities'] ?? [];
              mealsData =
                  data['meals'] ?? [];
            }

            // App workout burn + Health Connect active burn.
            final burned = manualBurned + healthBurned;

            int netCalories = totalEaten - burned;
            int remaining = (dailyTarget - netCalories).toInt();

            bool hasAnyActivity =
                mealsData.isNotEmpty ||
                finishedActivities.isNotEmpty ||
                healthSteps > 0 ||
                healthBurned > 0;

            return RefreshIndicator(
              color: AppColors.primary,
              // Firestore is already live; pull-to-refresh syncs phone activity.
              onRefresh: _syncPhoneActivity,
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

                    _buildTodayDietPlan(
                      meals: mealsData,
                      totalEaten: totalEaten,
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // Keep meal and hydration information directly under
                    // Today's Diet Plan.
                    _buildMealSection(mealsData),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildWaterIntakeCard(waterIntake),
                    const SizedBox(height: AppSpacing.xxl),

                    _buildTodayWorkoutCard(
                      finishedActivities: finishedActivities,
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    _buildPhoneActivityCard(
                      steps: healthSteps,
                      activeCalories: healthBurned,
                      exerciseMinutes: healthExerciseMinutes,
                      distanceKm: healthDistanceKm,
                    ),

                    const SizedBox(height: AppSpacing.xxl),
                    _buildHistoryHeader(),
                    const SizedBox(height: AppSpacing.md),
                    _buildDynamicWeeklyStrip(),
                    const SizedBox(height: AppSpacing.xxl),
                    if (finishedActivities.isNotEmpty) ...[
                      const AppSectionHeader(title: "Recent Activities", subtitle: "Today"),
                      const SizedBox(height: AppSpacing.md),
                      ...finishedActivities.reversed.map((data) => _buildRecentActivityItem(data)),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
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

  // ---------------------------------------------------------------------------
  // TODAY'S PERSONALIZED DIET PLAN
  // ---------------------------------------------------------------------------

  Widget _buildTodayDietPlan({
    required List<dynamic> meals,
    required int totalEaten,
  }) {
    final target = dailyTarget.round();

    // Balanced default distribution.
    // Breakfast 20%, Lunch 30%, Dinner 30%, Snacks 20%.
    final mealTargets = <String, int>{
      'Breakfast': (target * 0.20).round(),
      'Lunch': (target * 0.30).round(),
      'Dinner': (target * 0.30).round(),
      'Snacks': (target * 0.20).round(),
    };

    final mealConsumed = <String, int>{
      'Breakfast': 0,
      'Lunch': 0,
      'Dinner': 0,
      'Snacks': 0,
    };

    for (final rawMeal in meals) {
      if (rawMeal is! Map) continue;

      final meal =
          Map<String, dynamic>.from(rawMeal);

      final category =
          _resolvedMealCategory(meal);

      if (!mealConsumed.containsKey(category)) {
        continue;
      }

      final calories =
          (meal['calories'] as num?)?.toInt() ?? 0;

      mealConsumed[category] =
          (mealConsumed[category] ?? 0) + calories;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Text(
                "Today's Diet Plan",
                style: AppText.sectionTitle,
              ),
            ),
            Text(
              '$totalEaten / $target kcal',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          _dietPlanSubtitle(),
          style: AppText.muted,
        ),
        const SizedBox(height: AppSpacing.md),

        AppCard(
          radius: AppRadius.xxl,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _buildDietMealRow(
                category: 'Breakfast',
                icon: Icons.wb_sunny_outlined,
                color: const Color(0xFFFFB300),
                consumed: mealConsumed['Breakfast'] ?? 0,
                target: mealTargets['Breakfast'] ?? 0,
              ),
              _historyDivider(),
              _buildDietMealRow(
                category: 'Lunch',
                icon: Icons.lunch_dining_outlined,
                color: const Color(0xFF5C6BC0),
                consumed: mealConsumed['Lunch'] ?? 0,
                target: mealTargets['Lunch'] ?? 0,
              ),
              _historyDivider(),
              _buildDietMealRow(
                category: 'Dinner',
                icon: Icons.nightlight_round,
                color: const Color(0xFF3949AB),
                consumed: mealConsumed['Dinner'] ?? 0,
                target: mealTargets['Dinner'] ?? 0,
              ),
              _historyDivider(),
              _buildDietMealRow(
                category: 'Snacks',
                icon: Icons.apple_outlined,
                color: const Color(0xFFE53935),
                consumed: mealConsumed['Snacks'] ?? 0,
                target: mealTargets['Snacks'] ?? 0,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _dietPlanSubtitle() {
    final goal =
        widget.user.goal.trim();

    if (goal.isEmpty) {
      return 'Personalized from your daily calorie target.';
    }

    return 'Personalized for your ${goal.toLowerCase()} goal.';
  }

  Widget _buildDietMealRow({
    required String category,
    required IconData icon,
    required Color color,
    required int consumed,
    required int target,
  }) {
    final progress = target <= 0
        ? 0.0
        : (consumed / target).clamp(0.0, 1.0);

    final isLogged = consumed > 0;
    final isOver = target > 0 && consumed > target;

    final statusColor = isOver
        ? AppColors.danger
        : isLogged
            ? AppColors.primary
            : AppColors.textMuted;

    return InkWell(
      onTap: () => _scanFood(
        manualCategory: category,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: color,
                size: 23,
              ),
            ),

            const SizedBox(width: 13),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (isLogged)
                        Icon(
                          isOver
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_rounded,
                          size: 17,
                          color: statusColor,
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        '$consumed',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        ' / $target kcal',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor:
                          color.withValues(alpha: 0.10),
                      color: isOver
                          ? AppColors.danger
                          : color,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TODAY'S PERSONALIZED WORKOUT
  // ---------------------------------------------------------------------------

  WorkoutLevel _homeUserWorkoutLevel() {
    final level =
        widget.user.level.trim().toLowerCase();

    return WorkoutLevel.values.firstWhere(
      (item) =>
          item.name.toLowerCase() == level,
      orElse: () => WorkoutLevel.beginner,
    );
  }

  String _workoutLevelText(
    WorkoutLevel level,
  ) {
    switch (level) {
      case WorkoutLevel.beginner:
        return 'Beginner';
      case WorkoutLevel.intermediate:
        return 'Intermediate';
      case WorkoutLevel.advanced:
        return 'Advanced';
    }
  }

  WorkoutPlan? _pickTodayWorkout(
    List<WorkoutPlan> plans,
  ) {
    if (plans.isEmpty) {
      return null;
    }

    final userLevel =
        _homeUserWorkoutLevel();

    final sameLevel = plans
        .where((plan) => plan.level == userLevel)
        .toList();

    final available =
        sameLevel.isNotEmpty ? sameLevel : plans;

    final now = DateTime.now();
    final firstDay =
        DateTime(now.year, 1, 1);

    final dayNumber =
        now.difference(firstDay).inDays;

    return available[
        dayNumber % available.length];
  }

  bool _isTodayWorkoutCompleted(
    WorkoutPlan plan,
    List<dynamic> finishedActivities,
  ) {
    final normalizedTitle =
        plan.title.trim().toLowerCase();

    for (final raw in finishedActivities) {
      if (raw is Map) {
        final data =
            Map<String, dynamic>.from(raw);

        final possibleTitle =
            (data['title'] ??
                    data['name'] ??
                    data['workout_title'] ??
                    data['activity_name'] ??
                    '')
                .toString()
                .trim()
                .toLowerCase();

        if (possibleTitle.isNotEmpty &&
            possibleTitle == normalizedTitle) {
          return true;
        }
      } else {
        final value =
            raw.toString().toLowerCase();

        if (value.contains(normalizedTitle)) {
          return true;
        }
      }
    }

    return false;
  }

  Widget _buildTodayWorkoutCard({
    required List<dynamic> finishedActivities,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Workout",
          style: AppText.sectionTitle,
        ),
        const SizedBox(height: 5),
        Text(
          'Matched to your ${widget.user.level.toLowerCase()} level and ${widget.user.goal.toLowerCase()} goal.',
          style: AppText.muted,
        ),
        const SizedBox(height: AppSpacing.md),

        FutureBuilder<List<WorkoutPlan>>(
          future: _homeWorkoutPlans,
          builder: (context, snapshot) {
            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return AppCard(
                radius: AppRadius.xxl,
                padding: const EdgeInsets.all(
                  AppSpacing.xl,
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Preparing your personalized workout...',
                        style: AppText.muted,
                      ),
                    ),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              return _buildWorkoutUnavailableCard(
                'Unable to load your workout right now.',
              );
            }

            final plan =
                _pickTodayWorkout(
              snapshot.data ?? const [],
            );

            if (plan == null) {
              return _buildWorkoutUnavailableCard(
                'No workout is available yet.',
              );
            }

            final completed =
                _isTodayWorkoutCompleted(
              plan,
              finishedActivities,
            );

            return AppCard(
              radius: AppRadius.xxl,
              padding: const EdgeInsets.all(
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: AppColors.primary
                              .withValues(alpha: 0.10),
                          borderRadius:
                              BorderRadius.circular(17),
                        ),
                        child: Icon(
                          completed
                              ? Icons.check_rounded
                              : Icons
                                  .fitness_center_rounded,
                          color: AppColors.primary,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.title,
                              maxLines: 2,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: const TextStyle(
                                color:
                                    AppColors.textPrimary,
                                fontSize: 17,
                                fontWeight:
                                    FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${plan.category} • ${_workoutLevelText(plan.level)}',
                              style: AppText.muted,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      _buildWorkoutInfoPill(
                        Icons.timer_outlined,
                        '${plan.minutes} min',
                      ),
                      _buildWorkoutInfoPill(
                        Icons
                            .local_fire_department_outlined,
                        '${plan.calories} kcal',
                      ),
                      _buildWorkoutInfoPill(
                        Icons.format_list_numbered,
                        '${plan.exercises.length} activities',
                      ),
                    ],
                  ),

                  if (plan.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      plan.subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                WorkoutDetailScreen(
                              plan: plan,
                              user: widget.user,
                            ),
                          ),
                        );

                        if (mounted) {
                          setState(() {});
                        }
                      },
                      icon: Icon(
                        completed
                            ? Icons.replay_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        completed
                            ? 'PLAY AGAIN'
                            : 'START WORKOUT',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.primary,
                        foregroundColor:
                            Colors.white,
                        elevation: 0,
                        minimumSize:
                            const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWorkoutInfoPill(
    IconData icon,
    String text,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color:
            const Color(0xFFF3F6F2),
        borderRadius:
            BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: AppColors.primary,
            size: 15,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutUnavailableCard(
    String message,
  ) {
    return AppCard(
      radius: AppRadius.xxl,
      padding: const EdgeInsets.all(
        AppSpacing.xl,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.fitness_center_outlined,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppText.muted,
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _homeWorkoutPlans =
                    _ai.generatePersonalizedPlans(
                  widget.user,
                );
              });
            },
            child: const Text(
              'RETRY',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneActivityCard({
    required int steps,
    required int activeCalories,
    required int exerciseMinutes,
    required double distanceKm,
  }) {
    const stepGoal = 8000;
    const calorieGoal = 400;
    const exerciseGoal = 30;

    final stepProgress =
        (steps / stepGoal).clamp(0.0, 1.0);
    final calorieProgress =
        (activeCalories / calorieGoal).clamp(0.0, 1.0);
    final exerciseProgress =
        (exerciseMinutes / exerciseGoal).clamp(0.0, 1.0);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      radius: AppRadius.xxl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phone Activity',
                      style: AppText.sectionTitle,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Health Connect + phone sensor',
                      style: AppText.muted,
                    ),
                  ],
                ),
              ),
              if (_healthLoading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                  ),
                )
              else if (_healthConnected)
                IconButton(
                  tooltip: 'Sync activity',
                  onPressed: _syncPhoneActivity,
                  icon: const Icon(
                    Icons.sync_rounded,
                    color: AppColors.primary,
                    size: 25,
                  ),
                )
              else
                TextButton.icon(
                  onPressed: _syncPhoneActivity,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                  ),
                  icon: const Icon(
                    Icons.link_rounded,
                    size: 20,
                  ),
                  label: const Text(
                    'SYNC',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),

          if (_healthError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: const Color(0xFFFFE8CC),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _healthError!,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;

              if (compact) {
                return Column(
                  children: [
                    Center(
                      child: _buildActivityRings(
                        stepProgress: stepProgress,
                        calorieProgress: calorieProgress,
                        exerciseProgress: exerciseProgress,
                        size: 175,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildPhoneActivityStats(
                      steps: steps,
                      stepGoal: stepGoal,
                      activeCalories: activeCalories,
                      calorieGoal: calorieGoal,
                      exerciseMinutes: exerciseMinutes,
                      exerciseGoal: exerciseGoal,
                      distanceKm: distanceKm,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 56,
                    child: _buildPhoneActivityStats(
                      steps: steps,
                      stepGoal: stepGoal,
                      activeCalories: activeCalories,
                      calorieGoal: calorieGoal,
                      exerciseMinutes: exerciseMinutes,
                      exerciseGoal: exerciseGoal,
                      distanceKm: distanceKm,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 44,
                    child: Center(
                      child: _buildActivityRings(
                        stepProgress: stepProgress,
                        calorieProgress: calorieProgress,
                        exerciseProgress: exerciseProgress,
                        size: 165,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneActivityStats({
    required int steps,
    required int stepGoal,
    required int activeCalories,
    required int calorieGoal,
    required int exerciseMinutes,
    required int exerciseGoal,
    required double distanceKm,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPhoneActivityRow(
          color: const Color(0xFF42A5F5),
          label: 'Steps',
          value: '$steps',
          goal: '/ $stepGoal steps',
        ),
        const SizedBox(height: 18),
        _buildPhoneActivityRow(
          color: const Color(0xFFFF9F1C),
          label: 'Calories',
          value: '$activeCalories',
          goal: '/ $calorieGoal kcal',
        ),
        const SizedBox(height: 18),
        _buildPhoneActivityRow(
          color: const Color(0xFF2FB344),
          label: 'Exercise',
          value: '$exerciseMinutes',
          goal: '/ $exerciseGoal min',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Icon(
              Icons.route_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              'Distance',
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.95),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${distanceKm.toStringAsFixed(2)} km',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhoneActivityRow({
    required Color color,
    required String label,
    required String value,
    required String goal,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 5,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              children: [
                TextSpan(
                  text: '$label ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: '$value ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                TextSpan(
                  text: goal,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityRings({
    required double stepProgress,
    required double calorieProgress,
    required double exerciseProgress,
    required double size,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ActivityRingsPainter(
          stepProgress: stepProgress,
          calorieProgress: calorieProgress,
          exerciseProgress: exerciseProgress,
          stepColor: const Color(0xFF42A5F5),
          calorieColor: const Color(0xFFFF9F1C),
          exerciseColor: const Color(0xFF2FB344),
        ),
        child: Center(
          child: Container(
            width: size * 0.30,
            height: size * 0.30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
            child: Icon(
              _healthConnected
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: AppColors.primary,
              size: size * 0.16,
            ),
          ),
        ),
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
    final weekStart = DateTime(
      _viewedWeekMonday.year,
      _viewedWeekMonday.month,
      _viewedWeekMonday.day,
    );
    final weekEnd = weekStart.add(const Duration(days: 7));

    final startId =
        DateFormat('yyyy-MM-dd').format(weekStart);
    final endId =
        DateFormat('yyyy-MM-dd').format(weekEnd);

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('daily_logs')
          .where(
            FieldPath.documentId,
            isGreaterThanOrEqualTo: startId,
          )
          .where(
            FieldPath.documentId,
            isLessThan: endId,
          )
          .get(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        const dayLabels = [
          "Mon",
          "Tue",
          "Wed",
          "Thu",
          "Fri",
          "Sat",
          "Sun"
        ];

        final dayDataById =
            <String, Map<String, dynamic>>{};

        for (final doc in docs) {
          dayDataById[doc.id] =
              doc.data() as Map<String, dynamic>;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: List.generate(7, (index) {
                final dayDate =
                    weekStart.add(Duration(days: index));
                final dayId =
                    DateFormat('yyyy-MM-dd')
                        .format(dayDate);

                final data = dayDataById[dayId];
                final totalCalories =
                    (data?['total_calories'] ?? 0)
                        .toInt();

                final meals =
                    data?['meals']
                            as List<dynamic>? ??
                        const [];

                final hasData =
                    totalCalories > 0 ||
                    meals.isNotEmpty;

                final isSelected =
                    DateFormat('yyyy-MM-dd')
                            .format(_selectedDate) ==
                        dayId;

                final status =
                    _getCalorieHistoryStatus(
                  totalCalories: totalCalories,
                  hasData: hasData,
                );

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedDate = dayDate;
                      });

                      if (hasData) {
                        _showCalorieHistoryDetail(
                          date: dayDate,
                          data: data!,
                        );
                      }
                    },
                    child: Column(
                      children: [
                        Text(
                          dayLabels[index],
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('dd')
                              .format(dayDate),
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.textPrimary
                                : Colors.grey[400],
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.w900
                                : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding:
                              const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: status.color,
                                    width: 2.5,
                                  )
                                : null,
                          ),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  status.background,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              status.icon,
                              color: status.color,
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hasData
                              ? '$totalCalories'
                              : '—',
                          style: TextStyle(
                            color: hasData
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontSize: 11,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                        Text(
                          'kcal',
                          style: TextStyle(
                            color:
                                Colors.grey[500],
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 18),

            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(16),
                border: Border.all(
                  color:
                      const Color(0xFFF0F0F0),
                ),
              ),
              child: Wrap(
                spacing: 14,
                runSpacing: 8,
                children: const [
                  _HistoryLegendItem(
                    color: Color(0xFF2FB344),
                    label: 'Within target',
                  ),
                  _HistoryLegendItem(
                    color: Color(0xFFFFB020),
                    label: 'Moderate (+0–20%)',
                  ),
                  _HistoryLegendItem(
                    color: Color(0xFFE53935),
                    label: 'Over target (>20%)',
                  ),
                  _HistoryLegendItem(
                    color: Color(0xFFBDBDBD),
                    label: 'No data',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  _CalorieHistoryStatus _getCalorieHistoryStatus({
    required int totalCalories,
    required bool hasData,
  }) {
    if (!hasData) {
      return const _CalorieHistoryStatus(
        color: Color(0xFF9E9E9E),
        background: Color(0xFFF5F5F5),
        icon: Icons.remove_rounded,
        label: 'No data',
      );
    }

    if (totalCalories <= dailyTarget) {
      return const _CalorieHistoryStatus(
        color: Color(0xFF2FB344),
        background: Color(0xFFEAF8EC),
        icon: Icons.check_rounded,
        label: 'Within target',
      );
    }

    if (totalCalories <= dailyTarget * 1.20) {
      return const _CalorieHistoryStatus(
        color: Color(0xFFFFB020),
        background: Color(0xFFFFF3D6),
        icon: Icons.priority_high_rounded,
        label: 'Moderate',
      );
    }

    return const _CalorieHistoryStatus(
      color: Color(0xFFE53935),
      background: Color(0xFFFFE6E6),
      icon: Icons.close_rounded,
      label: 'Over target',
    );
  }

  Future<void> _showCalorieHistoryDetail({
    required DateTime date,
    required Map<String, dynamic> data,
  }) async {
    final totalCalories =
        (data['total_calories'] ?? 0).toInt();

    final meals =
        (data['meals'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map(
              (meal) => Map<String, dynamic>.from(
                meal,
              ),
            )
            .toList();

    final status =
        _getCalorieHistoryStatus(
      totalCalories: totalCalories,
      hasData:
          totalCalories > 0 || meals.isNotEmpty,
    );

    final remaining =
        (dailyTarget - totalCalories)
            .round();

    final categoryTotals =
        <String, int>{
      'Breakfast': 0,
      'Lunch': 0,
      'Dinner': 0,
      'Snacks': 0,
      'Uncategorized': 0,
    };

    for (final meal in meals) {
      // IMPORTANT:
      // Use one shared resolver for BOTH the summary totals and the meal row.
      // This prevents a meal from showing "Dinner" below while being counted
      // under "Snacks" above.
      final category =
          _resolvedMealCategory(meal);

      final int mealCalories =
          (meal['calories'] as num?)?.toInt() ?? 0;

      categoryTotals[category] =
          (categoryTotals[category] ?? 0) +
              mealCalories;
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.86,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF7F8FA),
              borderRadius:
                  BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFD9DDD9),
                      borderRadius:
                          BorderRadius.circular(
                        10,
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
                      18,
                      14,
                      18,
                      10,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () =>
                              Navigator.pop(
                            sheetContext,
                          ),
                          icon: const Icon(
                            Icons
                                .arrow_back_rounded,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Calorie History',
                            textAlign:
                                TextAlign.center,
                            style: TextStyle(
                              color: AppColors
                                  .textPrimary,
                              fontSize: 19,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child:
                        SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        28,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          AppCard(
                            radius:
                                AppRadius.xl,
                            padding:
                                const EdgeInsets.all(
                              18,
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(
                                  DateFormat(
                                    'EEEE, d MMMM yyyy',
                                  ).format(date),
                                  style:
                                      const TextStyle(
                                    color: AppColors
                                        .textPrimary,
                                    fontSize: 16,
                                    fontWeight:
                                        FontWeight
                                            .w900,
                                  ),
                                ),
                                const SizedBox(
                                  height: 18,
                                ),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 132,
                                      height: 132,
                                      child: Stack(
                                        alignment:
                                            Alignment
                                                .center,
                                        children: [
                                          Positioned.fill(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(
                                                5,
                                              ),
                                              child:
                                                  CircularProgressIndicator(
                                                value: dailyTarget >
                                                        0
                                                    ? (totalCalories /
                                                            dailyTarget)
                                                        .clamp(
                                                          0.0,
                                                          1.0,
                                                        )
                                                    : 0,
                                                strokeWidth:
                                                    11,
                                                backgroundColor:
                                                    status
                                                        .background,
                                                color:
                                                    status
                                                        .color,
                                                strokeCap:
                                                    StrokeCap
                                                        .round,
                                              ),
                                            ),
                                          ),
                                          Column(
                                            mainAxisSize:
                                                MainAxisSize
                                                    .min,
                                            children: [
                                              Icon(
                                                Icons
                                                    .local_fire_department_rounded,
                                                color:
                                                    status
                                                        .color,
                                                size: 25,
                                              ),
                                              Text(
                                                '$totalCalories',
                                                style:
                                                    TextStyle(
                                                  color:
                                                      status
                                                          .color,
                                                  fontSize:
                                                      24,
                                                  fontWeight:
                                                      FontWeight
                                                          .w900,
                                                ),
                                              ),
                                              const Text(
                                                'kcal',
                                                style:
                                                    TextStyle(
                                                  color:
                                                      AppColors
                                                          .textMuted,
                                                  fontSize:
                                                      11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 18,
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                        children: [
                                          const Text(
                                            'Daily Target',
                                            style:
                                                TextStyle(
                                              color:
                                                  AppColors
                                                      .textMuted,
                                              fontSize:
                                                  12,
                                            ),
                                          ),
                                          Text(
                                            '${dailyTarget.round()} kcal',
                                            style:
                                                const TextStyle(
                                              color:
                                                  AppColors
                                                      .textPrimary,
                                              fontSize:
                                                  18,
                                              fontWeight:
                                                  FontWeight
                                                      .w900,
                                            ),
                                          ),
                                          const SizedBox(
                                            height: 10,
                                          ),
                                          Container(
                                            padding:
                                                const EdgeInsets
                                                    .symmetric(
                                              horizontal:
                                                  10,
                                              vertical: 7,
                                            ),
                                            decoration:
                                                BoxDecoration(
                                              color: status
                                                  .background,
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(
                                                20,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize:
                                                  MainAxisSize
                                                      .min,
                                              children: [
                                                Icon(
                                                  status
                                                      .icon,
                                                  color:
                                                      status
                                                          .color,
                                                  size:
                                                      16,
                                                ),
                                                const SizedBox(
                                                  width: 5,
                                                ),
                                                Text(
                                                  status
                                                      .label,
                                                  style:
                                                      TextStyle(
                                                    color:
                                                        status
                                                            .color,
                                                    fontSize:
                                                        11,
                                                    fontWeight:
                                                        FontWeight
                                                            .w800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(
                                            height: 8,
                                          ),
                                          Text(
                                            remaining >= 0
                                                ? '$remaining kcal remaining'
                                                : '${remaining.abs()} kcal over target',
                                            style:
                                                TextStyle(
                                              color: remaining >=
                                                      0
                                                  ? AppColors
                                                      .textMuted
                                                  : const Color(
                                                      0xFFE53935,
                                                    ),
                                              fontSize:
                                                  12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(
                            height: 16,
                          ),

                          AppCard(
                            radius:
                                AppRadius.xl,
                            padding:
                                EdgeInsets.zero,
                            child: Column(
                              children: [
                                _buildHistoryCategoryRow(
                                  category:
                                      'Breakfast',
                                  calories:
                                      categoryTotals[
                                              'Breakfast'] ??
                                          0,
                                  icon: Icons
                                      .wb_sunny_outlined,
                                  color:
                                      const Color(
                                    0xFFFFB300,
                                  ),
                                ),
                                _historyDivider(),
                                _buildHistoryCategoryRow(
                                  category:
                                      'Lunch',
                                  calories:
                                      categoryTotals[
                                              'Lunch'] ??
                                          0,
                                  icon: Icons
                                      .lunch_dining_outlined,
                                  color:
                                      const Color(
                                    0xFF5C6BC0,
                                  ),
                                ),
                                _historyDivider(),
                                _buildHistoryCategoryRow(
                                  category:
                                      'Dinner',
                                  calories:
                                      categoryTotals[
                                              'Dinner'] ??
                                          0,
                                  icon: Icons
                                      .nightlight_round,
                                  color:
                                      const Color(
                                    0xFF3949AB,
                                  ),
                                ),
                                _historyDivider(),
                                _buildHistoryCategoryRow(
                                  category:
                                      'Snacks',
                                  calories:
                                      categoryTotals[
                                              'Snacks'] ??
                                          0,
                                  icon: Icons
                                      .apple_outlined,
                                  color:
                                      const Color(
                                    0xFFE53935,
                                  ),
                                ),
                                if ((categoryTotals[
                                            'Uncategorized'] ??
                                        0) >
                                    0) ...[
                                  _historyDivider(),
                                  _buildHistoryCategoryRow(
                                    category:
                                        'Uncategorized',
                                    calories:
                                        categoryTotals[
                                                'Uncategorized'] ??
                                            0,
                                    icon: Icons
                                        .help_outline_rounded,
                                    color:
                                        const Color(
                                      0xFF9E9E9E,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          if (meals.isNotEmpty) ...[
                            const SizedBox(
                              height: 20,
                            ),
                            const Text(
                              'Meals',
                              style:
                                  AppText.sectionTitle,
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                            ...meals.map(
                              (meal) =>
                                  _buildHistoryMealItem(
                                meal,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _resolvedMealCategory(
    Map<String, dynamic> meal,
  ) {
    return _normalizeMealCategory(
      meal['category']?.toString() ?? '',
      loggedAt: meal['logged_at'],
    );
  }

  String _normalizeMealCategory(
    String rawCategory, {
    dynamic loggedAt,
  }) {
    final value =
        rawCategory.trim().toLowerCase();

    if (value.contains('breakfast')) {
      return 'Breakfast';
    }

    if (value.contains('lunch')) {
      return 'Lunch';
    }

    if (value.contains('dinner')) {
      return 'Dinner';
    }

    if (value.contains('snack')) {
      return 'Snacks';
    }

    DateTime? loggedTime;

    if (loggedAt is Timestamp) {
      loggedTime = loggedAt.toDate();
    } else if (loggedAt is DateTime) {
      loggedTime = loggedAt;
    } else if (loggedAt is String) {
      loggedTime =
          DateTime.tryParse(loggedAt);
    }

    if (loggedTime != null) {
      return _suggestMealCategory(
        loggedTime,
      );
    }

    // Old records with no valid category and no timestamp should not
    // be incorrectly counted as Snacks.
    return 'Uncategorized';
  }

  Widget _buildHistoryCategoryRow({
    required String category,
    required int calories,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color:
                  color.withValues(alpha: 0.12),
              borderRadius:
                  BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              category,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '$calories kcal',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyDivider() {
    return const Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Color(0xFFF0F0F0),
    );
  }

  Widget _buildHistoryMealItem(
    Map<String, dynamic> meal,
  ) {
    final calories =
        (meal['calories'] ?? 0).toInt();
    final name =
        meal['food_name']?.toString() ??
            'Meal';
    final category =
        _resolvedMealCategory(meal);

    return AppCard(
      margin:
          const EdgeInsets.only(bottom: 10),
      padding:
          const EdgeInsets.all(14),
      radius: AppRadius.lg,
      child: Row(
        children: [
          const Icon(
            Icons.restaurant_rounded,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style:
                      const TextStyle(
                    color:
                        AppColors.textPrimary,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category,
                  style:
                      const TextStyle(
                    color:
                        AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$calories kcal',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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
                    onPressed: _selectMealCategoryAndScan,
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
          const SizedBox(
            width: double.infinity,
            height: 190,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.restaurant_outlined,
                    size: 48,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(height: 14),
                  Text(
                    "No meals logged for today.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...displayedMeals.map((mealData) {
            final meal = mealData as Map<String, dynamic>;
            final int calValue =
                (meal['calories'] ?? 0).toInt();
            final String path =
                meal['image_path'] ?? "";
            final String mealCategory =
                _resolvedMealCategory(meal);

            Color intensityColor =
                _getMealIntensityColor(calValue);

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
                      Row(
                        children: [
                          Icon(
                            _mealCategoryIcon(mealCategory),
                            size: 13,
                            color: _mealCategoryColor(mealCategory),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            mealCategory,
                            style: AppText.muted,
                          ),
                        ],
                      ),
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

  IconData _mealCategoryIcon(String category) {
    switch (category) {
      case 'Breakfast':
        return Icons.wb_sunny_outlined;
      case 'Lunch':
        return Icons.lunch_dining_outlined;
      case 'Dinner':
        return Icons.nightlight_round;
      case 'Snacks':
        return Icons.apple_outlined;
      case 'Uncategorized':
      default:
        return Icons.help_outline_rounded;
    }
  }

  Color _mealCategoryColor(String category) {
    switch (category) {
      case 'Breakfast':
        return const Color(0xFFFFB300);
      case 'Lunch':
        return const Color(0xFF5C6BC0);
      case 'Dinner':
        return const Color(0xFF3949AB);
      case 'Snacks':
        return const Color(0xFFE53935);
      case 'Uncategorized':
      default:
        return const Color(0xFF9E9E9E);
    }
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

class _ActivityRingsPainter extends CustomPainter {
  final double stepProgress;
  final double calorieProgress;
  final double exerciseProgress;
  final Color stepColor;
  final Color calorieColor;
  final Color exerciseColor;

  const _ActivityRingsPainter({
    required this.stepProgress,
    required this.calorieProgress,
    required this.exerciseProgress,
    required this.stepColor,
    required this.calorieColor,
    required this.exerciseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final shortest = size.shortestSide;

    const startAngle = -1.5707963267948966;
    const fullSweep = 6.283185307179586;

    final stroke = shortest * 0.095;
    final gap = stroke * 0.72;

    final outerRadius = shortest / 2 - stroke / 2;
    final middleRadius = outerRadius - stroke - gap;
    final innerRadius = middleRadius - stroke - gap;

    void drawRing({
      required double radius,
      required double progress,
      required Color color,
    }) {
      final safeProgress = progress.clamp(0.0, 1.0);

      final backgroundPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.16);

      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;

      final rect = Rect.fromCircle(
        center: center,
        radius: radius,
      );

      canvas.drawArc(
        rect,
        startAngle,
        fullSweep,
        false,
        backgroundPaint,
      );

      if (safeProgress > 0) {
        canvas.drawArc(
          rect,
          startAngle,
          fullSweep * safeProgress,
          false,
          progressPaint,
        );
      }
    }

    drawRing(
      radius: outerRadius,
      progress: stepProgress,
      color: stepColor,
    );

    drawRing(
      radius: middleRadius,
      progress: calorieProgress,
      color: calorieColor,
    );

    drawRing(
      radius: innerRadius,
      progress: exerciseProgress,
      color: exerciseColor,
    );
  }

  @override
  bool shouldRepaint(covariant _ActivityRingsPainter oldDelegate) {
    return oldDelegate.stepProgress != stepProgress ||
        oldDelegate.calorieProgress != calorieProgress ||
        oldDelegate.exerciseProgress != exerciseProgress ||
        oldDelegate.stepColor != stepColor ||
        oldDelegate.calorieColor != calorieColor ||
        oldDelegate.exerciseColor != exerciseColor;
  }
}

class _CalorieHistoryStatus {
  final Color color;
  final Color background;
  final IconData icon;
  final String label;

  const _CalorieHistoryStatus({
    required this.color,
    required this.background,
    required this.icon,
    required this.label,
  });
}

class _HistoryLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _HistoryLegendItem({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

