import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
    player?.dispose();
    player = null;
    controller = null;
    currentVideoUrl = null;
    isReturningFromPiP = false;
    subtitles = [];
  }
}
