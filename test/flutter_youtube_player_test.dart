import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_youtube_player/flutter_youtube_player.dart';

void main() {
  test('validates YouTube video IDs', () {
    expect(
      FlutterYouTubePlayerController.isValidVideoId('r9UYbCxus3s'),
      isTrue,
    );
    expect(FlutterYouTubePlayerController.isValidVideoId('too-short'), isFalse);
    expect(
      FlutterYouTubePlayerController.isValidVideoId('bad id here'),
      isFalse,
    );
  });

  test('maps IFrame player state codes', () {
    expect(YouTubePlayerState.fromCode(1), YouTubePlayerState.playing);
    expect(YouTubePlayerState.fromCode(42), YouTubePlayerState.unknown);
  });

  test('builds YouTube thumbnail URLs from a video ID', () {
    const thumbnails = ThumbnailSet('r9UYbCxus3s');

    expect(
      thumbnails.lowResUrl,
      'https://img.youtube.com/vi/r9UYbCxus3s/default.jpg',
    );
    expect(
      thumbnails.mediumResUrl,
      'https://img.youtube.com/vi/r9UYbCxus3s/mqdefault.jpg',
    );
    expect(
      thumbnails.highResUrl,
      'https://img.youtube.com/vi/r9UYbCxus3s/hqdefault.jpg',
    );
    expect(
      thumbnails.standardResUrl,
      'https://img.youtube.com/vi/r9UYbCxus3s/sddefault.jpg',
    );
    expect(
      thumbnails.maxResUrl,
      'https://img.youtube.com/vi/r9UYbCxus3s/maxresdefault.jpg',
    );
  });

  test('controller rejects an invalid video ID', () {
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
    );
    expect(() => controller.load('invalid'), throwsArgumentError);
    controller.dispose();
  });

  test('controller constructor rejects an invalid initial video ID', () {
    expect(
      () => FlutterYouTubePlayerController(initialVideoId: 'invalid'),
      throwsArgumentError,
    );
  });

  test('controller validates and exposes the initial playback position', () {
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
      initialPosition: const Duration(milliseconds: 1250),
    );

    expect(controller.value.position, const Duration(milliseconds: 1250));
    expect(
      () => FlutterYouTubePlayerController(
        initialVideoId: 'r9UYbCxus3s',
        initialPosition: const Duration(milliseconds: -1),
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.load(
        'M7lc1UVf-VE',
        initialPosition: const Duration(milliseconds: -1),
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.seekTo(const Duration(milliseconds: -1)),
      throwsArgumentError,
    );
    controller.dispose();
  });

  test('volume and playback rate validate their ranges', () {
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
    );

    expect(() => controller.setVolume(-1), throwsRangeError);
    expect(() => controller.setVolume(101), throwsRangeError);
    expect(() => controller.setPlaybackRate(0), throwsArgumentError);
    expect(() => controller.setPlaybackRate(double.nan), throwsArgumentError);
    controller.dispose();
  });

  testWidgets('shows loading until playback starts', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
      autoPlay: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 225,
          child: FlutterYouTubePlayer(controller: controller),
        ),
      ),
    );

    expect(
      find.ancestor(
        of: find.byType(AndroidView),
        matching: find.byWidgetPredicate(
          (widget) => widget is AbsorbPointer && widget.absorbing,
        ),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('player-cover')), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byKey(const ValueKey('player-cover'))).image
              as NetworkImage)
          .url,
      'https://img.youtube.com/vi/r9UYbCxus3s/hqdefault.jpg',
    );
    expect(find.byKey(const ValueKey('player-loading')), findsNothing);
    await tester.pump(const Duration(milliseconds: 119));
    expect(find.byKey(const ValueKey('player-loading')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('player-loading')), findsOneWidget);
    final loadingIndicator = find.descendant(
      of: find.byKey(const ValueKey('player-loading')),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(
      tester.widget<CircularProgressIndicator>(loadingIndicator).value,
      0.75,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('player-loading')),
        matching: find.byType(RotationTransition),
      ),
      findsOneWidget,
    );

    controller.value = controller.value.copyWith(
      state: YouTubePlayerState.playing,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('player-cover')), findsNothing);
    expect(find.byKey(const ValueKey('player-loading')), findsNothing);

    controller.value = controller.value.copyWith(
      videoId: 'M7lc1UVf-VE',
      state: YouTubePlayerState.unstarted,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('player-cover')), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byKey(const ValueKey('player-cover'))).image
              as NetworkImage)
          .url,
      'https://img.youtube.com/vi/M7lc1UVf-VE/hqdefault.jpg',
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('player-loading')), findsOneWidget);

    controller.value = controller.value.copyWith(isAutoplayBlocked: true);
    await tester.pump();
    expect(find.byKey(const ValueKey('player-cover')), findsNothing);
    expect(find.byKey(const ValueKey('player-loading')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows a 56px play-pause button matching player state', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
    );
    const channel = MethodChannel('flutter_youtube_player/player_88');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 225,
          child: FlutterYouTubePlayer(controller: controller),
        ),
      ),
    );
    tester.widget<AndroidView>(find.byType(AndroidView)).onPlatformViewCreated!(
      88,
    );
    await tester.pump();

    controller.value = controller.value.copyWith(
      state: YouTubePlayerState.playing,
    );
    await tester.pump();

    final button = find.byKey(const ValueKey('player-play-pause'));
    expect(button, findsOneWidget);
    expect(tester.getSize(button), const Size.square(56));
    final material = tester.widget<Material>(button);
    expect(material.color, const Color.fromRGBO(0, 0, 0, 0.3));
    expect(material.shape, const CircleBorder());
    final iconButton = tester.widget<IconButton>(
      find.descendant(of: button, matching: find.byType(IconButton)),
    );
    expect(iconButton.padding, const EdgeInsets.all(10));
    Image buttonImage() => tester.widget<Image>(
      find.descendant(of: button, matching: find.byType(Image)),
    );
    expect(buttonImage().width, 36);
    expect(buttonImage().height, 36);
    expect(
      (buttonImage().image as AssetImage).assetName,
      'assets/icons/player_pause.png',
    );

    await tester.tap(button);
    await tester.pump();
    expect(calls, contains('pause'));

    controller.value = controller.value.copyWith(
      state: YouTubePlayerState.paused,
    );
    await tester.pump();
    expect(
      (buttonImage().image as AssetImage).assetName,
      'assets/icons/player_play.png',
    );

    await tester.tap(button);
    await tester.pump();
    expect(calls, contains('play'));

    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(channel, null);
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('suspends the native player before a route pop animation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
      autoPlay: true,
    );
    const channel = MethodChannel('flutter_youtube_player/player_99');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: FlutterYouTubePlayer(controller: controller),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.widget<AndroidView>(find.byType(AndroidView)).onPlatformViewCreated!(
      99,
    );

    Navigator.of(tester.element(find.byType(FlutterYouTubePlayer))).pop();
    await tester.pump();

    expect(calls, contains('suspend'));
    await tester.pump(const Duration(milliseconds: 500));

    messenger.setMockMethodCallHandler(channel, null);
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'suspends while covered and resumes after the route is revealed',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final controller = FlutterYouTubePlayerController(
        initialVideoId: 'r9UYbCxus3s',
        autoPlay: true,
      );
      const channel = MethodChannel('flutter_youtube_player/player_101');
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  SizedBox(
                    width: 400,
                    height: 225,
                    child: FlutterYouTubePlayer(controller: controller),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: Text('cover')),
                      ),
                    ),
                    child: const Text('push cover'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      tester
          .widget<AndroidView>(find.byType(AndroidView))
          .onPlatformViewCreated!(101);
      controller.value = controller.value.copyWith(
        state: YouTubePlayerState.playing,
      );
      await tester.pump();

      await tester.tap(find.text('push cover'));
      await tester.pump();
      expect(calls, contains('suspend'));

      await tester.pump(const Duration(milliseconds: 500));
      Navigator.of(tester.element(find.text('cover'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, contains('resume'));

      messenger.setMockMethodCallHandler(channel, null);
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      'activates a ${platform.name} player before replaying pending commands',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final controller = FlutterYouTubePlayerController(
          initialVideoId: 'r9UYbCxus3s',
          initialPosition: const Duration(milliseconds: 1250),
        );
        const viewId = 77;
        const channel = MethodChannel('flutter_youtube_player/player_77');
        MethodCall? activation;
        final calls = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'activate') activation = call;
          return null;
        });
        final pendingPlay = controller.play();

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 400,
              height: 225,
              child: FlutterYouTubePlayer(controller: controller),
            ),
          ),
        );
        if (platform == TargetPlatform.android) {
          tester
              .widget<AndroidView>(find.byType(AndroidView))
              .onPlatformViewCreated!(viewId);
        } else {
          tester
              .widget<UiKitView>(find.byType(UiKitView))
              .onPlatformViewCreated!(viewId);
        }
        await pendingPlay;

        expect(activation?.arguments, <String, Object>{
          'videoId': 'r9UYbCxus3s',
          'autoplay': true,
          'startSeconds': 1.25,
          'muted': false,
        });
        expect(calls, <String>['activate', 'play']);

        await tester.pumpWidget(const SizedBox.shrink());
        messenger.setMockMethodCallHandler(channel, null);
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
