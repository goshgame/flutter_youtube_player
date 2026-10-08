package com.podoc.flutter_youtube_player

import android.app.Activity
import android.content.Context
import android.widget.FrameLayout
import android.view.ViewGroup

internal class PlayerViewPool(context: Context) {
  companion object {
    // kapt 同一时刻只保留一个详情页或迷你播放器，缓存一个空闲 WebView 即可覆盖切换场景。
    private const val MAXIMUM_IDLE_PLAYER_COUNT = 3
  }

  private data class Entry(
    val playerView: NativePlayerView,
    var isInUse: Boolean = false,
    var idleOrder: Long = 0,
  )

  private val applicationContext = context.applicationContext
  private val entries = mutableListOf<Entry>()
  private var nextIdleOrder = 0L
  private var closed = false

  fun acquirePlayerView(): NativePlayerView {
    checkMainThread()
    check(!closed) { "PlayerViewPool is closed" }
    removeInvalidIdlePlayers()
    val entry = entries.filterNot { it.isInUse }.maxByOrNull { it.idleOrder }
      ?: Entry(NativePlayerView(applicationContext)).also(entries::add)
    (entry.playerView.rootView.parent as? ViewGroup)?.removeView(entry.playerView.rootView)
    entry.isInUse = true
    return entry.playerView
  }

  fun releasePlayerView(playerView: NativePlayerView, activity: Activity?): Boolean {
    checkMainThread()
    val entry = entries.firstOrNull { it.playerView === playerView } ?: return false
    if (!entry.isInUse) return false
    entry.isInUse = false
    val attachedWindowRoot = (playerView.rootView.rootView as? FrameLayout)
      ?.takeIf { it !== playerView.rootView && it.isAttachedToWindow }
    (playerView.rootView.parent as? ViewGroup)?.removeView(playerView.rootView)
    if (playerView.isRetainingHandover && !playerView.isInvalidated) {
      val windowRoot = activity?.window?.decorView as? FrameLayout ?: attachedWindowRoot
      if (windowRoot != null) {
        // 原生视图留在窗口树中，但放在可见区域外，避免租约间隙停止媒体会话。
        val width = playerView.rootView.width.coerceAtLeast(1)
        val height = playerView.rootView.height.coerceAtLeast(1)
        windowRoot.addView(playerView.rootView, FrameLayout.LayoutParams(width, height).apply {
          leftMargin = -width
          topMargin = -height
        })
      }
    }
    entry.idleOrder = ++nextIdleOrder
    if (closed || playerView.isInvalidated) {
      entries.remove(entry)
      destroyIdlePlayerView(playerView)
    } else {
      trimIdlePlayerViewsIfNeeded()
    }
    return true
  }

  fun discardRetainedPlayback(sessionId: Int) {
    checkMainThread()
    entries.forEach { entry ->
      if (entry.playerView.discardRetainedPlayback(sessionId) && !entry.isInUse) {
        (entry.playerView.rootView.parent as? ViewGroup)?.removeView(entry.playerView.rootView)
      }
    }
  }

  fun removeAllIdlePlayerViews() {
    checkMainThread()
    val idleEntries = entries.filterNot { it.isInUse }
    entries.removeAll(idleEntries.toSet())
    idleEntries.forEach { destroyIdlePlayerView(it.playerView) }
  }

  fun close() {
    checkMainThread()
    if (closed) return
    closed = true
    removeAllIdlePlayerViews()
  }

  private fun removeInvalidIdlePlayers() {
    val invalid = entries.filter { !it.isInUse && it.playerView.isInvalidated }
    entries.removeAll(invalid.toSet())
    invalid.forEach { destroyIdlePlayerView(it.playerView) }
  }

  private fun trimIdlePlayerViewsIfNeeded() {
    while (entries.count { !it.isInUse } > MAXIMUM_IDLE_PLAYER_COUNT) {
      val oldest = entries.filterNot { it.isInUse }.minByOrNull { it.idleOrder }
        ?: return
      entries.remove(oldest)
      destroyIdlePlayerView(oldest.playerView)
    }
  }

  private fun destroyIdlePlayerView(playerView: NativePlayerView) {
    (playerView.rootView.parent as? ViewGroup)?.removeView(playerView.rootView)
    playerView.destroy()
  }

  private fun checkMainThread() {
    check(android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
      "PlayerViewPool must be used on the main thread"
    }
  }
}
