import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning
import Qt.labs.platform as Platform

import "../"
import "../common"
import "../components"

Popup {
    id: dialog

    width: Math.min(1080, Overlay.overlay ? Overlay.overlay.width - 36 : 1080)
    height: Math.min(760, Overlay.overlay ? Overlay.overlay.height - 36 : 760)
    modal: true
    dim: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: Overlay.overlay
    Overlay.modal: Rectangle { color: "#B8000000" }

    property bool deviceTab: false
    property string sensorName: ""
    property real mapLat: 0
    property real mapLon: 0
    property var sensorSnapshot: ({})
    property bool compact: width < 860

    signal settingsApplied()

    Connections {
        target: typeof backend !== "undefined" ? backend : null
        enabled: dialog.opened
        function onNotificationRaised(title, message) {
            if (title === "Sensor settings error")
                saveError.text = message
        }
    }

    function pick(keys, fallback) {
        for (let i = 0; i < keys.length; ++i) {
            const value = sensorSnapshot[keys[i]]
            if (value !== undefined && value !== null && value !== "")
                return value
        }
        return fallback
    }

    function fmtValue(value, suffix, decimals) {
        if (value === undefined || value === null || value === "") return "--"
        const n = Number(value)
        if (!isNaN(n))
            return (decimals >= 0 ? n.toFixed(decimals) : n.toString()) + suffix
        return value.toString() + suffix
    }

    function fmtLatency(value) {
        if (value === undefined || value === null || value === "" || Number(value) < 0) return "--"
        const n = Number(value)
        return n < 1 ? (n * 1000).toFixed(0) + " ms" : n.toFixed(2) + " s"
    }

    function statusColor(value) {
        const text = String(value || "").toLowerCase()
        if (text.indexOf("ok") >= 0 || text.indexOf("online") >= 0 || text.indexOf("connected") >= 0 || text === "1")
            return Theme.success
        if (text.indexOf("warn") >= 0 || text.indexOf("connecting") >= 0 || text.indexOf("unknown") >= 0)
            return Theme.warning
        if (text === "--" || text.length === 0)
            return Theme.mutedText
        return Theme.danger
    }

    function streamHealth() {
        return sensorSnapshot.stream_health || sensorSnapshot.mqtt_health || ({})
    }

    function streamStatus() {
        const health = streamHealth()
        return health.status || "Unknown"
    }

    function loadSettings() {
        deviceTab = false
        saveError.text = ""
        sensorSnapshot = typeof backend !== "undefined" ? (backend.getSensorData(sensorName, false) || ({})) : ({})
        deviceIdField.text = sensorSnapshot.device_id || ""
        streamForm.load(sensorSnapshot.profile || "nemosense", sensorSnapshot.streams || [], sensorSnapshot.acquisition || "")
        mapLat = Number(sensorSnapshot.gnss_lat || sensorSnapshot.GNSS_LAT || 0)
        mapLon = Number(sensorSnapshot.gnss_lon || sensorSnapshot.GNSS_LON || 0)
        if (mapLat === 0 && mapLon === 0) {
            mapLat = -6.917464
            mapLon = 107.619123
        }
        gnssMap.center = QtPositioning.coordinate(mapLat, mapLon)
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.98; to: 1; duration: 210; easing.type: Easing.OutCubic }
        }
    }

    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; to: 0; duration: 140 }
            NumberAnimation { property: "scale"; to: 0.98; duration: 140 }
        }
    }

    background: Rectangle {
        color: Theme.dialog
        radius: 14
        border.color: Theme.borderLight
        border.width: 1
    }

    Plugin { id: osmPlugin; name: "osm" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: dialog.compact ? 16 : 22
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 12
                color: Theme.accentSoft
                LucideIcon { anchors.centerIn: parent; icon: Icons.settings; size: Theme.iconSizeLarge; color: Theme.accent }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { text: pick(["name"], sensorName || I18n.t("sensorSettings.title", "Sensor settings")); color: Theme.text; font.pixelSize: 22; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                Text {
                    text: pick(["DEVICE_TYPE", "device_type"], I18n.t("sensorSettings.unknownDevice", "Unknown device")) + "  ·  " + pick(["device_id", "ID_MAC"], I18n.t("sensorSettings.pendingIdentity", "Pending identity"))
                    color: Theme.subText
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            StatusPill {
                text: dialog.streamStatus()
                iconText: Icons.signal
                accentColor: dialog.statusColor(dialog.streamStatus())
            }

            WinButton {
                iconName: Icons.cancel
                Accessible.name: I18n.t("common.close", "Close")
                isQuiet: true
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                onClicked: dialog.close()
            }
        }

        RowLayout {
            visible: (dialog.sensorSnapshot.profile || "").startsWith("beandevice_")
                     && dialog.sensorSnapshot.acquisition === "streaming"
            WinButton { text: "General"; isAccent: !dialog.deviceTab; onClicked: dialog.deviceTab = false }
            WinButton { text: "Device configuration"; isAccent: dialog.deviceTab; onClicked: { dialog.deviceTab = true; beanRate.model = []; backend.loadBeanRates(dialog.sensorName) } }
        }

        ScrollView {
            visible: dialog.deviceTab
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            GridLayout {
                id: beanControls
                width: parent.width
                columns: width >= 720 ? 2 : 1
                columnSpacing: 24
                rowSpacing: 20
                property int progress: -1
                property string downloadFeedback: ""

                Layout.fillWidth: true
                property bool pending: false
                property string feedback: ""
                property bool downloading: false

                Connections {
                    target: backend
                    function onBeanRatesLoaded(name, rates) {
                        if (name === dialog.sensorName)
                            beanRate.model = rates.map(rate => String(rate))
                    }
                    function onBeanDownloadProgress(name, percent) {
                        if (name === dialog.sensorName && beanControls.downloading)
                            beanControls.progress = Math.max(beanControls.progress, percent)
                    }
                    function onBeanDownloadFinished(name, saved, error) {
                        if (name !== dialog.sensorName) return
                        beanControls.downloading = false
                        beanControls.progress = saved ? 100 : -1
                        beanControls.downloadFeedback = saved ? "100% · Raw recording saved." : "Download failed. " + error
                    }
                    function onBeanCommandFinished(name, outcome) {
                        if (name !== dialog.sensorName)
                            return
                        beanControls.pending = false
                        beanControls.feedback = outcome === "queued"
                            ? I18n.t("sensorSettings.otacQueued", "Queued in Node-RED. Check the sensor’s reported sample rate.")
                            : I18n.t("sensorSettings.otacUnconfirmed", "Node-RED did not confirm queuing the request.")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    FieldLabel { labelText: I18n.t("sensorSettings.otacTitle", "Remote streaming configuration") }
                    FieldLabel { labelText: I18n.t("sensorSettings.otacRate", "Sample rate (Hz)") }
                    WinComboBox {
                        id: beanRate
                        Layout.fillWidth: true
                        model: []
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        visible: beanRate.count === 0
                        color: Theme.subText
                        text: "No sample rates loaded. Check the Node-RED allowlist."
                    }
                    FieldLabel { labelText: "Recording mode" }
                    WinComboBox {
                        id: beanMode
                        Layout.fillWidth: true
                        model: ["TX", "LOG", "TX & LOG", "SA"]
                    }
                    FieldLabel { visible: beanPattern.visible; labelText: "Streaming pattern" }
                    WinComboBox {
                        id: beanPattern
                        visible: beanMode.currentIndex !== 3
                        Layout.fillWidth: true
                        model: ["Continuous", "One shot", "Burst"]
                    }
                    WinComboBox {
                        id: beanForward
                        visible: beanMode.currentIndex === 0 || beanMode.currentIndex === 2
                        Layout.fillWidth: true
                        model: ["Store-and-forward off", "Store-and-forward on"]
                    }
                    FieldLabel { visible: beanCycle.visible; labelText: "Cycle (seconds)" }
                    WinTextField {
                        id: beanCycle
                        visible: beanMode.currentIndex === 3 || beanPattern.currentIndex === 2
                        text: "7200"
                        validator: IntValidator { bottom: 1; top: 16777215 }
                    }
                    FieldLabel { visible: beanDuration.visible; labelText: "Acquisition duration (seconds)" }
                    WinTextField {
                        id: beanDuration
                        visible: beanCycle.visible || beanPattern.currentIndex === 1
                        text: "60"
                        validator: IntValidator { bottom: 1; top: 16777215 }
                    }
                    WinButton {
                        enabled: !beanControls.pending && !beanControls.downloading && beanRate.currentIndex >= 0
                                 && (!beanDuration.visible || beanDuration.acceptableInput)
                                 && (!beanCycle.visible || (beanCycle.acceptableInput
                                     && Number(beanDuration.text) <= Number(beanCycle.text)))
                        text: I18n.t("sensorSettings.otacUpdate", "Update Sensor Config")
                        isAccent: true
                        onClicked: {
                            beanControls.pending = backend.applyBeanStreaming(
                                dialog.sensorName, Number(beanRate.currentText), ["tx", "log", "tx_log", "sa"][beanMode.currentIndex],
                                beanForward.visible && beanForward.currentIndex === 1,
                                Number(beanCycle.text), Number(beanDuration.text),
                                ["continuous", "one_shot", "burst"][beanPattern.currentIndex])
                            beanControls.feedback = beanControls.pending
                                ? I18n.t("sensorSettings.otacSending", "Sending to Node-RED…")
                                : I18n.t("sensorSettings.otacInvalid", "Check the saved device MAC ID and Node-RED address.")
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: beanControls.feedback
                        wrapMode: Text.WordWrap
                        color: Theme.subText
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    FieldLabel { labelText: "Stored recordings" }
                    FieldLabel { labelText: "Recording index" }
                    WinTextField {
                        id: recordingIndex
                        text: "0"
                        validator: IntValidator { bottom: 0; top: 65535 }
                    }
                    WinButton {
                        text: "Download raw recording"
                        enabled: !beanControls.pending && !beanControls.downloading
                                 && recordingIndex.acceptableInput
                        onClicked: recordingSave.open()
                    }
                    Platform.FileDialog {
                        id: recordingSave
                        fileMode: Platform.FileDialog.SaveFile
                        defaultSuffix: "beanframes"
                        onAccepted: {
                            beanControls.progress = -1
                            beanControls.downloading = backend.downloadBeanRecording(
                                dialog.sensorName, Number(recordingIndex.text), recordingSave.file)
                            beanControls.downloadFeedback = beanControls.downloading
                                ? "Downloading recording…" : "Could not start download."
                        }
                    }
                    ProgressBar {
                        id: downloadProgress
                        Layout.fillWidth: true
                        visible: beanControls.downloading || beanControls.progress === 100
                        from: 0
                        to: 100
                        value: Math.max(0, beanControls.progress)
                        indeterminate: beanControls.downloading && beanControls.progress < 0
                        Accessible.name: "Recording download progress"
                        background: Rectangle {
                            implicitHeight: 12
                            radius: 6
                            color: Theme.controlBg
                            border.color: Theme.border
                        }
                        contentItem: Item {
                            implicitHeight: 12
                            clip: true
                            Rectangle {
                                width: parent.width * (downloadProgress.indeterminate ? 0.25 : downloadProgress.visualPosition)
                                height: parent.height
                                radius: 6
                                color: beanControls.progress === 100 ? Theme.success : Theme.accent
                                SequentialAnimation on x {
                                    running: downloadProgress.visible && downloadProgress.indeterminate
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0; to: downloadProgress.availableWidth * 0.75; duration: 850 }
                                    NumberAnimation { to: 0; duration: 0 }
                                }
                                Binding on x {
                                    when: !downloadProgress.indeterminate
                                    value: 0
                                }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        visible: text.length > 0
                        color: Theme.subText
                        text: beanControls.downloading && beanControls.progress >= 0
                            ? "Downloading recording · " + beanControls.progress + "%"
                            : beanControls.downloadFeedback
                    }
                }
            }

        }

        ScrollView {
            visible: !dialog.deviceTab
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: parent.width
                spacing: 14

                GridLayout {
                    Layout.fillWidth: true
                    columns: dialog.width >= 980 ? 6 : (dialog.width >= 680 ? 3 : 2)
                    columnSpacing: 10
                    rowSpacing: 10

                    SummaryCard {
                        labelText: I18n.t("sensorSettings.nodeRedStream", "Node-RED stream")
                        valueText: dialog.streamStatus()
                        captionText: pick(["device_id"], I18n.t("sensorSettings.noDeviceId", "No device_id"))
                        iconText: Icons.nodeRed
                        accentColor: dialog.statusColor(valueText)
                    }
                    SummaryCard {
                        labelText: I18n.t("sensor.battery", "Battery")
                        valueText: fmtValue(pick(["BATTERY", "battery"], null), " %", 1)
                        captionText: pick(["BAT_CHARGER_STATUS_LABEL", "BATTERY_CHARGER_LABEL"], I18n.t("sensorSettings.chargerUnknown", "Charger unknown"))
                        iconText: Icons.battery
                        accentColor: Number(pick(["BATTERY", "battery"], 0)) >= 20 ? Theme.success : Theme.warning
                    }
                    SummaryCard {
                        labelText: I18n.t("sensor.signal", "Signal")
                        valueText: fmtValue(pick(["CELLULAR_RSSI"], null), " dBm", 0)
                        captionText: pick(["SIGNAL_STRENGTH_LABEL", "signal_strength_label"], I18n.t("sensorSettings.noLabel", "No label"))
                        iconText: Icons.signal
                        accentColor: Theme.info
                    }
                    SummaryCard {
                        labelText: I18n.t("sensor.sampleRate", "Sample rate")
                        valueText: fmtValue(pick(["inferred_sample_rate", "INFERRED_SAMPLE_RATE", "INFERED_SAMPLE_RATE", "sample_rate"], null), " Hz", 1)
                        captionText: I18n.t("sensorSettings.inferred", "Inferred from telemetry")
                        iconText: Icons.sampleRate
                        accentColor: Theme.info
                    }
                    SummaryCard {
                        labelText: I18n.t("sensorSettings.dataLatency", "Data latency")
                        valueText: fmtLatency(pick(["DATA_LATENCY_SECONDS"], null))
                        captionText: I18n.t("sensorSettings.deviceToStorage", "Device to storage")
                        iconText: Icons.sync
                        accentColor: Theme.warning
                    }
                    SummaryCard {
                        labelText: I18n.t("sensorSettings.lostSamples", "Lost samples")
                        valueText: fmtValue(pick(["ACC_LOST_SAMPLES_COUNT"], null), "", 0)
                        captionText: I18n.t("sensorSettings.accelerometerCounter", "Accelerometer counter")
                        iconText: Icons.chart
                        accentColor: Number(pick(["ACC_LOST_SAMPLES_COUNT"], 0)) > 0 ? Theme.danger : Theme.success
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: dialog.compact ? 1 : 2
                    columnSpacing: 14
                    rowSpacing: 14

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 14

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: connectionContent.implicitHeight + 30
                            radius: 11
                            color: Theme.card
                            border.color: Theme.border

                            ColumnLayout {
                                id: connectionContent
                                anchors.fill: parent
                                anchors.margins: 15
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: I18n.t("sensorSettings.connection", "Node-RED identity mapping"); color: Theme.text; font.pixelSize: 17; font.bold: true; Layout.fillWidth: true }
                                    LucideIcon { icon: Icons.nodeRed; color: Theme.accent; size: Theme.iconSizeSmall }
                                }
                                Text {
                                    text: I18n.t("sensorSettings.connectionHelpNodeRed", "Match device_id to the canonical JSON and the WebSocket path to this sensor's dedicated Node-RED listener. MQTT, credentials, subscriptions, and Sparkplug processing remain in Node-RED.")
                                    color: Theme.subText
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                FieldLabel { labelText: I18n.t("sensorSettings.nodeRedDeviceId", "Node-RED device_id") }
                                WinTextField { id: deviceIdField; Layout.fillWidth: true; placeholderText: "NEMOSENSE-01" }
                                SensorStreams {
                                    id: streamForm
                                    Layout.fillWidth: true
                                    profiles: typeof backend !== "undefined" && backend ? backend.sensorProfiles() : ({})
                                    deviceId: deviceIdField.text
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: identityContent.implicitHeight + 30
                            radius: 11
                            color: Theme.card
                            border.color: Theme.border

                            ColumnLayout {
                                id: identityContent
                                anchors.fill: parent
                                anchors.margins: 15
                                spacing: 9
                                Text { text: I18n.t("sensorSettings.identity", "Device identity"); color: Theme.text; font.pixelSize: 17; font.bold: true }
                                DataRow { labelText: I18n.t("sensorSettings.deviceId", "Device ID"); valueText: pick(["device_id", "ID_MAC"], "--") }
                                DataRow { labelText: I18n.t("sensorSettings.deviceType", "Device type"); valueText: pick(["DEVICE_TYPE", "device_type"], "--") }
                                DataRow { labelText: I18n.t("sensorSettings.firmware", "Firmware"); valueText: pick(["ID_FW_VERSION"], "--") }
                                DataRow { labelText: I18n.t("sensorSettings.mac", "MAC address"); valueText: pick(["ID_MAC"], "--") }
                                DataRow { labelText: I18n.t("sensorSettings.batteryPack", "Battery pack"); valueText: pick(["BATTERY_PACK_SERIAL"], "--") }
                                DataRow { labelText: I18n.t("sensorSettings.powerSource", "Power source"); valueText: pick(["POWER_SOURCE_LABEL"], "--") }
                                DataRow { labelText: I18n.t("sensorSettings.ntpStatus", "NTP status"); valueText: pick(["NTP_STATUS"], "--") }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: metricsText.implicitHeight + 70
                            radius: 11
                            color: Theme.card
                            border.color: Theme.border

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 15
                                spacing: 8
                                Text { text: I18n.t("sensorSettings.metrics", "Active telemetry metrics"); color: Theme.text; font.pixelSize: 17; font.bold: true }
                                Text {
                                    id: metricsText
                                    Layout.fillWidth: true
                                    text: {
                                        const metrics = dialog.pick(["active_metrics"], [])
                                        return metrics.length > 0 ? metrics.join("  ·  ") : "No telemetry has been stored for this sensor yet."
                                    }
                                    color: Theme.subText
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 14

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 360
                            radius: 11
                            color: Theme.card
                            border.color: Theme.border
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 54
                                    Layout.leftMargin: 14
                                    Layout.rightMargin: 14
                                    spacing: 10
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text { text: I18n.t("sensorSettings.gnss", "Reported GNSS position"); color: Theme.text; font.pixelSize: 17; font.bold: true }
                                        Text { text: dialog.mapLat.toFixed(6) + ", " + dialog.mapLon.toFixed(6); color: Theme.subText; font.pixelSize: 11; font.family: "monospace" }
                                    }
                                    Text { text: I18n.t("sensorSettings.relocate", "Double-click to relocate"); color: Theme.mutedText; font.pixelSize: 10 }
                                }

                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.divider }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    Map {
                                        id: gnssMap
                                        anchors.fill: parent
                                        plugin: osmPlugin
                                        center: QtPositioning.coordinate(dialog.mapLat, dialog.mapLon)
                                        zoomLevel: 16
                                        minimumZoomLevel: 2
                                        maximumZoomLevel: 20

                                        MapQuickItem {
                                            id: mapPinItem
                                            coordinate: QtPositioning.coordinate(dialog.mapLat, dialog.mapLon)
                                            anchorPoint.x: mapPin.width / 2
                                            anchorPoint.y: mapPin.height
                                            sourceItem: Item {
                                                id: mapPin
                                                width: 40
                                                height: 50
                                                Rectangle {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: 36
                                                    height: 36
                                                    radius: 18
                                                    color: Theme.accent
                                                    border.color: "white"
                                                    border.width: 3
                                                    LucideIcon { anchors.centerIn: parent; icon: Icons.location; color: Theme.accentText; size: Theme.iconSizeSmall }
                                                }
                                                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: 32; width: 10; height: 10; rotation: 45; color: Theme.accent }
                                            }
                                        }

                                        WheelHandler {
                                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                            onWheel: function(event) {
                                                gnssMap.zoomLevel = Math.max(gnssMap.minimumZoomLevel,
                                                                             Math.min(gnssMap.maximumZoomLevel,
                                                                                      gnssMap.zoomLevel + (event.angleDelta.y > 0 ? 0.75 : -0.75)))
                                            }
                                        }

                                        DragHandler {
                                            target: null
                                            acceptedButtons: Qt.LeftButton
                                            property real lastX: 0
                                            property real lastY: 0
                                            onActiveChanged: if (active) { lastX = translation.x; lastY = translation.y }
                                            onTranslationChanged: {
                                                if (!active) return
                                                const dx = translation.x - lastX
                                                const dy = translation.y - lastY
                                                gnssMap.pan(Math.round(-dx), Math.round(-dy))
                                                lastX = translation.x
                                                lastY = translation.y
                                            }
                                        }

                                        PinchHandler {
                                            target: null
                                            property real startZoom: 0
                                            onActiveChanged: if (active) startZoom = gnssMap.zoomLevel
                                            onScaleChanged: if (active) gnssMap.zoomLevel = Math.max(gnssMap.minimumZoomLevel, Math.min(gnssMap.maximumZoomLevel, startZoom + Math.log(scale) / Math.log(2)))
                                        }

                                        TapHandler {
                                            acceptedButtons: Qt.LeftButton
                                            onDoubleTapped: function(eventPoint) {
                                                const coord = gnssMap.toCoordinate(eventPoint.position)
                                                dialog.mapLat = coord.latitude
                                                dialog.mapLon = coord.longitude
                                            }
                                        }
                                    }

                                    Column {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 10
                                        spacing: 5
                                        MapButton { iconText: Icons.plus; tip: "Zoom in"; onClicked: gnssMap.zoomLevel = Math.min(gnssMap.maximumZoomLevel, gnssMap.zoomLevel + 1) }
                                        MapButton { iconText: Icons.minus; tip: "Zoom out"; onClicked: gnssMap.zoomLevel = Math.max(gnssMap.minimumZoomLevel, gnssMap.zoomLevel - 1) }
                                        MapButton { iconText: Icons.pinPoint; tip: "Center on sensor"; onClicked: gnssMap.center = QtPositioning.coordinate(dialog.mapLat, dialog.mapLon) }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: diagnosticsContent.implicitHeight + 30
                            radius: 11
                            color: Theme.card
                            border.color: Theme.border

                            ColumnLayout {
                                id: diagnosticsContent
                                anchors.fill: parent
                                anchors.margins: 15
                                spacing: 9
                                Text { text: I18n.t("sensorSettings.diagnostics", "Pipeline diagnostics"); color: Theme.text; font.pixelSize: 17; font.bold: true }
                                DataRow { labelText: I18n.t("sensorSettings.bridgeState", "Node-RED bridge state"); valueText: dialog.streamStatus() }
                                DataRow { labelText: I18n.t("sensorSettings.endpointConnected", "Stream connected"); valueText: dialog.streamHealth().connected ? I18n.t("common.yes", "Yes") : I18n.t("common.no", "No") }
                                DataRow { labelText: I18n.t("sensorSettings.normalizedDevice", "Normalized device_id"); valueText: pick(["device_id"], "--") }
                                Repeater {
                                    model: dialog.sensorSnapshot.streams || []
                                    DataRow {
                                        required property var modelData
                                        labelText: modelData.metric || I18n.t("sensorSettings.websocketEndpoint", "WebSocket path")
                                        valueText: modelData.path + " · " + (modelData.connected
                                            ? I18n.t("sensorStreams.connected", "Connected")
                                            : I18n.t("sensorStreams.offline", "Offline"))
                                            + (modelData.value === null || modelData.value === undefined
                                                ? "" : " · " + String(modelData.value))
                                    }
                                }
                                DataRow { labelText: I18n.t("sensorSettings.pipelineError", "Last pipeline error"); valueText: dialog.streamHealth().last_error || I18n.t("common.none", "None") }
                            }
                        }
                    }
                }
            }
        }

        Text {
            id: saveError
            Layout.fillWidth: true
            visible: text.length > 0
            color: Theme.danger
            wrapMode: Text.WordWrap
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.divider }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: I18n.t("sensorSettings.footerNodeRed", "Each sensor uses one dedicated WebSocket path carrying all of its normalized metrics.")
                color: Theme.mutedText
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            WinButton { text: I18n.t("common.cancel", "Cancel"); Layout.preferredWidth: 94; onClicked: dialog.close() }
            WinButton {
                iconName: Icons.save; text: I18n.t("sensorSettings.apply", "Apply settings")
                isAccent: true
                Layout.preferredWidth: 142
                enabled: deviceIdField.text.trim().length > 0
                onClicked: {
                    saveError.text = ""
                    const success = typeof backend !== "undefined"
                        ? backend.updateProfileSensor(sensorName, deviceIdField.text.trim(), streamForm.profile, streamForm.values(), dialog.mapLat, dialog.mapLon, streamForm.acquisition)
                        : false
                    if (success) {
                        dialog.settingsApplied()
                        dialog.close()
                    }
                }
            }
        }
    }
}
