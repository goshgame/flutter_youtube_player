import Flutter
import UIKit

public final class FlutterYoutubePlayerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(
      PlayerViewFactory(messenger: registrar.messenger()),
      withId: "flutter_youtube_player/player"
    )
  }
}
