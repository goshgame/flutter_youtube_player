import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String _viewType = 'flutter_youtube_player/player';
const String _channelPrefix = 'flutter_youtube_player/player_';

/// YouTube thumbnail URLs derived from a video ID.
@immutable
class ThumbnailSet {
  const ThumbnailSet(this.videoId);

  /// Video ID.
  final String videoId;

  /// Low resolution thumbnail URL.
  String get lowResUrl => 'https://img.youtube.com/vi/$videoId/default.jpg';

  /// Medium resolution thumbnail URL.
  String get mediumResUrl =>
      'https://img.youtube.com/vi/$videoId/mqdefault.jpg';

  /// High resolution thumbnail URL.
  String get highResUrl => 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

  /// Standard resolution thumbnail URL. Not always available.
  String get standardResUrl =>
      'https://img.youtube.com/vi/$videoId/sddefault.jpg';

  /// Maximum resolution thumbnail URL. Not always available.
  String get maxResUrl =>
      'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
}

/// YouTube IFrame Player API 返回的播放状态。
enum YouTubePlayerState {
  unstarted(-1),
  ended(0),
  playing(1),
  paused(2),
  buffering(3),
  cued(5),
  unknown(-999);

  const YouTubePlayerState(this.code);
  final int code;

  static YouTubePlayerState fromCode(int code) => values.firstWhere(
    (state) => state.code == code,
    orElse: () => YouTubePlayerState.unknown,
  );
}

/// 播放器当前状态的不可变快照。
///
/// 控制器通过 [ValueNotifier] 发布该对象，界面可以监听它来刷新播放进度、
/// 元数据和错误信息。
@immutable
class YouTubePlayerValue {
  const YouTubePlayerValue({
    required this.videoId,
    this.isReady = false,
    this.isAutoplayBlocked = false,
    this.state = YouTubePlayerState.unstarted,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.loadedFraction = 0,
    this.loadingProgress = 0,
    this.title,
    this.author,
    this.playbackQuality,
    this.playbackRate = 1,
    this.isMuted = false,
    this.volume = 100,
    this.isFullscreen = false,
    this.errorCode,
    this.errorMessage,
  });

  final String videoId;
  final bool isReady;
  final bool isAutoplayBlocked;
  final YouTubePlayerState state;
  final Duration position;
  final Duration duration;
  final double loadedFraction;
  final double loadingProgress;
  final String? title;
  final String? author;
  final String? playbackQuality;
  final double playbackRate;
  final bool isMuted;
  final int volume;
  final bool isFullscreen;
  final int? errorCode;
  final String? errorMessage;

  bool get hasError => errorCode != null || errorMessage != null;
  bool get isPlaying => state == YouTubePlayerState.playing;

