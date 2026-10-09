import UIKit

/// 平台视图创建不等于进入窗口；交接恢复必须等新宿主实际挂载并完成布局。
final class PlayerHostView: UIView {
  var onLayoutInWindow: (() -> Void)?
  private var hasLaidOutInWindow = false

  var isReadyForPlayback: Bool {
    hasLaidOutInWindow && window != nil && bounds.width > 0 && bounds.height > 0
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    hasLaidOutInWindow = false
    if window != nil { setNeedsLayout() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    hasLaidOutInWindow = window != nil
    if isReadyForPlayback { onLayoutInWindow?() }
  }
}
