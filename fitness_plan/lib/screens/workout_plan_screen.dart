import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_model.dart';
import '../models/user_model.dart';
import '../models/gamification_model.dart';
import '../services/groq_ai_service.dart';
import '../services/gamification_service.dart';
import '../widgets/energy_check_sheet.dart';
import 'workout_detail_screen.dart';

const _kGreen = Color(0xFF2E7D32);
const _kInk = Color(0xFF191C19);
const _kMuted = Color(0xFF747972);
const _kBg = Color(0xFFFBFDFA);
const _kBorder = Color(0xFFF0F0F0);
const _kMintBg = Color(0xFFF0F4EF);


class _BadgeDisplayInfo {
  final String description;
  final String requirement;

  const _BadgeDisplayInfo({
    required this.description,
    required this.requirement,
  });
}

class WorkoutPlanScreen extends StatefulWidget {
  final UserModel user;
  const WorkoutPlanScreen({super.key, required this.user});

  @override
  State<WorkoutPlanScreen> createState() => _WorkoutPlanScreenState();
}

class _WorkoutPlanScreenState extends State<WorkoutPlanScreen> {
  final _ai = GroqAiService();
  final _gamification = GamificationService();
  late Future<List<WorkoutPlan>> _aiPlans;
  late WorkoutLevel _selectedLevel;

  // Energy check-in is asked once per app open, then remembered for the
  // session so tapping around plans doesn't re-prompt every time.
  EnergyLevel? _todaysEnergy;

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

  Widget _buildCleanCard({required Widget child, EdgeInsets? margin}) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Tap handling: energy check-in -> possible gentler-plan nudge -> navigate
  // ---------------------------------------------------------------------

