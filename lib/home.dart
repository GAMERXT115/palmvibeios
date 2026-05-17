import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'login.dart';
import 'video_player.dart';
import 'downloads.dart';

class HomeScreen extends StatefulWidget {
  final String serverIp;
  final String serverPort;
  final String username;
  final String password;

  const HomeScreen({
    super.key,
    required this.serverIp,
    required this.serverPort,
    required this.username,
    required this.password,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final List<String> _categories = ['Bollywood', 'Hollywood'];
  String _currentCategory = 'Bollywood';
  List<Map<String, dynamic>> _tvShows = [];
  List<Map<String, dynamic>> _movies = [];
  List<Map<String, dynamic>> _recentlyAddedMovies = [];
  List<String> _currentPath = [];
  bool _isLoading = true;
  String _error = '';
  bool _userInteracting = false;
  Set<String> _downloadedPaths = {};
  StreamSubscription? _downloadSubscription;
  
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  
  int _currentPage = 0;
  final int _itemsPerPage = 24;
  int _totalPages = 0;
  
  bool _isInTvShowDetail = false;
  Map<String, dynamic>? _selectedTvShow;
  List<Map<String, dynamic>> _seasons = [];
  String? _selectedSeason;
  List<Map<String, dynamic>> _episodes = [];
  List<Map<String, dynamic>> _allVideoFiles = [];
  
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _tvShowsScrollController = ScrollController();
  final ScrollController _seasonsScrollController = ScrollController();
  
  bool _namesLoaded = false;
  Set<int> _pagesWithLoadingStarted = {0};
  
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _refreshData();
    _downloadSubscription = DownloadsManager().progressController.stream.listen((_) {
      _loadDownloadedPaths();
    });
    _searchController.addListener(() {
      if (_searchController.text.isEmpty && _isSearching) {
        setState(() {
          _isSearching = false;
          _searchResults = [];
        });
      }
    });
    _mainScrollController.addListener(_checkScrollPosition);
  }

  Future<void> _refreshData() async {
    await _loadDownloadedPaths();
    await _loadFiles();
  }

  Future<void> _loadDownloadedPaths() async {
    final downloads = await DownloadsManager().getDownloads();
    if (mounted) {
      setState(() {
        _downloadedPaths = downloads.map((e) => e.title.replaceAll(RegExp(r'[^\w\s]+'), '')).toSet();
      });
    }
  }
  
  void _checkScrollPosition() {
    if (_mainScrollController.position.pixels > 300 && !_pagesWithLoadingStarted.contains(1)) {
      setState(() => _pagesWithLoadingStarted.add(1));
    }
    if (_mainScrollController.position.pixels > 800 && !_pagesWithLoadingStarted.contains(2)) {
      setState(() => _pagesWithLoadingStarted.add(2));
    }
  }

  String get _baseUrl => 'http://${widget.serverIp}:${widget.serverPort}';

  String get _authHeader {
    if (widget.username.length > 100) {
      return 'Bearer ${widget.username}';
    } else if (widget.username.isNotEmpty && widget.password.isNotEmpty) {
      return 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
    }
    return '';
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        setState(() {
          _error = 'No internet connection';
          _isLoading = false;
        });
        return;
      }

      final queryParams = {
        'category': _currentCategory,
        'path': _currentPath.isEmpty ? '' : path.joinAll(_currentPath),
      };

      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: queryParams);
      final headers = <String, String>{};
      if (_authHeader.isNotEmpty) headers['Authorization'] = _authHeader;
      
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final files = List<Map<String, dynamic>>.from(data['files']);
          final directories = files.where((file) => file['type'] == 'directory').toList();
          final videoFiles = files.where((file) => file['type'] == 'file' && _isVideoFile(file['name'])).toList();
          
