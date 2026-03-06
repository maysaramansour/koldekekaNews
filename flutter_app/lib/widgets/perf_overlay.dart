import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Debug-only performance overlay — shows RAM usage and frame timing.
/// Wraps [child] and draws a draggable stats badge in the top-right corner.
/// Compiled away (returns [child] unchanged) in release builds.
class PerfOverlay extends StatefulWidget {
  final Widget child;
  const PerfOverlay({super.key, required this.child});

  @override
  State<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends State<PerfOverlay> {
  // ── State ─────────────────────────────────────────────────────────────────
  int _ramMb = 0;
  double _fps = 0;
  int _jankCount = 0;
  bool _expanded = true;

  // Frame timing
  int _frameCount = 0;
  DateTime _lastFpsSample = DateTime.now();
  int _slowFrames = 0; // frames > 16ms build time

  Timer? _ramTimer;

  @override
  void initState() {
    super.initState();
    _sampleRam();
    _ramTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sampleRam());
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  void dispose() {
    _ramTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    super.dispose();
  }

  void _sampleRam() {
    if (!mounted) return;
    final rss = ProcessInfo.currentRss;
    setState(() => _ramMb = (rss / 1024 / 1024).round());
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted) return;
    _frameCount += timings.length;
    for (final t in timings) {
      if (t.buildDuration.inMilliseconds > 16) _slowFrames++;
    }
    final now = DateTime.now();
    final elapsed = now.difference(_lastFpsSample).inMilliseconds;
    if (elapsed >= 1000) {
      final fps = _frameCount * 1000 / elapsed;
      setState(() {
        _fps = fps.clamp(0, 120);
        _jankCount += _slowFrames;
        _frameCount = 0;
        _slowFrames = 0;
        _lastFpsSample = now;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // No overhead in release builds
    if (kReleaseMode) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          right: 4,
          child: GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: _expanded ? _expandedBadge() : _collapsedBadge(),
          ),
        ),
      ],
    );
  }

  Widget _collapsedBadge() => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          border: Border.all(color: _fpsColor().withValues(alpha: 0.8), width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.speed, color: _fpsColor(), size: 18),
      );

  Widget _expandedBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.80),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _row('RAM', '$_ramMb MB', _ramColor()),
              const SizedBox(height: 2),
              _row('FPS', _fps.toStringAsFixed(1), _fpsColor()),
              const SizedBox(height: 2),
              _row('JANK', '$_jankCount frames', _jankCount > 0 ? Colors.orange : Colors.greenAccent),
            ],
          ),
        ),
      );

  Widget _row(String label, String value, Color valueColor) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: const TextStyle(color: Colors.white54)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold)),
        ],
      );

  Color _ramColor() {
    if (_ramMb > 400) return Colors.red;
    if (_ramMb > 250) return Colors.orange;
    return Colors.greenAccent;
  }

  Color _fpsColor() {
    if (_fps < 30) return Colors.red;
    if (_fps < 55) return Colors.orange;
    return Colors.greenAccent;
  }
}
