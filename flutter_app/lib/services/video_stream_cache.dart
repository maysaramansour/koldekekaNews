import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Video;

/// Caches resolved YouTube stream URLs **and** pre-initialized
/// [VideoPlayerController]s so videos play instantly.
///
/// Key design: [_futures] stores the in-flight Future for each videoId so
/// any number of callers awaiting the same ID share one network request.
class VideoStreamCache {
  VideoStreamCache._();

  // ── Shared YoutubeExplode instance ───────────────────────────────────────────
  static final YoutubeExplode _yt = YoutubeExplode();

  // ── URL cache ────────────────────────────────────────────────────────────────
  static final Map<String, String>       _urls    = {};
  // In-flight Futures — deduplicates parallel callers for the same videoId
  static final Map<String, Future<void>> _futures = {};

  // ── Controller cache ─────────────────────────────────────────────────────────
  static final Map<String, VideoPlayerController> _controllers = {};
  static final Set<String>                         _initingCtrl = {};

  /// Returns a cached stream URL, or `null` if not yet resolved.
  static String? get(String videoId) => _urls[videoId];

  /// Takes ownership of a pre-initialized controller (removes it from cache).
  /// Returns `null` if none is ready yet.
  static VideoPlayerController? takeController(String videoId) =>
      _controllers.remove(videoId);

  /// Ensures the stream URL for [videoId] is resolved, then returns it.
  /// If a fetch is already in progress, awaits that same Future (no duplicate
  /// network request). Returns `null` on failure.
  static Future<String?> ensureUrl(String videoId) async {
    if (_urls.containsKey(videoId)) return _urls[videoId];
    // Reuse or create the in-flight Future
    _futures[videoId] ??= _fetchUrl(videoId);
    await _futures[videoId];
    return _urls[videoId];
  }

  /// Starts background prefetch for [videoId] without awaiting.
  /// Subsequent calls for the same ID are no-ops (Future is reused).
  static void prefetch(String videoId) {
    if (_urls.containsKey(videoId)) {
      // URL ready — kick off controller pre-init if not done
      _preInitController(videoId);
      return;
    }
    _futures[videoId] ??= _fetchUrl(videoId);
  }

  static Future<void> _fetchUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final muxed    = manifest.muxed;
      if (muxed.isNotEmpty) {
        _urls[videoId] = muxed.withHighestBitrate().url.toString();
        _preInitController(videoId); // fire-and-forget
      }
    } catch (_) {
      // Ignored — card retries on-demand
    } finally {
      _futures.remove(videoId);
    }
  }

  static Future<void> _preInitController(String videoId) async {
    if (_controllers.containsKey(videoId) || _initingCtrl.contains(videoId)) return;
    final url = _urls[videoId];
    if (url == null) return;
    _initingCtrl.add(videoId);
    try {
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await ctrl.initialize();
      if (_controllers.containsKey(videoId)) {
        ctrl.dispose(); // race: card already owns one
      } else {
        _controllers[videoId] = ctrl;
      }
    } catch (_) {
      // Card falls back to on-demand init
    } finally {
      _initingCtrl.remove(videoId);
    }
  }

  /// Fires prefetch for ALL [videoIds] in parallel immediately.
  /// Call this as soon as the video list is available.
  static void warmUpAll(List<String> videoIds) {
    for (final id in videoIds) {
      prefetch(id);
    }
  }

  /// Warms up [count] videos starting at [from].
  static void warmUp(List<String> videoIds, {int from = 0, int count = 3}) {
    for (int i = from; i < from + count && i < videoIds.length; i++) {
      prefetch(videoIds[i]);
    }
  }

  /// Disposes controllers more than [window] pages away to free memory.
  static void evictDistant(int currentIndex, List<String> videoIds, {int window = 2}) {
    for (int i = 0; i < videoIds.length; i++) {
      if ((i - currentIndex).abs() > window) {
        final id = videoIds[i];
        _controllers.remove(id)?.dispose();
        _initingCtrl.remove(id);
      }
    }
  }

  /// Clears everything (e.g. when channel filter changes).
  static void clear() {
    for (final ctrl in _controllers.values) { ctrl.dispose(); }
    _controllers.clear();
    _initingCtrl.clear();
    _urls.clear();
    _futures.clear();
  }
}
