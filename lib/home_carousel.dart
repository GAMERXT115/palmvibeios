import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

class HomeCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> recentlyAddedMovies;
  final Function(Map<String, dynamic>) getPosterUrl;
  final String authHeader;
  final Function() buildShimmerEffect;
  final Function(Map<String, dynamic>) playVideo;
  final Function(String) navigateToFolder;
  final Function() onUserInteractionStart;
  final Function() onUserInteractionEnd;
  final List<Map<String, dynamic>> watchlist;
  final Function(Map<String, dynamic>) onToggleWatchlist;

  const HomeCarousel({
    Key? key,
    required this.recentlyAddedMovies,
    required this.getPosterUrl,
    required this.authHeader,
    required this.buildShimmerEffect,
    required this.playVideo,
    required this.navigateToFolder,
    required this.onUserInteractionStart,
    required this.onUserInteractionEnd,
    required this.watchlist,
    required this.onToggleWatchlist,
  }) : super(key: key);

  @override
  _HomeCarouselState createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel> {
  late PageController _carouselController;
  Timer? _autoSlideTimer;
  final int _infiniteStart = 5000;
  late double _pageOffset;

  @override
  void initState() {
    super.initState();
    _pageOffset = _infiniteStart.toDouble();
    _carouselController = PageController(
      viewportFraction: 0.55,
      initialPage: _infiniteStart,
    )..addListener(() {
        if (_carouselController.hasClients) {
          setState(() {
            _pageOffset = _carouselController.page!;
          });
        }
      });
    _startAutoSlideTimer();
  }

  void _startAutoSlideTimer() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (widget.recentlyAddedMovies.isNotEmpty && mounted) {
        _carouselController.nextPage(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.recentlyAddedMovies.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 250,
      width: double.infinity,
      child: PageView.builder(
        controller: _carouselController,
        clipBehavior: Clip.none,
        onPageChanged: (index) {
          widget.onUserInteractionStart();
          _startAutoSlideTimer();
        },
        itemBuilder: (context, index) {
          final realIndex = index % widget.recentlyAddedMovies.length;
          final movie = widget.recentlyAddedMovies[realIndex];
          final posterUrl = widget.getPosterUrl(movie);
          final title = movie['folderName'] ?? path.basenameWithoutExtension(movie['name'] ?? '');
          final bool isInWatchlist = widget.watchlist.any((item) => item['path'] == movie['path']);
          
          double difference = index - _pageOffset;
          
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(difference * 1.8)
              ..scale(1 - (difference.abs() * 0.1)),
            alignment: Alignment.center,
            child: Opacity(
              opacity: (1 - (difference.abs() * 0.3)).clamp(0.5, 1.0),
              child: GestureDetector(
                onTap: () => widget.playVideo(movie),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8A2BE2).withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          posterUrl,
                          headers: {'Authorization': widget.authHeader},
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(color: Colors.black),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 15,
                          bottom: 15,
                          right: 15,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () => widget.playVideo(movie),
                                    icon: const Icon(Icons.play_circle_fill, color: Colors.white, size: 30),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 15),
                                  IconButton(
                                    onPressed: () => widget.onToggleWatchlist(movie),
                                    icon: Icon(isInWatchlist ? Icons.check_circle : Icons.add_circle_outline, color: Colors.white, size: 26),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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
  void dispose() {
    _autoSlideTimer?.cancel();
    _carouselController.dispose();
    super.dispose();
  }
}
