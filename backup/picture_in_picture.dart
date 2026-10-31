import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:native_picture_in_picture/native_picture_in_picture.dart';
import 'package:native_picture_in_picture/pip_event.dart';
import 'video_player.dart';

class GlobalVideoManager {
  static final GlobalVideoManager _instance = GlobalVideoManager._internal();
  factory GlobalVideoManager() => _instance;
  GlobalVideoManager._internal();

  Player? player;
  VideoController? controller;
  OverlayEntry? _pipEntry;
  
  String? currentTitle;
  String? currentVideoUrl;
  List<String>? currentSubtitleUrls;
  String? serverIp;
  String? serverPort;
  String? username;
  String? password;

  List<SubtitleEntry> subtitles = [];
  double subtitleFontSize = 20.0;
  double subtitleDelaySeconds = 0.0;
  bool isGlassSubtitle = true;
  Color subtitleColor = Colors.white;

  Offset pipPosition = const Offset(16, 100);
  bool isPiPActive = false;
  bool isReturningFromPiP = false;

    void initPlayer({
    required String url,
    required String title,
    required List<String> subs,
    required String ip,
    required String port,
    required String user,
    required String pass,
  }) {
    if (player != null && currentVideoUrl == url) return;

    disposePlayer();

    player = Player();
    controller = VideoController(player!);
    
    currentVideoUrl = url;
    currentTitle = title;
    currentSubtitleUrls = subs;
    serverIp = ip;
    serverPort = port;
    username = user;
    password = pass;

    _setupNativePip(url, user, pass);
  }

  // ------------------------------------------------------------------
  // Native iOS system Picture-in-Picture (shows when the user leaves the
  // app, e.g. swipes to the iOS home screen, while a video is playing).
  //
  // media_kit renders into a Flutter texture, which iOS cannot show in a
  // system PiP window, so a second native AVPlayer is kept in sync and used
  // for the system PiP window only. AVPlayer can only play mp4/m4v/mov
  // (not mkv/avi...), so other formats skip native PiP.
  // ------------------------------------------------------------------
  static const Set<String> _nativePipFormats = {'mp4', 'm4v', 'mov'};
  // Set to true to attempt native PiP for every format (e.g. if your server
  // remuxes everything to an AVPlayer-compatible stream).
  static const bool tryNativePipForAllFormats = false;

  NativePictureInPicture? _nativePip;
  StreamSubscription<dynamic>? _nativePipEventSub;
  StreamSubscription<dynamic>? _nativePlayingSub;
  bool _nativePipReady = false;
  bool _nativePipActive = false;
  bool _nativeRestoreRequested = false;
  int _nativeGeneration = 0;

  String _extensionOf(String url) {
    String candidate = url;
    try {
      final uri = Uri.parse(url);
      candidate = uri.queryParameters['path'] ?? uri.path;
    } catch (_) {}
    final dot = candidate.lastIndexOf('.');
    if (dot < 0) return '';
    return candidate.substring(dot + 1).toLowerCase();
  }

  Future<void> _setupNativePip(String url, String user, String pass) async {
    if (!Platform.isIOS) return;
    final int gen = ++_nativeGeneration;
    final Player? mkPlayer = player;
    if (mkPlayer == null) return;
    try {
      final String ext = _extensionOf(url);
      // Movie paths are folders (no extension), so unknown extensions are allowed to try.
      if (!tryNativePipForAllFormats && ext.isNotEmpty && !_nativePipFormats.contains(ext)) return;
      final pip = NativePictureInPicture();
      if (!await pip.isPipSupported()) return;

      String nativeUrl;
      if (url.startsWith('/')) {
        nativeUrl = Uri.file(url).toString();
      } else if (url.startsWith('file://')) {
        nativeUrl = url;
      } else {
        final raw = base64Encode(utf8.encode('$user:$pass'));
        nativeUrl = url.contains('?') ? '$url&auth=$raw' : '$url?auth=$raw';
      }

      await pip.initialize(nativeUrl);
      if (gen != _nativeGeneration || player != mkPlayer) {
        await pip.dispose();
        return;
      }
      await pip.setAutoPipEnabled(false);
      _nativePip = pip;
      _nativePipReady = true;
      _nativePipEventSub = pip.onPipEvent.listen(_onNativePipEvent);
      _nativePlayingSub = mkPlayer.stream.playing.listen((_) => _refreshNativeAutoPip());
      _refreshNativeAutoPip();
    } catch (e) {
      _nativePipReady = false;
    }
  }

  // Auto-PiP (on swipe-home) is only armed while the video is actually playing.
  void _refreshNativeAutoPip() {
    final pip = _nativePip;
    final pl = player;
    if (pip == null || !_nativePipReady || pl == null || _nativePipActive) return;
    pip.setAutoPipEnabled(pl.state.playing).catchError((_) {});
  }

  Future<void> _onNativePipEvent(PipEvent event) async {
    final pip = _nativePip;
    final pl = player;
    if (pip == null || pl == null) return;
    try {
      if (event == PipEvent.willStart) {
        _nativePipActive = true;
        _nativeRestoreRequested = false;
        final pos = pl.state.position;
        await pl.pause(); // silence media_kit so audio is not doubled
        await pip.seekTo(pos);
        await pip.play();
      } else if (event == PipEvent.restoreUI) {
        _nativeRestoreRequested = true;
        await _pullPositionFromNative(resume: true);
        _nativePipActive = false;
        _refreshNativeAutoPip();
      } else if (event == PipEvent.didStop) {
        if (!_nativeRestoreRequested) await _pullPositionFromNative(resume: false);
        _nativePipActive = false;
        _nativeRestoreRequested = false;
        _refreshNativeAutoPip();
      }
    } catch (_) {}
  }

