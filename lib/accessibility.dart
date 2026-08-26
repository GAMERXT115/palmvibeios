import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AccessibilityDialog extends StatefulWidget {
  final double playbackSpeed;
  final bool isGlassSubtitle;
  final double audioBoostFactor;
  final double subtitleFontSize;
  final double subtitleDelaySeconds;
  final double subtitleHeight;
  final double scale;
  final Color subtitleColor;
  final bool autoSkipIntro;
  final Function(double) onPlaybackSpeedChanged;
  final Function(bool) onGlassSubtitleChanged;
  final Function(double) onAudioBoostChanged;
  final Function(double) onSubtitleFontSizeChanged;
  final Function(double) onSubtitleDelayChanged;
  final Function(double) onSubtitleHeightChanged;
  final Function(double) onScaleChanged;
  final Function(Color) onSubtitleColorChanged;
  final Function(bool) onAutoSkipIntroChanged;
  final Function(String) onSetIntroTiming;
  final VoidCallback onReportIssue;

  const AccessibilityDialog({
    Key? key,
    required this.playbackSpeed,
    required this.isGlassSubtitle,
    required this.audioBoostFactor,
    required this.subtitleFontSize,
    required this.subtitleDelaySeconds,
    required this.subtitleHeight,
    required this.scale,
    required this.subtitleColor,
    required this.autoSkipIntro,
    required this.onPlaybackSpeedChanged,
    required this.onGlassSubtitleChanged,
    required this.onAudioBoostChanged,
    required this.onSubtitleFontSizeChanged,
    required this.onSubtitleDelayChanged,
    required this.onSubtitleHeightChanged,
    required this.onScaleChanged,
    required this.onSubtitleColorChanged,
    required this.onAutoSkipIntroChanged,
    required this.onSetIntroTiming,
    required this.onReportIssue,
  }) : super(key: key);

  @override
  State<AccessibilityDialog> createState() => _AccessibilityDialogState();
}

class _AccessibilityDialogState extends State<AccessibilityDialog> {
  late double _currentSpeed;
  late bool _currentGlass;
  late double _currentBoost;
  late double _currentSize;
  late double _currentDelay;
  late double _currentHeight;
  late double _currentScale;
  late Color _currentColor;
  late bool _currentAutoSkip;

  Timer? _repeatTimer;
  Timer? _delayTimer;

  final Map<String, Color> _colorOptions = {
    'White': Colors.white,
    'Yellow': Colors.yellow,
    'Cyan': Colors.cyan,
    'Green': Colors.greenAccent,
    'Red': Colors.redAccent,
    'Orange': Colors.orangeAccent,
    'Pink': Colors.pinkAccent,
    'Purple': Colors.purpleAccent,
  };

  @override
  void initState() {
    super.initState();
    _currentSpeed = widget.playbackSpeed;
    _currentGlass = widget.isGlassSubtitle;
    _currentBoost = widget.audioBoostFactor;
    _currentSize = widget.subtitleFontSize;
    _currentDelay = widget.subtitleDelaySeconds;
    _currentHeight = widget.subtitleHeight;
    _currentScale = widget.scale;
    _currentAutoSkip = widget.autoSkipIntro;
    _currentColor = _colorOptions.values.firstWhere(
      (c) => c.value == widget.subtitleColor.value,
      orElse: () => Colors.white,
    );
  }

