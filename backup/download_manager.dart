import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const double kb = 1024;
  const double mb = kb * 1024;
  const double gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
  return '${(bytes / kb).toStringAsFixed(0)} KB';
}

int seasonNumberOf(String name) {
  final m = RegExp(r'(\d+)').firstMatch(name);
  return m == null ? 0 : int.parse(m.group(1)!);
}

int episodeNumberOf(String name) {
  final lower = name.toLowerCase();
  final patterns = [
    RegExp(r'e(\d{1,3})'),
    RegExp(r'ep(?:isode)?[ ._-]*(\d{1,3})'),
    RegExp(r'(\d+)'),
  ];
  for (final r in patterns) {
    final m = r.firstMatch(lower);
    if (m != null) return int.parse(m.group(1)!);
  }
  return 0;
}

enum DlStatus { queued, downloading, paused, completed, failed }

class DownloadItem {
  final String id;
  final String type; // 'movie' | 'episode'
  final String serverPath;
  String title;
  String fileName;
  String? showName;
  String? showPath;
  String? seasonName;
  int seasonNo;
  int episodeNo;
  DlStatus status;
  int received;
  int total;
  String? error;
  String? videoFile;
  String? posterFile;
  String? bannerFile;
  String? thumbFile;
  List<String> sceneFiles;
  List<String> subtitleFiles;
  Map<String, dynamic>? metadata;
  int addedAt;

  DownloadItem({
    required this.id,
    required this.type,
    required this.serverPath,
    required this.title,
    required this.fileName,
    this.showName,
    this.showPath,
    this.seasonName,
    this.seasonNo = 0,
    this.episodeNo = 0,
    this.status = DlStatus.queued,
    this.received = 0,
    this.total = 0,
    this.error,
    this.videoFile,
    this.posterFile,
    this.bannerFile,
    this.thumbFile,
    List<String>? sceneFiles,
    List<String>? subtitleFiles,
    this.metadata,
    int? addedAt,
  })  : sceneFiles = sceneFiles ?? [],
        subtitleFiles = subtitleFiles ?? [],
        addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  bool get isMovie => type == 'movie';
  bool get isActive => status == DlStatus.queued || status == DlStatus.downloading;
  String get folder => '${isMovie ? 'm' : 'e'}_$id';
  double get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'serverPath': serverPath,
        'title': title,
        'fileName': fileName,
        'showName': showName,
        'showPath': showPath,
        'seasonName': seasonName,
        'seasonNo': seasonNo,
        'episodeNo': episodeNo,
        'status': status.name,
        'received': received,
        'total': total,
        'error': error,
        'videoFile': videoFile,
        'posterFile': posterFile,
        'bannerFile': bannerFile,
        'thumbFile': thumbFile,
        'sceneFiles': sceneFiles,
        'subtitleFiles': subtitleFiles,
        'metadata': metadata,
        'addedAt': addedAt,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> j) {
    return DownloadItem(
      id: j['id'] ?? '',
      type: j['type'] ?? 'movie',
      serverPath: j['serverPath'] ?? '',
      title: j['title'] ?? '',
      fileName: j['fileName'] ?? '',
      showName: j['showName'],
      showPath: j['showPath'],
      seasonName: j['seasonName'],
      seasonNo: (j['seasonNo'] ?? 0) as int,
      episodeNo: (j['episodeNo'] ?? 0) as int,
      status: DlStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => DlStatus.paused),
      received: (j['received'] ?? 0) as int,
      total: (j['total'] ?? 0) as int,
      error: j['error'],
      videoFile: j['videoFile'],
      posterFile: j['posterFile'],
      bannerFile: j['bannerFile'],
      thumbFile: j['thumbFile'],
      sceneFiles: List<String>.from(j['sceneFiles'] ?? const []),
      subtitleFiles: List<String>.from(j['subtitleFiles'] ?? const []),
      metadata: j['metadata'] == null ? null : Map<String, dynamic>.from(j['metadata']),
      addedAt: j['addedAt'] as int?,
    );
  }
}

class DownloadShow {
  final String id;
  final String name;
  final String path;
  String? posterFile;
  String? bannerFile;
  Map<String, dynamic>? metadata;

