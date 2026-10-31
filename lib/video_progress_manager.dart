import 'dart:convert';
import 'package:http/http.dart' as http;

class VideoProgress {
  final String videoPath;
  final String username;
  final int position;
  final int duration;
  final DateTime lastUpdated;

  VideoProgress({
    required this.videoPath,
    required this.username,
    required this.position,
    required this.duration,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() {
    return {
      'videoPath': videoPath,
      'username': username,
      'position': position,
      'duration': duration,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory VideoProgress.fromJson(Map<String, dynamic> json) {
    return VideoProgress(
      videoPath: json['videoPath'] ?? '',
      username: json['username'] ?? '',
      position: json['position'] ?? 0,
      duration: json['duration'] ?? 0,
      lastUpdated: DateTime.parse(json['lastUpdated'] ?? DateTime.now().toIso8601String()),
    );
  }

  double get percentageWatched {
    if (duration <= 0) return 0;
    return (position / duration).clamp(0.0, 1.0);
  }
}

class VideoProgressManager {
  static Future<void> saveProgress({
    required String videoPath,
    required String title,
    required String serverIp,
    required String serverPort,
    required String authHeader,
    required int position,
    required int duration,
  }) async {
    try {
      if (position < 5000 || (duration - position < 10000)) return;

      final url = Uri.parse('http://$serverIp:$serverPort/api/save-progress');
      await http.post(
        url,
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'videoPath': videoPath,
          'title': title,
          'position': position,
          'duration': duration,
        }),
      );
    } catch (e) {}
  }

  static Future<VideoProgress?> getProgress({
    required String videoPath,
    required String title,
    required String serverIp,
    required String serverPort,
    required String authHeader,
  }) async {
    try {
      final url = Uri.parse('http://$serverIp:$serverPort/api/get-progress')
          .replace(queryParameters: {
        'path': videoPath,
        'title': title,
      });

      final response = await http.get(url, headers: {
        'Authorization': authHeader,
        'ngrok-skip-browser-warning': 'true',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['progress'] != null) {
          return VideoProgress.fromJson(data['progress']);
        }
      }
    } catch (e) {}
    return null;
  }
}
