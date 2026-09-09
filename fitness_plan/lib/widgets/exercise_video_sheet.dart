import 'package:flutter/material.dart';

import 'youtube_webview_player.dart';

const _kGreen = Color(0xFF2E7D32);
const _kInk = Color(0xFF191C19);
const _kMuted = Color(0xFF747972);

Future<bool?> showExerciseVideoSheet({
  required BuildContext context,
  required String exerciseName,
  required String category,
  required String levelLabel,
  String? youtubeApiKey,
}) async {
  if (!context.mounted) return null;

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ExerciseVideoSheet(
      exerciseName: exerciseName,
      category: category,
      levelLabel: levelLabel,
      youtubeApiKey: youtubeApiKey,
    ),
  );
}

class _ExerciseVideoSheet extends StatefulWidget {
  final String exerciseName;
  final String category;
  final String levelLabel;
  final String? youtubeApiKey;

  const _ExerciseVideoSheet({
    required this.exerciseName,
    required this.category,
    required this.levelLabel,
    this.youtubeApiKey,
  });

  @override
  State<_ExerciseVideoSheet> createState() => _ExerciseVideoSheetState();
}

class _ExerciseVideoSheetState extends State<_ExerciseVideoSheet> {
  bool _tutorialCompleted = false;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;

    return Container(
      height: height * 0.95,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E5E5),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.exerciseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kInk,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${widget.levelLabel} • 10–15 minute workout video',
                        style: const TextStyle(
                          color: _kMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close_rounded, color: _kMuted, size: 30),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // No large horizontal padding here: the player can use almost the
          // entire width of the bottom sheet.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 20),
              child: YoutubeWebViewPlayer(
                exerciseName: widget.exerciseName,
                category: widget.category,
                levelLabel: widget.levelLabel,
                youtubeApiKey: widget.youtubeApiKey,
                rounded: true,
                onCompleted: () {
                  if (!mounted) return;
                  setState(() => _tutorialCompleted = true);
                },
              ),
            ),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: ElevatedButton.icon(
                onPressed: _tutorialCompleted
                    ? () => Navigator.pop(context, true)
                    : null,
                icon: Icon(
                  _tutorialCompleted
                      ? Icons.check_circle_rounded
                      : Icons.lock_rounded,
                  color: Colors.white,
                ),
                label: Text(
                  _tutorialCompleted
                      ? 'VIDEO COMPLETED'
                      : 'FINISH VIDEO TO UNLOCK',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  disabledBackgroundColor: const Color(0xFFC9CCC9),
                  disabledForegroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
