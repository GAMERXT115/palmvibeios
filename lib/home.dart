import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'login.dart';
import 'dart:async';
import 'home_carousel.dart';
import 'home_tvshows.dart'; 
import 'home_movies.dart';
import 'video_player.dart';

class HomeScreen extends StatefulWidget {
  final String serverIp;
  final String serverPort;
  final String username;
  final String password;

  const HomeScreen({
    Key? key,
    required this.serverIp,
    required this.serverPort,
    required this.username,
    required this.password,
  }) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final List<String> _categories = ['Bollywood', 'Hollywood', 'Watchlist'];
  String _currentCategory = 'Hollywood';
  List<Map<String, dynamic>> _tvShows = [];
  List<Map<String, dynamic>> _movies = [];
  List<Map<String, dynamic>> _marvelMovies = [];
  List<Map<String, dynamic>> _dcMovies = [];
  List<Map<String, dynamic>> _recentlyAddedMovies = [];
  List<Map<String, dynamic>> _comingSoonMovies = [];
  List<Map<String, dynamic>> _watchlist = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<String> _currentPath = [];
  
  bool _isLoading = true;
  bool _isSearching = false;
  bool _namesLoaded = false;
  bool _isHeaderScrolled = false;
  String _error = '';
  bool _isSearchExpanded = false;
  
  int _currentPage = 0;
  final int _itemsPerPage = 18; 
  int _totalPages = 0;
  
  bool _isInTvShowDetail = false;
  Map<String, dynamic>? _selectedTvShow;
  List<Map<String, dynamic>> _seasons = [];
  String? _selectedSeason;
  List<Map<String, dynamic>> _episodes = [];
  
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _recentlyAddedScrollController = ScrollController();
  final ScrollController _comingSoonScrollController = ScrollController();
  final ScrollController _tvShowsScrollController = ScrollController();
  final ScrollController _marvelScrollController = ScrollController();
  final ScrollController _dcScrollController = ScrollController();
  final ScrollController _watchlistScrollController = ScrollController();
  final ScrollController _seasonsScrollController = ScrollController();
  
  late AnimationController _shimmerController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _mainScrollController.addListener(() {
      if (_mainScrollController.hasClients) {
        if (_mainScrollController.offset > 10 && !_isHeaderScrolled) {
          setState(() => _isHeaderScrolled = true);
        } else if (_mainScrollController.offset <= 10 && _isHeaderScrolled) {
          setState(() => _isHeaderScrolled = false);
        }
      }
    });

