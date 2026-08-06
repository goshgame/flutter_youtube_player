package com.podoc.flutter_youtube_player

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.nio.charset.StandardCharsets
import java.util.regex.Pattern
import kotlin.math.abs

internal class NativePlayerView(
  context: Context,
) : MethodChannel.MethodCallHandler {
  companion object {
    private const val ASSET = "flutter_youtube_player/YTPlayer.html"
    private const val ORIGIN = "http://example.com"
    private const val TAG = "FlutterYoutubePlayer"
    private val videoIdPattern = Pattern.compile("[A-Za-z0-9_-]{11}")
    @Volatile private var cachedTemplate: String? = null
  }

  val rootView = FrameLayout(context).apply { setBackgroundColor(Color.BLACK) }
  private val longPressSuppressor = LongPressSuppressor(context)
  private val webView = createWebView(context)
  private val loadingCover = View(context).apply { setBackgroundColor(Color.BLACK) }
  private var channel: MethodChannel? = null
  private var hostActivity = WeakReference<Activity>(null)
  private var videoId: String? = null
  private var wantsToPlay = false
  private var wantsMuted = false
  private var startSeconds = 0.0
  private var prepared = false
  private var ready = false
  private var destroyed = false
  private var rendererGone = false
  private var suspended = false
  private var resumeAfterLifecycle = false
  private var shellVideoId: String? = null
  private var duration = 0.0
  private var customView: View? = null
  private var customViewCallback: WebChromeClient.CustomViewCallback? = null

  val isInvalidated: Boolean get() = destroyed || rendererGone

  init {
    rootView.addView(webView, FrameLayout.LayoutParams(-1, -1))
    rootView.addView(loadingCover, FrameLayout.LayoutParams(-1, -1))
  }

  fun bind(
    messenger: BinaryMessenger,
    viewId: Int,
    activity: Activity?,
  ) {
    check(!destroyed && channel == null)
    hostActivity = WeakReference(activity)
    channel = MethodChannel(messenger, "flutter_youtube_player/player_$viewId").also {
      it.setMethodCallHandler(this)
    }
    wantsToPlay = false
    wantsMuted = false
    startSeconds = 0.0
    suspended = false
    resumeAfterLifecycle = false
    webView.visibility = View.VISIBLE
    webView.onResume()
  }

  fun unbind() {
    if (channel == null) return
    wantsToPlay = false
    evaluate("requestPause()")
    hideCustomView()
    channel?.setMethodCallHandler(null)
    channel = null
    hostActivity.clear()
    resumeAfterLifecycle = false
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "activate" -> {
        val id = call.argument<String>("videoId")
        if (!isValidVideoId(id)) {
          result.error("invalid_video_id", "Expected an 11 character YouTube video ID", null)
          return
        }
        wantsMuted = call.argument<Boolean>("muted") ?: false
        load(
          id!!,
          call.argument<Boolean>("autoplay") ?: false,
          validStartSeconds(call.argument<Number>("startSeconds")?.toDouble()),
          true,
        )
      }
      "load" -> {
        val id = call.argument<String>("videoId")
        if (!isValidVideoId(id)) {
          result.error("invalid_video_id", "Expected an 11 character YouTube video ID", null)
          return
        }
        load(
          id!!,
          call.argument<Boolean>("autoplay") ?: true,
          validStartSeconds(call.argument<Number>("startSeconds")?.toDouble()),
          true,
        )
      }
      "play" -> {
        wantsToPlay = true
        evaluate("requestPlay()")
      }
      "pause" -> {
        wantsToPlay = false
        evaluate("requestPause()")
      }
      "reload" -> {
        wantsToPlay = true
        showLoadingCover()
        val id = videoId
        if (!prepared && id != null) load(id, true, 0.0, false)
        else evaluate("reloadCurrentVideo()")
      }
      "seekTo" -> {
        val seconds = call.argument<Number>("seconds")?.toDouble() ?: 0.0
        if (seconds.isFinite()) evaluate("seekTo(${seconds.coerceAtLeast(0.0)},true)")
      }
      "suspend" -> {
        if (!suspended) resumeAfterLifecycle = wantsToPlay
        suspended = true
        evaluate("requestPause()")
        webView.onPause()
        showLoadingCover()
        webView.visibility = View.INVISIBLE
      }
      "resume" -> {
        suspended = false
        webView.visibility = View.VISIBLE
        webView.onResume()
        if (resumeAfterLifecycle && wantsToPlay) evaluate("requestPlay()")
        else if (ready) loadingCover.visibility = View.GONE
        resumeAfterLifecycle = false
      }
      "mute" -> {
        wantsMuted = true
        evaluate("mute()")
      }
      "unmute" -> {
        wantsMuted = false
        evaluate("unMute()")
      }
      "setVolume" -> {
        val volume = call.argument<Number>("volume")?.toInt()?.coerceIn(0, 100) ?: 100
        evaluate("setVolume($volume)")
      }
      "setPlaybackRate" -> {
        val rate = call.argument<Number>("rate")?.toDouble() ?: 1.0
        if (rate.isFinite() && rate > 0) evaluate("setPlaybackRate($rate)")
      }
      "exitFullscreen" -> hideCustomView()
      "openInYouTube" -> {
        if (!openInYouTube()) {
          result.error("open_failed", "Unable to open this video in YouTube", null)
          return
        }
      }
      else -> {
        result.notImplemented()
        return
      }
    }
    result.success(null)
  }

  private fun load(
    id: String,
    autoplay: Boolean,
    requestedStartSeconds: Double,
    forceReload: Boolean,
  ) {
    if (destroyed || rendererGone) return
    val changed = id != videoId
    videoId = id
    wantsToPlay = autoplay
    startSeconds = requestedStartSeconds
    if (changed || forceReload) {
      duration = 0.0
      showLoadingCover()
    }
    if (prepared) {
      if (ready) {
        switchVideo(id, autoplay, startSeconds)
        return
      }
      if (!forceReload) return
      // 上一个租约仍在加载时直接重建页面，避免同视频复用旧的进度、静音或自动播放参数。
      webView.stopLoading()
      prepared = false
    }

    val template = readTemplate() ?: return
    prepared = true
    ready = false
    shellVideoId = id
    val embedUrl = Uri.Builder()
      .scheme("https")
      .authority("www.youtube.com")
      .appendPath("embed")
      .appendPath(id)
      .appendQueryParameter("autoplay", if (autoplay) "1" else "0")
      .appendQueryParameter("start", startSeconds.toString())
      .appendQueryParameter("enablejsapi", "1")
      .appendQueryParameter("origin", ORIGIN)
      .appendQueryParameter("playsinline", "1")
      .appendQueryParameter("rel", "0")
      .appendQueryParameter("controls", "0")
      .appendQueryParameter("disablekb", "1")
      .appendQueryParameter("cc_load_policy", "0")
      .appendQueryParameter("iv_load_policy", "3")
      .appendQueryParameter("modestbranding", "1")
      .build()
      .toString()
    val html = template
      .replace("{{EMBED_URL}}", htmlEscape(embedUrl))
      .replace("{{TITLE}}", "YouTube video player")
      .replace("{{VIDEO_ID}}", id)
      .replace("{{AUTOPLAY}}", autoplay.toString())
      .replace("{{START_SECONDS}}", startSeconds.toString())
      .replace("{{MUTED}}", wantsMuted.toString())
    webView.loadDataWithBaseURL("$ORIGIN/", html, "text/html", "UTF-8", null)
  }

  private fun readTemplate(): String? {
    cachedTemplate?.let { return it }
    return try {
      webView.context.assets.open(ASSET).bufferedReader(StandardCharsets.UTF_8).use {
        it.readText().also { source -> cachedTemplate = source }
      }
    } catch (error: Exception) {
      hideLoadingCover()
      event("loadError", "message" to "Unable to read player template: ${error.message}")
      null
    }
  }

  @SuppressLint(
    "SetJavaScriptEnabled",
    "AddJavascriptInterface",
    "ClickableViewAccessibility",
  )
  private fun createWebView(context: Context) = WebView(context).apply {
    settings.javaScriptEnabled = true
    settings.domStorageEnabled = true
    settings.mediaPlaybackRequiresUserGesture = false
    settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
    settings.allowFileAccess = false
    settings.allowContentAccess = false
    settings.cacheMode = WebSettings.LOAD_DEFAULT
    isClickable = true
    // Consume WebView long-click callbacks in addition to cancelling the touch
    // stream below. The callback covers native selection/context-menu paths;
    // the touch cancellation prevents the cross-origin iframe from seeing a
    // completed long press.
    isHapticFeedbackEnabled = false
    setOnLongClickListener { true }
    setOnTouchListener(longPressSuppressor)
    setBackgroundColor(Color.BLACK)
    setLayerType(View.LAYER_TYPE_HARDWARE, null)
    addJavascriptInterface(Bridge(), "YouTubeAndroid")
    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
    webViewClient = PlayerWebViewClient()
    webChromeClient = PlayerChromeClient()
  }

  private fun evaluate(script: String) {
    if (!destroyed && !rendererGone) webView.evaluateJavascript(script, null)
  }

  private fun switchVideo(id: String, autoplay: Boolean, requestedStartSeconds: Double) {
    val boundChannel = channel
    val source =
      "loadVideoById(${JSONObject.quote(id)},$autoplay,$requestedStartSeconds,$wantsMuted)"
    webView.evaluateJavascript(source) { value ->
      if (
        destroyed || rendererGone || videoId != id ||
        boundChannel == null || channel !== boundChannel
      ) {
        return@evaluateJavascript
      }
      if (value == "true") {
        // 复用 WebView 时只有目标视频切换命令被接受后，Dart 才能继续发送播放命令。
        event("ready")
        return@evaluateJavascript
      }
      prepared = false
      ready = false
      load(id, autoplay, requestedStartSeconds, true)
    }
  }

  private fun handleMessage(raw: String) {
    if (destroyed) return
    try {
      val payload = JSONObject(raw)
      when (payload.optString("event")) {
        "Ready" -> {
          ready = true
          if (videoId != shellVideoId) {
            videoId?.let { switchVideo(it, wantsToPlay, startSeconds) }
          } else if (wantsToPlay && !suspended) {
            event("ready")
            evaluate("requestPlay()")
          } else {
            event("ready")
          }
        }
        "StateChange" -> {
          val state = payload.optInt("data", -999)
          if (state == 1 && !suspended) loadingCover.visibility = View.GONE
          event("state", "value" to state)
        }
        "VideoData" -> {
          val data = payload.optJSONObject("data") ?: return
          duration = data.optDouble("duration", 0.0).coerceAtLeast(0.0)
          event(
            "videoData",
            "duration" to duration,
            "title" to data.optString("title"),
            "author" to data.optString("author"),
          )
        }
        "VideoTime" -> {
          val data = payload.optJSONObject("data") ?: return
          event(
            "progress",
            "position" to data.optDouble("currentTime", 0.0),
            "duration" to duration,
            "loadedFraction" to data.optDouble("loadedFraction", 0.0),
          )
        }
        "AutoplayBlocked" -> event("autoplayBlocked")
        "PlaybackQualityChange" -> event("playbackQuality", "value" to payload.optString("data"))
        "PlaybackRateChange" -> event("playbackRate", "value" to payload.optDouble("data", 1.0))
        "AudioState" -> {
          val data = payload.optJSONObject("data") ?: return
          event(
            "audioState",
            "isMuted" to data.optBoolean("isMuted", wantsMuted),
            "volume" to data.optInt("volume", 100).coerceIn(0, 100),
          )
        }
        "FullscreenChange" -> event("fullscreen", "value" to payload.optBoolean("data", false))
        "Error" -> {
          hideLoadingCover()
          event("youtubeError", "code" to payload.optInt("data"))
        }
      }
    } catch (error: Exception) {
      // 桥接数据只应来自内置页面；记录异常便于定位页面与原生协议不一致。
      Log.w(TAG, "Invalid message from the bundled player page", error)
    }
  }

  private fun event(type: String, vararg values: Pair<String, Any?>) {
    val payload = mutableMapOf<String, Any?>("type" to type)
    payload.putAll(values)
    channel?.invokeMethod("event", payload)
  }

  private fun showLoadingCover() {
    loadingCover.visibility = View.VISIBLE
  }

  private fun hideLoadingCover() {
    loadingCover.visibility = View.GONE
  }

  fun destroy() {
    if (destroyed) return
    evaluate("requestPause()")
    destroyed = true
    hideCustomView()
    channel?.setMethodCallHandler(null)
    channel = null
    longPressSuppressor.dispose()
    webView.setOnTouchListener(null)
    webView.removeJavascriptInterface("YouTubeAndroid")
    webView.stopLoading()
    webView.webViewClient = WebViewClient()
    webView.webChromeClient = WebChromeClient()
    rootView.removeView(webView)
    if (!rendererGone) webView.loadUrl("about:blank")
    webView.destroy()
  }

  private inner class Bridge {
    @JavascriptInterface fun postMessage(json: String) {
      webView.post { handleMessage(json) }
    }
  }

  private inner class PlayerWebViewClient : WebViewClient() {
    override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
      event("loading", "value" to 0.0)
    }

    override fun onPageFinished(view: WebView, url: String?) {
      event("loading", "value" to 1.0)
      event("pageFinished", "title" to view.title)
    }

    override fun onReceivedError(
      view: WebView,
      request: WebResourceRequest,
      error: WebResourceError,
    ) {
      if (request.isForMainFrame) {
        prepared = false
        ready = false
        hideLoadingCover()
        event("loadError", "message" to error.description.toString())
      }
    }

    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
      rendererGone = true
      prepared = false
      ready = false
      hideLoadingCover()
      event("rendererGone", "message" to "The Android WebView renderer exited")
      return true
    }

  }

  private inner class PlayerChromeClient : WebChromeClient() {
    override fun onProgressChanged(view: WebView, newProgress: Int) {
      event("loading", "value" to newProgress.coerceIn(0, 100) / 100.0)
    }

    override fun onShowCustomView(
      view: View,
      callback: CustomViewCallback,
    ) {
      val activity = currentHostActivity()
      if (activity == null || customView != null) {
        callback.onCustomViewHidden()
        return
      }
      customView = view
      customViewCallback = callback
      view.setBackgroundColor(Color.BLACK)
      val content = activity.findViewById<ViewGroup>(android.R.id.content)
      content.addView(view, ViewGroup.LayoutParams(-1, -1))
      activity.window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
      event("fullscreen", "value" to true)
    }

    override fun onHideCustomView() {
      hideCustomView()
    }
  }

  private fun hideCustomView(): Boolean {
    val view = customView ?: return false
    (view.parent as? ViewGroup)?.removeView(view)
    customView = null
    customViewCallback?.onCustomViewHidden()
    customViewCallback = null
    currentHostActivity()?.window?.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
    event("fullscreen", "value" to false)
    return true
  }

  private fun openInYouTube(): Boolean {
    val id = videoId ?: return false
    val intent = Intent(
      Intent.ACTION_VIEW,
      Uri.parse("https://www.youtube.com/watch?v=$id"),
    )
    val activity = currentHostActivity()
    return try {
      if (activity != null) {
        activity.startActivity(intent)
      } else {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        webView.context.startActivity(intent)
      }
      true
    } catch (error: ActivityNotFoundException) {
      Log.w(TAG, "Unable to open the current video in YouTube", error)
      false
    }
  }

  private fun isValidVideoId(value: String?): Boolean =
    value != null && videoIdPattern.matcher(value).matches()

  private fun validStartSeconds(value: Double?): Double =
    value?.takeIf { it.isFinite() && it >= 0 } ?: 0.0

  private fun htmlEscape(value: String): String = value
    .replace("&", "&amp;")
    .replace("\"", "&quot;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")

  private fun currentHostActivity(): Activity? = hostActivity.get()
}

