import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_model.dart';

class InsightsScreen extends StatefulWidget {
  final UserModel user;

  const InsightsScreen({
    super.key,
    required this.user,
  });

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _ink = Color(0xFF191C19);
  static const Color _muted = Color(0xFF777C76);
  static const Color _page = Color(0xFFF6F9F6);
  static const Color _border = Color(0xFFE8ECE7);

  _InsightRange _range = _InsightRange.week;

  double _dailyTarget() {
    final age = widget.user.age == 0 ? 25 : widget.user.age;

    final bmr = widget.user.gender.toLowerCase() == 'male'
        ? 10 * widget.user.weight +
            6.25 * widget.user.height -
            5 * age +
            5
        : 10 * widget.user.weight +
            6.25 * widget.user.height -
            5 * age -
            161;

    final goal = widget.user.goal.toLowerCase();

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

  int get _days => _range == _InsightRange.week ? 7 : 30;

  Future<_InsightData> _loadInsights() async {
    final now = DateTime.now();
    final start =
        DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: _days - 1));

    // We use document IDs (yyyy-MM-dd), because the app already stores
    // daily logs with this date format.
    final dailySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('daily_logs')
        .get();

    final byDate = <String, Map<String, dynamic>>{};

    for (final doc in dailySnapshot.docs) {
      byDate[doc.id] = doc.data();
    }

    final days = <_DayInsight>[];

    for (var i = 0; i < _days; i++) {
      final date = start.add(Duration(days: i));
      final id = DateFormat('yyyy-MM-dd').format(date);
      final raw = byDate[id] ?? <String, dynamic>{};

      final meals = _mapList(raw['meals']);
      final activities = _mapList(raw['activities']);

      final eaten = _number(
        raw['total_calories'],
        fallback: _sumMealCalories(meals),
      );

      final burned = _number(
        raw['total_burned'],
        fallback: _number(raw['burned_calories']),
      );

      final water = _number(raw['water_glasses']).toInt();

      final steps = _number(
        raw['steps'],
        fallback: _number(raw['health_steps']),
      ).toInt();

      final exerciseMinutes = _number(
        raw['exercise_minutes'],
        fallback: _number(raw['active_minutes']),
      ).toInt();

      final energy =
          (raw['energy_level'] ?? '').toString().toLowerCase();

      days.add(
        _DayInsight(
          date: date,
          caloriesEaten: eaten,
          caloriesBurned: burned,
          waterGlasses: water,
          steps: steps,
          exerciseMinutes: exerciseMinutes,
          mealCount: meals.length,
          activityCount: activities.length,
          energy: energy,
          hasData: raw.isNotEmpty,
        ),
      );
    }

    // workout_history is already used by the Planner for replay/history.
    // We count completed history entries inside the selected period.
    int workoutCount = 0;

    try {
      final history = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('workout_history')
          .get();

      for (final doc in history.docs) {
        final data = doc.data();
        final date = _historyDate(data, doc.id);

        if (date != null &&
            !date.isBefore(start) &&
            date.isBefore(
              DateTime(now.year, now.month, now.day)
                  .add(const Duration(days: 1)),
            )) {
          workoutCount++;
        }
      }
    } catch (_) {
      // Insights still works even if older accounts do not have history.
    }

