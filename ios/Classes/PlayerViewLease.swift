import Flutter
import UIKit

final class PlayerViewLease: NSObject, FlutterPlatformView {
  private let pool: PlayerViewPool
  private let playerView: NativePlayerView

  init(
    pool: PlayerViewPool,
    playerView: NativePlayerView,
    viewId: Int64,
    messenger: FlutterBinaryMessenger
  ) {
    self.pool = pool
    self.playerView = playerView
    super.init()
    playerView.bind(
      viewId: viewId,
      messenger: messenger
    )
  }

  func view() -> UIView { playerView.rootView }

  deinit {
    playerView.unbind()
    pool.release(playerView)
  }
}
