import 'dart:convert';

import 'package:flutter/services.dart';

import 'episode.dart';

abstract interface class EpisodeDataSource {
  Future<EpisodePage> loadPage({int? cursor});
}

class EpisodeRepository implements EpisodeDataSource {
  @override
  Future<EpisodePage> loadPage({int? cursor}) async {
    final source = await rootBundle.loadString('assets/episodes.json');
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Unexpected episodes asset format');
    }
    final page = EpisodePage.fromJson(json);
    // The bundled file is the complete local list, regardless of API metadata.
    return EpisodePage(
      episodes: page.episodes,
      nextCursor: null,
      hasMore: false,
    );
  }
}
