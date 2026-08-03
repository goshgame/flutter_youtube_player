package com.podoc.flutter_youtube_player

import android.content.Context
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
    entry.isInUse = true
    return entry.playerView
  }

  fun releasePlayerView(playerView: NativePlayerView): Boolean {
    checkMainThread()
    val entry = entries.firstOrNull { it.playerView === playerView } ?: return false
    if (!entry.isInUse) return false
    entry.isInUse = false
    (playerView.rootView.parent as? ViewGroup)?.removeView(playerView.rootView)
    entry.idleOrder = ++nextIdleOrder
    if (closed || playerView.isInvalidated) {
      entries.remove(entry)
      playerView.destroy()
    } else {
      trimIdlePlayerViewsIfNeeded()
    }
    return true
  }

  fun removeAllIdlePlayerViews() {
    checkMainThread()
    val idleEntries = entries.filterNot { it.isInUse }
    entries.removeAll(idleEntries.toSet())
    idleEntries.forEach { it.playerView.destroy() }
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
    invalid.forEach { it.playerView.destroy() }
  }

  private fun trimIdlePlayerViewsIfNeeded() {
    while (entries.count { !it.isInUse } > MAXIMUM_IDLE_PLAYER_COUNT) {
      val oldest = entries.filterNot { it.isInUse }.minByOrNull { it.idleOrder }
        ?: return
      entries.remove(oldest)
      oldest.playerView.destroy()
    }
  }

  private fun checkMainThread() {
    check(android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
      "PlayerViewPool must be used on the main thread"
    }
  }
}
