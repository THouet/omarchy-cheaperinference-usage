pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar entry point (the manifest loads this file). It shows the wallet
// balance in the bar, hosts the details panel through a Loader, and
// forwards the panel lifecycle that Quattro routes clicks and shell
// commands through. Data extraction lives in Main.qml behind bin/collect.
BarWidget {
  id: root
  moduleName: "thouet.cheaperinference-usage"

  Main {
    id: usageModel
    settings: root.settings
  }

  // Exposed as a property (the id alone is invisible from Panel.qml) so the
  // panel reads the collector record through hostWidget.usage.
  readonly property alias usage: usageModel

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function switchPanel(direction) {
    if (panelLoader.item) return panelLoader.item.switchPanel(direction)
    return false
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  readonly property var record: usage.record
  readonly property bool balanceAlarming: {
    var balance = record ? (record.balance || null) : null
    return !!balance && balance.funded > 0 && balance.remaining / balance.funded <= 0.1
  }
  readonly property color barForeground: bar ? bar.foreground : (Color ? Color.foreground : "#ffffff")

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  property double nowMs: Date.now()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "CI"
    labelVisible: false
    hasVisualContent: true
    active: root.balanceAlarming
    fixedWidth: button.vertical ? Style.bar.iconSlot : barRow.implicitWidth + Style.space(16)
    fixedHeight: button.vertical ? Style.bar.iconSlot : -1
    tooltipText: {
      var balance = root.record ? (root.record.balance || null) : null
      return balance
        ? "CheaperInference · $" + Number(balance.remaining).toFixed(2) + " available"
        : "CheaperInference"
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) usage.refreshAll(true)
      else root.toggle()
    }

    Row {
      id: barRow
      visible: !button.vertical
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: "CI"
        color: root.balanceAlarming ? (root.bar ? root.bar.urgent : "#ff5555") : root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.bar.iconFont * 0.8
        font.bold: true
      }

      Text {
        visible: !!root.record && !!root.record.balance
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: {
          var balance = root.record ? (root.record.balance || null) : null
          if (!balance) return ""
          var amount = Number(balance.remaining)
          if (!isFinite(amount)) return ""
          var prefix = "$"
          if (amount >= 100000) return prefix + Math.floor(amount / 1000) + "k"
          if (amount >= 1000) return prefix + (Math.floor(amount / 100) / 10).toFixed(1).replace(/\.0$/, "") + "k"
          return prefix + amount.toFixed(2)
        }
        color: root.balanceAlarming ? (root.bar ? root.bar.urgent : "#ff5555") : root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: button.fontSize
        font.bold: true
        renderType: Text.NativeRendering
      }
    }

    Text {
      visible: button.vertical
      anchors.centerIn: parent
      text: "CI"
      color: root.balanceAlarming ? (root.bar ? root.bar.urgent : "#ff5555") : root.barForeground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.bar.iconFont * 0.8
      font.bold: true
    }
  }
}
