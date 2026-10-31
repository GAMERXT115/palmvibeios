import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'download_manager.dart';
import 'video_player.dart';

const Color _purple = Color(0xFF8A2BE2);
const Color _lightPurple = Color(0xFFB19CD9);

Widget _localImage(DownloadManager m, String? rel, {double? width, double? height, IconData fallback = Icons.movie_outlined}) {
  final placeholder = Container(
    width: width,
    height: height,
    color: Colors.grey[900],
    child: Icon(fallback, color: Colors.white24),
  );
  if (rel == null || !m.fileExists(rel)) return placeholder;
  return Image.file(
    File(m.absPath(rel)),
    width: width,
    height: height,
    fit: BoxFit.cover,
    errorBuilder: (c, e, s) => placeholder,
  );
}

Future<void> playDownloadedItem(BuildContext context, DownloadItem item, List<DownloadItem> queue) async {
  final m = DownloadManager.instance;
  if (item.videoFile == null || !m.fileExists(item.videoFile)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video file is missing. Please download it again.')));
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final idx = queue.indexWhere((e) => e.id == item.id);
  final DownloadItem? next = (idx >= 0 && idx < queue.length - 1) ? queue[idx + 1] : null;
  if (!context.mounted) return;

  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (c) => VideoPlayerScreen(
        videoUrl: m.absPath(item.videoFile!),
        subtitleUrls: item.subtitleFiles.where((s) => m.fileExists(s)).map((s) => m.absPath(s)).toList(),
        title: item.isMovie ? item.title : item.fileName,
        serverIp: prefs.getString('dl_server_ip') ?? prefs.getString('server_ip') ?? '',
        serverPort: prefs.getString('dl_server_port') ?? '8080',
        username: prefs.getString('username') ?? '',
        password: prefs.getString('password') ?? '',
        fileSize: item.total,
        nextEpisode: next == null ? null : {'name': next.fileName, 'path': next.serverPath},
      ),
    ),
  );

  if (result is Map && result['action'] == 'playNext' && next != null && context.mounted) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (context.mounted) await playDownloadedItem(context, next, queue);
  }
}

String _statusText(DownloadItem i) {
  switch (i.status) {
    case DlStatus.queued:
      return 'Waiting…';
    case DlStatus.downloading:
      if (i.total > 0) {
        return '${(i.progress * 100).toStringAsFixed(0)}%  •  ${formatBytes(i.received)} of ${formatBytes(i.total)}';
      }
      return 'Downloading…  ${formatBytes(i.received)}';
    case DlStatus.paused:
      return i.total > 0 ? 'Paused  •  ${(i.progress * 100).toStringAsFixed(0)}%' : 'Paused';
    case DlStatus.failed:
      return i.autoRetry ? '${i.error ?? 'Failed'} — will retry automatically' : 'Failed: ${i.error ?? 'unknown error'}';
    case DlStatus.completed:
      return formatBytes(i.total);
  }
}

double _groupProgress(Iterable<DownloadItem?> items, int total) {
  if (total <= 0) return 0;
  double sum = 0;
  for (final i in items) {
    if (i == null) continue;
    if (i.status == DlStatus.completed) {
      sum += 1;
    } else if (i.total > 0) {
      sum += i.progress;
    }
  }
  return (sum / total).clamp(0.0, 1.0);
}

