import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'video_player.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

class DownloadItem {
  final String title;
  final String localVideoPath;
  final String localPosterPath;
  final List<String> localSubtitlePaths;
  final String duration;
  final String? showTitle;
  final String? seasonName;
  final String? episodeThumbnailPath;

  DownloadItem({
    required this.title,
    required this.localVideoPath,
    required this.localPosterPath,
    required this.localSubtitlePaths,
    this.duration = "0:00",
    this.showTitle,
    this.seasonName,
    this.episodeThumbnailPath,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'localVideoPath': localVideoPath,
        'localPosterPath': localPosterPath,
        'localSubtitlePaths': localSubtitlePaths,
        'duration': duration,
        'showTitle': showTitle,
        'seasonName': seasonName,
        'episodeThumbnailPath': episodeThumbnailPath,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        title: json['title'],
        localVideoPath: json['localVideoPath'],
        localPosterPath: json['localPosterPath'],
        localSubtitlePaths: List<String>.from(json['localSubtitlePaths']),
        duration: json['duration'] ?? "0:00",
        seasonName: json['seasonName'],
        showTitle: json['showTitle'],
        episodeThumbnailPath: json['episodeThumbnailPath'],
      );
}

class DownloadsManager {
  static final DownloadsManager _instance = DownloadsManager._internal();
  factory DownloadsManager() => _instance;
  DownloadsManager._internal();

  final Map<String, double> downloadProgress = {};
  final Map<String, DownloadItem> activeMetadata = {};
  final Map<String, bool> cancelRequests = {};
  final StreamController<Map<String, double>> progressController = StreamController<Map<String, double>>.broadcast();

