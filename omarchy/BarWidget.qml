import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Quattro bar entry point. The popup is loaded separately so the object in
// the bar slot owns shell routing while Panel.qml remains focused on report
// collection, presentation and settings. ai-usagebar shape.
BarWidget {
  id: root
  moduleName: "kylesean.vps-traffic"

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem
    ? panelItem.popoutSwitchClosing === true
    : false

  function open() {
    if (panelItem) panelItem.open()
  }

  function close() {
    if (panelItem) panelItem.close()
  }

  function toggle() {
    if (panelItem) panelItem.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelItem) panelItem.closeForPopoutSwitch()
  }

  function refresh() {
    if (panelItem) panelItem.refresh()
  }

  function openSettings() {
    if (panelItem) panelItem.openSettings()
  }

  function injectPanel() {
    var target = panelItem
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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
    text: root.panelItem ? root.panelItem.barText() : "󰒋  …"
    fontSize: Style.font.bodySmall
    active: root.panelItem ? root.panelItem.alarming : false
    tooltipText: root.panelItem ? root.panelItem.tooltipText() : "VPS traffic"
    horizontalMargin: 8.5

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openSettings()
      else if (buttonCode === Qt.MiddleButton && root.panelItem)
        root.panelItem.nextProvider(1)
      else root.toggle()
    }

    onWheelMoved: function(delta) {
      if (delta !== 0) root.refresh()
    }
  }
}