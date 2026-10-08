import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
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

    controller.value = controller.value.copyWith(
      state: YouTubePlayerState.buffering,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('player-cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-loading')), findsOneWidget);

    controller.value = controller.value.copyWith(
      state: YouTubePlayerState.unstarted,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('player-cover')), findsNothing);
    expect(find.byKey(const ValueKey('player-loading')), findsNothing);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('player-cover')), findsNothing);
    expect(find.byKey(const ValueKey('player-loading')), findsNothing);

    controller.value = controller.value.copyWith(isAutoplayBlocked: true);
    await tester.pump();
    expect(find.byKey(const ValueKey('player-cover')), findsNothing);
    expect(find.byKey(const ValueKey('player-loading')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('hides custom overlays from the native buffering exit marker', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
      autoPlay: true,
    );
    const channel = MethodChannel('flutter_youtube_player/player_87');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => null);

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
      87,
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('player-cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-loading')), findsOneWidget);

    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('event', <String, Object>{
          'type': 'state',
          'value': 3,
          'hideInitialOverlay': false,
        }),
      ),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('event', <String, Object>{
          'type': 'state',
          'value': -1,
          'hideInitialOverlay': true,
        }),
      ),
      (_) {},
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('player-cover')), findsNothing);
    expect(find.byKey(const ValueKey('player-loading')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(channel, null);
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
    await tester.pump(const Duration(milliseconds: 3999));
    expect(button, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(button, findsNothing);

    controller.value = controller.value.copyWith(
      state: YouTubePlayerState.paused,
    );
    await tester.pump();
    expect(button, findsOneWidget);
    expect(
      (buttonImage().image as AssetImage).assetName,
      'assets/icons/player_play.png',
    );
    await tester.pump(const Duration(seconds: 8));
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(calls, contains('play'));

    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(channel, null);
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('can hide the built-in play-pause button', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
    );
    controller.value = controller.value.copyWith(
      state: YouTubePlayerState.playing,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 225,
          child: FlutterYouTubePlayer(
            controller: controller,
            showPlayPauseButton: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('player-play-pause')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows an externally provided embedding-disabled overlay', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 225,
          child: FlutterYouTubePlayer(
            controller: controller,
            embeddingDisabledOverlay: const ColoredBox(
              key: ValueKey('custom-embedding-disabled'),
              color: Colors.red,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('custom-embedding-disabled')),
      findsNothing,
    );

    controller.value = controller.value.copyWith(errorCode: 101);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('custom-embedding-disabled')),
      findsOneWidget,
    );

    controller.value = controller.value.copyWith(errorCode: 2);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('custom-embedding-disabled')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
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

  testWidgets('parks a retained player during route exit and discards it on close', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
      autoPlay: true,
    );
    const playerChannel = MethodChannel('flutter_youtube_player/player_109');
    const handoverChannel = MethodChannel('flutter_youtube_player/handover');
    final calls = <String>[];
    int? discardedSessionId;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(playerChannel, (call) async {
      calls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(handoverChannel, (call) async {
      if (call.method == 'discard') {
        discardedSessionId = (call.arguments as Map)['sessionId'] as int;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: FlutterYouTubePlayer(
                  controller: controller,
                  continuePlaybackOnRouteExit: true,
                ),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.widget<AndroidView>(find.byType(AndroidView)).onPlatformViewCreated!(109);
    await tester.pump();

    Navigator.of(tester.element(find.byType(FlutterYouTubePlayer))).pop();
    await tester.pump();
    expect(calls, contains('parkForHandover'));
    expect(calls, isNot(contains('suspend')));
    await tester.pump(const Duration(milliseconds: 500));
    controller.dispose();
    await tester.pump();
    expect(discardedSessionId, isNotNull);

    messenger.setMockMethodCallHandler(playerChannel, null);
    messenger.setMockMethodCallHandler(handoverChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('激活回调未返回时仍发送交接保活命令', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
      autoPlay: true,
    );
    const channel = MethodChannel('flutter_youtube_player/player_111');
    const handoverChannel = MethodChannel('flutter_youtube_player/handover');
    final activation = Completer<void>();
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'activate') await activation.future;
      return null;
    });
    messenger.setMockMethodCallHandler(handoverChannel, (call) async => null);

    await tester.pumpWidget(MaterialApp(
      home: FlutterYouTubePlayer(controller: controller),
    ));
    tester.widget<AndroidView>(find.byType(AndroidView))
        .onPlatformViewCreated!(111);
    await controller.parkForHandover();
    expect(calls, containsAllInOrder(<String>['activate', 'parkForHandover']));

    activation.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(handoverChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('cancelled back gesture resumes a parked player', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
      autoPlay: true,
    );
    const channel = MethodChannel('flutter_youtube_player/player_110');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            CupertinoPageRoute<void>(
              builder: (_) => Scaffold(
                body: SizedBox(
                  width: 400,
                  height: 225,
                  child: FlutterYouTubePlayer(
                    controller: controller,
                    continuePlaybackOnRouteExit: true,
                  ),
                ),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.widget<AndroidView>(find.byType(AndroidView)).onPlatformViewCreated!(110);
    await tester.pump();

    final navigator =
        Navigator.of(tester.element(find.byType(FlutterYouTubePlayer)));
    navigator.userGestureInProgressNotifier.value = true;
    await tester.pump();
    expect(calls, contains('parkForHandover'));
    navigator.userGestureInProgressNotifier.value = false;
    await tester.pump();
    expect(find.byType(FlutterYouTubePlayer), findsOneWidget);
    expect(calls.last, 'resume');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'prewarms while the covering route exits and then resumes playback',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final controller = FlutterYouTubePlayerController(
        initialVideoId: 'r9UYbCxus3s',
        autoPlay: true,
      );
      const channel = MethodChannel('flutter_youtube_player/player_101');
      final calls = <String>[];
      final methodCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        methodCalls.add(call);
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
      expect(calls.last, 'suspend');

      await tester.pump(const Duration(milliseconds: 500));
      Navigator.of(tester.element(find.text('cover'))).pop();
      await tester.pump();
      expect(calls.last, 'prewarm');

      await tester.pump(const Duration(milliseconds: 500));
      expect(calls.last, 'resume');
      expect(methodCalls.last.arguments, <String, Object>{'play': true});

      messenger.setMockMethodCallHandler(channel, null);
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('does not autoplay a manually paused player after route return', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
      autoPlay: true,
    );
    const channel = MethodChannel('flutter_youtube_player/player_103');
    final methodCalls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      methodCalls.add(call);
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
    tester.widget<AndroidView>(find.byType(AndroidView)).onPlatformViewCreated!(
      103,
    );
    await controller.pause();

    await tester.tap(find.text('push cover'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    Navigator.of(tester.element(find.text('cover'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final resumeCall = methodCalls.lastWhere((call) => call.method == 'resume');
    expect(resumeCall.arguments, <String, Object>{'play': false});

    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(channel, null);
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('suspends again when an interactive route pop is cancelled', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
      autoPlay: true,
    );
    const channel = MethodChannel('flutter_youtube_player/player_102');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
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
                    CupertinoPageRoute<void>(
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
    tester.widget<AndroidView>(find.byType(AndroidView)).onPlatformViewCreated!(
      102,
    );

    await tester.tap(find.text('push cover'));
    await tester.pumpAndSettle();
    expect(calls.last, 'suspend');

    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(calls.last, 'prewarm');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('cover'), findsOneWidget);
    expect(calls.last, 'suspend');

    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(channel, null);
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

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

        final arguments = activation?.arguments as Map;
        expect(arguments['videoId'], 'r9UYbCxus3s');
        expect(arguments['autoplay'], isTrue);
        expect(arguments['startSeconds'], 1.25);
        expect(arguments['muted'], isFalse);
        expect(arguments['sessionId'], isA<int>());
        expect(arguments['reuseCurrentVideo'], isFalse);
        expect(calls, <String>['activate', 'play']);

        await tester.pumpWidget(const SizedBox.shrink());
        messenger.setMockMethodCallHandler(channel, null);
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('旧视图迟到的解绑不会移除新视图通道', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
      autoPlay: true,
    );
    final oldActivation = Completer<void>();
    const oldChannel = MethodChannel('flutter_youtube_player/player_78');
    const newChannel = MethodChannel('flutter_youtube_player/player_79');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final newCalls = <String>[];
    MethodCall? oldActivateCall;
    MethodCall? newActivation;
    messenger.setMockMethodCallHandler(oldChannel, (call) async {
      if (call.method == 'activate') {
        oldActivateCall = call;
        await oldActivation.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(newChannel, (call) async {
      newCalls.add(call.method);
      if (call.method == 'activate') newActivation = call;
      return null;
    });

    Widget host({required bool old, required bool next}) => MaterialApp(
      home: Stack(children: [
        if (old)
          SizedBox(
            key: const ValueKey('old'),
            width: 200,
            height: 200,
            child: FlutterYouTubePlayer(controller: controller),
          ),
        if (next)
          SizedBox(
            key: const ValueKey('next'),
            width: 200,
            height: 200,
            child: FlutterYouTubePlayer(controller: controller),
          ),
      ]),
    );

    await tester.pumpWidget(host(old: true, next: false));
    tester.widget<AndroidView>(find.byType(AndroidView))
        .onPlatformViewCreated!(78);
    controller.reuseCurrentVideoOnNextAttach(
      resumePosition: const Duration(seconds: 10),
    );
    await tester.pumpWidget(host(old: true, next: true));
    tester.widgetList<AndroidView>(find.byType(AndroidView)).last
        .onPlatformViewCreated!(79);
    await tester.pumpWidget(host(old: false, next: true));
    oldActivation.complete();
    await tester.pump();
    await controller.pause();

    expect((newActivation?.arguments as Map)['reuseCurrentVideo'], isTrue);
    expect((newActivation?.arguments as Map)['startSeconds'], 10.0);
    expect((newActivation?.arguments as Map)['sessionId'],
        (oldActivateCall?.arguments as Map)['sessionId']);
    expect(newCalls, <String>['activate', 'pause']);

    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(oldChannel, null);
    messenger.setMockMethodCallHandler(newChannel, null);
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('替换 controller 后忽略旧平台视图的创建回调', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final oldController = FlutterYouTubePlayerController(
      initialVideoId: 'r9UYbCxus3s',
    );
    final newController = FlutterYouTubePlayerController(
      initialVideoId: 'M7lc1UVf-VE',
    );
    const oldChannel = MethodChannel('flutter_youtube_player/player_80');
    const newChannel = MethodChannel('flutter_youtube_player/player_81');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final oldCalls = <String>[];
    final newCalls = <String>[];
    messenger.setMockMethodCallHandler(oldChannel, (call) async {
      oldCalls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(newChannel, (call) async {
      newCalls.add(call.method);
      return null;
    });

    Widget host(FlutterYouTubePlayerController controller) => MaterialApp(
      home: SizedBox(
        width: 200,
        height: 200,
        child: FlutterYouTubePlayer(controller: controller),
      ),
    );

    await tester.pumpWidget(host(oldController));
    final oldView = tester.widget<AndroidView>(find.byType(AndroidView));
    await tester.pumpWidget(host(newController));
    oldView.onPlatformViewCreated!(80);
    tester.widget<AndroidView>(find.byType(AndroidView))
        .onPlatformViewCreated!(81);
    await tester.pump();

    expect(oldCalls, isEmpty);
    expect(newCalls, <String>['activate']);

    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(oldChannel, null);
    messenger.setMockMethodCallHandler(newChannel, null);
    oldController.dispose();
    newController.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
