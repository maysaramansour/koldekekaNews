import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/video.dart';
import '../services/video_service.dart';
import '../services/video_stream_cache.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/video_reel_card.dart';
import '../widgets/live_pill.dart';
import 'live_screen.dart';

class VideoReelsScreen extends StatefulWidget {
  final bool isActive;
  const VideoReelsScreen({super.key, this.isActive = true});

  @override
  State<VideoReelsScreen> createState() => _VideoReelsScreenState();
}

class _VideoReelsScreenState extends State<VideoReelsScreen> {
  final _service        = VideoService();
  final _pageController = PageController();

  List<Video>                  _videos      = [];
  List<Map<String, dynamic>>   _channels    = [];
  String                       _selected    = 'all';
  int                          _current     = 0;
  bool                         _loading     = true;
  bool                         _loadingMore = false;
  String?                      _error;

  // Pagination
  int  _page    = 1;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Initial load (page 1) ─────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _page = 1; _hasMore = false; });
    try {
      final results = await Future.wait([
        _service.fetchVideos(channel: _selected, page: 1),
        _service.fetchChannels(),
      ]);
      final resp     = results[0] as VideoResponse;
      final channels = results[1] as List<Map<String, dynamic>>;
      if (!mounted) return;
      setState(() {
        _videos      = resp.videos;
        _channels    = channels;
        _page        = resp.page;
        _hasMore     = resp.hasMore;
        _loading     = false;
        _current     = 0;
      });
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      // Pre-warm stream URLs for first 3 in a background isolate
      VideoStreamCache.warmUp(resp.videos.map((v) => v.videoId).toList(), from: 0, count: 3);
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Load next page (10 more videos) ──────────────────────────────────────
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final resp = await _service.fetchVideos(
          channel: _selected, page: _page + 1);
      if (!mounted) return;
      final existingIds = {for (final v in _videos) v.videoId};
      final newVideos = resp.videos
          .where((v) => !existingIds.contains(v.videoId))
          .toList();
      setState(() {
        _videos      = [..._videos, ...newVideos];
        _page        = resp.page;
        _hasMore     = resp.hasMore;
        _loadingMore = false;
      });
      // Pre-warm stream URLs for newly added videos
      final allIds = _videos.map((v) => v.videoId).toList();
      VideoStreamCache.warmUp(allIds,
          from: _videos.length - newVideos.length, count: newVideos.length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _changeChannel(String ch) async {
    if (ch == _selected) return;
    VideoStreamCache.clear();
    setState(() => _selected = ch);
    await _load();
  }

  void _prefetchAhead(int from, {int count = 3}) {
    final ids = _videos.map((v) => v.videoId).toList();
    VideoStreamCache.warmUp(ids, from: from, count: count);
  }

  @override
  Widget build(BuildContext context) {
    final routeActive = ModalRoute.of(context)?.isCurrent ?? true;
    _effectiveActive = widget.isActive && routeActive;

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: const BannerAdWidget(),
      body: Stack(
        children: [
          _buildBody(),
          _buildHeader(),
        ],
      ),
    );
  }

  bool _effectiveActive = true;

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white38));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            Text('Cannot connect to server.',
                style: GoogleFonts.cairo(color: Colors.white70, fontSize: 15),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text('Try Again', style: GoogleFonts.cairo()),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_library_outlined,
                color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(
              'No videos yet.\nServer may still be loading.',
              style: GoogleFonts.cairo(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, color: Colors.white70),
              label: Text('Refresh',
                  style: GoogleFonts.cairo(color: Colors.white70)),
            ),
          ],
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: _videos.length + (_loadingMore ? 1 : 0),
      onPageChanged: (i) {
        setState(() => _current = i);
        _prefetchAhead(i + 1, count: 3);
        final ids = _videos.map((v) => v.videoId).toList();
        VideoStreamCache.evictDistant(i, ids);
        // Trigger next page when 5 from end
        if (i >= _videos.length - 5) {
          if (_hasMore) { _loadMore(); }
        }
      },
      itemBuilder: (context, i) {
        // Loading spinner page at the end
        if (i == _videos.length) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white54),
                SizedBox(height: 12),
                Text('جارٍ تحميل المزيد…',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
              ],
            ),
          );
        }
        return VideoReelCard(
          video: _videos[i],
          isActive: _effectiveActive && i == _current,
          pageIndex: i,
          totalPages: _videos.length,
        );
      },
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() => Positioned(
        top: 0, left: 0, right: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Colors.transparent],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.smart_display_rounded,
                          color: Color(0xFFFF0000), size: 26),
                      const SizedBox(width: 8),
                      Text(
                        'كل دقيقة',
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(
                            color: Color(0xFFFF0000),
                            shape: BoxShape.circle),
                      ),
                      const Spacer(),
                      LivePill(onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LiveScreen()),
                      )),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white70, size: 22),
                        onPressed: _load,
                      ),
                    ],
                  ),
                ),
                if (_channels.isNotEmpty) _buildChannelFilter(),
              ],
            ),
          ),
        ),
      );

  Widget _buildChannelFilter() {
    final all = <Map<String, dynamic>>[
      {'name': 'all', 'color': '#888888'},
      ..._channels,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: all.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final ch   = all[i];
            final name = ch['name'] as String;
            final sel  = name == _selected;
            Color chip = Colors.grey;
            try {
              chip = Color(
                  int.parse((ch['color'] as String).replaceFirst('#', '0xFF')));
            } catch (_) {}

            return GestureDetector(
              onTap: () => _changeChannel(name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? chip : Colors.black38,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? chip : Colors.white24, width: 1.5),
                ),
                child: Text(
                  name == 'all' ? 'الكل' : name,
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