          if (_currentPath.isEmpty) {
            _processRootContent(directories, videoFiles);
          } else if (_isInTvShowDetail) {
            _processSeasons(directories, videoFiles);
          } else {
            setState(() {
              _isLoading = false;
              _namesLoaded = true;
            });
          }
        }
      } else if (response.statusCode == 401) {
        setState(() {
          _error = 'Authentication failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _processSeasons(List<Map<String, dynamic>> directories, List<Map<String, dynamic>> videoFiles) {
    final seasonFolders = directories.where((dir) => 
      dir['name'].toLowerCase().contains('season') || 
      RegExp(r's[0-9]+').hasMatch(dir['name'].toLowerCase())
    ).toList();
    
    if (seasonFolders.isNotEmpty) {
      seasonFolders.sort((a, b) => a['name'].compareTo(b['name']));
      setState(() {
        _seasons = seasonFolders;
        _episodes = videoFiles;
        if (_selectedSeason == null && _seasons.isNotEmpty) {
          _selectedSeason = _seasons.first['name'];
        }
        _isLoading = false;
        _namesLoaded = true;
      });
      if (_selectedSeason != null) _loadSeasonEpisodes(_selectedSeason!);
    } else {
      setState(() {
        _seasons = [];
        _episodes = videoFiles;
        _isLoading = false;
        _namesLoaded = true;
      });
    }
  }

  Future<void> _loadSeasonEpisodes(String seasonName) async {
    setState(() {
      _isLoading = true;
      _selectedSeason = seasonName;
    });
    try {
      final seasonFolder = _seasons.firstWhere((season) => season['name'] == seasonName);
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory,
        'path': seasonFolder['path'],
      });
      final headers = <String, String>{};
      if (_authHeader.isNotEmpty) headers['Authorization'] = _authHeader;
      
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final files = List<Map<String, dynamic>>.from(data['files']);
          final episodeFiles = files.where((file) => file['type'] == 'file' && _isVideoFile(file['name'])).toList();
          episodeFiles.sort((a, b) => a['name'].compareTo(b['name']));
          setState(() {
            _episodes = episodeFiles;
            _isLoading = false;
            _namesLoaded = true;
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _namesLoaded = true;
      });
    }
  }

  Future<void> _processRootContent(List<Map<String, dynamic>> directories, List<Map<String, dynamic>> videoFiles) async {
    _tvShows = [];
    _movies = [];
    _recentlyAddedMovies = [];
    _allVideoFiles = [];
    
    Map<String, dynamic>? moviesFolder;
    Map<String, dynamic>? tvShowsFolder;
    
    for (var dir in directories) {
      if (dir['name'] == 'TV Shows') tvShowsFolder = dir;
      else if (dir['name'] == 'Movies') moviesFolder = dir;
    }

    setState(() {
      _namesLoaded = true;
      _isLoading = false;
    });

    if (tvShowsFolder != null) await _loadTvShows(tvShowsFolder['path']);
    if (moviesFolder != null) await _checkMoviesFolderStructure(moviesFolder['path']);
    
    final movieDirs = directories.where((dir) => dir['name'] != 'TV Shows' && dir['name'] != 'Movies').toList();
    _allVideoFiles.addAll(videoFiles);
    for (var dir in movieDirs) await _extractVideosFromDirectory(dir);
    
    List<Map<String, dynamic>> recentlyAddedMoviesList = [];
    for (var movie in _recentlyAddedMovies) {
      if (movie['type'] == 'file') {
        final movieWithFlag = Map<String, dynamic>.from(movie);
        movieWithFlag['isRecentlyAdded'] = true;
        recentlyAddedMoviesList.add(movieWithFlag);
      }
    }
    
    final regularMovies = _allVideoFiles.where((movie) => 
      !recentlyAddedMoviesList.any((recent) => recent['path'] == movie['path'])
    ).toList();
    
    _movies = [...recentlyAddedMoviesList, ...regularMovies];
    _totalPages = (_movies.length / _itemsPerPage).ceil();
    if (mounted) setState(() {});
  }

  Future<void> _checkMoviesFolderStructure(String moviesPath) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory,
        'path': moviesPath,
      });
      final headers = <String, String>{};
      if (_authHeader.isNotEmpty) headers['Authorization'] = _authHeader;
      
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final folders = List<Map<String, dynamic>>.from(data['files']);
          final directories = folders.where((file) => file['type'] == 'directory').toList();
          final recentlyAddedFolder = directories.firstWhere((f) => f['name'] == '1RECENTLY ADDED', orElse: () => {});
          
          if (recentlyAddedFolder.isNotEmpty) await _loadRecentlyAddedMovies(recentlyAddedFolder['path']);
          final movieDirs = directories.where((dir) => dir['name'] != '1RECENTLY ADDED').toList();
          for (var dir in movieDirs) await _extractVideosFromDirectory(dir);
        }
      }
    } catch (e) {}
  }

  Future<void> _loadTvShows(String tvShowsPath) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory,
        'path': tvShowsPath,
      });
      final headers = <String, String>{};
      if (_authHeader.isNotEmpty) headers['Authorization'] = _authHeader;
      
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final tvShows = List<Map<String, dynamic>>.from(data['files']);
          if (mounted) setState(() => _tvShows = tvShows.where((show) => show['type'] == 'directory').toList());
        }
      }
    } catch (e) {}
  }
  
  Future<void> _loadRecentlyAddedMovies(String recentlyAddedPath) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory,
        'path': recentlyAddedPath,
      });
      final headers = <String, String>{};
      if (_authHeader.isNotEmpty) headers['Authorization'] = _authHeader;
      
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final folders = List<Map<String, dynamic>>.from(data['files']);
          final directoryItems = folders.where((item) => item['type'] == 'directory').toList();
          final videoFiles = folders.where((item) => item['type'] == 'file' && _isVideoFile(item['name'])).toList();
          List<Map<String, dynamic>> recentMovies = [];
          recentMovies.addAll(videoFiles);
          
          for (var dir in directoryItems) {
            final contents = await _getDirectoryContents(dir['path']);
            final dirVideoFiles = contents.where((file) => file['type'] == 'file' && _isVideoFile(file['name'])).toList();
            for (var video in dirVideoFiles) {
              final videoWithContext = Map<String, dynamic>.from(video);
              videoWithContext['folderName'] = dir['name'];
              videoWithContext['folderPath'] = dir['path'];
              recentMovies.add(videoWithContext);
            }
            if (dirVideoFiles.isEmpty) recentMovies.add(dir);
          }
          if (mounted) {
            setState(() {
              _recentlyAddedMovies = recentMovies;
              _recentlyAddedMovies.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
            });
          }
        }
      }
    } catch (e) {}
  }
  
  Future<void> _extractVideosFromDirectory(Map<String, dynamic> directory) async {
    try {
      final contents = await _getDirectoryContents(directory['path']);
      final videoFiles = contents.where((file) => file['type'] == 'file' && _isVideoFile(file['name'])).toList();
      for (var videoFile in videoFiles) {
        final videoWithContext = Map<String, dynamic>.from(videoFile);
        videoWithContext['folderName'] = directory['name'];
        videoWithContext['folderPath'] = directory['path'];
        _allVideoFiles.add(videoWithContext);
      }
      final subdirectories = contents.where((file) => file['type'] == 'directory').toList();
      for (var subdir in subdirectories) await _extractVideosFromDirectory(subdir);
      if (mounted) setState(() => _movies = _allVideoFiles);
    } catch (e) {}
  }
  
  Future<List<Map<String, dynamic>>> _getDirectoryContents(String dirPath) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory,
        'path': dirPath,
      });
      final headers = <String, String>{};
      if (_authHeader.isNotEmpty) headers['Authorization'] = _authHeader;
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return List<Map<String, dynamic>>.from(data['files']);
      }
      return [];
    } catch (e) { return []; }
  }

  void _navigateToFolder(String folderName) {
    setState(() {
      _currentPath.add(folderName);
      _namesLoaded = false;
    });
    _loadFiles();
  }

  void _navigateUp() {
    if (_isInTvShowDetail) {
      setState(() {
        _isInTvShowDetail = false;
        _selectedTvShow = null;
        _seasons = [];
        _episodes = [];
        _selectedSeason = null;
        _namesLoaded = false;
      });
      if (_currentPath.isNotEmpty) setState(() => _currentPath.removeLast());
      _loadFiles();
    } else if (_currentPath.isNotEmpty) {
      setState(() {
        _currentPath.removeLast();
        _namesLoaded = false;
      });
      _loadFiles();
    }
  }

  void _changeCategory(String category) {
    setState(() {
      _currentCategory = category;
      _currentPath = [];
      _isInTvShowDetail = false;
      _isSearching = false;
      _currentPage = 0;
      _namesLoaded = false;
      _pagesWithLoadingStarted = {0};
    });
    _loadFiles();
  }

  void _showTvShowDetail(Map<String, dynamic> tvShow) {
    setState(() {
      _isInTvShowDetail = true;
      _selectedTvShow = tvShow;
      _currentPath = [tvShow['path']];
      _seasons = [];
      _episodes = [];
      _selectedSeason = null;
      _namesLoaded = false;
    });
    _loadFiles();
  }

  void _search(String query) {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }
    final queryLower = query.toLowerCase();
    final matchingTvShows = _tvShows.where((show) => show['name'].toString().toLowerCase().contains(queryLower)).toList();
    final matchingMovies = _movies.where((movie) => 
      movie['name'].toString().toLowerCase().contains(queryLower) ||
      (movie['folderName'] != null && movie['folderName'].toString().toLowerCase().contains(queryLower))
    ).toList();
    
    setState(() {
      _isSearching = true;
      _searchResults = [...matchingTvShows, ...matchingMovies];
      _currentPage = 0;
      _totalPages = (_searchResults.length / _itemsPerPage).ceil();
      _pagesWithLoadingStarted = {0};
      _namesLoaded = true;
    });
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      setState(() {
        _currentPage++;
        _pagesWithLoadingStarted.add(_currentPage);
      });
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
        _pagesWithLoadingStarted.add(_currentPage);
      });
    }
  }

  bool _isVideoFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return ['.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm', '.m4v', '.3gp', '.ts'].contains(ext);
  }

  String _getPosterUrl(Map<String, dynamic> item) {
    String p = item['folderPath'] ?? (item['type'] == 'directory' ? item['path'] : path.dirname(item['path']));
    return '$_baseUrl/api/poster?path=${Uri.encodeComponent(p)}';
  }

  void _playVideo(Map<String, dynamic> file) async {
    final String videoName = file['name'];
    final String videoPath = file['path'];
    final String streamUrl = '$_baseUrl/api/stream?path=${Uri.encodeComponent(videoPath)}';
    List<String> subtitleUrls = [];
    try {
      final uri = Uri.parse('$_baseUrl/api/find-subtitles').replace(queryParameters: {'path': videoPath, 'videoName': videoName});
      final headers = <String, String>{};
      if (_authHeader.isNotEmpty) headers['Authorization'] = _authHeader;
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['subtitles'] != null) {
          subtitleUrls = List<Map<String, dynamic>>.from(data['subtitles']).map((s) => '$_baseUrl/api/subtitle?path=${Uri.encodeComponent(s['path'])}').toList();
        }
      }
    } catch (e) {}

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          videoUrl: streamUrl,
          subtitleUrls: subtitleUrls,
          title: videoName,
          serverIp: widget.serverIp,
          serverPort: widget.serverPort,
          username: widget.username,
          password: widget.password,
          fileSize: file['size'] ?? 0,
        ),
      ),
    );
  }

  Widget _buildShimmerEffect() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              colors: [Colors.grey.shade900, Colors.grey.shade800, Colors.grey.shade700, Colors.grey.shade800, Colors.grey.shade900],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
              begin: const Alignment(-1.0, -0.5),
              end: const Alignment(1.0, 0.5),
              transform: GradientRotation(_shimmerController.value * 2 * math.pi),
            ),
          ),
        );
      },
    );
  }

  String _formatFileSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<List<String>> _getSubtitleUrls(String videoPath, String videoName) async {
    List<String> subtitleUrls = [];
    try {
      final uri = Uri.parse('$_baseUrl/api/find-subtitles').replace(queryParameters: {'path': videoPath, 'videoName': videoName});
      final headers = <String, String>{};
      if (_authHeader.isNotEmpty) headers['Authorization'] = _authHeader;
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['subtitles'] != null) {
          subtitleUrls = List<Map<String, dynamic>>.from(data['subtitles']).map((s) => '$_baseUrl/api/subtitle?path=${Uri.encodeComponent(s['path'])}').toList();
        }
      }
    } catch (e) {}
    return subtitleUrls;
  }

  void _downloadMovie(Map<String, dynamic> movie, String posterUrl) async {
    final title = movie['folderName'] ?? path.basenameWithoutExtension(movie['name']);
    final subs = await _getSubtitleUrls(movie['path'], movie['name']);
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading $title'), backgroundColor: Colors.purple.shade900));
    
    final downloadsManager = DownloadsManager();
    downloadsManager.startDownload(
      videoUrl: '$_baseUrl/api/stream?path=${Uri.encodeComponent(movie['path'])}',
      title: title,
      posterUrl: posterUrl,
      subtitleUrls: subs,
      authHeader: _authHeader,
      onNotify: (m) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.purple.shade900));
        _loadDownloadedPaths();
      },
    );
  }

  void _downloadEpisode(Map<String, dynamic> ep, String showTitle, String seasonName, String showPosterUrl) async {
    final subs = await _getSubtitleUrls(ep['path'], ep['name']);
    final thumbUrl = '$_baseUrl/api/thumbnail?path=${Uri.encodeComponent(ep['path'])}';
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading ${ep['name']}'), backgroundColor: Colors.purple.shade900));
    
    final downloadsManager = DownloadsManager();
    downloadsManager.startDownload(
      videoUrl: '$_baseUrl/api/stream?path=${Uri.encodeComponent(ep['path'])}',
      title: ep['name'],
      posterUrl: showPosterUrl,
      subtitleUrls: subs,
      authHeader: _authHeader,
      showTitle: showTitle,
      seasonName: seasonName,
      episodeThumbnailUrl: thumbUrl,
      onNotify: (m) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.purple.shade900));
        _loadDownloadedPaths();
      },
    );
  }

  void _downloadSeason(String seasonName, List<Map<String, dynamic>> episodes, String showTitle, String showPosterUrl) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Starting season download: $seasonName'), backgroundColor: Colors.purple.shade900));
    for (var ep in episodes) {
      final isDownloaded = _downloadedPaths.any((p) => p.contains(ep['name'].replaceAll(RegExp(r'[^\w\s]+'), '')));
      if (!isDownloaded) {
        _downloadEpisode(ep, showTitle, seasonName, showPosterUrl);
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        title: Text(_isInTvShowDetail ? (_selectedTvShow?['name'] ?? 'TV Show') : (_currentPath.isEmpty ? 'Palm Vibe' : path.basename(_currentPath.last))),
        leading: (_currentPath.isEmpty && !_isInTvShowDetail) ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _navigateUp),
        actions: [
          if (_currentPath.isEmpty && !_isInTvShowDetail) ...[
            IconButton(icon: const Icon(Icons.file_download), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DownloadsScreen())).then((_) => _loadDownloadedPaths())),
            IconButton(icon: const Icon(Icons.search), onPressed: _showSearchDialog),
          ],
          PopupMenuButton<String>(
            onSelected: _changeCategory,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Text(_currentCategory), const Icon(Icons.arrow_drop_down)])),
            itemBuilder: (context) => _categories.map((c) => PopupMenuItem(value: c, child: Text(c))).toList(),
          ),
          IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()))),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _isLoading && !_namesLoaded 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF8A2BE2))) 
          : _error.isNotEmpty 
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(_error, style: const TextStyle(color: Color(0xFF8A2BE2))), const SizedBox(height: 20), ElevatedButton(onPressed: _loadFiles, child: const Text('Retry'))])) 
            : _buildContent(),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Search', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          onSubmitted: (v) { _search(v); Navigator.pop(context); },
        ),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
          TextButton(child: const Text('Search'), onPressed: () { _search(_searchController.text); Navigator.pop(context); }),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isInTvShowDetail) {
      return TvShowDetailWidget(
        selectedTvShow: _selectedTvShow,
        seasons: _seasons,
        episodes: _episodes,
        selectedSeason: _selectedSeason,
        loadSeasonEpisodes: _loadSeasonEpisodes,
        getPosterUrl: _getPosterUrl,
        authHeader: _authHeader,
        buildShimmerEffect: _buildShimmerEffect,
        formatFileSize: _formatFileSize,
        seasonsScrollController: _seasonsScrollController,
        serverIp: widget.serverIp,
        serverPort: widget.serverPort,
        username: widget.username,
        password: widget.password,
        playVideo: _playVideo,
        onDownloadEpisode: (ep) => _downloadEpisode(ep, _selectedTvShow!['name'], _selectedSeason!, _getPosterUrl(_selectedTvShow!)),
        onDownloadSeason: () => _downloadSeason(_selectedSeason!, _episodes, _selectedTvShow!['name'], _getPosterUrl(_selectedTvShow!)),
        downloadedPaths: _downloadedPaths,
        baseUrl: _baseUrl,
      );
    } else if (_currentPath.isEmpty) {
      return _isSearching ? _buildSearchResults() : _buildHomeScreen();
    } else {
      return _buildFolderContent();
    }
  }

  Widget _buildHomeScreen() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        controller: _mainScrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_recentlyAddedMovies.isNotEmpty)
              HomeCarousel(
                recentlyAddedMovies: _recentlyAddedMovies,
                getPosterUrl: _getPosterUrl,
                authHeader: _authHeader,
                buildShimmerEffect: _buildShimmerEffect,
                playVideo: _playVideo,
                navigateToFolder: _navigateToFolder,
                onUserInteractionStart: () => setState(() => _userInteracting = true),
                onUserInteractionEnd: () => setState(() => _userInteracting = false),
              ),
            if (_tvShows.isNotEmpty)
              TvShowsWidget(
                tvShows: _tvShows,
                scrollController: _tvShowsScrollController,
                getPosterUrl: _getPosterUrl,
                authHeader: _authHeader,
                buildShimmerEffect: _buildShimmerEffect,
                onTvShowSelected: _showTvShowDetail,
              ),
            if (_movies.isNotEmpty)
              MoviesGridWidget(
                movies: _movies,
                currentPage: _currentPage,
                itemsPerPage: _itemsPerPage,
                totalPages: _totalPages,
                pagesWithLoadingStarted: _pagesWithLoadingStarted,
                getPosterUrl: _getPosterUrl,
                authHeader: _authHeader,
                buildShimmerEffect: _buildShimmerEffect,
                playVideo: _playVideo,
                downloadMovie: _downloadMovie,
                nextPage: _nextPage,
                previousPage: _previousPage,
                downloadedPaths: _downloadedPaths,
                baseUrl: _baseUrl,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final startIndex = _currentPage * _itemsPerPage;
    final endIndex = math.min(startIndex + _itemsPerPage, _searchResults.length);
    final paginatedResults = _searchResults.sublist(startIndex, endIndex);
    
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 70),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 0.7, crossAxisSpacing: 12, mainAxisSpacing: 16),
            itemCount: paginatedResults.length,
            itemBuilder: (context, index) {
              final item = paginatedResults[index];
              final isDir = item['type'] == 'directory';
              final url = _getPosterUrl(item);
              final isDownloaded = _downloadedPaths.any((p) => p.contains(item['name'].replaceAll(RegExp(r'[^\w\s]+'), '')));
              final isCurrentlyDownloading = DownloadsManager().activeMetadata.values.any((m) => m.title == item['name']);

              return Column(
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 0.7,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildShimmerEffect(),
                            Image.network(
                              url,
                              headers: {'Authorization': _authHeader},
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const SizedBox.shrink();
                              },
                              errorBuilder: (c, e, s) => Container(color: Colors.grey[900]),
                            ),
                            Positioned.fill(child: Material(color: Colors.transparent, child: InkWell(onTap: () => isDir ? _navigateToFolder(item['name']) : _playVideo(item)))),
                            if (!isDir) Positioned(bottom: 8, right: 8, child: GestureDetector(onTap: (isDownloaded || isCurrentlyDownloading) ? null : () => _downloadMovie(item, url), child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: (isDownloaded || isCurrentlyDownloading) ? Colors.green : const Color(0xFF8A2BE2), borderRadius: BorderRadius.circular(4)), child: Icon((isDownloaded || isCurrentlyDownloading) ? Icons.check : Icons.file_download, color: Colors.white, size: 18)))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(item['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFolderContent() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 100, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.7, crossAxisSpacing: 12, mainAxisSpacing: 16),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final item = _files[index];
        final isDir = item['type'] == 'directory';
        final url = _getPosterUrl(item);
        final isDownloaded = _downloadedPaths.any((p) => p.contains(item['name'].replaceAll(RegExp(r'[^\w\s]+'), '')));
        final isCurrentlyDownloading = DownloadsManager().activeMetadata.values.any((m) => m.title == item['name']);

        return GestureDetector(
          onTap: () => isDir ? _navigateToFolder(item['name']) : _playVideo(item),
          child: Column(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 0.7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildShimmerEffect(),
                        Image.network(
                          url,
                          headers: {'Authorization': _authHeader},
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const SizedBox.shrink();
                          },
                          errorBuilder: (c, e, s) => Container(color: Colors.grey[900]),
                        ),
                        if (isDir) const Positioned(bottom: 8, right: 8, child: Icon(Icons.folder, color: Colors.white, size: 18)),
                        if (!isDir) Positioned(bottom: 8, right: 8, child: GestureDetector(onTap: (isDownloaded || isCurrentlyDownloading) ? null : () => _downloadMovie(item, url), child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: (isDownloaded || isCurrentlyDownloading) ? Colors.green : const Color(0xFF8A2BE2), borderRadius: BorderRadius.circular(4)), child: Icon((isDownloaded || isCurrentlyDownloading) ? Icons.check : Icons.file_download, color: Colors.white, size: 18)))),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(item['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Colors.white)),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> get _files => [..._tvShows, ..._movies];

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _mainScrollController.dispose();
    _tvShowsScrollController.dispose();
    _seasonsScrollController.dispose();
    _searchController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }
}

class HomeCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> recentlyAddedMovies;
  final Function(Map<String, dynamic>) getPosterUrl;
  final String authHeader;
  final Function() buildShimmerEffect;
  final Function(Map<String, dynamic>) playVideo;
  final Function(String) navigateToFolder;
  final Function() onUserInteractionStart;
  final Function() onUserInteractionEnd;

  const HomeCarousel({
    super.key,
    required this.recentlyAddedMovies,
    required this.getPosterUrl,
    required this.authHeader,
    required this.buildShimmerEffect,
    required this.playVideo,
    required this.navigateToFolder,
    required this.onUserInteractionStart,
    required this.onUserInteractionEnd,
  });

  @override
  State<HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel> {
  final PageController _carouselController = PageController();
  int _currentCarouselIndex = 0;
  Timer? _autoSlideTimer;

  @override
  void initState() {
    super.initState();
    _startAutoSlideTimer();
  }

  void _startAutoSlideTimer() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (widget.recentlyAddedMovies.isNotEmpty && mounted) {
        final nextPage = (_currentCarouselIndex + 1) % widget.recentlyAddedMovies.length;
        _carouselController.animateToPage(nextPage, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 500,
      width: double.infinity,
      child: Stack(
        children: [
          Listener(
            onPointerDown: (_) { widget.onUserInteractionStart(); _autoSlideTimer?.cancel(); },
            onPointerUp: (_) { widget.onUserInteractionEnd(); _startAutoSlideTimer(); },
            child: PageView.builder(
              controller: _carouselController,
              onPageChanged: (index) => setState(() => _currentCarouselIndex = index),
              itemCount: widget.recentlyAddedMovies.length,
              itemBuilder: (context, index) {
                final movie = widget.recentlyAddedMovies[index];
                final isFile = movie['type'] == 'file';
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.buildShimmerEffect(),
                    Image.network(
                      widget.getPosterUrl(movie),
                      headers: {'Authorization': widget.authHeader},
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox.shrink();
                      },
                      errorBuilder: (c, e, s) => Container(color: Colors.black),
                    ),
                    Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.5), Colors.transparent, Colors.black.withOpacity(0.7), Colors.black], stops: const [0.0, 0.5, 0.8, 1.0]))),
                    Positioned(bottom: 40, left: 0, right: 0, child: Column(children: [Text(movie['name'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center), const SizedBox(height: 20), ElevatedButton(onPressed: () => isFile ? widget.playVideo(movie) : widget.navigateToFolder(movie['name']), child: const Text('Play'))])),
                  ],
                );
              },
            ),
          ),
          Positioned(bottom: 10, left: 0, right: 0, child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(widget.recentlyAddedMovies.length, (i) => Container(width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(shape: BoxShape.circle, color: i == _currentCarouselIndex ? const Color(0xFF8A2BE2) : Colors.white54)))))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _carouselController.dispose();
    super.dispose();
  }
}

class TvShowsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> tvShows;
  final ScrollController scrollController;
  final Function(Map<String, dynamic>) getPosterUrl;
  final String authHeader;
  final Function() buildShimmerEffect;
  final Function(Map<String, dynamic>) onTvShowSelected;

  const TvShowsWidget({
    super.key,
    required this.tvShows,
    required this.scrollController,
    required this.getPosterUrl,
    required this.authHeader,
    required this.buildShimmerEffect,
    required this.onTvShowSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('TV Shows', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))),
        SizedBox(
          height: 180,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: tvShows.length,
            itemBuilder: (context, index) {
              final item = tvShows[index];
              return GestureDetector(
                onTap: () => onTvShowSelected(item),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 126,
                  child: Column(
                    children: [
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 0.7,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                buildShimmerEffect(),
                                Image.network(
                                  getPosterUrl(item),
                                  headers: {'Authorization': authHeader},
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const SizedBox.shrink();
                                  },
                                  errorBuilder: (c, e, s) => Container(color: Colors.grey[900]),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(item['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class TvShowDetailWidget extends StatefulWidget {
  final Map<String, dynamic>? selectedTvShow;
  final List<Map<String, dynamic>> seasons;
  final List<Map<String, dynamic>> episodes;
  final String? selectedSeason;
  final Function(String) loadSeasonEpisodes;
  final Function(Map<String, dynamic>) getPosterUrl;
  final String authHeader;
  final Function() buildShimmerEffect;
  final Function(int) formatFileSize;
  final ScrollController seasonsScrollController;
  final String serverIp;
  final String serverPort;
  final String username;
  final String password;
  final Function(Map<String, dynamic>) playVideo;
  final Function(Map<String, dynamic>) onDownloadEpisode;
  final VoidCallback onDownloadSeason;
  final Set<String> downloadedPaths;
  final String baseUrl;

  const TvShowDetailWidget({
    super.key,
    required this.selectedTvShow,
    required this.seasons,
    required this.episodes,
    required this.selectedSeason,
    required this.loadSeasonEpisodes,
    required this.getPosterUrl,
    required this.authHeader,
    required this.buildShimmerEffect,
    required this.formatFileSize,
    required this.seasonsScrollController,
    required this.serverIp,
    required this.serverPort,
    required this.username,
    required this.password,
    required this.playVideo,
    required this.onDownloadEpisode,
    required this.onDownloadSeason,
    required this.downloadedPaths,
    required this.baseUrl,
  });

  @override
  State<TvShowDetailWidget> createState() => _TvShowDetailWidgetState();
}

class _TvShowDetailWidgetState extends State<TvShowDetailWidget> {
  @override
  Widget build(BuildContext context) {
    final posterUrl = widget.selectedTvShow != null ? widget.getPosterUrl(widget.selectedTvShow!) : '';
    final isSeasonDownloaded = widget.episodes.isNotEmpty && widget.episodes.every((ep) => widget.downloadedPaths.any((p) => p.contains(ep['name'].replaceAll(RegExp(r'[^\w\s]+'), ''))));
    final isSeasonDownloading = widget.episodes.isNotEmpty && widget.episodes.any((ep) => DownloadsManager().activeMetadata.values.any((m) => m.title == ep['name']));

    return Stack(
      children: [
        Positioned.fill(
          child: Image.network(
            posterUrl,
            headers: {'Authorization': widget.authHeader},
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => Container(color: Colors.black),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(color: Colors.black.withOpacity(0.25)),
          ),
        ),
        SingleChildScrollView(
          padding: const EdgeInsets.only(top: 100, bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        posterUrl,
                        headers: {'Authorization': widget.authHeader},
                        height: 180,
                        width: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Container(color: Colors.grey[900]),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Text(widget.selectedTvShow?['name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
                  ],
                ),
              ),
              if (widget.seasons.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ListView.builder(
                            controller: widget.seasonsScrollController,
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.seasons.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ElevatedButton(
                                onPressed: () => widget.loadSeasonEpisodes(widget.seasons[index]['name']),
                                style: ElevatedButton.styleFrom(backgroundColor: widget.selectedSeason == widget.seasons[index]['name'] ? const Color(0xFF8A2BE2) : Colors.grey[800]),
                                child: Text(widget.seasons[index]['name']),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: Icon((isSeasonDownloaded || isSeasonDownloading) ? Icons.check : Icons.file_download, color: (isSeasonDownloaded || isSeasonDownloading) ? Colors.green : const Color(0xFF8A2BE2)),
                        onPressed: (isSeasonDownloaded || isSeasonDownloading) ? null : widget.onDownloadSeason,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              _buildEpisodeGrid(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeGrid() {
    if (widget.episodes.isEmpty) return const Center(child: Text('No episodes found', style: TextStyle(color: Colors.white60)));
    final sorted = List<Map<String, dynamic>>.from(widget.episodes)..sort((a, b) => a['name'].compareTo(b['name']));
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 16 / 9,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final ep = sorted[index];
        final thumbUrl = '${widget.baseUrl}/api/thumbnail?path=${Uri.encodeComponent(ep['path'])}';
        final isDownloaded = widget.downloadedPaths.any((p) => p.contains(ep['name'].replaceAll(RegExp(r'[^\w\s]+'), '')));
        final isCurrentlyDownloading = DownloadsManager().activeMetadata.values.any((m) => m.title == ep['name']);

        return GestureDetector(
          onTap: () => widget.playVideo(ep),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.buildShimmerEffect(),
                Image.network(
                  thumbUrl,
                  headers: {'Authorization': widget.authHeader},
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const SizedBox.shrink();
                  },
                  errorBuilder: (c, e, s) => Container(color: Colors.grey[900], child: const Icon(Icons.play_circle_fill, color: Colors.white54, size: 40)),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.black.withOpacity(0.5),
                    child: Text(ep['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
                Positioned(
                  top: 5,
                  right: 5,
                  child: GestureDetector(
                    onTap: (isDownloaded || isCurrentlyDownloading) ? null : () => widget.onDownloadEpisode(ep),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: (isDownloaded || isCurrentlyDownloading) ? Colors.green : const Color(0xFF8A2BE2), borderRadius: BorderRadius.circular(4)),
                      child: Icon((isDownloaded || isCurrentlyDownloading) ? Icons.check : Icons.file_download, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class MoviesGridWidget extends StatelessWidget {
  final List<Map<String, dynamic>> movies;
  final int currentPage;
  final int itemsPerPage;
  final int totalPages;
  final Set<int> pagesWithLoadingStarted;
  final Function(Map<String, dynamic>) getPosterUrl;
  final String authHeader;
  final Function() buildShimmerEffect;
  final Function(Map<String, dynamic>) playVideo;
  final Function(Map<String, dynamic>, String) downloadMovie;
  final Function() nextPage;
  final Function() previousPage;
  final Set<String> downloadedPaths;
  final String baseUrl;

  const MoviesGridWidget({
    super.key,
    required this.movies,
    required this.currentPage,
    required this.itemsPerPage,
    required this.totalPages,
    required this.pagesWithLoadingStarted,
    required this.getPosterUrl,
    required this.authHeader,
    required this.buildShimmerEffect,
    required this.playVideo,
    required this.downloadMovie,
    required this.nextPage,
    required this.previousPage,
    required this.downloadedPaths,
    required this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final start = currentPage * itemsPerPage;
    final end = math.min(start + itemsPerPage, movies.length);
    if (start >= movies.length) return const SizedBox.shrink();
    final paginated = movies.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 24, 16, 8), child: Text('Movies', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 0.7, crossAxisSpacing: 12, mainAxisSpacing: 16),
          itemCount: paginated.length,
          itemBuilder: (context, index) {
            final movie = paginated[index];
            final url = getPosterUrl(movie);
            final isDownloaded = downloadedPaths.any((p) => p.contains(movie['name'].replaceAll(RegExp(r'[^\w\s]+'), '')));
            final isCurrentlyDownloading = DownloadsManager().activeMetadata.values.any((m) => m.title == movie['name']);

            return Column(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 0.7,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          buildShimmerEffect(),
                          Image.network(
                            url,
                            headers: {'Authorization': authHeader},
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const SizedBox.shrink();
                            },
                            errorBuilder: (c, e, s) => Container(color: Colors.grey[900]),
                          ),
                          Positioned.fill(child: Material(color: Colors.transparent, child: InkWell(onTap: () => playVideo(movie)))),
                          Positioned(bottom: 8, right: 8, child: GestureDetector(onTap: (isDownloaded || isCurrentlyDownloading) ? null : () => downloadMovie(movie, url), child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: (isDownloaded || isCurrentlyDownloading) ? Colors.green : const Color(0xFF8A2BE2), borderRadius: BorderRadius.circular(4)), child: Icon((isDownloaded || isCurrentlyDownloading) ? Icons.check : Icons.file_download, color: Colors.white, size: 18)))),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(movie['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            );
          },
        ),
        if (totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: currentPage > 0 ? previousPage : null),
                Text('Page ${currentPage + 1} of $totalPages', style: const TextStyle(color: Colors.white)),
                IconButton(icon: const Icon(Icons.arrow_forward_ios, color: Colors.white), onPressed: currentPage < totalPages - 1 ? nextPage : null),
              ],
            ),
          ),
      ],
    );
  }
}
