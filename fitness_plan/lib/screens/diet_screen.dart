import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/user_model.dart';

const _kGreen = Color(0xFF2E7D32);
const _kDarkGreen = Color(0xFF1B5E20);
const _kInk = Color(0xFF191C19);
const _kMuted = Color(0xFF747972);
const _kBg = Color(0xFFF7FAF6);
const _kBorder = Color(0xFFE6EBE5);

class DietScreen extends StatelessWidget {
  final UserModel user;

  const DietScreen({
    super.key,
    required this.user,
  });

  double _dailyTarget() {
    final age = user.age == 0 ? 25 : user.age;

    double bmr = user.gender.toLowerCase() == 'male'
        ? 10 * user.weight +
            6.25 * user.height -
            5 * age +
            5
        : 10 * user.weight +
            6.25 * user.height -
            5 * age -
            161;

    double activityFactor = 1.2;
    final level = user.level.toLowerCase();

    if (level.contains('beginner') ||
        level.contains('light')) {
      activityFactor = 1.375;
    } else if (level.contains('intermediate') ||
        level.contains('moderat')) {
      activityFactor = 1.55;
    } else if (level.contains('advanced') ||
        level.contains('active') ||
        level.contains('pro')) {
      activityFactor = 1.725;
    }

    bmr *= activityFactor;

    final goal = user.goal.toLowerCase();

    if (goal.contains('lose')) {
      return math.max(1200, bmr - 500);
    }

    if (goal.contains('muscle') ||
        goal.contains('build') ||
        goal.contains('gain')) {
      return bmr + 300;
    }

    return bmr;
  }

  double _waterGoal() {
    var result = user.weight * 30.0;

    if (user.gender.toLowerCase() == 'male') {
      result += 400;
    }

    return result;
  }

