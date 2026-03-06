import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/article.dart';
import '../services/ad_service.dart';
import '../services/news_service.dart';
import '../services/widget_service.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/native_ad_card.dart';
import '../widgets/news_reel_card.dart';
import '../widgets/source_filter.dart';
import '../widgets/live_pill.dart';
import 'live_screen.dart';
import 'settings_screen.dart';

class ReelsScreen extends StatefulWidget {
  final bool urgentOnly;
  final bool isActive;
  const ReelsScreen({super.key, this.urgentOnly = false, this.isActive = true});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen>
    with TickerProviderStateMixin {
  final _newsService = NewsService();
  final _pageController = PageController();

  List<Article> _articles = [];
  List<NewsSource> _sources = [];
  String _selectedSource = 'all';
  // ValueNotifier: page changes update only card isActive, not the whole screen
  final _pageNotifier = ValueNotifier<int>(0);

  // Pagination
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  Timer? _autoRefreshTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _loadInitial();
    _startAutoRefresh();
  }

  @override
  void didUpdateWidget(ReelsScreen old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _startAutoRefresh();
    } else if (!widget.isActive && old.isActive) {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _autoRefreshTimer?.cancel();
    _pulseController.dispose();
    _pageNotifier.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final results = await Future.wait([
        _newsService.fetchNews(source: _selectedSource, forceRefresh: true, page: 1),
        _newsService.fetchSources(),
      ]);
      if (!mounted) return;
      final resp = results[0] as NewsResponse;
      final sources = results[1] as List<NewsSource>;
      setState(() {
        _articles = _filtered(resp.articles);
        _sources = sources;
        _page = 1;
        _hasMore = resp.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _newsService.fetchNews(
          source: _selectedSource, page: _page + 1);
      if (!mounted) return;
      final existingIds = {for (final a in _articles) a.id};
      final newArticles = result.articles
          .where((a) => !existingIds.contains(a.id))
          .toList();
      setState(() {
        _articles = _filtered([..._articles, ...newArticles]);
        _page = result.page;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final result = await _newsService.fetchNews(
          source: _selectedSource, forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _articles = _filtered(result.articles);
        _refreshing = false;
      });
      if (_articles.isNotEmpty && _pageNotifier.value > 0) {
        _pageController.animateToPage(0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _refreshing = false);
      _showSnack(_friendlyError(e));
    }
  }

  void _startAutoRefresh() {
    if (_autoRefreshTimer != null) return; // already running
    if (!widget.isActive) return;
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_refreshing) _silentRefresh();
    });
  }

  Future<void> _silentRefresh() async {
    try {
      final result =
          await _newsService.fetchNews(source: _selectedSource);
      if (!mounted) return;
      final newCount = result.articles.where((a) => a.isNew).length;
      if (newCount > 0) {
        setState(() => _articles = _filtered(result.articles));
        _showSnack('$newCount new articles');
      }
      // Keep home screen widget in sync with latest headline
      WidgetService.update();
    } catch (_) {}
  }

  Future<void> _changeSource(String source) async {
    if (source == _selectedSource) return;
    _newsService.clearCache();
    setState(() {
      _selectedSource = source;
      _articles = [];
      _loading = true;
      _error = null;
      _page = 1;
      _hasMore = false;
    });
    _pageController.jumpToPage(0);
    _pageNotifier.value = 0;
    try {
      final result = await _newsService.fetchNews(
          source: source, forceRefresh: true, page: 1);
      if (!mounted) return;
      setState(() {
        _articles = _filtered(result.articles);
        _page = 1;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  // ── Urgent filter ─────────────────────────────────────────────────────────

  List<Article> _filtered(List<Article> articles) {
    if (!widget.urgentOnly) return articles;
    final cutoff = DateTime.now().subtract(const Duration(hours: 3));
    return articles.where((a) =>
      a.pubDate.isAfter(cutoff) ||
      a.title.contains('عاجل') ||
      a.title.toLowerCase().contains('breaking')
    ).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') ||
        msg.contains('Connection refused')) {
      return 'Cannot connect to server.';
    }
    if (msg.contains('TimeoutException') || msg.contains('Timeout')) {
      return 'Server took too long to respond.';
    }
    return 'Something went wrong:\n$msg';
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF1a1a2e),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Banner ad anchored at the bottom
      bottomNavigationBar: const BannerAdWidget(),
      body: Stack(
        children: [
          _buildBody(),
          _buildHeader(),
          if (_refreshing) _buildRefreshBadge(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildSkeleton();
    if (_error != null) return _buildError();
    if (_articles.isEmpty) return _buildEmpty();

    // Inject native ad sentinels every 8 articles
    final injected = AdService.injectAdSlots(_articles);
    final totalItems = injected.length + (_loadingMore ? 1 : 0);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: Colors.white,
      backgroundColor: const Color(0xFF1a1a2e),
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        physics: const ClampingScrollPhysics(),
        onPageChanged: (i) {
          _pageNotifier.value = i;
          // Trigger load-more when close to the real article list end
          if (i >= injected.length - 10) {
            if (_hasMore) { _loadMore(); }
            else { _silentRefresh(); }
          }
        },
        itemCount: totalItems,
        itemBuilder: (context, i) {
          // Loading spinner at very end
          if (i == injected.length) {
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
          final item = injected[i];
          // Native ad slot
          if (item == AdService.adSentinel) {
            return const Center(child: NativeAdCard());
          }
          final article = item as Article;
          return RepaintBoundary(
            child: ValueListenableBuilder<int>(
              valueListenable: _pageNotifier,
              builder: (_, page, __) => NewsReelCard(
                article: article,
                isActive: i == page,
                pageIndex: i,
                totalPages: _articles.length,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xEE000000),
              Color(0x99000000),
              Colors.transparent
            ],
            stops: [0.0, 0.75, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'كل دقيقة',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: Color(0xFFe74c3c),
                          shape: BoxShape.circle),
                    ),
                    const Spacer(),
                    // ── TikTok-style LIVE pill ─────────────────────────
                    LivePill(onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LiveScreen()),
                    )),
                    // Refresh
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, child) => Opacity(
                        opacity: _refreshing
                            ? 0.4 + 0.6 * _pulseController.value
                            : 1.0,
                        child: child,
                      ),
                      child: IconButton(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 40, minHeight: 40),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      ),
                      icon: const Icon(Icons.settings_outlined,
                          color: Colors.white, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 40, minHeight: 40),
                    ),
                  ],
                ),
              ),
              if (_sources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 10),
                  child: SourceFilter(
                    sources: _sources,
                    selected: _selectedSource,
                    onSelected: _changeSource,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshBadge() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 110,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text('جارٍ التحديث…',
                  style: GoogleFonts.cairo(
                      color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty / error / loading states ────────────────────────────────────────

  Widget _buildSkeleton() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Text('جارٍ تحميل الأخبار…',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                    color: Colors.white70, fontSize: 17, height: 1.6)),
          ],
        ),
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: Colors.red, size: 64),
              const SizedBox(height: 20),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _loadInitial,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2c3e50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📰', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            const Text(
              'No articles yet.\nThe server may still be loading.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 16),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _refresh,
              child: const Text('Refresh',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
}

