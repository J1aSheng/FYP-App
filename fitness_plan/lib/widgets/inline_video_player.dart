import 'package:flutter/material.dart';

import 'youtube_webview_player.dart';

class InlineVideoPlayer extends StatelessWidget {
  final String exerciseName;
  final String category;
  final String levelLabel;
  final VoidCallback onVideoEnded;
  final String? youtubeApiKey;

  final void Function(Duration duration)? onDurationReady;
  final void Function(Duration position, Duration duration)? onProgressChanged;
  final void Function(bool playing)? onPlayingChanged;

  const InlineVideoPlayer({
    super.key,
    required this.exerciseName,
    required this.category,
    required this.levelLabel,
    required this.onVideoEnded,
    this.youtubeApiKey,
    this.onDurationReady,
    this.onProgressChanged,
    this.onPlayingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return YoutubeWebViewPlayer(
      exerciseName: exerciseName,
      category: category,
      levelLabel: levelLabel,
      youtubeApiKey: youtubeApiKey,
      rounded: true,
      onCompleted: onVideoEnded,
      onDurationReady: onDurationReady,
      onProgressChanged: onProgressChanged,
      onPlayingChanged: onPlayingChanged,
    );
  }
}
