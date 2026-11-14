import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning

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

    property string sensorName: ""
    property real mapLat: 0
    property real mapLon: 0
    property var sensorSnapshot: ({})
    property bool compact: width < 860

    signal settingsApplied()

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
        sensorSnapshot = typeof backend !== "undefined" ? (backend.getSensorData(sensorName) || ({})) : ({})
        deviceIdField.text = sensorSnapshot.device_id || ""
        websocketEndpointField.text = sensorSnapshot.websocket_endpoint || ""
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
                Text { anchors.centerIn: parent; text: Icons.settings; font.family: Icons.fontFamily; font.pixelSize: Theme.iconSizeLarge; color: Theme.accent }
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
                text: Icons.cancel
                isQuiet: true
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                onClicked: dialog.close()
            }
        }

        ScrollView {
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
                                    Text { text: Icons.nodeRed; font.family: Icons.fontFamily; color: Theme.accent; font.pixelSize: Theme.iconSizeSmall }
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
                                FieldLabel { labelText: I18n.t("sensorSettings.websocketEndpoint", "Dedicated WebSocket path") }
                                WinTextField { id: websocketEndpointField; Layout.fillWidth: true; placeholderText: "kai/sensors/nemosense-01" }
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
                                                    Text { anchors.centerIn: parent; text: Icons.location; font.family: Icons.fontFamily; color: Theme.accentText; font.pixelSize: Theme.iconSizeSmall }
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
                                DataRow { labelText: I18n.t("sensorSettings.websocketEndpoint", "WebSocket path"); valueText: pick(["websocket_endpoint"], "--") }
                                DataRow { labelText: I18n.t("sensorSettings.pipelineError", "Last pipeline error"); valueText: dialog.streamHealth().last_error || I18n.t("common.none", "None") }
                            }
                        }
                    }
                }
            }
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
                text: Icons.save + "  " + I18n.t("sensorSettings.apply", "Apply settings")
                isAccent: true
                Layout.preferredWidth: 142
                enabled: deviceIdField.text.trim().length > 0 && websocketEndpointField.text.trim().length > 0
                onClicked: {
                    const success = typeof backend !== "undefined"
                        ? backend.updateNodeRedSensorSettings(sensorName, deviceIdField.text.trim(), websocketEndpointField.text.trim(), dialog.mapLat, dialog.mapLon)
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
