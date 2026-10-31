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

List<DownloadItem> _sortedEpisodes(Iterable<DownloadItem> eps) {
  final list = eps.toList();
  list.sort((a, b) {
    final s = a.seasonNo.compareTo(b.seasonNo);
    if (s != 0) return s;
    final e = a.episodeNo.compareTo(b.episodeNo);
    if (e != 0) return e;
    return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
  });
  return list;
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
      return 'Failed: ${i.error ?? 'unknown error'}';
    case DlStatus.completed:
      return formatBytes(i.total);
  }
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
      if (mounted) setState(() => _ready = true);
    });
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      );

  Widget _activeTile(DownloadItem i) {
    final title = i.isMovie ? i.title : '${i.showName ?? ''} • ${i.title}';
    final poster = i.isMovie ? i.posterFile : (_m.showFor(i.showPath ?? '')?.posterFile ?? i.thumbFile);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _localImage(_m, poster, width: 52, height: 74),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: i.status == DlStatus.failed ? Colors.redAccent : Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          if (i.isActive)
            IconButton(icon: const Icon(Icons.pause_circle_outline, color: Colors.white), onPressed: () => _m.pause(i.id))
          else
            IconButton(icon: Icon(i.status == DlStatus.failed ? Icons.refresh_rounded : Icons.play_circle_outline, color: Colors.white), onPressed: () => _m.resume(i.id)),
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
    final done = eps.where((e) => e.status == DlStatus.completed).length;
    final seasons = eps.map((e) => e.seasonName ?? '').toSet().length;
    final name = show?.name ?? (eps.isNotEmpty ? eps.first.showName ?? '' : '');
    final poster = show?.posterFile;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => DownloadedShowScreen(showPath: showPath))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: _localImage(_m, poster, width: 52, height: 74, fallback: Icons.tv)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('$done of ${eps.length} episodes  •  $seasons season${seasons == 1 ? '' : 's'}', style: const TextStyle(color: _lightPurple, fontSize: 12)),
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
                        final pending = _m.items.where((i) => i.status != DlStatus.completed).toList()
                          ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
                        final movies = _m.movies.where((i) => i.status == DlStatus.completed).toList()
                          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
                        final shows = _m.showPaths.where((sp) => _m.itemsForShow(sp).any((e) => e.status == DlStatus.completed)).toList()
                          ..sort((a, b) => (_m.showFor(a)?.name ?? a).toLowerCase().compareTo((_m.showFor(b)?.name ?? b).toLowerCase()));

                        if (pending.isEmpty && movies.isEmpty && shows.isEmpty) {
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
                            if (pending.isNotEmpty) ...[
                              _sectionTitle('In Progress'),
                              ...pending.map(_activeTile),
                            ],
                            if (shows.isNotEmpty) ...[
                              _sectionTitle('TV Shows'),
                              ...shows.map(_showTile),
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
// Downloaded show (seasons + episodes)
// ====================================================================

class DownloadedShowScreen extends StatelessWidget {
  final String showPath;
  const DownloadedShowScreen({Key? key, required this.showPath}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final m = DownloadManager.instance;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: m,
        builder: (context, _) {
          final show = m.showFor(showPath);
          final all = _sortedEpisodes(m.itemsForShow(showPath));
          final playable = all.where((e) => e.status == DlStatus.completed).toList();
          final name = show?.name ?? (all.isNotEmpty ? all.first.showName ?? '' : '');
          final md = show?.metadata ?? {};
          final description = (md['Description'] ?? md['description'] ?? '').toString();
          final headerImage = m.fileExists(show?.bannerFile) ? show?.bannerFile : show?.posterFile;

          final seasons = <String, List<DownloadItem>>{};
          for (final e in all) {
            seasons.putIfAbsent(e.seasonName ?? 'Episodes', () => []).add(e);
          }

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
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.white70),
                            onPressed: () async {
                              final yes = await confirmDialog(context, 'Delete show?', 'Delete all downloaded episodes of "$name"?');
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
                    child: Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ),
              if (description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(description, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                ),
              ...(seasons.keys.toList()..sort((a, b) => seasonNumberOf(a).compareTo(seasonNumberOf(b)))).expand((season) {
                final eps = seasons[season]!;
                return [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                    child: Text(season, style: const TextStyle(color: _lightPurple, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  ...eps.map((e) => _episodeTile(context, m, e, playable)),
                ];
              }),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _episodeTile(BuildContext context, DownloadManager m, DownloadItem e, List<DownloadItem> playable) {
    final done = e.status == DlStatus.completed;
    return InkWell(
      onTap: done ? () => playDownloadedItem(context, e, playable) : null,
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
                    _localImage(m, e.thumbFile, width: 100, height: 60),
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
                  Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  if (!done)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: LinearProgressIndicator(
                        value: (e.status == DlStatus.downloading && e.total > 0) || e.status == DlStatus.paused ? e.progress : null,
                        minHeight: 3,
                        color: _purple,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  Text(_statusText(e),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: e.status == DlStatus.failed ? Colors.redAccent : Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            if (!done)
              IconButton(
                icon: Icon(e.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline, color: Colors.white),
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
                if (yes) {
                  await m.remove(e.id);
                  if (m.itemsForShow(showPath).isEmpty && context.mounted) Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
