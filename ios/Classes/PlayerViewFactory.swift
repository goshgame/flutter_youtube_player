import Flutter
import UIKit

final class PlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private let pool: PlayerViewPool

  init(messenger: FlutterBinaryMessenger, pool: PlayerViewPool) {
    self.messenger = messenger
    self.pool = pool
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let parameters = args as? [String: Any]
    let reuse = parameters?["reuseCurrentVideo"] as? Bool == true
    return PlayerViewLease(
      pool: pool,
      playerView: pool.acquire(
        frame: frame,
        viewId: viewId,
        sessionId: reuse ? (parameters?["sessionId"] as? NSNumber)?.intValue : nil,
        videoId: reuse ? parameters?["videoId"] as? String : nil
      ),
      viewId: viewId,
      messenger: messenger
    )
  }
}