  Future<void> _showLocalNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'downloads',
      'Downloads',
      channelDescription: 'Notifications for file downloads',
      importance: Importance.max,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformDetails,
    );
  }

  Future<void> startDownload({
    required String videoUrl,
    required String title,
    required String posterUrl,
    required List<String> subtitleUrls,
    required String authHeader,
    required Function(String) onNotify,
    String? showTitle,
    String? seasonName,
    String? episodeThumbnailUrl,
    String duration = "0:00",
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folderName = showTitle ?? title;
      final cleanShowName = folderName.replaceAll(RegExp(r'[^\w\s]+'), '');
      final cleanSeasonName = (seasonName ?? "Single").replaceAll(RegExp(r'[^\w\s]+'), '');
      final saveDir = Directory('${dir.path}/downloads/$cleanShowName/$cleanSeasonName');
      
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final posterPath = '${dir.path}/downloads/$cleanShowName/poster.jpg';
      if (!File(posterPath).existsSync()) {
        await _downloadStaticFile(posterUrl, posterPath, authHeader);
      }

      String? thumbPath;
      if (episodeThumbnailUrl != null) {
        thumbPath = '${saveDir.path}/${title.replaceAll(RegExp(r'[^\w\s]+'), '')}_thumb.jpg';
        await _downloadStaticFile(episodeThumbnailUrl, thumbPath, authHeader);
      }

      final videoExt = path.extension(Uri.parse(videoUrl).path).isEmpty ? ".mp4" : path.extension(Uri.parse(videoUrl).path);
      final videoPath = '${saveDir.path}/${title.replaceAll(RegExp(r'[^\w\s]+'), '')}_video$videoExt';

      activeMetadata[videoUrl] = DownloadItem(
        title: title,
        localVideoPath: videoPath,
        localPosterPath: posterPath,
        localSubtitlePaths: [],
        duration: duration,
        showTitle: showTitle,
        seasonName: seasonName,
        episodeThumbnailPath: thumbPath,
      );

      downloadProgress[videoUrl] = 0.0;
      cancelRequests[videoUrl] = false;
      progressController.add(downloadProgress);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(videoUrl));
      request.headers.addAll({
        'Authorization': authHeader,
        'ngrok-skip-browser-warning': 'true',
      });

      final response = await client.send(request);
      final total = response.contentLength ?? 0;
      int received = 0;

      final file = File(videoPath);
      final sink = file.openWrite();

      await for (var chunk in response.stream) {
        if (cancelRequests[videoUrl] == true) {
          await sink.close();
          if (await file.exists()) await file.delete();
          _cleanupActive(videoUrl);
          client.close();
          return;
        }
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          downloadProgress[videoUrl] = received / total;
          progressController.add(downloadProgress);
        }
      }

      await sink.close();

      List<String> localSubs = [];
      for (int i = 0; i < subtitleUrls.length; i++) {
        final sPath = '${saveDir.path}/${title.replaceAll(RegExp(r'[^\w\s]+'), '')}_sub_$i.srt';
        await _downloadStaticFile(subtitleUrls[i], sPath, authHeader);
        localSubs.add(sPath);
      }

      final finalItem = DownloadItem(
        title: title,
        localVideoPath: videoPath,
        localPosterPath: posterPath,
        localSubtitlePaths: localSubs,
        duration: duration,
        showTitle: showTitle,
        seasonName: seasonName,
        episodeThumbnailPath: thumbPath,
      );

      await _saveMetadata(finalItem);
      _cleanupActive(videoUrl);
      onNotify('Download complete: $title');
      await _showLocalNotification('Download Complete', title);
    } catch (e) {
      _cleanupActive(videoUrl);
      onNotify('Download failed: $e');
      await _showLocalNotification('Download Failed', title);
    }
  }

  void _cleanupActive(String url) {
    downloadProgress.remove(url);
    activeMetadata.remove(url);
    cancelRequests.remove(url);
    progressController.add(downloadProgress);
  }

  Future<void> _downloadStaticFile(String url, String savePath, String auth) async {
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': auth,
        'ngrok-skip-browser-warning': 'true',
      });
      if (response.statusCode == 200) {
        final file = File(savePath);
        await file.writeAsBytes(response.bodyBytes);
      }
    } catch (e) {}
  }

  Future<void> _saveMetadata(DownloadItem item) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList('downloaded_content_v2') ?? [];
    list.add(jsonEncode(item.toJson()));
    await prefs.setStringList('downloaded_content_v2', list);
    progressController.add({});
  }

  Future<List<DownloadItem>> getDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList('downloaded_content_v2') ?? [];
    return list.map((e) => DownloadItem.fromJson(jsonDecode(e))).toList();
  }

  Future<void> deleteDownload(DownloadItem item) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList('downloaded_content_v2') ?? [];
    list.removeWhere((e) => DownloadItem.fromJson(jsonDecode(e)).localVideoPath == item.localVideoPath);
    await prefs.setStringList('downloaded_content_v2', list);

    final vFile = File(item.localVideoPath);
    if (await vFile.exists()) await vFile.delete();

    if (item.episodeThumbnailPath != null) {
      final tFile = File(item.episodeThumbnailPath!);
      if (await tFile.exists()) await tFile.delete();
    }

    for (var s in item.localSubtitlePaths) {
      final sFile = File(s);
      if (await sFile.exists()) await sFile.delete();
    }
    progressController.add({});
  }

  Future<void> deleteShow(String showTitle) async {
    final downloads = await getDownloads();
    final toDelete = downloads.where((i) => i.showTitle == showTitle).toList();
    for (var item in toDelete) {
      await deleteDownload(item);
    }
    final dir = await getApplicationDocumentsDirectory();
    final showDir = Directory('${dir.path}/downloads/${showTitle.replaceAll(RegExp(r'[^\w\s]+'), '')}');
    if (await showDir.exists()) {
      await showDir.delete(recursive: true);
    }
    progressController.add({});
  }

  void stopDownload(String url) {
    cancelRequests[url] = true;
  }
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<DownloadItem> _movies = [];
  Map<String, List<DownloadItem>> _tvShows = {};
  bool _isLoading = true;
  StreamSubscription? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
    _progressSubscription = DownloadsManager().progressController.stream.listen((_) {
      _loadDownloads();
    });
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  int _extractNumber(String s) {
    final match = RegExp(r'(\d+)').firstMatch(s);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  Future<void> _loadDownloads() async {
    final items = await DownloadsManager().getDownloads();
    if (mounted) {
      setState(() {
        _movies = items.where((i) => i.showTitle == null).toList();
        _movies.sort((a, b) => _extractNumber(a.title).compareTo(_extractNumber(b.title)));
        
        _tvShows = {};
        for (var ep in items.where((i) => i.showTitle != null)) {
          _tvShows.putIfAbsent(ep.showTitle!, () => []).add(ep);
        }
        _isLoading = false;
      });
    }
  }

  Future<bool?> _showDeleteConfirmation(BuildContext context, String title) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Confirm Delete", style: TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to delete '$title'?", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Downloads'),
          backgroundColor: Colors.black,
          bottom: TabBar(
            indicatorColor: const Color(0xFF8A2BE2),
            onTap: (index) => _loadDownloads(),
            tabs: const [Tab(text: "Movies"), Tab(text: "TV Shows")],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF8A2BE2)))
            : TabBarView(
                children: [
                  _buildMoviesList(),
                  _buildTvShowsList(),
                ],
              ),
      ),
    );
  }

  Widget _buildMoviesList() {
    return StreamBuilder<Map<String, double>>(
      stream: DownloadsManager().progressController.stream,
      builder: (context, snapshot) {
        final active = snapshot.data ?? {};
        final activeMovies = active.keys.where((url) {
          final meta = DownloadsManager().activeMetadata[url];
          if (meta == null || meta.showTitle != null) return false;
          return !_movies.any((m) => m.title == meta.title);
        }).toList();

        return ListView.separated(
          itemCount: _movies.length + activeMovies.length,
          separatorBuilder: (context, index) => Divider(color: Colors.grey.withOpacity(0.2)),
          itemBuilder: (context, index) {
            if (index < activeMovies.length) {
              final url = activeMovies[index];
              final progress = active[url]!;
              final meta = DownloadsManager().activeMetadata[url]!;
              return ListTile(
                leading: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (meta.localPosterPath.isNotEmpty && File(meta.localPosterPath).existsSync())
                       ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(File(meta.localPosterPath), width: 50, height: 75, fit: BoxFit.cover)),
                    Container(width: 50, height: 75, color: Colors.black45),
                    CircularProgressIndicator(value: progress, color: const Color(0xFF8A2BE2)),
                    IconButton(icon: const Icon(Icons.stop, size: 18, color: Colors.white), onPressed: () => DownloadsManager().stopDownload(url)),
                  ],
                ),
                title: Text(meta.title, style: const TextStyle(color: Colors.white)),
                subtitle: const Text("Downloading...", style: TextStyle(color: Color(0xFF8A2BE2), fontWeight: FontWeight.bold)),
              );
            }
            final item = _movies[index - activeMovies.length];
            return Dismissible(
              key: Key(item.localVideoPath),
              direction: DismissDirection.endToStart,
              confirmDismiss: (dir) => _showDeleteConfirmation(context, item.title),
              onDismissed: (dir) async {
                await DownloadsManager().deleteDownload(item);
                _loadDownloads();
              },
              background: Container(
                color: Colors.redAccent,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: item.localPosterPath.isNotEmpty && File(item.localPosterPath).existsSync()
                      ? Image.file(File(item.localPosterPath), width: 50, height: 75, fit: BoxFit.cover)
                      : Container(width: 50, height: 75, color: Colors.grey[900], child: const Icon(Icons.movie, color: Colors.white24)),
                ),
                title: Text(item.title, style: const TextStyle(color: Colors.white)),
                subtitle: Row(
                  children: [
                    Text(item.duration, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    if (item.localSubtitlePaths.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.subtitles, size: 14, color: Colors.grey),
                    ]
                  ],
                ),
                onTap: () => _playOffline(item),
              ),
            );
          },
        );
      }
    );
  }

  Widget _buildTvShowsList() {
    return StreamBuilder<Map<String, double>>(
      stream: DownloadsManager().progressController.stream,
      builder: (context, snapshot) {
        final active = snapshot.data ?? {};
        final activeShows = active.keys
            .map((url) => DownloadsManager().activeMetadata[url])
            .where((meta) => meta != null && meta.showTitle != null)
            .map((meta) => meta!.showTitle!)
            .toSet();

        final allShowTitles = {..._tvShows.keys, ...activeShows}.toList()..sort();

        return ListView.separated(
          itemCount: allShowTitles.length,
          separatorBuilder: (context, index) => Divider(color: Colors.grey.withOpacity(0.2)),
          itemBuilder: (context, index) {
            final title = allShowTitles[index];
            final episodes = _tvShows[title] ?? [];
            final isActive = activeShows.contains(title);
            final firstItem = isActive 
                ? DownloadsManager().activeMetadata.values.firstWhere((m) => m.showTitle == title)
                : episodes.first;

            return Dismissible(
              key: Key(title),
              direction: DismissDirection.endToStart,
              confirmDismiss: (dir) => _showDeleteConfirmation(context, title),
              onDismissed: (dir) async {
                await DownloadsManager().deleteShow(title);
                _loadDownloads();
              },
              background: Container(
                color: Colors.redAccent,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: firstItem.localPosterPath.isNotEmpty && File(firstItem.localPosterPath).existsSync()
                      ? Image.file(File(firstItem.localPosterPath), width: 50, height: 75, fit: BoxFit.cover)
                      : Container(width: 50, height: 75, color: Colors.grey[900], child: const Icon(Icons.tv, color: Colors.white24)),
                ),
                title: Text(title, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  isActive ? "Downloading episodes..." : "${episodes.length} episodes downloaded",
                  style: TextStyle(color: isActive ? const Color(0xFF8A2BE2) : Colors.white54, fontSize: 12),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF8A2BE2), size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OfflineTvShowDetailScreen(
                      showTitle: title,
                      episodes: episodes,
                      onRefresh: _loadDownloads,
                    ),
                  ),
                ).then((_) => _loadDownloads()),
              ),
            );
          },
        );
      }
    );
  }

  void _playOffline(DownloadItem item) {
    Navigator.push(
      context, 
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          videoUrl: item.localVideoPath, 
          subtitleUrls: item.localSubtitlePaths, 
          title: item.title, 
          serverIp: '', 
          serverPort: '', 
          username: '', 
          password: '', 
          fileSize: 0
        )
      )
    ).then((_) => _loadDownloads());
  }
}

