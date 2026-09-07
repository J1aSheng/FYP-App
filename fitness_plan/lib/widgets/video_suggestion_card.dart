import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/youtube_suggestion_service.dart';

const _kGreen = Color(0xFF2E7D32);
const _kInk = Color(0xFF191C19);
const _kMuted = Color(0xFF747972);

/// A tappable card suggesting a YouTube video for an exercise, personalized
/// by the workout's category and the user's level. Shows a real video
/// (thumbnail + title) when a match is resolved, or a clearly-labeled
/// search link as a fallback.
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

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        _showFailure(context);
      }
    } catch (e) {
      debugPrint("Could not open video link: $e");
      if (context.mounted) _showFailure(context);
    }
  }

  void _showFailure(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't open YouTube — check that a browser/YouTube app is installed.")),
    );
  }

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
        if (!snapshot.hasData) {
          return Container(
            height: 72,
            decoration: BoxDecoration(color: const Color(0xFFF0F4EF), borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen),
            ),
          );
        }

        final suggestion = snapshot.data!;
        return GestureDetector(
          onTap: () => _openLink(context, suggestion.url),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4EF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8F5E9)),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    image: suggestion.thumbnailUrl != null
                        ? DecorationImage(image: NetworkImage(suggestion.thumbnailUrl!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: suggestion.thumbnailUrl == null
                      ? const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 30)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.isDirectMatch ? suggestion.title : "Watch \"$exerciseName\" on YouTube",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        suggestion.isDirectMatch
                            ? "Matched for your $levelLabel level"
                            : "Tap for personalized search results",
                        style: const TextStyle(color: _kMuted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new_rounded, color: _kGreen, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}