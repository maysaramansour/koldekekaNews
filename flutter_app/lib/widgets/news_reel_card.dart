import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../models/article.dart';
import '../screens/article_screen.dart';
import '../services/ad_service.dart';
import 'article_webview.dart';

class NewsReelCard extends StatefulWidget {
  final Article article;
  final bool isActive;
  final int pageIndex;
  final int totalPages;

  const NewsReelCard({
    super.key,
    required this.article,
    required this.isActive,
    required this.pageIndex,
    required this.totalPages,
  });

  @override
  State<NewsReelCard> createState() => _NewsReelCardState();
}

class _NewsReelCardState extends State<NewsReelCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  // Interstitial ad — preloaded, shown once when article is opened
  InterstitialAd? _interstitial;
  static int _articleOpenCount = 0; // show ad every 3 article opens

  // OG image cache — fetched lazily when no real RSS thumbnail available
  static final Map<String, String?> _ogCache = {};
  String? _ogImage; // fetched OG image for this article

  void _preloadInterstitial() {
    AdService.loadInterstitial(onLoaded: (ad) {
      _interstitial = ad;
    });
  }

  // Fetch the article page's og:image when no real RSS thumbnail is available
  Future<void> _fetchOgImage() async {
    if (!widget.article.aiImage) return; // already has a real RSS image
    final url = widget.article.link;
    if (url.isEmpty) return;
    if (_ogCache.containsKey(url)) {
      if (mounted && _ogCache[url] != null) {
        setState(() => _ogImage = _ogCache[url]);
      }
      return;
    }
    try {
      final resp = await http.get(Uri.parse(url),
          headers: {'Accept': 'text/html'}).timeout(const Duration(seconds: 6));
      final body = resp.body;
      // Try og:image first, then twitter:image
      final ogMatch = RegExp(
        r'''<meta[^>]+property=["']og:image["'][^>]+content=["'](https?://[^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(body) ?? RegExp(
        r'''<meta[^>]+content=["'](https?://[^"']+)["'][^>]+property=["']og:image["']''',
        caseSensitive: false,
      ).firstMatch(body) ?? RegExp(
        r'''<meta[^>]+name=["']twitter:image["'][^>]+content=["'](https?://[^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(body);
      final img = ogMatch?.group(1);
      _ogCache[url] = img;
      if (mounted && img != null) setState(() => _ogImage = img);
    } catch (_) {
      _ogCache[url] = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));
    _fadeAnim = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeIn,
    );
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _slideController.forward(from: 0);
          _preloadInterstitial();
          _fetchOgImage();
        }
      });
    }
  }

  @override
  void didUpdateWidget(NewsReelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _slideController.forward(from: 0);
      if (_interstitial == null) _preloadInterstitial();
      _fetchOgImage();
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _interstitial?.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  bool get _isAr => widget.article.isArabic;
  TextDirection get _dir =>
      _isAr ? TextDirection.rtl : TextDirection.ltr;

  Future<void> _openArticle() async {
    _articleOpenCount++;
    // Show interstitial every 3 article opens
    if (_articleOpenCount % 3 == 0 && _interstitial != null) {
      _interstitial!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitial = null;
          _preloadInterstitial(); // preload next one
          if (mounted) _navigateToArticle();
        },
        onAdFailedToShowFullScreenContent: (ad, _) {
          ad.dispose();
          _interstitial = null;
          if (mounted) _navigateToArticle();
        },
      );
      await _interstitial!.show();
    } else {
      _navigateToArticle();
    }
  }

  void _navigateToArticle() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => ArticleScreen(article: widget.article),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _openInBrowser() async {
    if (widget.article.link.isNotEmpty && mounted) {
      await ArticleWebView.show(
        context,
        widget.article.link,
        title: widget.article.title,
      );
    }
  }

  void _share() {
    Share.share(
      '${widget.article.title}\n\n${widget.article.link}',
      subject: widget.article.title,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final size = MediaQuery.of(context).size;

    return GestureDetector(
      onTap: _openArticle,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background image ────────────────────────────────────────────
            _buildBackground(article),

            // ── Dark gradient overlay ───────────────────────────────────────
            _buildGradient(article),

            // ── Content ─────────────────────────────────────────────────────
            _buildContent(article),

            // ── Right action sidebar ─────────────────────────────────────────
            _buildSidebar(),

            // ── Progress bar ─────────────────────────────────────────────────
            _buildProgressBar(),

            // ── New badge ────────────────────────────────────────────────────
            if (article.isNew) _buildNewBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(Article article) {
    // Priority: fetched OG image > real RSS image > fallback gradient
    final imageUrl = _ogImage ??
        (!article.aiImage && article.image != null && article.image!.isNotEmpty
            ? article.image
            : null);
    if (imageUrl != null) {
      return ColoredBox(
        color: Colors.black,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          fadeInDuration: const Duration(milliseconds: 300),
          placeholder: (_, __) => _fallbackBackground(article),
          errorWidget: (_, __, ___) => _buildBackground_fallbackOrAi(article),
        ),
      );
    }
    return _fallbackBackground(article);
  }

  // When real/OG image fails, try AI image before falling back to gradient
  Widget _buildBackground_fallbackOrAi(Article article) {
    if (article.aiImage && article.image != null && article.image!.isNotEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: CachedNetworkImage(
          imageUrl: article.image!,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          fadeInDuration: const Duration(milliseconds: 300),
          placeholder: (_, __) => _fallbackBackground(article),
          errorWidget: (_, __, ___) => _fallbackBackground(article),
        ),
      );
    }
    return _fallbackBackground(article);
  }

  Widget _fallbackBackground(Article article) {
    // Abbreviate source name: first word, max 4 code units
    final first = article.source.split(' ').first;
    final abbr  = (first.length > 4 ? first.substring(0, 4) : first).toUpperCase();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            article.sourceColor.withValues(alpha: 0.85),
            article.sourceColor.withValues(alpha: 0.35),
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final badgeSize = constraints.maxWidth * 0.42;
            final fontSize  = badgeSize * 0.38;
            return Container(
              width:  badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.25),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.20),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                abbr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGradient(Article article) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.35, 0.6, 1.0],
          colors: [
            Colors.black.withOpacity(0.3),
            Colors.transparent,
            Colors.black.withOpacity(0.5),
            Colors.black.withOpacity(0.92),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Article article) {
    return Positioned(
      left: 16,
      right: 72, // leave room for sidebar
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Directionality(
            textDirection: _dir,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Source chip
                    _buildSourceChip(article),
                    const SizedBox(height: 10),

                    // Title
                    Text(
                      article.title,
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: _isAr ? 20 : 19,
                        fontWeight: FontWeight.bold,
                        height: 1.35,
                        shadows: const [
                          Shadow(
                              blurRadius: 6,
                              color: Colors.black54,
                              offset: Offset(0, 2))
                        ],
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Description (if any)
                    if (article.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        article.description,
                        style: GoogleFonts.cairo(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.45,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Time + "Read more"
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            size: 13, color: Colors.white54),
                        const SizedBox(width: 4),
                        Text(
                          _isAr ? article.timeAgoAr : article.timeAgo,
                          style: GoogleFonts.cairo(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                        if (article.domain.isNotEmpty)
                          Text(
                            article.domain,
                            style: GoogleFonts.cairo(
                                color: Colors.white38, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _openArticle,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.3)),
                            ),
                            child: Text(
                              _isAr ? 'اقرأ المزيد' : 'Read more',
                              style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourceChip(Article article) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: article.sourceColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        article.source,
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Positioned(
      right: 8,
      bottom: 80,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sidebarBtn(
              icon: Icons.share_rounded,
              label: _isAr ? 'مشاركة' : 'Share',
              onTap: _share,
            ),
            const SizedBox(height: 20),
            _sidebarBtn(
              icon: Icons.open_in_browser_rounded,
              label: _isAr ? 'فتح' : 'Open',
              onTap: _openInBrowser,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.cairo(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Positioned(
      right: 0,
      top: MediaQuery.of(context).padding.top + 160,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.35,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.totalPages.clamp(0, 20),
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 1.5),
              width: 3,
              height: i == widget.pageIndex ? 20 : 6,
              decoration: BoxDecoration(
                color: i == widget.pageIndex
                    ? Colors.white
                    : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewBadge() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 130,
      left: 16,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'NEW',
          style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1),
        ),
      ),
    );
  }
}
