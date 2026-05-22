import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoProgress {
  final String videoUrl;
  final String username;
  final int position;
  final int duration;
  final DateTime lastUpdated;

  VideoProgress({
    required this.videoUrl,
    required this.username,
    required this.position,
    required this.duration,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() {
    return {
      'videoUrl': videoUrl,
      'username': username,
      'position': position,
      'duration': duration,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory VideoProgress.fromJson(Map<String, dynamic> json) {
    return VideoProgress(
      videoUrl: json['videoUrl'],
      username: json['username'],
      position: json['position'],
      duration: json['duration'],
      lastUpdated: DateTime.parse(json['lastUpdated']),
    );
  }

  double get percentageWatched {
    if (duration <= 0) return 0;
    return (position / duration).clamp(0.0, 1.0);
  }
}

class VideoProgressManager {
  static const String _prefsKey = 'video_progress';
  
  static Future<void> saveProgress(
    String videoUrl, 
    String username, 
    int position, 
    int duration,
  ) async {
    try {
      if (position < 5000 || (duration - position < 10000)) {
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final progress = VideoProgress(
        videoUrl: videoUrl,
        username: username,
        position: position,
        duration: duration,
        lastUpdated: DateTime.now(),
      );
      
      final Map<String, dynamic> allProgress = await _getAllProgress();
      final String key = '$username:$videoUrl';
      allProgress[key] = progress.toJson();
      await prefs.setString(_prefsKey, jsonEncode(allProgress));
    } catch (e) {}
  }
  
  static Future<VideoProgress?> getProgress(String videoUrl, String username) async {
    try {
      final Map<String, dynamic> allProgress = await _getAllProgress();
      final String key = '$username:$videoUrl';
      if (allProgress.containsKey(key)) {
        return VideoProgress.fromJson(allProgress[key]);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  
  static Future<Map<String, dynamic>> _getAllProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final String? progressJson = prefs.getString(_prefsKey);
    if (progressJson == null || progressJson.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(progressJson));
    } catch (e) {
      return {};
    }
  }

  static Future<List<VideoProgress>> getUserProgress(String username) async {
    try {
      final Map<String, dynamic> allProgress = await _getAllProgress();
      final List<VideoProgress> userProgress = [];
      for (final entry in allProgress.entries) {
        if (entry.key.startsWith('$username:')) {
          userProgress.add(VideoProgress.fromJson(entry.value));
        }
      }
      userProgress.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      return userProgress;
    } catch (e) {
      return [];
    }
  }
}

class SubtitleEntry {
  final Duration start;
  final Duration end;
  final String text;
  
  SubtitleEntry({
    required this.start,
    required this.end,
    required this.text,
  });
}

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final List<String> subtitleUrls;
  final String title;
  final String serverIp;
  final String serverPort;
  final String username;
  final String password;
  final int fileSize;
  final Map<String, dynamic>? nextEpisode;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.subtitleUrls,
    required this.title,
    required this.serverIp,
    required this.serverPort,
    required this.username,
    required this.password,
    required this.fileSize,
    this.nextEpisode,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String _error = '';
  bool _showControls = true;
  Timer? _hideTimer;
  List<SubtitleEntry> _subtitles = [];
  String _currentSubtitleText = '';
  double _subDelay = 0.0;
  double _subSize = 24.0;
  double _volumeBoost = 1.0;
  Color _subTextColor = Colors.white;
  Color _subBgColor = Colors.black.withOpacity(0.75);
  bool _hasError = false;
  String _errorMessage = '';
  bool _showRewindIndicator = false;
  bool _showForwardIndicator = false;
  Timer? _indicatorTimer;
  Timer? _subtitleTimer;
  Timer? _progressSaveTimer;
  double _scale = 1.0;

  late AnimationController _controlsAnimationController;
  late Animation<double> _controlsOpacity;
  late AnimationController _capsuleSlideController;
  late Animation<Offset> _capsuleSlideAnimation;
  late AnimationController _progressController;

  bool _showNextEpisodeOverlay = false;
  Timer? _nextEpisodeTimer;
  bool _nextEpisodeCancelled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _controlsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _controlsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controlsAnimationController);

    _capsuleSlideController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _capsuleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -2.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _capsuleSlideController,
      curve: Curves.easeOutCubic,
    ));

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _initializePlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _videoPlayerController?.play();
    }
  }

  Future<void> _initializePlayer() async {
    try {
      final bool isLocal = !widget.videoUrl.startsWith('http');

      if (isLocal) {
        String rawPath = widget.videoUrl;
        if (rawPath.startsWith('file://')) {
          rawPath = rawPath.replaceFirst('file://', '');
        }
        if (rawPath.contains('?')) {
          rawPath = rawPath.split('?')[0];
        }
        rawPath = Uri.decodeFull(rawPath);
        final cleanPath = p.normalize(rawPath);
        final file = File(cleanPath);
        
        if (!file.existsSync()) {
          throw Exception("File not found: $cleanPath");
        }

        _videoPlayerController = VideoPlayerController.file(
          file,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } else {
        final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
        final base64Token = auth.split(' ')[1];
        final separator = widget.videoUrl.contains('?') ? '&' : '?';
        final finalUrl = '${widget.videoUrl}${separator}auth=$base64Token';
        
        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(finalUrl),
          httpHeaders: {
            'Authorization': auth,
            'ngrok-skip-browser-warning': 'true',
          },
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      }

      await _videoPlayerController!.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        showControls: false,
        allowFullScreen: true,
      );

      _videoPlayerController!.addListener(_videoListener);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _videoPlayerController!.play();
        _videoPlayerController!.setVolume(_volumeBoost > 1.0 ? 1.0 : _volumeBoost);
        _startHideTimer();
        _startProgressSaveTimer();
        
        final progress = await VideoProgressManager.getProgress(widget.videoUrl, widget.username);
        if (progress != null && progress.position > 5000) {
          _showResumeDialog(progress);
        }
      }

      if (widget.subtitleUrls.isNotEmpty) {
        _loadSubtitles(widget.subtitleUrls.first);
      }

      _subtitleTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (mounted && _videoPlayerController != null && _videoPlayerController!.value.isPlaying) {
          _updateSubtitles();
        }
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _videoListener() {
    if (_videoPlayerController == null) return;
    
    if (_videoPlayerController!.value.hasError) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = _videoPlayerController!.value.errorDescription ?? 'Playback Error';
        });
      }
      return;
    }

    _checkForVideoCompletion();
    if (mounted) setState(() {});
  }

  void _checkForVideoCompletion() {
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized || _nextEpisodeCancelled) return;
    
    final duration = _videoPlayerController!.value.duration;
    final position = _videoPlayerController!.value.position;
    final remainingTime = duration - position;
    
    if (remainingTime.inSeconds <= 20 && widget.nextEpisode != null && !_showNextEpisodeOverlay) {
      setState(() {
        _showNextEpisodeOverlay = true;
      });
      
      _capsuleSlideController.forward().then((_) {
        _progressController.forward();
        _nextEpisodeTimer?.cancel();
        _nextEpisodeTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && _showNextEpisodeOverlay) {
            _playNextEpisode();
          }
        });
      });
    }
  }

  void _playNextEpisode() {
    if (widget.nextEpisode != null) {
      _nextEpisodeTimer?.cancel();
      _saveCurrentPosition();
      Navigator.of(context).pop({'action': 'playNext', 'episode': widget.nextEpisode});
    }
  }

  void _cancelNextEpisode() {
    _nextEpisodeTimer?.cancel();
    _capsuleSlideController.reverse();
    _progressController.stop();
    _progressController.reset();
    setState(() {
      _showNextEpisodeOverlay = false;
      _nextEpisodeCancelled = true;
    });
  }

  Future<void> _loadSubtitles(String url) async {
    try {
      final bool isLocal = !url.startsWith('http');
      String content = '';

      if (isLocal) {
        String rawPath = url;
        if (rawPath.startsWith('file://')) rawPath = rawPath.replaceFirst('file://', '');
        if (rawPath.contains('?')) rawPath = rawPath.split('?')[0];
        rawPath = Uri.decodeFull(rawPath);
        content = await File(p.normalize(rawPath)).readAsString();
      } else {
        final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
        final response = await http.get(Uri.parse(url), headers: {
          'Authorization': auth,
          'ngrok-skip-browser-warning': 'true',
        });
        if (response.statusCode == 200) {
          content = response.body;
        }
      }

      if (content.isNotEmpty) {
        _parseSRT(content);
      }
    } catch (e) {}
  }

  void _parseSRT(String content) {
    _subtitles.clear();
    final exp = RegExp(
      r'(\d+)\r?\n(\d{1,2}:\d{2}:\d{1,2},\d{2,3}) --> (\d{1,2}:\d{2}:\d{1,2},\d{2,3})\r?\n([\s\S]*?)(?=\r?\n\r?\n\d+\r?\n|$)',
      multiLine: true,
    );

    for (final match in exp.allMatches(content)) {
      _subtitles.add(SubtitleEntry(
        start: _parseT(match.group(2)!),
        end: _parseT(match.group(3)!),
        text: match.group(4)!.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      ));
    }
  }

  Duration _parseT(String t) {
    final parts = t.split(':');
    final secParts = parts[2].split(',');
    return Duration(
      hours: int.parse(parts[0]),
      minutes: int.parse(parts[1]),
      seconds: int.parse(secParts[0]),
      milliseconds: int.parse(secParts[1]),
    );
  }

  void _updateSubtitles() {
    if (_subtitles.isEmpty || _videoPlayerController == null) return;
    final now = _videoPlayerController!.value.position + Duration(milliseconds: (_subDelay * 1000).toInt());
    final entry = _subtitles.firstWhere(
      (e) => now >= e.start && now <= e.end,
      orElse: () => SubtitleEntry(start: Duration.zero, end: Duration.zero, text: ''),
    );

    if (_currentSubtitleText != entry.text) {
      if (mounted) {
        setState(() {
          _currentSubtitleText = entry.text;
        });
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _videoPlayerController != null && _videoPlayerController!.value.isPlaying) {
        setState(() {
          _showControls = false;
          _controlsAnimationController.reverse();
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _controlsAnimationController.forward();
        _startHideTimer();
      } else {
        _controlsAnimationController.reverse();
      }
    });
  }

  void _showSeekIndicator(bool isRewind) {
    _indicatorTimer?.cancel();
    setState(() {
      _showRewindIndicator = isRewind;
      _showForwardIndicator = !isRewind;
    });
    _indicatorTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _showRewindIndicator = false;
          _showForwardIndicator = false;
        });
      }
    });
  }

  void _saveCurrentPosition() {
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      VideoProgressManager.saveProgress(
        widget.videoUrl,
        widget.username,
        _videoPlayerController!.value.position.inMilliseconds,
        _videoPlayerController!.value.duration.inMilliseconds,
      );
    }
  }

  void _startProgressSaveTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _saveCurrentPosition();
    });
  }

  void _showResumeDialog(VideoProgress progress) {
    final minutes = (progress.position / 60000).floor();
    final seconds = ((progress.position % 60000) / 1000).floor();
    final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text('Resume Playback', style: TextStyle(color: Colors.white)),
        content: Text('Resume from $timeStr?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            child: const Text('Start Over', style: TextStyle(color: Colors.grey)),
            onPressed: () {
              Navigator.pop(context);
              _videoPlayerController?.seekTo(Duration.zero);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8A2BE2)),
            child: const Text('Resume'),
            onPressed: () {
              Navigator.pop(context);
              _videoPlayerController?.seekTo(Duration(milliseconds: progress.position));
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          if (_videoPlayerController == null) return;
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 2) {
            _videoPlayerController!.seekTo(_videoPlayerController!.value.position - const Duration(seconds: 10));
            _showSeekIndicator(true);
          } else {
            _videoPlayerController!.seekTo(_videoPlayerController!.value.position + const Duration(seconds: 10));
            _showSeekIndicator(false);
          }
        },
        child: Stack(
          children: [
            Center(
              child: _hasError
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 60),
                        const SizedBox(height: 20),
                        Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 20),
                        ElevatedButton(onPressed: _initializePlayer, child: const Text("Retry")),
                      ],
                    )
                  : (_videoPlayerController != null && _videoPlayerController!.value.isInitialized)
                      ? AspectRatio(
                          aspectRatio: _videoPlayerController!.value.aspectRatio,
                          child: VideoPlayer(_videoPlayerController!),
                        )
                      : const CircularProgressIndicator(color: Color(0xFF8A2BE2)),
            ),
            if (_showRewindIndicator) Center(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.replay_10, color: Colors.white, size: 50))),
            if (_showForwardIndicator) Center(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.forward_10, color: Colors.white, size: 50))),
            if (_currentSubtitleText.isNotEmpty && !_hasError)
              Positioned(
                bottom: _showControls ? 150 : 30,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(color: _subBgColor, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      _currentSubtitleText,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _subTextColor, fontSize: _subSize, fontWeight: FontWeight.w500, shadows: const [Shadow(blurRadius: 4, color: Colors.black, offset: Offset(2, 2))]),
                    ),
                  ),
                ),
              ),
            if (_showNextEpisodeOverlay && widget.nextEpisode != null)
              SlideTransition(
                position: _capsuleSlideAnimation,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                        child: Container(
                          width: 550,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: const Color(0xFFD866FF).withOpacity(0.6), width: 1.5),
                          ),
                          child: Stack(
                            children: [
                              AnimatedBuilder(
                                animation: _progressController,
                                builder: (context, child) => Container(width: 550 * _progressController.value, decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, const Color(0xFFD866FF).withOpacity(0.8)]))),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 35, right: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('UP NEXT', style: TextStyle(color: Color(0xFFD866FF), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                                          Text(widget.nextEpisode!['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD866FF), foregroundColor: Colors.white, shape: const StadiumBorder()),
                                      onPressed: _playNextEpisode,
                                      child: const Text('PLAY NOW', style: TextStyle(fontWeight: FontWeight.w800)),
                                    ),
                                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _cancelNextEpisode),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            FadeTransition(
              opacity: _controlsOpacity,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Stack(
                  children: [
                    Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent, Colors.transparent, Colors.black.withOpacity(0.8)], stops: const [0.0, 0.2, 0.8, 1.0]))),
                    Positioned(
                      top: 40,
                      left: 20,
                      right: 20,
                      child: Row(
                        children: [
                          IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                          IconButton(icon: const Icon(Icons.subtitles, color: Colors.white), onPressed: _showSubtitlePicker),
                          IconButton(icon: const Icon(Icons.accessibility, color: Colors.white), onPressed: _showAccessibilityDialog),
                        ],
                      ),
                    ),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(icon: const Icon(Icons.replay_10, color: Color(0xFF8A2BE2), size: 60), onPressed: () => _videoPlayerController?.seekTo(_videoPlayerController!.value.position - const Duration(seconds: 10))),
                          const SizedBox(width: 60),
                          IconButton(
                            icon: Icon(_videoPlayerController?.value.isPlaying == true ? Icons.pause_circle_filled : Icons.play_circle_filled, color: const Color(0xFF8A2BE2), size: 90),
                            onPressed: () {
                              setState(() {
                                if (_videoPlayerController!.value.isPlaying) {
                                  _videoPlayerController!.pause();
                                } else {
                                  _videoPlayerController!.play();
                                }
                              });
                              _startHideTimer();
                            },
                          ),
                          const SizedBox(width: 60),
                          IconButton(icon: const Icon(Icons.forward_10, color: Color(0xFF8A2BE2), size: 60), onPressed: () => _videoPlayerController?.seekTo(_videoPlayerController!.value.position + const Duration(seconds: 10))),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 40,
                      left: 20,
                      right: 20,
                      child: Column(
                        children: [
                          if (_videoPlayerController != null)
                            Slider(
                              value: _videoPlayerController!.value.position.inMilliseconds.toDouble().clamp(0, _videoPlayerController!.value.duration.inMilliseconds.toDouble()),
                              min: 0.0,
                              max: _videoPlayerController!.value.duration.inMilliseconds.toDouble(),
                              activeColor: const Color(0xFF8A2BE2),
                              onChanged: (v) {
                                _videoPlayerController!.seekTo(Duration(milliseconds: v.toInt()));
                                _startHideTimer();
                              },
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(_videoPlayerController?.value.position ?? Duration.zero), style: const TextStyle(color: Colors.white)),
                                Text(_formatDuration(_videoPlayerController?.value.duration ?? Duration.zero), style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSubtitlePicker() async {
    final bool isLocal = !widget.videoUrl.startsWith('http');
    if (isLocal) {
      String rawPath = widget.videoUrl;
      if (rawPath.startsWith('file://')) rawPath = rawPath.replaceFirst('file://', '');
      if (rawPath.contains('?')) rawPath = rawPath.split('?')[0];
      rawPath = Uri.decodeFull(rawPath);
      final dir = Directory(p.dirname(rawPath));
      if (!await dir.exists()) return;
      final files = dir.listSync().where((f) => f.path.endsWith('.srt')).toList();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: const Text('Subtitles', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) return ListTile(title: const Text('None', style: TextStyle(color: Colors.white)), onTap: () { setState(() => _subtitles.clear()); Navigator.pop(context); });
                final s = files[i - 1];
                return ListTile(title: Text(p.basename(s.path), style: const TextStyle(color: Colors.white)), onTap: () { _loadSubtitles(s.path); Navigator.pop(context); });
              },
            ),
          ),
        ),
      );
      return;
    }

    final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
    final videoPath = Uri.parse(widget.videoUrl).queryParameters['path'] ?? '';
    final response = await http.get(
      Uri.parse('http://${widget.serverIp}:${widget.serverPort}/api/find-subtitles?path=${Uri.encodeComponent(videoPath)}'),
      headers: {'Authorization': auth, 'ngrok-skip-browser-warning': 'true'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        final subs = List<Map<String, dynamic>>.from(data['subtitles']);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF111111),
            title: const Text('Subtitles', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: subs.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return ListTile(title: const Text('None', style: TextStyle(color: Colors.white)), onTap: () { setState(() => _subtitles.clear()); Navigator.pop(context); });
                  final s = subs[i - 1];
                  return ListTile(title: Text(s['name'], style: const TextStyle(color: Colors.white)), onTap: () { _loadSubtitles('http://${widget.serverIp}:${widget.serverPort}/api/subtitle?path=${Uri.encodeComponent(s['path'])}'); Navigator.pop(context); });
                },
              ),
            ),
          ),
        );
      }
    }
  }

  void _showAccessibilityDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: const Text('Accessibility', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAccRow('Volume Boost', '${_volumeBoost.toStringAsFixed(1)}x', () {
                setState(() { _volumeBoost = math.max(1.0, _volumeBoost - 1.0); _videoPlayerController?.setVolume(_volumeBoost > 1.0 ? 1.0 : _volumeBoost); });
                setDialogState(() {});
              }, () {
                setState(() { _volumeBoost = math.min(20.0, _volumeBoost + 1.0); _videoPlayerController?.setVolume(_volumeBoost > 1.0 ? 1.0 : _volumeBoost); });
                setDialogState(() {});
              }),
              _buildAccRow('Font Size', '${_subSize.toInt()}px', () { setState(() => _subSize -= 2); setDialogState(() {}); }, () { setState(() => _subSize += 2); setDialogState(() {}); }),
              _buildAccRow('Delay', '${_subDelay.toStringAsFixed(1)}s', () { setState(() => _subDelay -= 0.5); setDialogState(() {}); }, () { setState(() => _subDelay += 0.5); setDialogState(() {}); }),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Color(0xFF8A2BE2))))],
        ),
      ),
    );
  }

  Widget _buildAccRow(String label, String val, VoidCallback onDec, VoidCallback onInc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white)),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.remove, color: Colors.white), onPressed: onDec),
              Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: onInc),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveCurrentPosition();
    _hideTimer?.cancel();
    _subtitleTimer?.cancel();
    _progressSaveTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    _videoPlayerController?.removeListener(_videoListener);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _controlsAnimationController.dispose();
    _capsuleSlideController.dispose();
    _progressController.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    super.dispose();
  }
}
