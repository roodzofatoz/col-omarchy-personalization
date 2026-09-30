// Notification card. Pure presentational — no service, Notification, or
// ListModel references. The popup container drives lifetime; the history
// panel drives static rendering. Both use the same component.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../NotificationLogic.js" as NotificationLogic

BorderSurface {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  // Nerd Font glyph rendered in the icon slot when no real icon is set.
  // Used by omarchy-notification-send so user-action toasts (`Silenced
  // notifications` etc.) show their bell/lock/etc. glyph without leaking
  // into the summary text.
  property string glyph: ""
  // NotificationUrgency: Low=0, Normal=1, Critical=2 (upstream).
  property int urgency: 1
  property double timestamp: 0
  property int cornerRadius: 0

  // System monospace font injected by the container.
  property string fontFamily: ""

  readonly property bool hovered: hoverTracker.hovered

  // ------------------------------------------------------------------ swipe
  //
  // Dragging a toast to the right throws it away. The offset is applied as a
  // transform rather than by moving x, so it does not fight the anchors the
  // popup column sets on the card.
  property real swipeOffset: 0
  // Past this much travel, letting go dismisses instead of springing back.
  readonly property real dismissDistance: Math.max(Style.space(90), root.width * 0.3)
  // True once a swipe has been committed: the card is flying out and must not
  // spring back or accept another gesture.
  property bool dismissing: false

  signal closeRequested()
  signal cardClicked()
  // Prefer per-notification media/avatar data, then fall back to the app icon.
  // The `check` flag avoids Qt's missing-texture placeholder for unknown names.
  readonly property string smallIconSource: image.length > 0 ? image : iconSource(appIcon)
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool compactGlyph: NotificationLogic.shouldRenderCompactGlyph(glyph, smallIconSource, singleLineToast)
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  readonly property bool summaryStartsWithGlyph: NotificationLogic.summaryStartsWithGlyph(summary)
  readonly property bool singleLineToast: sanitizedBody.length === 0
  readonly property bool collapseRedundantIcon: singleLineToast && !hasGlyph && summaryStartsWithGlyph
  // Live "how long ago this popped up" pill (top-right). Shown for Claude
  // Code toasts, or for any summary carrying a trailing "⟦⟧" marker. The
  // summary marker is stripped from the title.
  readonly property var badgeMatch: summary.match(/^(.*?)\s*⟦[^⟧]*⟧\s*$/)
  readonly property string displaySummary: badgeMatch ? badgeMatch[1] : summary
  // "Prefix [name]" titles (Claude Code hook) render the bracketed part in the
  // terminal monospace font at a smaller size so more of it fits on one line.
  readonly property var titleParts: displaySummary.match(/^([^\[\]]+?)\s*\[(.*)\]\s*$/)
  readonly property string titlePrefix: titleParts ? titleParts[1] : displaySummary
  readonly property string titleTag: titleParts ? titleParts[2] : ""
  readonly property bool hasBadge: (!!badgeMatch || app === "Claude Code") && timestamp > 0
  property double nowMs: Date.now()
  readonly property string badge: NotificationLogic.coarseAge(nowMs - timestamp)
  // Body is one line at rest and grows to full text once the cursor has
  // rested on the card for expandDelay ms; a cursor passing through never
  // expands it. Collapses immediately on leave.
  readonly property int expandDelay: 300
  property bool expanded: false
  onHoveredChanged: {
    if (hovered) expandTimer.restart()
    else { expandTimer.stop(); expanded = false }
  }
  readonly property string sanitizedBody: sanitizeBody(body)
  readonly property string styledBody: sanitizedBody.replace(/\r\n|\r|\n/g, "<br/>")

  readonly property color dimColor: Qt.darker(Color.notifications.text, 1.4)
  readonly property color bodyColor: Qt.darker(Color.notifications.text, 1.15)
  readonly property color accentColor: urgency === 2 ? Color.urgent : (urgency === 0 ? dimColor : Color.notifications.countdown)
  readonly property var cardBorderSpec: Border.surfaceSpec("notifications", "border", Color.notifications.border, Math.max(1, Style.space(2)))

  function sanitizeBody(s) {
    return NotificationLogic.sanitizeBody(s, app, appIcon)
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  implicitWidth: Style.space(380)
  // Add vertical border insets so mainColumn (inset by border on top/left/right)
  // doesn't push content under the bottom edge.
  implicitHeight: mainColumn.implicitHeight + borderTop + borderBottom
  radius: cornerRadius
  color: Color.notifications.background
  borderSpec: cardBorderSpec
  clip: true

  transform: Translate { x: root.swipeOffset }

  // Fade with the swipe so a half-committed drag reads as "on its way out".
  opacity: root.dismissing ? 0
    : (root.swipeOffset > 0 ? Math.max(0.2, 1 - root.swipeOffset / (root.dismissDistance * 2)) : 1)

  // Only animate when the finger is not driving the card: during the drag the
  // card must track the pointer exactly.
  Behavior on swipeOffset {
    enabled: !swipeHandler.active
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Behavior on opacity {
    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
  }

  // Smoothly grow/shrink when the body expands on hover.
  Behavior on implicitHeight {
    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
  }

  HoverHandler {
    id: hoverTracker
    cursorShape: Qt.PointingHandCursor
  }

  // Tap and drag are separate handlers rather than one MouseArea so that a
  // drag never also registers as a click. DragThreshold cancels the tap as
  // soon as the pointer travels far enough to count as a swipe.
  TapHandler {
    enabled: !root.dismissing
    acceptedButtons: Qt.LeftButton
    gesturePolicy: TapHandler.DragThreshold
    onTapped: root.cardClicked()
  }

  TapHandler {
    enabled: !root.dismissing
    acceptedButtons: Qt.RightButton
    gesturePolicy: TapHandler.DragThreshold
    onTapped: root.closeRequested()
  }

  DragHandler {
    id: swipeHandler
    enabled: !root.dismissing
    // Nothing is moved by the handler itself; the offset drives the transform.
    target: null
    xAxis.enabled: true
    yAxis.enabled: false

    // Rightward only: the toast column sits against the right screen edge, so
    // that is the direction that throws the card off-screen.
    onActiveTranslationChanged: {
      if (active) root.swipeOffset = Math.max(0, activeTranslation.x)
    }

    onActiveChanged: {
      if (active || root.dismissing) return
      if (root.swipeOffset >= root.dismissDistance) {
        root.dismissing = true
        // Let it fly the rest of the way out before the row is removed.
        root.swipeOffset = root.width + Style.space(40)
        dismissTimer.start()
      } else {
        root.swipeOffset = 0
      }
    }
  }

  Timer {
    id: expandTimer
    interval: root.expandDelay
    onTriggered: if (root.hovered) root.expanded = true
  }

  Timer {
    id: dismissTimer
    interval: 180
    onTriggered: root.closeRequested()
  }

  // Keep the age pill current. 1s while under a minute, then coarser.
  Timer {
    running: root.hasBadge && root.visible
    repeat: true
    interval: (root.nowMs - root.timestamp) < 60000 ? 1000 : 15000
    onTriggered: root.nowMs = Date.now()
  }

  ColumnLayout {
    id: mainColumn
    // Inset by the card border so the content doesn't paint over the card's
    // outer border.
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.borderTop
    anchors.leftMargin: root.borderLeft
    anchors.rightMargin: root.borderRight
    spacing: 0

    // Text content.
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: root.singleLineToast ? Style.space(7) : Style.space(10)
      Layout.bottomMargin: root.singleLineToast ? Style.space(7) : Style.space(10)
      spacing: root.collapseRedundantIcon ? 0 : (root.compactGlyph ? Style.space(8) : Style.space(12))

      Item {
        id: smallIconSlot
        Layout.preferredWidth: visible ? Style.space(40) : 0
        Layout.preferredHeight: visible ? Style.space(40) : 0
        Layout.alignment: Qt.AlignVCenter
        // Hide the slot when the icon failed to resolve (themed-icon name
        // not in the user's icon theme) AND we don't have a glyph fallback
        // — prevents rendering Qt's pink broken-image placeholder.
        visible: !root.collapseRedundantIcon && !root.compactGlyph && (root.hasSmallIcon || root.hasGlyph) && (root.hasGlyph || smallIconImage.status !== Image.Error)

        Image {
          id: smallIconImage
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio
          sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          visible: !root.hasGlyph || smallIconImage.status === Image.Ready
        }

        // Glyph fallback (Nerd Font character) when no image icon is
        // available. Used by omarchy-notification-send's `-g` flag.
        Text {
          anchors.centerIn: parent
          visible: root.hasGlyph && smallIconImage.status !== Image.Ready
          text: root.glyph
          color: Color.notifications.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
      }

      Text {
        Layout.alignment: Qt.AlignVCenter
        visible: root.compactGlyph
        text: root.glyph
        color: Color.notifications.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(2)

        RowLayout {
          Layout.fillWidth: true
          Layout.rightMargin: root.hasBadge ? badgePill.width + Style.space(4) : 0
          visible: root.displaySummary.length > 0
          spacing: Style.space(5)

          Text {
            text: root.titlePrefix
            font.family: "Liberation Sans"
            color: Color.notifications.text
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            maximumLineCount: 1
            // Only the prefix is shown when there is no tag: let it take the row.
            Layout.fillWidth: root.titleTag.length === 0
            Layout.maximumWidth: root.titleTag.length === 0 ? -1 : Math.round(parent.width * 0.5)
          }

          // "[" + name + "]" as three items so the closing bracket survives
          // elision of the name: "[a long session na…]". Positioned by hand
          // (not a layout) so "]" hugs the drawn text, not the text box.
          Item {
            id: tagRow
            visible: root.titleTag.length > 0
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBaseline
            implicitHeight: tagName.implicitHeight

            component TagText: Text {
              font.family: root.fontFamily.length > 0 ? root.fontFamily : "monospace"
              color: root.bodyColor
              font.pixelSize: Style.font.bodySmall
              maximumLineCount: 1
            }

            TagText { id: tagOpen; text: "["; anchors.left: parent.left }
            TagText {
              id: tagName
              anchors.left: tagOpen.right
              width: Math.min(implicitWidth, tagRow.width - tagOpen.width - tagClose.width)
              text: root.titleTag
              elide: Text.ElideRight
            }
            TagText { id: tagClose; text: "]"; x: tagName.x + tagName.contentWidth }
          }
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
          visible: root.sanitizedBody.length > 0
          text: root.styledBody
          textFormat: Text.StyledText
          font.family: "Liberation Sans"
          color: root.bodyColor
          font.pixelSize: Style.font.title
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: root.expanded ? 40 : 1
        }
      }
    }
  }

  // Floating elapsed-time pill (top-right). Sits above the content layer.
  Rectangle {
    id: badgePill
    visible: root.hasBadge
    z: 10
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: root.borderTop + Style.space(6)
    anchors.rightMargin: root.borderRight + Style.space(8)
    width: badgeText.implicitWidth + Style.space(12)
    height: badgeText.implicitHeight + Style.space(4)
    radius: height / 2
    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
    border.width: 1
    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.55)

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: "⏱ " + root.badge + " ago"
      color: Color.notifications.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
