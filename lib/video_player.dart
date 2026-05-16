import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;

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

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _showControls = true;
  Timer? _hideTimer;
  List<SubtitleEntry> _subtitles = [];
  String _currentSubtitleText = '';
  double _subDelay = 0.0;
  double _subSize = 24.0;
  double _volumeBoost = 1.0;
  Color _subTextColor = Colors.white;
  Color _subBgColor = Colors.black.withOpacity(0.75);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
    _controller = VideoPlayerController.networkUrl(
      Uri.parse('${widget.videoUrl}&auth=${auth.split(' ')[1]}'),
      httpHeaders: {
        'Authorization': auth,
        'ngrok-skip-browser-warning': 'true',
      },
    );

    _controller.addListener(_videoListener);
    await _controller.initialize();
    if (mounted) {
      setState(() {});
      _controller.play();
      _controller.setVolume(_volumeBoost > 1.0 ? 1.0 : _volumeBoost);
      _startHideTimer();
    }

    if (widget.subtitleUrls.isNotEmpty) {
      _loadSubtitles(widget.subtitleUrls.first);
    }
  }

  void _videoListener() {
    if (_controller.value.isPlaying) {
      _updateSubtitles();
    }
    if (_controller.value.position >= _controller.value.duration && _controller.value.duration != Duration.zero) {
      if (widget.nextEpisode != null) {
        Navigator.pop(context, {'action': 'playNext', 'episode': widget.nextEpisode});
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadSubtitles(String url) async {
    try {
      final auth = 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': auth,
        'ngrok-skip-browser-warning': 'true',
      });
      if (response.statusCode == 200) {
        _parseSRT(response.body);
      }
    } catch (e) {}
  }

  void _parseSRT(String content) {
    _subtitles.clear();
    final exp = RegExp(
      r'(\d+)\r?\n(\d{1,2}:\d{2}:\d{1,2},\d{2,3}) --> (\d{1,2}:\d{2}:\d{1,2},\d{2,3})\r?\n([\s\S]*?)(?=\r?\n\r?\n\d+\r?\n|\$)',
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
    if (_subtitles.isEmpty) return;
    final now = _controller.value.position + Duration(milliseconds: (_subDelay * 1000).toInt());
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
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) _startHideTimer();
    });
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
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 2) {
            _controller.seekTo(_controller.value.position - const Duration(seconds: 10));
          } else {
            _controller.seekTo(_controller.value.position + const Duration(seconds: 10));
          }
        },
        child: Stack(
          children: [
            Center(
              child: _controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(color: Color(0xFF8A2BE2)),
            ),
            if (_currentSubtitleText.isNotEmpty)
              Positioned(
                bottom: _showControls ? 150 : 30,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: _subBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _currentSubtitleText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _subTextColor,
                        fontSize: _subSize,
                        fontWeight: FontWeight.w500,
                        shadows: const [Shadow(blurRadius: 4, color: Colors.black, offset: Offset(2, 2))],
                      ),
                    ),
                  ),
                ),
              ),
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withOpacity(0.8), Colors.transparent, Colors.transparent, Colors.black.withOpacity(0.8)],
                          stops: const [0.0, 0.2, 0.8, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 40,
                      left: 20,
                      right: 20,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.subtitles, color: Colors.white),
                            onPressed: _showSubtitlePicker,
                          ),
                          IconButton(
                            icon: const Icon(Icons.accessibility, color: Colors.white),
                            onPressed: _showAccessibilityDialog,
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.replay_10, color: Color(0xFF8A2BE2), size: 60),
                            onPressed: () => _controller.seekTo(_controller.value.position - const Duration(seconds: 10)),
                          ),
                          const SizedBox(width: 60),
                          IconButton(
                            icon: Icon(
                              _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: const Color(0xFF8A2BE2),
                              size: 90,
                            ),
                            onPressed: () {
                              _controller.value.isPlaying ? _controller.pause() : _controller.play();
                              _startHideTimer();
                            },
                          ),
                          const SizedBox(width: 60),
                          IconButton(
                            icon: const Icon(Icons.forward_10, color: Color(0xFF8A2BE2), size: 60),
                            onPressed: () => _controller.seekTo(_controller.value.position + const Duration(seconds: 10)),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 40,
                      left: 20,
                      right: 20,
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF8A2BE2),
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: _controller.value.position.inMilliseconds.toDouble(),
                              min: 0.0,
                              max: _controller.value.duration.inMilliseconds.toDouble(),
                              onChanged: (v) {
                                _controller.seekTo(Duration(milliseconds: v.toInt()));
                                _startHideTimer();
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(_controller.value.position), style: const TextStyle(color: Colors.white)),
                                Text(_formatDuration(_controller.value.duration), style: const TextStyle(color: Colors.white)),
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
                  if (i == 0) {
                    return ListTile(
                      title: const Text('None', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        setState(() => _subtitles.clear());
                        Navigator.pop(context);
                      },
                    );
                  }
                  final s = subs[i - 1];
                  return ListTile(
                    title: Text(s['name'], style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      _loadSubtitles('http://${widget.serverIp}:${widget.serverPort}/api/subtitle?path=${Uri.encodeComponent(s['path'])}');
                      Navigator.pop(context);
                    },
                  );
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
          shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFF8A2BE2)), borderRadius: BorderRadius.circular(20)),
          title: const Text('Accessibility', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAccRow('Volume Boost', '${_volumeBoost.toStringAsFixed(1)}x', () {
                setState(() {
                  _volumeBoost = math.max(1.0, _volumeBoost - 1.0);
                  _controller.setVolume(_volumeBoost > 1.0 ? 1.0 : _volumeBoost);
                });
                setDialogState(() {});
              }, () {
                setState(() {
                  _volumeBoost = math.min(20.0, _volumeBoost + 1.0);
                  _controller.setVolume(_volumeBoost > 1.0 ? 1.0 : _volumeBoost);
                });
                setDialogState(() {});
              }),
              _buildAccRow('Font Size', '${_subSize.toInt()}px', () {
                setState(() => _subSize -= 2);
                setDialogState(() {});
              }, () {
                setState(() => _subSize += 2);
                setDialogState(() {});
              }),
              _buildAccRow('Delay', '${_subDelay.toStringAsFixed(1)}s', () {
                setState(() => _subDelay -= 0.5);
                setDialogState(() {});
              }, () {
                setState(() => _subDelay += 0.5);
                setDialogState(() {});
              }),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Color(0xFF8A2BE2)))),
          ],
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
    _hideTimer?.cancel();
    _controller.removeListener(_videoListener);
    _controller.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
}

class SubtitleEntry {
  final Duration start;
  final Duration end;
  final String text;
  SubtitleEntry({required this.start, required this.end, required this.text});
}