    _loadInitialContent();
    _fetchWatchlist();
  }

  String get _baseUrl => 'http://${widget.serverIp}:${widget.serverPort}';
  String get _authHeader => 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (query.isEmpty) {
        setState(() {
          _isSearching = false;
          _searchResults = [];
        });
      } else {
        _performSearch(query);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isSearching = true;
      _isLoading = true;
    });

    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory == 'Watchlist' ? 'Hollywood' : _currentCategory,
        'path': 'Movies',
        'search': query,
        'limit': '500',
      });

      final response = await http.get(uri, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true',
      });

      List<Map<String, dynamic>> movieResults = [];
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          movieResults = List<Map<String, dynamic>>.from(data['files']);
        }
      }

      final filteredTvShows = _tvShows.where((show) {
        final name = show['name'].toString().toLowerCase();
        return name.contains(query.toLowerCase());
      }).toList();

      setState(() {
        _searchResults = [...filteredTvShows, ...movieResults];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchWatchlist() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/get-userdata');
      final response = await http.get(uri, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true',
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['userData'] != null && data['userData']['watchlist'] != null) {
          setState(() {
            _watchlist = List<Map<String, dynamic>>.from(data['userData']['watchlist']);
          });
        }
      }
    } catch (e) {}
  }

  Future<void> _toggleWatchlist(Map<String, dynamic> item) async {
    setState(() {
      final index = _watchlist.indexWhere((element) => element['path'] == item['path']);
      if (index >= 0) {
        _watchlist.removeAt(index);
      } else {
        _watchlist.add(item);
      }
    });

    try {
      final uri = Uri.parse('$_baseUrl/api/save-userdata');
      await http.post(
        uri,
        headers: {
          'Authorization': _authHeader,
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: json.encode({'watchlist': _watchlist}),
      );
    } catch (e) {}
  }

  Future<void> _loadInitialContent() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory == 'Watchlist' ? 'Hollywood' : _currentCategory,
        'path': _currentPath.isEmpty ? '' : path.joinAll(_currentPath),
      });
      
      final response = await http.get(uri, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<Map<String, dynamic>> files = List<Map<String, dynamic>>.from(data['files']);
          final directories = files.where((file) => file['type'] == 'directory').toList();
          final videoFiles = files.where((file) => file['type'] == 'file' && _isVideoFile(file['name'])).toList();

          if (_currentPath.isEmpty) {
            _loadRecentlyAdded();
            _loadComingSoon();
            _loadTvShows();
            _loadMarvelMovies();
            _loadDcMovies();
            _loadMoviesPaginated(0);
          } else if (_isInTvShowDetail) {
            _processSeasons(directories, videoFiles);
          }
          
          setState(() {
            _isLoading = false;
            _namesLoaded = true;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Connection Error');
    }
  }

  void _processSeasons(List<Map<String, dynamic>> directories, List<Map<String, dynamic>> videoFiles) {
    final seasonFolders = directories.where((dir) => dir['name'].toLowerCase().contains('season')).toList();
    setState(() {
      _seasons = seasonFolders;
      _episodes = videoFiles;
      if (_selectedSeason == null && _seasons.isNotEmpty) {
        _selectedSeason = _seasons.first['name'];
        _loadSeasonEpisodes(_selectedSeason!);
      }
    });
  }

  Future<void> _loadMoviesPaginated(int page) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory == 'Watchlist' ? 'Hollywood' : _currentCategory,
        'path': 'Movies',
        'page': (page + 1).toString(),
        'limit': _itemsPerPage.toString(),
      });

      final response = await http.get(uri, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            List<Map<String, dynamic>> allFiles = List<Map<String, dynamic>>.from(data['files']);
            _movies = allFiles.where((m) {
              final name = m['name'].toString();
              return name != 'Marvel' && name != 'DC' && name != '1RECENTLY ADDED' && name != '2COMINGSOON';
            }).toList();
            _totalPages = (data['total'] / _itemsPerPage).ceil();
            _currentPage = page;
          });
        }
      }
    } catch (e) {}
  }

  Future<void> _loadRecentlyAdded() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory == 'Watchlist' ? 'Hollywood' : _currentCategory,
        'path': 'Movies/1RECENTLY ADDED',
        'limit': '1000',
      });
      final response = await http.get(uri, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true',
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _recentlyAddedMovies = List<Map<String, dynamic>>.from(data['files']);
        });
      }
    } catch (e) {}
  }

  Future<void> _loadComingSoon() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory == 'Watchlist' ? 'Hollywood' : _currentCategory,
        'path': 'Movies/2COMINGSOON',
        'limit': '1000',
      });
      final response = await http.get(uri, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true',
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _comingSoonMovies = List<Map<String, dynamic>>.from(data['files']);
        });
      }
    } catch (e) {}
  }

  Future<void> _loadMarvelMovies() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory == 'Watchlist' ? 'Hollywood' : _currentCategory,
        'path': 'Movies/Marvel',
        'limit': '1000',
      });
      final response = await http.get(uri, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true',
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _marvelMovies = List<Map<String, dynamic>>.from(data['files']);
        });
      }
    } catch (e) {}
  }

  Future<void> _loadDcMovies() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory == 'Watchlist' ? 'Hollywood' : _currentCategory,
        'path': 'Movies/DC',
        'limit': '1000',
      });
      final response = await http.get(uri, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true',
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _dcMovies = List<Map<String, dynamic>>.from(data['files']);
        });
      }
    } catch (e) {}
  }

  Future<void> _loadTvShows() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
        'category': _currentCategory == 'Watchlist' ? 'Hollywood' : _currentCategory,
        'path': 'TV Shows',
        'limit': '1000',
      });
      final response = await http.get(uri, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true',
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _tvShows = List<Map<String, dynamic>>.from(data['files']);
        });
      }
    } catch (e) {}
  }

  Future<void> _loadSeasonEpisodes(String seasonName) async {
    final seasonFolder = _seasons.firstWhere((s) => s['name'] == seasonName);
    final uri = Uri.parse('$_baseUrl/api/browse').replace(queryParameters: {
      'category': _currentCategory == 'Watchlist' ? 'Hollywood' : _currentCategory,
      'path': seasonFolder['path'],
      'limit': '1000',
    });
    final response = await http.get(uri, headers: {
      'Authorization': _authHeader,
      'ngrok-skip-browser-warning': 'true',
    });
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _episodes = List<Map<String, dynamic>>.from(data['files']).where((f) => _isVideoFile(f['name'])).toList();
        _selectedSeason = seasonName;
      });
    }
  }

  void _changeCategory(String category) {
    setState(() {
      _currentCategory = category;
      _currentPath = [];
      _isInTvShowDetail = false;
      _currentPage = 0;
      _movies = [];
      _marvelMovies = [];
      _dcMovies = [];
      _tvShows = [];
      _recentlyAddedMovies = [];
      _comingSoonMovies = [];
      _isSearching = false;
      _searchController.clear();
    });
    _loadInitialContent();
  }

  bool _isVideoFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return ['.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm', '.m4v', '.ts'].contains(ext);
  }

  String _getPosterUrl(Map<String, dynamic> item) {
    return '$_baseUrl/api/poster?path=${Uri.encodeComponent(item['path'])}';
  }

  void _showMovieDetails(Map<String, dynamic> movie) {
  setState(() {
    _isSearchExpanded = false;
  });
  FocusScope.of(context).unfocus();
  showDialog(
    context: context,
    builder: (context) => MovieDetailsModal(
      movie: movie,
      baseUrl: _baseUrl,
      authHeader: _authHeader,
      onPlay: _playVideo,
      watchlist: _watchlist,
      onToggleWatchlist: _toggleWatchlist,
      serverIp: widget.serverIp,
      serverPort: widget.serverPort,
      username: widget.username,
    ),
  ).then((_) => setState(() {}));
}


  void _playVideo(Map<String, dynamic> file) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.purple)),
    );

    List<String> subtitleUrls = [];
    try {
      final subUri = Uri.parse('$_baseUrl/api/find-subtitles').replace(queryParameters: {
        'path': file['path'],
      });

      final response = await http.get(subUri, headers: {
        'Authorization': _authHeader,
        'ngrok-skip-browser-warning': 'true',
      }).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['subtitles'] != null) {
          subtitleUrls = (data['subtitles'] as List).map((sub) {
            return '$_baseUrl/api/subtitle?path=${Uri.encodeComponent(sub['path'])}';
          }).toList();
        }
      }
    } catch (e) {}

    if (!mounted) return;
    Navigator.pop(context);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          videoUrl: '$_baseUrl/api/stream?path=${Uri.encodeComponent(file['path'])}',
          subtitleUrls: subtitleUrls,
          title: path.basenameWithoutExtension(file['name'] ?? ''),
          serverIp: widget.serverIp,
          serverPort: widget.serverPort,
          username: widget.username,
          password: widget.password,
          fileSize: file['size'] ?? 0,
        ),
      ),
    );

    setState(() {});
  }

  void _handleItemTap(Map<String, dynamic> item) {
  final String itemPath = item['path'] ?? '';
  FocusScope.of(context).unfocus();
  if (itemPath.contains('TV Shows') && item['type'] == 'directory') {
    setState(() {
      _isSearching = false;
      _isSearchExpanded = false;
      _searchController.clear();
      _selectedTvShow = item;
      _isInTvShowDetail = true;
      _currentPath = [item['path']];
    });
    _loadInitialContent();
  } else {
    setState(() {
      _isSearchExpanded = false;
    });
    _showMovieDetails(item);
  }
}


  Widget _buildShimmerEffect() {
    return Container(color: Colors.grey[900]);
  }

  