// ====================================================================
// Downloads screen
// ====================================================================

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({Key? key}) : super(key: key);

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadManager _m = DownloadManager.instance;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _m.ensureInit().then((_) {
      _m.startBackground();
      if (mounted) setState(() => _ready = true);
    });
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      );

  Widget _movieActiveTile(DownloadItem i) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(6), child: _localImage(_m, i.posterFile, width: 52, height: 74)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (i.status == DlStatus.downloading && i.total > 0) || i.status == DlStatus.paused ? i.progress : null,
                    minHeight: 3,
                    color: _purple,
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_statusText(i),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: i.status == DlStatus.failed ? Colors.redAccent : Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          if (i.isActive)
            IconButton(icon: const Icon(Icons.pause_circle_outline, color: Colors.white), onPressed: () => _m.pause(i.id))
          else
            IconButton(
              icon: Icon(i.status == DlStatus.failed ? Icons.refresh_rounded : Icons.play_circle_outline, color: Colors.white),
              onPressed: () => _m.resume(i.id),
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () async {
              final yes = await confirmDialog(context, 'Cancel download?', 'Remove "${i.title}" and its partial data?', confirm: 'REMOVE');
              if (yes) await _m.remove(i.id);
            },
          ),
        ],
      ),
    );
  }

  Widget _movieTile(DownloadItem i) {
    final md = i.metadata ?? {};
    final details = [
      if ((md['year'] ?? '').toString().isNotEmpty) md['year'].toString(),
      if ((md['quality'] ?? '').toString().isNotEmpty) md['quality'].toString(),
      formatBytes(i.total),
    ].join('  •  ');
    return InkWell(
      onTap: () => playDownloadedItem(context, i, const []),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: _localImage(_m, i.posterFile, width: 52, height: 74)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(details, style: const TextStyle(color: _lightPurple, fontSize: 12)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.play_circle_fill, color: _purple, size: 32), onPressed: () => playDownloadedItem(context, i, const [])),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white54),
              onPressed: () async {
                final yes = await confirmDialog(context, 'Delete download?', 'Delete "${i.title}" from this device?');
                if (yes) await _m.remove(i.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _showTile(String showPath) {
    final show = _m.showFor(showPath);
    final eps = _m.itemsForShow(showPath).toList();
    final catalogIds = _m.catalogIds(showPath);
    final total = catalogIds.isNotEmpty ? catalogIds.length : eps.length;
    final done = eps.where((e) => e.status == DlStatus.completed).length;
    final active = eps.any((e) => e.isActive);
    final waiting = eps.any((e) => e.status == DlStatus.failed && e.autoRetry);
    final seasonCount = show != null && show.seasons.isNotEmpty ? show.seasons.length : eps.map((e) => e.seasonName ?? '').toSet().length;
    final name = show?.name ?? (eps.isNotEmpty ? eps.first.showName ?? '' : '');
    final progress = _groupProgress(catalogIds.isNotEmpty ? catalogIds.map(_m.itemFor) : eps, total);

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => DownloadedShowScreen(showPath: showPath))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: _localImage(_m, show?.posterFile, width: 52, height: 74, fallback: Icons.tv)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('$done of $total episodes  •  $seasonCount season${seasonCount == 1 ? '' : 's'}', style: const TextStyle(color: _lightPurple, fontSize: 12)),
                  if (active || waiting) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: active ? progress : null, minHeight: 3, color: _purple, backgroundColor: Colors.white12),
                    ),
                    const SizedBox(height: 4),
                    Text(active ? 'Downloading…' : 'Waiting for connection — will retry automatically',
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  const Text('Downloads', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _m,
                    builder: (c, _) => Text(formatBytes(_m.totalBytesOnDisk), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !_ready
                  ? const Center(child: CircularProgressIndicator(color: Colors.purple))
                  : AnimatedBuilder(
                      animation: _m,
                      builder: (c, _) {
                        // TV episodes never appear individually here: every show is a single entry.
                        final pendingMovies = _m.movies.where((i) => i.status != DlStatus.completed).toList()
                          ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
                        final movies = _m.movies.where((i) => i.status == DlStatus.completed).toList()
                          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
                        final shows = _m.showPaths.toList()
                          ..sort((a, b) => (_m.showFor(a)?.name ?? a).toLowerCase().compareTo((_m.showFor(b)?.name ?? b).toLowerCase()));

                        if (pendingMovies.isEmpty && movies.isEmpty && shows.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.download_for_offline_outlined, color: Colors.white24, size: 64),
                                SizedBox(height: 12),
                                Text('No downloads yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
                              ],
                            ),
                          );
                        }

                        return ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 40),
                          children: [
                            if (shows.isNotEmpty) ...[
                              _sectionTitle('TV Shows'),
                              ...shows.map(_showTile),
                            ],
                            if (pendingMovies.isNotEmpty) ...[
                              _sectionTitle('Movies In Progress'),
                              ...pendingMovies.map(_movieActiveTile),
                            ],
                            if (movies.isNotEmpty) ...[
                              _sectionTitle('Movies'),
                              ...movies.map(_movieTile),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// Show screen: the full episode menu, downloaded or not
// ====================================================================

class _EpRow {
  final String id;
  final String path;
  final String fileName;
  final String title;
  final int size;
  final String season;
  final DownloadItem? item;
  _EpRow({required this.id, required this.path, required this.fileName, required this.title, required this.size, required this.season, required this.item});

  Map<String, dynamic> toServerMap() => {'name': fileName, 'path': path, 'size': size};
}

class DownloadedShowScreen extends StatelessWidget {
  final String showPath;
  const DownloadedShowScreen({Key? key, required this.showPath}) : super(key: key);

  List<MapEntry<String, List<_EpRow>>> _buildSeasons(DownloadManager m, DownloadShow? show) {
    final result = <String, List<_EpRow>>{};
    final knownIds = <String>{};

    if (show != null) {
      for (final s in show.seasons) {
        result[s.name] = s.episodes.map((e) {
          knownIds.add(e.id);
          return _EpRow(id: e.id, path: e.path, fileName: e.name, title: e.title, size: e.size, season: s.name, item: m.itemFor(e.id));
        }).toList();
      }
    }
    // Downloads that are not part of a saved catalog (e.g. downloaded before the catalog existed)
    final extras = m.itemsForShow(showPath).where((i) => !knownIds.contains(i.id)).toList()
      ..sort((a, b) {
        final s = a.seasonNo.compareTo(b.seasonNo);
        return s != 0 ? s : a.episodeNo.compareTo(b.episodeNo);
      });
    for (final i in extras) {
      final season = i.seasonName ?? 'Episodes';
      result.putIfAbsent(season, () => []).add(_EpRow(
        id: i.id,
        path: i.serverPath,
        fileName: i.fileName,
        title: i.title,
        size: i.total,
        season: season,
        item: i,
      ));
    }
    return result.entries.toList();
  }

  Future<void> _queueRows(BuildContext context, DownloadManager m, DownloadShow? show, String showName, List<_EpRow> rows) async {
    if (rows.isEmpty) return;
    final bySeason = <String, List<_EpRow>>{};
    for (final r in rows) {
      bySeason.putIfAbsent(r.season, () => []).add(r);
    }
    for (final entry in bySeason.entries) {
      await m.enqueueEpisodes(
        showName: showName,
        showPath: showPath,
        seasonName: entry.key,
        episodes: entry.value.map((r) => r.toServerMap()).toList(),
        category: show?.category,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = DownloadManager.instance;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: m,
        builder: (context, _) {
          final show = m.showFor(showPath);
          final seasons = _buildSeasons(m, show);
          final allRows = seasons.expand((e) => e.value).toList();
          final playable = allRows.where((r) => r.item?.status == DlStatus.completed).map((r) => r.item!).toList();
          final first = m.itemsForShow(showPath).isNotEmpty ? m.itemsForShow(showPath).first : null;
          final name = show?.name ?? first?.showName ?? '';
          final md = show?.metadata ?? {};
          final description = (md['Description'] ?? md['description'] ?? '').toString();
          final headerImage = m.fileExists(show?.bannerFile) ? show?.bannerFile : show?.posterFile;
          final doneCount = playable.length;

          return ListView(
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            children: [
              Stack(
                children: [
                  SizedBox(height: 260, width: double.infinity, child: _localImage(m, headerImage, height: 260, fallback: Icons.tv)),
                  Container(
                    height: 260,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withOpacity(0.5), Colors.black.withOpacity(0.95)],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                          const Spacer(),
                          DownloadGroupButton(
                            tooltip: 'Download all episodes',
                            size: 26,
                            idsSelector: (mm) => allRows.map((r) => r.id).toList(),
                            onDownload: () => _queueRows(context, m, show, name, allRows),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.white70),
                            onPressed: () async {
                              final yes = await confirmDialog(context, 'Delete show?', 'Delete "$name" and all of its downloaded episodes?');
                              if (yes) {
                                await m.removeShow(showPath);
                                if (context.mounted) Navigator.pop(context);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text('$doneCount of ${allRows.length} episodes downloaded  •  ${seasons.length} season${seasons.length == 1 ? '' : 's'}',
                            style: const TextStyle(color: _lightPurple, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              if (description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(description, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                ),
              if (show != null && show.seasons.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text('The full episode list will appear here once the server can be reached.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              ...seasons.expand((entry) {
                final rows = entry.value;
                return [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(entry.key, style: const TextStyle(color: _lightPurple, fontWeight: FontWeight.bold, fontSize: 15))),
                        DownloadGroupButton(
                          tooltip: 'Download season',
                          size: 22,
                          idsSelector: (mm) => rows.map((r) => r.id).toList(),
                          onDownload: () => _queueRows(context, m, show, name, rows),
                        ),
                      ],
                    ),
                  ),
                  ...rows.map((r) => _episodeTile(context, m, show, name, r, playable)),
                ];
              }),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _episodeTile(BuildContext context, DownloadManager m, DownloadShow? show, String showName, _EpRow r, List<DownloadItem> playable) {
    final e = r.item;
    final done = e?.status == DlStatus.completed;
    final notDownloaded = e == null;
    final thumbRel = show != null && m.fileExists(show.thumbRel(r.id)) ? show.thumbRel(r.id) : e?.thumbFile;

    Future<void> queueThis() async {
      await _queueRows(context, m, show, showName, [r]);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Queued ${r.title}'), duration: const Duration(seconds: 2)));
      }
    }

    return InkWell(
      onTap: done
          ? () => playDownloadedItem(context, e!, playable)
          : (notDownloaded ? queueThis : null),
      child: Opacity(
        opacity: notDownloaded ? 0.4 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                height: 60,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _localImage(m, thumbRel, width: 100, height: 60),
                      if (done) const Center(child: Icon(Icons.play_arrow, color: Colors.white, size: 24)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    if (e != null && !done)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: LinearProgressIndicator(
                          value: (e.status == DlStatus.downloading && e.total > 0) || e.status == DlStatus.paused ? e.progress : null,
                          minHeight: 3,
                          color: _purple,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    Text(
                      e == null ? 'Not downloaded — tap to download' : _statusText(e),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: e?.status == DlStatus.failed ? Colors.redAccent : Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (e == null)
                IconButton(icon: const Icon(Icons.download_rounded, color: Colors.white), onPressed: queueThis)
              else ...[
                if (!done)
                  IconButton(
                    icon: Icon(e.isActive ? Icons.pause_circle_outline : (e.status == DlStatus.failed ? Icons.refresh_rounded : Icons.play_circle_outline), color: Colors.white),
                    onPressed: () => e.isActive ? m.pause(e.id) : m.resume(e.id),
                  ),
                IconButton(
                  icon: Icon(done ? Icons.delete_outline : Icons.close, color: Colors.white54),
                  onPressed: () async {
                    final yes = await confirmDialog(
                      context,
                      done ? 'Delete episode?' : 'Cancel download?',
                      done ? 'Delete "${e.title}" from this device?' : 'Remove "${e.title}" and its partial data?',
                      confirm: done ? 'DELETE' : 'REMOVE',
                    );
                    if (yes) await m.remove(e.id);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
