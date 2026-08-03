package com.podoc.flutter_youtube_player

import io.flutter.embedding.engine.plugins.FlutterPlugin

class FlutterYoutubePlayerPlugin : FlutterPlugin {
  private var playerPool: PlayerViewPool? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val pool = PlayerViewPool(binding.applicationContext)
    playerPool = pool
    binding.platformViewRegistry.registerViewFactory(
      "flutter_youtube_player/player",
      PlayerViewFactory(binding.binaryMessenger, pool),
    )
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    playerPool?.close()
    playerPool = null
  }
}