class OfflineTvShowDetailScreen extends StatefulWidget {
  final String showTitle;
  final List<DownloadItem> episodes;
  final VoidCallback onRefresh;

  const OfflineTvShowDetailScreen({super.key, required this.showTitle, required this.episodes, required this.onRefresh});

  @override
  State<OfflineTvShowDetailScreen> createState() => _OfflineTvShowDetailScreenState();
}

class _OfflineTvShowDetailScreenState extends State<OfflineTvShowDetailScreen> {
  late List<DownloadItem> _currentEpisodes;
  String? _selectedSeason;
  StreamSubscription? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _currentEpisodes = List.from(widget.episodes);
    _updateSelectedSeason();
    _progressSubscription = DownloadsManager().progressController.stream.listen((_) {
      _refreshLibrary();
    });
  }

  void _updateSelectedSeason() {
    if (_currentEpisodes.isNotEmpty && _selectedSeason == null) {
      _selectedSeason = _currentEpisodes.first.seasonName ?? "Season 1";
    } else if (_currentEpisodes.isEmpty) {
      final active = DownloadsManager().activeMetadata.values.where((m) => m.showTitle == widget.showTitle).toList();
      if (active.isNotEmpty && _selectedSeason == null) {
        _selectedSeason = active.first.seasonName ?? "Season 1";
      }
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshLibrary() async {
    final items = await DownloadsManager().getDownloads();
    if (mounted) {
      setState(() {
        _currentEpisodes = items.where((i) => i.showTitle == widget.showTitle).toList();
        _updateSelectedSeason();
      });
      widget.onRefresh();
    }
  }

  Future<bool?> _showDeleteConfirmation(BuildContext context, String title) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Confirm Delete", style: TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to delete '$title'?", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  int _extractNumber(String s) {
    final match = RegExp(r'(\d+)').firstMatch(s);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, double>>(
      stream: DownloadsManager().progressController.stream,
      builder: (context, snapshot) {
        final active = snapshot.data ?? {};
        final activeEpisodes = DownloadsManager().activeMetadata.entries
            .where((entry) => entry.value.showTitle == widget.showTitle)
            .toList();

        final List<dynamic> allEpisodes = [..._currentEpisodes];
        for (var entry in activeEpisodes) {
          if (!_currentEpisodes.any((e) => e.localVideoPath == entry.value.localVideoPath)) {
            allEpisodes.add(entry);
          }
        }
        
        Map<String, List<dynamic>> seasons = {};
        for (var ep in allEpisodes) {
          final item = ep is MapEntry<String, DownloadItem> ? ep.value : ep as DownloadItem;
          seasons.putIfAbsent(item.seasonName ?? "Season 1", () => []).add(ep);
        }
        
        final seasonNames = seasons.keys.toList()..sort((a, b) => _extractNumber(a).compareTo(_extractNumber(b)));
        seasons.forEach((key, value) {
          value.sort((a, b) {
            final aItem = a is MapEntry<String, DownloadItem> ? a.value : a as DownloadItem;
            final bItem = b is MapEntry<String, DownloadItem> ? b.value : b as DownloadItem;
            return _extractNumber(aItem.title).compareTo(_extractNumber(bItem.title));
          });
        });

        final posterPath = _currentEpisodes.isNotEmpty ? _currentEpisodes.first.localPosterPath : (activeEpisodes.isNotEmpty ? activeEpisodes.first.value.localPosterPath : "");

        return Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
          body: Stack(
            children: [
              if (posterPath.isNotEmpty && File(posterPath).existsSync())
                Positioned.fill(child: Image.file(File(posterPath), fit: BoxFit.cover)),
              Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(color: Colors.black.withOpacity(0.1)))),
              Column(
                children: [
                  const SizedBox(height: 100),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        ClipRRect(borderRadius: BorderRadius.circular(8), child: posterPath.isNotEmpty && File(posterPath).existsSync() ? Image.file(File(posterPath), height: 150, width: 100, fit: BoxFit.cover) : Container(height: 150, width: 100, color: Colors.grey[900])),
                        const SizedBox(width: 16),
                        Expanded(child: Text(widget.showTitle, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  if (seasonNames.isNotEmpty)
                    Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: seasonNames.length,
                        itemBuilder: (context, index) {
                          final isSelected = _selectedSeason == seasonNames[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ElevatedButton(
                              onPressed: () => setState(() => _selectedSeason = seasonNames[index]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isSelected ? const Color(0xFF8A2BE2) : Colors.grey[800],
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              child: Text(seasonNames[index], style: TextStyle(color: isSelected ? Colors.white : Colors.grey[300])),
                            ),
                          );
                        },
                      ),
                    ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 16 / 9, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      itemCount: seasons[_selectedSeason]?.length ?? 0,
                      itemBuilder: (context, i) {
                        final dynamic entry = seasons[_selectedSeason]![i];
                        final bool isDownloading = entry is MapEntry<String, DownloadItem>;
                        final DownloadItem ep = isDownloading ? entry.value : entry as DownloadItem;
                        final String downloadUrl = isDownloading ? entry.key : "";

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ep.episodeThumbnailPath != null && File(ep.episodeThumbnailPath!).existsSync()
                                  ? Image.file(File(ep.episodeThumbnailPath!), fit: BoxFit.cover)
                                  : Container(color: Colors.grey[900], child: const Icon(Icons.play_circle_fill, color: Colors.white54, size: 40)),
                              if (isDownloading) ...[
                                Container(color: Colors.black54),
                                Center(
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CircularProgressIndicator(value: active[downloadUrl], color: const Color(0xFF8A2BE2)),
                                      IconButton(icon: const Icon(Icons.stop, size: 14, color: Colors.white), onPressed: () => DownloadsManager().stopDownload(downloadUrl)),
                                    ],
                                  ),
                                ),
                              ],
                              if (!isDownloading)
                                Positioned.fill(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => Navigator.push(
                                        context, 
                                        MaterialPageRoute(
                                          builder: (context) => VideoPlayerScreen(
                                            videoUrl: ep.localVideoPath, 
                                            subtitleUrls: ep.localSubtitlePaths, 
                                            title: ep.title, 
                                            serverIp: '', 
                                            serverPort: '', 
                                            username: '', 
                                            password: '', 
                                            fileSize: 0
                                          )
                                        )
                                      ).then((_) => _refreshLibrary()),
                                    ),
                                  ),
                                ),
                              Positioned(
                                bottom: 0, left: 0, right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  color: Colors.black54,
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(ep.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10))),
                                      if (isDownloading) const Text("DL", style: TextStyle(color: Color(0xFF8A2BE2), fontSize: 8, fontWeight: FontWeight.bold))
                                      else if (ep.localSubtitlePaths.isNotEmpty) const Icon(Icons.subtitles, size: 12, color: Colors.white70),
                                    ],
                                  ),
                                ),
                              ),
                              if (!isDownloading)
                                Positioned(
                                  top: 5, right: 5,
                                  child: GestureDetector(
                                    onTap: () async {
                                      final confirm = await _showDeleteConfirmation(context, ep.title);
                                      if (confirm == true) {
                                        await DownloadsManager().deleteDownload(ep);
                                        _refreshLibrary();
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                                      child: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }
    );
  }
}
