import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/youtube_suggestion_service.dart';

const _kGreen = Color(0xFF2E7D32);
const _kMuted = Color(0xFF747972);
const _kInk = Color(0xFF191C19);

class YoutubeWebViewPlayer extends StatefulWidget {
  final String exerciseName;
  final String category;
  final String levelLabel;
  final String? youtubeApiKey;
  final bool rounded;

  final VoidCallback? onCompleted;
  final void Function(Duration duration)? onDurationReady;
  final void Function(Duration position, Duration duration)?
      onProgressChanged;
  final void Function(bool playing)? onPlayingChanged;

  const YoutubeWebViewPlayer({
    super.key,
    required this.exerciseName,
    required this.category,
    required this.levelLabel,
    this.youtubeApiKey,
    this.rounded = true,
    this.onCompleted,
    this.onDurationReady,
    this.onProgressChanged,
    this.onPlayingChanged,
  });

  @override
  State<YoutubeWebViewPlayer> createState() =>
      _YoutubeWebViewPlayerState();
}

class _YoutubeWebViewPlayerState extends State<YoutubeWebViewPlayer> {
  // IMPORTANT:
  // YouTube requires Android WebView embeds to identify the embedding app
  // through the HTTP Referer. This must match your Android applicationId.
  //
  // From your current app logs, the installed package is:
  // com.example.fitness_plan
  static const String _androidAppId = 'com.example.fitness_plan';
  static const String _appOrigin = 'https://com.example.fitness_plan';

  final List<String> _candidateIds = [];

  WebViewController? _controller;
  Timer? _loadTimeout;

  int _candidateIndex = 0;
  int _generation = 0;

  bool _searching = true;
  bool _loading = false;
  bool _ready = false;
  bool _failed = false;
  bool _playing = false;
  bool _completed = false;

  double _progress = 0;
  Duration _videoDuration = Duration.zero;
  Duration _videoPosition = Duration.zero;

  String? _errorMessage;

