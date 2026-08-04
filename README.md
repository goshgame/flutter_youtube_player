# flutter_youtube_player

A native-view Flutter wrapper around the YouTube IFrame API for Android and
iOS. Every mounted player owns an independent WebView, while the most recently
disposed player is paused and retained for the next detail/mini-player handoff.
Older idle players are destroyed. The embedded view
keeps touch input enabled for 360-degree video navigation while suppressing
long presses before they reach the embedded YouTube frame.

## Usage

```dart
final controller = FlutterYouTubePlayerController(
  initialVideoId: 'r9UYbCxus3s',
  initialPosition: const Duration(seconds: 30),
  autoPlay: true,
  muted: false,
);

AspectRatio(
  aspectRatio: 16 / 9,
  child: FlutterYouTubePlayer(
    controller: controller,
  ),
);

await controller.play();
await controller.pause();
await controller.seekTo(const Duration(seconds: 45));
await controller.load(
  'M7lc1UVf-VE',
  autoplay: true,
  initialPosition: const Duration(seconds: 10),
);
await controller.mute();
await controller.setVolume(70);
await controller.setPlaybackRate(1.5);
```

The widget pauses its native player while the app is inactive, while its route
is covered, and during route removal. A retained player is detached from its
old method channel and listener before another Flutter view can acquire it; the
new channel activates the requested video before queued commands are replayed.

Before playback starts, the player automatically displays YouTube's high
resolution thumbnail derived from the current video ID. Other thumbnail sizes
are available through `ThumbnailSet(videoId)`.

Listen to the controller for ready, playback, buffer, loading, autoplay and
error state changes. The value also exposes the video title, author, playback
quality, playback rate, volume, mute and fullscreen state. Call
`controller.reinitialize()` to explicitly rebuild the native player; renderer
process failures trigger this automatically. Dispose the controller with its
owning widget.

The bundled page uses `http://example.com` as a non-network base origin and
keeps the real platform WebView user agent. Together they provide the Referer
and client identity required by YouTube and prevent IFrame error 153.

Android requires `INTERNET` permission. The plugin supports Android API 26+
and iOS 12+.
