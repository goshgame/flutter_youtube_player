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
    showPlayPauseButton: true,
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
if (controller.value.isPictureInPictureAvailable) {
  await controller.enterPictureInPicture();
}
await controller.exitPictureInPicture();
await controller.openInYouTube();
```

## iOS Picture in Picture

The YouTube IFrame API does not expose a Picture in Picture method or event.
On iOS, this plugin keeps the official embedded player and asks its HTML5 video
element to enter WebKit Picture in Picture presentation mode. It does not
resolve or play YouTube media URLs outside the IFrame player.

Start playback first and wait for
`controller.value.isPictureInPictureAvailable` before calling
`enterPictureInPicture()`. The returned future completes only after iOS reports
the actual state change. `controller.value.isPictureInPicture` tracks both
programmatic and system state changes.

The plugin does not enter PiP automatically when the app moves to the
background. Call `enterPictureInPicture()` from an explicit user action before
backgrounding when that behavior is required.

The host iOS app must enable **Background Modes > Audio, AirPlay, and Picture
in Picture**. The corresponding `Info.plist` entry is:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

The app must also use an `AVAudioSession` playback category. Configure this in
the app or with the app's existing audio-session package; the plugin does not
replace global audio-session policy:

```swift
try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
```

Android Picture in Picture is not implemented yet.

The widget pauses its native player while the app is inactive, while its route
is covered, and during route removal. A retained player is detached from its
old method channel and listener before another Flutter view can acquire it; the
new channel activates the requested video before queued commands are replayed.

Before playback starts, the player automatically displays YouTube's high
resolution thumbnail derived from the current video ID. Other thumbnail sizes
are available through `ThumbnailSet(videoId)`.

By default, the player displays a centered play/pause button that follows the
IFrame player state. The play button remains visible while paused; the pause
button hides four seconds after playback starts. Set
`showPlayPauseButton: false` when providing a custom playback control surface.

Listen to the controller for ready, playback, buffer, loading, autoplay and
error state changes. The value also exposes the video title, author, playback
quality, playback rate, volume, mute and fullscreen state. Call
`controller.reinitialize()` to explicitly rebuild the native player; renderer
process failures trigger this automatically. Dispose the controller with its
owning widget.

IFrame errors 101 and 150 indicate that the video owner disabled embedding.
The widget replaces the player with a dedicated message and an action that
opens the current video in the YouTube app or system browser. Native playback
and loading errors uncover the WebView instead of leaving its black loading
surface visible.

The bundled page uses `http://example.com` as a non-network base origin and
keeps the real platform WebView user agent. Together they provide the Referer
and client identity required by YouTube and prevent IFrame error 153.

Android requires `INTERNET` permission. The plugin supports Android API 26+
and iOS 12+.
