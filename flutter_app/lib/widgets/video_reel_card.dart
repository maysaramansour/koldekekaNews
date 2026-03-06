import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../models/video.dart';
import '../services/video_stream_cache.dart';

class VideoReelCard extends StatefulWidget {
  final Video video;
  final bool isActive;
  final int pageIndex;
  final int totalPages;

  const VideoReelCard({
    super.key,
    required this.video,
    required this.isActive,
    required this.pageIndex,
    required this.totalPages,
  });

  @override
  State<VideoReelCard> createState() => _VideoReelCardState();
}

class _VideoReelCardState extends State<VideoReelCard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ── Animation ──────────────────────────────────────────────────────────────
  late AnimationController _slideCtrl;
  late Animation<Offset>   _slideAnim;
  late Animation<double>   _fadeAnim;

  // ── Player ─────────────────────────────────────────────────────────────────
  VideoPlayerController? _ctrl;
  bool _loadingStream = false;
  bool _streamError   = false;
  bool _showControls  = true;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeIn);

    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      _slideCtrl.forward(from: 0);
      _initPlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _ctrl?.pause();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      _ctrl?.play();
    }
  }

  @override
  void didUpdateWidget(VideoReelCard old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _slideCtrl.forward(from: 0);
      if (_ctrl == null) {
        _initPlayer();
      } else {
        _ctrl!.play();
      }
    } else if (!widget.isActive && old.isActive) {
      _ctrl?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.pause();
    _slideCtrl.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    if (_loadingStream || _ctrl != null) return;
    setState(() { _loadingStream = true; _streamError = false; });

    try {
      // Try to take a pre-initialized controller from the cache first
      final cached = VideoStreamCache.takeController(widget.video.videoId);
      if (cached != null) {
        if (!mounted) { cached.dispose(); return; }
        setState(() { _ctrl = cached; _loadingStream = false; });
        _ctrl!.play();
        return;
      }

      // Otherwise resolve the URL (may already be cached or in-flight)
      final url = await VideoStreamCache.ensureUrl(widget.video.videoId);
      if (!mounted) return;
      if (url == null) {
        setState(() { _loadingStream = false; _streamError = true; });
        return;
      }

      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      setState(() { _ctrl = ctrl; _loadingStream = false; });
      ctrl.setLooping(true);
      ctrl.play();
    } catch (_) {
      if (!mounted) return;
      setState(() { _loadingStream = false; _streamError = true; });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  bool get _isAr => widget.video.isArabic;
  TextDirection get _dir => _isAr ? TextDirection.rtl : TextDirection.ltr;

  void _share() => SharePlus.instance.share(
        ShareParams(text: '${widget.video.title}\n\n${widget.video.youtubeUrl}',
            subject: widget.video.title));

  void _toggleControls() => setState(() => _showControls = !_showControls);

  void _togglePlay() {
    if (_ctrl == null) return;
    setState(() {
      _ctrl!.value.isPlaying ? _ctrl!.pause() : _ctrl!.play();
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.of(context).size;
    final video = widget.video;

    return SizedBox(
      width: size.width,
      height: size.height,
      child: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoOrThumb(video),
            _buildGradient(),
            _buildContent(video),
            _buildSidebar(),
            _buildProgressBar(),
            if (_showControls) _buildPlayPauseOverlay(),
          ],
        ),
      ),
    );
  }

  // ── Video player or thumbnail ──────────────────────────────────────────────
  Widget _buildVideoOrThumb(Video video) {
    if (_streamError) return _buildErrorOverlay(video);

    if (_ctrl != null && _ctrl!.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width:  _ctrl!.value.size.width,
          height: _ctrl!.value.size.height,
          child: VideoPlayer(_ctrl!),
        ),
      );
    }

    // Thumbnail while loading
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildThumbnail(video),
        if (_loadingStream)
          const Center(
            child: CircularProgressIndicator(
                color: Colors.white60, strokeWidth: 2.5),
          ),
      ],
    );
  }

  Widget _buildThumbnail(Video video) {
    final thumb = video.thumbnail.isNotEmpty
        ? video.thumbnail
        : 'https://img.youtube.com/vi/${video.videoId}/maxresdefault.jpg';
    return ColoredBox(
      color: Colors.black,
      child: CachedNetworkImage(
        imageUrl: thumb,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        fadeInDuration: const Duration(milliseconds: 300),
        placeholder: (_, __) => _fallbackBg(video),
        errorWidget: (_, __, ___) => CachedNetworkImage(
          imageUrl:
              'https://img.youtube.com/vi/${video.videoId}/hqdefault.jpg',
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _fallbackBg(video),
        ),
      ),
    );
  }

  Widget _fallbackBg(Video video) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              video.channelColor.withValues(alpha: 0.85),
              video.channelColor.withValues(alpha: 0.4),
              Colors.black,
            ],
          ),
        ),
        child: Center(
          child: Icon(Icons.smart_display_rounded,
              size: 80, color: Colors.white.withValues(alpha: 0.1)),
        ),
      );

  Widget _buildErrorOverlay(Video video) => Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnail(video),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_circle_outline_rounded,
                    color: Colors.white70, size: 72),
                const SizedBox(height: 12),
                Text(
                  'تعذّر تحميل الفيديو',
                  style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(video.youtubeUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text('شاهد على يوتيوب',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF0000),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    _ctrl?.dispose();
                    _ctrl = null;
                    _initPlayer();
                  },
                  child: Text('إعادة المحاولة',
                      style: GoogleFonts.cairo(color: Colors.white54)),
                ),
              ],
            ),
          ),
        ],
      );

  // ── Play/pause overlay ─────────────────────────────────────────────────────
  Widget _buildPlayPauseOverlay() {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return const SizedBox();
    final playing = _ctrl!.value.isPlaying;
    return Positioned.fill(
      child: Align(
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: _togglePlay,
          child: AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Gradient ───────────────────────────────────────────────────────────────
  Widget _buildGradient() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.3, 0.55, 1.0],
            colors: [
              Colors.black.withValues(alpha: 0.25),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.55),
              Colors.black.withValues(alpha: 0.93),
            ],
          ),
        ),
      );

  // ── Content ────────────────────────────────────────────────────────────────
  Widget _buildContent(Video video) => Positioned(
        left: 16,
        right: 72,
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
                      _buildChannelChip(video),
                      const SizedBox(height: 10),

                      Text(
                        video.title,
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: _isAr ? 19 : 17,
                          fontWeight: FontWeight.bold,
                          height: 1.35,
                          shadows: const [
                            Shadow(
                                blurRadius: 6,
                                color: Colors.black54,
                                offset: Offset(0, 2))
                          ],
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),

                      if (video.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          video.description,
                          style: GoogleFonts.cairo(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.4),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 13, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            _isAr ? video.timeAgoAr : video.timeAgo,
                            style: GoogleFonts.cairo(
                                color: Colors.white54, fontSize: 12),
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

  Widget _buildChannelChip(Video video) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: video.channelColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_display_rounded,
                color: Colors.white, size: 13),
            const SizedBox(width: 5),
            Text(
              video.channel,
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );

  // ── Sidebar ────────────────────────────────────────────────────────────────
  Widget _buildSidebar() => Positioned(
        right: 8,
        bottom: 80,
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sideBtn(
                  icon: Icons.share_rounded,
                  label: _isAr ? 'مشاركة' : 'Share',
                  onTap: _share),
            ],
          ),
        ),
      );

  Widget _sideBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) =>
      GestureDetector(
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
                style:
                    GoogleFonts.cairo(color: Colors.white70, fontSize: 10)),
          ],
        ),
      );

  // ── Progress dots ──────────────────────────────────────────────────────────
  Widget _buildProgressBar() => Positioned(
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
                      : Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );
}