  /// 创建包含指定变更的新快照。
  ///
  /// 可空字段无法用 `null` 表示“清除”，因此错误和视频元数据分别通过
  /// [clearError]、[clearMetadata] 显式重置。
  YouTubePlayerValue copyWith({
    String? videoId,
    bool? isReady,
    bool? isAutoplayBlocked,
    YouTubePlayerState? state,
    Duration? position,
    Duration? duration,
    double? loadedFraction,
    double? loadingProgress,
    String? title,
    String? author,
    String? playbackQuality,
    double? playbackRate,
    bool? isMuted,
    int? volume,
    bool? isFullscreen,
    int? errorCode,
    String? errorMessage,
    bool clearError = false,
    bool clearMetadata = false,
  }) => YouTubePlayerValue(
    videoId: videoId ?? this.videoId,
    isReady: isReady ?? this.isReady,
    isAutoplayBlocked: isAutoplayBlocked ?? this.isAutoplayBlocked,
    state: state ?? this.state,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    loadedFraction: loadedFraction ?? this.loadedFraction,
    loadingProgress: loadingProgress ?? this.loadingProgress,
    title: clearMetadata ? null : title ?? this.title,
    author: clearMetadata ? null : author ?? this.author,
    playbackQuality: clearMetadata
        ? null
        : playbackQuality ?? this.playbackQuality,
    playbackRate: playbackRate ?? this.playbackRate,
    isMuted: isMuted ?? this.isMuted,
    volume: volume ?? this.volume,
    isFullscreen: isFullscreen ?? this.isFullscreen,
    errorCode: clearError ? null : errorCode ?? this.errorCode,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

/// 管理 YouTube 播放器状态，并通过平台通道向原生播放器发送命令。
class FlutterYouTubePlayerController extends ValueNotifier<YouTubePlayerValue> {
  FlutterYouTubePlayerController({
    required String initialVideoId,
    this.autoPlay = false,
    Duration initialPosition = Duration.zero,
    bool muted = false,
  }) : super(
         YouTubePlayerValue(
           videoId: initialVideoId,
           position: initialPosition,
           isMuted: muted,
         ),
       ) {
    if (!isValidVideoId(initialVideoId)) {
      throw ArgumentError.value(
        initialVideoId,
        'initialVideoId',
        'Must be an 11 character YouTube video ID',
      );
    }
    _validatePosition(initialPosition, 'initialPosition');
    _wantsToPlay = autoPlay;
    _wantsMuted = muted;
  }

  final bool autoPlay;
  MethodChannel? _channel;

  // 原生视图尚未创建时，先缓存调用；通道连接后再按原顺序发送。
  final List<_PendingCommand> _pending = [];

  // 记录用户期望的播放状态，原生视图重建时会作为初始化参数传入。
  late bool _wantsToPlay;
  late bool _wantsMuted;
  bool _isChannelActivating = false;

  // 递增该值会通知 Widget 丢弃旧平台视图并创建一个新实例。
  int _viewGeneration = 0;
  bool _disposed = false;

  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static bool isValidVideoId(String videoId) =>
      _videoIdPattern.hasMatch(videoId);

  // 每个平台视图拥有独立通道，避免多个播放器实例之间发生事件串扰。
  void _attach(int viewId) {
    _isChannelActivating = true;
    final channel = _attachChannel(viewId);
    if (channel == null) {
      _isChannelActivating = false;
      return;
    }
    unawaited(_activatePlatform(channel));
  }

  MethodChannel? _attachChannel(int viewId) {
    if (_disposed) return null;
    _channel?.setMethodCallHandler(null);
    final channel = MethodChannel('$_channelPrefix$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleNativeEvent);
    return channel;
  }

  void _flushPending(MethodChannel channel) {
    final pending = List<_PendingCommand>.of(_pending);
    _pending.clear();
    if (pending.isEmpty) return;
    unawaited(_sendPendingInOrder(channel, pending));
  }

  Future<void> _activatePlatform(MethodChannel channel) async {
    try {
      // 原生端会复用 WebView，必须先绑定当前视频，再补发挂载前缓存的命令。
      await channel.invokeMethod<void>('activate', <String, Object>{
        'videoId': value.videoId,
        'autoplay': _wantsToPlay,
        'startSeconds': _seconds(value.position),
        'muted': _wantsMuted,
      });
      if (!_disposed && identical(channel, _channel)) {
        _isChannelActivating = false;
        _flushPending(channel);
      }
    } catch (error, stackTrace) {
      if (!identical(channel, _channel)) return;
      _isChannelActivating = false;
      final pending = List<_PendingCommand>.of(_pending);
      _pending.clear();
      for (final command in pending) {
        if (!command.completer.isCompleted) {
          command.completer.completeError(error, stackTrace);
        }
      }
    }
  }

  void _detach() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _isChannelActivating = false;
  }

  Future<void> _sendPendingInOrder(
    MethodChannel channel,
    List<_PendingCommand> commands,
  ) async {
    for (final command in commands) {
      try {
        await channel.invokeMethod<void>(command.method, command.arguments);
        command.completer.complete();
      } catch (error, stackTrace) {
        command.completer.completeError(error, stackTrace);
      }
    }
  }

  /// 加载一个视频；[autoplay] 为 `false` 时仅预载视频，等待后续播放命令。
  Future<void> load(
    String videoId, {
    bool autoplay = true,
    Duration initialPosition = Duration.zero,
  }) {
    if (!isValidVideoId(videoId)) {
      throw ArgumentError.value(
        videoId,
        'videoId',
        'Must be an 11 character YouTube video ID',
      );
    }
    _validatePosition(initialPosition, 'initialPosition');
    _wantsToPlay = autoplay;
    value = value.copyWith(
      videoId: videoId,
      isReady: false,
      isAutoplayBlocked: false,
      state: YouTubePlayerState.unstarted,
      position: initialPosition,
      duration: Duration.zero,
      loadedFraction: 0,
      loadingProgress: 0,
      clearError: true,
      clearMetadata: true,
    );
    return _invoke('load', <String, Object>{
      'videoId': videoId,
      'autoplay': autoplay,
      'startSeconds': _seconds(initialPosition),
    });
  }

  Future<void> cue(String videoId) => load(videoId, autoplay: false);

  Future<void> play() {
    _wantsToPlay = true;
    return _invoke('play');
  }

  Future<void> pause() {
    _wantsToPlay = false;
    return _invoke('pause');
  }

  Future<void> reload() {
    _wantsToPlay = true;
    return _invoke('reload');
  }

  Future<void> suspend() => _invoke('suspend');
  Future<void> resume() => _invoke('resume');
  Future<void> exitFullscreen() => _invoke('exitFullscreen');

  Future<void> mute() {
    _wantsMuted = true;
    value = value.copyWith(isMuted: true);
    return _invoke('mute');
  }

  Future<void> unmute() {
    _wantsMuted = false;
    value = value.copyWith(isMuted: false);
    return _invoke('unmute');
  }

  Future<void> setVolume(int volume) {
    if (volume < 0 || volume > 100) {
      throw RangeError.range(volume, 0, 100, 'volume');
    }
    value = value.copyWith(volume: volume);
    return _invoke('setVolume', <String, Object>{'volume': volume});
  }

  Future<void> setPlaybackRate(double rate) {
    if (!rate.isFinite || rate <= 0) {
      throw ArgumentError.value(
        rate,
        'rate',
        'Must be a finite positive value',
      );
    }
    value = value.copyWith(playbackRate: rate);
    return _invoke('setPlaybackRate', <String, Object>{'rate': rate});
  }

  /// 保留当前视频并重新创建原生播放器。
  void reinitialize({bool? autoplay, Duration? initialPosition}) {
    if (_disposed) return;
    if (initialPosition != null) {
      _validatePosition(initialPosition, 'initialPosition');
    }
    if (autoplay != null) _wantsToPlay = autoplay;
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _isChannelActivating = false;
    _viewGeneration++;
    value = value.copyWith(
      isReady: false,
      state: YouTubePlayerState.unstarted,
      position: initialPosition ?? value.position,
      duration: Duration.zero,
      loadedFraction: 0,
      loadingProgress: 0,
      isFullscreen: false,
      clearError: true,
      clearMetadata: true,
    );
  }

  Future<void> seekTo(Duration position) {
    _validatePosition(position, 'position');
    return _invoke('seekTo', <String, Object>{'seconds': _seconds(position)});
  }

  Future<void> _invoke(String method, [Map<String, Object>? arguments]) {
    if (_disposed) return Future<void>.value();
    final channel = _channel;
    if (channel != null && !_isChannelActivating) {
      return channel.invokeMethod<void>(method, arguments);
    }

    // Widget 首次构建完成前也允许调用控制器，命令将在 _attach 中补发。
    final completer = Completer<void>();
    _pending.add(_PendingCommand(method, arguments, completer));
    return completer.future;
  }

  Future<void> _handleNativeEvent(MethodCall call) async {
    if (_disposed || call.method != 'event' || call.arguments is! Map) return;

    // 原生端统一通过 event 方法上报事件，再由 type 区分具体状态变化。
    final event = Map<Object?, Object?>.from(call.arguments as Map);
    switch (event['type']) {
      case 'ready':
        value = value.copyWith(
          isReady: true,
          loadingProgress: 1,
          clearError: true,
        );
      case 'state':
        final code = (event['value'] as num?)?.toInt() ?? -999;
        value = value.copyWith(
          state: YouTubePlayerState.fromCode(code),
          isAutoplayBlocked: code == 1 ? false : null,
        );
      case 'progress':
        value = value.copyWith(
          position: _durationFromSeconds(event['position']),
          duration: _durationFromSeconds(event['duration']),
          loadedFraction: _fraction(event['loadedFraction']),
        );
      case 'loading':
        value = value.copyWith(loadingProgress: _fraction(event['value']));
      case 'pageFinished':
        value = value.copyWith(title: event['title'] as String?);
      case 'videoData':
        value = value.copyWith(
          title: event['title'] as String?,
          author: event['author'] as String?,
          duration: _durationFromSeconds(event['duration']),
        );
      case 'playbackQuality':
        value = value.copyWith(playbackQuality: event['value'] as String?);
      case 'playbackRate':
        value = value.copyWith(
          playbackRate: (event['value'] as num?)?.toDouble() ?? 1,
        );
      case 'audioState':
        final isMuted = event['isMuted'] as bool? ?? value.isMuted;
        final volume = (event['volume'] as num?)?.toInt();
        if (isMuted == value.isMuted &&
            (volume == null || volume == value.volume)) {
          return;
        }
        value = value.copyWith(
          isMuted: isMuted,
          volume: volume?.clamp(0, 100).toInt(),
        );
      case 'fullscreen':
        value = value.copyWith(isFullscreen: event['value'] as bool? ?? false);
      case 'autoplayBlocked':
        value = value.copyWith(isAutoplayBlocked: true);
      case 'youtubeError':
        final code = (event['code'] as num?)?.toInt();
        value = value.copyWith(
          errorCode: code,
          errorMessage:
              'YouTube playback error${code == null ? '' : ' ($code)'}',
        );
      case 'loadError':
        value = value.copyWith(
          isReady: false,
          errorMessage:
              event['message'] as String? ?? 'The player is unavailable',
        );
      case 'rendererGone':
        // WebView 渲染进程退出后废弃旧通道，并触发平台视图重新创建。
        _channel?.setMethodCallHandler(null);
        _channel = null;
        _viewGeneration++;
        value = value.copyWith(
          isReady: false,
          errorMessage:
              event['message'] as String? ?? 'The player is unavailable',
        );
    }
  }

  static Duration _durationFromSeconds(Object? raw) {
    final seconds = (raw as num?)?.toDouble() ?? 0;
    if (!seconds.isFinite || seconds <= 0) return Duration.zero;
    return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
  }

  static double _fraction(Object? raw) {
    final number = (raw as num?)?.toDouble() ?? 0;
    if (!number.isFinite) return 0;
    return number.clamp(0.0, 1.0).toDouble();
  }

  static double _seconds(Duration position) =>
      position.inMicroseconds / Duration.microsecondsPerSecond;

  static void _validatePosition(Duration position, String name) {
    if (position.isNegative) {
      throw ArgumentError.value(position, name, 'Must not be negative');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final command in _pending) {
      if (!command.completer.isCompleted) command.completer.complete();
    }
    _pending.clear();
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _isChannelActivating = false;
    super.dispose();
  }
}

class _PendingCommand {
  const _PendingCommand(this.method, this.arguments, this.completer);

  final String method;
  final Map<String, Object>? arguments;
  final Completer<void> completer;
}

/// 在 Android 和 iOS 上承载原生 YouTube 播放器的平台视图。
class FlutterYouTubePlayer extends StatefulWidget {
  const FlutterYouTubePlayer({
    required this.controller,
    this.backgroundColor = Colors.black,
    this.showPlayPauseButton = true,
    this.gestureRecognizers = const <Factory<OneSequenceGestureRecognizer>>{},
    super.key,
  });

  final FlutterYouTubePlayerController controller;
  final Color backgroundColor;

  /// 是否在播放器中央显示跟随 YouTube 状态切换的播放/暂停按钮。
  final bool showPlayPauseButton;

  /// 交由原生平台视图处理的手势识别器集合。
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  @override
  State<FlutterYouTubePlayer> createState() => _FlutterYouTubePlayerState();
}

class _FlutterYouTubePlayerState extends State<FlutterYouTubePlayer>
    with WidgetsBindingObserver {
  // 延迟显示进度指示器，避免加载很快时出现短暂闪烁。
  static const _loadingIndicatorDelay = Duration(milliseconds: 120);
  static const _playPauseButtonVisibilityDuration = Duration(seconds: 4);

  late int _viewGeneration;
  late Key _platformViewKey;
  Timer? _loadingIndicatorTimer;
  Timer? _playPauseButtonTimer;
  Animation<double>? _routeAnimation;
  Animation<double>? _secondaryRouteAnimation;
  late String _videoId;
  YouTubePlayerState? _playPauseButtonState;
  bool _isInitialOverlayVisible = false;
  bool _isLoadingIndicatorVisible = false;
  bool _isPlayPauseButtonVisible = false;
  bool _hasPlaybackStarted = false;
  bool _isAppSuspended = false;
  bool _isRouteExiting = false;
  bool _isRouteCovered = false;
  bool _isNativeSuspended = false;

  @override
  void initState() {
    super.initState();
    _viewGeneration = widget.controller._viewGeneration;
    _platformViewKey = UniqueKey();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isAppSuspended =
        lifecycleState != null && lifecycleState != AppLifecycleState.resumed;
    _resetPlaybackState();
    widget.controller.addListener(_handleControllerChange);
    WidgetsBinding.instance.addObserver(this);
    _syncLoadingIndicatorVisibility();
    _syncPlayPauseButtonVisibility(notify: false);
    _syncNativeSuspension();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    final secondaryAnimation = ModalRoute.of(context)?.secondaryAnimation;
    if (!identical(animation, _routeAnimation)) {
      _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
      _routeAnimation = animation;
      animation?.addStatusListener(_handleRouteAnimationStatus);
      if (animation != null) _handleRouteAnimationStatus(animation.status);
    }
    if (!identical(secondaryAnimation, _secondaryRouteAnimation)) {
      _secondaryRouteAnimation?.removeStatusListener(
        _handleSecondaryRouteAnimationStatus,
      );
      _secondaryRouteAnimation = secondaryAnimation;
      secondaryAnimation?.addStatusListener(
        _handleSecondaryRouteAnimationStatus,
      );
      if (secondaryAnimation != null) {
        _handleSecondaryRouteAnimationStatus(secondaryAnimation.status);
      }
    }
  }

  @override
  void didUpdateWidget(FlutterYouTubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChange);
    oldWidget.controller._detach();
    _viewGeneration = widget.controller._viewGeneration;
    _platformViewKey = UniqueKey();
    _loadingIndicatorTimer?.cancel();
    _loadingIndicatorTimer = null;
    _playPauseButtonTimer?.cancel();
    _playPauseButtonTimer = null;
    _playPauseButtonState = null;
    _isPlayPauseButtonVisible = false;
    _isInitialOverlayVisible = false;
    _isLoadingIndicatorVisible = false;
    _resetPlaybackState();
    widget.controller.addListener(_handleControllerChange);
    _syncLoadingIndicatorVisibility();
    _syncPlayPauseButtonVisibility(notify: false);
    _isNativeSuspended = false;
    _syncNativeSuspension();
  }

  void _handleControllerChange() {
    if (!mounted) return;

    if (_viewGeneration != widget.controller._viewGeneration) {
      // 更换 Key 强制 Flutter 销毁旧平台视图，并向原生端申请新实例。
      setState(() {
        _viewGeneration = widget.controller._viewGeneration;
        _platformViewKey = UniqueKey();
      });
      _hasPlaybackStarted = false;
    }

    final value = widget.controller.value;
    if (value.videoId != _videoId) {
      setState(() {
        _videoId = value.videoId;
        _hasPlaybackStarted = false;
      });
    }
    if (value.state == YouTubePlayerState.playing) {
      _hasPlaybackStarted = true;
    }
    _syncLoadingIndicatorVisibility();
    _syncPlayPauseButtonVisibility();
  }

  void _resetPlaybackState() {
    final value = widget.controller.value;
    _videoId = value.videoId;
    _hasPlaybackStarted = value.state == YouTubePlayerState.playing;
    _isInitialOverlayVisible = _shouldShowInitialOverlay(value);
  }

  bool _shouldShowInitialOverlay(YouTubePlayerValue value) {
    // 出错或自动播放被拦截时移除遮罩，露出原生播放器自身的提示画面。
    if (value.hasError || value.isAutoplayBlocked) return false;
    return !_hasPlaybackStarted;
  }

  void _syncLoadingIndicatorVisibility() {
    final isLoading = _shouldShowInitialOverlay(widget.controller.value);
    if (!isLoading) {
      _loadingIndicatorTimer?.cancel();
      _loadingIndicatorTimer = null;
      if ((_isInitialOverlayVisible || _isLoadingIndicatorVisible) && mounted) {
        setState(() {
          _isInitialOverlayVisible = false;
          _isLoadingIndicatorVisible = false;
        });
      }
      return;
    }
    if (!_isInitialOverlayVisible && mounted) {
      setState(() => _isInitialOverlayVisible = true);
    }
    if (_isLoadingIndicatorVisible || _loadingIndicatorTimer != null) return;

    _loadingIndicatorTimer = Timer(_loadingIndicatorDelay, () {
      _loadingIndicatorTimer = null;
      if (!mounted) return;
      if (_shouldShowInitialOverlay(widget.controller.value)) {
        setState(() => _isLoadingIndicatorVisible = true);
      }
    });
  }

  void _syncPlayPauseButtonVisibility({bool notify = true}) {
    final state = widget.controller.value.state;
    if (_playPauseButtonState == state) return;

    _playPauseButtonState = state;
    _playPauseButtonTimer?.cancel();
    _playPauseButtonTimer = null;
    final shouldShow =
        state == YouTubePlayerState.playing ||
        state == YouTubePlayerState.paused;
    if (notify && mounted) {
      setState(() => _isPlayPauseButtonVisible = shouldShow);
    } else {
      _isPlayPauseButtonVisible = shouldShow;
    }

    if (state != YouTubePlayerState.playing) return;
    _playPauseButtonTimer = Timer(_playPauseButtonVisibilityDuration, () {
      _playPauseButtonTimer = null;
      if (!mounted || _playPauseButtonState != YouTubePlayerState.playing) {
        return;
      }
      setState(() => _isPlayPauseButtonVisible = false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppSuspended = state != AppLifecycleState.resumed;
    _syncNativeSuspension();
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    // 路由反向动画开始时立即冻结原生画面，避免视频纹理与返回动画竞争。
    final isExiting = status == AnimationStatus.reverse;
    if (_isRouteExiting == isExiting) return;
    _isRouteExiting = isExiting;
    _syncNativeSuspension();
  }

  void _handleSecondaryRouteAnimationStatus(AnimationStatus status) {
    final isCovered = status != AnimationStatus.dismissed;
    if (_isRouteCovered == isCovered) return;
    _isRouteCovered = isCovered;
    _syncNativeSuspension();
  }

  void _syncNativeSuspension() {
    final shouldSuspend = _isAppSuspended || _isRouteExiting || _isRouteCovered;
    if (_isNativeSuspended == shouldSuspend) return;
    _isNativeSuspended = shouldSuspend;
    if (shouldSuspend) {
      unawaited(widget.controller.suspend());
    } else {
      unawaited(widget.controller.resume());
    }
  }

  @override
  void dispose() {
    _loadingIndicatorTimer?.cancel();
    _playPauseButtonTimer?.cancel();
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _secondaryRouteAnimation?.removeStatusListener(
      _handleSecondaryRouteAnimationStatus,
    );
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChange);
    widget.controller._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidView(
        key: _platformViewKey,
        viewType: _viewType,
        gestureRecognizers: widget.gestureRecognizers,
        onPlatformViewCreated: widget.controller._attach,
      ),
      TargetPlatform.iOS => UiKitView(
        key: _platformViewKey,
        viewType: _viewType,
        gestureRecognizers: widget.gestureRecognizers,
        onPlatformViewCreated: widget.controller._attach,
      ),
      _ => throw UnsupportedError(
        'flutter_youtube_player supports Android and iOS only',
      ),
    };
    return ColoredBox(
      color: widget.backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          view,
          if (_isInitialOverlayVisible)
            IgnorePointer(
              child: Image.network(
                ThumbnailSet(_videoId).highResUrl,
                key: const ValueKey('player-cover'),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: widget.backgroundColor),
              ),
            ),
          if (_isLoadingIndicatorVisible)
            const IgnorePointer(
              child: Center(
                child: _PlayerLoadingIndicator(key: ValueKey('player-loading')),
              ),
            ),
          if (widget.showPlayPauseButton && _isPlayPauseButtonVisible)
            ValueListenableBuilder<YouTubePlayerValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                final isPlaying = value.state == YouTubePlayerState.playing;
                final isPaused = value.state == YouTubePlayerState.paused;
                if (!isPlaying && !isPaused) return const SizedBox.shrink();

                return Center(
                  child: _PlayerPlayPauseButton(
                    isPlaying: isPlaying,
                    onPressed: () {
                      unawaited(
                        isPlaying
                            ? widget.controller.pause()
                            : widget.controller.play(),
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _PlayerPlayPauseButton extends StatelessWidget {
  const _PlayerPlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
  });

  final bool isPlaying;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = isPlaying ? '暂停' : '播放';
    return Material(
      key: const ValueKey('player-play-pause'),
      color: const Color.fromRGBO(0, 0, 0, 0.3),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: label,
        constraints: const BoxConstraints.tightFor(width: 56, height: 56),
        padding: const EdgeInsets.all(10),
        onPressed: onPressed,
        icon: Image.asset(
          isPlaying
              ? 'assets/icons/player_pause.png'
              : 'assets/icons/player_play.png',
          package: 'flutter_youtube_player',
          width: 36,
          height: 36,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class _PlayerLoadingIndicator extends StatefulWidget {
  const _PlayerLoadingIndicator({super.key});

  @override
  State<_PlayerLoadingIndicator> createState() =>
      _PlayerLoadingIndicatorState();
}

class _PlayerLoadingIndicatorState extends State<_PlayerLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Video loading',
      child: SizedBox.square(
        dimension: 36,
        child: RotationTransition(
          turns: _rotation,
          child: const RepaintBoundary(
            child: CircularProgressIndicator(
              value: 0.75,
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
