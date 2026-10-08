import UIKit

final class PlayerViewPool {
  // kapt 同一时刻只保留一个详情页或迷你播放器，缓存一个空闲 WebView 即可覆盖切换场景。
  private static let maximumIdlePlayerCount = 3

  private final class Entry {
    let playerView: NativePlayerView
    var isInUse = false
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

  func acquire(frame: CGRect) -> NativePlayerView {
    dispatchPrecondition(condition: .onQueue(.main))
    removeInvalidIdlePlayers()
    let entry: Entry
    if let idle = entries.filter({ !$0.isInUse }).max(by: { $0.idleOrder < $1.idleOrder }) {
      entry = idle
      entry.playerView.rootView.removeFromSuperview()
      entry.playerView.rootView.frame = frame
    } else {
      entry = Entry(NativePlayerView(frame: frame))
      entries.append(entry)
    }
    entry.isInUse = true
    return entry.playerView
  }

  func release(_ playerView: NativePlayerView) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard let entry = entries.first(where: { $0.playerView === playerView }),
          entry.isInUse else { return }
    entry.isInUse = false
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

  func discardRetainedPlayback(sessionId: Int) {
    dispatchPrecondition(condition: .onQueue(.main))
    entries.forEach { entry in
      if entry.playerView.discardRetainedPlayback(sessionId: sessionId),
         !entry.isInUse {
        entry.playerView.rootView.removeFromSuperview()
      }
    }
  }

  private func removeInvalidIdlePlayers() {
    let invalid = entries.filter {
      !$0.isInUse && $0.playerView.isInvalidated
    }
    entries.removeAll { entry in invalid.contains { $0 === entry } }
    invalid.forEach { destroyIdlePlayerView($0.playerView) }
  }

  private func trimIdlePlayerViewsIfNeeded() {
    while entries.filter({ !$0.isInUse }).count > Self.maximumIdlePlayerCount {
      guard let oldest = entries
        .filter({ !$0.isInUse })
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
