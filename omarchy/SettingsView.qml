import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Native Quattro settings form for VPS Traffic. Credentials are pasted here
// and written atomically to ~/.config/vps-traffic/<provider>/env (mode 600)
// by a small python helper over stdin — never argv, so the key never shows in
// the process list. Display, refresh and threshold preferences go to the
// widget settings in shell.json.
Column {
  id: root

  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family
  property string provider: "kiwivm"
  property var providers: []
  property bool showPercent: true
  property bool showHost: false
  property int warnPercent: 80
  property int criticalPercent: 95
  property int refreshIntervalSec: 300

  signal saved()
  signal providerRequested(string id)
  signal refreshIntervalSecRequested(int value)
  signal warnPercentRequested(int value)
  signal criticalPercentRequested(int value)
  signal showPercentRequested(bool enabled)
  signal showHostRequested(bool enabled)
  signal closeRequested()

  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property var fields: Model.credentialFields(provider)
  property var credsValues: ({})
  property bool keyPresent: false
  property bool showKeyValue: false
  property bool credsLoading: false
  property bool saving: false
  property string credsStatus: ""
  property string credsError: ""
  property string credsStderr: ""

  onProviderChanged: if (visible) loadCredentials()

  function credValue(key) {
    return String((credsValues && credsValues[key]) || "")
  }

  spacing: Style.space(12)
  focus: visible
  Keys.onEscapePressed: closeRequested()

  // ---- credential read / write ---------------------------------------------
  function loadCredentials() {
    if (credsReadProcess.running || credsWriteProcess.running) return
    credsLoading = true
    credsError = ""
    credsStatus = ""
    credsReadProcess.running = true
  }

  function finishRead() {
    credsLoading = false
    if (credsReadExitCode !== 0) {
      credsError = "Could not read saved credentials: " + credsReadStderr
      return
    }
    var parsed = {}
    try { parsed = JSON.parse(credsReadStdout) } catch (e) { return }
    if (!parsed || typeof parsed !== "object") return
    var next = {}
    for (var i = 0; i < fields.length; i++)
      next[fields[i].key] = parsed[fields[i].key] || ""
    credsValues = next
    keyPresent = parsed.key_present === true
  }

  function saveCredentials() {
    if (saving) return
    credsError = ""
    credsStatus = ""
    var idKey = fields.length > 0 ? fields[0].key : ""
    if (String(credsValues[idKey] || "").trim() === "") {
      credsError = fields.length > 0 ? fields[0].label + " is required" : "Credentials are required"
      return
    }
    if (!keyPresent && String(credsValues.api_key || "").trim() === "") {
      credsError = "API key is required"
      return
    }
    var payload = {}
    for (var i = 0; i < fields.length; i++) {
      var v = String(credsValues[fields[i].key] || "").trim()
      if (v !== "") payload[fields[i].key] = v
    }
    saving = true
    pendingPayload = JSON.stringify(payload)
    credsWriteProcess.running = true
  }

  function finishWrite() {
    saving = false
    if (credsWriteExitCode !== 0) {
      credsError = "Could not save credentials: " + credsWriteStderr
      return
    }
    if ("api_key" in credsValues) credsValues.api_key = ""
    credsStatus = "Credentials saved locally (mode 600)"
    saved()
  }

  property string credsReadStdout: ""
  property string credsReadStderr: ""
  property int credsReadExitCode: -1
  property string credsWriteStderr: ""
  property int credsWriteExitCode: -1
  property string pendingPayload: ""

  readonly property string scriptPath: {
    var url = String(Qt.resolvedUrl("../bin/vps-traffic"))
    if (url.indexOf("file://") === 0) url = url.slice(7)
    return url
  }

  Process {
    id: credsReadProcess
    running: false
    command: ["/usr/bin/env", "bash", root.scriptPath, "--creds-read", root.provider]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.credsReadStdout = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.credsReadStderr = text
    }
    onExited: function(exitCode) {
      root.credsReadExitCode = exitCode
      Qt.callLater(root.finishRead)
    }
  }

  Process {
    id: credsWriteProcess
    running: false
    command: ["/usr/bin/env", "bash", root.scriptPath, "--creds-write", root.provider]
    stdinEnabled: true
    onStarted: {
      write(root.pendingPayload + "\n")
      root.pendingPayload = ""
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.credsStatus = text.trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.credsWriteStderr = text
    }
    onExited: function(exitCode) {
      root.credsWriteExitCode = exitCode
      Qt.callLater(root.finishWrite)
    }
  }

  // ---- form ---------------------------------------------------------------
  PanelSectionHeader {
    text: "PROVIDER"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  ListView {
    id: providerSelector
    width: parent.width
    height: Style.spacing.controlHeight
    orientation: ListView.Horizontal
    spacing: Style.spacing.md
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.providers

    delegate: Button {
      required property var modelData
      required property int index

      height: providerSelector.height
      text: modelData.label
      selected: modelData.id === root.provider
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      verticalPadding: Style.spacing.controlPaddingY
      onClicked: root.providerRequested(modelData.id)
    }
  }

  Text {
    width: parent.width
    text: root.providers.length > 1
      ? "Add another backend to the registry to switch here. Credentials are kept per provider."
      : "Other VPS panels plug in the same way; the registry drives the selector."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  PanelSectionHeader {
    text: "CREDENTIALS"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    width: parent.width
    text: "Paste the credentials from the provider panel. Stored locally with mode 600, "
      + "never in the process list."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Repeater {
    id: credFields
    model: root.fields

    delegate: Column {
      required property var modelData
      width: root.width
      spacing: Style.space(6)

      TextField {
        width: parent.width
        placeholderText: root.keyPresent && modelData.secret
          ? "API key already set (leave empty to keep it)"
          : modelData.placeholder
        text: root.credValue(modelData.key)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        selectByMouse: true
        echoMode: modelData.secret && !root.showKeyValue ? TextInput.Password : TextInput.Normal
        onTextChanged: root.credsValues[modelData.key] = text
      }
    }
  }

  Row {
    spacing: Style.space(8)

    Button {
      id: showKey
      text: root.showKeyValue ? "Hide" : "Show"
      bordered: true
      focusable: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.showKeyValue = !root.showKeyValue
    }

    PanelActionButton {
      iconText: "󰇷"
      tooltipText: "Save credentials"
      foreground: root.foreground
      fontFamily: root.fontFamily
      enabled: !root.saving
      onClicked: root.saveCredentials()
    }

    PanelActionButton {
      iconText: "󰁍"
      tooltipText: "Done"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.closeRequested()
    }
  }

  Text {
    visible: root.credsError !== ""
    width: parent.width
    text: root.credsError
    color: root.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    visible: root.credsStatus !== "" && root.credsError === ""
    width: parent.width
    text: root.credsStatus
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  PanelSectionHeader {
    text: "DISPLAY"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  SettingToggle {
    label: "Show usage percentage in the bar"
    checked: root.showPercent
    foreground: root.foreground
    fontFamily: root.fontFamily
    onToggled: function(enabled) { root.showPercentRequested(enabled) }
  }

  SettingToggle {
    label: "Show VPS hostname in the bar"
    checked: root.showHost
    foreground: root.foreground
    fontFamily: root.fontFamily
    onToggled: function(enabled) { root.showHostRequested(enabled) }
  }

  PanelSectionHeader {
    text: "REFRESH & THRESHOLDS"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  SettingStepper {
    label: "Refresh every (s)"
    value: root.refreshIntervalSec
    min: 30
    max: 3600
    step: 30
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(value) { root.refreshIntervalSecRequested(value) }
  }

  SettingStepper {
    label: "Warn at usage %"
    value: root.warnPercent
    min: 10
    max: 99
    step: 1
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(value) { root.warnPercentRequested(value) }
  }

  SettingStepper {
    label: "Critical at usage %"
    value: root.criticalPercent
    min: 11
    max: 100
    step: 1
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(value) { root.criticalPercentRequested(value) }
  }

  Text {
    width: parent.width
    text: "The KiwiVM counter lags ~15 minutes behind real usage, so a larger interval is fine."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component SettingToggle: Item {
    id: settingToggle
    property string label: ""
    property bool checked: false
    property color foreground
    property string fontFamily
    signal toggled(bool enabled)

    implicitHeight: Math.max(controlButton.implicitHeight, toggleLabel.implicitHeight)

    Text {
      id: toggleLabel
      textFormat: Text.PlainText
      text: settingToggle.label
      color: settingToggle.foreground
      font.family: settingToggle.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    PanelActionButton {
      id: controlButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: settingToggle.checked ? "󰄲" : "󰄱"
      tooltipText: settingToggle.checked ? "On" : "Off"
      foreground: settingToggle.foreground
      fontFamily: settingToggle.fontFamily
      onClicked: settingToggle.toggled(!settingToggle.checked)
    }
  }

  component SettingStepper: Item {
    id: settingStepper
    property string label: ""
    property int value: 0
    property int min: 0
    property int max: 100
    property int step: 1
    property color foreground
    property string fontFamily
    signal changed(int value)

    implicitHeight: Math.max(controlRow.implicitHeight, stepperLabel.implicitHeight)

    Text {
      id: stepperLabel
      textFormat: Text.PlainText
      text: settingStepper.label
      color: settingStepper.foreground
      font.family: settingStepper.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Row {
      id: controlRow
      spacing: Style.space(6)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter

      Button {
        text: "−"
        bordered: true
        focusable: true
        foreground: settingStepper.foreground
        fontFamily: settingStepper.fontFamily
        onClicked: settingStepper.changed(Math.max(settingStepper.min, settingStepper.value - settingStepper.step))
      }

      Text {
        textFormat: Text.PlainText
        text: String(settingStepper.value)
        color: settingStepper.foreground
        font.family: settingStepper.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }

      Button {
        text: "+"
        bordered: true
        focusable: true
        foreground: settingStepper.foreground
        fontFamily: settingStepper.fontFamily
        onClicked: settingStepper.changed(Math.min(settingStepper.max, settingStepper.value + settingStepper.step))
      }
    }
  }
}