import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// A suggested video for a given exercise. [isDirectMatch] is true when a
/// real video was resolved via the YouTube Data API; false when we fell
/// back to a plain search-results link (no API key configured, or the
/// lookup failed/timed out).
class VideoSuggestion {
  final String title;
  final String url;
  final String? thumbnailUrl;
  final bool isDirectMatch;

  const VideoSuggestion({
    required this.title,
    required this.url,
    required this.isDirectMatch,
    this.thumbnailUrl,
  });
}

/// Builds personalized YouTube suggestions for a workout exercise.
/// Personalization comes from folding the workout's category and the
/// user's level (beginner/intermediate/advanced) into the search query, so
/// results skew toward form videos that match ability — not just the bare
/// exercise name.
class YoutubeSuggestionService {
  /// Set this (e.g. from an env var or remote config) to enable real video
  /// lookups via the YouTube Data API v3. Left null, every suggestion falls
  /// back to a search-results link — still tappable, still personalized,
  /// just not resolved to a single video.
  static String? defaultApiKey;

  String buildSearchQuery({
    required String exerciseName,
    required String category,
    required String levelLabel,
  }) {
    final level = levelLabel.toLowerCase();
    final levelHint = level == 'beginner'
        ? 'for beginners'
        : level == 'advanced'
            ? 'advanced technique'
            : '';
    return [exerciseName, category, levelHint, 'proper form tutorial']
        .where((s) => s.trim().isNotEmpty)
        .join(' ');
  }

  String buildSearchUrl({
    required String exerciseName,
    required String category,
    required String levelLabel,
  }) {
    final query = buildSearchQuery(
      exerciseName: exerciseName,
      category: category,
      levelLabel: levelLabel,
    );
    return 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}';
  }

  /// Resolves the best video suggestion for an exercise. Tries a real
  /// YouTube Data API search first (if [apiKey] or [defaultApiKey] is set),
  /// and falls back to a search link on any error, timeout, or missing key.
  Future<VideoSuggestion> suggestVideo({
    required String exerciseName,
    required String category,
    required String levelLabel,
    String? apiKey,
  }) async {
    final key = apiKey ?? defaultApiKey;
    final query = buildSearchQuery(
      exerciseName: exerciseName,
      category: category,
      levelLabel: levelLabel,
    );

    if (key != null && key.isNotEmpty) {
      try {
        final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
          'part': 'snippet',
          'q': query,
          'type': 'video',
          'maxResults': '1',
          'videoEmbeddable': 'true',
          'safeSearch': 'strict',
          'key': key,
        });
        final res = await http.get(uri).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final items = data['items'] as List?;
          if (items != null && items.isNotEmpty) {
            final item = items.first as Map<String, dynamic>;
            final videoId = item['id']?['videoId'] as String?;
            final snippet = item['snippet'] as Map<String, dynamic>?;
            if (videoId != null) {
              return VideoSuggestion(
                title: (snippet?['title'] as String?) ?? exerciseName,
                url: 'https://www.youtube.com/watch?v=$videoId',
                thumbnailUrl: snippet?['thumbnails']?['medium']?['url'] as String?,
                isDirectMatch: true,
              );
            }
          }
        }
      } catch (_) {
        // Falls through to the search-link fallback below.
      }
    }

    return VideoSuggestion(
      title: exerciseName,
      url: buildSearchUrl(exerciseName: exerciseName, category: category, levelLabel: levelLabel),
      isDirectMatch: false,
    );
  }
}