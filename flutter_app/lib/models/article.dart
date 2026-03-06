import 'dart:ui';

class Article {
  final String id;
  final String title;
  final String link;
  final String description;
  final DateTime pubDate;
  final String source;
  final String color;
  final String lang;
  final String? image;
  final bool aiImage;
  final String domain;
  final bool isNew;

  const Article({
    required this.id,
    required this.title,
    required this.link,
    required this.description,
    required this.pubDate,
    required this.source,
    required this.color,
    required this.lang,
    this.image,
    required this.aiImage,
    required this.domain,
    required this.isNew,
  });

  bool get isArabic => lang == 'ar';

  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      link: json['link']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      pubDate: json['pubDate'] != null
          ? DateTime.tryParse(json['pubDate'].toString()) ?? DateTime.now()
          : DateTime.now(),
      source: json['source']?.toString() ?? '',
      color: json['color']?.toString() ?? '#2c3e50',
      lang: json['lang']?.toString() ?? 'en',
      image: json['image']?.toString(),
      aiImage: json['aiImage'] == true,
      domain: json['domain']?.toString() ?? '',
      isNew: json['isNew'] == true,
    );
  }

  Color get sourceColor {
    try {
      final hex = color.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF2c3e50);
  }

  String get timeAgo {
    final diff = DateTime.now().difference(pubDate);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${pubDate.day}/${pubDate.month}/${pubDate.year}';
  }

  String get timeAgoAr {
    final diff = DateTime.now().difference(pubDate);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} أيام';
    return '${pubDate.day}/${pubDate.month}/${pubDate.year}';
  }
}

class NewsResponse {
  final List<Article> articles;
  final int? lastUpdated;
  final int total;
  final int fetchCount;
  final int page;
  final int totalPages;
  final bool hasMore;

  const NewsResponse({
    required this.articles,
    this.lastUpdated,
    required this.total,
    required this.fetchCount,
    this.page = 1,
    this.totalPages = 1,
    this.hasMore = false,
  });

  factory NewsResponse.fromJson(Map<String, dynamic> json) {
    final rawArticles = json['articles'] as List<dynamic>? ?? [];
    return NewsResponse(
      articles: rawArticles
          .whereType<Map<String, dynamic>>()
          .map(Article.fromJson)
          .toList(),
      lastUpdated: json['lastUpdated'] as int?,
      total: (json['total'] as num?)?.toInt() ?? 0,
      fetchCount: (json['fetchCount'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      hasMore: json['hasMore'] == true,
    );
  }
}

class NewsSource {
  final String name;
  final String color;

  const NewsSource({required this.name, required this.color});

  factory NewsSource.fromJson(Map<String, dynamic> json) {
    return NewsSource(
      name: json['name']?.toString() ?? '',
      color: json['color']?.toString() ?? '#2c3e50',
    );
  }

  Color get sourceColor {
    try {
      final hex = color.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF2c3e50);
  }
}