private class LongPressSuppressor(context: Context) : View.OnTouchListener {
  companion object {
    private const val CANCELLATION_LEAD_TIME_MS = 100
  }

  private val handler = Handler(Looper.getMainLooper())
  private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop.toFloat()
  private val cancellationDelay =
    (ViewConfiguration.getLongPressTimeout() - CANCELLATION_LEAD_TIME_MS)
      .coerceAtLeast(0)
      .toLong()
  private var target: View? = null
  private var downTime = 0L
  private var downX = 0f
  private var downY = 0f
  private var suppressing = false

  private val cancelTouch = Runnable {
    val view = target ?: return@Runnable
    suppressing = true
    val event = MotionEvent.obtain(
      downTime,
      SystemClock.uptimeMillis(),
      MotionEvent.ACTION_CANCEL,
      downX,
      downY,
      0,
    )
    view.onTouchEvent(event)
    event.recycle()
  }

  override fun onTouch(view: View, event: MotionEvent): Boolean {
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> {
        reset()
        target = view
        downTime = event.downTime
        downX = event.x
        downY = event.y
        handler.postDelayed(cancelTouch, cancellationDelay)
      }
      MotionEvent.ACTION_POINTER_DOWN -> cancelPending()
      MotionEvent.ACTION_MOVE -> {
        if (suppressing) return true
        if (abs(event.x - downX) > touchSlop || abs(event.y - downY) > touchSlop) {
          cancelPending()
        }
      }
      MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
        val consume = suppressing
        reset()
        return consume
      }
    }
    return suppressing
  }

  fun dispose() {
    reset()
  }

  private fun cancelPending() {
    handler.removeCallbacks(cancelTouch)
    target = null
  }

  private fun reset() {
    cancelPending()
    suppressing = false
  }
}
