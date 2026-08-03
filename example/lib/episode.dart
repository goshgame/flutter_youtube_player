class EpisodePage {
  const EpisodePage({
    required this.episodes,
    required this.nextCursor,
    required this.hasMore,
  });

  factory EpisodePage.fromJson(Map<String, dynamic> json) => EpisodePage(
    episodes: (json['episodes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Episode.fromJson)
        .where((episode) => episode.hasValidVideoId)
        .toList(growable: false),
    nextCursor: (json['next_cursor'] as num?)?.toInt(),
    hasMore: json['has_more'] as bool? ?? false,
  );

  final List<Episode> episodes;
  final int? nextCursor;
  final bool hasMore;
}

class Episode {
  const Episode({
    required this.id,
    required this.videoId,
    required this.title,
    required this.duration,
    required this.podcast,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    final podcast = json['podcast'] as Map<String, dynamic>?;
    return Episode(
      id: (json['id'] as num?)?.toInt() ?? 0,
      videoId: json['video_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      duration: json['duration'] as String? ?? '',
      podcast: podcast?['title'] as String? ?? '',
    );
  }

  final int id;
  final String videoId;
  final String title;
  final String duration;
  final String podcast;

  bool get hasValidVideoId => RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId);
}
