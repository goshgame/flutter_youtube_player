package com.podoc.flutter_youtube_player

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class FlutterYoutubePlayerPlugin : FlutterPlugin {
  private var playerPool: PlayerViewPool? = null
  private var handoverChannel: MethodChannel? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val pool = PlayerViewPool(binding.applicationContext)
    playerPool = pool
    handoverChannel = MethodChannel(
      binding.binaryMessenger,
      "flutter_youtube_player/handover",
    ).also { channel ->
      channel.setMethodCallHandler { call, result ->
        if (call.method != "discard") {
          result.notImplemented()
          return@setMethodCallHandler
        }
        val sessionId = call.argument<Int>("sessionId")
        if (sessionId == null) {
          result.error("invalid_session", "Missing playback session ID", null)
          return@setMethodCallHandler
        }
        pool.discardRetainedPlayback(sessionId)
        result.success(null)
      }
    }
    binding.platformViewRegistry.registerViewFactory(
      "flutter_youtube_player/player",
      PlayerViewFactory(binding.binaryMessenger, pool),
    )
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    handoverChannel?.setMethodCallHandler(null)
    handoverChannel = null
    playerPool?.close()
    playerPool = null
  }
}