  Future<void> _pullPositionFromNative({required bool resume}) async {
    final pip = _nativePip;
    final pl = player;
    if (pip == null || pl == null) return;
    final pos = await pip.getPosition();
    await pip.pause();
    if (pos > Duration.zero) await pl.seek(pos);
    if (resume) await pl.play();
  }

  void _teardownNativePip() {
    _nativeGeneration++;
    _nativePipEventSub?.cancel();
    _nativePipEventSub = null;
    _nativePlayingSub?.cancel();
    _nativePlayingSub = null;
    final pip = _nativePip;
    _nativePip = null;
    _nativePipReady = false;
    _nativePipActive = false;
    _nativeRestoreRequested = false;
    if (pip != null) {
      () async {
        try {
          await pip.setAutoPipEnabled(false);
          await pip.dispose();
        } catch (_) {}
      }();
    }
  }


  void updateSubtitleData({
    required List<SubtitleEntry> entries,
    required double fontSize,
    required double delay,
    required bool glass,
    required Color color,
  }) {
    subtitles = entries;
    subtitleFontSize = fontSize;
    subtitleDelaySeconds = delay;
    isGlassSubtitle = glass;
    subtitleColor = color;
  }

  void showPiP(BuildContext context) {
    if (isPiPActive || player == null) return;
    isPiPActive = true;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    bool isDragging = false;
    _pipEntry = OverlayEntry(
      builder: (context) => StatefulBuilder(
        builder: (context, setOverlayState) {
          final size = MediaQuery.of(context).size;
          final padding = MediaQuery.of(context).padding;
          const double pipWidth = 220.0;
          const double pipHeight = 124.0;
          const double edgePadding = 16.0;
          return AnimatedPositioned(
            duration: isDragging ? Duration.zero : const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            left: pipPosition.dx,
            top: pipPosition.dy,
            child: GestureDetector(
              onPanStart: (_) => setOverlayState(() => isDragging = true),
              onPanUpdate: (details) {
                setOverlayState(() {
                  double newX = pipPosition.dx + details.delta.dx;
                  double newY = pipPosition.dy + details.delta.dy;
                  pipPosition = Offset(
                    newX.clamp(0.0, size.width - pipWidth),
                    newY.clamp(padding.top, size.height - pipHeight - padding.bottom),
                  );
                });
              },
              onPanEnd: (_) {
                setOverlayState(() {
                  isDragging = false;
                  double targetX = (pipPosition.dx + pipWidth / 2) < size.width / 2 
                      ? edgePadding 
                      : size.width - pipWidth - edgePadding;
                  double targetY = pipPosition.dy.clamp(
                    padding.top + edgePadding, 
                    size.height - pipHeight - padding.bottom - edgePadding
                  );
                  pipPosition = Offset(targetX, targetY);
                });
              },
              onTap: () {
                isReturningFromPiP = true;
                hidePiP();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    settings: const RouteSettings(name: '/video_player'),
                    builder: (context) => VideoPlayerScreen(
                      videoUrl: currentVideoUrl!,
                      subtitleUrls: currentSubtitleUrls!,
                      title: currentTitle!,
                      serverIp: serverIp!,
                      serverPort: serverPort!,
                      username: username!,
                      password: password!,
                    ),
                  ),
                );
              },
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                color: Colors.black,
                child: Stack(
                  children: [
                    SizedBox(
                      width: pipWidth,
                      height: pipHeight,
                      child: Video(controller: controller!, controls: NoVideoControls),
                    ),
                    Positioned.fill(
                      child: StreamBuilder<Duration>(
                        stream: player!.stream.position,
                        builder: (context, snapshot) {
                          if (subtitles.isEmpty) return const SizedBox.shrink();
                          final currentMs = player!.state.position.inMilliseconds;
                          final delayMs = (subtitleDelaySeconds * 1000).toInt();
                          final adjustedPos = Duration(milliseconds: currentMs - delayMs);
                          String text = '';
                          for (final entry in subtitles) {
                            if (adjustedPos >= entry.start && adjustedPos <= entry.end) {
                              text = entry.text;
                              break;
                            }
                          }
                          if (text.isEmpty) return const SizedBox.shrink();
                          return Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: isGlassSubtitle ? 5 : 0, sigmaY: isGlassSubtitle ? 5 : 0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isGlassSubtitle ? subtitleColor.withOpacity(0.15) : subtitleColor.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      text,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: subtitleFontSize * 0.4,
                                        fontWeight: FontWeight.bold,
                                        height: 1.1,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          disposePlayer();
                          hidePiP();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    Overlay.of(context).insert(_pipEntry!);
  }

  void hidePiP() {
    isPiPActive = false;
    _pipEntry?.remove();
    _pipEntry = null;
  }

  void disposePlayer() {
    _teardownNativePip();
    player?.dispose();
    player = null;
    controller = null;
    currentVideoUrl = null;
    isReturningFromPiP = false;
    subtitles = [];
  }
}