  DownloadShow({
    required this.id,
    required this.name,
    required this.path,
    this.posterFile,
    this.bannerFile,
    this.metadata,
  });

  String get folder => 's_$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'posterFile': posterFile,
        'bannerFile': bannerFile,
        'metadata': metadata,
      };

  factory DownloadShow.fromJson(Map<String, dynamic> j) => DownloadShow(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        path: j['path'] ?? '',
        posterFile: j['posterFile'],
        bannerFile: j['bannerFile'],
        metadata: j['metadata'] == null ? null : Map<String, dynamic>.from(j['metadata']),
      );
}

class _Interrupted implements Exception {}

class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const List<String> _sceneTimes = ['00:10:00', '00:25:00', '00:45:00', '01:05:00', '01:25:00'];

  final Map<String, DownloadItem> _items = {};
  final Map<String, DownloadShow> _shows = {};
  final List<String> _queue = [];
  final Set<String> _pauseRequested = {};
  final Set<String> _removeRequested = {};

  Directory? _root;
  Future<void>? _initFuture;
  String _ip = '';
  String _port = '8080';
  String _auth = '';
  bool _running = false;
  String? _activeId;
  http.Client? _activeClient;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _saveTimer;

  // ---------------------------------------------------------------- setup

  Future<void> ensureInit() => _initFuture ??= _init();

  Future<void> _init() async {
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory(p.join(docs.path, 'palmvibe_downloads'));
    await _root!.create(recursive: true);

    final prefs = await SharedPreferences.getInstance();
    _ip = prefs.getString('dl_server_ip') ?? prefs.getString('server_ip') ?? '';
    _port = prefs.getString('dl_server_port') ?? '8080';
    _auth = prefs.getString('dl_auth') ?? '';
    if (_auth.isEmpty) {
      final u = prefs.getString('username') ?? '';
      final pw = prefs.getString('password') ?? '';
      if (u.isNotEmpty && pw.isNotEmpty) {
        _auth = 'Basic ${base64Encode(utf8.encode('$u:$pw'))}';
      }
    }

    try {
      final f = File(p.join(_root!.path, 'index.json'));
      if (await f.exists()) {
        final data = json.decode(await f.readAsString());
        for (final raw in (data['items'] as List? ?? const [])) {
          final item = DownloadItem.fromJson(Map<String, dynamic>.from(raw));
          if (item.id.isEmpty) continue;
          if (item.status == DlStatus.queued || item.status == DlStatus.downloading) {
            item.status = DlStatus.paused;
          }
          if (item.status != DlStatus.completed && item.videoFile != null) {
            final vf = File(absPath(item.videoFile!));
            if (await vf.exists()) item.received = await vf.length();
          }
          _items[item.id] = item;
        }
        for (final raw in (data['shows'] as List? ?? const [])) {
          final show = DownloadShow.fromJson(Map<String, dynamic>.from(raw));
          if (show.id.isNotEmpty) _shows[show.id] = show;
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  void configure({required String ip, required String port, required String authHeader}) {
    _ip = ip;
    _port = port;
    _auth = authHeader;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('dl_server_ip', ip);
      prefs.setString('dl_server_port', port);
      prefs.setString('dl_auth', authHeader);
    });
  }

  static String idFor(String serverPath) {
    int h1 = 0x811c9dc5;
    int h2 = 0x1b873593;
    for (final unit in serverPath.codeUnits) {
      h1 = ((h1 ^ unit) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 ^ unit) * 0x85ebca6b) & 0xFFFFFFFF;
    }
    return h1.toRadixString(16).padLeft(8, '0') + h2.toRadixString(16).padLeft(8, '0');
  }

  // ---------------------------------------------------------------- queries

  String absPath(String rel) {
    if (_root == null) return rel;
    return p.joinAll([_root!.path, ...rel.split('/')]);
  }

  bool fileExists(String? rel) {
    if (rel == null || _root == null) return false;
    return File(absPath(rel)).existsSync();
  }

  DownloadItem? itemFor(String id) => _items[id];
  List<DownloadItem> get items => _items.values.toList();
  List<DownloadItem> get movies => _items.values.where((i) => i.isMovie).toList();
  Iterable<DownloadItem> itemsForShow(String showPath) => _items.values.where((i) => !i.isMovie && i.showPath == showPath);
  Iterable<DownloadItem> itemsForSeason(String showPath, String season) =>
      itemsForShow(showPath).where((i) => i.seasonName == season);
  DownloadShow? showFor(String showPath) => _shows[idFor(showPath)];

  List<String> get showPaths {
    final set = <String>{};
    for (final i in _items.values) {
      if (!i.isMovie && i.showPath != null) set.add(i.showPath!);
    }
    return set.toList();
  }

  int get totalBytesOnDisk => _items.values.fold(0, (a, b) => a + (b.status == DlStatus.completed ? b.total : b.received));

  // ---------------------------------------------------------------- enqueue

  Future<void> enqueueMovie({required Map<String, dynamic> movie, required String title}) async {
    await ensureInit();
    final serverPath = (movie['path'] ?? '').toString();
    if (serverPath.isEmpty) return;
    final id = idFor(serverPath);
    final existing = _items[id];
    if (existing != null) {
      if (existing.status != DlStatus.completed) resume(id);
      return;
    }
    final ext = _videoExt(serverPath);
    final item = DownloadItem(
      id: id,
      type: 'movie',
      serverPath: serverPath,
      title: title,
      fileName: p.basename(serverPath),
      total: movie['size'] is num ? (movie['size'] as num).toInt() : 0,
    );
    item.videoFile = '${item.folder}/video$ext';
    _items[id] = item;
    _queue.add(id);
    _saveIndexSoon();
    _notifyNow();
    _pump();
  }

  Future<int> enqueueEpisodes({
    required String showName,
    required String showPath,
    required String seasonName,
    required List<Map<String, dynamic>> episodes,
  }) async {
    await ensureInit();
    int added = 0;
    for (final ep in episodes) {
      final serverPath = (ep['path'] ?? '').toString();
      if (serverPath.isEmpty) continue;
      final id = idFor(serverPath);
      final existing = _items[id];
      if (existing != null) {
        if (existing.status != DlStatus.completed) resume(id);
        continue;
      }
      final name = (ep['name'] ?? p.basename(serverPath)).toString();
      final ext = _videoExt(serverPath);
      final item = DownloadItem(
        id: id,
        type: 'episode',
        serverPath: serverPath,
        title: name.split('.').first,
        fileName: name,
        showName: showName,
        showPath: showPath,
        seasonName: seasonName,
        seasonNo: seasonNumberOf(seasonName),
        episodeNo: episodeNumberOf(name),
        total: ep['size'] is num ? (ep['size'] as num).toInt() : 0,
      );
      item.videoFile = '${item.folder}/video$ext';
      _items[id] = item;
      _queue.add(id);
      added++;
    }
    _saveIndexSoon();
    _notifyNow();
    unawaited(_ensureShowAssets(showName, showPath));
    _pump();
    return added;
  }

  // Movie paths are usually folders (the server picks the video inside), so only trust real video extensions.
  String _videoExt(String serverPath) {
    final e = p.extension(serverPath).toLowerCase();
    const known = ['.mp4', '.m4v', '.mov', '.mkv', '.avi', '.wmv', '.flv', '.webm', '.ts'];
    return known.contains(e) ? e : '.mp4';
  }

  // ---------------------------------------------------------------- controls

  void pause(String id) {
    final item = _items[id];
    if (item == null) return;
    if (_activeId == id) {
      _pauseRequested.add(id);
      _activeClient?.close();
    } else if (item.status == DlStatus.queued) {
      _queue.remove(id);
      item.status = DlStatus.paused;
      _saveIndexSoon();
      _notifyNow();
    }
  }

  void resume(String id) {
    final item = _items[id];
    if (item == null) return;
    if (item.status == DlStatus.paused || item.status == DlStatus.failed) {
      item.status = DlStatus.queued;
      item.error = null;
      if (!_queue.contains(id)) _queue.add(id);
      _saveIndexSoon();
      _notifyNow();
      _pump();
    }
  }

  Future<void> remove(String id) async {
    final item = _items[id];
    if (item == null) return;
    _queue.remove(id);
    if (_activeId == id) {
      _removeRequested.add(id);
      _activeClient?.close();
      return; // _process cleans up once the active request stops
    }
    _items.remove(id);
    await _deleteFolder(item.folder);
    await _cleanupShow(item.showPath);
    await _saveIndex();
    _notifyNow();
  }

  Future<void> removeShow(String showPath) async {
    final ids = itemsForShow(showPath).map((i) => i.id).toList();
    for (final id in ids) {
      await remove(id);
    }
  }

  // ---------------------------------------------------------------- queue

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final id = _queue.removeAt(0);
        final item = _items[id];
        if (item == null || item.status == DlStatus.completed) continue;
        await _process(item);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _process(DownloadItem item) async {
    if (_ip.isEmpty || _auth.isEmpty) {
      item.status = DlStatus.failed;
      item.error = 'Not connected to a server';
      _saveIndexSoon();
      _notifyNow();
      return;
    }

    _activeId = item.id;
    item.status = DlStatus.downloading;
    item.error = null;
    _notifyNow();

    try {
      await _fetchAssets(item);
      _throwIfInterrupted(item.id);
      await _downloadVideo(item);
      item.status = DlStatus.completed;
      item.error = null;
    } catch (e) {
      if (_removeRequested.contains(item.id)) {
        // cleaned up below
      } else if (_pauseRequested.contains(item.id)) {
        item.status = DlStatus.paused;
      } else {
        item.status = DlStatus.failed;
        item.error = _friendlyError(e);
      }
    } finally {
      _activeId = null;
      _activeClient = null;
    }

    _pauseRequested.remove(item.id);
    if (_removeRequested.remove(item.id)) {
      _items.remove(item.id);
      await _deleteFolder(item.folder);
      await _cleanupShow(item.showPath);
    }
    await _saveIndex();
    _notifyNow();
  }

  void _throwIfInterrupted(String id) {
    if (_pauseRequested.contains(id) || _removeRequested.contains(id)) throw _Interrupted();
  }

  String _friendlyError(Object e) {
    if (e is TimeoutException) return 'Connection timed out';
    if (e is SocketException) return 'Cannot reach server';
    if (e is FileSystemException) return 'Storage error (is the disk full?)';
    if (e is http.ClientException) return 'Connection lost';
    final s = e.toString().replaceFirst('Exception: ', '');
    return s.length > 80 ? s.substring(0, 80) : s;
  }

  // ---------------------------------------------------------------- network

  String get _base => 'http://$_ip:$_port';
  String get _rawAuth => _auth.startsWith('Basic ') ? _auth.substring(6) : _auth;
  Map<String, String> get _headers => {'Authorization': _auth, 'ngrok-skip-browser-warning': 'true'};
  Uri _api(String endpoint, Map<String, String> query) =>
      Uri.parse('$_base/api/$endpoint').replace(queryParameters: query);

  Future<bool> _saveFile(Uri uri, String rel, {int minBytes = 100, bool image = false}) async {
    try {
      final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 45));
      if (r.statusCode != 200 || r.bodyBytes.length < minBytes) return false;
      if (image) {
        final ct = r.headers['content-type'] ?? '';
        if (ct.isNotEmpty && !ct.startsWith('image/')) return false;
      }
      final f = File(absPath(rel));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(r.bodyBytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _getAssets(String serverPath) async {
    try {
      final r = await http.get(_api('movie-assets', {'path': serverPath}), headers: _headers).timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) {
        final data = json.decode(r.body);
        if (data is Map) return Map<String, dynamic>.from(data);
      }
    } catch (_) {}
    return null;
  }

  String _safeName(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');

  Future<void> _fetchAssets(DownloadItem item) async {
    if (item.isMovie) {
      await _fetchMovieAssets(item);
    } else {
      if (item.thumbFile == null) {
        final rel = '${item.folder}/thumb.jpg';
        final ok = await _saveFile(_api('thumbnail', {'path': item.serverPath, 'auth': _rawAuth}), rel, image: true);
        if (ok) item.thumbFile = rel;
      }
    }
    _throwIfInterrupted(item.id);
    await _fetchSubtitles(item);
    _saveIndexSoon();
    _notifyNow();
  }

  Future<void> _fetchMovieAssets(DownloadItem item) async {
    if (item.posterFile == null) {
      final rel = '${item.folder}/poster.jpg';
      if (await _saveFile(_api('poster', {'path': item.serverPath}), rel, image: true)) item.posterFile = rel;
      _notifyNow();
    }
    _throwIfInterrupted(item.id);

    if (item.metadata == null) {
      final data = await _getAssets(item.serverPath);
      if (data != null) {
        final md = data['metadata'];
        if (md is Map) item.metadata = Map<String, dynamic>.from(md);
        final banner = data['banner']?.toString();
        if (banner != null && banner.isNotEmpty && item.bannerFile == null) {
          final rel = '${item.folder}/banner.jpg';
          if (await _saveFile(_api('poster', {'path': banner}), rel, image: true)) item.bannerFile = rel;
        }
        try {
          final f = File(absPath('${item.folder}/metadata.json'));
          await f.parent.create(recursive: true);
          await f.writeAsString(json.encode(data));
        } catch (_) {}
      }
    }
    _throwIfInterrupted(item.id);

    if (item.sceneFiles.isEmpty) {
      // Sequential on purpose: the server names ffmpeg temp files by Date.now(), so parallel requests can collide.
      final found = <String>[];
      for (int i = 0; i < _sceneTimes.length; i++) {
        _throwIfInterrupted(item.id);
        final rel = '${item.folder}/scene_$i.jpg';
        final ok = await _saveFile(
          _api('thumbnail', {'path': item.serverPath, 'time': _sceneTimes[i], 'auth': _rawAuth}),
          rel,
          image: true,
        );
        if (ok) found.add(rel);
      }
      item.sceneFiles = found;
    }
  }

  Future<void> _fetchSubtitles(DownloadItem item) async {
    if (item.subtitleFiles.isNotEmpty) return;
    try {
      final r = await http.get(_api('find-subtitles', {'path': item.serverPath}), headers: _headers).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return;
      final data = json.decode(r.body);
      if (data is! Map || data['success'] != true || data['subtitles'] is! List) return;
      int i = 0;
      for (final sub in data['subtitles']) {
        final subPath = sub is Map ? sub['path']?.toString() : null;
        if (subPath == null || subPath.isEmpty) continue;
        final rel = '${item.folder}/sub_${i}_${_safeName(p.basename(subPath))}';
        if (await _saveFile(_api('subtitle', {'path': subPath}), rel, minBytes: 1)) {
          item.subtitleFiles.add(rel);
          i++;
        }
      }
    } catch (_) {}
  }

  Future<void> _ensureShowAssets(String showName, String showPath) async {
    if (_ip.isEmpty) return;
    final sid = idFor(showPath);
    final show = _shows.putIfAbsent(sid, () => DownloadShow(id: sid, name: showName, path: showPath));
    try {
      if (show.posterFile == null) {
        final rel = '${show.folder}/poster.jpg';
        if (await _saveFile(_api('poster', {'path': showPath}), rel, image: true)) show.posterFile = rel;
      }
      if (show.metadata == null) {
        final data = await _getAssets(showPath);
        if (data != null) {
          final md = data['metadata'];
          if (md is Map) show.metadata = Map<String, dynamic>.from(md);
          final banner = data['banner']?.toString();
          if (banner != null && banner.isNotEmpty && show.bannerFile == null) {
            final rel = '${show.folder}/banner.jpg';
            if (await _saveFile(_api('poster', {'path': banner}), rel, image: true)) show.bannerFile = rel;
          }
          try {
            final f = File(absPath('${show.folder}/metadata.json'));
            await f.parent.create(recursive: true);
            await f.writeAsString(json.encode(data));
          } catch (_) {}
        }
      }
    } catch (_) {}
    _saveIndexSoon();
    _notifyNow();
  }

  Future<void> _downloadVideo(DownloadItem item) async {
    final file = File(absPath(item.videoFile!));
    await file.parent.create(recursive: true);
    int existing = await file.exists() ? await file.length() : 0;
    if (item.total > 0 && existing >= item.total && item.status != DlStatus.failed) {
      item.received = existing;
      return;
    }

    final client = http.Client();
    _activeClient = client;
    IOSink? sink;
    try {
      final uri = Uri.parse('$_base/api/stream').replace(queryParameters: {'path': item.serverPath, 'auth': _rawAuth});
      final req = http.Request('GET', uri);
      req.headers.addAll(_headers);
      if (existing > 0) req.headers['Range'] = 'bytes=$existing-';
      final resp = await client.send(req).timeout(const Duration(seconds: 45));
      _throwIfInterrupted(item.id);

      if (resp.statusCode == 416) {
        item.received = existing;
        if (item.total <= 0) item.total = existing;
        return;
      }
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw Exception('Server returned ${resp.statusCode}');
      }

      bool append = false;
      int? headerTotal;
      if (resp.statusCode == 206 && existing > 0) {
        append = true;
        final cr = resp.headers['content-range'];
        final m = cr == null ? null : RegExp(r'/(\d+)$').firstMatch(cr);
        if (m != null) {
          headerTotal = int.parse(m.group(1)!);
        } else if (resp.contentLength != null) {
          headerTotal = existing + resp.contentLength!;
        }
      } else {
        existing = 0;
        if (resp.contentLength != null && resp.contentLength! > 0) headerTotal = resp.contentLength;
      }
      if (headerTotal != null && headerTotal > 0) item.total = headerTotal;
      item.received = existing;

      sink = file.openWrite(mode: append ? FileMode.append : FileMode.write);
      int sinceFlush = 0;
      await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        item.received += chunk.length;
        sinceFlush += chunk.length;
        if (sinceFlush >= 4 * 1024 * 1024) {
          sinceFlush = 0;
          await sink.flush();
        }
        _notifyThrottled();
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (headerTotal != null && headerTotal > 0 && item.received < headerTotal) {
        throw Exception('Connection lost');
      }
      item.total = item.received;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
      if (identical(_activeClient, client)) _activeClient = null;
    }
  }

  // ---------------------------------------------------------------- storage

  Future<void> _deleteFolder(String folder) async {
    try {
      final d = Directory(absPath(folder));
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _cleanupShow(String? showPath) async {
    if (showPath == null) return;
    if (itemsForShow(showPath).isNotEmpty) return;
    final sid = idFor(showPath);
    final show = _shows.remove(sid);
    if (show != null) await _deleteFolder(show.folder);
  }

  void _saveIndexSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () => _saveIndex());
  }

  Future<void> _saveIndex() async {
    if (_root == null) return;
    try {
      final data = {
        'items': _items.values.map((e) => e.toJson()).toList(),
        'shows': _shows.values.map((e) => e.toJson()).toList(),
      };
      final tmp = File(p.join(_root!.path, 'index.json.tmp'));
      await tmp.writeAsString(json.encode(data), flush: true);
      await tmp.rename(p.join(_root!.path, 'index.json'));
    } catch (_) {}
  }

  void _notifyNow() {
    _lastNotify = DateTime.now();
    notifyListeners();
  }

  void _notifyThrottled() {
    if (DateTime.now().difference(_lastNotify).inMilliseconds < 300) return;
    _notifyNow();
  }
}

