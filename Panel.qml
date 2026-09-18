pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Controls as Controls
import Quickshell
import qs.Commons
import qs.Ui

// Details panel (loaded by BarWidget.qml's Loader). Quattro's Panel base
// provides the open state and controller; KeyboardPanel anchors the surface
// to the bar button, and Escape closes it through PanelKeyCatcher.
Panel {
  id: root
  moduleName: "thouet.cheaperinference-usage"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var usage: hostWidget ? hostWidget.usage : null
  readonly property var record: usage ? usage.record : null
  readonly property var balance: record ? (record.balance || null) : null
  readonly property var days: record ? (record.recentDays || []).slice().reverse() : []
  readonly property var activity: record ? (record.activity || null) : null
  property string activeTab: "daily"
  property double nowMs: hostWidget ? hostWidget.nowMs : Date.now()
  readonly property bool periodReady: !!activity && !!usage && activity.period === usage.detailsPeriod
  readonly property var breakdownRows: !periodReady ? [] :
    (activeTab === "keys" ? activity.topKeys || [] : activity.topModels || [])
  readonly property string breakdownError: periodReady && activity.breakdownErrors
    ? String(activity.breakdownErrors[activeTab] || "") : ""

  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function refreshNow() { if (usage) usage.refreshAll(true) }

  function openLink(url) {
    var href = String(url || "")
    if (href === "") return
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("xdg-open " + Util.shellQuote(href))
    else
      Qt.openUrlExternally(href)
  }

  // ---------------------------------------------------------------- money

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) return ""
    var prefix = String(currency || "USD").toUpperCase() === "USD" ? "$" : String(currency).toUpperCase() + " "
    return prefix + amount.toFixed(2)
  }

  function formatBalance(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) return ""
    var prefix = String(currency || "USD").toUpperCase() === "USD" ? "$" : String(currency).toUpperCase() + " "
    if (amount >= 100000) return prefix + Math.floor(amount / 1000) + "k"
    if (amount >= 1000) {
      var thousands = Math.floor(amount / 100) / 10
      return prefix + thousands.toFixed(1).replace(/\.0$/, "") + "k"
    }
    return prefix + amount.toFixed(2)
  }

  function formatCost(value) {
    var n = Number(value || 0)
    if (!(n >= 0)) n = 0
    if (n >= 1000) return "$" + (n / 1000).toFixed(1) + "k"
    return "$" + (n >= 100 ? n.toFixed(0) : n.toFixed(2))
  }

  // ---------------------------------------------------------------- content

  function heroMeta() {
    if (!record) return ""
    if (String(record.usageStatusText || "") !== "") return record.usageStatusText
    return "Wallet usage"
  }

  // UTC calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getUTCFullYear()
      + "-" + String(now.getUTCMonth() + 1).padStart(2, "0")
      + "-" + String(now.getUTCDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    return today ? "Today" : String(date || "").slice(5)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + formatCost(day.cost)
      + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    text += " · " + Number(day.prompts || 0) + " requests · UTC · all keys"
    return text
  }

  function weekPeak() {
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].cost || 0))
    return Math.max(1e-9, peak)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return String(row.name) + " · " + formatMoney(row.cost, "USD")
      + " · " + usage.formatTokenCount(row.tokens) + " tokens"
  }

  function footerText() {
    if (!record || !record.updatedAt) return ""
    var updated = new Date(String(record.updatedAt))
    if (isNaN(updated.getTime())) return ""
    var minutes = Math.max(0, Math.round((root.nowMs - updated.getTime()) / 60000))
    return minutes === 0 ? "Updated just now" : "Updated " + minutes + " min ago"
  }

  function activityHint() {
    if (!activity) return ""
    return String(activity.helpText || "All keys combined · UTC calendar days · today is partial.")
  }

  function formatActivityTokens(n) {
    return usage.formatTokenCount(n)
  }

  function formatRequests(n) {
    var count = Number(n || 0)
    if (!(count >= 0)) count = 0
    if (count >= 1000) return usage.formatTokenCount(count)
    return String(Math.round(count))
  }

  function formatCacheHit(n) {
    if (n === null || n === undefined) return "—"
    var rate = Number(n || 0)
    if (!(rate >= 0)) rate = 0
    if (rate > 1) rate = rate / 100
    return (rate * 100).toFixed(1) + "%"
  }

  // ------------------------------------------------------------------ shell

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    if (usage) usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: mark · name · tier · available ----------
          Item {
            id: header
            visible: !!root.record
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property string amountText: root.balance
              ? root.formatBalance(root.balance.remaining, root.balance.currency)
              : ""
            readonly property color amountColor: root.balanceAlarming ? root.urgent : root.foreground
            readonly property color dimColor: root.dim
            readonly property string family: root.fontFamily

            AccountHero {
              id: hero
              width: parent.width
              title: "CheaperInference"
              meta: root.heroMeta()
              foreground: root.foreground
              fontFamily: root.fontFamily
              trailingControl: Component {
                Controls.AbstractButton {
                  id: balanceLink
                  visible: header.amountText !== ""
                  implicitWidth: Math.max(heroAmount.implicitWidth, heroAvailable.implicitWidth)
                  implicitHeight: balanceLabels.implicitHeight
                  hoverEnabled: true
                  Accessible.name: "Open CheaperInference dashboard, " + header.amountText + " available"
                  onClicked: root.openLink("https://www.cheaperinference.com/dashboard")
                  HoverHandler { cursorShape: Qt.PointingHandCursor }
                  contentItem: Column {
                    id: balanceLabels
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      id: heroAmount
                      width: parent.width
                      text: header.amountText
                      color: header.amountColor
                      font.family: header.family
                      font.pixelSize: Style.font.title
                      font.bold: true
                      font.underline: balanceLink.hovered || balanceLink.activeFocus
                      horizontalAlignment: Text.AlignRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      id: heroAvailable
                      width: parent.width
                      text: "AVAILABLE"
                      color: header.dimColor
                      font.family: header.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 1.2
                      horizontalAlignment: Text.AlignRight
                    }
                  }
                }
              }

              iconComponent: Component {
                Item {
                  width: Style.font.display
                  height: Style.font.display

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "CI"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display * 0.7
                    font.bold: true
                  }
                }
              }
            }
          }

          // ---------- Status (errors only) ----------
          BorderSurface {
            visible: !!root.record && String(root.record.usageStatusText || "") !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              textFormat: Text.PlainText
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.record ? String(root.record.authHelpText || root.record.usageStatusText || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            id: tabRow
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: ["Daily", "Keys", "Models"]
              Controls.Button {
                id: tabButton
                required property string modelData
                width: (tabRow.width - tabRow.spacing * 2) / 3
                height: Style.space(34)
                text: modelData
                checkable: true
                checked: root.activeTab === modelData.toLowerCase()
                onClicked: {
                  root.activeTab = modelData.toLowerCase()
                  panelFlick.contentY = 0
                }
                contentItem: Text {
                  text: tabButton.text
                  textFormat: Text.PlainText
                  color: tabButton.checked ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: tabButton.checked
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                  radius: Style.cornerRadius
                  color: root.alpha(root.foreground, tabButton.checked ? 0.14 : tabButton.hovered ? 0.08 : 0.03)
                  border.width: tabButton.checked ? 1 : 0
                  border.color: root.alpha(root.foreground, 0.35)
                }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(10)
            Text {
              width: parent.width - periodSelect.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              text: root.periodReady ? root.formatMoney(root.activity.spend, "USD") + " total spend" : "Loading usage…"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Controls.ComboBox {
              id: periodSelect
              width: Style.space(144)
              height: Style.space(32)
              leftPadding: Style.space(12)
              rightPadding: Style.space(28)
              contentItem: Text {
                text: periodSelect.displayText
                textFormat: Text.PlainText
                color: root.foreground
                font: periodSelect.font
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }
              indicator: Text {
                text: "▾"
                color: root.foreground
                font: periodSelect.font
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
              }
              delegate: Controls.ItemDelegate {
                required property string modelData
                required property int index
                width: periodSelect.width
                height: Style.space(32)
                leftPadding: Style.space(12)
                rightPadding: Style.space(12)
                text: modelData
                font: periodSelect.font
                palette.text: root.foreground
                highlighted: periodSelect.highlightedIndex === index
              }
              model: ["Last 3 days", "Last 7 days", "Last 30 days", "Last 90 days"]
              currentIndex: root.usage ? root.usage.detailsPeriods.indexOf(root.usage.detailsPeriod) : 1
              onActivated: function(index) { if (root.usage) root.usage.setPeriod(root.usage.detailsPeriods[index]) }
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              palette.buttonText: root.foreground
              palette.text: root.foreground
              palette.button: root.surface
              palette.base: root.surface
              palette.window: root.surface
              palette.highlight: root.track
              palette.highlightedText: root.foreground
            }
          }

          Column {
            id: detailsSection
            visible: root.periodReady
            width: parent.width
            spacing: Style.space(10)

            Grid {
              id: detailsGrid
              width: parent.width
              columns: 2
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(8)

              StatCard {
                width: (detailsGrid.width - detailsGrid.columnSpacing) / 2
                label: "Spend"
                value: root.activity ? root.formatCost(root.activity.spend) : "—"
              }
              StatCard {
                width: (detailsGrid.width - detailsGrid.columnSpacing) / 2
                label: "Requests"
                value: root.activity ? root.formatRequests(root.activity.requests) : "—"
              }
              StatCard {
                width: (detailsGrid.width - detailsGrid.columnSpacing) / 2
                label: "Tokens"
                value: root.activity ? root.formatActivityTokens(root.activity.tokens) : "—"
              }
              StatCard {
                width: (detailsGrid.width - detailsGrid.columnSpacing) / 2
                label: "Cache hit"
                value: root.activity ? root.formatCacheHit(root.activity.cacheHitRate) : "—"
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width
              text: root.activityHint()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            visible: !root.periodReady
            width: parent.width
            text: root.usage && root.usage.loading ? "Loading the selected period…" : root.usage && root.usage.collectError ? root.usage.collectError : "Usage for this period is unavailable. Refresh to try again."
            color: root.dim
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.activeTab !== "daily" && root.periodReady
            width: parent.width
            spacing: Style.spacing.md
            PanelSectionHeader {
              width: parent.width
              text: "SPEND BY " + (root.activeTab === "keys" ? "KEY" : "MODEL")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Text {
              visible: root.breakdownRows.length === 0
              width: parent.width
              text: root.breakdownError || "No usage in this period."
              color: root.dim
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            Repeater {
              model: root.breakdownRows
              RankedRow {
                required property var modelData
                width: parent.width
                row: modelData
              }
            }
          }

          // ---------- Spend by day ----------
          Column {
            id: spendSection
            visible: root.activeTab === "daily" && root.periodReady && root.days.length > 0
            width: parent.width
            spacing: Style.spacing.md

            readonly property real peak: root.weekPeak()

            PanelSectionHeader {
              width: parent.width
              text: "SPEND BY DAY · ALL KEYS · UTC"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.days

              DayRow {
                required property var modelData

                width: spendSection.width
                day: modelData
                ratio: Number(modelData.cost || 0) / spendSection.peak
                today: String(modelData.date || "") === root.todayDate()
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "R refreshes"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

        }
      }
    }
  }

  // ------------------------------------------------------------ components

  // One row per day: label, bar, dollars. Today is picked out in full
  // foreground; the rest of the period sits dimmed behind it.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabelText.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      textFormat: Text.PlainText
      id: dayLabelText
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabelText.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      id: dayValue
      text: root.formatCost(dayRow.day ? dayRow.day.cost : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }

  component StatCard: Rectangle {
    id: statCard
    property string label: ""
    property string value: ""

    implicitHeight: statLabel.implicitHeight + statValue.implicitHeight + Style.space(16)
    radius: Style.cornerRadius
    color: root.alpha(root.foreground, 0.05)

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        id: statLabel
        width: parent.width
        text: statCard.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        id: statValue
        width: parent.width
        text: statCard.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
    }
  }

  component RankedRow: Item {
    id: rankedRow
    property var row: null

    implicitHeight: Math.max(rankedName.implicitHeight, rankedValue.implicitHeight) + Style.spacing.sm

    Text {
      textFormat: Text.PlainText
      id: rankedName
      text: rankedRow.row ? String(rankedRow.row.name || "") : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.right: rankedValue.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      textFormat: Text.PlainText
      id: rankedValue
      text: rankedRow.row ? root.formatMoney(rankedRow.row.cost, "USD") : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
    MouseArea {
      id: rankedHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }
    PanelToolTip {
      visible: rankedHover.containsMouse
      text: root.modelTooltip(rankedRow.row)
      fontFamily: root.fontFamily
    }
  }
}
