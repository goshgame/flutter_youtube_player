package com.podoc.flutter_youtube_player

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal class PlayerViewFactory(
  private val messenger: BinaryMessenger,
  private val playerPool: PlayerViewPool,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    return PlayerViewLease(
      playerPool,
      playerPool.acquirePlayerView(),
      messenger,
      viewId,
      findActivity(context),
    )
  }
}

private fun findActivity(context: Context): Activity? {
  var current = context
  while (current is ContextWrapper) {
    if (current is Activity) return current
    current = current.baseContext
  }
  return null
}
