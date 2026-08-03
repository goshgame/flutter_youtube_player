import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_youtube_player/flutter_youtube_player.dart';

import 'episode.dart';
import 'episode_player_page.dart';
import 'episode_repository.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter YouTube Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffc62828)),
        useMaterial3: true,
      ),
      home: const NewsListPage(),
    );
  }
}

class NewsListPage extends StatefulWidget {
  const NewsListPage({this.repository, super.key});

  final EpisodeDataSource? repository;

  @override
  State<NewsListPage> createState() => _NewsListPageState();
}

class _NewsListPageState extends State<NewsListPage> {
  final _scrollController = ScrollController();
  final List<Episode> _episodes = [];
  late final EpisodeDataSource _repository;
  int? _nextCursor;
  bool _hasMore = true;
  bool _isLoading = false;
  String? _errorMessage;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? EpisodeRepository();
    _scrollController.addListener(_loadMoreWhenNeeded);
    unawaited(_loadEpisodes());
  }

  void _loadMoreWhenNeeded() {
    if (_scrollController.position.extentAfter < 360) {
      unawaited(_loadEpisodes());
    }
  }

  Future<void> _refresh() async {
    _requestGeneration++;
    _isLoading = false;
    _hasMore = true;
    _nextCursor = null;
    await _loadEpisodes(replace: true);
  }

  Future<void> _loadEpisodes({bool replace = false}) async {
    if (_isLoading || (!replace && _episodes.isNotEmpty && !_hasMore)) return;

    final generation = _requestGeneration;
    final cursor = replace || _episodes.isEmpty ? null : _nextCursor;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final page = await _repository.loadPage(cursor: cursor);
      if (!mounted || generation != _requestGeneration) return;

      setState(() {
        if (replace) _episodes.clear();
        final ids = _episodes.map((episode) => episode.id).toSet();
        for (final episode in page.episodes) {
          if (ids.add(episode.id)) _episodes.add(episode);
        }
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore && page.nextCursor != null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _describeError(error);
      });
    }
  }

  void _openEpisode(Episode episode) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EpisodePlayerPage(episode: episode),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _requestGeneration++;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新闻视频'),
        actions: [
          IconButton(
            tooltip: '刷新列表',
            onPressed: _isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildList()),
    );
  }

  Widget _buildList() {
    if (_episodes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 240,
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : _ErrorState(
                        message: _errorMessage ?? '暂无新闻视频',
                        onRetry: _loadEpisodes,
                      ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _episodes.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == _episodes.length) return _buildFooter();
          final episode = _episodes[index];
          return _EpisodeTile(
            episode: episode,
            onTap: () => _openEpisode(episode),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (_errorMessage != null) {
      return SizedBox(
        height: 56,
        child: Center(
          child: TextButton.icon(
            onPressed: _loadEpisodes,
            icon: const Icon(Icons.refresh),
            label: const Text('加载失败，点击重试'),
          ),
        ),
      );
    }
    if (_isLoading) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: Center(child: Text(_hasMore ? '继续滚动加载' : '已加载全部')),
    );
  }

  static String _describeError(Object error) =>
      error.toString().replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '');
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.onTap});

  final Episode episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 128,
                      height: 72,
                      child: Image.network(
                        ThumbnailSet(episode.videoId).highResUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xffe0e0e0),
                          child: Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (episode.duration.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      color: Colors.black87,
                      child: Text(
                        episode.duration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episode.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        episode.podcast,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 24),
                child: Icon(Icons.chevron_right, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 36),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
