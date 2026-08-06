import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_youtube_player/flutter_youtube_player.dart';

import 'episode.dart';

class EpisodePlayerPage extends StatefulWidget {
  const EpisodePlayerPage({required this.episode, super.key});

  final Episode episode;

  @override
  State<EpisodePlayerPage> createState() => _EpisodePlayerPageState();
}

class _EpisodePlayerPageState extends State<EpisodePlayerPage> {
  late final FlutterYouTubePlayerController _playerController;
  late final TextEditingController _videoIdController;
  String? _videoIdError;
  bool _isLoadingVideo = false;

  @override
  void initState() {
    super.initState();
    _playerController = FlutterYouTubePlayerController(
      initialVideoId: widget.episode.videoId,
      autoPlay: true,
    );
    _videoIdController = TextEditingController(text: widget.episode.videoId);
  }

  @override
  void dispose() {
    _videoIdController.dispose();
    _playerController.dispose();
    super.dispose();
  }

  Future<void> _loadVideo() async {
    if (_isLoadingVideo) return;
    final videoId = _videoIdController.text.trim();
    if (!FlutterYouTubePlayerController.isValidVideoId(videoId)) {
      setState(() => _videoIdError = '请输入有效的 11 位 YouTube 视频 ID');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _videoIdError = null;
      _isLoadingVideo = true;
    });
    try {
      await _playerController.load(videoId);
    } catch (_) {
      if (mounted) setState(() => _videoIdError = '视频加载失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _isLoadingVideo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    return Scaffold(
      appBar: AppBar(title: const Text('播放视频')),
      body: SafeArea(
        child: ListView(
          children: [
            _PlayerSurface(controller: _playerController),
            _PlaybackProgress(controller: _playerController),
            _PlayerControls(controller: _playerController),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: TextField(
                key: const ValueKey('youtube-video-id-input'),
                controller: _videoIdController,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: 1,
                textInputAction: TextInputAction.go,
                decoration: InputDecoration(
                  labelText: 'YouTube 视频 ID',
                  hintText: '例如：lOnDRI_G3tg',
                  errorText: _videoIdError,
                  border: const OutlineInputBorder(),
                  suffixIcon: _isLoadingVideo
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          key: const ValueKey('load-youtube-video'),
                          tooltip: '加载并播放',
                          onPressed: _loadVideo,
                          icon: const Icon(Icons.play_arrow),
                        ),
                ),
                onChanged: (videoId) {
                  if (_videoIdError != null &&
                      FlutterYouTubePlayerController.isValidVideoId(
                        videoId.trim(),
                      )) {
                    setState(() => _videoIdError = null);
                  }
                },
                onSubmitted: (_) => unawaited(_loadVideo()),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (episode.podcast.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      episode.podcast,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerSurface extends StatelessWidget {
  const _PlayerSurface({required this.controller});

  final FlutterYouTubePlayerController controller;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: FlutterYouTubePlayer(controller: controller),
    );
  }
}

class _PlaybackProgress extends StatefulWidget {
  const _PlaybackProgress({required this.controller});

  final FlutterYouTubePlayerController controller;

  @override
  State<_PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<_PlaybackProgress> {
  double? _dragPosition;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<YouTubePlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final duration = value.duration.inMilliseconds;
        final sliderMax = duration > 0 ? duration.toDouble() : 1.0;
        final playerPosition = value.position.inMilliseconds
            .clamp(0, duration > 0 ? duration : 0)
            .toDouble();
        final sliderPosition = (_dragPosition ?? playerPosition).clamp(
          0.0,
          sliderMax,
        );
        final bufferedPosition = (value.loadedFraction * sliderMax).clamp(
          sliderPosition,
          sliderMax,
        );
        final displayedPosition = Duration(
          milliseconds: sliderPosition.round(),
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 3),
                child: Slider(
                  key: const ValueKey('playback-progress'),
                  value: sliderPosition,
                  secondaryTrackValue: bufferedPosition,
                  max: sliderMax,
                  onChanged: duration > 0
                      ? (position) => setState(() => _dragPosition = position)
                      : null,
                  onChangeEnd: duration > 0
                      ? (position) {
                          setState(() => _dragPosition = null);
                          unawaited(
                            widget.controller.seekTo(
                              Duration(milliseconds: position.round()),
                            ),
                          );
                        }
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatPlaybackTime(displayedPosition),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      _formatPlaybackTime(value.duration),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({required this.controller});

  final FlutterYouTubePlayerController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ValueListenableBuilder<YouTubePlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) => Row(
          children: [
            const SizedBox(width: 8),
            IconButton(
              tooltip: value.isMuted ? '取消静音' : '静音',
              onPressed: value.isMuted ? controller.unmute : controller.mute,
              icon: Icon(value.isMuted ? Icons.volume_off : Icons.volume_up),
            ),
            IconButton(
              tooltip: '播放',
              onPressed: controller.play,
              icon: const Icon(Icons.play_arrow),
            ),
            IconButton(
              tooltip: '暂停',
              onPressed: controller.pause,
              icon: const Icon(Icons.pause),
            ),
            PopupMenuButton<double>(
              tooltip: '播放速度',
              icon: const Icon(Icons.speed),
              onSelected: controller.setPlaybackRate,
              itemBuilder: (context) => const [
                PopupMenuItem(value: 0.5, child: Text('0.5x')),
                PopupMenuItem(value: 1, child: Text('1.0x')),
                PopupMenuItem(value: 1.5, child: Text('1.5x')),
                PopupMenuItem(value: 2, child: Text('2.0x')),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value.title?.trim().isNotEmpty == true
                    ? value.title!
                    : value.state.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatPlaybackTime(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ Duration.secondsPerHour;
  final minutes = (totalSeconds ~/ Duration.secondsPerMinute) % 60;
  final seconds = totalSeconds % 60;
  final paddedSeconds = seconds.toString().padLeft(2, '0');
  if (hours == 0) return '$minutes:$paddedSeconds';
  return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
}
