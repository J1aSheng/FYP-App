import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class VideoSuggestion {
  final String title;
  final String url;
  final String? thumbnailUrl;
  final bool isDirectMatch;
  final String? videoId;
  final Duration? duration;

  const VideoSuggestion({
    required this.title,
    required this.url,
    required this.isDirectMatch,
    this.thumbnailUrl,
    this.videoId,
    this.duration,
  });
}

class YoutubeVideoCandidate {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final Duration duration;

  const YoutubeVideoCandidate({
    required this.id,
    required this.title,
    required this.duration,
    this.thumbnailUrl,
  });
}

class YoutubeSuggestionService {
  /// Keep using the API key setup that already works in your project.
  /// Example in main.dart:
  /// YoutubeSuggestionService.defaultApiKey = 'YOUR_KEY';
  static const String defaultApiKey ='AIzaSyA5PV9O8lDhnCwK0ntHGw6JtFK_OdX7JrM';
  

  static const Duration minVideoDuration = Duration(minutes: 10);
  static const Duration maxVideoDuration = Duration(minutes: 15);
  static const Duration preferredVideoDuration = Duration(minutes: 12, seconds: 30);

  String buildSearchQuery({
    required String exerciseName,
    required String category,
    required String levelLabel,
  }) {
    final level = levelLabel.toLowerCase();
    final levelHint = level == 'beginner'
        ? 'beginner'
        : level == 'advanced'
            ? 'advanced'
            : 'intermediate';

    return '$exerciseName $category $levelHint 10 minute follow along workout exercise';
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

    return Uri.https(
      'www.youtube.com',
      '/results',
      {'search_query': query},
    ).toString();
  }

  Future<List<String>> fetchCandidateVideoIds({
    required String exerciseName,
    required String category,
    required String levelLabel,
    String? apiKey,
    int maxResults = 5,
  }) async {
    final videos = await fetchCandidateVideos(
      exerciseName: exerciseName,
      category: category,
      levelLabel: levelLabel,
      apiKey: apiKey,
      maxResults: maxResults,
    );

    return videos.map((video) => video.id).toList();
  }

  Future<List<YoutubeVideoCandidate>> fetchCandidateVideos({
    required String exerciseName,
    required String category,
    required String levelLabel,
    String? apiKey,
    int maxResults = 5,
  }) async {
    final key = (apiKey ?? defaultApiKey)?.trim();

    if (key == null || key.isEmpty) {
      debugPrint('YouTube API key is missing.');
      return [];
    }

    final query = buildSearchQuery(
      exerciseName: exerciseName,
      category: category,
      levelLabel: levelLabel,
    );

    debugPrint('=====================================');
    debugPrint('YOUTUBE SEARCH');
    debugPrint('Exercise: $exerciseName');
    debugPrint('Query: $query');
    debugPrint('Required length: 10-15 minutes');
    debugPrint('=====================================');

    try {
      // Search more than 5 because duration filtering happens afterward.
      final searchUri = Uri.https(
        'www.googleapis.com',
        '/youtube/v3/search',
        {
          'part': 'snippet',
          'q': query,
          'type': 'video',
          'maxResults': '25',
          'videoEmbeddable': 'true',
          'videoSyndicated': 'true',
          'safeSearch': 'strict',
          'key': key,
        },
      );

      final searchResponse = await http
          .get(searchUri)
          .timeout(const Duration(seconds: 10));

      debugPrint('Search status: ${searchResponse.statusCode}');

      if (searchResponse.statusCode != 200) {
        debugPrint(searchResponse.body);
        return [];
      }

      final searchJson = jsonDecode(searchResponse.body) as Map<String, dynamic>;
      final searchItems = searchJson['items'] as List<dynamic>? ?? [];

      final ids = <String>[];
      for (final raw in searchItems) {
        final item = raw as Map<String, dynamic>;
        final id = (item['id'] as Map<String, dynamic>?)?['videoId']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }

      if (ids.isEmpty) return [];

      final videosUri = Uri.https(
        'www.googleapis.com',
        '/youtube/v3/videos',
        {
          'part': 'contentDetails,status,snippet',
          'id': ids.join(','),
          'key': key,
        },
      );

      final videosResponse = await http
          .get(videosUri)
          .timeout(const Duration(seconds: 10));

      debugPrint('Videos status: ${videosResponse.statusCode}');

      if (videosResponse.statusCode != 200) {
        debugPrint(videosResponse.body);
        return [];
      }

      final videosJson = jsonDecode(videosResponse.body) as Map<String, dynamic>;
      final videoItems = videosJson['items'] as List<dynamic>? ?? [];
      final valid = <YoutubeVideoCandidate>[];

      for (final raw in videoItems) {
        final item = raw as Map<String, dynamic>;
        final id = item['id']?.toString();
        if (id == null) continue;

        final status = item['status'] as Map<String, dynamic>? ?? {};
        if (status['embeddable'] != true || status['privacyStatus'] != 'public') {
          continue;
        }

        final details = item['contentDetails'] as Map<String, dynamic>? ?? {};
        final isoDuration = details['duration']?.toString();
        if (isoDuration == null) continue;

        final duration = _parseYoutubeDuration(isoDuration);
        if (duration < minVideoDuration || duration > maxVideoDuration) {
          debugPrint('$id rejected: ${_formatDuration(duration)}');
          continue;
        }

        final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
        final title = snippet['title']?.toString() ?? exerciseName;
        final thumbnails = snippet['thumbnails'] as Map<String, dynamic>?;
        final thumbnailUrl =
            (thumbnails?['high'] as Map<String, dynamic>?)?['url']?.toString() ??
            (thumbnails?['medium'] as Map<String, dynamic>?)?['url']?.toString() ??
            (thumbnails?['default'] as Map<String, dynamic>?)?['url']?.toString();

        valid.add(
          YoutubeVideoCandidate(
            id: id,
            title: title,
            thumbnailUrl: thumbnailUrl,
            duration: duration,
          ),
        );
      }

      // Prefer a video close to 12:30, while still accepting 10:00-15:00.
      valid.sort((a, b) {
        final aDiff = (a.duration.inSeconds - preferredVideoDuration.inSeconds).abs();
        final bDiff = (b.duration.inSeconds - preferredVideoDuration.inSeconds).abs();
        return aDiff.compareTo(bDiff);
      });

      final result = valid.take(maxResults).toList();
      for (final video in result) {
        debugPrint('Accepted ${video.id}: ${_formatDuration(video.duration)} ${video.title}');
      }
      return result;
    } catch (e) {
      debugPrint('YouTube API error: $e');
      return [];
    }
  }

  Future<VideoSuggestion> suggestVideo({
    required String exerciseName,
    required String category,
    required String levelLabel,
    String? apiKey,
  }) async {
    final videos = await fetchCandidateVideos(
      exerciseName: exerciseName,
      category: category,
      levelLabel: levelLabel,
      apiKey: apiKey,
      maxResults: 1,
    );

    if (videos.isNotEmpty) {
      final video = videos.first;
      return VideoSuggestion(
        title: video.title,
        url: 'https://www.youtube.com/watch?v=${video.id}',
        thumbnailUrl: video.thumbnailUrl,
        isDirectMatch: true,
        videoId: video.id,
        duration: video.duration,
      );
    }

    return VideoSuggestion(
      title: exerciseName,
      url: buildSearchUrl(
        exerciseName: exerciseName,
        category: category,
        levelLabel: levelLabel,
      ),
      isDirectMatch: false,
    );
  }

  Duration _parseYoutubeDuration(String value) {
    final match = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$').firstMatch(value);
    if (match == null) return Duration.zero;

    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;

    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
