import Flutter
import UIKit
import WebKit

final class NativePlayerView: NSObject,
  WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
  private static let origin = "http://example.com"
  private static let processPool = WKProcessPool()
  private static let resumePlayRetryInterval = 0.4
  private static let maximumResumePlayAttempts = 8
  private static let pictureInPictureCommandTimeout = 4.0
  private static let videoIdPattern = try! NSRegularExpression(
    pattern: "^[A-Za-z0-9_-]{11}$"
  )
  private static var cachedTemplate: String?
  private static let pictureInPictureBridge = #"""
    (function () {
      if (window.parent === window || window.location.hostname !== 'www.youtube.com') return;
      if (window.__flutterYouTubePictureInPictureBridge) return;
      window.__flutterYouTubePictureInPictureBridge = true;

      var trackedVideo = null;
      var trackedAvailability = null;
      var trackedActive = null;

      function sendEvent(name, data) {
        if (!window.webkit || !window.webkit.messageHandlers.youtubeEvent) return;
        window.webkit.messageHandlers.youtubeEvent.postMessage({ event: name, data: data });
      }

      function supportsPictureInPicture(video) {
        if (!video || video.readyState === 0 || video.disablePictureInPicture) return false;
        if (typeof video.webkitSetPresentationMode === 'function') {
          return typeof video.webkitSupportsPresentationMode !== 'function' ||
            video.webkitSupportsPresentationMode('picture-in-picture');
        }
        return document.pictureInPictureEnabled === true &&
          typeof video.requestPictureInPicture === 'function';
      }

      function isPictureInPicture(video) {
        if (!video) return false;
        return video.webkitPresentationMode === 'picture-in-picture' ||
          document.pictureInPictureElement === video;
      }

      function reportState() {
        var availability = supportsPictureInPicture(trackedVideo);
        var active = isPictureInPicture(trackedVideo);
        if (availability !== trackedAvailability) {
          trackedAvailability = availability;
          sendEvent('PictureInPictureAvailability', availability);
        }
        if (active !== trackedActive) {
          trackedActive = active;
          sendEvent('PictureInPictureStateChange', active);
        }
      }

      function detachVideo() {
        if (!trackedVideo) return;
        trackedVideo.removeEventListener('loadedmetadata', reportState);
        trackedVideo.removeEventListener('canplay', reportState);
        trackedVideo.removeEventListener('emptied', reportState);
        trackedVideo.removeEventListener('webkitpresentationmodechanged', reportState);
        trackedVideo.removeEventListener('enterpictureinpicture', reportState);
        trackedVideo.removeEventListener('leavepictureinpicture', reportState);
        trackedVideo = null;
        trackedAvailability = null;
        trackedActive = null;
      }

      function findVideo() {
        var video = document.querySelector('video');
        if (video === trackedVideo) {
          reportState();
          return video;
        }
        detachVideo();
        if (!video) {
          reportState();
          return null;
        }
        trackedVideo = video;
        video.addEventListener('loadedmetadata', reportState);
        video.addEventListener('canplay', reportState);
        video.addEventListener('emptied', reportState);
        video.addEventListener('webkitpresentationmodechanged', reportState);
        video.addEventListener('enterpictureinpicture', reportState);
        video.addEventListener('leavepictureinpicture', reportState);
        reportState();
        return video;
      }

      function fail(error, requestId) {
        var message = error && error.message ? error.message : String(error);
        sendEvent('PictureInPictureError', { message: message, requestId: requestId });
      }

      function setPictureInPicture(active, requestId) {
        var video = findVideo();
        if (!video || (active && !supportsPictureInPicture(video))) {
          fail('Picture in Picture is unavailable for the current video', requestId);
          return;
        }
        try {
          if (typeof video.webkitSetPresentationMode === 'function') {
            video.webkitSetPresentationMode(active ? 'picture-in-picture' : 'inline');
            return;
          }
          var operation = active
            ? video.requestPictureInPicture()
            : document.exitPictureInPicture();
          if (operation && typeof operation.catch === 'function') {
            operation.catch(function (error) { fail(error, requestId); });
          }
        } catch (error) {
          fail(error, requestId);
        }
      }

      window.addEventListener('message', function (event) {
        if (event.source !== window.parent || event.origin !== 'http://example.com') return;
        var data = event.data;
        if (!data || data.source !== 'flutter_youtube_player_pip') return;
        if (data.action === 'refresh') {
          trackedAvailability = null;
          trackedActive = null;
          findVideo();
          return;
        }
        setPictureInPicture(data.active === true, data.requestId);
      });

      var observer = new MutationObserver(findVideo);
      if (document.documentElement) {
        observer.observe(document.documentElement, { childList: true, subtree: true });
      }
      findVideo();
    })();
    """#

  let rootView: UIView
  private let webView: WKWebView
  private let messageHandler: WeakScriptMessageHandler
  private let loadingCover: UIView
  private var channel: FlutterMethodChannel?
  private var progressObservation: NSKeyValueObservation?
  private var videoId: String?
  private var wantsToPlay = false
  private var wantsMuted = false
  private var startSeconds = 0.0
  private var prepared = false
  private var shellVideoId: String?
  private var ready = false
  private var invalidated = false
  private var destroyed = false
  private var suspended = false
  private var prewarming = false
  private var duration = 0.0
  private var playerState: Int?
  private var resumePlayAttempt = 0
  private var resumePlayRetryGeneration = 0
  private var resumePlayRetryWorkItem: DispatchWorkItem?
  private var pictureInPictureAvailable = false
  private var pictureInPictureActive = false
  private var pendingPictureInPictureTarget: Bool?
  private var pendingPictureInPictureResult: FlutterResult?
  private var pictureInPictureTimeoutWorkItem: DispatchWorkItem?
  private var pictureInPictureRequestId = 0

  private var keepsPictureInPictureAlive: Bool {
    pictureInPictureActive || pendingPictureInPictureTarget == true
  }

  // 保留页面的暂停意图，等 PiP 退出或启动失败后再执行。
  private func applyDeferredSuspension() {
    guard !keepsPictureInPictureAlive, suspended || prewarming else { return }
    cancelResumePlayRetry()
    evaluate("requestPause()")
    webView.isHidden = !prewarming
    if prewarming && ready { hideLoadingCover() }
    else { showLoadingCover() }
  }

  private func resetPictureInPictureState() {
    pictureInPictureAvailable = false
    pictureInPictureActive = false
    event("pictureInPictureAvailability", values: ["value": false])
    event("pictureInPicture", values: ["value": false])
  }

  var isInvalidated: Bool { invalidated }

  init(frame: CGRect) {
    rootView = UIView(frame: frame)
    rootView.backgroundColor = .black
    messageHandler = WeakScriptMessageHandler()
    let configuration = WKWebViewConfiguration()
    configuration.processPool = Self.processPool
    configuration.websiteDataStore = .default()
    configuration.allowsInlineMediaPlayback = true
    configuration.allowsPictureInPictureMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    if #available(iOS 15.4, *) {
      configuration.preferences.isElementFullscreenEnabled = true
    }
    configuration.userContentController.addUserScript(WKUserScript(
      source: Self.pictureInPictureBridge,
      injectionTime: .atDocumentEnd,
      forMainFrameOnly: false
    ))
    configuration.userContentController.add(messageHandler, name: "youtubeEvent")
    webView = WKWebView(frame: rootView.bounds, configuration: configuration)
    loadingCover = UIView(frame: rootView.bounds)
    loadingCover.backgroundColor = .black
    super.init()

    messageHandler.delegate = self
    webView.isUserInteractionEnabled = false
    webView.allowsLinkPreview = false
    webView.isOpaque = false
    webView.backgroundColor = .black
    webView.scrollView.backgroundColor = .black
    webView.scrollView.bounces = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    webView.navigationDelegate = self
    webView.uiDelegate = self
    loadingCover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    rootView.addSubview(webView)
    rootView.addSubview(loadingCover)
    progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) {
      [weak self] webView, _ in
      self?.event("loading", values: ["value": webView.estimatedProgress])
    }
  }

  deinit {
    destroy()
  }

  func bind(
    viewId: Int64,
    messenger: FlutterBinaryMessenger
  ) {
    precondition(!invalidated && channel == nil)
    wantsToPlay = false
    wantsMuted = false
    startSeconds = 0
    suspended = false
    prewarming = false
    cancelResumePlayRetry()
    webView.isHidden = false
    channel = FlutterMethodChannel(
      name: "flutter_youtube_player/player_\(viewId)",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func unbind() {
    guard channel != nil else { return }
    let discardAfterUnbind = keepsPictureInPictureAlive
    cancelPendingPictureInPicture(
      code: "pip_cancelled",
      message: "The player was detached before Picture in Picture changed"
    )
    wantsToPlay = false
    cancelResumePlayRetry()
    evaluate("requestPause()")
    // 仍在 PiP 转换中的 WebView 不可租给另一个播放器。
    if discardAfterUnbind { invalidated = true }
    channel?.setMethodCallHandler(nil)
    channel = nil
    prewarming = false
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "activate":
      guard let id = arguments?["videoId"] as? String, Self.isValidVideoId(id) else {
        result(FlutterError(
          code: "invalid_video_id",
          message: "Expected an 11 character YouTube video ID",
          details: nil
        ))
        return
      }
      ready = messageHandler.isReady
      wantsMuted = arguments?["muted"] as? Bool ?? false
      load(
        id,
        autoplay: arguments?["autoplay"] as? Bool ?? false,
        startSeconds: Self.validStartSeconds(
          (arguments?["startSeconds"] as? NSNumber)?.doubleValue
        ),
        forceReload: true
      )
    case "load":
      guard let id = arguments?["videoId"] as? String, Self.isValidVideoId(id) else {
        result(FlutterError(
          code: "invalid_video_id",
          message: "Expected an 11 character YouTube video ID",
          details: nil
        ))
        return
      }
      load(
        id,
        autoplay: arguments?["autoplay"] as? Bool ?? true,
        startSeconds: Self.validStartSeconds(
          (arguments?["startSeconds"] as? NSNumber)?.doubleValue
        ),
        forceReload: true
      )
    case "play":
      wantsToPlay = true
      evaluate("requestPlay()")
    case "pause":
      wantsToPlay = false
      cancelResumePlayRetry()
      evaluate("requestPause()")
    case "reload":
      wantsToPlay = true
      showLoadingCover()
      if !prepared, let id = videoId {
        load(id, autoplay: true, startSeconds: 0, forceReload: false)
      } else {
        evaluate("reloadCurrentVideo()")
      }
    case "seekTo":
      let seconds = (arguments?["seconds"] as? NSNumber)?.doubleValue ?? 0
      if seconds.isFinite { evaluate("seekTo(\(max(seconds, 0)),true)") }
    case "suspend":
      suspended = true
      prewarming = false
      applyDeferredSuspension()
    case "prewarm":
      prewarming = true
      // suspend 发出的 JavaScript 可能在 WKWebView 再次可运行后才落地；
      // 预热时重新暂停，保证迟到的 pause 不会覆盖随后的 resume 播放请求。
      applyDeferredSuspension()
    case "resume":
      let shouldPlay = arguments?["play"] as? Bool ?? wantsToPlay
      wantsToPlay = shouldPlay
      suspended = false
      prewarming = false
      webView.isHidden = false
      if ready { loadingCover.isHidden = true }
      if shouldPlay && !keepsPictureInPictureAlive { startResumePlayRetry() }
      else { cancelResumePlayRetry() }
    case "mute":
      wantsMuted = true
      evaluate("mute()")
    case "unmute":
      wantsMuted = false
      evaluate("unMute()")
    case "setVolume":
      let volume = min(max((arguments?["volume"] as? NSNumber)?.intValue ?? 100, 0), 100)
      evaluate("setVolume(\(volume))")
    case "setPlaybackRate":
      let rate = (arguments?["rate"] as? NSNumber)?.doubleValue ?? 1
      if rate.isFinite && rate > 0 { evaluate("setPlaybackRate(\(rate))") }
    case "exitFullscreen":
      evaluate("exitFullscreen()")
    case "enterPictureInPicture":
      setPictureInPicture(true, result: result)
      return
    case "exitPictureInPicture":
      setPictureInPicture(false, result: result)
      return
    case "openInYouTube":
      guard let id = videoId,
            let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else {
        result(FlutterError(
          code: "open_failed",
          message: "Unable to open this video in YouTube",
          details: nil
        ))
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        if opened {
          result(nil)
        } else {
          result(FlutterError(
            code: "open_failed",
            message: "Unable to open this video in YouTube",
            details: nil
          ))
        }
      }
      return
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  private func load(
    _ id: String,
    autoplay: Bool,
    startSeconds requestedStartSeconds: Double,
    forceReload: Bool
  ) {
    guard !invalidated else { return }
    cancelPendingPictureInPicture(code: "pip_cancelled", message: "The video is changing")
    cancelResumePlayRetry()
    let changed = id != videoId
    videoId = id
    wantsToPlay = autoplay
    startSeconds = requestedStartSeconds
    if changed || forceReload {
      duration = 0
      playerState = nil
      showLoadingCover()
    }

    if prepared {
      if messageHandler.isReady {
        switchVideo(id, autoplay: autoplay, startSeconds: startSeconds)
        return
      }
      if !forceReload { return }
      // 上一个租约仍在加载时直接重建页面，避免同视频复用旧的进度、静音或自动播放参数。
      webView.stopLoading()
      prepared = false
    }

    guard let template = Self.playerTemplate() else {
      hideLoadingCover()
      event("loadError", values: ["message": "Unable to read YTPlayer.html"])
      return
    }
    resetPictureInPictureState()
    prepared = true
    messageHandler.markNotReady()
    ready = false
    shellVideoId = id
    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.youtube.com"
    components.path = "/embed/\(id)"
    components.queryItems = [
      // 首次 iframe 先保持暂停，Ready 后由原生播放意图统一发起播放。
      URLQueryItem(name: "autoplay", value: "0"),
      URLQueryItem(name: "start", value: String(startSeconds)),
      URLQueryItem(name: "enablejsapi", value: "1"),
      URLQueryItem(name: "origin", value: Self.origin),
      URLQueryItem(name: "playsinline", value: "1"),
      URLQueryItem(name: "rel", value: "0"),
      URLQueryItem(name: "controls", value: "0"),
      URLQueryItem(name: "disablekb", value: "1"),
      URLQueryItem(name: "cc_load_policy", value: "0"),
      URLQueryItem(name: "iv_load_policy", value: "3"),
      URLQueryItem(name: "modestbranding", value: "1"),
    ]
    guard let embedUrl = components.url?.absoluteString else {
      prepared = false
      hideLoadingCover()
      event("loadError", values: ["message": "Unable to create the YouTube embed URL"])
      return
    }
    let html = template
      .replacingOccurrences(of: "{{EMBED_URL}}", with: Self.htmlEscape(embedUrl))
      .replacingOccurrences(of: "{{TITLE}}", with: "YouTube video player")
      .replacingOccurrences(of: "{{VIDEO_ID}}", with: id)
      .replacingOccurrences(of: "{{AUTOPLAY}}", with: "false")
      .replacingOccurrences(of: "{{START_SECONDS}}", with: String(startSeconds))
      .replacingOccurrences(of: "{{MUTED}}", with: wantsMuted ? "true" : "false")
    webView.loadHTMLString(html, baseURL: URL(string: "\(Self.origin)/"))
  }

  private static func playerTemplate() -> String? {
    if let cachedTemplate { return cachedTemplate }
    let classBundle = Bundle(for: FlutterYoutubePlayerPlugin.self)
    let resourceBundle = classBundle.url(
      forResource: "flutter_youtube_player_resources",
      withExtension: "bundle"
    ).flatMap(Bundle.init(url:))
    guard let url = resourceBundle?.url(forResource: "YTPlayer", withExtension: "html"),
          let source = try? String(contentsOf: url, encoding: .utf8) else {
      return nil
    }
    cachedTemplate = source
    return source
  }

  private func evaluate(_ source: String) {
    guard !invalidated else { return }
    webView.evaluateJavaScript(source)
  }

  private func setPictureInPicture(
    _ active: Bool,
    result: @escaping FlutterResult
  ) {
    guard !invalidated else {
      result(FlutterError(
        code: "pip_unavailable",
        message: "The player is unavailable",
        details: nil
      ))
      return
    }
    guard pendingPictureInPictureResult == nil else {
      result(FlutterError(
        code: "pip_in_progress",
        message: "Another Picture in Picture request is still in progress",
        details: nil
      ))
      return
    }
    if pictureInPictureActive == active {
      result(nil)
      return
    }
    if active && !pictureInPictureAvailable {
      result(FlutterError(
        code: "pip_unavailable",
        message: "Picture in Picture is unavailable for the current video",
        details: nil
      ))
      return
    }
    pictureInPictureRequestId += 1
    let requestId = pictureInPictureRequestId
    pendingPictureInPictureTarget = active
    pendingPictureInPictureResult = result
    cancelResumePlayRetry()
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.pictureInPictureRequestId == requestId else { return }
      self.cancelPendingPictureInPicture(
        code: "pip_timeout",
        message: "Timed out while changing Picture in Picture state"
      )
    }
    pictureInPictureTimeoutWorkItem = timeout
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.pictureInPictureCommandTimeout,
      execute: timeout
    )
    webView.evaluateJavaScript("requestPictureInPicture(\(active ? "true" : "false"),\(requestId))") {
      [weak self] value, error in
      guard let self, self.pictureInPictureRequestId == requestId,
            self.pendingPictureInPictureResult != nil else { return }
      if let error {
        self.cancelPendingPictureInPicture(
          code: "pip_failed",
          message: error.localizedDescription
        )
      } else if value as? Bool != true {
        self.cancelPendingPictureInPicture(
          code: "pip_failed",
          message: "The embedded player did not accept the Picture in Picture request"
        )
      }
    }
  }

  private func completePendingPictureInPictureIfNeeded(active: Bool) {
    guard pendingPictureInPictureTarget == active,
          let result = pendingPictureInPictureResult else { return }
    pictureInPictureTimeoutWorkItem?.cancel()
    pictureInPictureTimeoutWorkItem = nil
    pendingPictureInPictureTarget = nil
    pendingPictureInPictureResult = nil
    applyDeferredSuspension()
    result(nil)
  }

  private func cancelPendingPictureInPicture(code: String, message: String) {
    guard let result = pendingPictureInPictureResult else { return }
    pictureInPictureTimeoutWorkItem?.cancel()
    pictureInPictureTimeoutWorkItem = nil
    pendingPictureInPictureTarget = nil
    pendingPictureInPictureResult = nil
    applyDeferredSuspension()
    result(FlutterError(code: code, message: message, details: nil))
  }

  private func switchVideo(
    _ id: String,
    autoplay: Bool,
    startSeconds: Double
  ) {
    guard let boundChannel = channel else { return }
    let quotedId = Self.jsonQuote(id)
    let source = "loadVideoById(\(quotedId),\(autoplay ? "true" : "false")," +
      "\(startSeconds),\(wantsMuted ? "true" : "false"))"
    webView.evaluateJavaScript(source) { [weak self] value, error in
      guard let self,
            !self.invalidated,
            self.channel === boundChannel,
            self.videoId == id else { return }
      if error == nil, value as? Bool == true {
        // 复用 WebView 时，切换命令被目标播放器接受后才通知 Dart 可以补发控制命令。
        self.event("ready")
        self.evaluate("refreshPictureInPicture()")
        return
      }
      self.prepared = false
      self.messageHandler.markNotReady()
      self.ready = false
      self.load(
        id,
        autoplay: autoplay,
        startSeconds: startSeconds,
        forceReload: true
      )
    }
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard message.name == "youtubeEvent",
          let payload = message.body as? [String: Any],
          let type = payload["event"] as? String else { return }
    let data = payload["data"]
    if type.hasPrefix("PictureInPicture") {
      let host = message.frameInfo.request.url?.host?.lowercased()
      guard host == "youtube.com" || host?.hasSuffix(".youtube.com") == true else {
        return
      }
    }
    switch type {
    case "Ready":
      ready = true
      evaluate("refreshPictureInPicture()")
      if prewarming { hideLoadingCover() }
      if videoId != shellVideoId, let id = videoId {
        switchVideo(id, autoplay: wantsToPlay, startSeconds: startSeconds)
      } else if wantsToPlay && !suspended {
        event("ready")
        startResumePlayRetry()
      } else {
        event("ready")
      }
    case "StateChange":
      let state = (data as? NSNumber)?.intValue ?? -999
      let exitedBufferingToUnstarted = playerState == 3 && state == -1
      playerState = state
      if state == 1 {
        cancelResumePlayRetry()
        if !suspended || prewarming { hideLoadingCover() }
      } else if exitedBufferingToUnstarted && (!suspended || prewarming) {
        // Upcoming videos can return to UNSTARTED after buffering. Reveal the
        // WebView's scheduled state without changing the WebView visibility.
        hideLoadingCover()
      }
      event("state", values: [
        "value": state,
        "hideInitialOverlay": exitedBufferingToUnstarted,
      ])
    case "VideoData":
      let values = data as? [String: Any]
      duration = max((values?["duration"] as? NSNumber)?.doubleValue ?? 0, 0)
      event("videoData", values: [
        "duration": duration,
        "title": values?["title"] as? String ?? "",
        "author": values?["author"] as? String ?? "",
      ])
    case "VideoTime":
      let values = data as? [String: Any]
      event("progress", values: [
        "position": max((values?["currentTime"] as? NSNumber)?.doubleValue ?? 0, 0),
        "duration": duration,
        "loadedFraction": max((values?["loadedFraction"] as? NSNumber)?.doubleValue ?? 0, 0),
      ])
    case "AutoplayBlocked":
      cancelResumePlayRetry()
      event("autoplayBlocked")
    case "PlaybackQualityChange":
      event("playbackQuality", values: ["value": data as? String ?? ""])
    case "PlaybackRateChange":
      event("playbackRate", values: [
        "value": (data as? NSNumber)?.doubleValue ?? 1,
      ])
    case "AudioState":
      let values = data as? [String: Any]
      event("audioState", values: [
        "isMuted": values?["isMuted"] as? Bool ?? wantsMuted,
        "volume": min(max((values?["volume"] as? NSNumber)?.intValue ?? 100, 0), 100),
      ])
    case "FullscreenChange":
      event("fullscreen", values: ["value": data as? Bool ?? false])
    case "PictureInPictureAvailability":
      pictureInPictureAvailable = data as? Bool ?? false
      event("pictureInPictureAvailability", values: [
        "value": pictureInPictureAvailable,
      ])
      if !pictureInPictureAvailable && pendingPictureInPictureTarget == true {
        cancelPendingPictureInPicture(
          code: "pip_unavailable",
          message: "Picture in Picture became unavailable"
        )
      }
    case "PictureInPictureStateChange":
      pictureInPictureActive = data as? Bool ?? false
      event("pictureInPicture", values: ["value": pictureInPictureActive])
      completePendingPictureInPictureIfNeeded(active: pictureInPictureActive)
      applyDeferredSuspension()
    case "PictureInPictureError":
      guard let error = data as? [String: Any],
            (error["requestId"] as? NSNumber)?.intValue == pictureInPictureRequestId else { return }
      cancelPendingPictureInPicture(
        code: "pip_failed",
        message: error["message"] as? String ?? "Picture in Picture failed"
      )
    case "Error":
      cancelResumePlayRetry()
      hideLoadingCover()
      event("youtubeError", values: ["code": (data as? NSNumber)?.intValue as Any])
    default:
      break
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
    event("pageFinished", values: ["title": webView.title as Any])
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation?,
    withError error: Error
  ) {
    markLoadFailed(error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    cancelPendingPictureInPicture(
      code: "pip_failed",
      message: "The iOS WebKit content process exited"
    )
    cancelResumePlayRetry()
    invalidated = true
    resetPictureInPictureState()
    prepared = false
    messageHandler.markNotReady()
    ready = false
    hideLoadingCover()
    event("rendererGone", values: [
      "message": "The iOS WebKit content process exited",
    ])
  }

  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
      webView.load(URLRequest(url: url))
    }
    return nil
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation?,
    withError error: Error
  ) {
    markLoadFailed(error)
  }

  private func markLoadFailed(_ error: Error) {
    let nsError = error as NSError
    guard nsError.code != NSURLErrorCancelled else { return }
    cancelPendingPictureInPicture(
      code: "pip_failed",
      message: nsError.localizedDescription
    )
    cancelResumePlayRetry()
    prepared = false
    resetPictureInPictureState()
    messageHandler.markNotReady()
    ready = false
    hideLoadingCover()
    event("loadError", values: ["message": nsError.localizedDescription])
  }

  private func event(_ type: String, values: [String: Any] = [:]) {
    var payload = values
    payload["type"] = type
    channel?.invokeMethod("event", arguments: payload)
  }

  private func showLoadingCover() {
    loadingCover.isHidden = false
  }

  private func hideLoadingCover() {
    loadingCover.isHidden = true
  }

  private func startResumePlayRetry() {
    cancelResumePlayRetry()
    let generation = resumePlayRetryGeneration
    scheduleResumePlayAttempt(after: 0, generation: generation)
  }

  private func scheduleResumePlayAttempt(
    after delay: TimeInterval,
    generation: Int
  ) {
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      // 已取消的 DispatchWorkItem 仍可能被调度。旧代任务只能退出，不能取消
      // 当前代刚创建的恢复链。
      guard generation == self.resumePlayRetryGeneration else { return }
      guard !self.invalidated,
            self.channel != nil,
            !self.keepsPictureInPictureAlive,
            !self.suspended,
            self.wantsToPlay,
            self.resumePlayAttempt < Self.maximumResumePlayAttempts else {
        self.cancelResumePlayRetry()
        return
      }
      self.resumePlayAttempt += 1
      self.evaluate("requestPlay()")
      self.scheduleResumePlayAttempt(
        after: Self.resumePlayRetryInterval,
        generation: generation
      )
    }
    resumePlayRetryWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func cancelResumePlayRetry() {
    resumePlayRetryGeneration += 1
    resumePlayRetryWorkItem?.cancel()
    resumePlayRetryWorkItem = nil
    resumePlayAttempt = 0
  }

  func destroy() {
    guard !destroyed else { return }
    cancelPendingPictureInPicture(
      code: "pip_cancelled",
      message: "The player was destroyed before Picture in Picture changed"
    )
    cancelResumePlayRetry()
    if !invalidated { evaluate("requestPause()") }
    destroyed = true
    invalidated = true
    channel?.setMethodCallHandler(nil)
    channel = nil
    progressObservation?.invalidate()
    progressObservation = nil
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.removeFromSuperview()
    messageHandler.delegate = nil
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: "youtubeEvent"
    )
  }

  private static func isValidVideoId(_ value: String) -> Bool {
    let range = NSRange(value.startIndex..., in: value)
    return videoIdPattern.firstMatch(in: value, range: range)?.range == range
  }

  private static func validStartSeconds(_ value: Double?) -> Double {
    guard let value, value.isFinite, value >= 0 else { return 0 }
    return value
  }

  private static func jsonQuote(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value]),
          let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
    return String(encoded.dropFirst().dropLast())
  }

  private static func htmlEscape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }

}
