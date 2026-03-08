import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Video;

/// Manages YouTube stream URL resolution and sequential controller pre-init.
///
/// Strategy:
///   - URL cache: resolve up to 4 videos ahead (strings only, cheap).
///   - Controller cache: pre-init exactly ONE controller at a time (the next
///     video). Sequential — never two controller inits running in parallel.
///   - When user advances to video N, the controller for N+1 starts pre-init.
///   - Result: instant play for every video, max ~1 extra controller in RAM.
class VideoStreamCache {
  VideoStreamCache._();

  static final YoutubeExplode _yt = YoutubeExplode();

  // ── URL cache (lightweight — just strings) ────────────────────────────────
  static final Map<String, String>       _urls    = {};
  static final Map<String, Future<void>> _futures = {};

  // ── Controller cache — at most 1 entry at a time ──────────────────────────
  static final Map<String, VideoPlayerController> _controllers = {};
  static bool _ctrlBusy = false; // ensures sequential init

  // ── URL resolution ────────────────────────────────────────────────────────

  static String? get(String videoId) => _urls[videoId];

  /// Resolves and returns the stream URL, awaiting any in-flight fetch.
  static Future<String?> ensureUrl(String videoId) async {
    if (_urls.containsKey(videoId)) return _urls[videoId];
    _futures[videoId] ??= _fetchUrl(videoId);
    await _futures[videoId];
    return _urls[videoId];
  }

  static void _prefetch(String videoId) {
    if (_urls.containsKey(videoId) || _futures.containsKey(videoId)) return;
    _futures[videoId] = _fetchUrl(videoId);
  }

  static Future<void> _fetchUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      // Sort by resolution height (desc) then bitrate (desc) — highest quality first.
      // Muxed streams are capped at 720p by YouTube; this ensures we get that max.
      final muxed = manifest.muxed.toList()
        ..sort((a, b) {
          final hDiff = b.videoResolution.height.compareTo(a.videoResolution.height);
          return hDiff != 0 ? hDiff : b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond);
        });
      if (muxed.isNotEmpty) {
        _urls[videoId] = muxed.first.url.toString();
      }
    } catch (_) {
    } finally {
      _futures.remove(videoId);
    }
  }

  // ── Controller pre-init (sequential) ─────────────────────────────────────

  /// Takes ownership of a pre-initialized controller. Returns null if not ready.
  static VideoPlayerController? takeController(String videoId) =>
      _controllers.remove(videoId);

  /// Pre-initializes the controller for [videoId] if nothing else is running.
  /// Fire-and-forget — safe to call without await.
  static Future<void> _preInitController(String videoId) async {
    if (_controllers.containsKey(videoId) || _ctrlBusy) return;
    final url = _urls[videoId];
    if (url == null) {
      // URL not ready yet — wait for it first
      await _fetchUrl(videoId);
      if (!_urls.containsKey(videoId)) return;
    }
    if (_ctrlBusy || _controllers.containsKey(videoId)) return;
    _ctrlBusy = true;
    try {
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(_urls[videoId]!),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await ctrl.initialize();
      if (_controllers.containsKey(videoId)) {
        // Race: another path already took it — discard
        ctrl.dispose();
      } else {
        _controllers[videoId] = ctrl;
      }
    } catch (_) {
    } finally {
      _ctrlBusy = false;
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Call whenever the user lands on [currentIndex].
  /// Prefetches URLs 4 ahead and pre-inits the controller for the next video.
  static void advanceTo(int currentIndex, List<String> videoIds) {
    // Prefetch URLs for next 4 videos (just string resolution, cheap)
    for (int i = currentIndex + 1;
        i <= currentIndex + 4 && i < videoIds.length;
        i++) {
      _prefetch(videoIds[i]);
    }

    // Evict pre-initialized controllers that are no longer the "next" video
    final keepId =
        currentIndex + 1 < videoIds.length ? videoIds[currentIndex + 1] : null;
    _controllers.removeWhere((id, ctrl) {
      if (id == keepId) return false;
      ctrl.dispose();
      return true;
    });

    // Evict URLs that are too far behind (> 5 away) to bound string cache
    for (int i = 0; i < currentIndex - 5 && i < videoIds.length; i++) {
      _urls.remove(videoIds[i]);
    }

    // Pre-init the next video's controller (sequential — skips if busy)
    if (keepId != null) {
      _preInitController(keepId);
    }
  }

  /// Clears everything (e.g. on channel filter change).
  static void clear() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    _controllers.clear();
    _urls.clear();
    _futures.clear();
    _ctrlBusy = false;
  }
}
