import Flutter
import UIKit

final class PlayerViewLease: NSObject, FlutterPlatformView {
  private let pool: PlayerViewPool
  private let playerView: NativePlayerView
  private let viewId: Int64
  private let containerView: UIView

  init(
    pool: PlayerViewPool,
    playerView: NativePlayerView,
    viewId: Int64,
    messenger: FlutterBinaryMessenger
  ) {
    self.pool = pool
    self.playerView = playerView
    self.viewId = viewId
    containerView = UIView(frame: playerView.rootView.frame)
    super.init()
    // 每个 FlutterPlatformView 独占容器，旧视图回收和布局不会作用于新宿主。
    playerView.rootView.frame = containerView.bounds
    playerView.rootView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    containerView.addSubview(playerView.rootView)
    playerView.bind(
      viewId: viewId,
      messenger: messenger
    )
  }

  func view() -> UIView { containerView }

  deinit {
    pool.release(playerView, viewId: viewId)
  }
}
