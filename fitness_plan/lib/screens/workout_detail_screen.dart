import 'package:flutter/material.dart';
import '../models/workout_model.dart';
import '../models/user_model.dart';
import 'workout_timer_screen.dart';
import '../widgets/exercise_video_sheet.dart';

const _kGreen = Color(0xFF2E7D32);
const _kInk = Color(0xFF191C19);
const _kMuted = Color(0xFF747972);

class WorkoutDetailScreen extends StatefulWidget {
  final WorkoutPlan plan;
  final UserModel user;

  const WorkoutDetailScreen({
    super.key,
    required this.plan,
    required this.user,
  });

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  String _getLevelText(WorkoutLevel level) {
    switch (level) {
      case WorkoutLevel.beginner:
        return 'Beginner';
      case WorkoutLevel.intermediate:
        return 'Intermediate';
      case WorkoutLevel.advanced:
        return 'Advanced';
    }
  }


  String _getWorkoutImage() {
    final category = widget.plan.category.toLowerCase();
    final title = widget.plan.title.toLowerCase();

    if (category.contains('cardio') ||
        title.contains('run') ||
        title.contains('jog')) {
      return 'assets/workouts/cardio.jpg';
    }

    if (category.contains('strength') ||
        title.contains('strength')) {
      return 'assets/workouts/strength.jpg';
    }

    if (category.contains('yoga')) {
      return 'assets/workouts/yoga.jpg';
    }

    if (category.contains('mobility') ||
        category.contains('recovery')) {
      return 'assets/workouts/mobility.jpg';
    }

    if (category.contains('core') ||
        category.contains('plank')) {
      return 'assets/workouts/core.jpg';
    }

    if (category.contains('leg')) {
      return 'assets/workouts/legs.jpg';
    }

    if (category.contains('arm') ||
        category.contains('upper')) {
      return 'assets/workouts/upper_body.jpg';
    }

    if (category.contains('hiit')) {
      return 'assets/workouts/hiit.jpg';
    }

    return 'assets/workouts/default_workout.jpg';
  }

  Future<void> _openWorkoutVideo() async {
    await showExerciseVideoSheet(
      context: context,
      exerciseName: widget.plan.title,
      category: widget.plan.category,
      levelLabel: _getLevelText(widget.plan.level),
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
        border: Border.all(color: const Color(0xFFF0F0F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFDFA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    _getWorkoutImage(),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: const Color(0xFFF1F8F1),
                        child: Center(
                          child: Icon(
                            Icons.fitness_center_rounded,
                            size: 80,
                            color: _kGreen.withOpacity(0.2),
                          ),
                        ),
                      );
                    },
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.10),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.black,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.plan.title,
                              style: const TextStyle(
                                color: _kInk,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              widget.plan.subtitle,
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _kGreen,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Text(
                          '10–15 MIN\nPER VIDEO',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      _buildInfoChip(
                        icon: Icons.bar_chart,
                        label: _getLevelText(widget.plan.level),
                        color: _kMuted,
                      ),
                      const SizedBox(width: 15),
                      _buildInfoChip(
                        icon: Icons.local_fire_department,
                        label: '${widget.plan.calories} kcal',
                        color: Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  GestureDetector(
                    onTap: _openWorkoutVideo,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4EF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFFE8F5E9),
                        ),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 52,
                            height: 52,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                              ),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Preview workout video',
                                  style: TextStyle(
                                    color: _kInk,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'One 10–15 minute follow-along video for this activity',
                                  style: TextStyle(
                                    color: _kMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.open_in_new_rounded,
                            color: _kGreen,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  const Text(
                    'Workout',
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.plan.exercises.length,
                    itemBuilder: (context, index) => _buildExerciseCard(index),
                  ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(25, 8, 25, 24),
          color: const Color(0xFFFBFDFA),
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkoutTimerScreen(
                    plan: widget.plan,
                    user: widget.user,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              minimumSize: const Size(double.infinity, 65),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 8,
              shadowColor: _kGreen.withOpacity(0.3),
            ),
            child: const Text(
              'START WORKOUT',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(int index) {
    final exercise = widget.plan.exercises[index];
    final caption = exercise.instructions.isNotEmpty
        ? exercise.instructions.first
        : '';

    return _buildCleanCard(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: const TextStyle(
                    color: _kGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '10–15 min video',
                  style: TextStyle(
                    color: _kGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (exercise.reps.isNotEmpty && exercise.reps != '-') ...[
                const Icon(Icons.repeat_rounded, size: 13, color: _kMuted),
                const SizedBox(width: 4),
                Text(
                  exercise.reps,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              const Icon(
                Icons.local_fire_department_rounded,
                size: 13,
                color: Colors.orange,
              ),
              const SizedBox(width: 4),
              Text(
                '${exercise.caloriesBurned} kcal',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              caption,
              style: const TextStyle(
                color: _kMuted,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4EF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE8F5E9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