Widget _buildNavHeader() {
  return Container(
    color: (_isHeaderScrolled || _isInTvShowDetail) ? Colors.black : Colors.black.withOpacity(0.4),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                reverseDuration: const Duration(milliseconds: 250),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.05, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                      child: child,
                    ),
                  );
                },
                child: _isSearchExpanded
                    ? Container(
                        key: const ValueKey('searchField'),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search movies...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                            border: InputBorder.none,
                            prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 20),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                              onPressed: () {
                                setState(() {
                                  _isSearchExpanded = false;
                                  _isSearching = false;
                                  _searchController.clear();
                                  FocusScope.of(context).unfocus();
                                });
                              },
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      )
                    : Row(
                        key: const ValueKey('headerContent'),
                        children: [
                          if (_isInTvShowDetail)
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                              onPressed: _navigateUp,
                            ),
                          GestureDetector(
                            onTap: () => _changeCategory('Hollywood'),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Color(0xFF8A2BE2), blurRadius: 8)],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.asset('assets/icon/app_icon.png'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'PALM VIBE',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (!_isInTvShowDetail)
                            IconButton(
                              icon: const Icon(Icons.search, color: Colors.white, size: 24),
                              onPressed: () => setState(() => _isSearchExpanded = true),
                            ),
                          IconButton(
                            icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
                            onPressed: () async {
                              await BiometricService().setManualLogout(true);
                              if (mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const ServerConfigScreen()),
                                );
                              }
                            },
                          ),
                        ],
                      ),
              ),
            ),
            if (!_isInTvShowDetail && !_isSearchExpanded) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _categories
                    .map((cat) => _buildNavItem(cat, _currentCategory == cat, () => _changeCategory(cat)))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

  Widget _buildNavItem(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        decoration: BoxDecoration(
          border: isActive ? const Border(bottom: BorderSide(color: Color(0xFFB19CD9), width: 2)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isActive ? const Color(0xFFB19CD9) : const Color(0xFFE5E5E5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentPath.isEmpty && !_isInTvShowDetail,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _navigateUp();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: _isLoading && !_namesLoaded
                  ? const Center(child: CircularProgressIndicator(color: Colors.purple))
                  : SingleChildScrollView(
                      controller: _mainScrollController,
                      physics: const BouncingScrollPhysics(),
                      child: _buildContent(),
                    ),
            ),
            if (!_isLoading || _namesLoaded)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildNavHeader(),
              ),
          ],
        ),
      ),
    );
  }

  void _navigateUp() {
    setState(() {
      if (_isInTvShowDetail) {
        _isInTvShowDetail = false;
        _currentPath = [];
        _selectedSeason = null;
      } else if (_currentPath.isNotEmpty) {
        _currentPath.removeLast();
      }
    });
    _loadInitialContent();
  }

  Widget _buildHorizontalMovieSection(String title, List<Map<String, dynamic>> items, ScrollController controller) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        SizedBox(
          height: 220,
          child: ListView.builder(
            controller: controller,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 15),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                width: 130,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: MovieCard(
                    movie: item,
                    getPosterUrl: _getPosterUrl,
                    authHeader: _authHeader,
                    buildShimmerEffect: _buildShimmerEffect,
                    onTap: () => _handleItemTap(item),
                    serverIp: widget.serverIp,
                    serverPort: widget.serverPort,
                    username: widget.username,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

    Widget _buildContent() {
    if (_isInTvShowDetail) {
      return Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 60),
          TvShowDetailWidget(
            selectedTvShow: _selectedTvShow,
            seasons: _seasons,
            episodes: _episodes,
            watchlist: _watchlist,
            selectedSeason: _selectedSeason,
            loadSeasonEpisodes: _loadSeasonEpisodes,
            getPosterUrl: _getPosterUrl,
            authHeader: _authHeader,
            buildShimmerEffect: _buildShimmerEffect,
            onWatchlistUpdated: _fetchWatchlist,
            formatFileSize: (s) => "",
            serverIp: widget.serverIp,
            serverPort: widget.serverPort,
            username: widget.username,
            password: widget.password,
            currentCategory: _currentCategory,
            seasonsScrollController: _seasonsScrollController,
          ),
        ],
      );
    }

    if (_isSearching) {
      if (_isLoading) {
        return Padding(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 150),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.purple),
          ),
        );
      }
      
      final tvResults = _searchResults.where((item) => item['path'].toString().contains('TV Shows')).toList();
      final movieResults = _searchResults.where((item) => !item['path'].toString().contains('TV Shows')).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 100),
          if (tvResults.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Text(
                'TV Shows',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 15,
                ),
                itemBuilder: (context, index) {
                  final item = tvResults[index];
                  return MovieCard(
                    movie: item,
                    getPosterUrl: _getPosterUrl,
                    authHeader: _authHeader,
                    buildShimmerEffect: _buildShimmerEffect,
                    onTap: () => _handleItemTap(item),
                    serverIp: widget.serverIp,
                    serverPort: widget.serverPort,
                    username: widget.username,
                  );
                },
                itemCount: tvResults.length,
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (movieResults.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Text(
                'Movies',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 15,
                ),
                itemBuilder: (context, index) {
                  final item = movieResults[index];
                  return MovieCard(
                    movie: item,
                    getPosterUrl: _getPosterUrl,
                    authHeader: _authHeader,
                    buildShimmerEffect: _buildShimmerEffect,
                    onTap: () => _handleItemTap(item),
                    serverIp: widget.serverIp,
                    serverPort: widget.serverPort,
                    username: widget.username,
                  );
                },
                itemCount: movieResults.length,
              ),
            ),
          ],
          if (tvResults.isEmpty && movieResults.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 50),
                child: Text(
                  'No results found',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),
        ],
      );
    }

    if (_currentCategory == 'Watchlist') {
      final watchlistTv = _watchlist.where((i) => i['path'].toString().contains('TV Shows')).toList();
      final watchlistMovies = _watchlist.where((i) => !i['path'].toString().contains('TV Shows')).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 100),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Text('My Watchlist', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          if (watchlistTv.isNotEmpty)
            _buildHorizontalMovieSection('TV Shows', watchlistTv, _watchlistScrollController),
          if (watchlistMovies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Movies', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 15),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 15,
                    ),
                    itemBuilder: (context, index) {
                      final movie = watchlistMovies[index];
                      return MovieCard(
                        movie: movie,
                        getPosterUrl: _getPosterUrl,
                        authHeader: _authHeader,
                        buildShimmerEffect: _buildShimmerEffect,
                        onTap: () => _handleItemTap(movie),
                        serverIp: widget.serverIp,
                        serverPort: widget.serverPort,
                        username: widget.username,
                      );
                    },
                    itemCount: watchlistMovies.length,
                  ),
                ],
              ),
            ),
          if (watchlistTv.isEmpty && watchlistMovies.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 50),
                child: Text('Your watchlist is empty', style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top + 100),
        if (_recentlyAddedMovies.isNotEmpty)
          HomeCarousel(
            recentlyAddedMovies: _recentlyAddedMovies,
            getPosterUrl: _getPosterUrl,
            authHeader: _authHeader,
            buildShimmerEffect: _buildShimmerEffect,
            playVideo: _playVideo,
            navigateToFolder: (p) {},
            onUserInteractionStart: () {},
            onUserInteractionEnd: () {},
            watchlist: _watchlist,
            onToggleWatchlist: _toggleWatchlist,
          ),
        _buildHorizontalMovieSection('Coming Soon', _comingSoonMovies, _comingSoonScrollController),
        _buildHorizontalMovieSection('Recently Added', _recentlyAddedMovies, _recentlyAddedScrollController),
        if (_tvShows.isNotEmpty)
          TvShowsWidget(
            tvShows: _tvShows,
            scrollController: _tvShowsScrollController,
            getPosterUrl: _getPosterUrl,
            authHeader: _authHeader,
            buildShimmerEffect: _buildShimmerEffect,
            onTvShowSelected: (show) {
              setState(() {
                _selectedTvShow = show;
                _isInTvShowDetail = true;
                _currentPath = [show['path']];
              });
              _loadInitialContent();
            },
            serverIp: widget.serverIp,
            serverPort: widget.serverPort,
            username: widget.username,
          ),
        _buildHorizontalMovieSection('DC', _dcMovies, _dcScrollController),
        _buildHorizontalMovieSection('Marvel', _marvelMovies, _marvelScrollController),
        if (_movies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Movies', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 15),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 15,
                  ),
                  itemBuilder: (context, index) {
                    final movie = _movies[index];
                    return MovieCard(
                      movie: movie,
                      getPosterUrl: _getPosterUrl,
                      authHeader: _authHeader,
                      buildShimmerEffect: _buildShimmerEffect,
                      onTap: () => _showMovieDetails(movie),
                      serverIp: widget.serverIp,
                      serverPort: widget.serverPort,
                      username: widget.username,
                    );
                  },
                  itemCount: _movies.length,
                ),
              ],
            ),
          ),
        if (_movies.isNotEmpty && _totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _currentPage > 0 ? () => _loadMoviesPaginated(_currentPage - 1) : null,
                  icon: const Icon(Icons.arrow_back_ios, size: 14),
                ),
                Text('Page ${_currentPage + 1} of $_totalPages', style: const TextStyle(color: Colors.white, fontSize: 14)),
                IconButton(
                  onPressed: _currentPage < _totalPages - 1 ? () => _loadMoviesPaginated(_currentPage + 1) : null,
                  icon: const Icon(Icons.arrow_forward_ios, size: 14),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _mainScrollController.dispose();
    _recentlyAddedScrollController.dispose();
    _comingSoonScrollController.dispose();
    _tvShowsScrollController.dispose();
    _marvelScrollController.dispose();
    _dcScrollController.dispose();
    _watchlistScrollController.dispose();
    _seasonsScrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }
}
