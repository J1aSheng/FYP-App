import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_model.dart';
import '../models/user_model.dart';
import '../services/database_service.dart';
import '../services/gamification_service.dart';
import '../widgets/inline_video_player.dart';

const _kGreen = Color(0xFF2E7D32);
const _kInk = Color(0xFF191C19);
const _kMuted = Color(0xFF747972);
const _kBg = Color(0xFFFBFDFA);
const _kBorder = Color(0xFFF0F0F0);
const _kMintBg = Color(0xFFF0F4EF);

class WorkoutTimerScreen extends StatefulWidget {
  final WorkoutPlan plan;
  final UserModel user;

  const WorkoutTimerScreen({
    super.key,
    required this.plan,
    required this.user,
  });

  @override
  State<WorkoutTimerScreen> createState() => _WorkoutTimerScreenState();
}

class _WorkoutTimerScreenState extends State<WorkoutTimerScreen> {
  int _currentActivityIndex = 0;

  // IMPORTANT: there is no independent Flutter countdown anymore.
  // The YouTube video clock is the only source of truth.
  Duration _videoDuration = Duration.zero;
  Duration _videoPosition = Duration.zero;
  bool _videoPlaying = false;
  bool _videoCompleted = false;

  final _db = DatabaseService();
  final _gamification = GamificationService();

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

  Duration get _remainingVideoTime {
    if (_videoDuration == Duration.zero) return Duration.zero;
    final remaining = _videoDuration - _videoPosition;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  double get _videoProgress {
    if (_videoDuration.inMilliseconds <= 0) return 0.0;
    return (_videoPosition.inMilliseconds / _videoDuration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get _remainingText {
    if (_videoDuration == Duration.zero) return '--:--';
    return _formatDuration(_remainingVideoTime);
  }

  void _resetVideoState() {
    _videoDuration = Duration.zero;
    _videoPosition = Duration.zero;
    _videoPlaying = false;
    _videoCompleted = false;
  }

  void _onVideoDurationReady(Duration duration) {
    if (!mounted) return;
    setState(() {
      _videoDuration = duration;
    });
  }

  void _onVideoProgressChanged(Duration position, Duration duration) {
    if (!mounted) return;
    setState(() {
      _videoPosition = position;
      _videoDuration = duration;
    });
  }

  void _onVideoPlayingChanged(bool playing) {
    if (!mounted) return;
    setState(() {
      _videoPlaying = playing;
    });
  }

  void _onVideoFinished() {
    if (!mounted || _videoCompleted) return;

    setState(() {
      _videoCompleted = true;
      _videoPlaying = false;
      if (_videoDuration > Duration.zero) {
        _videoPosition = _videoDuration;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _currentActivityIndex == widget.plan.exercises.length - 1
              ? 'Video finished! You can complete the workout.'
              : 'Video finished! You can move to the next exercise.',
        ),
        backgroundColor: _kGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _moveToNextActivity() {
    if (!_videoCompleted) return;

    if (_currentActivityIndex < widget.plan.exercises.length - 1) {
      setState(() {
        _currentActivityIndex++;
        _resetVideoState();
      });
    } else {
      _finishWorkout();
    }
  }

  Future<void> _saveWorkoutHistory() async {
    if (widget.plan.exercises.isEmpty) return;

    final exercise = widget.plan.exercises.first;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('workout_history')
          .add({
        'title': widget.plan.title,
        'subtitle': widget.plan.subtitle,
        'category': widget.plan.category,
        'minutes': widget.plan.minutes,
        'calories': widget.plan.calories,
        'level': widget.plan.level.index,
        'imagePath': widget.plan.imagePath,
        'completedAt': FieldValue.serverTimestamp(),
        'exercise': {
          'name': exercise.name,
          'reps': exercise.reps,
          'duration': exercise.duration,
          'caloriesBurned': exercise.caloriesBurned,
          'instructions': exercise.instructions,
        },
      });
    } catch (e) {
      debugPrint('Workout history save error: $e');
    }
  }

  Future<void> _finishWorkout() async {
    try {
      await _db.logWorkoutActivity(
        uid: widget.user.uid,
        calories: widget.plan.calories,
        workoutTitle: widget.plan.title,
      );
    } catch (e) {
      debugPrint('Database sync error: $e');
    }

    await _saveWorkoutHistory();

    try {
      await _gamification.recordWorkoutCompletion(
        uid: widget.user.uid,
        caloriesBurned: widget.plan.calories,
      );
    } catch (e) {
      debugPrint('Gamification sync error: $e');
    }

    if (mounted) _showCompletionDialog();
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

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kMintBg,
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

  @override
  Widget build(BuildContext context) {
    if (widget.plan.exercises.isEmpty) {
      return Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        body: const Center(child: Text('No exercises found for this plan.')),
      );
    }

    final exercise = widget.plan.exercises.first;
    final caption = exercise.instructions.isNotEmpty
        ? exercise.instructions.first
        : '';

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: _kInk, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'WORKOUT VIDEO',
          style: const TextStyle(
            color: _kMuted,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.plan.subtitle,
                        style: const TextStyle(
                          color: _kMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: _kGreen,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    _videoDuration == Duration.zero
                        ? '10–15 MIN VIDEO'
                        : '${_formatDuration(_videoDuration)} VIDEO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildInfoChip(
                  icon: Icons.bar_chart,
                  label: _getLevelText(widget.plan.level),
                  color: _kMuted,
                ),
                const SizedBox(width: 12),
                _buildInfoChip(
                  icon: Icons.local_fire_department,
                  label: '${widget.plan.calories} kcal',
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 26),

            const SizedBox(height: 8),
            const Text(
              'Workout Activity',
              style: TextStyle(
                color: _kInk,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
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
                            if (exercise.reps.isNotEmpty &&
                                exercise.reps != '-') ...[
                              Text(
                                exercise.reps,
                                style: const TextStyle(
                                  color: _kMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Text(
                              _videoDuration == Duration.zero
                                  ? '10–15 min'
                                  : _formatDuration(_videoDuration),
                              style: const TextStyle(
                                color: _kMuted,
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
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 15),
                          child: Divider(color: _kBorder, height: 1),
                        ),
                      ],
                    ),
                  ),

                  // Larger video area: almost full width of the card.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                    child: InlineVideoPlayer(
                      key: ValueKey(widget.plan.title),
                      exerciseName: widget.plan.title,
                      category: widget.plan.category,
                      levelLabel: _getLevelText(widget.plan.level),
                      onDurationReady: _onVideoDurationReady,
                      onProgressChanged: _onVideoProgressChanged,
                      onPlayingChanged: _onVideoPlayingChanged,
                      onVideoEnded: _onVideoFinished,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          color: _kBg,
          child: ElevatedButton(
            onPressed: _videoCompleted ? _finishWorkout : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              disabledBackgroundColor: Colors.grey.shade400,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: _videoCompleted ? 8 : 0,
              shadowColor: _kGreen.withValues(alpha: 0.3),
            ),
            child: Text(
              _videoCompleted
                  ? 'COMPLETE WORKOUT'
                  : 'FINISH VIDEO TO UNLOCK',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Workout Completed!',
          style: TextStyle(color: _kInk, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
        ),
        content: Text(
          'You burned ${widget.plan.calories} kcal. Streak and XP updated.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kMuted),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'FINISH',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
