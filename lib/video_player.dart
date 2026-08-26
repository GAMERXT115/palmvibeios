import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'video_progress_manager.dart';
import 'accessibility.dart';
import 'picture_in_picture.dart';

class SubtitleEntry {
  final int index;
  final Duration start;
  final Duration end;
  final String text;
  SubtitleEntry({required this.index, required this.start, required this.end, required this.text});
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
    Key? key,
    required this.videoUrl,
    required this.subtitleUrls,
    required this.title,
    required this.serverIp,
    required this.serverPort,
    required this.username,
    required this.password,
    this.fileSize = 0,
    this.nextEpisode,
  }) : super(key: key);

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> with TickerProviderStateMixin {
  final FocusNode _rootFocusNode = FocusNode();
  
  late AnimationController _controlsAnimationController;
  late Animation<double> _controlsOpacity;
  late AnimationController _capsuleSlideController;
  late Animation<Offset> _capsuleSlideAnimation;
  late AnimationController _progressController;
  late AnimationController _skipIntroProgressController;

  Map<String, dynamic>? _metadata;
  bool _showSkipIntro = false;
  bool _isAutoSkipping = false;
  Map<String, int>? _currentIntro;

  List<SubtitleEntry> _subtitles = [];
  String? _selectedSubtitle;
  double _subtitleFontSize = 20.0;
  double _subtitleDelaySeconds = 0.0;
  double _subtitleHeight = 60.0;
  bool _isGlassSubtitle = true;
  double _playbackSpeed = 1.0;
  Color _subtitleColor = Colors.white;
  bool _autoSkipIntro = false;

  double _audioBoostFactor = 1.0;
  bool _isIndicatorVisible = false;
  String _indicatorText = "";
  IconData _indicatorIcon = Icons.volume_up;

  bool _isLoading = true;
  bool _isBuffering = false;
  bool _controlsVisible = true;
  double _scale = 1.0;
  bool _showRewindIndicator = false;
  bool _showForwardIndicator = false;

  Timer? _hideControlsTimer;
  Timer? _progressSaveTimer;
  Timer? _indicatorTimer;
  Timer? _nextEpisodeTimer;
  Timer? _actionIndicatorTimer;
  Timer? _castHeartbeatTimer;
  Timer? _castStatusTimer;

  bool _showNextEpisodeOverlay = false;
  bool _nextEpisodeCancelled = false;
  final Color _purpleGlow = const Color(0xFFD866FF);

  bool _isDragging = false;
  double _dragValue = 0.0;
  double? _initialTimeBeforeDrag;
  bool _isHoveringX = false;
  bool _isCasting = false;

    @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    GlobalVideoManager().initPlayer(
      url: widget.videoUrl,
      title: widget.title,
      subs: widget.subtitleUrls,
      ip: widget.serverIp,
      port: widget.serverPort,
      user: widget.username,
      pass: widget.password,
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadSettings();
    _controlsAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _controlsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controlsAnimationController);
    _capsuleSlideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _capsuleSlideAnimation = Tween<Offset>(begin: const Offset(0, -2.0), end: Offset.zero).animate(CurvedAnimation(parent: _capsuleSlideController, curve: Curves.easeOutCubic));
    _progressController = AnimationController(vsync: this, duration: const Duration(seconds: 5));
    _skipIntroProgressController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _initializePlayer();
    _startCastHeartbeat();
  }


  void _startCastHeartbeat() {
    _castHeartbeatTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _sendHeartbeat();
    });
  }

  Future<void> _sendHeartbeat() async {
    final player = GlobalVideoManager().player;
    if (player == null || !player.state.playing || _isCasting) return;
    final String auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
    final int position = player.state.position.inSeconds;
    try {
      await http.post(
        Uri.parse("http://${widget.serverIp}:${widget.serverPort}/api/cast/heartbeat"),
        headers: {'Authorization': auth, 'Content-Type': 'application/json'},
        body: json.encode({'timestamp': position}),
      );
    } catch (e) {}
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isGlassSubtitle = prefs.getBool('isGlassSubtitle') ?? true;
      _subtitleFontSize = prefs.getDouble('subtitleFontSize') ?? 20.0;
      _subtitleHeight = prefs.getDouble('subtitleHeight') ?? 60.0;
      _subtitleColor = Color(prefs.getInt('subtitleColor') ?? Colors.white.value);
      _autoSkipIntro = prefs.getBool('autoSkipIntro') ?? false;
      _playbackSpeed = 1.0;
      _subtitleDelaySeconds = 0.0;
      _audioBoostFactor = 1.0;
      _scale = 1.0;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isGlassSubtitle', _isGlassSubtitle);
    await prefs.setDouble('subtitleFontSize', _subtitleFontSize);
    await prefs.setDouble('subtitleHeight', _subtitleHeight);
    await prefs.setInt('subtitleColor', _subtitleColor.value);
    await prefs.setBool('autoSkipIntro', _autoSkipIntro);
  }

  Future<void> _fetchMetadata() async {
    try {
      final String videoPath = _getRelativeVideoPath();
      if (videoPath.isEmpty) return;
      final url = "http://${widget.serverIp}:${widget.serverPort}/api/movie-assets?path=${Uri.encodeComponent(videoPath)}";
      final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
      final response = await http.get(Uri.parse(url), headers: {'Authorization': auth});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['metadata'] != null) {
          setState(() {
            _metadata = data['metadata'];
            _identifyIntro();
          });
        }
      }
    } catch (e) {}
  }

  void _identifyIntro() {
    if (_metadata == null || _metadata!['episodes'] == null) return;
    final List episodes = _metadata!['episodes'];
    final currentEp = episodes.firstWhere((ep) => ep['title'] == widget.title, orElse: () => null);
    if (currentEp != null && currentEp['intro'] != null) {
      setState(() {
        _currentIntro = {
          'start': currentEp['intro']['start'],
          'end': currentEp['intro']['end'],
        };
      });
    }
  }

  Future<void> _initializePlayer() async {
    final player = GlobalVideoManager().player;
    if (player == null) return;

    setState(() {
      _isLoading = true;
      _isBuffering = true;
    });

    try {
      final String rawAuth = base64Encode(utf8.encode('${widget.username}:${widget.password}'));
      final String authenticatedUrl = widget.videoUrl.contains('?') ? '${widget.videoUrl}&auth=$rawAuth' : '${widget.videoUrl}?auth=$rawAuth';

      _fetchMetadata();

      player.stream.buffering.listen((event) {
        if (mounted) setState(() => _isBuffering = event);
      });

      player.stream.position.listen((pos) {
        if (mounted) _videoListener(pos);
      });

      player.stream.playing.listen((playing) {
        if (playing && mounted) {
          _startHideTimer();
        }
      });

      player.stream.completed.listen((completed) {
        if (completed && widget.nextEpisode != null && mounted) {
          _playNextEpisode();
        }
      });

      if (player.state.playlist.medias.isNotEmpty) {
        setState(() {
          _isLoading = false;
          _isBuffering = false;
        });
      } else {
        await player.open(Media(authenticatedUrl, httpHeaders: {
          'Authorization': 'Basic $rawAuth',
          'User-Agent': 'Mozilla/5.0',
        }));
      }

      await player.setSubtitleTrack(SubtitleTrack.no());
      await player.setRate(_playbackSpeed);
      player.setVolume(_audioBoostFactor * 100.0);

      final progress = await VideoProgressManager.getProgress(
        videoPath: _getRelativeVideoPath(),
        title: widget.title,
        serverIp: widget.serverIp,
        serverPort: widget.serverPort,
        authHeader: 'Basic $rawAuth',
      );

      if (progress != null && progress.position > 5000 && mounted && !GlobalVideoManager().isReturningFromPiP) {
        _showResumeDialog(progress);
      }
      
      GlobalVideoManager().isReturningFromPiP = false;

      if (widget.subtitleUrls.isNotEmpty && mounted) _selectSubtitle(widget.subtitleUrls[0]);

      setState(() {
        _isLoading = false;
        _isBuffering = false;
      });

      _startHideTimer();
      _startProgressSaveTimer();
      player.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isBuffering = false;
        });
      }
    }
  }

  void _videoListener(Duration position) {
    if (!mounted) return;
    if (_currentIntro != null) {
      final int start = _currentIntro!['start']!;
      final int end = _currentIntro!['end']!;
      final int currentSec = position.inSeconds;
      if (end > start && currentSec >= start && currentSec <= end) {
        if (!_showSkipIntro && !_isAutoSkipping) {
          setState(() => _showSkipIntro = true);
          if (_autoSkipIntro) {
            _skipIntro();
          } else {
            _startIntroProgressAnimation(start, end, position);
          }
        }
      } else {
        if (_showSkipIntro) setState(() => _showSkipIntro = false);
        if (_isAutoSkipping && currentSec > end) setState(() => _isAutoSkipping = false);
      }
    }
    final player = GlobalVideoManager().player;
    final duration = player?.state.duration ?? Duration.zero;
    if (widget.nextEpisode != null && !_nextEpisodeCancelled && duration.inSeconds > 0 && (duration.inSeconds - position.inSeconds) <= 20 && !_showNextEpisodeOverlay) {
      _triggerNextEpisodeOverlay();
    }
  }

  void _startIntroProgressAnimation(int start, int end, Duration position) {
    final int totalMs = (end - start) * 1000;
    if (totalMs <= 0) return;
    final int elapsedMs = (position.inMilliseconds - (start * 1000)).clamp(0, totalMs);
    final int remainingMs = totalMs - elapsedMs;
    _skipIntroProgressController.value = elapsedMs / totalMs;
    _skipIntroProgressController.animateTo(1.0, duration: Duration(milliseconds: remainingMs), curve: Curves.linear);
  }

  Future<void> _skipIntro() async {
    final player = GlobalVideoManager().player;
    if (_currentIntro != null && !_isAutoSkipping && player != null) {
      setState(() {
        _isAutoSkipping = true;
        _showSkipIntro = false;
      });
      final targetSeconds = _currentIntro!['end']!;
      await player.seek(Duration(seconds: targetSeconds));
      _skipIntroProgressController.stop();
      _skipIntroProgressController.value = 0.0;
    }
  }

  void _togglePlay() {
    final player = GlobalVideoManager().player;
    if (player == null) return;
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
      _startHideTimer();
    }
    setState(() {});
    _showControls();
  }

  void _showActionIndicator(bool isRewind) {
    _actionIndicatorTimer?.cancel();
    setState(() { _showRewindIndicator = isRewind; _showForwardIndicator = !isRewind; });
    _actionIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() { _showRewindIndicator = false; _showForwardIndicator = false; });
    });
  }

  void _showResumeDialog(VideoProgress progress) {
    Future.delayed(Duration.zero, () {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text("Resume Playback?", style: TextStyle(color: Colors.white)),
          content: Text("Continue watching from ${_formatDuration(Duration(milliseconds: progress.position))}?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("START OVER")),
            ElevatedButton(
              onPressed: () { GlobalVideoManager().player?.seek(Duration(milliseconds: progress.position)); Navigator.pop(context); },
              child: const Text("RESUME"),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _seekToRelative(Duration relativeOffset) async {
    final player = GlobalVideoManager().player;
    if (player == null) return;
    final int currentMs = player.state.position.inMilliseconds;
    final int totalDurationMs = player.state.duration.inMilliseconds;
    final int clampedPosMs = (currentMs + relativeOffset.inMilliseconds).clamp(0, totalDurationMs);
    await player.seek(Duration(milliseconds: clampedPosMs));
    _saveProgress();
    _showControls();
  }

  void _saveProgress() {
    final player = GlobalVideoManager().player;
    if (player == null) return;
    final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
    VideoProgressManager.saveProgress(
      videoPath: _getRelativeVideoPath(),
      title: widget.title,
      serverIp: widget.serverIp,
      serverPort: widget.serverPort,
      authHeader: auth,
      position: player.state.position.inMilliseconds,
      duration: player.state.duration.inMilliseconds,
    );
  }

  Future<void> _selectSubtitle(String? subtitleUrl) async {
    if (subtitleUrl == null) {
      setState(() { _selectedSubtitle = null; _subtitles = []; });
      return;
    }
    try {
      final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
      final response = await http.get(Uri.parse(subtitleUrl), headers: {'Authorization': auth}).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        String decodedContent;
        try {
          decodedContent = utf8.decode(response.bodyBytes);
        } catch (e) {
          decodedContent = latin1.decode(response.bodyBytes);
        }
        final parsed = subtitleUrl.toLowerCase().endsWith('.vtt') 
            ? SubtitleHelper.parseVTT(decodedContent) 
            : SubtitleHelper.parseSRT(decodedContent);
        setState(() { _selectedSubtitle = subtitleUrl; _subtitles = parsed; });
      }
    } catch (e) {}
    _showControls();
  }

  void _showIndicatorUI() {
    _indicatorTimer?.cancel();
    setState(() => _isIndicatorVisible = true);
    _indicatorTimer = Timer(const Duration(seconds: 2), () { if (mounted) setState(() => _isIndicatorVisible = false); });
  }

  void _showControls() {
    if (_controlsVisible) return;
    _hideControlsTimer?.cancel();
    setState(() {
      _controlsVisible = true;
    });
    _controlsAnimationController.forward();
    _startHideTimer();
  }

  void _hideControls() {
    if (!_controlsVisible || _isDragging) return;
    setState(() {
      _controlsVisible = false;
    });
    _controlsAnimationController.reverse();
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      final player = GlobalVideoManager().player;
      if (mounted && player != null && player.state.playing && !_isDragging) {
        _hideControls();
      }
    });
  }

  void _startProgressSaveTimer() {
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (t) => _saveProgress());
  }

  void _triggerNextEpisodeOverlay() {
  if (_showNextEpisodeOverlay || _nextEpisodeCancelled) return;
  setState(() => _showNextEpisodeOverlay = true);
  _capsuleSlideController.forward();
  _progressController.reset();
  _progressController.forward();
  _nextEpisodeTimer?.cancel();
  _nextEpisodeTimer = Timer(const Duration(seconds: 5), () {
    if (mounted && _showNextEpisodeOverlay) {
      _playNextEpisode();
    }
  });
}

  void _playNextEpisode() {
    if (widget.nextEpisode != null) {
      _nextEpisodeTimer?.cancel();
      _saveProgress();
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

  Future<void> _showCastDialog() async {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text("Select TV Device", style: TextStyle(color: Colors.white)),
            content: FutureBuilder<List<String>>(
              future: _fetchDevices(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: Colors.purpleAccent)));
                }
                if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) {
                  return const Text("No active TV apps found.", style: TextStyle(color: Colors.white70));
                }
                return SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      final deviceName = snapshot.data![index];
                      return ListTile(
                        title: Text(deviceName, style: const TextStyle(color: Colors.white)),
                        onTap: () {
                          Navigator.pop(context);
                          _triggerCast(deviceName);
                        },
                      );
                    },
                  ),
                );
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
            ],
          );
        },
      ),
    );
  }

  Future<List<String>> _fetchDevices() async {
    final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
    try {
      final response = await http.get(
        Uri.parse("http://${widget.serverIp}:${widget.serverPort}/api/cast/devices"),
        headers: {'Authorization': auth, 'ngrok-skip-browser-warning': 'true'},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<String>.from(data['devices']);
        }
      }
    } catch (e) {}
    return [];
  }

  Future<void> _triggerCast(String targetDevice) async {
    final player = GlobalVideoManager().player;
    if (player == null) return;
    final String videoPath = _getRelativeVideoPath();
    final String auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
    final int timestamp = player.state.position.inSeconds;
    String? subPath;
    if (_selectedSubtitle != null) {
      try {
        subPath = Uri.decodeFull(Uri.parse(_selectedSubtitle!).queryParameters['path'] ?? "");
      } catch (e) {}
    }

    try {
      final response = await http.post(
        Uri.parse("http://${widget.serverIp}:${widget.serverPort}/api/cast/command"),
        headers: {'Authorization': auth, 'Content-Type': 'application/json'},
        body: json.encode({
          'action': 'START_CAST',
          'videoPath': videoPath,
          'timestamp': timestamp,
          'title': widget.title,
          'targetDevice': targetDevice,
          'subtitlePath': subPath ?? ""
        }),
      );
      final data = json.decode(response.body);
      if (data['success'] == true) {
        player.pause();
        setState(() => _isCasting = true);
        _hideControls();
        _startCastPolling();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cast failed"), backgroundColor: Colors.redAccent));
    }
  }

  void _startCastPolling() {
    _castStatusTimer?.cancel();
    _castStatusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
      try {
        final response = await http.get(
          Uri.parse("http://${widget.serverIp}:${widget.serverPort}/api/cast/status"),
          headers: {'Authorization': auth, 'ngrok-skip-browser-warning': 'true'},
        );
        final data = json.decode(response.body);
        if (data['success'] == true && data['timestamp'] != null) {
          final int remotePos = data['timestamp'];
          GlobalVideoManager().player?.seek(Duration(seconds: remotePos));
        }
      } catch (e) {}
    });
  }

  Future<void> _stopCast() async {
    final player = GlobalVideoManager().player;
    if (player == null) return;
    final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
    try {
      final statusRes = await http.get(
        Uri.parse("http://${widget.serverIp}:${widget.serverPort}/api/cast/status"),
        headers: {'Authorization': auth, 'ngrok-skip-browser-warning': 'true'},
      );
      final statusData = json.decode(statusRes.body);
      int returnTime = player.state.position.inSeconds;
      if (statusData['success'] == true && statusData['timestamp'] != null) {
        returnTime = statusData['timestamp'];
      }

      await http.post(
        Uri.parse("http://${widget.serverIp}:${widget.serverPort}/api/cast/command"),
        headers: {'Authorization': auth, 'Content-Type': 'application/json'},
        body: json.encode({'action': 'STOP_CAST'}),
      );

      _castStatusTimer?.cancel();
      setState(() => _isCasting = false);
      await player.seek(Duration(seconds: returnTime));
      player.play();
      _showControls();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to stop cast"), backgroundColor: Colors.redAccent));
    }
  }

  void _showAccessibilityDialog() {
    showDialog(
      context: context,
      builder: (context) => AccessibilityDialog(
        playbackSpeed: _playbackSpeed,
        isGlassSubtitle: _isGlassSubtitle,
        audioBoostFactor: _audioBoostFactor,
        subtitleFontSize: _subtitleFontSize,
        subtitleDelaySeconds: _subtitleDelaySeconds,
        subtitleHeight: _subtitleHeight,
        scale: _scale,
        subtitleColor: _subtitleColor,
        autoSkipIntro: _autoSkipIntro,
        onPlaybackSpeedChanged: (speed) { 
          setState(() { 
            _playbackSpeed = double.parse(speed.toStringAsFixed(1));
            GlobalVideoManager().player?.setRate(_playbackSpeed); 
          }); 
          _indicatorIcon = Icons.speed;
          _indicatorText = "${_playbackSpeed.toStringAsFixed(1)}x";
          _showIndicatorUI();
          _saveSettings(); 
        },
        onGlassSubtitleChanged: (val) { setState(() => _isGlassSubtitle = val); _saveSettings(); },
        onAudioBoostChanged: (boost) { 
          _audioBoostFactor = boost;
          GlobalVideoManager().player?.setVolume(_audioBoostFactor * 100.0);
          _indicatorIcon = Icons.bolt;
          _indicatorText = "${(_audioBoostFactor * 100).round()}%";
          _showIndicatorUI();
          _saveSettings();
        },
        onSubtitleFontSizeChanged: (size) { setState(() => _subtitleFontSize = size); _saveSettings(); },
        onSubtitleDelayChanged: (delay) { 
          setState(() => _subtitleDelaySeconds = double.parse(delay.toStringAsFixed(1))); 
          _indicatorIcon = Icons.subtitles;
          _indicatorText = "Delay: ${_subtitleDelaySeconds.toStringAsFixed(1)}s";
          _showIndicatorUI();
          _saveSettings(); 
        },
        onSubtitleHeightChanged: (h) { setState(() => _subtitleHeight = h); _saveSettings(); },
        onScaleChanged: (s) => setState(() => _scale = s),
        onSubtitleColorChanged: (color) { setState(() => _subtitleColor = color); _saveSettings(); },
        onAutoSkipIntroChanged: (val) { setState(() => _autoSkipIntro = val); _saveSettings(); },
        onSetIntroTiming: (type) async {
          final player = GlobalVideoManager().player;
          if (player == null) return;
          final String videoPath = _getRelativeVideoPath();
          final String auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
          final double currentTime = player.state.position.inSeconds.toDouble();
          try {
            await http.post(
              Uri.parse("http://${widget.serverIp}:${widget.serverPort}/api/save-episode-metadata"),
              headers: {'Authorization': auth, 'Content-Type': 'application/json'},
              body: json.encode({ 'videoPath': videoPath, 'videoTitle': widget.title, 'type': type, 'time': currentTime}),
            );
          } catch (e) {}
        },
        onReportIssue: () {},
      ),
    );
  }

  void _showSubtitleDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('SUBTITLES', style: TextStyle(color: Colors.purpleAccent, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 20),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          title: const Text('None', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          trailing: _selectedSubtitle == null ? const Icon(Icons.check_circle, color: Colors.purpleAccent) : null,
                          onTap: () { _selectSubtitle(null); Navigator.pop(context); },
                        ),
                        ...widget.subtitleUrls.map((url) {
                          String fileName = Uri.decodeFull(url).split('path=').last.split('/').last;
                          bool isSelected = _selectedSubtitle == url;
                          return ListTile(
                            title: Text(fileName, style: TextStyle(color: isSelected ? Colors.purpleAccent : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.purpleAccent) : null,
                            onTap: () { _selectSubtitle(url); Navigator.pop(context); },
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CLOSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = GlobalVideoManager().player;
    final controller = GlobalVideoManager().controller;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        GlobalVideoManager().showPiP(context);
        Navigator.of(context).pop();
      },
      child: KeyboardListener(
        focusNode: _rootFocusNode,
        autofocus: true,
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.space) _togglePlay();
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) _seekToRelative(const Duration(seconds: -10));
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) _seekToRelative(const Duration(seconds: 10));
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_controlsVisible) {
                _hideControls();
              } else {
                _showControls();
              }
            },
            onDoubleTapDown: (details) {
              final screenWidth = MediaQuery.of(context).size.width;
              if (details.globalPosition.dx < screenWidth / 2) {
                _seekToRelative(const Duration(seconds: -10));
                _showActionIndicator(true);
              } else {
                _seekToRelative(const Duration(seconds: 10));
                _showActionIndicator(false);
              }
            },
            child: Stack(
              children: [
                if (controller != null)
                  Center(
                    child: Transform.scale(
                      scale: _scale, 
                      child: Video(
                        controller: controller,
                        controls: NoVideoControls,
                      )
                    ),
                  ),
                if (_isCasting) _buildCastOverlay(),
                if (_showRewindIndicator || _showForwardIndicator)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(50)),
                      child: Icon(_showRewindIndicator ? Icons.replay_10 : Icons.forward_10, color: Colors.white, size: 60),
                    ),
                  ),
                if (player != null)
                  StreamBuilder<Duration>(
                    stream: player.stream.position,
                    builder: (context, snapshot) {
                      if (_subtitles.isEmpty || _isCasting) return const SizedBox.shrink();
                      final currentMs = player.state.position.inMilliseconds;
                      final delayMs = (_subtitleDelaySeconds * 1000).toInt();
                      final adjustedPos = Duration(milliseconds: currentMs - delayMs);
                      String text = '';
                      for (final entry in _subtitles) {
                        if (adjustedPos >= entry.start && adjustedPos <= entry.end) {
                          text = entry.text;
                          break;
                        }
                      }
                      if (text.isEmpty) return const SizedBox.shrink();
                      return Positioned(
                        bottom: _subtitleHeight, left: 20, right: 20,
                        child: IgnorePointer(
                          child: Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: _isGlassSubtitle ? 15 : 0, sigmaY: _isGlassSubtitle ? 15 : 0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _isGlassSubtitle ? _subtitleColor.withOpacity(0.15) : _subtitleColor.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    text, 
                                    style: TextStyle(color: Colors.white, fontSize: _subtitleFontSize, fontWeight: FontWeight.bold, height: 1.2), 
                                    textAlign: TextAlign.center
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                if (_showSkipIntro && !_isCasting) _buildSkipIntroButton(),
                if (_isIndicatorVisible)
                  Positioned(
                    top: 40, right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_indicatorIcon, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(_indicatorText, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ]),
                    ),
                  ),
                if (_showNextEpisodeOverlay && widget.nextEpisode != null && !_isCasting) _buildNextEpisodeCapsule(),
                if (_controlsVisible && !_isCasting) _buildMainControls(),
                if ((_isBuffering || _isLoading) && !_isCasting) const Center(child: CircularProgressIndicator(color: Colors.purpleAccent)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCastOverlay() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "Casted to TV",
            style: TextStyle(
              color: Colors.purpleAccent,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.purpleAccent, blurRadius: 20)],
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _stopCast,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
            child: const Text("Stop Casting", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildNextEpisodeCapsule() {
  return SlideTransition(
    position: _capsuleSlideAnimation,
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: 450,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: _purpleGlow.withOpacity(0.5), width: 1.5),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedBuilder(
                        animation: _progressController,
                        builder: (context, child) => FractionallySizedBox(
                          widthFactor: _progressController.value,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _purpleGlow.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'UP NEXT',
                                style: TextStyle(
                                  color: _purpleGlow,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                path.basenameWithoutExtension(widget.nextEpisode!['name']),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 15),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _purpleGlow,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          onPressed: _playNextEpisode,
                          child: const Text(
                            'PLAY NOW',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                          onPressed: _cancelNextEpisode,
                        ),
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
  );
}

  Widget _buildSkipIntroButton() {
    return Positioned(
      bottom: 100, right: 40,
      child: GestureDetector(
        onTap: _skipIntro,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.purple)),
          child: const Text("SKIP INTRO", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildMainControls() {
    final player = GlobalVideoManager().player;
    return FadeTransition(
      opacity: _controlsOpacity,
      child: Container(
        color: Colors.black45,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white), 
                    onPressed: () {
                      GlobalVideoManager().showPiP(context);
                      Navigator.pop(context);
                    }
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(path.basenameWithoutExtension(widget.title), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  IconButton(icon: const Icon(Icons.cast, color: Colors.white), onPressed: _showCastDialog),
                  IconButton(icon: const Icon(Icons.accessibility, color: Colors.white), onPressed: _showAccessibilityDialog),
                  IconButton(icon: const Icon(Icons.subtitles, color: Colors.white), onPressed: _showSubtitleDialog),
                ],
              ),
            ),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.replay_10, size: 40, color: Colors.white), onPressed: () => _seekToRelative(const Duration(seconds: -10))),
              const SizedBox(width: 40),
              IconButton(
                icon: Icon((player?.state.playing ?? false) ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 80, color: Colors.purpleAccent), 
                onPressed: _togglePlay
              ),
              const SizedBox(width: 40),
              IconButton(icon: const Icon(Icons.forward_10, size: 40, color: Colors.white), onPressed: () => _seekToRelative(const Duration(seconds: 10))),
            ]),
            const Spacer(),
            _buildProgressBar(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _getRelativeVideoPath() {
    try { return Uri.parse(widget.videoUrl).queryParameters['path'] ?? ""; } catch (e) { return ""; }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    if (d.inHours > 0) return "${d.inHours}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

    Widget _buildProgressBar() {
    final player = GlobalVideoManager().player;
    if (player == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: StreamBuilder<Duration>(
        stream: player.stream.position,
        builder: (context, snapshot) {
          final double duration = player.state.duration.inMilliseconds.toDouble();
          final double position = _isDragging ? _dragValue : player.state.position.inMilliseconds.toDouble();
          final double fraction = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

          return LayoutBuilder(builder: (context, constraints) {
            final double width = constraints.maxWidth;
            final double thumbRadius = 10.0;
            final double trackPadding = thumbRadius;
            final double usableWidth = width - (trackPadding * 2);
            final double thumbX = trackPadding + (fraction * usableWidth);
            
            final double buttonSize = 36.0;
            final double buttonTop = 30.0;

            return Listener(
              onPointerMove: (event) {
                if (_isDragging) {
                  RenderBox box = context.findRenderObject() as RenderBox;
                  Offset localPos = box.globalToLocal(event.position);
                  
                  double dx = localPos.dx - thumbX;
                  double dy = localPos.dy - (buttonTop + buttonSize / 2);
                  double distance = math.sqrt(dx * dx + dy * dy);

                  bool isHovering = distance <= (buttonSize / 2) + 20;
                  if (isHovering != _isHoveringX) {
                    setState(() => _isHoveringX = isHovering);
                  }
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor: Colors.purpleAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.transparent,
                          trackShape: const RectangularSliderTrackShape(),
                          overlayShape: SliderComponentShape.noOverlay,
                          thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbRadius, pressedElevation: 0),
                        ),
                        child: Slider(
                          value: position.clamp(0.0, duration > 0 ? duration : 1.0),
                          min: 0.0,
                          max: duration > 0 ? duration : 1.0,
                          onChanged: (val) {
                            if (!_isDragging) {
                              _initialTimeBeforeDrag = player.state.position.inMilliseconds.toDouble();
                            }
                            setState(() {
                              _isDragging = true;
                              _dragValue = val;
                            });
                            _showControls();
                          },
                          onChangeEnd: (val) {
                            if (_isHoveringX) {
                              if (_initialTimeBeforeDrag != null) {
                                player.seek(Duration(milliseconds: _initialTimeBeforeDrag!.toInt()));
                              }
                            } else {
                              player.seek(Duration(milliseconds: val.toInt()));
                              _saveProgress();
                            }
                            setState(() {
                              _isDragging = false;
                              _isHoveringX = false;
                            });
                            _startHideTimer();
                          },
                        ),
                      ),
                      if (_isDragging) ...[
                        Positioned(
                          left: (thumbX - 80).clamp(0.0, width - 160),
                          bottom: 45,
                          child: _buildThumbnailPreview(position),
                        ),
                        Positioned(
                          left: thumbX - (buttonSize / 2),
                          top: buttonTop,
                          child: Container(
                            width: buttonSize,
                            height: buttonSize,
                            decoration: BoxDecoration(
                              color: _isHoveringX ? Colors.purpleAccent : Colors.black.withOpacity(0.8),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isHoveringX ? Colors.white : Colors.white24, 
                                width: 1.5
                              ),
                              boxShadow: [
                                if (_isHoveringX)
                                  BoxShadow(
                                    color: Colors.purpleAccent.withOpacity(0.6),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                              ],
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 35),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(Duration(milliseconds: position.toInt())), 
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text(_formatDuration(player.state.duration), 
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            );
          });
        },
      ),
    );
  }

  Widget _buildThumbnailPreview(double positionMs) {
    final String videoPath = _getRelativeVideoPath();
    final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
    final String thumbUrl = "http://${widget.serverIp}:${widget.serverPort}/api/thumbnail?path=${Uri.encodeComponent(videoPath)}&time=${(positionMs / 1000).toStringAsFixed(1)}";
    
    return Container(
      width: 160,
      height: 90,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purpleAccent, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          thumbUrl,
          headers: {'Authorization': auth},
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => const Icon(Icons.image_not_supported, color: Colors.white24),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveProgress();
    _progressSaveTimer?.cancel();
    _hideControlsTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    _indicatorTimer?.cancel();
    _actionIndicatorTimer?.cancel();
    _castHeartbeatTimer?.cancel();
    _castStatusTimer?.cancel();
    _controlsAnimationController.dispose();
    _capsuleSlideController.dispose();
    _progressController.dispose();
    _skipIntroProgressController.dispose();
    _rootFocusNode.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }
}

class SubtitleHelper {
  static List<SubtitleEntry> parseSRT(String content) {
    List<SubtitleEntry> subtitles = [];
    if (content.startsWith('\uFEFF')) content = content.substring(1);
    final blocks = content.trim().split(RegExp(r'\n\s*\n'));
    for (var block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;
      final index = int.tryParse(lines[0].trim());
      if (index == null) continue;
      final timeLine = lines[1].trim();
      final timeMatch = RegExp(r'(\d{1,2}:\d{2}:\d{1,2}[.,]\d+)\s*--+>\s*(\d{1,2}:\d{2}:\d{1,2}[.,]\d+)').firstMatch(timeLine);
      if (timeMatch != null) {
        final start = _parseSrtTime(timeMatch.group(1)!);
        final end = _parseSrtTime(timeMatch.group(2)!);
        final text = lines.sublist(2).join('\n').replaceAll(RegExp(r'<[^>]*>'), '');
        subtitles.add(SubtitleEntry(index: index, start: start, end: end, text: text));
      }
    }
    return subtitles;
  }

  static List<SubtitleEntry> parseVTT(String content) {
    String sanitized = content.replaceFirst(RegExp(r'^WEBVTT[^\n]*'), '').trim();
    return parseSRT(sanitized);
  }

  static Duration _parseSrtTime(String timeString) {
    final parts = timeString.trim().replaceAll(',', '.').split(':');
    if (parts.length == 3) {
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final secondsParts = parts[2].split('.');
      final seconds = int.parse(secondsParts[0]);
      int milliseconds = 0;
      if (secondsParts.length > 1) {
        milliseconds = int.parse(secondsParts[1].padRight(3, '0').substring(0, 3));
      }
      return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: milliseconds);
    }
    return Duration.zero;
  }
}