  void _handleAction(VoidCallback action) {
    action();
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
    _delayTimer = Timer(const Duration(seconds: 3), () {
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 100), (t) => action());
    });
  }

  void _stopAction() {
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
  }

  Widget _buildRepeatingButton({
    required IconData icon,
    required VoidCallback action,
  }) {
    return GestureDetector(
      onTapDown: (_) => _handleAction(action),
      onTapUp: (_) => _stopAction(),
      onTapCancel: () => _stopAction(),
      child: Focus(
        child: Builder(builder: (context) {
          final bool hasFocus = Focus.of(context).hasFocus;
          return Container(
            decoration: BoxDecoration(
              color: hasFocus ? Colors.purple.withOpacity(0.6) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(icon, color: Colors.white),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTile({
    required String title,
    required Widget trailing,
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: Colors.white70)) : null,
        trailing: trailing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 30),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 1000,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(40, 80, 40, 40),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _buildTile(
                                  title: 'Playback Speed',
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildRepeatingButton(
                                        icon: Icons.remove_circle,
                                        action: () {
                                          setState(() => _currentSpeed = double.parse((_currentSpeed - 0.1).toStringAsFixed(1)).clamp(0.1, 5.0));
                                          widget.onPlaybackSpeedChanged(_currentSpeed);
                                        },
                                      ),
                                      Text('${_currentSpeed.toStringAsFixed(1)}x', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      _buildRepeatingButton(
                                        icon: Icons.add_circle,
                                        action: () {
                                          setState(() => _currentSpeed = double.parse((_currentSpeed + 0.1).toStringAsFixed(1)).clamp(0.1, 5.0));
                                          widget.onPlaybackSpeedChanged(_currentSpeed);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                _buildTile(
                                  title: 'Audio Boost',
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildRepeatingButton(
                                        icon: Icons.remove_circle,
                                        action: () {
                                          setState(() => _currentBoost = double.parse((_currentBoost - 0.1).toStringAsFixed(1)).clamp(1.0, 20.0));
                                          widget.onAudioBoostChanged(_currentBoost);
                                        },
                                      ),
                                      Text('${(_currentBoost * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      _buildRepeatingButton(
                                        icon: Icons.add_circle,
                                        action: () {
                                          setState(() => _currentBoost = double.parse((_currentBoost + 0.1).toStringAsFixed(1)).clamp(1.0, 20.0));
                                          widget.onAudioBoostChanged(_currentBoost);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                _buildTile(
                                  title: 'Zoom Level',
                                  subtitle: _currentScale == 1.0 ? "Original" : "${(_currentScale * 100).toInt()}%",
                                  trailing: IconButton(
                                    icon: const Icon(Icons.zoom_in, color: Colors.white),
                                    onPressed: () {
                                      setState(() => _currentScale = _currentScale == 1.0 ? 1.25 : (_currentScale == 1.25 ? 1.5 : 1.0));
                                      widget.onScaleChanged(_currentScale);
                                    },
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white10,
                                          padding: const EdgeInsets.symmetric(vertical: 20),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: () => widget.onSetIntroTiming('start'),
                                        child: const Text("INTRO\nSTART", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, height: 1.2)),
                                      ),
                                    ),
                                    const SizedBox(width: 15),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white10,
                                          padding: const EdgeInsets.symmetric(vertical: 20),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: () => widget.onSetIntroTiming('end'),
                                        child: const Text("INTRO\nEND", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, height: 1.2)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 15),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent.withOpacity(0.2),
                                    minimumSize: const Size(double.infinity, 60),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: const BorderSide(color: Colors.redAccent, width: 1),
                                    ),
                                  ),
                                  onPressed: widget.onReportIssue,
                                  icon: const Icon(Icons.report_problem, color: Colors.white),
                                  label: const Text("REPORT AN ISSUE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                ),
                              ],
                            ),
                          ),
                          const VerticalDivider(color: Colors.white10, thickness: 1, width: 60),
                          Expanded(
                            child: Column(
                              children: [
                                _buildTile(
                                  title: 'Glass Subtitles',
                                  trailing: Switch(
                                    value: _currentGlass,
                                    activeColor: Colors.purpleAccent,
                                    onChanged: (val) {
                                      setState(() => _currentGlass = val);
                                      widget.onGlassSubtitleChanged(val);
                                    },
                                  ),
                                ),
                                _buildTile(
                                  title: 'Auto-Skip Intro',
                                  trailing: Switch(
                                    value: _currentAutoSkip,
                                    activeColor: Colors.purpleAccent,
                                    onChanged: (val) {
                                      setState(() => _currentAutoSkip = val);
                                      widget.onAutoSkipIntroChanged(val);
                                    },
                                  ),
                                ),
                                _buildTile(
                                  title: 'Subtitle Shade Color',
                                  trailing: Theme(
                                    data: Theme.of(context).copyWith(canvasColor: Colors.black),
                                    child: DropdownButton<Color>(
                                      value: _currentColor,
                                      underline: const SizedBox(),
                                      icon: const Icon(Icons.color_lens, color: Colors.white),
                                      items: _colorOptions.entries.map((entry) {
                                        return DropdownMenuItem<Color>(
                                          value: entry.value,
                                          child: Row(
                                            children: [
                                              Container(width: 20, height: 20, decoration: BoxDecoration(color: entry.value, shape: BoxShape.circle)),
                                              const SizedBox(width: 10),
                                              Text(entry.key, style: const TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (Color? newColor) {
                                        if (newColor != null) {
                                          setState(() => _currentColor = newColor);
                                          widget.onSubtitleColorChanged(newColor);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                _buildTile(
                                  title: 'Subtitle Size',
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildRepeatingButton(
                                        icon: Icons.remove_circle,
                                        action: () {
                                          setState(() => _currentSize = (_currentSize - 2).clamp(10, 100));
                                          widget.onSubtitleFontSizeChanged(_currentSize);
                                        },
                                      ),
                                      Text('${_currentSize.toInt()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      _buildRepeatingButton(
                                        icon: Icons.add_circle,
                                        action: () {
                                          setState(() => _currentSize = (_currentSize + 2).clamp(10, 100));
                                          widget.onSubtitleFontSizeChanged(_currentSize);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                _buildTile(
                                  title: 'Subtitle Delay',
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildRepeatingButton(
                                        icon: Icons.remove_circle,
                                        action: () {
                                          setState(() => _currentDelay = double.parse((_currentDelay - 0.5).toStringAsFixed(1)));
                                          widget.onSubtitleDelayChanged(_currentDelay);
                                        },
                                      ),
                                      Text('${_currentDelay.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      _buildRepeatingButton(
                                        icon: Icons.add_circle,
                                        action: () {
                                          setState(() => _currentDelay = double.parse((_currentDelay + 0.5).toStringAsFixed(1)));
                                          widget.onSubtitleDelayChanged(_currentDelay);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                _buildTile(
                                  title: 'Subtitle Height',
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildRepeatingButton(
                                        icon: Icons.remove_circle,
                                        action: () {
                                          setState(() => _currentHeight = (_currentHeight - 5).clamp(0, 500));
                                          widget.onSubtitleHeightChanged(_currentHeight);
                                        },
                                      ),
                                      Text('${_currentHeight.toInt()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      _buildRepeatingButton(
                                        icon: Icons.add_circle,
                                        action: () {
                                          setState(() => _currentHeight = (_currentHeight + 5).clamp(0, 500));
                                          widget.onSubtitleHeightChanged(_currentHeight);
                                        },
                                      ),
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
                ),
                Positioned(
                  top: 20,
                  left: 40,
                  child: const Text('ACCESSIBILITY', style: TextStyle(color: Colors.purpleAccent, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                ),
                Positioned(
                  top: 15,
                  right: 15,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopAction();
    super.dispose();
  }
}