  String _todayId() {
    final now = DateTime.now();

    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _meals(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map(
          (meal) => Map<String, dynamic>.from(meal),
        )
        .toList();
  }

  int _mealCalories(
    List<Map<String, dynamic>> meals,
    String category,
  ) {
    return meals
        .where(
          (meal) => _resolvedCategory(meal) == category,
        )
        .fold<int>(
          0,
          (total, meal) =>
              total +
              ((meal['calories'] as num?)?.toInt() ?? 0),
        );
  }

  String _resolvedCategory(
    Map<String, dynamic> meal,
  ) {
    final raw = meal['category']?.toString().trim();

    if (raw != null && raw.isNotEmpty) {
      final lower = raw.toLowerCase();

      if (lower.contains('breakfast')) {
        return 'Breakfast';
      }
      if (lower.contains('lunch')) {
        return 'Lunch';
      }
      if (lower.contains('dinner')) {
        return 'Dinner';
      }
      if (lower.contains('snack')) {
        return 'Snacks';
      }
    }

    final loggedAt = meal['logged_at'];

    if (loggedAt is Timestamp) {
      final hour = loggedAt.toDate().hour;

      if (hour >= 5 && hour < 11) {
        return 'Breakfast';
      }
      if (hour >= 11 && hour < 16) {
        return 'Lunch';
      }
      if (hour >= 17 && hour < 22) {
        return 'Dinner';
      }
    }

    return 'Snacks';
  }

  @override
  Widget build(BuildContext context) {
    final target = _dailyTarget();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: _kBg,
        surfaceTintColor: _kBg,
        elevation: 0,
        title: const Text(
          'DIET',
          style: TextStyle(
            color: _kInk,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: StreamBuilder<
          DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('daily_logs')
            .doc(_todayId())
            .snapshots(),
        builder: (context, snapshot) {
          final data =
              snapshot.data?.data() ?? <String, dynamic>{};

          final meals = _meals(data['meals']);

          final consumed =
              (data['total_calories'] as num?)?.toInt() ??
                  meals.fold<int>(
                    0,
                    (total, meal) =>
                        total +
                        ((meal['calories'] as num?)
                                ?.toInt() ??
                            0),
                  );

          final water =
              (data['water_intake'] as num?)?.toInt() ?? 0;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              10,
              20,
              125,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _nutritionOverview(
                  target: target,
                  consumed: consumed,
                  meals: meals,
                ),
                const SizedBox(height: 26),

                _sectionHeader(
                  'Today by Meal',
                  'Tap camera to add food',
                ),
                const SizedBox(height: 12),

                _mealGrid(
                  meals: meals,
                  target: target,
                ),
                const SizedBox(height: 28),

                _sectionHeader(
                  'Meal Timeline',
                  '${meals.length} logged',
                ),
                const SizedBox(height: 12),

                _mealTimeline(meals),
                const SizedBox(height: 28),

                _sectionHeader(
                  'Hydration',
                  'Daily target',
                ),
                const SizedBox(height: 12),

                _hydrationPanel(
                  currentMl: water,
                  goalMl: _waterGoal(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _nutritionOverview({
    required double target,
    required int consumed,
    required List<Map<String, dynamic>> meals,
  }) {
    final remaining =
        math.max(0, target.round() - consumed);
    final progress =
        (consumed / math.max(1, target))
            .clamp(0.0, 1.0);
    final over = consumed > target;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF153C21),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _kDarkGreen.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.restaurant_menu_rounded,
                color: Color(0xFFA5D6A7),
                size: 19,
              ),
              SizedBox(width: 8),
              Text(
                'DAILY NUTRITION',
                style: TextStyle(
                  color: Color(0xFFA5D6A7),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$consumed',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '/ ${target.round()} kcal',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            over
                ? '${consumed - target.round()} kcal over today'
                : '$remaining kcal remaining today',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 18),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor:
                  Colors.white.withValues(alpha: 0.12),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(
                Color(0xFF81C784),
              ),
            ),
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: _overviewMetric(
                  '${meals.length}',
                  'Meals',
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color:
                    Colors.white.withValues(alpha: 0.12),
              ),
              Expanded(
                child: _overviewMetric(
                  '${(progress * 100).round()}%',
                  'Target used',
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color:
                    Colors.white.withValues(alpha: 0.12),
              ),
              Expanded(
                child: _overviewMetric(
                  '$remaining',
                  'Kcal left',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overviewMetric(
    String value,
    String label,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 8.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _mealGrid({
    required List<Map<String, dynamic>> meals,
    required double target,
  }) {
    final items = [
      _MealTarget(
        name: 'Breakfast',
        ratio: 0.20,
        icon: Icons.wb_sunny_outlined,
        color: const Color(0xFFD7A91B),
        background: const Color(0xFFFFF8DE),
      ),
      _MealTarget(
        name: 'Lunch',
        ratio: 0.30,
        icon: Icons.lunch_dining_rounded,
        color: const Color(0xFF5964C2),
        background: const Color(0xFFF0F1FF),
      ),
      _MealTarget(
        name: 'Dinner',
        ratio: 0.30,
        icon: Icons.nightlight_round,
        color: const Color(0xFF43529D),
        background: const Color(0xFFEEF1FA),
      ),
      _MealTarget(
        name: 'Snacks',
        ratio: 0.20,
        icon: Icons.apple_rounded,
        color: const Color(0xFFD94848),
        background: const Color(0xFFFFEEEE),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.12,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final mealTarget =
            (target * item.ratio).round();
        final eaten =
            _mealCalories(meals, item.name);
        final progress =
            (eaten / math.max(1, mealTarget))
                .clamp(0.0, 1.0);

        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _kBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: 0.022,
                ),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: item.background,
                  borderRadius:
                      BorderRadius.circular(13),
                ),
                child: Icon(
                  item.icon,
                  color: item.color,
                  size: 21,
                ),
              ),
              const Spacer(),
              Text(
                item.name,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$eaten / $mealTarget kcal',
                style: const TextStyle(
                  color: _kMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: item.background,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(
                    item.color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _mealTimeline(
    List<Map<String, dynamic>> meals,
  ) {
    if (meals.isEmpty) {
      return Container(
        width: double.infinity,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kBorder),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.restaurant_outlined,
                color: _kMuted,
                size: 38,
              ),
              SizedBox(height: 10),
              Text(
                'No meals logged for today.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _kMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        14,
        8,
        14,
        8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: List.generate(
          meals.length,
          (index) {
            final meal = meals[index];
            final category =
                _resolvedCategory(meal);
            final calories =
                (meal['calories'] as num?)
                        ?.toInt() ??
                    0;

            return Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _mealImage(meal),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              meal['food_name']
                                      ?.toString() ??
                                  'Meal',
                              maxLines: 2,
                              overflow:
                                  TextOverflow
                                      .ellipsis,
                              style:
                                  const TextStyle(
                                color: _kInk,
                                fontSize: 13,
                                fontWeight:
                                    FontWeight
                                        .w900,
                              ),
                            ),
                            const SizedBox(
                              height: 4,
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration:
                                      const BoxDecoration(
                                    color:
                                        _kGreen,
                                    shape:
                                        BoxShape
                                            .circle,
                                  ),
                                ),
                                const SizedBox(
                                  width: 6,
                                ),
                                Flexible(
                                  child: Text(
                                    category,
                                    overflow:
                                        TextOverflow
                                            .ellipsis,
                                    style:
                                        const TextStyle(
                                      color:
                                          _kMuted,
                                      fontSize:
                                          10,
                                      fontWeight:
                                          FontWeight
                                              .w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$calories kcal',
                        style: const TextStyle(
                          color: _kGreen,
                          fontSize: 11.5,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index !=
                    meals.length - 1)
                  const Divider(
                    height: 1,
                    color: _kBorder,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _mealImage(
    Map<String, dynamic> meal,
  ) {
    final rawPath =
        meal['image_path']?.toString().trim() ??
            meal['imagePath']?.toString().trim() ??
            '';

    if (rawPath.isNotEmpty) {
      final file = File(rawPath);

      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.file(
            file,
            width: 58,
            height: 58,
            fit: BoxFit.cover,
            errorBuilder:
                (context, error, stackTrace) {
              return _mealImageFallback();
            },
          ),
        );
      }
    }

    return _mealImageFallback();
  }

  Widget _mealImageFallback() {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4EF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Icon(
        Icons.restaurant_rounded,
        color: _kGreen,
        size: 25,
      ),
    );
  }

  Widget _hydrationPanel({
    required int currentMl,
    required double goalMl,
  }) {
    final progress =
        (currentMl / math.max(1, goalMl))
            .clamp(0.0, 1.0);

    final remaining =
        math.max(0, goalMl.round() - currentMl);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF7FC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFDCECF5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    backgroundColor: Colors.white,
                    valueColor:
                        const AlwaysStoppedAnimation<
                            Color>(
                      Color(0xFF4B9BD3),
                    ),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                const Icon(
                  Icons.water_drop_rounded,
                  color: Color(0xFF4B9BD3),
                  size: 28,
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Water today',
                  style: TextStyle(
                    color: _kInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$currentMl / ${goalMl.round()} ml',
                  style: const TextStyle(
                    color: Color(0xFF2D7EBC),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$remaining ml remaining',
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    String title,
    String subtitle,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _kInk,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(
            color: _kMuted,
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MealTarget {
  final String name;
  final double ratio;
  final IconData icon;
  final Color color;
  final Color background;

  const _MealTarget({
    required this.name,
    required this.ratio,
    required this.icon,
    required this.color,
    required this.background,
  });
}
