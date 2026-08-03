import 'dart:convert';
import 'dart:io';

import 'episode.dart';

abstract interface class EpisodeDataSource {
  Future<EpisodePage> loadPage({int? cursor});
}

class EpisodeRepository implements EpisodeDataSource {
  static const endpoint =
      'http://podoc.jiamid.com/api/v1/tags/%E6%96%B0%E9%97%BB/episodes';

  @override
  Future<EpisodePage> loadPage({int? cursor}) async {
    final baseUri = Uri.parse(endpoint);
    final uri = cursor == null
        ? baseUri
        : baseUri.replace(queryParameters: {'cursor': '$cursor'});
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException('Server returned ${response.statusCode}', uri: uri);
      }

      final source = await response.transform(utf8.decoder).join();
      final json = jsonDecode(source);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Unexpected response format');
      }
      return EpisodePage.fromJson(json);
    } finally {
      client.close(force: true);
    }
  }
}