// ====================================================================
// Widgets
// ====================================================================

Future<bool> confirmDialog(BuildContext context, String title, String message, {String confirm = 'DELETE'}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Text(message, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCEL', style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          onPressed: () => Navigator.pop(c, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return res ?? false;
}

class DownloadButton extends StatefulWidget {
  final String id;
  final Future<void> Function() onDownload;
  final double size;

  const DownloadButton({Key? key, required this.id, required this.onDownload, this.size = 32}) : super(key: key);

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  final DownloadManager _m = DownloadManager.instance;

  @override
  void initState() {
    super.initState();
    _m.addListener(_refresh);
    _m.ensureInit();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _m.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _onTap(DownloadItem? item) async {
    if (item == null) {
      try {
        await widget.onDownload();
      } catch (_) {}
      return;
    }
    switch (item.status) {
      case DlStatus.queued:
      case DlStatus.downloading:
        _m.pause(item.id);
        break;
      case DlStatus.paused:
      case DlStatus.failed:
        _m.resume(item.id);
        break;
      case DlStatus.completed:
        final yes = await confirmDialog(context, 'Remove download?', 'Delete "${item.title}" from this device?');
        if (yes) await _m.remove(item.id);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _m.itemFor(widget.id);
    final s = widget.size;
    Widget inner;

    if (item == null) {
      inner = Icon(Icons.download_rounded, color: Colors.white, size: s * 0.58);
    } else {
      switch (item.status) {
        case DlStatus.completed:
          inner = Icon(Icons.check_rounded, color: const Color(0xFFB19CD9), size: s * 0.65);
          break;
        case DlStatus.failed:
          inner = Icon(Icons.refresh_rounded, color: Colors.redAccent, size: s * 0.6);
          break;
        case DlStatus.paused:
          inner = Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: s - 8,
              height: s - 8,
              child: CircularProgressIndicator(
                value: item.total > 0 ? item.progress : 0,
                strokeWidth: 2.5,
                color: const Color(0xFF8A2BE2),
                backgroundColor: Colors.white24,
              ),
            ),
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: s * 0.45),
          ]);
          break;
        case DlStatus.queued:
        case DlStatus.downloading:
          inner = Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: s - 8,
              height: s - 8,
              child: CircularProgressIndicator(
                value: (item.status == DlStatus.downloading && item.total > 0) ? item.progress : null,
                strokeWidth: 2.5,
                color: const Color(0xFF8A2BE2),
                backgroundColor: Colors.white24,
              ),
            ),
            Icon(Icons.pause_rounded, color: Colors.white, size: s * 0.42),
          ]);
          break;
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTap(item),
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Center(child: inner),
      ),
    );
  }
}

