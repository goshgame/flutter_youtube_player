import WebKit

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
  weak var delegate: WKScriptMessageHandler?
  private(set) var isReady = false

  func markNotReady() {
    isReady = false
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    if let payload = message.body as? [String: Any],
       payload["event"] as? String == "Ready" {
      isReady = true
    }
    delegate?.userContentController(userContentController, didReceive: message)
  }
}
