import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'reels_screen.dart';
import 'video_reels_screen.dart';
import '../widgets/video_reel_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: VideoReelCard.fullscreenNotifier,
        builder: (_, isFullscreen, __) => Scaffold(
          backgroundColor: Colors.black,
          body: IndexedStack(
            index: _tab,
            children: [
              ReelsScreen(isActive: _tab == 0),
              ReelsScreen(urgentOnly: true, isActive: _tab == 1),
              VideoReelsScreen(isActive: _tab == 2),
            ],
          ),
          bottomNavigationBar: isFullscreen ? null : _buildNavBar(),
        ),
      );

  Widget _buildNavBar() => Container(
        decoration: const BoxDecoration(
          border: Border(
              top: BorderSide(color: Color(0xFF222222), width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          backgroundColor: const Color(0xFF0a0a14),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white30,
          selectedLabelStyle:
              GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.cairo(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.newspaper_rounded),
              activeIcon: Icon(Icons.newspaper_rounded, size: 28),
              label: 'الأخبار',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bolt_rounded, color: Colors.red),
              activeIcon: Icon(Icons.bolt_rounded, size: 28, color: Colors.red),
              label: 'عاجل',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.smart_display_rounded),
              activeIcon: Icon(Icons.smart_display_rounded,
                  size: 28, color: Color(0xFFFF0000)),
              label: 'فيديو',
            ),
          ],
        ),
      );
}