    return _InsightData(
      days: days,
      workoutCount: workoutCount,
    );
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
        )
        .toList();
  }

  double _sumMealCalories(
    List<Map<String, dynamic>> meals,
  ) {
    return meals.fold<double>(
      0,
      (total, meal) =>
          total + _number(meal['calories']),
    );
  }

  double _number(
    dynamic value, {
    double fallback = 0,
  }) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  DateTime? _historyDate(
    Map<String, dynamic> data,
    String documentId,
  ) {
    const keys = [
      'completed_at',
      'completedAt',
      'timestamp',
      'created_at',
      'date',
    ];

    for (final key in keys) {
      final value = data[key];

      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }

    return DateTime.tryParse(documentId);
  }

  @override
  Widget build(BuildContext context) {
    final target = _dailyTarget();

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text(
          'INSIGHTS',
          style: TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: _page,
      ),
      body: FutureBuilder<_InsightData>(
        key: ValueKey(_range),
        future: _loadInsights(),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: _green,
              ),
            );
          }

          if (snapshot.hasError) {
            return _errorState();
          }

          final data = snapshot.data ??
              const _InsightData(
                days: [],
                workoutCount: 0,
              );

          return RefreshIndicator(
            color: _green,
            onRefresh: () async {
              setState(() {});
            },
            child: SingleChildScrollView(
              physics:
                  const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                20,
                12,
                20,
                110,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _rangeSelector(),
                  const SizedBox(height: 22),

                  _overview(data, target),
                  const SizedBox(height: 28),

                  _sectionTitle(
                    'Calorie Balance',
                    'Consumed vs target',
                  ),
                  const SizedBox(height: 12),
                  _calorieCard(data, target),
                  const SizedBox(height: 28),

                  _sectionTitle(
                    'Activity',
                    'Movement & exercise',
                  ),
                  const SizedBox(height: 12),
                  _activityCard(data),
                  const SizedBox(height: 28),

                  _sectionTitle(
                    'Workout Consistency',
                    'Training progress',
                  ),
                  const SizedBox(height: 12),
                  _workoutCard(data),
                  const SizedBox(height: 28),

                  _sectionTitle(
                    'Nutrition & Hydration',
                    'Daily habits',
                  ),
                  const SizedBox(height: 12),
                  _habitCard(data),
                  const SizedBox(height: 28),

                  _sectionTitle(
                    'Energy & Readiness',
                    'How you felt',
                  ),
                  const SizedBox(height: 12),
                  _energyCard(data),
                  const SizedBox(height: 28),

                  _sectionTitle(
                    'Personal Insight',
                    'Based on your data',
                  ),
                  const SizedBox(height: 12),
                  _personalInsightCard(
                    data,
                    target,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _rangeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF1EC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _rangeButton(
              '7 DAYS',
              _InsightRange.week,
            ),
          ),
          Expanded(
            child: _rangeButton(
              '30 DAYS',
              _InsightRange.month,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeButton(
    String label,
    _InsightRange value,
  ) {
    final selected = _range == value;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        if (_range == value) return;

        setState(() {
          _range = value;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(
          milliseconds: 180,
        ),
        padding: const EdgeInsets.symmetric(
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color:
              selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: 0.04,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? _green : _muted,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _overview(
    _InsightData data,
    double target,
  ) {
    final activeDays =
        data.days.where((d) => d.hasData).length;

    final avgEaten = data.averageEaten;
    final avgBurned = data.averageBurned;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Progress',
          style: TextStyle(
            color: _ink,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _range == _InsightRange.week
              ? 'A quick look at your last 7 days.'
              : 'A broader look at your last 30 days.',
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _summaryTile(
                icon: Icons
                    .local_fire_department_rounded,
                value: '${avgBurned.round()}',
                label: 'Avg burned',
                unit: 'kcal/day',
                iconColor: Colors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryTile(
                icon: Icons.restaurant_rounded,
                value: '${avgEaten.round()}',
                label: 'Avg eaten',
                unit: 'kcal/day',
                iconColor: _green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _summaryTile(
                icon: Icons
                    .fitness_center_rounded,
                value: '${data.workoutCount}',
                label: 'Workouts',
                unit: 'completed',
                iconColor: _green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryTile(
                icon:
                    Icons.calendar_today_rounded,
                value: '$activeDays',
                label: 'Logged days',
                unit: 'of $_days days',
                iconColor: const Color(
                  0xFF5865C7,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryTile({
    required IconData icon,
    required String value,
    required String label,
    required String unit,
    required Color iconColor,
  }) {
    return _card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 21,
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            unit,
            style: const TextStyle(
              color: _muted,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _calorieCard(
    _InsightData data,
    double target,
  ) {
    final chartDays = _chartDays(data.days);
    final maxValue = math.max(
      target * 1.25,
      chartDays.fold<double>(
        0,
        (highest, day) => math.max(
          highest,
          day.caloriesEaten,
        ),
      ),
    );

    return _card(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _legendDot(
                _green,
                'Consumed',
              ),
              const SizedBox(width: 16),
              _legendDot(
                Colors.orange,
                'Daily target',
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 190,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: math.max(
                  1,
                  chartDays.length - 1,
                ).toDouble(),
                minY: 0,
                maxY: maxValue <= 0
                    ? 100
                    : maxValue,
                clipData:
                    const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine:
                      (_) => FlLine(
                    color: const Color(
                      0xFFF0F2EF,
                    ),
                    strokeWidth: 1,
                  ),
                ),
                borderData:
                    FlBorderData(show: false),
                titlesData:
                    _chartTitles(chartDays),
                extraLinesData:
                    ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: target,
                      color: Colors.orange
                          .withValues(
                        alpha: 0.45,
                      ),
                      strokeWidth: 1.5,
                      dashArray: [5, 5],
                    ),
                  ],
                ),
                lineTouchData:
                    LineTouchData(
                  touchTooltipData:
                      LineTouchTooltipData(
                    getTooltipColor: (_) =>
                        _ink,
                    getTooltipItems:
                        (spots) => spots
                            .map(
                              (spot) =>
                                  LineTooltipItem(
                                '${spot.y.round()} kcal',
                                const TextStyle(
                                  color:
                                      Colors.white,
                                  fontSize: 11,
                                  fontWeight:
                                      FontWeight.w800,
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      chartDays.length,
                      (i) => FlSpot(
                        i.toDouble(),
                        chartDays[i]
                            .caloriesEaten,
                      ),
                    ),
                    isCurved: true,
                    preventCurveOverShooting:
                        true,
                    color: _green,
                    barWidth: 3.5,
                    dotData:
                        const FlDotData(
                      show: false,
                    ),
                    belowBarData:
                        BarAreaData(
                      show: true,
                      color: _green.withValues(
                        alpha: 0.07,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _metricRow(
            'Daily target',
            '${target.round()} kcal',
          ),
          _divider(),
          _metricRow(
            'Average consumed',
            '${data.averageEaten.round()} kcal',
          ),
          _divider(),
          _metricRow(
            'Days within target',
            '${data.daysWithinTarget(target)} / $_days',
            valueColor: _green,
          ),
        ],
      ),
    );
  }

  Widget _activityCard(_InsightData data) {
    final chartDays = _chartDays(data.days);
    final maxBurn = math.max(
      100,
      chartDays.fold<double>(
        0,
        (highest, day) => math.max(
          highest,
          day.caloriesBurned,
        ),
      ),
    );

    return _card(
      child: Column(
        children: [
          SizedBox(
            height: 165,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxBurn * 1.15,
                gridData:
                    const FlGridData(
                  show: false,
                ),
                borderData:
                    FlBorderData(show: false),
                titlesData:
                    _chartTitles(chartDays),
                barTouchData:
                    BarTouchData(
                  touchTooltipData:
                      BarTouchTooltipData(
                    getTooltipColor: (_) =>
                        _ink,
                    getTooltipItem: (
                      group,
                      groupIndex,
                      rod,
                      rodIndex,
                    ) {
                      return BarTooltipItem(
                        '${rod.toY.round()} kcal',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight:
                              FontWeight.w800,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: List.generate(
                  chartDays.length,
                  (i) => BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: chartDays[i]
                            .caloriesBurned,
                        width: 14,
                        color: Colors.orange,
                        borderRadius:
                            BorderRadius.circular(
                          6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _miniMetric(
                  Icons
                      .local_fire_department_rounded,
                  '${data.totalBurned.round()}',
                  'Total kcal',
                ),
              ),
              Expanded(
                child: _miniMetric(
                  Icons.directions_walk_rounded,
                  '${data.totalSteps}',
                  'Total steps',
                ),
              ),
              Expanded(
                child: _miniMetric(
                  Icons.timer_outlined,
                  '${data.totalExerciseMinutes}',
                  'Active min',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _workoutCard(_InsightData data) {
    final goal = _range == _InsightRange.week
        ? 3
        : 12;

    final progress =
        (data.workoutCount / goal).clamp(0.0, 1.0);

    return _card(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFE8F5E9,
                  ),
                  borderRadius:
                      BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons
                      .fitness_center_rounded,
                  color: _green,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data.workoutCount} workouts completed',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _range ==
                              _InsightRange.week
                          ? 'Suggested consistency: 3 workouts/week'
                          : 'Suggested consistency: about 3 workouts/week',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 10.5,
                        fontWeight:
                            FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius:
                BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor:
                  const Color(0xFFEDF1EC),
              valueColor:
                  const AlwaysStoppedAnimation(
                _green,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.workoutCount >= goal
                ? 'Consistency goal reached.'
                : '${goal - data.workoutCount} more workout${goal - data.workoutCount == 1 ? '' : 's'} to reach this ${_range == _InsightRange.week ? 'week' : 'period'} goal.',
            style: TextStyle(
              color: data.workoutCount >= goal
                  ? _green
                  : _muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _habitCard(_InsightData data) {
    final loggedDays =
        data.days.where((d) => d.hasData).length;

    final mealDays = data.days
        .where((d) => d.mealCount > 0)
        .length;

    final hydrationDays = data.days
        .where((d) => d.waterGlasses > 0)
        .length;

    final avgWater = data.averageWater;

    return _card(
      child: Column(
        children: [
          _habitRow(
            icon: Icons.restaurant_rounded,
            title: 'Meal logging',
            value: '$mealDays / $_days days',
            progress:
                mealDays / math.max(1, _days),
          ),
          const SizedBox(height: 20),
          _habitRow(
            icon: Icons.water_drop_rounded,
            title: 'Hydration logging',
            value:
                '${avgWater.toStringAsFixed(1)} glasses/day',
            progress: hydrationDays /
                math.max(1, _days),
          ),
          const SizedBox(height: 20),
          _habitRow(
            icon: Icons
                .fact_check_outlined,
            title: 'Overall logging',
            value:
                '$loggedDays / $_days days',
            progress:
                loggedDays / math.max(1, _days),
          ),
        ],
      ),
    );
  }

  Widget _energyCard(_InsightData data) {
    final low = data.days
        .where((d) => d.energy == 'low')
        .length;
    final normal = data.days
        .where(
          (d) =>
              d.energy == 'normal' ||
              d.energy == 'medium',
        )
        .length;
    final high = data.days
        .where((d) => d.energy == 'high')
        .length;

    final total = low + normal + high;

    if (total == 0) {
      return _card(
        child: const Row(
          children: [
            Icon(
              Icons.battery_unknown_rounded,
              color: _muted,
              size: 28,
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'No energy check-ins yet. Your Low, Normal and High selections will appear here.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 11,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _energyTile(
                  'Low',
                  low,
                  Icons.battery_1_bar_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _energyTile(
                  'Normal',
                  normal,
                  Icons.battery_4_bar_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _energyTile(
                  'High',
                  high,
                  Icons.battery_full_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            _energyMessage(
              low,
              normal,
              high,
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 10.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _personalInsightCard(
    _InsightData data,
    double target,
  ) {
    final messages =
        _buildInsightMessages(data, target);

    return _card(
      child: Column(
        children: List.generate(
          messages.length,
          (index) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: index ==
                        messages.length - 1
                    ? 0
                    : 16,
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFFE8F5E9,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: _green,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      messages[index],
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 11.5,
                        height: 1.5,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<String> _buildInsightMessages(
    _InsightData data,
    double target,
  ) {
    final messages = <String>[];

    final loggedDays =
        data.days.where((d) => d.hasData).length;

    if (loggedDays == 0) {
      return [
        'Start logging meals, water and workouts to build your personal insights.',
      ];
    }

    final within =
        data.daysWithinTarget(target);

    if (within >= loggedDays * 0.7) {
      messages.add(
        'Your calorie intake has been close to your daily target on most logged days.',
      );
    } else {
      messages.add(
        'Your calorie intake varies across the period. More consistent meal logging will make this trend easier to understand.',
      );
    }

    if (data.workoutCount >=
        (_range == _InsightRange.week ? 3 : 12)) {
      messages.add(
        'Your workout consistency is strong for this period. Keep the routine sustainable.',
      );
    } else {
      messages.add(
        'You have completed ${data.workoutCount} workout${data.workoutCount == 1 ? '' : 's'} in this period. Regular sessions will make your progress trend clearer.',
      );
    }

    if (data.averageWater > 0 &&
        data.averageWater < 6) {
      messages.add(
        'Your recorded water intake averages ${data.averageWater.toStringAsFixed(1)} glasses per day. Try to log hydration consistently so the app can track the habit accurately.',
      );
    }

    return messages.take(3).toList();
  }

  List<_DayInsight> _chartDays(
    List<_DayInsight> days,
  ) {
    if (_range == _InsightRange.week) {
      return days;
    }

    // 30 bars/labels are too crowded on a phone.
    // Use six representative 5-day points for charts,
    // while all 30 days still count in the statistics.
    final result = <_DayInsight>[];

    for (var i = 4; i < days.length; i += 5) {
      final chunk =
          days.sublist(i - 4, i + 1);

      result.add(
        _DayInsight(
          date: chunk.last.date,
          caloriesEaten:
              chunk.fold<double>(
                    0,
                    (t, d) =>
                        t + d.caloriesEaten,
                  ) /
                  chunk.length,
          caloriesBurned:
              chunk.fold<double>(
                    0,
                    (t, d) =>
                        t + d.caloriesBurned,
                  ) /
                  chunk.length,
          waterGlasses: 0,
          steps: chunk.fold<int>(
            0,
            (t, d) => t + d.steps,
          ),
          exerciseMinutes:
              chunk.fold<int>(
            0,
            (t, d) =>
                t + d.exerciseMinutes,
          ),
          mealCount: 0,
          activityCount: 0,
          energy: '',
          hasData:
              chunk.any((d) => d.hasData),
        ),
      );
    }

    return result;
  }

  FlTitlesData _chartTitles(
    List<_DayInsight> days,
  ) {
    return FlTitlesData(
      leftTitles: const AxisTitles(
        sideTitles:
            SideTitles(showTitles: false),
      ),
      rightTitles: const AxisTitles(
        sideTitles:
            SideTitles(showTitles: false),
      ),
      topTitles: const AxisTitles(
        sideTitles:
            SideTitles(showTitles: false),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();

            if (index < 0 ||
                index >= days.length ||
                value != index.toDouble()) {
              return const SizedBox.shrink();
            }

            final label =
                _range == _InsightRange.week
                    ? DateFormat('E')
                        .format(days[index].date)
                        .substring(0, 1)
                    : DateFormat('d')
                        .format(days[index].date);

            return Padding(
              padding:
                  const EdgeInsets.only(top: 9),
              child: Text(
                label,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _energyTile(
    String label,
    int count,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 15,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6F1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: _green,
            size: 24,
          ),
          const SizedBox(height: 7),
          Text(
            '$count',
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _energyMessage(
    int low,
    int normal,
    int high,
  ) {
    if (high >= normal && high >= low) {
      return 'High-energy check-ins were the most common in this period.';
    }

    if (low >= normal && low >= high) {
      return 'Low-energy check-ins were the most common. Lighter workout recommendations can help on these days.';
    }

    return 'Normal-energy check-ins were the most common, suggesting mostly balanced training days.';
  }

  Widget _habitRow({
    required IconData icon,
    required String title,
    required String value,
    required double progress,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: _green,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: _green,
                      fontSize: 10,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(20),
                child:
                    LinearProgressIndicator(
                  value:
                      progress.clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor:
                      const Color(0xFFEDF1EC),
                  valueColor:
                      const AlwaysStoppedAnimation(
                    _green,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniMetric(
    IconData icon,
    String value,
    String label,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          color: _green,
          size: 20,
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _muted,
            fontSize: 8.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _metricRow(
    String label,
    String value, {
    Color valueColor = _ink,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(
    Color color,
    String label,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(
    String title,
    String subtitle,
  ) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(
            color: _muted,
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsets padding =
        const EdgeInsets.all(18),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.025,
            ),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(
        vertical: 12,
      ),
      child: Divider(
        height: 1,
        color: _border,
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.query_stats_rounded,
              color: _muted,
              size: 52,
            ),
            const SizedBox(height: 12),
            const Text(
              'Unable to load insights',
              style: TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _muted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () {
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
              child: const Text('TRY AGAIN'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _InsightRange {
  week,
  month,
}

class _DayInsight {
  final DateTime date;
  final double caloriesEaten;
  final double caloriesBurned;
  final int waterGlasses;
  final int steps;
  final int exerciseMinutes;
  final int mealCount;
  final int activityCount;
  final String energy;
  final bool hasData;

  const _DayInsight({
    required this.date,
    required this.caloriesEaten,
    required this.caloriesBurned,
    required this.waterGlasses,
    required this.steps,
    required this.exerciseMinutes,
    required this.mealCount,
    required this.activityCount,
    required this.energy,
    required this.hasData,
  });
}

class _InsightData {
  final List<_DayInsight> days;
  final int workoutCount;

  const _InsightData({
    required this.days,
    required this.workoutCount,
  });

  double get totalEaten => days.fold<double>(
        0,
        (total, day) =>
            total + day.caloriesEaten,
      );

  double get totalBurned => days.fold<double>(
        0,
        (total, day) =>
            total + day.caloriesBurned,
      );

  int get totalSteps => days.fold<int>(
        0,
        (total, day) => total + day.steps,
      );

  int get totalExerciseMinutes =>
      days.fold<int>(
        0,
        (total, day) =>
            total + day.exerciseMinutes,
      );

  double get averageEaten =>
      days.isEmpty ? 0 : totalEaten / days.length;

  double get averageBurned =>
      days.isEmpty ? 0 : totalBurned / days.length;

  double get averageWater => days.isEmpty
      ? 0
      : days.fold<int>(
            0,
            (total, day) =>
                total + day.waterGlasses,
          ) /
          days.length;

  int daysWithinTarget(double target) {
    return days
        .where(
          (day) =>
              day.hasData &&
              day.caloriesEaten > 0 &&
              day.caloriesEaten <= target,
        )
        .length;
  }
}
