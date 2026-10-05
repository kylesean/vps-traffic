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

  readonly property string barText: root.panelItem ? root.panelItem.barText() : "󰒋  …"
  // Spec: icon-only goes through BarIconButton (Style.bar.iconFont 13px,
  // 27px slot), readings go through WidgetButton (Style.font.body 12px).
  readonly property bool iconOnly: root.barText.trim() === "󰒋"

  function activeButton() {
    return root.iconOnly ? iconButton : textButton
  }

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
    if ("anchorItem" in target) target.anchorItem = root.activeButton()
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: root.activeButton().implicitWidth
  implicitHeight: root.activeButton().implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onIconOnlyChanged: injectPanel()

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

  // Readings: text widget, aligned with clock/workspaces.
  WidgetButton {
    id: textButton
    anchors.fill: parent
    visible: !root.iconOnly
    bar: root.bar
    text: root.barText
    fontSize: Style.font.body
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

  // Icon-only: icon widget, aligned with audio/network/bluetooth.
  BarIconButton {
    id: iconButton
    anchors.fill: parent
    visible: root.iconOnly
    bar: root.bar
    text: root.barText
    active: root.panelItem ? root.panelItem.alarming : false
    tooltipText: root.panelItem ? root.panelItem.tooltipText() : "VPS traffic"

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