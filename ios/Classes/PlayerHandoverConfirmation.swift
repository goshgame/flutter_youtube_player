/// 换宿主后的单次 playing 查询可能早于 WebKit 的迟到暂停，需要确认进度继续前进。
struct PlayerHandoverConfirmation {
  private var playingPosition: Double?

  mutating func observe(state: Int, position: Double) -> Bool {
    guard state == 1, position.isFinite, position >= 0 else {
      playingPosition = nil
      return false
    }
    defer { playingPosition = position }
    guard let previous = playingPosition else { return false }
    return position > previous
  }
}
