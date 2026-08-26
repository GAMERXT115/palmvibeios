import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'video_progress_manager.dart';

class MoviesGridWidget extends StatefulWidget {
  final List<Map<String, dynamic>> movies;
  final int currentPage;
  final int itemsPerPage;
  final int totalPages;
  final Function(Map<String, dynamic>) getPosterUrl;
  final String authHeader;
  final Function() buildShimmerEffect;
  final Function(Map<String, dynamic>) playVideo;
  final Function() nextPage;
  final Function() previousPage;
  final String serverIp;
  final String serverPort;
  final List<Map<String, dynamic>> watchlist;
  final Function(Map<String, dynamic>) onToggleWatchlist;
  final String username;

  const MoviesGridWidget({
    Key? key,
    required this.movies,
    required this.currentPage,
    required this.itemsPerPage,
    required this.totalPages,
    required this.getPosterUrl,
    required this.authHeader,
    required this.buildShimmerEffect,
    required this.playVideo,
    required this.nextPage,
    required this.previousPage,
    required this.serverIp,
    required this.serverPort,
    required this.watchlist,
    required this.onToggleWatchlist,
    required this.username,
  }) : super(key: key);

  @override
  State<MoviesGridWidget> createState() => _MoviesGridWidgetState();
}

class _MoviesGridWidgetState extends State<MoviesGridWidget> {
  void _showMovieDetails(BuildContext context, Map<String, dynamic> movie) {
    showDialog(
      context: context,
      builder: (context) => MovieDetailsModal(
        movie: movie,
        baseUrl: 'http://${widget.serverIp}:${widget.serverPort}',
        authHeader: widget.authHeader,
        onPlay: widget.playVideo,
        watchlist: widget.watchlist,
        onToggleWatchlist: widget.onToggleWatchlist,
        serverIp: widget.serverIp,
        serverPort: widget.serverPort,
        username: widget.username,
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(
            'Movies',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.65,
            crossAxisSpacing: 10,
            mainAxisSpacing: 15,
          ),
          itemCount: widget.movies.length,
          itemBuilder: (context, index) {
            final movie = widget.movies[index];
            return MovieCard(
              movie: movie,
              getPosterUrl: widget.getPosterUrl,
              authHeader: widget.authHeader,
              buildShimmerEffect: widget.buildShimmerEffect,
              onTap: () => _showMovieDetails(context, movie),
              serverIp: widget.serverIp,
              serverPort: widget.serverPort,
              username: widget.username,
            );
          },
        ),
        if (widget.totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: widget.currentPage > 0 ? widget.previousPage : null,
                  icon: const Icon(Icons.arrow_back_ios, size: 16),
                ),
                const SizedBox(width: 20),
                Text(
                  'Page ${widget.currentPage + 1} of ${widget.totalPages}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(width: 20),
                IconButton(
                  onPressed: widget.currentPage < widget.totalPages - 1 ? widget.nextPage : null,
                  icon: const Icon(Icons.arrow_forward_ios, size: 16),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class MovieCard extends StatefulWidget {
  final Map<String, dynamic> movie;
  final Function(Map<String, dynamic>) getPosterUrl;
  final String authHeader;
  final Function() buildShimmerEffect;
  final VoidCallback onTap;
  final String serverIp;
  final String serverPort;
  final String username;

  const MovieCard({
    Key? key,
    required this.movie,
    required this.getPosterUrl,
    required this.authHeader,
    required this.buildShimmerEffect,
    required this.onTap,
    required this.serverIp,
    required this.serverPort,
    required this.username,
  }) : super(key: key);

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final String itemPath = widget.movie['path'] ?? '';
    if (itemPath.contains('2COMINGSOON')) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _getCountdown(String releaseDate) {
    try {
      final monthsMap = {
        'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6,
        'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12
      };

      List<String> parts = releaseDate.toLowerCase().split(' ');
      if (parts.length < 3) return releaseDate;

      int? month = monthsMap[parts[0]];
      int? day = int.tryParse(parts[1]);
      int? year = int.tryParse(parts[2]);

      if (month == null || day == null || year == null) return releaseDate;

      DateTime releaseDateTime = DateTime(year, month, day, 0, 0, 0);
      DateTime now = DateTime.now();
      Duration diff = releaseDateTime.difference(now);

      if (diff.isNegative) return "RELEASED";

      if (diff.inDays >= 365) {
        int years = (diff.inDays / 365).floor();
        return "In $years Year${years > 1 ? 's' : ''}";
      }
      if (diff.inDays >= 30) {
        int months = (diff.inDays / 30).floor();
        return "In $months Month${months > 1 ? 's' : ''}";
      }
      if (diff.inDays >= 1) {
        return "In ${diff.inDays} Day${diff.inDays > 1 ? 's' : ''}";
      }
      if (diff.inHours >= 1) {
        return "In ${diff.inHours} Hour${diff.inHours > 1 ? 's' : ''}";
      }
      if (diff.inMinutes >= 1) {
        return "In ${diff.inMinutes} Minute${diff.inMinutes > 1 ? 's' : ''}";
      }
      return "In ${diff.inSeconds} Second${diff.inSeconds > 1 ? 's' : ''}";
    } catch (e) {
      return releaseDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String itemPath = widget.movie['path'] ?? '';
    String title = path.basenameWithoutExtension(itemPath);

    if (widget.movie['type'] == 'file') {
      String parent = path.basename(path.dirname(itemPath));
      List<String> rootFolders = ['Movies', 'Bollywood', 'Hollywood', '1RECENTLY ADDED', '2COMINGSOON', 'Marvel', 'DC'];
      if (!rootFolders.contains(parent) && parent.isNotEmpty) {
        title = parent;
      }
    }

    final posterUrl = widget.getPosterUrl(widget.movie);
    final String? year = widget.movie['year']?.toString();
    final String? releaseDateStr = widget.movie['release']?.toString();
    final bool isComingSoon = itemPath.contains('2COMINGSOON');

    String displayLabel = "";
    bool isReleased = false;

    if (isComingSoon && releaseDateStr != null) {
      displayLabel = _getCountdown(releaseDateStr);
      isReleased = displayLabel == "RELEASED";
    } else if (year != null) {
      displayLabel = year;
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10, width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      posterUrl,
                      headers: {'Authorization': widget.authHeader, 'ngrok-skip-browser-warning': 'true'},
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Container(color: Colors.grey[900]),
                    ),
                    if (displayLabel.isNotEmpty)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isReleased ? const Color(0xFF8A2BE2) : Colors.black.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            displayLabel,
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    FutureBuilder<VideoProgress?>(
                      future: VideoProgressManager.getProgress(
                        videoPath: itemPath,
                        title: title,
                        serverIp: widget.serverIp,
                        serverPort: widget.serverPort,
                        authHeader: widget.authHeader,
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
                                      decoration: const BoxDecoration(color: Color(0xFF8A2BE2)),
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
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class MovieDetailsModal extends StatefulWidget {
  final Map<String, dynamic> movie;
  final String baseUrl;
  final String authHeader;
  final Function(Map<String, dynamic>) onPlay;
  final List<Map<String, dynamic>> watchlist;
  final Function(Map<String, dynamic>) onToggleWatchlist;
  final String serverIp;
  final String serverPort;
  final String username;

  const MovieDetailsModal({
    Key? key,
    required this.movie,
    required this.baseUrl,
    required this.authHeader,
    required this.onPlay,
    required this.watchlist,
    required this.onToggleWatchlist,
    required this.serverIp,
    required this.serverPort,
    required this.username,
  }) : super(key: key);

  @override
  _MovieDetailsModalState createState() => _MovieDetailsModalState();
}

class _MovieDetailsModalState extends State<MovieDetailsModal> {
  Map<String, dynamic>? _assets;
  bool _isLoading = true;
  bool _isPlayingTrailer = false;
  String? _trailerLocalUrl;
  HttpServer? _localTrailerServer;
  final List<String> _timeStamps = ['00:10:00', '00:25:00', '00:45:00', '01:05:00', '01:25:00'];

  @override
  void initState() {
    super.initState();
    _fetchAssets();
  }

  Future<void> _fetchAssets() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/api/movie-assets').replace(queryParameters: {
        'path': widget.movie['path'],
      });
      final response = await http.get(uri, headers: {
        'Authorization': widget.authHeader,
        'ngrok-skip-browser-warning': 'true',
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _assets = data;
          _isLoading = false;
        });
        _setupTrailer(data);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupTrailer(Map<String, dynamic> data) {
    final metadata = data['metadata'] ?? {};
    String? trailerUrl = metadata['trailer'] ?? data['trailer'] ?? metadata['Trailer'];
    if (trailerUrl == null) return;

    final videoId = YoutubePlayer.convertUrlToId(trailerUrl);
    if (videoId == null) return;

    _startLocalTrailerServer(videoId);
  }

  Future<void> _startLocalTrailerServer(String videoId) async {
    try {
      final html = '''
      <!DOCTYPE html>
      <html>
      <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        html, body { margin:0; padding:0; background:#000; overflow:hidden; }
        iframe { position:absolute; top:0; left:0; width:100%; height:100%; border:0; }
      </style>
      </head>
      <body>
      <iframe
        src="https://www.youtube.com/embed/$videoId?autoplay=1&mute=0&loop=1&playlist=$videoId&rel=0&enablejsapi=1"
        allow="autoplay; encrypted-media; fullscreen"
        allowfullscreen>
      </iframe>
      </body>
      </html>
      ''';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _localTrailerServer = server;
      server.listen((request) {
        request.response
          ..headers.contentType = ContentType.html
          ..write(html);
        request.response.close();
      });

      if (mounted) {
        setState(() {
          _trailerLocalUrl = 'http://127.0.0.1:${server.port}/trailer';
          _isPlayingTrailer = true;
        });
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    _localTrailerServer?.close(force: true);
    super.dispose();
  }

  void _showFullScreenImage(String url, int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.9),
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) {
          return GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: Hero(
                  tag: 'scene_$index',
                  child: InteractiveViewer(
                    child: Image.network(
                      url,
                      headers: {'Authorization': widget.authHeader, 'ngrok-skip-browser-warning': 'true'},
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metadata = _assets?['metadata'] ?? {};
    final bannerPath = _assets?['banner'] ?? widget.movie['path'];
    final bannerUrl = '${widget.baseUrl}/api/poster?path=${Uri.encodeComponent(bannerPath)}';
    final bool isInWatchlist = widget.watchlist.any((item) => item['path'] == widget.movie['path']);
    final bool isComingSoon = widget.movie['path']?.contains('2COMINGSOON') ?? false;

    String displayName = path.basenameWithoutExtension(widget.movie['path'] ?? '');

    return Dialog(
      backgroundColor: const Color(0xFF111111),
      insetPadding: const EdgeInsets.all(15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                    color: Colors.black,
                  ),
                  child: _isPlayingTrailer && _trailerLocalUrl != null
                      ? ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                          child: InAppWebView(
                            initialUrlRequest: URLRequest(url: WebUri(_trailerLocalUrl!)),
                            initialSettings: InAppWebViewSettings(
                              mediaPlaybackRequiresUserGesture: false,
                              transparentBackground: true,
                            ),
                            onReceivedError: (controller, request, error) {
                              if (mounted) {
                                setState(() => _isPlayingTrailer = false);
                              }
                            },
                          ),
                        )
                      : Image.network(
                          bannerUrl,
                          headers: {'Authorization': widget.authHeader, 'ngrok-skip-browser-warning': 'true'},
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(color: Colors.black),
                        ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 5),
                  Text(
                    isComingSoon 
                      ? (metadata['release'] ?? 'Release Date TBD')
                      : '${metadata['year'] ?? ''} • ${metadata['quality'] ?? 'HD'}',
                    style: const TextStyle(color: Color(0xFFB19CD9), fontSize: 13),
                  ),
                  const SizedBox(height: 15),
                  Text(metadata['description'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      if (!isComingSoon)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onPlay(widget.movie);
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('PLAY'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                          ),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            widget.onToggleWatchlist(widget.movie);
                            setState(() {});
                          },
                          icon: Icon(isInWatchlist ? Icons.check : Icons.add),
                          label: const Text('WATCHLIST'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  if (!isComingSoon) ...[
                    const SizedBox(height: 30),
                    const Text('SCENES', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    const SizedBox(height: 15),
                    SizedBox(
                      height: 110,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _timeStamps.length,
                        itemBuilder: (context, index) {
                          final thumbUrl = '${widget.baseUrl}/api/thumbnail?path=${Uri.encodeComponent(widget.movie['path'])}&time=${_timeStamps[index]}&auth=${widget.authHeader.split(' ').last}';
                          return GestureDetector(
                            onTap: () => _showFullScreenImage(thumbUrl, index),
                            child: Container(
                              width: 180,
                              margin: const EdgeInsets.only(right: 12),
                              child: Hero(
                                tag: 'scene_$index',
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white10),
                                    image: DecorationImage(
                                      image: NetworkImage(thumbUrl),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
