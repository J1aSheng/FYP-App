import 'dart:async';
import 'package:flutter/material.dart';
import '../models/workout_model.dart';
import '../models/user_model.dart'; 
import '../services/database_service.dart';
import '../services/gamification_service.dart';
import '../services/youtube_suggestion_service.dart';
import 'package:url_launcher/url_launcher.dart';

class WorkoutTimerScreen extends StatefulWidget {
  final WorkoutPlan plan;
  final UserModel user; 
  const WorkoutTimerScreen({super.key, required this.plan, required this.user});

  @override
  State<WorkoutTimerScreen> createState() => _WorkoutTimerScreenState();
}

class _WorkoutTimerScreenState extends State<WorkoutTimerScreen> with TickerProviderStateMixin {
  // --- ✅ 邏輯完全保留自 Source 12 ---
  int _currentActivityIndex = 0; 
  int _activeStepIndex = 0; 
  late int _remainingSeconds;
  late int _totalActivitySeconds;
  Timer? _timer;
  bool _isActive = true;
  final _db = DatabaseService();
  final _gamification = GamificationService();
  final _youtube = YoutubeSuggestionService();

  @override
  void initState() {
    super.initState();
    _initTimerForActivity();
  }

  void _initTimerForActivity() {
    String durationStr = widget.plan.exercises[_currentActivityIndex].duration;
    int timeValue = int.tryParse(durationStr.split(' ')[0]) ?? 60;
    _totalActivitySeconds = durationStr.toLowerCase().contains('min') ? timeValue * 60 : timeValue;
    _remainingSeconds = _totalActivitySeconds;
    _activeStepIndex = 0; 
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel(); 
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        if (_isActive) {
          setState(() {
            _remainingSeconds--;
            _updateCycleLogic(); 
          });
        }
      } else {
        _moveToNextActivity();
      }
    });
  }

  void _updateCycleLogic() {
    // instructions is a real array now — no more regex-splitting a blob string.
    final steps = widget.plan.exercises[_currentActivityIndex].instructions;

    if (steps.isEmpty) return;
    int secondsPerStep = 6; 
    int totalCycleTime = steps.length * secondsPerStep;
    int elapsed = _totalActivitySeconds - _remainingSeconds;
    int newStepIndex = (elapsed % totalCycleTime) ~/ secondsPerStep;
    if (_activeStepIndex != newStepIndex) {
      setState(() => _activeStepIndex = newStepIndex);
    }
  }

  void _moveToNextActivity() {
    if (_currentActivityIndex < widget.plan.exercises.length - 1) {
      setState(() {
        _currentActivityIndex++;
        _isActive = true;
      });
      _initTimerForActivity();
    } else {
      _timer?.cancel();
      _finishWorkout();
    }
  }

  Future<void> _finishWorkout() async {
    try {
      await _db.logWorkoutActivity(
        uid: widget.user.uid, 
        calories: widget.plan.calories,
        workoutTitle: widget.plan.title,
      );
    } catch (e) { if (mounted) debugPrint("Sync Error: $e"); }

    try {
      // Extends the streak and awards XP — feeds the plan screen's
      // streak/level header, badges row, and history calendar.
      await _gamification.recordWorkoutCompletion(
        uid: widget.user.uid,
        caloriesBurned: widget.plan.calories,
      );
    } catch (e) { if (mounted) debugPrint("Gamification sync error: $e"); }

    _showCompletionDialog();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildCleanCard({required Widget child, EdgeInsets? margin}) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
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
        padding: const EdgeInsets.all(25),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.plan.exercises[_currentActivityIndex];
    // instructions is a real array now — no regex parsing needed here either.
    final List<String> steps = ex.instructions;

    // Defensive: fall back if the index ever overflows.
    final String currentStepText = (steps.length > _activeStepIndex) 
        ? steps[_activeStepIndex] 
        : steps.isNotEmpty ? steps[0] : "Follow the exercise guidance.";

    return Scaffold(
      backgroundColor: const Color(0xFFFBFDFA), 
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF191C19)), 
                    onPressed: () => Navigator.pop(context)
                  ),
                  const Text(
                    "SESSION IN PROGRESS", 
                    style: TextStyle(color: Color(0xFF747972), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900)
                  ),
                  const SizedBox(width: 48), 
                ],
              ),
            ),

            const Spacer(),

            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 280, height: 280,
                  child: CircularProgressIndicator(
                    value: _remainingSeconds / _totalActivitySeconds,
                    strokeWidth: 8,
                    backgroundColor: const Color(0xFFF0F4EF),
                    color: const Color(0xFF2E7D32), 
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(_remainingSeconds),
                      style: const TextStyle(color: Color(0xFF191C19), fontSize: 80, fontWeight: FontWeight.w200),
                    ),
                    Text(
                      ex.name.toUpperCase(), 
                      style: const TextStyle(color: Color(0xFF747972), letterSpacing: 3, fontSize: 12, fontWeight: FontWeight.w800)
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _openExerciseDemo(ex.name),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_outline_rounded, color: Color(0xFF2E7D32), size: 16),
                          SizedBox(width: 5),
                          Text(
                            "WATCH DEMO",
                            style: TextStyle(color: Color(0xFF2E7D32), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const Spacer(),

            _buildCleanCard(
              margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
              child: Column(
                children: [
                  const Text(
                    "CURRENT ACTION", 
                    style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 10)
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      currentStepText,
                      key: ValueKey<int>(_activeStepIndex),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF191C19), fontSize: 22, fontWeight: FontWeight.w600, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  GestureDetector(
                    onTap: () => setState(() => _isActive = !_isActive),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: Color(0xFF2E7D32), 
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0x332E7D32), blurRadius: 15, offset: Offset(0, 8))
                        ]
                      ),
                      child: Icon(
                        _isActive ? Icons.pause_rounded : Icons.play_arrow_rounded, 
                        color: Colors.white, 
                        size: 35
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    int mins = seconds ~/ 60;
    int secs = seconds % 60;
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  Future<void> _openExerciseDemo(String exerciseName) async {
    final suggestion = await _youtube.suggestVideo(
      exerciseName: exerciseName,
      category: widget.plan.category,
      levelLabel: widget.plan.level.name,
    );
    final uri = Uri.parse(suggestion.url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open YouTube — check that a browser/YouTube app is installed.")),
        );
      }
    } catch (e) {
      debugPrint("Could not open video link: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open YouTube — check that a browser/YouTube app is installed.")),
        );
      }
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text(
          "Well Done!", 
          style: TextStyle(color: Color(0xFF191C19), fontWeight: FontWeight.w900), 
          textAlign: TextAlign.center
        ),
        content: const Text(
          "Activity cycle complete. Your progress has been synced.", 
          style: TextStyle(color: Color(0xFF747972), fontWeight: FontWeight.w500), 
          textAlign: TextAlign.center
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: ElevatedButton(
              onPressed: () { 
                Navigator.pop(context); 
                Navigator.pop(context); 
              }, 
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32), 
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: const Text(
                "FINISH", 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)
              ),
            ),
          ),
        ],
      ),
    );
  }
}