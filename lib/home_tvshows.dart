import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'video_progress_manager.dart';
import 'video_player.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TvShowsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> tvShows;
  final ScrollController scrollController;
  final Function(Map<String, dynamic>) getPosterUrl;
  final String authHeader;
  final Function() buildShimmerEffect;
  final Function(Map<String, dynamic>) onTvShowSelected;
  final String serverIp;
  final String serverPort;
  final String username;

  const TvShowsWidget({
    Key? key,
    required this.tvShows,
    required this.scrollController,
    required this.getPosterUrl,
    required this.authHeader,
    required this.buildShimmerEffect,
    required this.onTvShowSelected,
    required this.serverIp,
    required this.serverPort,
    required this.username,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(
            'TV Shows',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 15),
            itemCount: tvShows.length,
            itemBuilder: (context, index) {
              final show = tvShows[index];
              final String showPath = show['path'] ?? '';

              return GestureDetector(
                onTap: () => onTvShowSelected(show),
                child: Container(
                  width: 130,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white10,
                              width: 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  getPosterUrl(show),
                                  headers: {
                                    'Authorization': authHeader,
                                    'ngrok-skip-browser-warning': 'true',
                                  },
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => Container(color: Colors.grey[900]),
                                ),
                                FutureBuilder<VideoProgress?>(
                                  future: VideoProgressManager.getProgress(
                                    videoPath: showPath,
                                    title: show['name'],
                                    serverIp: serverIp,
                                    serverPort: serverPort,
                                    authHeader: authHeader,
                                  ),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData && snapshot.data != null) {
                                      final double progress = snapshot.data!.percentageWatched;
                                      if (progress > 0.02) {
                                        return Positioned(
                                          bottom: 0,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            height: 3,
                                            color: Colors.black54,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: FractionallySizedBox(
                                                widthFactor: progress.clamp(0.0, 1.0),
                                                child: Container(
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFF8A2BE2),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        show['name'],
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
  final List<Map<String, dynamic>> watchlist;
  final String? selectedSeason;
  final Function(String) loadSeasonEpisodes;
  final Function(Map<String, dynamic>) getPosterUrl;
  final String authHeader;
  final Function() buildShimmerEffect;
  final Function() onWatchlistUpdated;
  final Function(int) formatFileSize;
  final ScrollController seasonsScrollController;
  final String serverIp, serverPort, username, password;
  final String currentCategory;

  const TvShowDetailWidget({
    Key? key,
    required this.selectedTvShow,
    required this.seasons,
    required this.episodes,
    required this.watchlist,
    required this.selectedSeason,
    required this.loadSeasonEpisodes,
    required this.getPosterUrl,
    required this.authHeader,
    required this.buildShimmerEffect,
    required this.onWatchlistUpdated,
    required this.formatFileSize,
    required this.seasonsScrollController,
    required this.serverIp,
    required this.serverPort,
    required this.username,
    required this.password,
    required this.currentCategory,
  }) : super(key: key);

  @override
  State<TvShowDetailWidget> createState() => _TvShowDetailWidgetState();
}

class _TvShowDetailWidgetState extends State<TvShowDetailWidget> {
  Map<String, dynamic>? _metadata;
  bool _isAdded = false;

  @override
  void initState() {
    super.initState();
    _isAdded = widget.watchlist.any((item) => item['path'] == widget.selectedTvShow?['path']);
    _fetchMetadata();
  }

  Future<void> _fetchMetadata() async {
    if (widget.selectedTvShow == null) return;
    try {
      final path = widget.selectedTvShow!['path'];
      final uri = Uri.parse('http://${widget.serverIp}:${widget.serverPort}/api/movie-assets')
          .replace(queryParameters: {'path': path});
      final response = await http.get(uri, headers: {'Authorization': widget.authHeader});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['metadata'] != null) {
          setState(() => _metadata = data['metadata']);
        }
      }
    } catch (e) {}
  }

  Future<void> _toggleWatchlist() async {
    final String endpoint = _isAdded ? 'api/watchlist-remove' : 'api/watchlist-add';
    try {
      final String itemPath = widget.selectedTvShow?['path'] ?? '';
      final String displayName = path.basename(itemPath);
      final url = Uri.parse('http://${widget.serverIp}:${widget.serverPort}/$endpoint');
      final response = await http.post(
        url,
        headers: {
          'Authorization': widget.authHeader,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'name': displayName,
          'path': itemPath,
          'type': 'directory',
          'mediaType': 'tv',
        }),
      );
      if (response.statusCode == 200) {
        setState(() => _isAdded = !_isAdded);
        widget.onWatchlistUpdated();
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> sortedEpisodes = List<Map<String, dynamic>>.from(widget.episodes);
    sortedEpisodes.sort((a, b) {
      final String nameA = a['name'].toString().toLowerCase();
      final String nameB = b['name'].toString().toLowerCase();
      final RegExp regExp = RegExp(r'(\d+)');
      final Match? matchA = regExp.firstMatch(nameA);
      final Match? matchB = regExp.firstMatch(nameB);
      if (matchA != null && matchB != null) {
        int numA = int.parse(matchA.group(1)!);
        int numB = int.parse(matchB.group(1)!);
        if (numA != numB) return numA.compareTo(numB);
      }
      return nameA.compareTo(nameB);
    });

    final String posterUrl = widget.selectedTvShow != null ? widget.getPosterUrl(widget.selectedTvShow!) : '';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              if (posterUrl.isNotEmpty)
                Container(
                  height: 300,
                  width: double.infinity,
                  child: Image.network(
                    posterUrl,
                    headers: {'Authorization': widget.authHeader, 'ngrok-skip-browser-warning': 'true'},
                    fit: BoxFit.cover,
                  ),
                ),
              Container(
                height: 300,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.selectedTvShow?['name'] ?? '',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (_metadata != null)
                          Text(
                            '${_metadata!['Year'] ?? ''}  •  ${_metadata!['Seasons'] ?? widget.seasons.length} Seasons',
                            style: const TextStyle(color: Color(0xFFB19CD9), fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        const Spacer(),
                        IconButton(
                          onPressed: _toggleWatchlist,
                          icon: Icon(_isAdded ? Icons.check_circle : Icons.add_circle_outline, color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_metadata != null && _metadata!['Description'] != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _metadata!['Description'],
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DropdownButton<String>(
              value: widget.selectedSeason,
              dropdownColor: Colors.black,
              isExpanded: true,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              underline: Container(height: 1, color: Colors.purpleAccent),
              items: widget.seasons.map((s) {
                return DropdownMenuItem<String>(
                  value: s['name'],
                  child: Text(s['name']),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) widget.loadSeasonEpisodes(val);
              },
            ),
          ),
          const SizedBox(height: 10),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedEpisodes.length,
            itemBuilder: (context, index) {
              final ep = sortedEpisodes[index];
              final String videoPath = ep['path'];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Container(
                  width: 100,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    image: DecorationImage(
                      image: NetworkImage(
                        'http://${widget.serverIp}:${widget.serverPort}/api/thumbnail?path=${Uri.encodeComponent(videoPath)}',
                        headers: {'Authorization': widget.authHeader, 'ngrok-skip-browser-warning': 'true'},
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: const Center(child: Icon(Icons.play_arrow, color: Colors.white, size: 24)),
                ),
                title: Text(
                  ep['name'].toString().split('.').first,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _playEpisode(ep, index, sortedEpisodes),
              );
            },
          ),
        ],
      ),
    );
  }

  void _playEpisode(Map<String, dynamic> ep, int index, List<Map<String, dynamic>> allEpisodes) async {
    Map<String, dynamic>? nextEp = (index < allEpisodes.length - 1) ? allEpisodes[index + 1] : null;
    List<String> subtitleUrls = [];
    try {
      final String videoPath = ep['path'];
      final subUri = Uri.parse('http://${widget.serverIp}:${widget.serverPort}/api/find-subtitles')
          .replace(queryParameters: {'path': videoPath});
      final response = await http.get(subUri, headers: {'Authorization': widget.authHeader});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          subtitleUrls = (data['subtitles'] as List).map((sub) {
            return 'http://${widget.serverIp}:${widget.serverPort}/api/subtitle?path=${Uri.encodeComponent(sub['path'])}';
          }).toList();
        }
      }
    } catch (e) {}

    if (!mounted) return;

    final result = await Navigator.push(context, MaterialPageRoute(builder: (c) => VideoPlayerScreen(
      videoUrl: 'http://${widget.serverIp}:${widget.serverPort}/api/stream?path=${Uri.encodeComponent(ep['path'])}',
      subtitleUrls: subtitleUrls,
      title: ep['name'],
      serverIp: widget.serverIp,
      serverPort: widget.serverPort,
      username: widget.username,
      password: widget.password,
      fileSize: ep['size'] ?? 0,
      nextEpisode: nextEp,
    )));

    if (mounted) setState(() {});

    if (result is Map && result['action'] == 'playNext' && index < allEpisodes.length - 1) {
      final int nextIndex = index + 1;
      _playEpisode(allEpisodes[nextIndex], nextIndex, allEpisodes);
    }
  }
}