  // If a candidate cannot initialize, move to the next one.
  static const Duration _candidateTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _searchVideos();
  }

  Future<void> _searchVideos() async {
    _loadTimeout?.cancel();

    // Incrementing this invalidates callbacks from an older WebView.
    final generation = ++_generation;

    if (mounted) {
      setState(() {
        _candidateIds.clear();
        _candidateIndex = 0;

        _searching = true;
        _loading = false;
        _ready = false;
        _failed = false;
        _playing = false;
        _completed = false;

        _progress = 0;
        _videoDuration = Duration.zero;
        _videoPosition = Duration.zero;

        _controller = null;
        _errorMessage = null;
      });
    }

    try {
      final ids = await YoutubeSuggestionService().fetchCandidateVideoIds(
        exerciseName: widget.exerciseName,
        category: widget.category,
        levelLabel: widget.levelLabel,
        apiKey: widget.youtubeApiKey,

        // Ask for many candidates because YouTube may still reject some
        // videos at actual iframe playback time.
        maxResults: 25,
      );

      if (!mounted || generation != _generation) return;

      if (ids.isEmpty) {
        setState(() {
          _searching = false;
          _failed = true;
          _errorMessage =
              'No public 10–15 minute YouTube workout video was found.';
        });
        return;
      }

      _candidateIds.addAll(ids);

      setState(() {
        _searching = false;
      });

      await _loadCandidate(0, generation);
    } catch (e) {
      debugPrint('YouTube search failed: $e');

      if (!mounted || generation != _generation) return;

      setState(() {
        _searching = false;
        _failed = true;
        _errorMessage =
            'Unable to search for a workout video. Please try again.';
      });
    }
  }

  Future<void> _loadCandidate(
    int index,
    int generation,
  ) async {
    if (!mounted || generation != _generation) return;

    _loadTimeout?.cancel();

    if (index >= _candidateIds.length) {
      _showNoPlayableVideo();
      return;
    }

    final videoId = _candidateIds[index];

    setState(() {
      _candidateIndex = index;
      _loading = true;
      _ready = false;
      _failed = false;
      _playing = false;
      _completed = false;

      _progress = 0;
      _videoDuration = Duration.zero;
      _videoPosition = Duration.zero;
      _errorMessage = null;
    });

    final controller = WebViewController();

    await controller.setJavaScriptMode(
      JavaScriptMode.unrestricted,
    );

    await controller.setBackgroundColor(
      Colors.black,
    );

    await controller.addJavaScriptChannel(
      'FlutterPlayer',
      onMessageReceived: (message) {
        _handlePlayerMessage(
          controller: controller,
          candidateIndex: index,
          generation: generation,
          message: message.message,
        );
      },
    );

    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) {
          debugPrint(
            'YouTube iframe candidate ${index + 1}/'
            '${_candidateIds.length} started: $url',
          );
        },
        onPageFinished: (url) {
          debugPrint(
            'YouTube iframe candidate ${index + 1}/'
            '${_candidateIds.length} page loaded: $url',
          );
        },
        onWebResourceError: (error) {
          debugPrint(
            'YouTube WebView resource error '
            '${error.errorCode}: ${error.description}',
          );
        },
      ),
    );

    if (!mounted || generation != _generation) return;

    _controller = controller;
    setState(() {});

    debugPrint(
      'YouTube WebView app identity: $_androidAppId '
      '(Referer/baseUrl: $_appOrigin/)',
    );

    await controller.loadHtmlString(
      _buildIframeHtml(videoId),
      // YouTube requires the WebView page to identify the Android app.
      // Using the app ID as the base URL causes WebView to send a valid
      // Referer such as: https://com.example.fitness_plan/
      baseUrl: '$_appOrigin/',
    );

    if (!mounted || generation != _generation) return;

    _loadTimeout = Timer(
      _candidateTimeout,
      () {
        if (!mounted ||
            generation != _generation ||
            index != _candidateIndex ||
            _ready) {
          return;
        }

        debugPrint(
          'YouTube candidate ${index + 1} timed out. '
          'Trying next candidate.',
        );

        _tryNextCandidate(
          failedIndex: index,
          generation: generation,
        );
      },
    );
  }

  void _handlePlayerMessage({
    required WebViewController controller,
    required int candidateIndex,
    required int generation,
    required String message,
  }) {
    if (!mounted ||
        generation != _generation ||
        controller != _controller ||
        candidateIndex != _candidateIndex) {
      return;
    }

    debugPrint('YouTube iframe -> Flutter: $message');

    if (message == 'READY') {
      _loadTimeout?.cancel();

      setState(() {
        _ready = true;
        _loading = false;
      });

      return;
    }

    if (message.startsWith('DURATION:')) {
      final seconds = double.tryParse(
        message.substring('DURATION:'.length),
      );

      if (seconds != null && seconds > 0) {
        _setDuration(
          Duration(
            milliseconds: (seconds * 1000).round(),
          ),
        );
      }

      return;
    }

    if (message == 'PLAYING') {
      _setPlaying(true);
      return;
    }

    if (message == 'PAUSED') {
      _setPlaying(false);
      return;
    }

    // Buffering is not the same as pause. We keep the current UI state
    // until YouTube reports PLAYING or PAUSED.
    if (message == 'BUFFERING') {
      return;
    }

    if (message.startsWith('PROGRESS:')) {
      final payload = message.substring(
        'PROGRESS:'.length,
      );

      final separator = payload.indexOf('|');
      if (separator == -1) return;

      final current = double.tryParse(
        payload.substring(0, separator),
      );

      final total = double.tryParse(
        payload.substring(separator + 1),
      );

      if (current == null ||
          total == null ||
          total <= 0) {
        return;
      }

      _updateProgress(
        currentSeconds: current,
        totalSeconds: total,
      );

      return;
    }

    if (message.startsWith('ERROR:')) {
      final code = int.tryParse(
        message.substring('ERROR:'.length),
      );

      debugPrint(
        'YouTube iframe rejected candidate '
        '${candidateIndex + 1} with error $code.',
      );

      // Common YouTube iframe errors:
      // 2   = invalid parameter / video id
      // 5   = HTML5 player error
      // 100 = video unavailable/private/deleted
      // 101 = owner does not allow embedding
      // 150 = same as 101
      // 152 = treated by some wrappers as another not-embeddable case
      // 153 = missing/invalid client identification in some environments
      //
      // Do not open youtube.com/watch as a fallback. Just try another
      // candidate, preventing the black WebView problem.
      _tryNextCandidate(
        failedIndex: candidateIndex,
        generation: generation,
      );

      return;
    }

    if (message == 'ENDED') {
      if (_videoDuration > Duration.zero) {
        _updateProgress(
          currentSeconds:
              _videoDuration.inMilliseconds / 1000.0,
          totalSeconds:
              _videoDuration.inMilliseconds / 1000.0,
        );
      }

      _markCompleted();
    }
  }

  void _tryNextCandidate({
    required int failedIndex,
    required int generation,
  }) {
    _loadTimeout?.cancel();

    if (!mounted ||
        generation != _generation ||
        failedIndex != _candidateIndex) {
      return;
    }

    final nextIndex = failedIndex + 1;

    if (nextIndex < _candidateIds.length) {
      _loadCandidate(
        nextIndex,
        generation,
      );
      return;
    }

    _showNoPlayableVideo();
  }

  void _showNoPlayableVideo() {
    _loadTimeout?.cancel();

    if (!mounted) return;

    setState(() {
      _loading = false;
      _ready = false;
      _failed = true;
      _playing = false;
      _controller = null;

      _errorMessage =
          'YouTube blocked every matching video from playing '
          'inside the app. Tap TRY AGAIN to search for a new set.';
    });
  }

  void _setDuration(Duration duration) {
    if (!mounted || duration <= Duration.zero) return;

    if (_videoDuration != duration) {
      setState(() {
        _videoDuration = duration;
      });
    }

    widget.onDurationReady?.call(duration);
  }

  void _setPlaying(bool playing) {
    if (!mounted) return;

    if (_playing != playing) {
      setState(() {
        _playing = playing;
      });
    }

    widget.onPlayingChanged?.call(playing);
  }

  void _updateProgress({
    required double currentSeconds,
    required double totalSeconds,
  }) {
    if (!mounted || totalSeconds <= 0) return;

    final clampedCurrent = currentSeconds.clamp(
      0.0,
      totalSeconds,
    );

    final position = Duration(
      milliseconds: (clampedCurrent * 1000).round(),
    );

    final duration = Duration(
      milliseconds: (totalSeconds * 1000).round(),
    );

    final fraction = (
      clampedCurrent / totalSeconds
    ).clamp(0.0, 1.0);

    setState(() {
      _videoPosition = position;
      _videoDuration = duration;
      _progress = fraction;
    });

    widget.onDurationReady?.call(duration);

    widget.onProgressChanged?.call(
      position,
      duration,
    );
  }

  void _markCompleted() {
    if (!mounted || _completed) return;

    setState(() {
      _completed = true;
      _playing = false;
      _progress = 1.0;

      if (_videoDuration > Duration.zero) {
        _videoPosition = _videoDuration;
      }
    });

    widget.onPlayingChanged?.call(false);

    if (_videoDuration > Duration.zero) {
      widget.onProgressChanged?.call(
        _videoDuration,
        _videoDuration,
      );
    }

    widget.onCompleted?.call();
  }

  String _buildIframeHtml(String videoId) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta
    name="viewport"
    content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"
  />

  <style>
    html,
    body,
    #player {
      width: 100%;
      height: 100%;
      margin: 0;
      padding: 0;
      background: #000;
      overflow: hidden;
    }

    iframe {
      width: 100% !important;
      height: 100% !important;
      border: 0 !important;
    }
  </style>