class DownloadGroupButton extends StatefulWidget {
  final Iterable<DownloadItem> Function(DownloadManager m) selector;
  final int? expected;
  final Future<void> Function() onDownload;
  final String tooltip;
  final double size;

  const DownloadGroupButton({
    Key? key,
    required this.selector,
    required this.onDownload,
    this.expected,
    this.tooltip = 'Download',
    this.size = 28,
  }) : super(key: key);

  @override
  State<DownloadGroupButton> createState() => _DownloadGroupButtonState();
}

class _DownloadGroupButtonState extends State<DownloadGroupButton> {
  final DownloadManager _m = DownloadManager.instance;

  @override
  void initState() {
    super.initState();
    _m.addListener(_refresh);
    _m.ensureInit();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _m.removeListener(_refresh);
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.selector(_m).toList();
    final active = list.any((i) => i.isActive);
    final completed = list.where((i) => i.status == DlStatus.completed).length;
    final done = widget.expected != null && widget.expected! > 0 && completed >= widget.expected!;
    final s = widget.size;

    Widget icon;
    if (done) {
      icon = Icon(Icons.download_done_rounded, color: const Color(0xFFB19CD9), size: s);
    } else if (active) {
      final rec = list.fold<int>(0, (a, b) => a + b.received);
      final tot = list.fold<int>(0, (a, b) => a + b.total);
      icon = SizedBox(
        width: s - 4,
        height: s - 4,
        child: CircularProgressIndicator(
          value: tot > 0 ? (rec / tot).clamp(0.0, 1.0) : null,
          strokeWidth: 2.5,
          color: const Color(0xFF8A2BE2),
          backgroundColor: Colors.white24,
        ),
      );
    } else {
      icon = Icon(Icons.download_rounded, color: Colors.white, size: s);
    }

    return IconButton(
      tooltip: widget.tooltip,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: s + 14, minHeight: s + 14),
      icon: icon,
      onPressed: () async {
        if (done) {
          _snack('Already downloaded');
        } else if (active) {
          _snack('Download in progress — see the Downloads screen');
        } else {
          try {
            await widget.onDownload();
          } catch (_) {
            if (mounted) _snack('Could not start download');
          }
        }
      },
    );
  }
}
