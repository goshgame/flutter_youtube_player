import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_youtube_player/flutter_youtube_player.dart';
import 'package:flutter_youtube_player_example/episode.dart';
import 'package:flutter_youtube_player_example/episode_player_page.dart';
import 'package:flutter_youtube_player_example/episode_repository.dart';
import 'package:flutter_youtube_player_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('example video ID is valid', () {
    expect(
      FlutterYouTubePlayerController.isValidVideoId('r9UYbCxus3s'),
      isTrue,
    );
  });

  test('bundled episodes load as a complete local list', () async {
    final page = await EpisodeRepository().loadPage();

    expect(page.episodes, hasLength(20));
    expect(page.episodes.first.videoId, 'vlHh6B5_-z4');
    expect(page.episodes.last.videoId, 'y84USJTIlsU');
    expect(page.nextCursor, isNull);
    expect(page.hasMore, isFalse);
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

  testWidgets('episode player validates an entered YouTube video ID', (
    tester,
  ) async {
    const episode = Episode(
      id: 1,
      videoId: 'CoihJCn01Rk',
      title: 'Morning News',
      duration: '20:06',
      podcast: 'NBC News',
    );
    await tester.pumpWidget(
      const MaterialApp(home: EpisodePlayerPage(episode: episode)),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();

    final input = find.byKey(const ValueKey('youtube-video-id-input'));
    expect(input, findsOneWidget);
    expect(find.text('CoihJCn01Rk'), findsOneWidget);

    await tester.enterText(input, 'invalid');
    await tester.tap(find.byKey(const ValueKey('load-youtube-video')));
    await tester.pump();
    expect(find.text('请输入有效的 11 位 YouTube 视频 ID'), findsOneWidget);

    await tester.enterText(input, 'lOnDRI_G3tg');
    await tester.pump();
    expect(find.text('请输入有效的 11 位 YouTube 视频 ID'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('episode player can push the next episode player page', (
    tester,
  ) async {
    const firstEpisode = Episode(
      id: 1,
      videoId: 'CoihJCn01Rk',
      title: 'Morning News',
      duration: '20:06',
      podcast: 'NBC News',
    );
    const nextEpisode = Episode(
      id: 2,
      videoId: 'lOnDRI_G3tg',
      title: 'Evening News',
      duration: '18:42',
      podcast: 'NBC News',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const EpisodePlayerPage(
          episode: firstEpisode,
          nextEpisode: nextEpisode,
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();

    expect(find.text('播放下一集'), findsOneWidget);
    expect(find.text('Evening News'), findsOneWidget);

    tester
        .widget<ListTile>(find.byKey(const ValueKey('open-next-episode')))
        .onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final playerPages = find.byType(EpisodePlayerPage, skipOffstage: false);
    expect(playerPages, findsNWidgets(2));
    expect(
      tester
          .widgetList<EpisodePlayerPage>(playerPages)
          .map((page) => page.episode),
      contains(nextEpisode),
    );

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Morning News'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
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
