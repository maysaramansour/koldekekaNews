import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/article.dart';
import '../services/news_service.dart';
import '../widgets/article_webview.dart';

class ArticleScreen extends StatefulWidget {
  final Article article;
  const ArticleScreen({super.key, required this.article});

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late final WebViewController _webController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0d0d1a));
    _loadBody();
  }

  Future<void> _loadBody() async {
    String body = '';
    if (widget.article.link.isNotEmpty) {
      try {
        final data = await NewsService().fetchArticle(widget.article.link);
        final b = data['body']?.toString() ?? '';
        final d = data['description']?.toString() ?? '';
        body = b.isNotEmpty ? b : d;
      } catch (_) {
        body = widget.article.description;
      }
    } else {
      body = widget.article.description;
    }
    if (mounted) {
      await _webController.loadHtmlString(_buildHtml(body));
      setState(() => _loading = false);
    }
  }

  bool get _isAr => widget.article.isArabic;

  String _buildHtml(String body) {
    final article = widget.article;
    final dir = _isAr ? 'rtl' : 'ltr';
    final color = article.color;
    final imageHtml = (article.image != null && article.image!.isNotEmpty)
        ? '<img src="${article.image}" class="hero-img" onerror="this.style.display=\'none\'">'
        : '<div class="hero-placeholder" style="background:${color}44"></div>';
    final bodyHtml = body.isNotEmpty
        ? body.replaceAll('\n', '<br>')
        : (_isAr ? 'لا يتوفر محتوى.' : 'No content available.');
    final readMoreLabel = _isAr ? 'قراءة المقال كاملاً' : 'Read full article';
    final timeLabel = _isAr ? article.timeAgoAr : article.timeAgo;

    return '''<!DOCTYPE html>
<html dir="$dir" lang="${_isAr ? 'ar' : 'en'}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #0d0d1a;
      color: rgba(255,255,255,0.88);
      font-family: 'Cairo', 'Noto Naskh Arabic', Arial, sans-serif;
      font-size: ${_isAr ? 17 : 16}px;
      line-height: 1.75;
      direction: $dir;
    }
    .hero-img {
      width: 100%;
      max-height: 220px;
      object-fit: cover;
      display: block;
    }
    .hero-placeholder {
      width: 100%;
      height: 120px;
    }
    .content { padding: 18px 16px 48px; }
    .meta {
      display: flex;
      align-items: center;
      gap: 10px;
      flex-wrap: wrap;
      margin-bottom: 14px;
    }
    .source-chip {
      background: $color;
      color: #fff;
      font-size: 12px;
      font-weight: 700;
      padding: 3px 10px;
      border-radius: 6px;
    }
    .time {
      color: rgba(255,255,255,0.4);
      font-size: 12px;
    }
    h1 {
      color: #fff;
      font-size: ${_isAr ? 20 : 19}px;
      font-weight: 700;
      line-height: 1.4;
      margin-bottom: 16px;
    }
    hr {
      border: none;
      border-top: 1px solid rgba(255,255,255,0.1);
      margin: 0 0 16px;
    }
    .body-text {
      color: rgba(255,255,255,0.85);
      font-size: ${_isAr ? 17 : 16}px;
      line-height: 1.75;
    }
    .body-text p { margin-bottom: 12px; }
    .read-more {
      display: block;
      width: 100%;
      margin-top: 28px;
      padding: 14px;
      background: $color;
      color: #fff;
      font-family: 'Cairo', sans-serif;
      font-size: 15px;
      font-weight: 600;
      text-align: center;
      border: none;
      border-radius: 12px;
      cursor: pointer;
      text-decoration: none;
    }
  </style>
</head>
<body>
  $imageHtml
  <div class="content">
    <div class="meta">
      <span class="source-chip">${article.source}</span>
      <span class="time">⏱ $timeLabel</span>
    </div>
    <h1>${article.title}</h1>
    <hr>
    <div class="body-text">$bodyHtml</div>
    <a class="read-more" href="${article.link}" target="_blank">$readMoreLabel</a>
  </div>
  <script>
    document.querySelector('.read-more').addEventListener('click', function(e) {
      e.preventDefault();
      window.open(this.href, '_blank');
    });
  </script>
</body>
</html>''';
  }

  Future<void> _openBrowser() async {
    if (widget.article.link.isNotEmpty && mounted) {
      await ArticleWebView.show(
        context,
        widget.article.link,
        title: widget.article.title,
      );
    }
  }

  void _share() {
    Share.share(
      '${widget.article.title}\n\n${widget.article.link}',
      subject: widget.article.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d0d1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131f),
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white, size: 22),
            onPressed: _share,
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded,
                color: Colors.white, size: 22),
            onPressed: _openBrowser,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(
            controller: _webController,
            gestureRecognizers: {
              Factory<VerticalDragGestureRecognizer>(
                () => VerticalDragGestureRecognizer(),
              ),
              Factory<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(),
              ),
            },
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),
        ],
      ),
    );
  }
}
