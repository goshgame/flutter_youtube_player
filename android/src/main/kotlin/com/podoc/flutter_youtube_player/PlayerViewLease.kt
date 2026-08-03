package com.podoc.flutter_youtube_player

import android.app.Activity
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView

internal class PlayerViewLease(
  private val pool: PlayerViewPool,
  private val playerView: NativePlayerView,
  messenger: BinaryMessenger,
  viewId: Int,
  hostActivity: Activity?,
) : PlatformView {
  private var disposed = false

  init {
    playerView.bind(messenger, viewId, hostActivity)
  }

  override fun getView(): View = playerView.rootView

  override fun dispose() {
    if (disposed) return
    disposed = true
    playerView.unbind()
    pool.releasePlayerView(playerView)
  }
}
