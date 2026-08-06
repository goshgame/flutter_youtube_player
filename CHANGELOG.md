## Unreleased

* Suppress long-press gestures, native long-click callbacks, haptics, and
  context-menu events inside every embedded YouTube frame while preserving
  taps, multi-touch, and drag navigation.
* Show a dedicated error with an external YouTube link when a video owner
  disables embedding, and uncover native playback errors instead of leaving a
  black loading surface visible.

## 0.1.1

* Refactor Android and iOS around the native demo's explicit player-view pool:
  active players own independent WebViews and idle players are paused, detached,
  and reused with bounded retention.
* Restore WebView touch delivery for 360-degree video interaction.
* Suspend playback when a Flutter route is covered as well as when it exits or
  the app becomes inactive.
* Preserve the requested initial position when creating or recreating a player.
* Apply the requested mute state inside the IFrame player and report the actual
  audio state back to Flutter.
* Activate an acquired iOS player before replaying queued controller commands.
* Activate acquired Android players through the same ordered channel handshake,
  and report readiness after a pooled WebView accepts the requested video.
* Keep at most one idle native WebView, matching the app's detail-to-mini-player
  handoff while avoiding a second unused WebView allocation.
* Remove unused JavaScript compatibility wrappers and avoid reporting a stale
  playback position immediately after seeking.

## 0.1.0

* Use a stable HTTP origin and the platform WebView user agent to prevent
  YouTube IFrame error 153.
* Add video metadata, playback quality and playback rate state.
* Add mute, volume, playback rate and fullscreen commands.
* Automatically recreate the platform view after a WebView renderer exits.
* Add Android fullscreen hosting and share the iOS WebKit process pool.

## 0.0.1

* Add Android and iOS native YouTube IFrame platform views.
* Add load, cue, play, pause, reload and seek controller commands.
* Publish ready, playback, progress, loading, autoplay and error states.
* Add automatic app lifecycle suspension and resume behavior.
