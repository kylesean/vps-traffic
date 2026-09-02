import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Native Omarchy Quattro popup. Follows the ai-usagebar panel shape: the
// panel owns the refresh cycle and the settings form, BarWidget.qml keeps
// only the bar-slot glue. `provider` rides in the report JSON so future
// VPS panels (vultr, hetzner, ...) plug in with no QML changes.
Panel {
  id: root
  moduleName: "kylesean.vps-traffic"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool vertical: bar ? bar.vertical : false

  property var report: null
  property string loadError: ""
  property string commandStderr: ""
  property string commandStdout: ""
  property bool loading: true
  property int lastExitCode: 0
  property bool refreshQueued: false
  property double lastSuccessfulMs: 0
  property double nowMs: Date.now()
  property bool settingsOpen: false

  readonly property int refreshIntervalSec: Math.max(30, Math.min(3600,
    Number(setting("refreshIntervalSec", 300)) || 300))
  readonly property int warnPercent: Math.max(1, Math.min(99,
    Number(setting("warnPercent", 80)) || 80))
  readonly property int criticalPercent: Math.max(2, Math.min(100,
    Number(setting("criticalPercent", 95)) || 95))
  readonly property bool showPercent: Model.booleanSetting(setting("showPercent", true), true)
  readonly property bool showHost: Model.booleanSetting(setting("showHost", false), false)
  readonly property string configuredProvider: String(setting("provider", "") || "").trim()
  readonly property var providerList: Model.supportedProviders()
  readonly property bool providerSwitchVisible: providerList.length > 1
  property string selectedProviderId: "kiwivm"

  // Never show one provider's numbers under another's tab: only the report
  // that matches the selected provider counts.
  readonly property var currentReport: report && report.provider === selectedProviderId ? report : null
  readonly property bool credentialMissing: Model.isMissingCredentials(loadError)
  readonly property string severity: currentReport ? Model.isAlarming(currentReport, warnPercent, criticalPercent) : ""
  readonly property bool alarming: (loadError !== "" && !credentialMissing)
    || (currentReport && currentReport.suspended)
    || severity === "critical"

  function alpha(color, opacity) {
    return Qt.rgba(color.r, color.g, color.b, opacity)
  }

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  // ---- settings persistence ------------------------------------------------
  function persistWidgetSettings(values) {
    var entry = Model.settingsWithOverrides(root.settings, root.moduleName, values)
    if (!entry) return false
    root.settings = entry
    if (hostWidget && "settings" in hostWidget) hostWidget.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
    return true
  }

  function setShowPercent(enabled) {
    var next = enabled === true
    if (next === showPercent) return
    persistWidgetSettings({ showPercent: next })
  }

  function setShowHost(enabled) {
    var next = enabled === true
    if (next === showHost) return
    persistWidgetSettings({ showHost: next })
  }

  function setProvider(id) {
    var clean = String(id || "").trim()
    if (clean === "" || !Model.isKnownProvider(clean)) return
    if (clean === selectedProviderId) return
    selectedProviderId = clean
    persistWidgetSettings({ provider: clean })
    startRefresh()
  }

  // Follow the pinned provider setting on entry, falling back to the first
  // known provider. Kept here (not a readonly binding) so the source of truth
  // for the fetch is unambiguous.
  function syncProvider() {
    if (configuredProvider !== "" && Model.isKnownProvider(configuredProvider))
      selectedProviderId = configuredProvider
    else if (!Model.isKnownProvider(selectedProviderId)) selectedProviderId = "kiwivm"
  }

  // Reserved entry switching: cycles the provider registry. Only becomes
  // active once more than one backend is registered; a single provider is a
  // no-op so today's behavior is unchanged.
  function nextProvider(direction) {
    var list = Model.supportedProviders()
    if (list.length < 2) return
    var idx = 0
    for (var i = 0; i < list.length; i++)
      if (list[i].id === selectedProviderId) { idx = i; break }
    var wrapped = ((idx + direction) % list.length + list.length) % list.length
    setProvider(list[wrapped].id)
  }

  function setRefreshIntervalSec(value) {
    var n = Math.max(30, Math.min(3600, Math.round(Number(value) || 300)))
    if (n === refreshIntervalSec) return
    persistWidgetSettings({ refreshIntervalSec: n })
  }

  function setWarnPercent(value) {
    var n = Math.max(10, Math.min(99, Math.round(Number(value) || 80)))
    if (n === warnPercent) return
    persistWidgetSettings({ warnPercent: n })
  }

  function setCriticalPercent(value) {
    var n = Math.max(11, Math.min(100, Math.round(Number(value) || 95)))
    if (n === criticalPercent) return
    persistWidgetSettings({ criticalPercent: n })
  }

  // ---- refresh cycle --------------------------------------------------------
  function startRefresh() {
    if (trafficProcess.running) {
      refreshQueued = true
      return
    }
    refreshQueued = false
    commandStdout = ""
    commandStderr = ""
    if (!report) loading = true
    trafficProcess.running = true
  }

  function finishRefresh() {
    var parsed = Model.parseReport(commandStdout)
    if (parsed.ok) {
      report = parsed.report
      loadError = ""
      lastSuccessfulMs = Date.now()
    } else {
      var detail = commandStderr.trim()
      loadError = lastExitCode === 127
        ? "vps-traffic not found: " + detail
        : (detail !== "" ? detail : parsed.error)
    }
    loading = false
    if (refreshQueued) Qt.callLater(startRefresh)
  }

  function refresh() { startRefresh() }

  function openSettings() {
    settingsOpen = true
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { settingsView.loadCredentials() })
    Qt.callLater(function() { settingsView.forceActiveFocus() })
  }

  function closeSettings() {
    settingsOpen = false
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  // ---- header text ----------------------------------------------------------
  function heroTitle() {
    if (settingsOpen) return "Settings"
    if (currentReport) return Model.providerName(currentReport)
    if (credentialMissing) return Model.providerLabel(selectedProviderId)
    return "VPS traffic"
  }

  function heroMeta() {
    if (settingsOpen) return "Provider, credentials & display"
    if (credentialMissing) return "Not configured"
    if (loading && !currentReport) return "Collecting usage"
    if (loadError !== "") return "Fetch failed"
    if (currentReport && currentReport.suspended) return "Suspended · bandwidth overage"
    return currentReport ? Model.autoTextSafe(String(currentReport.plan || "Usage")) : "No data"
  }

  function heroDetail() {
    // The hero renders detail as a compact badge beside the title, so keep it
    // terse: a sentence here only gets clipped.
    if (settingsOpen) return "LOCAL"
    if (!currentReport) return ""
    return Model.headline(currentReport) + " · " + Model.percentText(currentReport) + " used"
  }

  function statusMessage() {
    if (credentialMissing)
      return "Add " + Model.providerLabel(selectedProviderId) + " credentials in Settings to see usage."
    if (loadError !== "") return "Fetch failed · " + loadError
    if (currentReport && currentReport.suspended)
      return "Traffic quota exhausted. The VPS is suspended until the quota resets."
    return ""
  }

  function statusIsUrgent() {
    if (credentialMissing) return false
    return loadError !== "" || (currentReport && currentReport.suspended) || severity === "critical"
  }

  function barText() {
    if (currentReport) return Model.barLabel(currentReport, { showHost: showHost, showPercent: showPercent })
    if (credentialMissing) return "󰒋"
    if (loading) return "󰒋  …"
    return "󰒋"
  }

  function tooltipText() {
    if (currentReport)
      return Model.providerName(currentReport) + " · " + Model.headline(currentReport)
        + " · " + Model.percentText(currentReport)
    if (credentialMissing)
      return "VPS traffic: add " + Model.providerLabel(selectedProviderId) + " credentials in settings"
    if (loading) return "VPS traffic: collecting usage…"
    return loadError !== "" ? "VPS traffic: " + loadError : "VPS traffic"
  }

  onOpenedChanged: {
    if (opened) {
      syncProvider()
      nowMs = Date.now()
      if (panelFlick) panelFlick.contentY = 0
      if (lastSuccessfulMs === 0 || nowMs - lastSuccessfulMs >= refreshIntervalSec * 1000)
        startRefresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      settingsOpen = false
    }
  }

  Component.onCompleted: syncProvider()

  IpcHandler {
    target: "kylesean.vps-traffic"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function openSettings(): void { root.openSettings() }
    function refresh(): void { root.refresh() }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.startRefresh()
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Process {
    id: trafficProcess
    running: false
    // /usr/bin/env always starts on Omarchy and reports a missing script as
    // exit 127. Keep the command as structured argv: no shell is needed.
    command: ["/usr/bin/env", "bash", root.scriptPath, "--provider", root.selectedProviderId, "--json"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.commandStdout = text
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.commandStderr = text
    }

    onExited: function(exitCode) {
      root.lastExitCode = exitCode
      // Let both waitForEnd collectors publish their buffers first.
      Qt.callLater(function() { root.finishRefresh() })
    }
  }

  readonly property string scriptPath: {
    var url = String(Qt.resolvedUrl("../bin/vps-traffic"))
    if (url.indexOf("file://") === 0) url = url.slice(7)
    return url
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Native form controls own Tab/Enter/Esc while settings are open.
      blocked: root.settingsOpen

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
            Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: if (!root.settingsOpen) root.refresh()
      onCloseRequested: root.settingsOpen ? root.closeSettings() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (!root.settingsOpen && (text === "r" || text === "R")) root.refresh()
        else if (!root.settingsOpen && (text === "s" || text === "S")) root.openSettings()
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

          PanelHero {
            width: parent.width
            title: root.heroTitle()
            meta: root.heroMeta()
            detail: root.heroDetail()
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: root.settingsOpen ? "󰒓" : "󰒋"
                color: root.alarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              Row {
                spacing: Style.space(4)

                PanelActionButton {
                  visible: !root.settingsOpen
                  iconText: "󰑐"
                  tooltipText: "Refresh usage"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !trafficProcess.running
                  onClicked: root.refresh()
                }

                PanelActionButton {
                  iconText: root.settingsOpen ? "󰁍" : "󰒓"
                  tooltipText: root.settingsOpen ? "Back to usage" : "Settings"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.settingsOpen ? root.closeSettings() : root.openSettings()
                }
              }
            }
          }

          SettingsView {
            id: settingsView
            visible: root.settingsOpen
            width: parent.width
            foreground: root.foreground
            urgent: root.urgent
            fontFamily: root.fontFamily
            provider: root.selectedProviderId
            providers: root.providerList
            showPercent: root.showPercent
            showHost: root.showHost
            warnPercent: root.warnPercent
            criticalPercent: root.criticalPercent
            refreshIntervalSec: root.refreshIntervalSec
            onSaved: {
              // Refresh now and leave Settings so the fresh usage is visible
              // instead of hiding behind the form.
              root.startRefresh()
              root.closeSettings()
            }
            onProviderRequested: function(id) { root.setProvider(id) }
            onRefreshIntervalSecRequested: function(value) { root.setRefreshIntervalSec(value) }
            onWarnPercentRequested: function(value) { root.setWarnPercent(value) }
            onCriticalPercentRequested: function(value) { root.setCriticalPercent(value) }
            onShowPercentRequested: function(enabled) { root.setShowPercent(enabled) }
            onShowHostRequested: function(enabled) { root.setShowHost(enabled) }
            onCloseRequested: root.closeSettings()
          }

          ListView {
            visible: root.providerSwitchVisible && !root.settingsOpen
            width: parent.width
            height: visible ? Style.spacing.controlHeight : 0
            orientation: ListView.Horizontal
            spacing: Style.spacing.md
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.providerList

            delegate: Button {
              required property var modelData
              required property int index

              height: root.providerList.length > 1 ? Style.spacing.controlHeight : 0
              text: Model.providerLabel(modelData.id)
              selected: modelData.id === root.selectedProviderId
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.setProvider(modelData.id)
            }
          }

          BorderSurface {
            readonly property string message: root.statusMessage()
            visible: !root.settingsOpen && message !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.statusIsUrgent() ? root.urgent : root.foreground, 0.09)
            borderSpec: Border.flat(root.alpha(root.statusIsUrgent() ? root.urgent : root.foreground, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: parent.message
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            visible: !root.settingsOpen && root.loading && !root.currentReport && !root.credentialMissing
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "USAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              text: "Collecting usage from the provider…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Column {
            id: usageSection
            visible: !root.settingsOpen && root.currentReport !== null
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { width: parent.width }

            PanelSectionHeader {
              text: "USAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            MetricRow {
              width: parent.width
              label: "Bandwidth used"
              percent: root.currentReport ? root.currentReport.percent : 0
              value: root.currentReport ? Model.headline(root.currentReport) : ""
              detail: root.currentReport ? Model.metricDetail(root.currentReport) : ""
              resetText: root.currentReport ? Model.formatReset(root.currentReport.next_reset, root.nowMs) : ""
              critical: root.severity === "critical"
            }

            PanelSectionHeader {
              text: "DETAILS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            DetailRow { width: parent.width; label: "Provider"; value: root.currentReport ? Model.autoTextSafe(String(root.currentReport.provider || "")) : "--" }
            DetailRow { width: parent.width; label: "Plan"; value: root.currentReport ? Model.autoTextSafe(String(root.currentReport.plan || "")) : "--" }
            DetailRow { width: parent.width; label: "Next reset"; value: root.currentReport ? Model.autoTextSafe(String(root.currentReport.next_reset_iso || "")) : "--" }
            DetailRow { width: parent.width; label: "Location"; value: root.currentReport ? Model.autoTextSafe(String(root.currentReport.location || "")) : "--" }
            DetailRow { width: parent.width; label: "OS"; value: root.currentReport ? Model.autoTextSafe(String(root.currentReport.os || "")) : "--" }
            DetailRow { width: parent.width; label: "IP"; value: root.currentReport ? Model.autoTextSafe(String(root.currentReport.ip || "")) : "--" }
          }

          Text {
            visible: !root.settingsOpen && root.currentReport !== null
            width: parent.width
            topPadding: Style.space(2)
            text: root.currentReport ? Model.formatUpdated(root.currentReport.fetched_at, root.nowMs)
              + (trafficProcess.running ? " · refreshing…" : "") : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  component MetricRow: Column {
    id: metricRow
    property string label: ""
    property double percent: 0
    property string value: ""
    property string detail: ""
    property string resetText: ""
    property bool critical: false

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(metricLabel.implicitHeight, metricValue.implicitHeight)

      Text {
        id: metricLabel
        text: metricRow.label
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: metricValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: metricValue
        text: metricRow.value
        textFormat: Text.PlainText
        color: metricRow.critical ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Item {
      width: parent.width
      implicitHeight: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

      Rectangle {
        id: meterTrack
        anchors.fill: parent
        radius: height / 2
        color: root.track
      }

      Rectangle {
        anchors.left: meterTrack.left
        anchors.verticalCenter: meterTrack.verticalCenter
        height: meterTrack.height
        radius: meterTrack.radius
        width: meterTrack.width * root.clamp(metricRow.percent / 100, 0, 1)
        color: metricRow.critical ? root.urgent : root.foreground

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      visible: text !== ""
      width: parent.width
      text: metricRow.detail
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      visible: text !== ""
      width: parent.width
      text: metricRow.resetText
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  component DetailRow: Item {
    id: detailRow
    property string label: ""
    property string value: ""

    implicitHeight: Math.max(detailLabel.implicitHeight, detailValue.implicitHeight)

    Text {
      id: detailLabel
      text: detailRow.label
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.left: parent.left
      anchors.top: parent.top
      width: Math.min(implicitWidth, parent.width * 0.42)
      elide: Text.ElideRight
    }

    Text {
      id: detailValue
      text: detailRow.value
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: detailLabel.visible ? Text.AlignRight : Text.AlignLeft
      wrapMode: Text.WordWrap
      anchors.left: detailLabel.visible ? detailLabel.right : parent.left
      anchors.leftMargin: detailLabel.visible ? Style.spacing.md : 0
      anchors.right: parent.right
      anchors.top: parent.top
    }
  }
}