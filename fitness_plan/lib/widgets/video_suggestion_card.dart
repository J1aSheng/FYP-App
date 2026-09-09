import 'package:flutter/material.dart';

import '../services/youtube_suggestion_service.dart';
import 'exercise_video_sheet.dart';

const _kGreen = Color(0xFF2E7D32);
const _kInk = Color(0xFF191C19);
const _kMuted = Color(0xFF747972);

/// Shows a suggested YouTube tutorial for an exercise.
///
/// Tapping the card opens the tutorial INSIDE the app
/// using ExerciseVideoSheet.
///
/// No url_launcher is required.
class VideoSuggestionCard extends StatelessWidget {
  final String exerciseName;
  final String category;
  final String levelLabel;
  final String? youtubeApiKey;

  const VideoSuggestionCard({
    super.key,
    required this.exerciseName,
    required this.category,
    required this.levelLabel,
    this.youtubeApiKey,
  });

  // ============================================================
  // OPEN VIDEO INSIDE APP
  // ============================================================

  Future<void> _openVideo(
    BuildContext context,
  ) async {
    try {
      await showExerciseVideoSheet(
        context: context,
        exerciseName: exerciseName,
        category: category,
        levelLabel: levelLabel,
        youtubeApiKey: youtubeApiKey,
      );
    } catch (e) {
      debugPrint(
        'Could not open exercise video: $e',
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the tutorial video.',
          ),
        ),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VideoSuggestion>(
      future: YoutubeSuggestionService().suggestVideo(
        exerciseName: exerciseName,
        category: category,
        levelLabel: levelLabel,
        apiKey: youtubeApiKey,
      ),

      builder: (context, snapshot) {
        // ========================================================
        // LOADING
        // ========================================================

        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return Container(
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4EF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFE8F5E9),
              ),
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _kGreen,
              ),
            ),
          );
        }

        // ========================================================
        // ERROR
        // ========================================================

        if (snapshot.hasError) {
          return _buildFallbackCard(context);
        }

        // ========================================================
        // NO DATA
        // ========================================================

        if (!snapshot.hasData) {
          return _buildFallbackCard(context);
        }

        final suggestion = snapshot.data!;

        // ========================================================
        // VIDEO SUGGESTION CARD
        // ========================================================

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openVideo(context),

            borderRadius: BorderRadius.circular(16),

            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4EF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFE8F5E9),
                ),
              ),

              padding: const EdgeInsets.all(12),

              child: Row(
                children: [
                  // ==============================================
                  // THUMBNAIL
                  // ==============================================

                  Container(
                    width: 64,
                    height: 64,

                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius:
                          BorderRadius.circular(12),

                      image:
                          suggestion.thumbnailUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(
                                    suggestion.thumbnailUrl!,
                                  ),
                                  fit: BoxFit.cover,
                                )
                              : null,
                    ),

                    child:
                        suggestion.thumbnailUrl == null
                            ? const Icon(
                                Icons
                                    .play_circle_fill_rounded,
                                color: Colors.white,
                                size: 34,
                              )
                            : null,
                  ),

                  const SizedBox(width: 14),

                  // ==============================================
                  // TEXT
                  // ==============================================

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [
                        const Text(
                          'VIDEO TUTORIAL',
                          style: TextStyle(
                            color: _kGreen,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          suggestion.isDirectMatch
                              ? suggestion.title
                              : 'Watch "$exerciseName" tutorial',

                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,

                          style: const TextStyle(
                            color: _kInk,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          suggestion.isDirectMatch
                              ? 'Matched for your $levelLabel level'
                              : 'Tap to find a tutorial',

                          style: const TextStyle(
                            color: _kMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 5),

                        const Row(
                          children: [
                            Icon(
                              Icons.phone_android_rounded,
                              size: 13,
                              color: _kGreen,
                            ),

                            SizedBox(width: 4),

                            Text(
                              'Watch inside app',
                              style: TextStyle(
                                color: _kGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // ==============================================
                  // OPEN BUTTON
                  // ==============================================

                  Container(
                    width: 40,
                    height: 40,

                    decoration: const BoxDecoration(
                      color: _kGreen,
                      shape: BoxShape.circle,
                    ),

                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 25,
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

  // ============================================================
  // FALLBACK
  // ============================================================

  Widget _buildFallbackCard(
    BuildContext context,
  ) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: () => _openVideo(context),

        borderRadius: BorderRadius.circular(16),

        child: Container(
          width: double.infinity,

          padding: const EdgeInsets.all(14),

          decoration: BoxDecoration(
            color: const Color(0xFFF0F4EF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE8F5E9),
            ),
          ),

          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,

                decoration: const BoxDecoration(
                  color: _kGreen,
                  shape: BoxShape.circle,
                ),

                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [
                    Text(
                      '$exerciseName Tutorial',

                      style: const TextStyle(
                        color: _kInk,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 4),

                    const Text(
                      'Tap to search and watch inside the app',

                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.chevron_right_rounded,
                color: _kGreen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}