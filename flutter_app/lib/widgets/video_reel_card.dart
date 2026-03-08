import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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

  /// Global fullscreen state — HomeScreen & VideoReelsScreen listen to this.
  static final ValueNotifier<bool> fullscreenNotifier = ValueNotifier(false);

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

  // ── Pinch-to-zoom ──────────────────────────────────────────────────────────
  double _scale = 1.0;
  double _baseScale = 1.0;

  // ── Tap-to-pause flash ─────────────────────────────────────────────────────
  bool _showPauseIcon = false;
  Timer? _pauseIconTimer;

  // ── Fullscreen ─────────────────────────────────────────────────────────────
  bool _isFullscreen = false;

  // ── Seekbar ────────────────────────────────────────────────────────────────
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _showSeekBar  = false;
  Timer? _seekBarTimer;

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
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      _ctrl?.play();
      WakelockPlus.enable();
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
      WakelockPlus.disable();
    }
  }

  void _onVideoProgress() {
    if (!mounted || _ctrl == null) return;
    final pos = _ctrl!.value.position;
    final dur = _ctrl!.value.duration;
    if (pos != _position || dur != _duration) {
      setState(() { _position = pos; _duration = dur; });
    }
  }

  @override
  void dispose() {
    _pauseIconTimer?.cancel();
    _seekBarTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.removeListener(_onVideoProgress);
    _ctrl?.pause();
    _slideCtrl.dispose();
    _ctrl?.dispose();
    WakelockPlus.disable();
    if (_isFullscreen) _exitFullscreen();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    if (_loadingStream || _ctrl != null) return;
    setState(() { _loadingStream = true; _streamError = false; });

    try {
      // Take pre-initialized controller if ready (instant play)
      final cached = VideoStreamCache.takeController(widget.video.videoId);
      if (cached != null) {
        if (!mounted) { cached.dispose(); return; }
        setState(() { _ctrl = cached; _loadingStream = false; });
        _ctrl!.addListener(_onVideoProgress);
        _ctrl!.setLooping(true);
        _ctrl!.play();
        WakelockPlus.enable();
        return;
      }

      // Otherwise resolve URL (should already be cached) then init on-demand
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
      ctrl.addListener(_onVideoProgress);
      ctrl.setLooping(true);
      ctrl.play();
      WakelockPlus.enable();
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

  void _togglePlay() {
    if (_ctrl == null) return;
    setState(() {
      if (_ctrl!.value.isPlaying) {
        _ctrl!.pause();
        WakelockPlus.disable();
      } else {
        _ctrl!.play();
        WakelockPlus.enable();
      }
      _showPauseIcon = true;
    });
    _pauseIconTimer?.cancel();
    _pauseIconTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showPauseIcon = false);
    });
    // In fullscreen, also show the seekbar briefly
    if (_isFullscreen) _showSeekBarBriefly();
  }

  void _showSeekBarBriefly() {
    setState(() => _showSeekBar = true);
    _seekBarTimer?.cancel();
    _seekBarTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSeekBar = false);
    });
  }

  void _enterFullscreen() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() { _isFullscreen = true; _scale = 1.0; });
    VideoReelCard.fullscreenNotifier.value = true;
    _showSeekBarBriefly();
  }

  void _exitFullscreen() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() { _isFullscreen = false; _showSeekBar = false; });
    VideoReelCard.fullscreenNotifier.value = false;
  }

  void _toggleFullscreen() =>
      _isFullscreen ? _exitFullscreen() : _enterFullscreen();

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
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
        onTap: () {
          _showSeekBarBriefly();
          _togglePlay();
        },
        onScaleStart: (_) => _baseScale = _scale,
        onScaleUpdate: (d) {
          if (d.pointerCount < 2 || _isFullscreen) return;
          setState(() => _scale = (_baseScale * d.scale).clamp(1.0, 4.0));
        },
        onScaleEnd: (_) {
          if (_scale < 1.1) setState(() => _scale = 1.0);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video / thumbnail
            Transform.scale(
              scale: _isFullscreen ? 1.0 : _scale,
              child: _buildVideoOrThumb(video),
            ),

            // Normal mode overlays (hidden in fullscreen)
            if (!_isFullscreen && _scale <= 1.0) ...[
              _buildGradient(),
              _buildContent(video),
              _buildSidebar(),
              _buildProgressBar(),
            ],

            // Brief pause/play flash
            if (_showPauseIcon)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    (_ctrl?.value.isPlaying ?? false)
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
              ),

            // Portrait seekbar (shown briefly on tap)
            if (!_isFullscreen && _showSeekBar && _duration > Duration.zero)
              _buildPortraitSeekBar(),

            // Fullscreen UI: exit button + seekbar
            if (_isFullscreen) ...[
              // Exit fullscreen button (top-left)
              Positioned(
                top: 16,
                left: 16,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: _exitFullscreen,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.fullscreen_exit_rounded,
                          color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ),

              // Seekbar (shown briefly on tap)
              if (_showSeekBar) _buildSeekBar(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Video player or thumbnail ──────────────────────────────────────────────
  Widget _buildVideoOrThumb(Video video) {
    if (_streamError) return _buildErrorOverlay(video);

    if (_ctrl != null && _ctrl!.value.isInitialized) {
      if (_isFullscreen) {
        // Fullscreen: fill the landscape width at native aspect ratio (no crop)
        return Center(
          child: AspectRatio(
            aspectRatio: _ctrl!.value.aspectRatio,
            child: VideoPlayer(_ctrl!),
          ),
        );
      }
      // Portrait: cover the full card (crop as needed)
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

  // ── Seekbar (portrait) ────────────────────────────────────────────────────
  Widget _buildPortraitSeekBar() {
    final dur = _duration.inMilliseconds.toDouble();
    final pos = _position.inMilliseconds.toDouble().clamp(0.0, dur == 0 ? 1.0 : dur);
    final progress = dur > 0 ? pos / dur : 0.0;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_duration),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                  Text(_formatDuration(_position),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChangeStart: (_) => _seekBarTimer?.cancel(),
                  onChanged: (val) {
                    final newPos = Duration(
                        milliseconds: (val * _duration.inMilliseconds).toInt());
                    setState(() => _position = newPos);
                    _ctrl?.seekTo(newPos);
                  },
                  onChangeEnd: (_) => _showSeekBarBriefly(),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  // ── Seekbar (fullscreen) ───────────────────────────────────────────────────
  Widget _buildSeekBar() {
    final dur = _duration.inMilliseconds.toDouble();
    final pos = _position.inMilliseconds.toDouble().clamp(0.0, dur == 0 ? 1.0 : dur);
    final progress = dur > 0 ? pos / dur : 0.0;

    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Time labels: right = current, left = total (RTL)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChangeStart: (_) => _seekBarTimer?.cancel(),
                  onChanged: (val) {
                    final newPos = Duration(
                      milliseconds: (val * _duration.inMilliseconds).toInt(),
                    );
                    setState(() => _position = newPos);
                    _ctrl?.seekTo(newPos);
                  },
                  onChangeEnd: (_) => _showSeekBarBriefly(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
              const SizedBox(height: 20),
              _sideBtn(
                  icon: _isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  label: _isFullscreen ? 'تصغير' : 'ملء الشاشة',
                  onTap: _toggleFullscreen),
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
