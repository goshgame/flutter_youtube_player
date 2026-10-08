import Flutter
import UIKit

public final class FlutterYoutubePlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let pool = PlayerViewPool(parkingView: registrar.viewController()?.view)
    let handoverChannel = FlutterMethodChannel(
      name: "flutter_youtube_player/handover",
      binaryMessenger: registrar.messenger()
    )
    handoverChannel.setMethodCallHandler { call, result in
      guard call.method == "discard" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let sessionId = (arguments["sessionId"] as? NSNumber)?.intValue else {
        result(FlutterError(
          code: "invalid_session",
          message: "Missing playback session ID",
          details: nil
        ))
        return
      }
      pool.discardRetainedPlayback(sessionId: sessionId)
      result(nil)
    }
    registrar.register(
      PlayerViewFactory(messenger: registrar.messenger(), pool: pool),
      withId: "flutter_youtube_player/player"
    )
  }
}
