import 'package:flutter/material.dart';
import '../services/news_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostController = TextEditingController(
    text: NewsService.serverBase,
  );
  Map<String, dynamic>? _status;
  bool _loadingStatus = false;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _loadingStatus = true;
      _statusError = null;
    });
    try {
      final status = await NewsService().fetchStatus();
      setState(() {
        _status = status;
        _loadingStatus = false;
      });
    } catch (e) {
      setState(() {
        _statusError = e.toString();
        _loadingStatus = false;
      });
    }
  }

  void _applyHost() {
    final raw = _hostController.text.trim();
    if (raw.isEmpty) return;
    final base = raw.endsWith('/')
        ? raw.substring(0, raw.length - 1)
        : raw;
    NewsService.setServerBase(base);
    NewsService().clearCache();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server URL updated. Refresh the feed.')),
    );
    _checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d0d1a),
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0d0d1a),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Server connection ──────────────────────────────────────────────
          _sectionHeader('Server Connection'),
          const SizedBox(height: 12),

          // Status card
          _buildStatusCard(),
          const SizedBox(height: 16),

          // Host input
          Text('Server URL',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hostController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'https://us-central1-kol-dekeka.cloudfunctions.net/api',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _applyHost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2471a3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Default: Firebase Cloud Functions (works on any network)\n'
            'Override only if running a local server.',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),

          const SizedBox(height: 32),
          _sectionHeader('About'),
          const SizedBox(height: 12),
          _infoTile('App', 'Arab News Reels'),
          _infoTile('Backend', 'Firebase Cloud Functions'),
          _infoTile('Sources', '25+ Arab & Middle East outlets'),
          _infoTile('Auto-refresh', 'Every 1 minute'),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    if (_loadingStatus) {
      return _statusCard(
        icon: Icons.circle,
        iconColor: Colors.amber,
        title: 'Checking connection…',
        subtitle: '',
      );
    }

    if (_statusError != null) {
      return _statusCard(
        icon: Icons.cancel_outlined,
        iconColor: Colors.red,
        title: 'Server unreachable',
        subtitle: 'Check your internet connection or server URL.',
        trailing: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white54),
          onPressed: _checkStatus,
        ),
      );
    }

    if (_status != null) {
      return _statusCard(
        icon: Icons.check_circle_outline,
        iconColor: Colors.greenAccent,
        title: 'Connected',
        subtitle:
            '${_status!['total']} articles  •  fetch #${_status!['fetchCount']}',
        trailing: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white54),
          onPressed: _checkStatus,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _statusCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text('$label  ',
              style: const TextStyle(color: Colors.white54, fontSize: 14)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
