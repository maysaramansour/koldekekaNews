import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class LivePlayerScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  final Color channelColor;
  /// Direct HLS/DASH stream URL from the channel's own CDN.
  /// Empty string = skip and go straight to YouTube fallback.
  final String streamUrl;
  /// Known YouTube live video ID — skips the API search step.
  final String videoId;

  const LivePlayerScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.channelColor,
    this.streamUrl = '',
    this.videoId = '',
  });

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<LivePlayerScreen> {
  // ── State ────────────────────────────────────────────────────────────────
  _PlayerMode _mode = _PlayerMode.loading;
  VideoPlayerController? _videoCtrl;
  WebViewController? _webCtrl;
  bool _showControls = true;
  String? _videoId; // live video ID once found

  static const _apiKey = 'AIzaSyCUJoaM752dWDRlskvHDgK6q43jHLoqPp0';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initPlayer();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _videoCtrl?.dispose();
    super.dispose();
  }

  // ── Step 1: find live video ID via YouTube Data API ──────────────────────
  Future<String?> _getLiveVideoId() async {
    final uri = Uri.parse(
      'https://www.googleapis.com/youtube/v3/search'
      '?part=id'
      '&channelId=${widget.channelId}'
      '&eventType=live'
      '&type=video'
      '&key=$_apiKey',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = json.decode(res.body) as Map<String, dynamic>;
      final items = data['items'] as List?;
      if (items == null || items.isEmpty) return null;
      return (items[0]['id'] as Map<String, dynamic>)['videoId'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Step 1b: play direct CDN HLS/DASH URL natively (no YouTube) ─────────
  Future<bool> _tryDirectStream(String url) async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      await ctrl.initialize().timeout(const Duration(seconds: 15));
      ctrl.play();
      if (!mounted) { ctrl.dispose(); return false; }
      setState(() { _videoCtrl = ctrl; _mode = _PlayerMode.native; });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Step 2a: try native HLS via youtube_explode_dart ────────────────────
  Future<bool> _tryNativeHls(String videoId) async {
    try {
      final yt = YoutubeExplode();
      final hlsUrl = await yt.videos.streamsClient
          .getHttpLiveStreamUrl(VideoId(videoId))
          .timeout(const Duration(seconds: 15));
      yt.close();

      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(hlsUrl),
        httpHeaders: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120',
        },
      );
      await ctrl.initialize().timeout(const Duration(seconds: 15));
      ctrl.play();

      if (!mounted) {
        ctrl.dispose();
        return false;
      }
      setState(() {
        _videoCtrl = ctrl;
        _mode = _PlayerMode.native;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Step 2b: YouTube IFrame API via HTML with youtube.com origin ────────
  // Loading an HTML string with baseUrl='https://www.youtube.com' makes the
  // WebView's page origin = youtube.com, which YouTube trusts for embedding.
  // This bypasses Error 153 caused by unknown/no origin in raw WebView embeds.
  void _tryWebViewEmbed(String videoId) {
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
    #player { width: 100%; height: 100%; }
    #player iframe { width: 100% !important; height: 100% !important; border: none; }
  </style>
</head>
<body>
  <div id="player"></div>
  <script>
    var tag = document.createElement('script');
    tag.src = "https://www.youtube.com/iframe_api";
    document.head.appendChild(tag);

    function onYouTubeIframeAPIReady() {
      new YT.Player('player', {
        videoId: '$videoId',
        width: '100%',
        height: '100%',
        playerVars: {
          autoplay: 1,
          controls: 1,
          playsinline: 1,
          rel: 0,
          modestbranding: 1,
          iv_load_policy: 3,
          origin: 'https://www.youtube.com'
        }
      });
    }
  </script>
</body>
</html>
''';

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (err) {
          if ((err.isForMainFrame ?? false) && mounted) {
            setState(() => _mode = _PlayerMode.error);
          }
        },
      ))
      // baseUrl sets the page origin to youtube.com — key to bypassing Error 153
      ..loadHtmlString(html, baseUrl: 'https://www.youtube.com');

    if (!mounted) return;
    setState(() {
      _webCtrl = ctrl;
      _mode = _PlayerMode.webview;
    });
  }

  // ── Main init ────────────────────────────────────────────────────────────
  Future<void> _initPlayer() async {
    setState(() => _mode = _PlayerMode.loading);

    // Dispose previous player if retrying
    await _videoCtrl?.dispose();
    _videoCtrl = null;
    _webCtrl = null;

    // 1. Try direct CDN stream URL first (fastest, no YouTube restrictions)
    if (widget.streamUrl.isNotEmpty) {
      final ok = await _tryDirectStream(widget.streamUrl);
      if (ok) return;
    }

    // 2. YouTube fallback: use provided videoId or find via API
    final videoId = widget.videoId.isNotEmpty
        ? widget.videoId
        : await _getLiveVideoId();
    if (videoId == null) {
      if (mounted) setState(() => _mode = _PlayerMode.noStream);
      return;
    }
    _videoId = videoId;

    // 3. Try HLS extraction via youtube_explode_dart
    final nativeOk = await _tryNativeHls(videoId);
    if (nativeOk) return;

    // 4. Fall back to WebView with YouTube IFrame API (youtube.com origin)
    if (mounted) _tryWebViewEmbed(videoId);
  }

  void _toggleControls() => setState(() => _showControls = !_showControls);

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildContent(),
          _buildTopBar(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_mode) {
      case _PlayerMode.loading:
        return _buildLoading();

      case _PlayerMode.native:
        final initialized = _videoCtrl?.value.isInitialized ?? false;
        if (!initialized) return _buildLoading();
        return GestureDetector(
          onTap: _toggleControls,
          child: Center(
            child: AspectRatio(
              aspectRatio: _videoCtrl!.value.aspectRatio,
              child: VideoPlayer(_videoCtrl!),
            ),
          ),
        );

      case _PlayerMode.webview:
        return GestureDetector(
          onTap: _toggleControls,
          child: WebViewWidget(controller: _webCtrl!),
        );

      case _PlayerMode.noStream:
        return _buildNoStream();

      case _PlayerMode.error:
        return _buildError();
    }
  }

  // ── Top bar overlay ──────────────────────────────────────────────────────
  Widget _buildTopBar() {
    final isPlaying =
        _mode == _PlayerMode.native || _mode == _PlayerMode.webview;

    // In webview mode we always show a minimal back button (WebView captures taps)
    if (_mode == _PlayerMode.webview) {
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                _PulseDot(color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.channelName,
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                      Text('بث مباشر',
                          style: GoogleFonts.cairo(
                              color: Colors.red, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!isPlaying || !_showControls) {
      return Positioned(
        top: 0,
        left: 0,
        child: SafeArea(
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      );
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                _PulseDot(color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.channelName,
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                      Text('بث مباشر',
                          style: GoogleFonts.cairo(
                              color: Colors.red, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── State screens ────────────────────────────────────────────────────────
  Widget _buildLoading() => Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                  color: widget.channelColor, strokeWidth: 3),
              const SizedBox(height: 16),
              Text('جارٍ تحميل البث المباشر…',
                  style: GoogleFonts.cairo(
                      color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 6),
              Text(widget.channelName,
                  style: GoogleFonts.cairo(
                      color: widget.channelColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );

  Widget _buildNoStream() => _buildErrorState(
        icon: Icons.sensors_off_rounded,
        title: 'لا يوجد بث مباشر الآن',
        subtitle: 'القناة غير مباشرة في هذا الوقت',
      );

  Widget _buildError() => _buildErrorState(
        icon: Icons.wifi_off_rounded,
        title: 'تعذّر تحميل البث',
        subtitle: 'تحقق من الاتصال وأعد المحاولة',
      );

  Widget _buildErrorState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) =>
      Column(
        children: [
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.red.shade300, size: 60),
                  const SizedBox(height: 16),
                  Text(title,
                      style: GoogleFonts.cairo(
                          color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(subtitle,
                      style: GoogleFonts.cairo(
                          color: Colors.white38, fontSize: 13)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _initPlayer,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('إعادة المحاولة',
                        style: GoogleFonts.cairo()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.channelColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

// ── Player mode enum ──────────────────────────────────────────────────────────
enum _PlayerMode { loading, native, webview, noStream, error }

// ── Pulsing live dot ──────────────────────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Color.lerp(
                widget.color, widget.color.withOpacity(0.3), _ctrl.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.5 * _ctrl.value),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      );
}