</head>

<body>
  <div id="player"></div>

  <script>
    let player = null;
    let progressTimer = null;

    function send(message) {
      try {
        FlutterPlayer.postMessage(message);
      } catch (e) {
        console.log(e);
      }
    }

    function startProgressTimer() {
      if (progressTimer !== null) {
        clearInterval(progressTimer);
      }

      progressTimer = setInterval(function () {
        if (!player ||
            typeof player.getCurrentTime !== 'function' ||
            typeof player.getDuration !== 'function') {
          return;
        }

        try {
          const current = player.getCurrentTime() || 0;
          const duration = player.getDuration() || 0;

          if (duration > 0) {
            send('PROGRESS:' + current + '|' + duration);
          }
        } catch (e) {
          console.log(e);
        }
      }, 500);
    }

    const tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';

    tag.onerror = function () {
      send('ERROR:5');
    };

    const firstScript =
        document.getElementsByTagName('script')[0];

    firstScript.parentNode.insertBefore(
      tag,
      firstScript,
    );

    function onYouTubeIframeAPIReady() {
      try {
        player = new YT.Player('player', {
          host: 'https://www.youtube.com',
          width: '100%',
          height: '100%',
          videoId: '$videoId',

          playerVars: {
            autoplay: 0,
            controls: 1,
            enablejsapi: 1,
            playsinline: 1,
            fs: 1,
            rel: 0,
            modestbranding: 1,

            // These values identify the embedding Android app to YouTube.
            // They must match the baseUrl/Referer above.
            origin: '$_appOrigin',
            widget_referrer: '$_appOrigin'
          },

          events: {
            onReady: onPlayerReady,
            onStateChange: onPlayerStateChange,
            onError: onPlayerError
          }
        });
      } catch (e) {
        send('ERROR:5');
      }
    }

    function onPlayerReady(event) {
      send('READY');

      try {
        const duration = player.getDuration();

        if (duration > 0) {
          send('DURATION:' + duration);
        }
      } catch (e) {
        console.log(e);
      }

      startProgressTimer();
    }

    function onPlayerStateChange(event) {
      if (!window.YT ||
          !YT.PlayerState) {
        return;
      }

      if (event.data === YT.PlayerState.PLAYING) {
        send('PLAYING');
      }

      if (event.data === YT.PlayerState.PAUSED) {
        send('PAUSED');
      }

      if (event.data === YT.PlayerState.BUFFERING) {
        send('BUFFERING');
      }

      if (event.data === YT.PlayerState.ENDED) {
        send('ENDED');
      }
    }

    function onPlayerError(event) {
      send('ERROR:' + event.data);
    }
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    if (_searching) {
      return _loadingBox(
        'Finding a playable 10–15 minute workout...',
      );
    }

    if (_failed) {
      return _errorBox();
    }

    if (_controller == null) {
      return _loadingBox(
        'Preparing video...',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: widget.rounded
              ? BorderRadius.circular(16)
              : BorderRadius.zero,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(
                  color: Colors.black,
                ),

                WebViewWidget(
                  controller: _controller!,
                ),

                if (_loading)
                  Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: Colors.white,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Testing video '
                          '${_candidateIndex + 1}/'
                          '${_candidateIds.length}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        _buildProgressBox(),
      ],
    );
  }

  Widget _buildProgressBox() {
    final percent = (
      _progress * 100
    ).clamp(0, 100).toStringAsFixed(0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4EF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _completed
                    ? Icons.verified_rounded
                    : _playing
                        ? Icons.play_circle_rounded
                        : Icons.pause_circle_rounded,
                color: _completed
                    ? _kGreen
                    : _kMuted,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  _completed
                      ? 'Workout video completed'
                      : _playing
                          ? 'Workout video playing'
                          : _ready
                              ? 'Video ready'
                              : 'Preparing video',
                  style: const TextStyle(
                    color: _kInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          LinearProgressIndicator(
            value: _progress,
            minHeight: 8,
            backgroundColor:
                const Color(0xFFDDE5DD),
            color: _completed
                ? _kGreen
                : Colors.orange,
          ),

          const SizedBox(height: 8),

          Text(
            '$percent% watched • '
            '${_formatDuration(_videoPosition)} / '
            '${_formatDuration(_videoDuration)}',
            style: const TextStyle(
              color: _kMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingBox(String text) {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: Colors.white,
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4EF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE8F5E9),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.video_library_outlined,
            color: Colors.orange,
            size: 30,
          ),

          const SizedBox(height: 10),

          Text(
            _errorMessage ??
                'Unable to load a playable workout video.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _kInk,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 14),

          ElevatedButton.icon(
            onPressed: _searchVideos,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text(
              'TRY AGAIN',
              style: TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(
    Duration duration,
  ) {
    if (duration <= Duration.zero) {
      return '--:--';
    }

    final minutes = duration.inMinutes;
    final seconds =
        duration.inSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _generation++;
    _loadTimeout?.cancel();
    super.dispose();
  }
}
