import UIKit

final class PlayerViewPool {
  // 限制空闲缓存；交接时优先按播放会话接管，不依赖回收顺序。
  private static let maximumIdlePlayerCount = 3

  private final class Entry {
    let playerView: NativePlayerView
    var ownerViewId: Int64?
    var isInUse: Bool { ownerViewId != nil }
    var isAvailable: Bool { !isInUse && !playerView.isRetainingHandover }
    var idleOrder = 0

    init(_ playerView: NativePlayerView) {
      self.playerView = playerView
    }
  }

  private weak var parkingView: UIView?
  private var entries: [Entry] = []
  private var nextIdleOrder = 0

  init(parkingView: UIView?) {
    self.parkingView = parkingView
  }

  func acquire(frame: CGRect, viewId: Int64, sessionId: Int?, videoId: String?) -> NativePlayerView {
    dispatchPrecondition(condition: .onQueue(.main))
    removeInvalidIdlePlayers()
    let entry: Entry
    if let sessionId, let videoId,
       let retained = entries.first(where: {
         $0.playerView.canTakeOver(sessionId: sessionId, videoId: videoId)
       }) {
      entry = retained
      // Flutter 原生释放可晚于新宿主创建，主动交还旧通道后接管同一 WebView。
      if entry.isInUse { entry.playerView.unbind(retainingPlayback: true) }
    } else if let idle = entries.filter({ $0.isAvailable }).max(by: { $0.idleOrder < $1.idleOrder }) {
      entry = idle
    } else {
      entry = Entry(NativePlayerView(frame: frame))
      entries.append(entry)
    }
    entry.playerView.rootView.removeFromSuperview()
    entry.playerView.rootView.frame = frame
    entry.ownerViewId = viewId
    if let sessionId {
      // 无法接管时也终止同会话的旧保活实例，避免备用加载留下后台声音。
      discardRetainedPlayback(sessionId: sessionId, excluding: entry.playerView)
    }
    return entry.playerView
  }

  func release(_ playerView: NativePlayerView, viewId: Int64) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let entry = entries.first(where: { $0.playerView === playerView }),
          entry.ownerViewId == viewId else { return }
    // 旧租约迟到释放时不能解绑、暂停或移走新宿主的播放器。
    playerView.unbind()
    entry.ownerViewId = nil
    let currentWindow = playerView.rootView.window
    playerView.rootView.removeFromSuperview()
    let attachedParkingView = parkingView?.window == nil ? nil : parkingView
    if playerView.isRetainingHandover && !playerView.isInvalidated,
       let host = attachedParkingView ?? currentWindow {
      // 保持 WKWebView 附着在窗口树，交接期间仅移到可见区域外。
      let size = playerView.rootView.bounds.size
      playerView.rootView.frame.origin = CGPoint(
        x: -max(size.width, 1),
        y: -max(size.height, 1)
      )
      host.addSubview(playerView.rootView)
    }
    nextIdleOrder += 1
    entry.idleOrder = nextIdleOrder
    if playerView.isInvalidated {
      entries.removeAll { $0 === entry }
      destroyIdlePlayerView(playerView)
    } else {
      trimIdlePlayerViewsIfNeeded()
    }
  }

  func discardRetainedPlayback(sessionId: Int, excluding playerView: NativePlayerView? = nil) {
    dispatchPrecondition(condition: .onQueue(.main))
    entries.forEach { entry in
      if entry.playerView !== playerView,
         entry.playerView.discardRetainedPlayback(sessionId: sessionId),
         !entry.isInUse {
        entry.playerView.rootView.removeFromSuperview()
      }
    }
    trimIdlePlayerViewsIfNeeded()
  }

  private func removeInvalidIdlePlayers() {
    let invalid = entries.filter {
      !$0.isInUse && $0.playerView.isInvalidated
    }
    entries.removeAll { entry in invalid.contains { $0 === entry } }
    invalid.forEach { destroyIdlePlayerView($0.playerView) }
  }

  private func trimIdlePlayerViewsIfNeeded() {
    // 保活实例仍属于原播放会话，不进入通用空闲缓存，也不被 LRU 提前销毁。
    while entries.filter({ $0.isAvailable }).count > Self.maximumIdlePlayerCount {
      guard let oldest = entries
        .filter({ $0.isAvailable })
        .min(by: { $0.idleOrder < $1.idleOrder }) else { return }
      entries.removeAll { $0 === oldest }
      destroyIdlePlayerView(oldest.playerView)
    }
  }

  private func destroyIdlePlayerView(_ playerView: NativePlayerView) {
    playerView.rootView.removeFromSuperview()
    playerView.destroy()
  }
}
