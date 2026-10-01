import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import qs.Commons
import qs.Ui

import "../../shared"
import ".."

WidgetCard {
  id: videoWidgetRoot

  widgetId: "video_player"
  title: "Video Player"
  icon: ""
  showHeader: false

  width: 420
  height: 260
  minWidth: 240
  minHeight: 160
  maxWidth: Math.min(1200, screenWidth - 40)
  maxHeight: Math.min(900, screenHeight - 80)
  resizable: true

  // ---------------------------------------------------------------------------
  // 🎬 Selected Video, Loop & Volume State
  // ---------------------------------------------------------------------------
  property string videoPath: ""
  property real volume: 0.8
  property bool muted: false
  property bool loopVideo: true
  property bool videoFailed: false
  property bool browsing: false
  property bool barPressed: false
  property bool seeking: false
  property real seekPreviewFrac: 0
  property bool hideWhenPaused: false
  // ▶ Autoplay on Start (right-click toggle): whether the saved video starts
  // playing when the widget loads (shell start, login). Off: it loads paused
  // on its first frame. A video you pick or paste always plays straight away.
  property bool autoPlayOnStart: true
  property bool startupDone: false      // the first video load has happened
  property bool startupRefetch: false   // a YouTube re-download made at start-up
  readonly property bool barRevealed: bottomHoverHandler.hovered || videoWidgetRoot.barPressed || (rootRef && rootRef.layoutEditMode === true)

  // ---------------------------------------------------------------------------
  // 👻 Hide While Paused (right-click toggle): the whole card -- frame,
  // shadow and all -- fades out while a loaded video isn't playing, and fades
  // back in while the cursor is over its reveal zone. Opacity (not visible) so the
  // hover handler keeps receiving events on the invisible card.
  // ---------------------------------------------------------------------------
  //
  // Reappear zone (right-click, while Hide While Paused is on): hovering the
  // whole panel, just its centre, or just the bottom control-bar strip brings
  // it back. Once back, it stays while the cursor is anywhere on the panel,
  // so reaching for a button doesn't make it vanish again.
  property string revealZone: "panel"   // panel | center | bar
  readonly property bool zoneHovered: revealZone === "center" ? centerHoverHandler.hovered
    : (revealZone === "bar" ? bottomHoverHandler.hovered : panelHoverHandler.hovered)
  property bool revealLatched: false
  onZoneHoveredChanged: if (zoneHovered) revealLatched = true
  Connections {
    target: panelHoverHandler
    function onHoveredChanged() { if (!panelHoverHandler.hovered) videoWidgetRoot.revealLatched = false }
  }

  function setRevealZone(z) {
    videoWidgetRoot.revealZone = z
    videoWidgetRoot.saveSetting("revealZone", z)
  }

  readonly property bool pausedHidden: videoWidgetRoot.hideWhenPaused
    && player.hasVideo
    && player.playbackState !== MediaPlayer.PlayingState
    && !videoWidgetRoot.zoneHovered
    && !(videoWidgetRoot.revealLatched && panelHoverHandler.hovered)
    && !videoWidgetRoot.contextMenuOpen
    && !videoWidgetRoot.isFullscreen
    && !videoWidgetRoot.barPressed
    && !(rootRef && rootRef.layoutEditMode === true)

  opacity: videoWidgetRoot.pausedHidden ? 0.0 : 1.0
  Behavior on opacity {
    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
  }

  function toggleHideWhenPaused() {
    videoWidgetRoot.hideWhenPaused = !videoWidgetRoot.hideWhenPaused
    videoWidgetRoot.saveSetting("hideWhenPaused", videoWidgetRoot.hideWhenPaused)
  }

  // ---------------------------------------------------------------------------
  // ⛶ Double-Click Fullscreen (Esc or double-click again to collapse)
  // ---------------------------------------------------------------------------
  property bool isFullscreen: false
  property real fsSavedX: 0
  property real fsSavedY: 0
  property real fsSavedWidth: 0
  property real fsSavedHeight: 0

  function enterFullscreen() {
    if (videoWidgetRoot.isFullscreen || videoWidgetRoot.videoUrl.length === 0) return
    var t = videoWidgetRoot.targetItem
    videoWidgetRoot.fsSavedX = t.x
    videoWidgetRoot.fsSavedY = t.y
    videoWidgetRoot.fsSavedWidth = videoWidgetRoot.width
    videoWidgetRoot.fsSavedHeight = videoWidgetRoot.height
    videoWidgetRoot.isFullscreen = true
    videoWidgetRoot.customGripDragging = true
    t.z = 1000
    if (rootRef) rootRef.keyboardFocusRequested = true
    fullscreenAnim.toX = 0
    fullscreenAnim.toY = 0
    fullscreenAnim.toWidth = videoWidgetRoot.screenWidth
    fullscreenAnim.toHeight = videoWidgetRoot.screenHeight
    fullscreenAnim.restart()
  }

  function exitFullscreen() {
    if (!videoWidgetRoot.isFullscreen) return
    videoWidgetRoot.isFullscreen = false
    videoWidgetRoot.customGripDragging = false
    if (rootRef && rootRef.keyboardFocusRequested) rootRef.keyboardFocusRequested = false
    fullscreenAnim.toX = videoWidgetRoot.fsSavedX
    fullscreenAnim.toY = videoWidgetRoot.fsSavedY
    fullscreenAnim.toWidth = videoWidgetRoot.fsSavedWidth
    fullscreenAnim.toHeight = videoWidgetRoot.fsSavedHeight
    fullscreenAnim.restart()
  }

  function toggleFullscreen() {
    if (videoWidgetRoot.isFullscreen) videoWidgetRoot.exitFullscreen()
    else videoWidgetRoot.enterFullscreen()
  }

  // The plugin's own root already promotes the whole desktop-widgets layer to
  // WlrLayer.Overlay + on-demand keyboard focus, and wires a real Escape
  // Shortcut to clear this same flag, whenever `keyboardFocusRequested` is
  // set (see DesktopWidgets.qml) — reusing it gets us real fullscreen
  // layering and Esc-to-close for free instead of reinventing either.
  Connections {
    target: rootRef || null
    function onKeyboardFocusRequestedChanged() {
      if (videoWidgetRoot.isFullscreen && rootRef && !rootRef.keyboardFocusRequested) {
        videoWidgetRoot.exitFullscreen()
      }
    }
  }

  ParallelAnimation {
    id: fullscreenAnim
    property real toX: 0
    property real toY: 0
    property real toWidth: 0
    property real toHeight: 0
    NumberAnimation { target: videoWidgetRoot.targetItem; property: "x"; to: fullscreenAnim.toX; duration: 260; easing.type: Easing.OutCubic }
    NumberAnimation { target: videoWidgetRoot.targetItem; property: "y"; to: fullscreenAnim.toY; duration: 260; easing.type: Easing.OutCubic }
    NumberAnimation { target: videoWidgetRoot; property: "width"; to: fullscreenAnim.toWidth; duration: 260; easing.type: Easing.OutCubic }
    NumberAnimation { target: videoWidgetRoot; property: "height"; to: fullscreenAnim.toHeight; duration: 260; easing.type: Easing.OutCubic }
    onStopped: if (!videoWidgetRoot.isFullscreen) videoWidgetRoot.targetItem.z = 0
  }

  function formatTime(ms) {
    if (!ms || ms <= 0) return "0:00"
    var totalSec = Math.floor(ms / 1000)
    var h = Math.floor(totalSec / 3600)
    var m = Math.floor((totalSec % 3600) / 60)
    var s = totalSec % 60
    var mm = (h > 0 && m < 10) ? ("0" + m) : String(m)
    var ss = s < 10 ? ("0" + s) : String(s)
    return h > 0 ? (h + ":" + mm + ":" + ss) : (m + ":" + ss)
  }

  readonly property string videoUrl: {
    if (videoWidgetRoot.videoPath.length === 0) return ""
    var encoded = String(videoWidgetRoot.videoPath).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded
  }

  readonly property string videoFileName: {
    if (videoWidgetRoot.videoPath.length === 0) return ""
    if (videoWidgetRoot.videoTitle.length > 0) return videoWidgetRoot.videoTitle
    var parts = videoWidgetRoot.videoPath.split("/")
    return parts[parts.length - 1]
  }

  // ---------------------------------------------------------------------------
  // ▶️ YouTube URL (right-click menu). get-youtube.sh downloads via yt-dlp
  // into ~/.cache/dagyr.desktop-widgets/youtube/ and hands back a local file
  // -- QtMultimedia can't mux YouTube's split video/audio streams and direct
  // stream URLs expire, so a cached file keeps HD + looping working.
  // ---------------------------------------------------------------------------
  property string videoTitle: ""     // set for YouTube videos, "" for local files
  property string youtubeUrl: ""     // source URL of the current YouTube video
  property string ytUrlDraft: ""
  property bool ytLoading: false
  property int ytProgress: 0
  property string ytLoadingTitle: ""
  property string ytError: ""
  property bool menuHoldsKeyboard: false

  readonly property string youtubeScriptPath: {
    var u = Qt.resolvedUrl("get-youtube.sh").toString()
    return decodeURIComponent(u.replace(/^file:\/\//, ""))
  }

  // atStart: the start-up re-download of a cached video that went missing
  // (Autoplay on Start decides whether it plays), not a URL you just pasted.
  function loadYoutubeUrl(url, atStart) {
    url = String(url || "").trim()
    if (url.length === 0 || ytProc.running) return
    ytProc.atStart = atStart === true
    videoWidgetRoot.ytLoading = true
    videoWidgetRoot.ytProgress = 0
    videoWidgetRoot.ytLoadingTitle = ""
    videoWidgetRoot.ytError = ""
    ytProc.pendingUrl = url
    ytProc.command = [videoWidgetRoot.youtubeScriptPath, url]
    ytProc.running = true
  }

  Process {
    id: ytProc
    property string pendingUrl: ""
    property bool atStart: false
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line).trim()
        if (!str) return
        try {
          var data = JSON.parse(str)
          if (data.status === "progress") {
            videoWidgetRoot.ytProgress = data.percent || 0
            if (data.title) videoWidgetRoot.ytLoadingTitle = data.title
          } else if (data.status === "ok" && data.path) {
            videoWidgetRoot.videoTitle = data.title || ""
            videoWidgetRoot.youtubeUrl = ytProc.pendingUrl
            videoWidgetRoot.startupRefetch = ytProc.atStart
            videoWidgetRoot.videoPath = data.path
            videoWidgetRoot.videoFailed = false
            videoWidgetRoot.saveSettings({
              videoPath: data.path,
              videoTitle: videoWidgetRoot.videoTitle,
              youtubeUrl: ytProc.pendingUrl
            })
          } else if (data.status === "error") {
            videoWidgetRoot.ytError = data.message || "Download failed"
          }
        } catch (e) {
          console.warn("[VideoPlayerWidget] YouTube parse error:", e)
        }
      }
    }
    onExited: function(exitCode) {
      videoWidgetRoot.ytLoading = false
    }
  }

  // The URL field lives in the floating menu, which needs the desktop layer
  // to take keyboard focus on demand (same flag hover-hotkeys/fullscreen use).
  function grabMenuKeyboard(input) {
    if (rootRef) rootRef.keyboardFocusRequested = true
    videoWidgetRoot.menuHoldsKeyboard = true
    input.forceActiveFocus()
  }

  onContextMenuOpenChanged: {
    if (videoWidgetRoot.contextMenuOpen) {
      videoWidgetRoot.ytUrlDraft = videoWidgetRoot.youtubeUrl
    } else if (videoWidgetRoot.menuHoldsKeyboard) {
      videoWidgetRoot.menuHoldsKeyboard = false
      videoWidgetRoot.updateKeyboardFocusForHover()
    }
  }

  function applySavedSettings() {
    // before videoPath: setting the path starts the load (and the autoplay
    // decision) straight away
    autoPlayOnStart = getSetting("autoPlayOnStart", true)
    videoPath = getSetting("videoPath", "")
    videoTitle = getSetting("videoTitle", "")
    youtubeUrl = getSetting("youtubeUrl", "")
    volume = getSetting("volume", 0.8)
    muted = getSetting("muted", false)
    loopVideo = getSetting("loopVideo", true)
    hideWhenPaused = getSetting("hideWhenPaused", false)
    revealZone = getSetting("revealZone", "panel")
    // A cached YouTube file can be pruned out of the cache (or the cache
    // cleared); fetch it again rather than showing "couldn't play".
    if (youtubeUrl.length > 0 && videoPath.length > 0 && !ytLoading) ytExistsCheck.running = true
  }

  Process {
    id: ytExistsCheck
    command: ["test", "-f", videoWidgetRoot.videoPath]
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0 && videoWidgetRoot.youtubeUrl.length > 0) videoWidgetRoot.loadYoutubeUrl(videoWidgetRoot.youtubeUrl, true)
    }
  }

  onSettingsLoaded: applySavedSettings()
  onRootRefChanged: applySavedSettings()
  Component.onCompleted: applySavedSettings()

  onVideoUrlChanged: {
    videoWidgetRoot.videoFailed = false
    videoWidgetRoot.updateKeyboardFocusForHover()
  }

  function togglePlayPause() {
    if (!player.hasVideo) return
    if (player.playbackState === MediaPlayer.PlayingState) player.pause()
    else player.play()
  }

  function toggleMute() {
    videoWidgetRoot.muted = !videoWidgetRoot.muted
    videoWidgetRoot.saveSetting("muted", videoWidgetRoot.muted)
  }

  function setVolume(v) {
    var clamped = Math.max(0, Math.min(1, v))
    videoWidgetRoot.volume = clamped
    videoWidgetRoot.saveSetting("volume", clamped)
    if (clamped > 0 && videoWidgetRoot.muted) {
      videoWidgetRoot.muted = false
      videoWidgetRoot.saveSetting("muted", false)
    }
  }

  function toggleAutoPlayOnStart() {
    videoWidgetRoot.autoPlayOnStart = !videoWidgetRoot.autoPlayOnStart
    videoWidgetRoot.saveSetting("autoPlayOnStart", videoWidgetRoot.autoPlayOnStart)
  }

  function toggleLoop() {
    videoWidgetRoot.loopVideo = !videoWidgetRoot.loopVideo
    videoWidgetRoot.saveSetting("loopVideo", videoWidgetRoot.loopVideo)
  }

  readonly property string videoScriptPath: {
    var u = Qt.resolvedUrl("get-video.sh").toString()
    return decodeURIComponent(u.replace(/^file:\/\//, ""))
  }

  function browseForVideo() {
    if (browseProc.running) return
    videoWidgetRoot.browsing = true
    browseProc.running = true
  }

  Process {
    id: browseProc
    command: [videoWidgetRoot.videoScriptPath]
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line).trim()
        if (!str) return
        try {
          var data = JSON.parse(str)
          if (data.status === "ok" && data.path) {
            videoWidgetRoot.videoTitle = ""
            videoWidgetRoot.youtubeUrl = ""
            videoWidgetRoot.videoPath = data.path
            videoWidgetRoot.videoFailed = false
            videoWidgetRoot.saveSettings({ videoPath: data.path, videoTitle: "", youtubeUrl: "" })
          }
        } catch (e) {
          console.warn("[VideoPlayerWidget] Pick parse error:", e)
        }
      }
    }
    onExited: function(exitCode) {
      videoWidgetRoot.browsing = false
    }
  }

  MediaPlayer {
    id: player
    source: videoWidgetRoot.videoUrl
    videoOutput: videoOutputItem
    audioOutput: audioOut
    // Autoplay from here, not onVideoUrlChanged: that handler runs before
    // this `source` binding re-evaluates, so play() there hit an empty source.
    // The first load (the saved video, at start-up) follows Autoplay on
    // Start; pause() still loads it and shows its first frame.
    onSourceChanged: {
      if (String(source).length === 0) return
      var atStart = !videoWidgetRoot.startupDone || videoWidgetRoot.startupRefetch
      videoWidgetRoot.startupDone = true
      videoWidgetRoot.startupRefetch = false
      if (atStart && !videoWidgetRoot.autoPlayOnStart) pause()
      else play()
    }
    loops: videoWidgetRoot.loopVideo ? MediaPlayer.Infinite : 1
    onErrorOccurred: function(error, errorString) {
      videoWidgetRoot.videoFailed = true
      console.warn("[VideoPlayerWidget] cannot play", videoWidgetRoot.videoPath, errorString)
    }
  }

  AudioOutput {
    id: audioOut
    volume: videoWidgetRoot.muted ? 0 : videoWidgetRoot.volume
  }

  customMenuContent: Component {
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)

      Text {
        text: "VIDEO"
        font.family: Style.font.family
        font.pixelSize: 9
        font.weight: Font.Bold
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.45)
        Layout.leftMargin: 4
        Layout.topMargin: 2
      }

      // Browse
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: browseMenuMouse.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: ""
            font.family: Style.font.family
            font.pixelSize: 11
            color: Color.accent
          }

          Text {
            Layout.fillWidth: true
            text: "Browse for Video..."
            font.family: Style.font.family
            font.pixelSize: 11
            color: Color.foreground
          }
        }

        MouseArea {
          id: browseMenuMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            videoWidgetRoot.browseForVideo()
            videoWidgetRoot.contextMenuOpen = false
          }
        }
      }

      // YouTube URL
      RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: Style.space(6)

        Rectangle {
          Layout.fillWidth: true
          implicitHeight: 28
          radius: 6
          color: Qt.rgba(1, 1, 1, 0.07)
          border.color: ytUrlInput.activeFocus ? Color.accent : Qt.rgba(1, 1, 1, 0.12)
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(6)

            Text {
              text: "\uf16a"
              font.family: Style.font.family
              font.pixelSize: 11
              color: ytUrlInput.activeFocus ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.5)
            }

            TextInput {
              id: ytUrlInput
              Layout.fillWidth: true
              font.family: Style.font.family
              font.pixelSize: 10
              color: Color.foreground
              selectionColor: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4)
              clip: true
              enabled: !videoWidgetRoot.ytLoading
              text: videoWidgetRoot.ytUrlDraft
              onTextEdited: videoWidgetRoot.ytUrlDraft = text
              onAccepted: {
                videoWidgetRoot.loadYoutubeUrl(text)
                videoWidgetRoot.contextMenuOpen = false
              }

              Text {
                anchors.fill: parent
                visible: !ytUrlInput.text && !ytUrlInput.activeFocus
                text: "Paste a YouTube URL..."
                font.family: Style.font.family
                font.pixelSize: 10
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.35)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onPressed: function(mouse) {
                  videoWidgetRoot.grabMenuKeyboard(ytUrlInput)
                  mouse.accepted = false
                }
              }
            }
          }
        }

        Rectangle {
          implicitWidth: ytPlayText.implicitWidth + Style.space(16)
          implicitHeight: 28
          radius: 6
          readonly property bool canPlay: videoWidgetRoot.ytUrlDraft.trim().length > 0 && !videoWidgetRoot.ytLoading
          opacity: canPlay ? 1 : 0.45
          color: ytPlayMouse.containsMouse && canPlay ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)

          Text {
            id: ytPlayText
            anchors.centerIn: parent
            text: videoWidgetRoot.ytLoading ? (videoWidgetRoot.ytProgress + "%") : "Play"
            font.family: Style.font.family
            font.pixelSize: 10
            font.weight: Font.Bold
            color: ytPlayMouse.containsMouse && parent.canPlay ? Color.background : Color.accent
          }

          MouseArea {
            id: ytPlayMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: parent.canPlay ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
              if (!parent.canPlay) return
              videoWidgetRoot.loadYoutubeUrl(videoWidgetRoot.ytUrlDraft)
              videoWidgetRoot.contextMenuOpen = false
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        visible: videoWidgetRoot.ytError.length > 0
        text: videoWidgetRoot.ytError
        font.family: Style.font.family
        font.pixelSize: 9
        wrapMode: Text.WordWrap
        color: Color.urgent
      }

      // Loop Toggle
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: loopMouse.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: ""
            font.family: Style.font.family
            font.pixelSize: 11
            color: videoWidgetRoot.loopVideo ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.5)
          }

          Text {
            Layout.fillWidth: true
            text: "Loop Video"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Color.foreground
          }

          Text {
            text: videoWidgetRoot.loopVideo ? "" : ""
            font.family: Style.font.family
            font.pixelSize: 12
            color: videoWidgetRoot.loopVideo ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.4)
          }
        }

        MouseArea {
          id: loopMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // Menu stays open: closing it here would also re-hide a card that
          // Hide While Paused only revealed because the menu was open.
          onClicked: videoWidgetRoot.toggleLoop()
        }
      }

      // Autoplay on Start Toggle
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: autoPlayMouse.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf04b"
            font.family: Style.font.family
            font.pixelSize: 11
            color: videoWidgetRoot.autoPlayOnStart ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.5)
          }

          Text {
            Layout.fillWidth: true
            text: "Autoplay on Start"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Color.foreground
          }

          Text {
            text: videoWidgetRoot.autoPlayOnStart ? "\uf14a" : "\uf0c8"
            font.family: Style.font.family
            font.pixelSize: 12
            color: videoWidgetRoot.autoPlayOnStart ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.4)
          }
        }

        MouseArea {
          id: autoPlayMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: videoWidgetRoot.toggleAutoPlayOnStart()
        }
      }

      // Hide While Paused Toggle
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: hidePausedMouse.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf070"
            font.family: Style.font.family
            font.pixelSize: 11
            color: videoWidgetRoot.hideWhenPaused ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.5)
          }

          Text {
            Layout.fillWidth: true
            text: "Hide While Paused"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Color.foreground
          }

          Text {
            text: videoWidgetRoot.hideWhenPaused ? "" : ""
            font.family: Style.font.family
            font.pixelSize: 12
            color: videoWidgetRoot.hideWhenPaused ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.4)
          }
        }

        MouseArea {
          id: hidePausedMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // Menu stays open so the reappear-zone choice below can be set.
          onClicked: videoWidgetRoot.toggleHideWhenPaused()
        }
      }

      // Where the hidden card listens for the cursor to come back.
      RowLayout {
        visible: videoWidgetRoot.hideWhenPaused
        Layout.fillWidth: true
        Layout.leftMargin: Style.space(8)
        Layout.rightMargin: 4
        spacing: Style.space(4)

        Text {
          text: "Reappear on"
          font.family: Style.font.family
          font.pixelSize: 10
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.6)
        }

        Repeater {
          model: [{ id: "panel", label: "Panel" }, { id: "center", label: "Center" }, { id: "bar", label: "Controls" }]

          Rectangle {
            required property var modelData
            readonly property bool isActive: videoWidgetRoot.revealZone === modelData.id
            Layout.fillWidth: true
            implicitHeight: 24
            radius: 6
            color: isActive ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3) : (zoneMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05))
            border.color: isActive ? Color.accent : "transparent"
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: modelData.label
              font.family: Style.font.family
              font.pixelSize: 10
              font.weight: parent.isActive ? Font.Bold : Font.Normal
              color: parent.isActive ? Color.accent : Color.foreground
            }

            MouseArea {
              id: zoneMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: videoWidgetRoot.setRevealZone(modelData.id)
            }
          }
        }
      }

      Text {
        text: "VOLUME"
        font.family: Style.font.family
        font.pixelSize: 9
        font.weight: Font.Bold
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.45)
        Layout.leftMargin: 4
        Layout.topMargin: 4
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Layout.leftMargin: 4
        Layout.rightMargin: 4

        Text {
          text: videoWidgetRoot.muted ? "" : ""
          font.family: Style.font.family
          font.pixelSize: 12
          color: videoWidgetRoot.muted ? Color.urgent : Color.accent

          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: videoWidgetRoot.toggleMute()
          }
        }

        Rectangle {
          id: volumeMenuTrack
          Layout.fillWidth: true
          height: 8
          radius: 4
          color: Qt.rgba(1, 1, 1, 0.12)

          Rectangle {
            height: parent.height
            width: Math.max(8, Math.min(parent.width, (videoWidgetRoot.muted ? 0 : videoWidgetRoot.volume) * parent.width))
            radius: 4
            color: Color.accent
          }

          Rectangle {
            x: Math.max(0, Math.min(parent.width - width, (videoWidgetRoot.muted ? 0 : videoWidgetRoot.volume) * (parent.width - width)))
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: Color.accent
            border.color: "#ffffff"
            border.width: 2
          }

          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            cursorShape: Qt.PointingHandCursor
            function setVal(mx) {
              var frac = Math.max(0.0, Math.min(1.0, (mx - 8) / volumeMenuTrack.width))
              videoWidgetRoot.setVolume(frac)
            }
            onPressed: function(mouse) { setVal(mouse.x) }
            onPositionChanged: function(mouse) { if (pressed) setVal(mouse.x) }
            onWheel: function(wheel) {
              videoWidgetRoot.setVolume(videoWidgetRoot.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
              wheel.accepted = true
            }
          }
        }

        Text {
          text: Math.round((videoWidgetRoot.muted ? 0 : videoWidgetRoot.volume) * 100) + "%"
          font.family: Style.font.family
          font.pixelSize: 11
          font.weight: Font.Bold
          color: Color.accent
          Layout.preferredWidth: 34
        }
      }
      // Update the whole custom widget suite from its repo.
      SuiteUpdateItem {}
    }
  }

  // ---------------------------------------------------------------------------
  // ⌨️ Space/M Hotkeys While Hovering The Panel
  // ---------------------------------------------------------------------------
  // Mirrors the fullscreen flow's use of rootRef.keyboardFocusRequested to
  // promote the shared desktop-widgets layer to on-demand keyboard focus
  // (see enterFullscreen/exitFullscreen above) -- WlrKeyboardFocus.OnDemand
  // means this doesn't yank focus from another app just by hovering, only
  // makes the surface eligible to receive it.
  function updateKeyboardFocusForHover() {
    // The YouTube URL field in the right-click menu owns focus while typing.
    if (videoWidgetRoot.menuHoldsKeyboard) return
    if (panelHoverHandler.hovered && player.hasVideo) {
      if (rootRef) rootRef.keyboardFocusRequested = true
    } else if (!videoWidgetRoot.isFullscreen) {
      if (rootRef && rootRef.keyboardFocusRequested) rootRef.keyboardFocusRequested = false
    }
  }

  Shortcut {
    sequence: "Space"
    enabled: panelHoverHandler.hovered && player.hasVideo && !videoWidgetRoot.contextMenuOpen
    onActivated: videoWidgetRoot.togglePlayPause()
  }

  Shortcut {
    sequence: "M"
    enabled: panelHoverHandler.hovered && player.hasVideo && !videoWidgetRoot.contextMenuOpen
    onActivated: videoWidgetRoot.toggleMute()
  }

  // ---------------------------------------------------------------------------
  // 🎥 Video Surface
  // ---------------------------------------------------------------------------
  // Transparent (not black) so WidgetCard's own themed surface -- bar
  // background colour at the user's bg_opacity, border and corner_radius --
  // shows through like every other widget; inset by the card's 1px border
  // and radius-matched so the video clips inside it. Black only in
  // fullscreen, where there's no card chrome to show.
  readonly property real cardRadius: (rootRef && rootRef.appearance && rootRef.appearance.corner_radius !== undefined) ? rootRef.appearance.corner_radius : 18

  ClippingRectangle {
    anchors.fill: parent
    anchors.margins: videoWidgetRoot.isFullscreen ? 0 : 1
    radius: videoWidgetRoot.isFullscreen ? 0 : Math.max(0, videoWidgetRoot.cardRadius - 1)
    color: videoWidgetRoot.isFullscreen ? "black" : "transparent"

    Behavior on radius {
      NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }

    HoverHandler {
      id: panelHoverHandler
      onHoveredChanged: videoWidgetRoot.updateKeyboardFocusForHover()
    }

    // Centre reveal zone (see revealZone): the middle ~45% of the panel.
    Item {
      anchors.centerIn: parent
      width: parent.width * 0.45
      height: parent.height * 0.45
      HoverHandler { id: centerHoverHandler }
    }

    VideoOutput {
      id: videoOutputItem
      anchors.fill: parent
      fillMode: VideoOutput.PreserveAspectFit
      visible: videoWidgetRoot.videoUrl.length > 0 && !videoWidgetRoot.videoFailed
    }

    // Double-click the video surface to expand/collapse fullscreen. Sits
    // below the top chrome and bottom bar (declared before them), so their
    // own buttons still get first claim on clicks within their bounds.
    MouseArea {
      anchors.fill: parent
      enabled: videoWidgetRoot.videoUrl.length > 0 && !videoWidgetRoot.videoFailed
      acceptedButtons: Qt.LeftButton
      onDoubleClicked: videoWidgetRoot.toggleFullscreen()
    }

    // Empty / Error State
    ColumnLayout {
      anchors.centerIn: parent
      spacing: Style.space(10)
      visible: videoWidgetRoot.videoUrl.length === 0 || videoWidgetRoot.videoFailed
      width: parent.width - Style.space(40)

      Text {
        Layout.alignment: Qt.AlignHCenter
        text: videoWidgetRoot.videoFailed ? "" : ""
        font.family: Style.font.family
        font.pixelSize: 28
        color: videoWidgetRoot.videoFailed ? Color.urgent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.5)
      }

      Text {
        Layout.alignment: Qt.AlignHCenter
        text: videoWidgetRoot.ytLoading
          ? ("Downloading from YouTube... " + videoWidgetRoot.ytProgress + "%" + (videoWidgetRoot.ytLoadingTitle ? ("\n" + videoWidgetRoot.ytLoadingTitle) : ""))
          : (videoWidgetRoot.ytError.length > 0 && videoWidgetRoot.videoUrl.length === 0 ? videoWidgetRoot.ytError
          : (videoWidgetRoot.videoFailed ? "Couldn't play this video" : (videoWidgetRoot.browsing ? "Opening file picker..." : "No video selected")))
        font.family: Style.font.family
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.7)
      }

      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: browseBtnRow.implicitWidth + Style.space(24)
        implicitHeight: 32
        radius: 16
        color: browseBtnMouse.containsMouse ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.85)

        RowLayout {
          id: browseBtnRow
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            text: ""
            font.family: Style.font.family
            font.pixelSize: 11
            color: Color.background
          }
          Text {
            text: "Browse for Video..."
            font.family: Style.font.family
            font.pixelSize: 11
            font.weight: Font.Bold
            color: Color.background
          }
        }

        visible: !videoWidgetRoot.ytLoading

        MouseArea {
          id: browseBtnMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: videoWidgetRoot.browseForVideo()
        }
      }
    }

    // YouTube download progress while another video keeps playing.
    Rectangle {
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.topMargin: Style.space(8)
      visible: videoWidgetRoot.ytLoading && videoWidgetRoot.videoUrl.length > 0 && !videoWidgetRoot.videoFailed
      z: 6
      implicitWidth: Math.min(parent.width - Style.space(16), ytPillText.implicitWidth + Style.space(20))
      implicitHeight: 24
      radius: 12
      color: Qt.rgba(0, 0, 0, 0.6)

      Text {
        id: ytPillText
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        text: "\uf16a  " + videoWidgetRoot.ytProgress + "%" + (videoWidgetRoot.ytLoadingTitle ? ("  " + videoWidgetRoot.ytLoadingTitle) : "")
        font.family: Style.font.family
        font.pixelSize: 10
        color: "#ffffff"
        elide: Text.ElideRight
      }
    }

    // Top Chrome (title + move grip + close, edit mode only)
    RowLayout {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Style.space(8)
      visible: rootRef && rootRef.layoutEditMode
      spacing: Style.space(8)
      z: 5

      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 24
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.55)

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: videoWidgetRoot.videoFileName.length > 0 ? videoWidgetRoot.videoFileName : "Video Player"
          font.family: Style.font.family
          font.pixelSize: 11
          font.weight: Font.Bold
          color: "#ffffff"
          elide: Text.ElideRight
        }
      }

      Rectangle {
        width: 24
        height: 24
        radius: 12
        color: gripMouse2.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35) : Qt.rgba(0, 0, 0, 0.55)
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.5)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: ""
          font.family: Style.font.family
          font.pixelSize: 10
          color: Color.accent
        }

        MouseArea {
          id: gripMouse2
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.SizeAllCursor
          drag.target: videoWidgetRoot.targetItem
          drag.axis: Drag.XAndYAxis
          drag.minimumX: 10
          drag.maximumX: Math.max(10, videoWidgetRoot.screenWidth - videoWidgetRoot.width - 10)
          drag.minimumY: 10
          drag.maximumY: Math.max(10, videoWidgetRoot.screenHeight - videoWidgetRoot.height - 10)

          onPressed: videoWidgetRoot.customGripDragging = true
          onReleased: function() {
            videoWidgetRoot.customGripDragging = false
            var maxX = Math.max(10, videoWidgetRoot.screenWidth - videoWidgetRoot.width - 10)
            var maxY = Math.max(10, videoWidgetRoot.screenHeight - videoWidgetRoot.height - 10)
            var snappedX = Math.round(videoWidgetRoot.targetItem.x / 20) * 20
            var snappedY = Math.round(videoWidgetRoot.targetItem.y / 20) * 20
            snappedX = Math.max(10, Math.min(maxX, snappedX))
            snappedY = Math.max(10, Math.min(maxY, snappedY))
            videoWidgetRoot.targetItem.x = snappedX
            videoWidgetRoot.targetItem.y = snappedY
            if (rootRef && rootRef.saveWidgetPos) {
              rootRef.saveWidgetPos(videoWidgetRoot.widgetId, snappedX, snappedY, videoWidgetRoot.snapVal(videoWidgetRoot.width), videoWidgetRoot.snapVal(videoWidgetRoot.height), videoWidgetRoot.monitorName)
            }
          }
          onCanceled: videoWidgetRoot.customGripDragging = false
        }
      }

      Rectangle {
        width: 24
        height: 24
        radius: 12
        color: closeMouse2.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.35) : Qt.rgba(0, 0, 0, 0.55)
        border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.5)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: ""
          font.family: Style.font.family
          font.pixelSize: 10
          color: Color.urgent
        }

        MouseArea {
          id: closeMouse2
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (rootRef && rootRef.toggleWidgetEnabled) {
              rootRef.toggleWidgetEnabled(videoWidgetRoot.widgetId, false, videoWidgetRoot.monitorName)
            }
          }
        }
      }
    }

    // Bottom Control Bar: a hover Item wrapping both the reveal zone (a bit
    // taller than the visible bar, so the reveal doesn't need pixel-perfect
    // aim) AND the bar itself, so the HoverHandler stays "hovered" while the
    // cursor is over any child button/slider — not just the empty backdrop.
    // (A HoverHandler on a sibling item behind the bar loses hover as soon as
    // a child button's own MouseArea claims the point, which made the bar
    // flicker open/closed while moving across the buttons.)
    Item {
      id: bottomBarWrapper
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Math.min(parent.height, barColumn.implicitHeight + Style.space(12) + Style.space(28))
      visible: videoWidgetRoot.videoUrl.length > 0 && !videoWidgetRoot.videoFailed
      z: 4

      HoverHandler {
        id: bottomHoverHandler
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(8)
        visible: opacity > 0
        opacity: videoWidgetRoot.barRevealed ? 1.0 : 0.0

        Behavior on opacity {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        implicitHeight: barColumn.implicitHeight + Style.space(12)
        radius: 14
        color: Qt.rgba(0, 0, 0, 0.55)

        ColumnLayout {
          id: barColumn
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          anchors.topMargin: Style.space(6)
          anchors.bottomMargin: Style.space(6)
          spacing: Style.space(4)

          // Seek / Scrub Bar
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              text: videoWidgetRoot.formatTime(player.position)
              font.family: Style.font.family
              font.pixelSize: 9
              color: Qt.rgba(1, 1, 1, 0.6)
              Layout.preferredWidth: 32
            }

            Rectangle {
              id: seekTrack
              Layout.fillWidth: true
              height: 6
              radius: 3
              color: Qt.rgba(1, 1, 1, 0.25)

              readonly property real frac: player.duration > 0 ? (videoWidgetRoot.seeking ? videoWidgetRoot.seekPreviewFrac : Math.min(1, player.position / player.duration)) : 0

              Rectangle {
                height: parent.height
                width: Math.max(0, Math.min(parent.width, parent.width * seekTrack.frac))
                radius: 3
                color: Color.accent
              }

              Rectangle {
                visible: player.duration > 0
                x: Math.max(0, Math.min(parent.width - width, seekTrack.frac * parent.width - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                width: 11
                height: 11
                radius: 5.5
                color: Color.accent
                border.color: "#ffffff"
                border.width: 1.5
              }

              MouseArea {
                id: seekMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                function updatePreview(mx) {
                  if (player.duration <= 0) return
                  videoWidgetRoot.seekPreviewFrac = Math.max(0.0, Math.min(1.0, mx / seekTrack.width))
                }
                onPressed: function(mouse) {
                  videoWidgetRoot.barPressed = true
                  videoWidgetRoot.seeking = true
                  updatePreview(mouse.x)
                }
                onPositionChanged: function(mouse) { if (pressed) updatePreview(mouse.x) }
                onReleased: function(mouse) {
                  updatePreview(mouse.x)
                  if (player.duration > 0) player.setPosition(Math.round(videoWidgetRoot.seekPreviewFrac * player.duration))
                  videoWidgetRoot.seeking = false
                  videoWidgetRoot.barPressed = false
                }
                onCanceled: {
                  videoWidgetRoot.seeking = false
                  videoWidgetRoot.barPressed = false
                }
                onWheel: function(wheel) {
                  if (player.duration <= 0) return
                  var deltaMs = (wheel.angleDelta.y > 0 ? 1 : -1) * 5000
                  player.setPosition(Math.max(0, Math.min(player.duration, player.position + deltaMs)))
                  wheel.accepted = true
                }
              }
            }

            Text {
              text: videoWidgetRoot.formatTime(player.duration)
              font.family: Style.font.family
              font.pixelSize: 9
              color: Qt.rgba(1, 1, 1, 0.6)
              Layout.preferredWidth: 32
              horizontalAlignment: Text.AlignRight
            }
          }

        RowLayout {
          id: controlsRow
          Layout.fillWidth: true
          spacing: Style.space(10)

          // Play/Pause
          Rectangle {
            width: 26
            height: 26
            radius: 13
            color: playPauseMouse.containsMouse ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.85)

            Text {
              anchors.centerIn: parent
              text: player.playbackState === MediaPlayer.PlayingState ? "" : ""
              font.family: Style.font.family
              font.pixelSize: 11
              color: Color.background
            }

            MouseArea {
              id: playPauseMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: videoWidgetRoot.togglePlayPause()
            }
          }

          // Loop Toggle
          Text {
            text: ""
            font.family: Style.font.family
            font.pixelSize: 13
            color: videoWidgetRoot.loopVideo ? Color.accent : Qt.rgba(1, 1, 1, 0.4)

            MouseArea {
              id: loopBarMouse
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: videoWidgetRoot.toggleLoop()
            }
          }

          // Filename
          Text {
            Layout.fillWidth: true
            text: videoWidgetRoot.videoFileName
            font.family: Style.font.family
            font.pixelSize: 11
            color: "#ffffff"
            elide: Text.ElideRight
          }

          // Mute
          Text {
            text: videoWidgetRoot.muted ? "" : ""
            font.family: Style.font.family
            font.pixelSize: 13
            color: videoWidgetRoot.muted ? Color.urgent : "#ffffff"

            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: videoWidgetRoot.toggleMute()
            }
          }

          // Volume Slider
          Rectangle {
            id: barVolumeTrack
            Layout.preferredWidth: 70
            height: 6
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.25)

            Rectangle {
              height: parent.height
              width: Math.max(6, Math.min(parent.width, (videoWidgetRoot.muted ? 0 : videoWidgetRoot.volume) * parent.width))
              radius: 3
              color: Color.accent
            }

            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              function setVal(mx) {
                var frac = Math.max(0.0, Math.min(1.0, mx / barVolumeTrack.width))
                videoWidgetRoot.setVolume(frac)
              }
              onPressed: function(mouse) { videoWidgetRoot.barPressed = true; setVal(mouse.x) }
              onPositionChanged: function(mouse) { if (pressed) setVal(mouse.x) }
              onReleased: videoWidgetRoot.barPressed = false
              onCanceled: videoWidgetRoot.barPressed = false
              onWheel: function(wheel) {
                videoWidgetRoot.setVolume(videoWidgetRoot.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                wheel.accepted = true
              }
            }
          }

          // Browse
          Text {
            text: ""
            font.family: Style.font.family
            font.pixelSize: 12
            color: browseIconMouse.containsMouse ? Color.accent : "#ffffff"

            MouseArea {
              id: browseIconMouse
              anchors.fill: parent
              hoverEnabled: true
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: videoWidgetRoot.browseForVideo()
            }
          }
        }
        }
      }
    }
  }
}
