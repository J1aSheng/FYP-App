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
            color: Colors.black.withOpacity(0.04),
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

  Future<void> _handlePlanTap(WorkoutPlan plan, List<WorkoutPlan> allPlans) async {
    if (_todaysEnergy == null) {
      final energy = await showEnergyCheckIn(context);
      if (energy == null) return; // dismissed, don't force a choice
      setState(() => _todaysEnergy = energy);
    }

    WorkoutPlan planToOpen = plan;

    // If energy is low/medium, offer the gentlest (lowest-calorie) plan at
    // this level instead of forcing the tapped one — no fixed category
    // names involved, so this works no matter what the AI calls things.
    if (_todaysEnergy != EnergyLevel.high) {
      final alt = _gamification.findGentlerAlternative(
        allPlans: allPlans,
        level: _selectedLevel,
        excluding: plan,
      );
      if (alt != null && alt.calories < plan.calories) {
        final swap = await _confirmSwap(original: plan, alternative: alt);
        if (swap == true) planToOpen = alt;
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => WorkoutDetailScreen(plan: planToOpen, user: widget.user)),
    );
  }

  Future<bool?> _confirmSwap({required WorkoutPlan original, required WorkoutPlan alternative}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Take it easier today?", style: TextStyle(color: _kInk, fontWeight: FontWeight.w900)),
        content: Text(
          "Since you're a bit low on energy, \"${alternative.title}\" might feel better than \"${original.title}\".",
          style: const TextStyle(color: _kMuted, fontWeight: FontWeight.w500, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Keep original", style: TextStyle(color: _kMuted, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text("Switch me", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String todayId = DateTime.now().toString().split(' ')[0];
    final userCurrentLevel = _parseLevel(widget.user.level);

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
          final levelPlans = allPlans.where((p) => p.level == _selectedLevel).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              _buildProgressHeader(todayId),
              _buildQuickSuggestionBanner(allPlans),
              _buildBadgesRow(),
              _buildLevelSelector(userCurrentLevel),
              if (levelPlans.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 15),
                        child: Text("Your AI Plans", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _kGreen)),
                      ),
                      ...levelPlans.map((plan) => _buildActivityCard(plan, allPlans)),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              if (allPlans.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: Text("No activities found.", style: TextStyle(color: _kMuted))),
                )
              else if (levelPlans.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: Text("No plans at this level yet — try another level.", style: TextStyle(color: _kMuted))),
                ),
            ],
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.user.uid)
                .collection('daily_logs')
                .doc(todayId)
                .snapshots(),
            builder: (context, snapshot) {
              int burned = 0;
              if (snapshot.hasData && snapshot.data!.exists) {
                burned = (snapshot.data!.data() as Map<String, dynamic>)['total_burned'] ?? 0;
              }
              return Container(
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(25)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(children: [
                    const Icon(Icons.local_fire_department_rounded, color: _kGreen, size: 40),
                    const SizedBox(width: 15),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text("Today's Progress", style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                      Text("$burned kcal burned", style: const TextStyle(color: _kGreen, fontWeight: FontWeight.w900, fontSize: 20)),
                    ]),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.calendar_month_rounded, color: _kGreen),
                      onPressed: _showHistoryCalendar,
                    ),
                  ]),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<UserProgress>(
            stream: _gamification.watchProgress(widget.user.uid),
            builder: (context, snapshot) {
              final progress = snapshot.data ?? const UserProgress();
              return _buildCleanCard(
                child: Row(
                  children: [
                    _streakBadge(progress.currentStreak),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text("LEVEL ${progress.level}",
                                  style: const TextStyle(color: _kInk, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                              const Spacer(),
                              Text("${progress.xpIntoLevel}/100 XP",
                                  style: const TextStyle(color: _kMuted, fontWeight: FontWeight.w700, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progress.levelProgress,
                              minHeight: 8,
                              backgroundColor: _kMintBg,
                              color: _kGreen,
                            ),
                          ),
                        ],
                      ),
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

  Widget _streakBadge(int streak) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: _kMintBg, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE8F5E9))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.whatshot_rounded, color: Colors.orange, size: 18),
          Text("$streak", style: const TextStyle(color: _kInk, fontWeight: FontWeight.w900, fontSize: 14)),
        ],
      ),
    );
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
      stream: _gamification.watchProgress(widget.user.uid),
      builder: (context, snapshot) {
        final progress = snapshot.data ?? const UserProgress();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Badges", style: TextStyle(color: _kInk, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 20),
                  itemCount: kBadgeCatalog.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final badge = kBadgeCatalog[index];
                    final unlocked = badge.isUnlocked(progress);
                    return Container(
                      width: 88,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: unlocked ? const Color(0xFFE8F5E9) : _kMintBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: unlocked ? _kGreen.withOpacity(0.3) : _kBorder),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            unlocked ? Icons.emoji_events_rounded : Icons.lock_rounded,
                            color: unlocked ? Colors.orange : _kMuted,
                            size: 22,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            badge.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: TextStyle(
                              color: unlocked ? _kInk : _kMuted,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
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
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Level selector (unchanged behavior, restyled into the list flow)
  // ---------------------------------------------------------------------

  Widget _buildLevelSelector(WorkoutLevel userCurrentLevel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: WorkoutLevel.values.map((level) {
          bool isSelected = _selectedLevel == level;
          bool isLocked = level.index > userCurrentLevel.index;

          return GestureDetector(
            onTap: isLocked ? null : () => setState(() => _selectedLevel = level),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? _kGreen : (isLocked ? _kBorder : Colors.white),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? Colors.transparent : _kBorder),
              ),
              child: Row(
                children: [
                  if (isLocked)
                    const Padding(
                      padding: EdgeInsets.only(right: 5),
                      child: Icon(Icons.lock_rounded, size: 14, color: _kMuted),
                    ),
                  Text(
                    level.name.toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? Colors.white : (isLocked ? _kMuted : _kInk),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Activity card
  // ---------------------------------------------------------------------

  Widget _buildActivityCard(WorkoutPlan plan, List<WorkoutPlan> allPlans) {
    return GestureDetector(
      onTap: () => _handlePlanTap(plan, allPlans),
      child: _buildCleanCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF8E1), shape: BoxShape.circle),
            child: const Icon(Icons.bolt_rounded, color: Colors.orange, size: 22),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plan.title, style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text("${plan.category} • ${plan.calories} kcal • ${plan.minutes} Min",
                  style: const TextStyle(color: _kGreen, fontSize: 12, fontWeight: FontWeight.w900)),
            ]),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: _kBorder, size: 16),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // History calendar dialog
  // ---------------------------------------------------------------------

  Future<void> _showHistoryCalendar() async {
    final now = DateTime.now();
    final history = await _gamification.fetchMonthHistory(widget.user.uid, now);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _MonthCalendar(month: now, completedDays: history),
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final Map<DateTime, int> completedDays;
  const _MonthCalendar({required this.month, required this.completedDays});

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday = 1 ... Sunday = 7 -> leading blanks before day 1
    final leadingBlanks = firstOfMonth.weekday - 1;
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("${monthNames[month.month - 1]} ${month.year}",
            style: const TextStyle(color: _kInk, fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leadingBlanks + daysInMonth,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = index - leadingBlanks + 1;
            final date = DateTime(month.year, month.month, day);
            final completed = completedDays.containsKey(date);
            final isToday = date.year == DateTime.now().year &&
                date.month == DateTime.now().month &&
                date.day == DateTime.now().day;

            return Container(
              margin: const EdgeInsets.all(3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: completed ? _kGreen : _kMintBg,
                shape: BoxShape.circle,
                border: isToday ? Border.all(color: Colors.orange, width: 2) : null,
              ),
              child: Text(
                "$day",
                style: TextStyle(
                  color: completed ? Colors.white : _kMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text("${completedDays.length} active days this month",
            style: const TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}