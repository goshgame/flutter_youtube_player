import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_youtube_player/flutter_youtube_player.dart';
import 'package:flutter_youtube_player_example/episode.dart';
import 'package:flutter_youtube_player_example/episode_repository.dart';
import 'package:flutter_youtube_player_example/main.dart';

void main() {
  test('example video ID is valid', () {
    expect(
      FlutterYouTubePlayerController.isValidVideoId('r9UYbCxus3s'),
      isTrue,
    );
  });

  test('news endpoint uses the requested tag API', () {
    expect(
      EpisodeRepository.endpoint,
      'http://podoc.jiamid.com/api/v1/tags/%E6%96%B0%E9%97%BB/episodes',
    );
  });

  test('episode page parses playable videos and pagination', () {
    final page = EpisodePage.fromJson({
      'next_cursor': 14625,
      'has_more': true,
      'episodes': [
        {
          'id': 14667,
          'video_id': 'CoihJCn01Rk',
          'title': 'Morning News',
          'duration': '20:06',
          'podcast': {'title': 'NBC News'},
        },
        {'id': 2, 'video_id': 'invalid'},
      ],
    });

    expect(page.nextCursor, 14625);
    expect(page.hasMore, isTrue);
    expect(page.episodes, hasLength(1));
    expect(page.episodes.single.videoId, 'CoihJCn01Rk');
    expect(page.episodes.single.podcast, 'NBC News');
  });

  testWidgets('home page shows the episode list without a player', (
    tester,
  ) async {
    final navigatorObserver = _RecordingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [navigatorObserver],
        home: NewsListPage(repository: _FakeEpisodeRepository()),
      ),
    );
    await tester.pump();

    expect(find.text('新闻视频'), findsOneWidget);
    expect(find.text('Morning News'), findsOneWidget);
    expect(find.byType(FlutterYouTubePlayer), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.tap(find.text('Morning News'));
    expect(navigatorObserver.pushCount, 2);
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

class _FakeEpisodeRepository implements EpisodeDataSource {
  @override
  Future<EpisodePage> loadPage({int? cursor}) async => const EpisodePage(
    episodes: [
      Episode(
        id: 1,
        videoId: 'CoihJCn01Rk',
        title: 'Morning News',
        duration: '20:06',
        podcast: 'NBC News',
      ),
    ],
    nextCursor: null,
    hasMore: false,
  );
}
