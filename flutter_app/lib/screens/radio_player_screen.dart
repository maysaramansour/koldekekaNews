import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class RadioPlayerScreen extends StatefulWidget {
  final String stationName;
  final String stationSub;
  final String streamUrl;
  final Color color;
  final String icon;

  const RadioPlayerScreen({
    super.key,
    required this.stationName,
    required this.stationSub,
    required this.streamUrl,
    required this.color,
    required this.icon,
  });

  @override
  State<RadioPlayerScreen> createState() => _RadioPlayerScreenState();
}

class _RadioPlayerScreenState extends State<RadioPlayerScreen>
    with TickerProviderStateMixin {
  VideoPlayerController? _ctrl;
  _State _state = _State.loading;
  late AnimationController _waveCtrl;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _initStream();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _pulseCtrl.dispose();
    _ctrl?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initStream() async {
    setState(() => _state = _State.loading);
    await _ctrl?.dispose();
    _ctrl = null;

    try {
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(widget.streamUrl),
      );
      await ctrl.initialize().timeout(const Duration(seconds: 20));
      ctrl.setLooping(true);
      ctrl.play();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _ctrl = ctrl;
        _state = _State.playing;
      });
      WakelockPlus.enable();
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _State.error);
    }
  }

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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.4,
                  colors: [
                    widget.color.withOpacity(0.6),
                    widget.color.withOpacity(0.2),
                    Colors.black,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),

            Column(
              children: [
                // Back button
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

                const Spacer(),

                // Station icon
                Text(widget.icon, style: const TextStyle(fontSize: 80)),
                const SizedBox(height: 24),

                // Station name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.stationName,
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.stationSub,
                  style: GoogleFonts.cairo(
                      color: Colors.white54, fontSize: 14),
                ),

                const SizedBox(height: 40),

                // Waveform / loading / error
                SizedBox(
                  height: 60,
                  child: _buildVisualizer(),
                ),

                const SizedBox(height: 32),

                // Play/pause button
                if (_state == _State.playing)
                  GestureDetector(
                    onTap: _togglePlay,
                    child: AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, child) => Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.color,
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withOpacity(
                                  0.4 + 0.2 * _pulseCtrl.value),
                              blurRadius: 20 + 10 * _pulseCtrl.value,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: child,
                      ),
                      child: Icon(
                        (_ctrl?.value.isPlaying ?? false)
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),

                if (_state == _State.error)
                  ElevatedButton.icon(
                    onPressed: _initStream,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('إعادة المحاولة',
                        style: GoogleFonts.cairo()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.color,
                      foregroundColor: Colors.white,
                    ),
                  ),

                const Spacer(),

                // Live badge
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _state == _State.playing
                              ? Color.lerp(Colors.red, Colors.orange,
                                  _pulseCtrl.value)
                              : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _state == _State.loading
                            ? 'جارٍ التحميل…'
                            : _state == _State.error
                                ? 'تعذّر الاتصال'
                                : 'بث مباشر',
                        style: GoogleFonts.cairo(
                            color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualizer() {
    if (_state == _State.loading) {
      return Center(
        child: CircularProgressIndicator(
            color: widget.color, strokeWidth: 2),
      );
    }
    if (_state == _State.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: Colors.red, size: 28),
            const SizedBox(height: 6),
            Text('تعذّر تحميل البث',
                style: GoogleFonts.cairo(
                    color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
    }

    final isPlaying = _ctrl?.value.isPlaying ?? false;

    return AnimatedBuilder(
      animation: _waveCtrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(20, (i) {
            final phase = _waveCtrl.value * 2 * pi + i * 0.5;
            final height = isPlaying
                ? 10.0 + 28.0 * ((sin(phase) + 1) / 2)
                : 4.0;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 5,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: widget.color
                    .withOpacity(0.5 + 0.5 * ((sin(phase) + 1) / 2)),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        );
      },
    );
  }
}

enum _State { loading, playing, error }