  Future<void> _handlePlanTap(
    WorkoutPlan plan,
    List<WorkoutPlan> allPlans,
  ) async {
    if (_todaysEnergy == null) {
      final energy = await showEnergyCheckIn(context);
      if (energy == null) return;
      if (!mounted) return;

      setState(() {
        _todaysEnergy = energy;
      });

      // Save today's readiness so it has a real purpose beyond this popup.
      await _saveTodayEnergy(energy);
    }

    // Energy NEVER changes Beginner / Intermediate / Advanced.
    // It only chooses an intensity that fits today's readiness inside
    // the same level as the workout the user tapped.
    final tappedLevel = plan.level;

    final sameLevelPlans = allPlans
        .where((candidate) => candidate.level == tappedLevel)
        .toList();

    WorkoutPlan planToOpen = plan;
    String energyMessage = '';

    if (sameLevelPlans.isNotEmpty &&
        _todaysEnergy != null) {
      if (_todaysEnergy == EnergyLevel.low) {
        // Low -> lightest plan in this level.
        sameLevelPlans.sort(
          (a, b) => a.calories.compareTo(b.calories),
        );
        planToOpen = sameLevelPlans.first;
        energyMessage =
            'Low energy today — a lighter ${_levelLabel(tappedLevel)} workout is recommended.';
      } else if (_todaysEnergy == EnergyLevel.medium) {
        // Normal -> plan closest to the average calorie demand.
        final totalCalories = sameLevelPlans.fold<int>(
          0,
          (total, item) => total + item.calories,
        );
        final averageCalories =
            totalCalories / sameLevelPlans.length;

        sameLevelPlans.sort(
          (a, b) => (a.calories - averageCalories)
              .abs()
              .compareTo(
                (b.calories - averageCalories).abs(),
              ),
        );

        planToOpen = sameLevelPlans.first;
        energyMessage =
            'Normal energy today — a balanced ${_levelLabel(tappedLevel)} workout is recommended.';
      } else {
        // High -> most demanding plan in this level.
        sameLevelPlans.sort(
          (a, b) => b.calories.compareTo(a.calories),
        );
        planToOpen = sameLevelPlans.first;
        energyMessage =
            'High energy today — a harder ${_levelLabel(tappedLevel)} workout is recommended.';
      }
    }

    // Safety: readiness must never promote/demote the user's workout level.
    if (planToOpen.level != tappedLevel) {
      planToOpen = plan;
    }

    if (!mounted) return;

    // Tell the user what the readiness check actually did.
    if (energyMessage.isNotEmpty &&
        planToOpen.title != plan.title) {
      final useRecommendation =
          await _showEnergyRecommendation(
        original: plan,
        recommended: planToOpen,
        message: energyMessage,
      );

      if (useRecommendation != true) {
        planToOpen = plan;
      }
    } else if (energyMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(energyMessage),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutDetailScreen(
          plan: planToOpen,
          user: widget.user,
        ),
      ),
    );
  }

  Future<void> _saveTodayEnergy(
    EnergyLevel energy,
  ) async {
    final now = DateTime.now();
    final todayId =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('daily_logs')
        .doc(todayId)
        .set(
      {
        'energy_level': _energyValue(energy),
        'energy_updated_at':
            FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  String _energyValue(EnergyLevel energy) {
    switch (energy) {
      case EnergyLevel.low:
        return 'low';
      case EnergyLevel.medium:
        return 'normal';
      case EnergyLevel.high:
        return 'high';
    }
  }

  String _levelLabel(WorkoutLevel level) {
    final value = level.name;
    return value[0].toUpperCase() +
        value.substring(1);
  }

  Future<bool?> _showEnergyRecommendation({
    required WorkoutPlan original,
    required WorkoutPlan recommended,
    required String message,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE8F5E9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: _kGreen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Today’s Recommendation',
                        style: TextStyle(
                          color: _kInk,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4EF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        recommended.title,
                        style: const TextStyle(
                          color: _kInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${recommended.category} • '
                        '${recommended.calories} kcal • '
                        '${recommended.minutes} min',
                        style: const TextStyle(
                          color: _kGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(
                          sheetContext,
                          false,
                        ),
                        child: const Text(
                          'KEEP MY CHOICE',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(
                          sheetContext,
                          true,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'USE SUGGESTION',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    String todayId = DateTime.now().toString().split(' ')[0];

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "AI PERSONAL PLANNER",
          style: TextStyle(color: _kInk, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _kGreen),
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
            return const Center(child: CircularProgressIndicator(color: _kGreen));
          }

          final allPlans = snapshot.data ?? [];

          // One plan for each category in the selected level.
          // 3 levels x 5 categories = 15 plans total.
          const categoryOrder = [
            'Cardio',
            'Strength',
            'Mobility',
            'Core',
            'Full Body',
          ];

          final levelPlans = <WorkoutPlan>[];

          for (final category in categoryOrder) {
            final matches = allPlans.where(
              (plan) =>
                  plan.level == _selectedLevel &&
                  plan.category.toLowerCase() ==
                      category.toLowerCase(),
            );

            if (matches.isNotEmpty) {
              levelPlans.add(matches.first);
            }
          }

          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Useful temporary debug line:
              // If this prints changing pixels/maxScrollExtent, Flutter
              // scrolling itself is working correctly.
              if (notification is ScrollUpdateNotification) {
                debugPrint(
                  'PLAN SCROLL: '
                  '${notification.metrics.pixels.toStringAsFixed(1)} / '
                  '${notification.metrics.maxScrollExtent.toStringAsFixed(1)}',
                );
              }
              return false;
            },
            child: SingleChildScrollView(
              primary: true,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                bottom:
                    MediaQuery.of(context).padding.bottom +
                    180,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  _buildProgressHeader(todayId),
                  _buildWorkoutHistorySection(),
                  _buildQuickSuggestionBanner(
                    allPlans,
                  ),
                  _buildBadgesRow(),

                  // Lock/unlock still follows the user's real level.
                  _buildLevelSelector(
                    _parseLevel(widget.user.level),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      24,
                      20,
                      12,
                    ),
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.end,
                      children: [
                        const Expanded(
                          child: Text(
                            'Your AI Plans',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight:
                                  FontWeight.w900,
                              color: _kGreen,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        Text(
                          _selectedLevel.name
                              .toUpperCase(),
                          style: const TextStyle(
                            color: _kMuted,
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (levelPlans.isNotEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      child: Column(
                        children: levelPlans
                            .map(
                              (plan) =>
                                  _buildActivityCard(
                                plan,
                                allPlans,
                              ),
                            )
                            .toList(),
                      ),
                    ),

                  if (allPlans.isNotEmpty &&
                      levelPlans.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(
                        20,
                        14,
                        20,
                        0,
                      ),
                      child: _buildCleanCard(
                        child: const Column(
                          children: [
                            Icon(
                              Icons
                                  .fitness_center_rounded,
                              color: _kMuted,
                              size: 34,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'No workout plans are available for this level.',
                              textAlign:
                                  TextAlign.center,
                              style: TextStyle(
                                color: _kInk,
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (allPlans.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(
                        20,
                        50,
                        20,
                        0,
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons
                                .fitness_center_rounded,
                            color: _kMuted,
                            size: 34,
                          ),
                          const SizedBox(
                            height: 10,
                          ),
                          const Text(
                            'No workout plans were generated.',
                            style: TextStyle(
                              color: _kInk,
                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tap refresh to try generating the plans again.',
                            textAlign:
                                TextAlign.center,
                            style: TextStyle(
                              color: _kMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _aiPlans = _ai
                                    .generatePersonalizedPlans(
                                  widget.user,
                                );
                              });
                            },
                            icon: const Icon(
                              Icons.refresh_rounded,
                            ),
                            label: const Text(
                              'GENERATE AGAIN',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Dashboard header: today's burned kcal + streak + level/XP + history
  // ---------------------------------------------------------------------

  Widget _buildProgressHeader(String todayId) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        16,
        20,
        0,
      ),
      child: Column(
        children: [
          // ---------------------------------------------------------------
          // Today's calories burned + history calendar
          // ---------------------------------------------------------------
          StreamBuilder<
              DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.user.uid)
                .collection('daily_logs')
                .doc(todayId)
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data();

              final rawBurned =
                  data?['total_burned'] ??
                  data?['burned_calories'] ??
                  0;

              final burned =
                  rawBurned is num
                      ? rawBurned.toInt()
                      : 0;

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 22,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(
                    28,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons
                            .local_fire_department_rounded,
                        color: _kGreen,
                        size: 29,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Today's Progress",
                            style: TextStyle(
                              color: _kMuted,
                              fontSize: 12,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$burned kcal burned',
                            style: const TextStyle(
                              color: _kGreen,
                              fontWeight:
                                  FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip:
                          'View calorie history',
                      onPressed:
                          _showHistoryCalendar,
                      icon: const Icon(
                        Icons
                            .calendar_month_rounded,
                        color: _kGreen,
                        size: 27,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // ---------------------------------------------------------------
          // Clear streak + level / XP card
          // ---------------------------------------------------------------
          StreamBuilder<UserProgress>(
            stream: _gamification.watchProgress(
              widget.user.uid,
            ),
            builder: (context, snapshot) {
              final progress =
                  snapshot.data ??
                  const UserProgress();

              // UserProgress already exposes XP within the current level
              // and a normalized 0..1 levelProgress value.
              final xpIntoLevel =
                  progress.xpIntoLevel;
              const xpPerLevel = 100;

              final xpRemaining =
                  (xpPerLevel - xpIntoLevel)
                      .clamp(0, xpPerLevel);

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(24),
                  border:
                      Border.all(color: _kBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: 0.035),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    // Clearly labelled streak — no isolated flame number.
                    Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFFFFF6E8,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          15,
                        ),
                      ),
                      child: Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons
                                .whatshot_rounded,
                            color: Colors.orange,
                            size: 19,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${progress.currentStreak} DAY STREAK',
                            style:
                                const TextStyle(
                              color: _kInk,
                              fontSize: 10.5,
                              fontWeight:
                                  FontWeight.w900,
                              letterSpacing:
                                  0.25,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 15),

                    Row(
                      children: [
                        Text(
                          'LEVEL ${progress.level}',
                          style: const TextStyle(
                            color: _kInk,
                            fontSize: 13,
                            fontWeight:
                                FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$xpIntoLevel/100 XP',
                          style: const TextStyle(
                            color: _kMuted,
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 9),

                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(20),
                      child:
                          LinearProgressIndicator(
                        value:
                            progress.levelProgress,
                        minHeight: 9,
                        backgroundColor:
                            const Color(
                          0xFFEEF1ED,
                        ),
                        valueColor:
                            const AlwaysStoppedAnimation<
                                Color>(
                          _kGreen,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Text(
                          'Level progress',
                          style: TextStyle(
                            color: _kMuted,
                            fontSize: 9.5,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$xpRemaining XP to Level ${progress.level + 1}',
                          style: const TextStyle(
                            color: _kGreen,
                            fontSize: 9.5,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutHistorySection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('workout_history')
          .orderBy('completedAt', descending: true)
          .limit(8)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Padding(
            padding:
                EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: LinearProgressIndicator(
              minHeight: 3,
              color: _kGreen,
              backgroundColor: _kMintBg,
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding:
              const EdgeInsets.fromLTRB(20, 20, 0, 0),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.only(right: 20),
                child: Row(
                  children: [
                    const Text(
                      'Workout History',
                      style: TextStyle(
                        color: _kInk,
                        fontSize: 18,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed:
                          _showAllWorkoutHistory,
                      child: const Text(
                        'VIEW ALL',
                        style: TextStyle(
                          color: _kGreen,
                          fontSize: 11,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Horizontal only, so it does not conflict with
              // the page's vertical SingleChildScrollView.
              SizedBox(
                height: 156,
                child: ListView.separated(
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  physics:
                      const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.only(right: 20),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final data =
                        docs[index].data();

                    return _buildWorkoutHistoryCard(
                      data,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkoutHistoryCard(
    Map<String, dynamic> data,
  ) {
    final title =
        data['title']?.toString() ?? 'Workout';

    final category =
        data['category']?.toString() ??
            'Workout';

    final calories =
        (data['calories'] as num?)?.toInt() ??
            0;

    final completedAt =
        data['completedAt'] as Timestamp?;

    final dateText = completedAt == null
        ? 'Completed'
        : _formatHistoryDate(
            completedAt.toDate(),
          );

    return Container(
      width: 230,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                color: _kGreen,
                size: 20,
              ),
              const Spacer(),
              Text(
                dateText,
                style: const TextStyle(
                  color: _kMuted,
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _kInk,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$category • $calories kcal',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _kGreen,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: ElevatedButton.icon(
              onPressed: () =>
                  _replayWorkout(data),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(
                Icons.replay_rounded,
                size: 16,
              ),
              label: const Text(
                'PLAY AGAIN',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAllWorkoutHistory() async {
    final history =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.user.uid)
            .collection('workout_history')
            .orderBy(
              'completedAt',
              descending: true,
            )
            .limit(50)
            .get();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: Container(
            decoration: const BoxDecoration(
              color: _kBg,
              borderRadius:
                  BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _kBorder,
                    borderRadius:
                        BorderRadius.circular(10),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    18,
                    20,
                    12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Workout History',
                        style: TextStyle(
                          color: _kInk,
                          fontSize: 20,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: history.docs.isEmpty
                      ? const Center(
                          child: Text(
                            'No completed workouts yet.',
                            style: TextStyle(
                              color: _kMuted,
                            ),
                          ),
                        )
                      : ListView.separated(
                          primary: false,
                          padding:
                              const EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            30,
                          ),
                          itemCount:
                              history.docs.length,
                          separatorBuilder:
                              (_, _) =>
                                  const SizedBox(
                            height: 10,
                          ),
                          itemBuilder:
                              (context, index) {
                            final data =
                                history.docs[index]
                                    .data();

                            final rawExercise =
                                data['exercise'];

                            final exercise =
                                rawExercise is Map
                                    ? rawExercise
                                    : null;

                            final title =
                                data['title']
                                        ?.toString() ??
                                    'Workout';

                            final activity =
                                exercise?['name']
                                        ?.toString() ??
                                    'Workout activity';

                            final calories =
                                (data['calories']
                                            as num?)
                                        ?.toInt() ??
                                    0;

                            final timestamp =
                                data['completedAt']
                                    as Timestamp?;

                            return Container(
                              padding:
                                  const EdgeInsets
                                      .all(16),
                              decoration:
                                  BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  18,
                                ),
                                border: Border.all(
                                  color: _kBorder,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration:
                                        const BoxDecoration(
                                      color: Color(
                                        0xFFE8F5E9,
                                      ),
                                      shape:
                                          BoxShape
                                              .circle,
                                    ),
                                    child:
                                        const Icon(
                                      Icons
                                          .check_rounded,
                                      color:
                                          _kGreen,
                                    ),
                                  ),
                                  const SizedBox(
                                    width: 12,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                      children: [
                                        Text(
                                          title,
                                          style:
                                              const TextStyle(
                                            color:
                                                _kInk,
                                            fontWeight:
                                                FontWeight
                                                    .w900,
                                          ),
                                        ),
                                        const SizedBox(
                                          height: 3,
                                        ),
                                        Text(
                                          '$activity • $calories kcal',
                                          style:
                                              const TextStyle(
                                            color:
                                                _kMuted,
                                            fontSize:
                                                11,
                                            fontWeight:
                                                FontWeight
                                                    .w600,
                                          ),
                                        ),
                                        if (timestamp !=
                                            null) ...[
                                          const SizedBox(
                                            height: 3,
                                          ),
                                          Text(
                                            _formatHistoryDateTime(
                                              timestamp
                                                  .toDate(),
                                            ),
                                            style:
                                                const TextStyle(
                                              color:
                                                  _kMuted,
                                              fontSize:
                                                  10,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip:
                                        'Play again',
                                    onPressed: () {
                                      Navigator.pop(
                                        sheetContext,
                                      );
                                      _replayWorkout(
                                        data,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons
                                          .replay_circle_filled_rounded,
                                      color: _kGreen,
                                      size: 34,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _replayWorkout(
    Map<String, dynamic> data,
  ) {
    final plan =
        _historyDataToWorkoutPlan(data);

    if (plan == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'This older history item does not contain enough workout data to replay.',
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            WorkoutDetailScreen(
          plan: plan,
          user: widget.user,
        ),
      ),
    );
  }

  WorkoutPlan? _historyDataToWorkoutPlan(
    Map<String, dynamic> data,
  ) {
    final rawExercise = data['exercise'];

    if (rawExercise is! Map) {
      return null;
    }

    final rawLevel =
        (data['level'] as num?)?.toInt() ??
            0;

    final safeLevel = rawLevel.clamp(
      0,
      WorkoutLevel.values.length - 1,
    );

    final rawInstructions =
        rawExercise['instructions'];

    final instructions =
        rawInstructions is List
            ? rawInstructions
                .map(
                  (item) => item.toString(),
                )
                .toList()
            : <String>[];

    return WorkoutPlan(
      title:
          data['title']?.toString() ??
              'Workout',
      subtitle:
          data['subtitle']?.toString() ?? '',
      category:
          data['category']?.toString() ??
              'Workout',
      minutes:
          (data['minutes'] as num?)?.toInt() ??
              12,
      calories:
          (data['calories'] as num?)?.toInt() ??
              0,
      level:
          WorkoutLevel.values[safeLevel],
      imagePath:
          data['imagePath']?.toString() ??
              'assets/ai_gen.png',
      exercises: [
        Exercise(
          name:
              rawExercise['name']
                      ?.toString() ??
                  'Workout Activity',
          reps:
              rawExercise['reps']
                      ?.toString() ??
                  'Follow video',
          duration:
              rawExercise['duration']
                      ?.toString() ??
                  '10-15 min',
          caloriesBurned:
              (rawExercise[
                          'caloriesBurned']
                      as num?)
                  ?.toInt() ??
              ((data['calories'] as num?)
                      ?.toInt() ??
                  0),
          instructions: instructions,
        ),
      ],
    );
  }

  String _formatHistoryDate(
    DateTime date,
  ) {
    final now = DateTime.now();
    final today =
        DateTime(now.year, now.month, now.day);

    final value = DateTime(
      date.year,
      date.month,
      date.day,
    );

    final difference =
        today.difference(value).inDays;

    if (difference == 0) {
      return 'Today';
    }

    if (difference == 1) {
      return 'Yesterday';
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatHistoryDateTime(
    DateTime date,
  ) {
    final hour =
        date.hour.toString().padLeft(2, '0');

    final minute =
        date.minute.toString().padLeft(2, '0');

    return '${_formatHistoryDate(date)} • $hour:$minute';
  }


  // ---------------------------------------------------------------------
  // Smart "time-crunch" suggestion
  // ---------------------------------------------------------------------

  Widget _buildQuickSuggestionBanner(List<WorkoutPlan> allPlans) {
    final now = DateTime.now();
    final isLateAndBusy = now.hour >= 18; // getting late in the day
    if (!isLateAndBusy) return const SizedBox.shrink();

    return FutureBuilder<Map<DateTime, int>>(
      future: _gamification.fetchMonthHistory(widget.user.uid, now),
      builder: (context, snapshot) {
        final history = snapshot.data ?? {};
        final today = DateTime(now.year, now.month, now.day);
        final alreadyLoggedToday = history.containsKey(today);
        if (alreadyLoggedToday) return const SizedBox.shrink();

        final alt = _gamification.findQuickAlternative(
          allPlans: allPlans,
          level: _selectedLevel,
        );
        if (alt == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: GestureDetector(
            onTap: () => _handlePlanTap(alt, allPlans),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _kGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Colors.white, size: 26),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Short on time today?",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text("Try \"${alt.title}\" — just ${alt.minutes} min",
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Badges row
  // ---------------------------------------------------------------------

  Widget _buildBadgesRow() {
    return StreamBuilder<UserProgress>(
      stream: _gamification.watchProgress(
        widget.user.uid,
      ),
      builder: (context, snapshot) {
        final progress =
            snapshot.data ?? const UserProgress();

        return Padding(
          padding:
              const EdgeInsets.fromLTRB(20, 20, 0, 0),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Badges',
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Icon(
                    Icons.info_outline_rounded,
                    color: _kMuted,
                    size: 15,
                  ),
                  const Spacer(),
                  Text(
                    '${kBadgeCatalog.where((badge) => badge.isUnlocked(progress)).length}'
                    '/${kBadgeCatalog.length} unlocked',
                    style: const TextStyle(
                      color: _kMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
              ),
              const SizedBox(height: 12),

              SizedBox(
                height: 112,
                child: ListView.separated(
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  physics:
                      const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.only(right: 20),
                  itemCount: kBadgeCatalog.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final badge =
                        kBadgeCatalog[index];

                    // IMPORTANT:
                    // Existing badge logic remains the source of truth.
                    // We are only adding a clickable information UI.
                    final unlocked =
                        badge.isUnlocked(progress);

                    return InkWell(
                      borderRadius:
                          BorderRadius.circular(18),
                      onTap: () =>
                          _showBadgeDetails(
                        title: badge.title,
                        unlocked: unlocked,
                        progress: progress,
                      ),
                      child: Container(
                        width: 96,
                        padding:
                            const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: unlocked
                              ? const Color(
                                  0xFFE8F5E9,
                                )
                              : _kMintBg,
                          borderRadius:
                              BorderRadius.circular(
                            18,
                          ),
                          border: Border.all(
                            color: unlocked
                                ? _kGreen.withValues(alpha: 
                                    0.30,
                                  )
                                : _kBorder,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration:
                                  BoxDecoration(
                                color: unlocked
                                    ? Colors.orange
                                        .withValues(alpha: 
                                          0.12,
                                        )
                                    : const Color(
                                        0xFFE7EAE6,
                                      ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                unlocked
                                    ? Icons
                                        .emoji_events_rounded
                                    : Icons
                                        .lock_rounded,
                                color: unlocked
                                    ? Colors.orange
                                    : _kMuted,
                                size: 21,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              badge.title,
                              textAlign:
                                  TextAlign.center,
                              maxLines: 2,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unlocked
                                    ? _kInk
                                    : _kMuted,
                                fontWeight:
                                    FontWeight.w800,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              unlocked
                                  ? 'UNLOCKED'
                                  : 'TAP TO VIEW',
                              style: TextStyle(
                                color: unlocked
                                    ? _kGreen
                                    : _kMuted,
                                fontSize: 7.5,
                                fontWeight:
                                    FontWeight.w900,
                                letterSpacing: 0.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showBadgeDetails({
    required String title,
    required bool unlocked,
    required UserProgress progress,
  }) async {
    // Workout history is used only to give the user useful current progress.
    // It does NOT decide whether the badge is unlocked. The existing
    // badge.isUnlocked(progress) logic above remains unchanged.
    int completedWorkouts = 0;

    try {
      final history = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('workout_history')
          .get();

      completedWorkouts = history.docs.length;
    } catch (e) {
      debugPrint(
        'Badge workout count error: $e',
      );
    }

    if (!mounted) return;

    final info = _badgeInformation(title);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin:
                const EdgeInsets.fromLTRB(
              14,
              0,
              14,
              14,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(28),
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
                      color: const Color(
                        0xFFE1E5E0,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: unlocked
                            ? const Color(
                                0xFFFFF4D8,
                              )
                            : const Color(
                                0xFFF0F2EF,
                              ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        unlocked
                            ? Icons
                                .emoji_events_rounded
                            : Icons.lock_rounded,
                        color: unlocked
                            ? Colors.orange
                            : _kMuted,
                        size: 31,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            title,
                            style:
                                const TextStyle(
                              color: _kInk,
                              fontSize: 20,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                          const SizedBox(
                            height: 5,
                          ),
                          Container(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration:
                                BoxDecoration(
                              color: unlocked
                                  ? const Color(
                                      0xFFE8F5E9,
                                    )
                                  : const Color(
                                      0xFFF0F2EF,
                                    ),
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                20,
                              ),
                            ),
                            child: Text(
                              unlocked
                                  ? 'ACHIEVEMENT UNLOCKED'
                                  : 'LOCKED',
                              style: TextStyle(
                                color: unlocked
                                    ? _kGreen
                                    : _kMuted,
                                fontSize: 9,
                                fontWeight:
                                    FontWeight
                                        .w900,
                                letterSpacing:
                                    0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Text(
                  info.description,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 12,
                    height: 1.5,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 18),

                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: unlocked
                        ? const Color(
                            0xFFF2F8F2,
                          )
                        : const Color(
                            0xFFF7F8F6,
                          ),
                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                    border: Border.all(
                      color: unlocked
                          ? _kGreen.withValues(alpha: 
                              0.14,
                            )
                          : _kBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            unlocked
                                ? Icons
                                    .check_circle_rounded
                                : Icons
                                    .flag_rounded,
                            color: unlocked
                                ? _kGreen
                                : _kMuted,
                            size: 20,
                          ),
                          const SizedBox(
                            width: 8,
                          ),
                          Text(
                            unlocked
                                ? 'How you earned it'
                                : 'How to unlock',
                            style:
                                const TextStyle(
                              color: _kInk,
                              fontSize: 13,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      Text(
                        info.requirement,
                        style: TextStyle(
                          color: unlocked
                              ? _kGreen
                              : _kInk,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight:
                              FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),

                if (!unlocked) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Your current progress',
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 13,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child:
                            _badgeStatCard(
                          icon: Icons
                              .fitness_center_rounded,
                          value:
                              '$completedWorkouts',
                          label:
                              'Workouts',
                        ),
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Expanded(
                        child:
                            _badgeStatCard(
                          icon: Icons
                              .whatshot_rounded,
                          value:
                              '${progress.currentStreak}',
                          label:
                              'Day streak',
                        ),
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Expanded(
                        child:
                            _badgeStatCard(
                          icon: Icons
                              .trending_up_rounded,
                          value:
                              '${progress.level}',
                          label:
                              'Level',
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pop(
                      sheetContext,
                    ),
                    style:
                        ElevatedButton.styleFrom(
                      backgroundColor:
                          _kGreen,
                      foregroundColor:
                          Colors.white,
                      elevation: 0,
                      minimumSize:
                          const Size(
                        double.infinity,
                        48,
                      ),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          15,
                        ),
                      ),
                    ),
                    child: Text(
                      unlocked
                          ? 'GOT IT'
                          : 'KEEP GOING',
                      style: const TextStyle(
                        fontWeight:
                            FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _badgeStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F3),
        borderRadius:
            BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: _kGreen,
            size: 18,
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: _kInk,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _kMuted,
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  _BadgeDisplayInfo _badgeInformation(
    String title,
  ) {
    switch (title.trim().toLowerCase()) {
      case 'first step':
        return const _BadgeDisplayInfo(
          description:
              'Your first milestone for starting your workout journey.',
          requirement:
              'Complete your first workout.',
        );

      case 'consistent':
        return const _BadgeDisplayInfo(
          description:
              'Rewards you for building a regular workout habit.',
          requirement:
              'Build a 3-day workout streak.',
        );

      case 'streak master':
        return const _BadgeDisplayInfo(
          description:
              'A stronger consistency milestone for staying active across the week.',
          requirement:
              'Build a 7-day workout streak.',
        );

      case 'dedicated':
        return const _BadgeDisplayInfo(
          description:
              'Rewards long-term commitment and repeated workout completion.',
          requirement:
              'Complete 10 workouts.',
        );

      default:
        return const _BadgeDisplayInfo(
          description:
              'Keep training and improving your fitness progress to earn this achievement.',
          requirement:
              'Continue completing workouts and building your streak to unlock this badge.',
        );
    }
  }

  // ---------------------------------------------------------------------
  // Level selector (unchanged behavior, restyled into the list flow)
  // ---------------------------------------------------------------------

  Widget _buildLevelSelector(
    WorkoutLevel userCurrentLevel,
  ) {
    final levels = WorkoutLevel.values;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        20,
        20,
        0,
      ),
      child: Row(
        children: levels.map((level) {
          // Dynamic lock:
          // Beginner user -> Intermediate + Advanced locked
          // Intermediate user -> Advanced locked
          // Advanced user -> all levels available
          final isLocked =
              level.index > userCurrentLevel.index;
          final isSelected =
              level == _selectedLevel;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right:
                    level != levels.last ? 10 : 0,
              ),
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(22),
                onTap: isLocked
                    ? null
                    : () {
                        setState(() {
                          _selectedLevel = level;
                        });
                      },
                child: AnimatedContainer(
                  duration: const Duration(
                    milliseconds: 220,
                  ),
                  height: 54,
                  decoration: BoxDecoration(
                    color: isLocked
                        ? const Color(0xFFF0F1EE)
                        : isSelected
                            ? _kGreen
                            : Colors.white,
                    borderRadius:
                        BorderRadius.circular(18),
                    border: Border.all(
                      color: isLocked
                          ? Colors.transparent
                          : isSelected
                              ? _kGreen
                              : _kBorder,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color:
                                  _kGreen.withValues(alpha: 
                                0.16,
                              ),
                              blurRadius: 14,
                              offset:
                                  const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      if (isLocked) ...[
                        const Icon(
                          Icons.lock_rounded,
                          size: 15,
                          color:
                              Color(0xFF8B8F8A),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          level.name.toUpperCase(),
                          overflow:
                              TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isLocked
                                ? const Color(
                                    0xFF8B8F8A,
                                  )
                                : isSelected
                                    ? Colors.white
                                    : _kInk,
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w900,
                            letterSpacing: 0.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _displayPlanTitle(String title) {
    // Hide body weight from the Workout Plan card title only.
    // Examples:
    // "Intermediate 70kg Cardio Burn" -> "Intermediate Cardio Burn"
    // "70kg Beginner Cardio Burn" -> "Beginner Cardio Burn"
    // "Advanced 70 kg - Strength" -> "Advanced Strength"
    //
    // The original plan.title is NOT changed, so AI personalization,
    // Firestore, workout history, replay and navigation keep the real data.
    var cleaned = title.replaceAll(
      RegExp(
        r'\b\d+(?:\.\d+)?\s*kg\b\s*(?:[-:|]\s*)?',
        caseSensitive: false,
      ),
      '',
    );

    // Clean up spaces/punctuation that may remain after removing the weight.
    cleaned = cleaned
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'\s+([,:;])'), r'$1')
        .trim();

    return cleaned;
  }

  // ---------------------------------------------------------------------
  // Activity card
  // ---------------------------------------------------------------------

  Widget _buildActivityCard(
    WorkoutPlan plan,
    List<WorkoutPlan> allPlans,
  ) {
    final category = plan.category.toLowerCase();

    IconData icon;
    Color iconColor;
    Color iconBackground;

    if (category == 'strength') {
      icon = Icons.fitness_center_rounded;
      iconColor = _kGreen;
      iconBackground = const Color(0xFFEAF5EC);
    } else if (category == 'mobility') {
      icon = Icons.self_improvement_rounded;
      iconColor = const Color(0xFF6B73D9);
      iconBackground = const Color(0xFFF0F0FF);
    } else if (category == 'core') {
      icon =
          Icons.local_fire_department_rounded;
      iconColor = const Color(0xFFF07A3B);
      iconBackground = const Color(0xFFFFEFE7);
    } else if (category == 'full body') {
      icon = Icons.accessibility_new_rounded;
      iconColor = const Color(0xFF4F7FCE);
      iconBackground = const Color(0xFFEDF4FF);
    } else {
      icon = Icons.bolt_rounded;
      iconColor = const Color(0xFFFFA800);
      iconBackground = const Color(0xFFFFF7D9);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFE8ECE7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () =>
              _handlePlanTap(plan, allPlans),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius:
                        BorderRadius.circular(22),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayPlanTitle(plan.title),
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kInk,
                          fontSize: 15.5,
                          height: 1.18,
                          fontWeight:
                              FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 3,
                        children: [
                          Text(
                            plan.level.name
                                .toUpperCase(),
                            style: const TextStyle(
                              color: _kGreen,
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                          const Text(
                            '•',
                            style: TextStyle(
                              color: _kGreen,
                            ),
                          ),
                          Text(
                            plan.category,
                            style: const TextStyle(
                              color: _kGreen,
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),
                          const Text(
                            '•',
                            style: TextStyle(
                              color: _kGreen,
                            ),
                          ),
                          Text(
                            '${plan.calories} kcal',
                            style: const TextStyle(
                              color: _kGreen,
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),
                          const Text(
                            '•',
                            style: TextStyle(
                              color: _kGreen,
                            ),
                          ),
                          Text(
                            '${plan.minutes} Min',
                            style: const TextStyle(
                              color: _kGreen,
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF6F7F5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFADB2AC),
                    size: 21,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Burned-calorie history calendar
  // ---------------------------------------------------------------------

  Future<void> _showHistoryCalendar() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => _BurnHistoryCalendarDialog(
        uid: widget.user.uid,
        initialMonth: DateTime.now(),
      ),
    );
  }
}

class _BurnHistoryCalendarDialog extends StatefulWidget {
  final String uid;
  final DateTime initialMonth;

  const _BurnHistoryCalendarDialog({
    required this.uid,
    required this.initialMonth,
  });

  @override
  State<_BurnHistoryCalendarDialog> createState() =>
      _BurnHistoryCalendarDialogState();
}

class _BurnHistoryCalendarDialogState
    extends State<_BurnHistoryCalendarDialog> {
  late DateTime _visibleMonth;
  late Future<Map<DateTime, int>> _monthFuture;

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const _weekDays = [
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
    'S',
  ];

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(
      widget.initialMonth.year,
      widget.initialMonth.month,
      1,
    );
    _monthFuture = _loadMonth(_visibleMonth);
  }

  String _dateId(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<Map<DateTime, int>> _loadMonth(
    DateTime month,
  ) async {
    final start = DateTime(
      month.year,
      month.month,
      1,
    );
    final nextMonth = DateTime(
      month.year,
      month.month + 1,
      1,
    );

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('daily_logs')
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: _dateId(start),
        )
        .where(
          FieldPath.documentId,
          isLessThan: _dateId(nextMonth),
        )
        .get();

    final result = <DateTime, int>{};

    for (final doc in snapshot.docs) {
      final parts = doc.id.split('-');
      if (parts.length != 3) continue;

      final year = int.tryParse(parts[0]);
      final monthNumber = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);

      if (year == null ||
          monthNumber == null ||
          day == null) {
        continue;
      }

      final data = doc.data();

      // Current planner uses total_burned.
      // burned_calories is also supported for older/newer logs.
      final rawBurned =
          data['total_burned'] ??
          data['burned_calories'] ??
          0;

      final burned =
          rawBurned is num ? rawBurned.toInt() : 0;

      result[DateTime(year, monthNumber, day)] =
          burned;
    }

    return result;
  }

  void _changeMonth(int offset) {
    final next = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
      1,
    );

    // Do not navigate into future months.
    final now = DateTime.now();
    final currentMonth =
        DateTime(now.year, now.month, 1);

    if (next.isAfter(currentMonth)) return;

    setState(() {
      _visibleMonth = next;
      _monthFuture = _loadMonth(next);
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _visibleMonth.year == now.year &&
        _visibleMonth.month == now.month;
  }

  void _showDayDetails(
    DateTime date,
    int burned,
  ) {
    final startOfDay = DateTime(
      date.year,
      date.month,
      date.day,
    );

    final nextDay = startOfDay.add(
      const Duration(days: 1),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.68,
            child: Container(
              margin: const EdgeInsets.fromLTRB(
                14,
                0,
                14,
                14,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFBFDFA),
                borderRadius:
                    BorderRadius.circular(28),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFFD8DDD7,
                      ),
                      borderRadius:
                          BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
                      20,
                      18,
                      20,
                      14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration:
                              const BoxDecoration(
                            color:
                                Color(0xFFE8F5E9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons
                                .local_fire_department_rounded,
                            color: _kGreen,
                            size: 27,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                '${date.day} ${_monthNames[date.month - 1]} ${date.year}',
                                style:
                                    const TextStyle(
                                  color: _kInk,
                                  fontWeight:
                                      FontWeight
                                          .w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(
                                height: 3,
                              ),
                              Text(
                                '$burned kcal burned',
                                style:
                                    const TextStyle(
                                  color: _kGreen,
                                  fontWeight:
                                      FontWeight
                                          .w900,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding:
                        EdgeInsets.symmetric(
                      horizontal: 20,
                    ),
                    child: Divider(
                      height: 1,
                      color: Color(0xFFE8ECE7),
                    ),
                  ),
                  const Padding(
                    padding:
                        EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      10,
                    ),
                    child: Align(
                      alignment:
                          Alignment.centerLeft,
                      child: Text(
                        'Workouts Completed',
                        style: TextStyle(
                          color: _kInk,
                          fontSize: 16,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<
                        QuerySnapshot<
                            Map<String, dynamic>>>(
                      future: FirebaseFirestore
                          .instance
                          .collection('users')
                          .doc(widget.uid)
                          .collection(
                            'workout_history',
                          )
                          .where(
                            'completedAt',
                            isGreaterThanOrEqualTo:
                                Timestamp.fromDate(
                              startOfDay,
                            ),
                          )
                          .where(
                            'completedAt',
                            isLessThan:
                                Timestamp.fromDate(
                              nextDay,
                            ),
                          )
                          .orderBy(
                            'completedAt',
                            descending: true,
                          )
                          .get(),
                      builder:
                          (context, snapshot) {
                        if (snapshot
                                .connectionState ==
                            ConnectionState
                                .waiting) {
                          return const Center(
                            child:
                                CircularProgressIndicator(
                              color: _kGreen,
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return const Center(
                            child: Padding(
                              padding:
                                  EdgeInsets.all(
                                20,
                              ),
                              child: Text(
                                'Could not load workout details.',
                                textAlign:
                                    TextAlign
                                        .center,
                                style:
                                    TextStyle(
                                  color: _kMuted,
                                ),
                              ),
                            ),
                          );
                        }

                        final workouts =
                            snapshot.data?.docs ??
                                [];

                        if (workouts.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding:
                                  EdgeInsets.all(
                                20,
                              ),
                              child: Column(
                                mainAxisSize:
                                    MainAxisSize
                                        .min,
                                children: [
                                  Icon(
                                    Icons
                                        .fitness_center_rounded,
                                    color:
                                        _kMuted,
                                    size: 32,
                                  ),
                                  SizedBox(
                                    height: 8,
                                  ),
                                  Text(
                                    'No saved workout details for this day.',
                                    textAlign:
                                        TextAlign
                                            .center,
                                    style:
                                        TextStyle(
                                      color:
                                          _kMuted,
                                      fontSize:
                                          12,
                                      fontWeight:
                                          FontWeight
                                              .w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(
                            20,
                            0,
                            20,
                            24,
                          ),
                          itemCount:
                              workouts.length,
                          separatorBuilder:
                              (_, _) =>
                                  const SizedBox(
                            height: 10,
                          ),
                          itemBuilder:
                              (context, index) {
                            final data =
                                workouts[index]
                                    .data();

                            final title =
                                data['title']
                                        ?.toString() ??
                                    'Workout';

                            final category =
                                data['category']
                                        ?.toString() ??
                                    'Workout';

                            final calories =
                                (data['calories']
                                            as num?)
                                        ?.toInt() ??
                                    0;

                            final rawExercise =
                                data['exercise'];

                            final exercise =
                                rawExercise is Map
                                    ? rawExercise
                                    : null;

                            final activityName =
                                exercise?['name']
                                        ?.toString() ??
                                    'Workout activity';

                            final duration =
                                exercise?[
                                            'duration']
                                        ?.toString() ??
                                    '';

                            final completedAt =
                                data['completedAt']
                                    as Timestamp?;

                            final timeText =
                                completedAt ==
                                        null
                                    ? ''
                                    : _formatTime(
                                        completedAt
                                            .toDate(),
                                      );

                            return Container(
                              padding:
                                  const EdgeInsets
                                      .all(16),
                              decoration:
                                  BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  18,
                                ),
                                border:
                                    Border.all(
                                  color:
                                      const Color(
                                    0xFFE8ECE7,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration:
                                            const BoxDecoration(
                                          color: Color(
                                            0xFFE8F5E9,
                                          ),
                                          shape:
                                              BoxShape
                                                  .circle,
                                        ),
                                        child:
                                            const Icon(
                                          Icons
                                              .fitness_center_rounded,
                                          color:
                                              _kGreen,
                                          size: 21,
                                        ),
                                      ),
                                      const SizedBox(
                                        width: 12,
                                      ),
                                      Expanded(
                                        child:
                                            Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [
                                            Text(
                                              title,
                                              maxLines:
                                                  2,
                                              overflow:
                                                  TextOverflow
                                                      .ellipsis,
                                              style:
                                                  const TextStyle(
                                                color:
                                                    _kInk,
                                                fontWeight:
                                                    FontWeight.w900,
                                                fontSize:
                                                    14,
                                              ),
                                            ),
                                            const SizedBox(
                                              height:
                                                  3,
                                            ),
                                            Text(
                                              '$category • $calories kcal${timeText.isEmpty ? '' : ' • $timeText'}',
                                              style:
                                                  const TextStyle(
                                                color:
                                                    _kGreen,
                                                fontSize:
                                                    11,
                                                fontWeight:
                                                    FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: 12,
                                  ),
                                  Container(
                                    width:
                                        double.infinity,
                                    padding:
                                        const EdgeInsets
                                            .all(12),
                                    decoration:
                                        BoxDecoration(
                                      color:
                                          const Color(
                                        0xFFF4F7F3,
                                      ),
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                        14,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons
                                              .play_circle_outline_rounded,
                                          color:
                                              _kGreen,
                                          size: 20,
                                        ),
                                        const SizedBox(
                                          width: 8,
                                        ),
                                        Expanded(
                                          child:
                                              Text(
                                            activityName,
                                            style:
                                                const TextStyle(
                                              color:
                                                  _kInk,
                                              fontSize:
                                                  12,
                                              fontWeight:
                                                  FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        if (duration
                                            .isNotEmpty)
                                          Text(
                                            duration,
                                            style:
                                                const TextStyle(
                                              color:
                                                  _kMuted,
                                              fontSize:
                                                  10,
                                              fontWeight:
                                                  FontWeight.w700,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
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

  String _formatTime(DateTime date) {
    final hour =
        date.hour.toString().padLeft(2, '0');
    final minute =
        date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 28,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: FutureBuilder<Map<DateTime, int>>(
        future: _monthFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const SizedBox(
              height: 350,
              child: Center(
                child: CircularProgressIndicator(
                  color: _kGreen,
                ),
              ),
            );
          }

          final burnedByDay =
              snapshot.data ?? <DateTime, int>{};

          final totalBurned =
              burnedByDay.values.fold<int>(
            0,
            (total, value) => total + value,
          );

          final activeDays = burnedByDay.values
              .where((value) => value > 0)
              .length;

          final firstOfMonth = DateTime(
            _visibleMonth.year,
            _visibleMonth.month,
            1,
          );

          final daysInMonth = DateTime(
            _visibleMonth.year,
            _visibleMonth.month + 1,
            0,
          ).day;

          final leadingBlanks =
              firstOfMonth.weekday - 1;

          final itemCount =
              leadingBlanks + daysInMonth;

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.of(context).size.height *
                      0.82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header + month navigation
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () =>
                            _changeMonth(-1),
                        icon: const Icon(
                          Icons
                              .chevron_left_rounded,
                          color: _kInk,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                              textAlign:
                                  TextAlign.center,
                              style:
                                  const TextStyle(
                                color: _kInk,
                                fontWeight:
                                    FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'CALORIE HISTORY',
                              style: TextStyle(
                                color: _kMuted,
                                fontSize: 9,
                                fontWeight:
                                    FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: _isCurrentMonth
                            ? null
                            : () =>
                                _changeMonth(1),
                        icon: Icon(
                          Icons
                              .chevron_right_rounded,
                          color: _isCurrentMonth
                              ? const Color(
                                  0xFFD7DAD6,
                                )
                              : _kInk,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Monthly summary
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFE8F5E9),
                      borderRadius:
                          BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _summaryItem(
                            icon: Icons
                                .local_fire_department_rounded,
                            value:
                                '$totalBurned kcal',
                            label:
                                'Total burned',
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 38,
                          color: _kGreen.withValues(alpha: 
                            0.15,
                          ),
                        ),
                        Expanded(
                          child: _summaryItem(
                            icon: Icons
                                .calendar_month_rounded,
                            value:
                                '$activeDays days',
                            label:
                                'Active days',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Weekday row
                  Row(
                    children: _weekDays
                        .map(
                          (day) => Expanded(
                            child: Center(
                              child: Text(
                                day,
                                style:
                                    const TextStyle(
                                  color: _kMuted,
                                  fontSize: 10,
                                  fontWeight:
                                      FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),

                  const SizedBox(height: 8),

                  GridView.builder(
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),
                    itemCount: itemCount,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 0.78,
                    ),
                    itemBuilder: (context, index) {
                      if (index < leadingBlanks) {
                        return const SizedBox.shrink();
                      }

                      final day =
                          index - leadingBlanks + 1;

                      final date = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month,
                        day,
                      );

                      final burned =
                          burnedByDay[date] ?? 0;

                      final hasData = burned > 0;

                      final now = DateTime.now();
                      final isToday =
                          date.year == now.year &&
                          date.month == now.month &&
                          date.day == now.day;

                      return GestureDetector(
                        onTap: hasData
                            ? () =>
                                _showDayDetails(
                                  date,
                                  burned,
                                )
                            : null,
                        child: Container(
                          margin:
                              const EdgeInsets.all(
                            2.5,
                          ),
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 5,
                            horizontal: 2,
                          ),
                          decoration: BoxDecoration(
                            color: hasData
                                ? const Color(
                                    0xFFE8F5E9,
                                  )
                                : const Color(
                                    0xFFF6F8F5,
                                  ),
                            borderRadius:
                                BorderRadius.circular(
                              12,
                            ),
                            border: Border.all(
                              color: isToday
                                  ? Colors.orange
                                  : hasData
                                      ? _kGreen
                                          .withValues(alpha: 
                                            0.18,
                                          )
                                      : Colors
                                          .transparent,
                              width: isToday
                                  ? 1.5
                                  : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .center,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  color: hasData
                                      ? _kInk
                                      : _kMuted,
                                  fontWeight:
                                      FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(
                                height: 3,
                              ),
                              if (hasData)
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '$burned',
                                    style:
                                        const TextStyle(
                                      color: _kGreen,
                                      fontSize: 8,
                                      fontWeight:
                                          FontWeight
                                              .w900,
                                    ),
                                  ),
                                )
                              else
                                const Text(
                                  '—',
                                  style: TextStyle(
                                    color: Color(
                                      0xFFC4C8C3,
                                    ),
                                    fontSize: 8,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  const Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons
                            .local_fire_department_rounded,
                        color: _kGreen,
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Number under each date = kcal burned',
                        style: TextStyle(
                          color: _kMuted,
                          fontSize: 10,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _summaryItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: _kGreen,
          size: 20,
        ),
        const SizedBox(height: 5),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _kGreen,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _kMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
