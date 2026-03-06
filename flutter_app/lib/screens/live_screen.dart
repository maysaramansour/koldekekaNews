import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'live_player_screen.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  // streamUrl: direct HLS from the channel's own CDN (no YouTube needed).
  // Empty string = fall back to YouTube API search.
  static const _channels = [
    {
      'name': 'الجزيرة',
      'sub': 'Al Jazeera Arabic',
      'channelId': 'UCfiwzLy-8yKzIbsmZTzxDgw',
      'streamUrl': 'https://live-hls-web-aja.getaj.net/AJA/index.m3u8',
      'videoId': 'bNyUyrR0PHo',
      'color': 0xFFa93226,
      'icon': '📺',
    },
    {
      'name': 'العربية',
      'sub': 'Al Arabiya',
      'channelId': 'UCahpxixMCwoANAftn6IxkTg',
      'streamUrl': 'https://live.alarabiya.net/alarabiapublish/alarabiya.smil/playlist.m3u8',
      'color': 0xFF884ea0,
      'icon': '📡',
    },
    {
      'name': 'سكاي نيوز عربية',
      'sub': 'Sky News Arabia',
      'channelId': 'UCIJXOvggjKtCagMfxvcCzAA',
      'streamUrl': 'https://skynewsarabia-live.akamaized.net/hls/live/2002309/skynewsarabia/master.m3u8',
      'color': 0xFF1a5276,
      'icon': '🌐',
    },
    {
      'name': 'BBC عربي',
      'sub': 'BBC Arabic',
      'channelId': 'UCPmIZByAioZQLmVqPSWCQLQ',
      'streamUrl': 'https://vs-cmaf-pushb-ww-live.akamaized.net/x=4/i=urn:bbc:piff:service:bbc_arabic_tv/pc_hd_abr_v2.mpd',
      'color': 0xFFc0392b,
      'icon': '📻',
    },
    {
      'name': 'قناة الحرة',
      'sub': 'Al Hurra TV',
      'channelId': 'UCyscVWiJELkATSuU-RF2NLg',
      'streamUrl': 'https://mts.usagm.gov/channels/alhurra/index.m3u8',
      'color': 0xFF27ae60,
      'icon': '🎙️',
    },
    {
      'name': 'DW عربية',
      'sub': 'DW Arabic',
      'channelId': 'UC30ditU5JI16o5NbFsHde_Q',
      'streamUrl': 'https://dwamdstream106.akamaized.net/hls/live/2017965/dwstream106/index.m3u8',
      'color': 0xFF2471a3,
      'icon': '📰',
    },
    {
      'name': 'فرانس 24',
      'sub': 'France 24 Arabic',
      'channelId': 'UCdTyuXgmJkG_O8_75eqej-w',
      'streamUrl': 'https://static.france24.com/live/F24_AR_LO_HLS/live_web.m3u8',
      'color': 0xFF154360,
      'icon': '🗞️',
    },
    {
      'name': 'TRT عربي',
      'sub': 'TRT Arabic',
      'channelId': 'UCP9b8o5C9sVr2sZUBAqRnAg',
      'streamUrl': 'https://tv-trta.medya.trt.com.tr/master.m3u8',
      'color': 0xFFd35400,
      'icon': '📣',
    },
    {
      'name': 'روسيا اليوم',
      'sub': 'RT Arabic',
      'channelId': 'UCuP-v6UNKp8x7tKjpxPOnyA',
      'streamUrl': 'https://rt-arab.secure.footprint.net/1105.m3u8',
      'color': 0xFF922b21,
      'icon': '🔊',
    },
    {
      'name': 'Al Jazeera English',
      'sub': 'Al Jazeera Eng',
      'channelId': 'UCB87_o2zsNZTrJ9MO6DdM-A',
      'streamUrl': 'https://live-hls-web-aje.getaj.net/AJE/index.m3u8',
      'color': 0xFFc0392b,
      'icon': '🌍',
    },
    {
      'name': 'Middle East Eye',
      'sub': 'Middle East Eye',
      'channelId': 'UCR0fZh5SBxxMNYdg0VzRFkg',
      'streamUrl': '',
      'color': 0xFF16a085,
      'icon': '👁️',
    },
    {
      'name': 'euronews بالعربية',
      'sub': 'Euronews Arabic',
      'channelId': 'UCBqMeqoF_wOrGFqKVpOqOiQ',
      'streamUrl': 'https://euronews-euronews-arabic-1-eu.samsung.wurl.tv/manifest/playlist.m3u8',
      'color': 0xFF2980b9,
      'icon': '🇪🇺',
    },
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _openLive(Map<String, dynamic> ch) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LivePlayerScreen(
          channelId: ch['channelId'] as String,
          channelName: ch['name'] as String,
          channelColor: Color(ch['color'] as int),
          streamUrl: ch['streamUrl'] as String? ?? '',
          videoId: ch['videoId'] as String? ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: const Color(0xFF0a0a14),
            floating: true,
            snap: true,
            elevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Color.lerp(Colors.red, Colors.red.shade900,
                          _pulseCtrl.value),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.6),
                          blurRadius: 8 * _pulseCtrl.value,
                          spreadRadius: 2 * _pulseCtrl.value,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'بث مباشر',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'LIVE',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Subtitle ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'اضغط على أي قناة لمشاهدة البث المباشر',
                style: GoogleFonts.cairo(
                    color: Colors.white38, fontSize: 13),
                textDirection: TextDirection.rtl,
              ),
            ),
          ),

          // ── Channel grid ────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverGrid(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) =>
                    _buildCard(_channels[i] as Map<String, dynamic>),
                childCount: _channels.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> ch) {
    final color = Color(ch['color'] as int);

    return GestureDetector(
      onTap: () => _openLive(ch),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.9),
              color.withOpacity(0.5),
              Colors.black87,
            ],
          ),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
        ),
        child: Stack(
          children: [
            // Background icon
            Positioned(
              right: -8,
              bottom: -8,
              child: Text(
                ch['icon'] as String,
                style: const TextStyle(fontSize: 56),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Live badge
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Color.lerp(Colors.red,
                                Colors.orange, _pulseCtrl.value),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'LIVE',
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Channel name
                  Text(
                    ch['name'] as String,
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                  ),

                  const SizedBox(height: 2),

                  // Watch button
                  Row(
                    children: [
                      const Icon(Icons.play_circle_outline_rounded,
                          color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'شاهد الآن',
                        style: GoogleFonts.cairo(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
