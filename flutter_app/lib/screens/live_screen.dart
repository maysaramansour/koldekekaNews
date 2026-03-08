import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'live_player_screen.dart';
import 'radio_player_screen.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  // Only channels with reliable public CDN HLS streams
  static const _tvChannels = [
    {
      'name': 'العربية',
      'sub': 'Al Arabiya',
      'streamUrl': 'https://live.alarabiya.net/alarabiapublish/alarabiya.smil/playlist.m3u8',
      'color': 0xFF884ea0,
      'icon': '📡',
    },
    {
      'name': 'DW عربية',
      'sub': 'DW Arabic',
      'streamUrl': 'https://dwamdstream106.akamaized.net/hls/live/2017965/dwstream106/index.m3u8',
      'color': 0xFF2471a3,
      'icon': '📰',
    },
    {
      'name': 'فرانس 24',
      'sub': 'France 24 Arabic',
      'streamUrl': 'https://static.france24.com/live/F24_AR_LO_HLS/live_web.m3u8',
      'color': 0xFF154360,
      'icon': '🗞️',
    },
    {
      'name': 'سكاي نيوز عربية',
      'sub': 'Sky News Arabia',
      'streamUrl': 'https://skynewsarabia-live.akamaized.net/hls/live/2002309/skynewsarabia/master.m3u8',
      'color': 0xFF1a5276,
      'icon': '🌐',
    },
  ];

  // Arabic news radio stations with reliable streams
  static const _radioStations = [
    {
      'name': 'مونت كارلو الدولية',
      'sub': 'Monte Carlo Doualiya',
      'streamUrl': 'https://icecast.mcd.fr/mcd_ar_mp3_128k',
      'color': 0xFF1a5276,
      'icon': '📻',
    },
    {
      'name': 'BBC عربي راديو',
      'sub': 'BBC Arabic Radio',
      'streamUrl': 'https://bbcwssc.ic.llnwd.net/stream/bbcwssc_mp3_ws-arws',
      'color': 0xFFc0392b,
      'icon': '🎙️',
    },
    {
      'name': 'راديو فرانس الدولي',
      'sub': 'RFI Arabic',
      'streamUrl': 'https://live02.rfi.fr/rfiarabic-96k.mp3',
      'color': 0xFF003189,
      'icon': '🌐',
    },
    {
      'name': 'DW راديو عربي',
      'sub': 'DW Arabic Radio',
      'streamUrl': 'https://dwamdstream104.akamaized.net/hls/live/2015530/dwstream104/index.m3u8',
      'color': 0xFF2471a3,
      'icon': '📡',
    },
    {
      'name': 'راديو سوا',
      'sub': 'Radio Sawa (VOA)',
      'streamUrl': 'https://voa-ingest.akamaized.net/hls/live/2033888/SAWA/master.m3u8',
      'color': 0xFF27ae60,
      'icon': '🔊',
    },
    {
      'name': 'صوت أمريكا العربية',
      'sub': 'VOA Arabic',
      'streamUrl': 'https://voa-ingest.akamaized.net/hls/live/2033895/VOAARAB/master.m3u8',
      'color': 0xFF884ea0,
      'icon': '📣',
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

  void _openTv(Map<String, dynamic> ch) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LivePlayerScreen(
          channelId: '',
          channelName: ch['name'] as String,
          channelColor: Color(ch['color'] as int),
          streamUrl: ch['streamUrl'] as String,
        ),
      ),
    );
  }

  void _openRadio(Map<String, dynamic> station) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RadioPlayerScreen(
          stationName: station['name'] as String,
          stationSub: station['sub'] as String,
          streamUrl: station['streamUrl'] as String,
          color: Color(station['color'] as int),
          icon: station['icon'] as String,
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
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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

          // ── TV section header ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.tv_rounded, color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'قنوات تلفزيونية',
                    style: GoogleFonts.cairo(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
          ),

          // ── TV grid ─────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildCard(
                  _tvChannels[i],
                  onTap: () => _openTv(_tvChannels[i]),
                  label: 'شاهد الآن',
                  icon: Icons.play_circle_outline_rounded,
                ),
                childCount: _tvChannels.length,
              ),
            ),
          ),

          // ── Radio section header ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.radio_rounded, color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'إذاعات إخبارية',
                    style: GoogleFonts.cairo(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
          ),

          // ── Radio grid ──────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildCard(
                  _radioStations[i],
                  onTap: () => _openRadio(_radioStations[i]),
                  label: 'استمع الآن',
                  icon: Icons.headphones_rounded,
                ),
                childCount: _radioStations.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    Map<String, dynamic> ch, {
    required VoidCallback onTap,
    required String label,
    required IconData icon,
  }) {
    final color = Color(ch['color'] as int);

    return GestureDetector(
      onTap: onTap,
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
            Positioned(
              right: -8,
              bottom: -8,
              child: Text(ch['icon'] as String,
                  style: const TextStyle(fontSize: 56)),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                                Colors.red, Colors.orange, _pulseCtrl.value),
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
                  Row(
                    children: [
                      Icon(icon, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(label,
                          style: GoogleFonts.cairo(
                              color: Colors.white70, fontSize: 11)),
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
