import 'package:flutter/material.dart';

class Video {
  final String id;
  final String videoId;
  final String title;
  final String description;
  final String channel;
  final String channelId;
  final String color;
  final String lang;
  final String thumbnail;
  final DateTime published;

  const Video({
    required this.id,
    required this.videoId,
    required this.title,
    required this.description,
    required this.channel,
    required this.channelId,
    required this.color,
    required this.lang,
    required this.thumbnail,
    required this.published,
  });

  factory Video.fromJson(Map<String, dynamic> j) => Video(
        id:          j['id']?.toString() ?? '',
        videoId:     j['videoId']?.toString() ?? '',
        title:       j['title']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        channel:     j['channel']?.toString() ?? '',
        channelId:   j['channelId']?.toString() ?? '',
        color:       j['color']?.toString() ?? '#333333',
        lang:        j['lang']?.toString() ?? 'ar',
        thumbnail:   j['thumbnail']?.toString() ?? '',
        published: j['published'] != null
            ? DateTime.tryParse(j['published'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );

  bool get isArabic => lang == 'ar';

  Color get channelColor {
    try {
      return Color(int.parse(color.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF333333);
    }
  }

  String get timeAgo {
    final diff = DateTime.now().difference(published);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get timeAgoAr {
    final diff = DateTime.now().difference(published);
    if (diff.inMinutes < 1)  return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24)   return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  String get youtubeUrl => 'https://www.youtube.com/watch?v=$videoId';
}

class VideoResponse {
  final List<Video> videos;
  final int total;
  final int page;
  final int totalPages;
  final bool hasMore;

  const VideoResponse({
    required this.videos,
    required this.total,
    this.page = 1,
    this.totalPages = 1,
    this.hasMore = false,
  });

  factory VideoResponse.fromJson(Map<String, dynamic> json) {
    final list = json['videos'] as List<dynamic>? ?? [];
    return VideoResponse(
      videos:     list.whereType<Map<String, dynamic>>().map(Video.fromJson).toList(),
      total:      (json['total'] as num?)?.toInt() ?? 0,
      page:       (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      hasMore:    json['hasMore'] == true,
    );
  }
}
