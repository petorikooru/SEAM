import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform 1.1
import QtPositioning

import "../"
import "../common"
import "../dialogs"
import "../components/sensor"

Item {
    id: page

    property string sensorName: I18n.t("sensor.unknown", "Unknown Sensor")
    property var sensorData: ({})
    property bool isEditing: false
    readonly property bool splitStreams: !!sensorData.profile && sensorData.profile !== "nemosense"
    readonly property var streamMetrics: sensorData.profile_metrics || []
    readonly property bool hasAcceleration: !splitStreams || ["ACC/X", "ACC/Y", "ACC/Z"].some(metric => streamMetrics.includes(metric))
    readonly property bool hasInclination: !splitStreams || ["ACC/ROLL", "ACC/PITCH"].some(metric => streamMetrics.includes(metric))

    property real mapLat: -6.917464
    property real mapLon: 107.619123

    property string liveTemp: "-- °C"
    property string liveBattery: "-- %"
    property string liveSampleRate: "-- Hz"
    property string liveRssi: "-- dBm"
    property string liveSignalLabel: "lost"
    property string liveChargerStatus: "unknown"
    property string livePowerSource: "--"
    property string liveMqttDeviceStatus: "unknown"
    property string liveNtpStatus: "unknown"
    property string liveLostSamples: "--"
    property string liveDataLatency: "--"
    property string liveDeviceType: "Dewesoft Nemosense"

    property bool inclPanMode: true
    property bool accelPanMode: true
    property bool isFrozen: false

    onIsFrozenChanged: {
        if (typeof backend !== "undefined")
            backend.setLiveChartsPaused(isFrozen)
        accelChart.frozen = isFrozen
        inclinoChart.frozen = isFrozen
        if (isFrozen)
            freezeAdjustTimer.restart()
        else {
            accelChart.resetView()
            inclinoChart.resetView()
        }
    }

    Timer {
        id: freezeAdjustTimer
        interval: 10
        repeat: false
        onTriggered: {
            accelChart.adjustFrozenRange()
            inclinoChart.adjustFrozenRange()
        }
    }

    Connections {
        target: typeof backend !== "undefined" ? backend : null

        function onIndicatorsUpdated(data) {
            if (data["device_id"] !== page.sensorName)
                return

            page.updateLiveMetrics(data, false)

            let mapNeedsUpdate = false
            if (data["GNSS_LAT"] !== undefined) { page.mapLat = Number(data["GNSS_LAT"]); mapNeedsUpdate = true }
            if (data["GNSS_LON"] !== undefined) { page.mapLon = Number(data["GNSS_LON"]); mapNeedsUpdate = true }
            if (mapNeedsUpdate)
                sensorMapCard.map.center = QtPositioning.coordinate(page.mapLat, page.mapLon)
        }
    }

    Component.onCompleted: {
        if (typeof backend !== "undefined")
            backend.setLiveChartsPaused(false)
    }

    Component.onDestruction: {
        if (typeof backend !== "undefined") {
            backend.setLiveChartsPaused(false)
            if (page.sensorName !== "")
                backend.registerLiveCharts(page.sensorName, null, null, null, null, null)
        }
    }

    function metricValue(data, keys) {
        if (!data) return undefined
        for (let i = 0; i < keys.length; ++i) {
            const value = data[keys[i]]
            if (value !== undefined && value !== null && value !== "")
                return value
        }
        return undefined
    }

    function formatMetric(value, decimals, suffix, fallback) {
        const numeric = Number(value)
        return isFinite(numeric) ? numeric.toFixed(decimals) + suffix : fallback
    }

    function resetLiveMetrics() {
        liveTemp = "-- °C"
        liveBattery = "-- %"
        liveSampleRate = "-- Hz"
        liveRssi = "-- dBm"
        liveSignalLabel = "lost"
        liveChargerStatus = "unknown"
        livePowerSource = "--"
        liveMqttDeviceStatus = "unknown"
        liveNtpStatus = "unknown"
        liveLostSamples = "--"
        liveDataLatency = "--"
    }

    function updateLiveMetrics(data, replaceMissing) {
        if (!data) return
        const temp = metricValue(data, ["ACC/TEMPERATURE", "TEMPERATURE", "temp", "temperature"])
        const battery = metricValue(data, ["BATTERY", "BAT_FUEL_GAUGE_REPSOC", "battery"])
        const rssi = metricValue(data, ["CELLULAR_RSSI", "SIGNAL", "RSSI", "cellular_rssi"])
        const sampleRate = metricValue(data, ["INFERRED_SAMPLE_RATE", "INFERED_SAMPLE_RATE", "inferred_sample_rate", "infered_sample_rate", "sample_rate"])

        if (temp !== undefined) liveTemp = formatMetric(temp, 2, " °C", liveTemp)
        else if (replaceMissing) liveTemp = "-- °C"
        if (battery !== undefined) liveBattery = formatMetric(battery, 1, " %", liveBattery)
        else if (replaceMissing) liveBattery = "-- %"
        if (rssi !== undefined) liveRssi = formatMetric(rssi, 0, " dBm", liveRssi)
        else if (replaceMissing) liveRssi = "-- dBm"
        if (sampleRate !== undefined) liveSampleRate = formatMetric(sampleRate, 1, " Hz", liveSampleRate)
        else if (replaceMissing) liveSampleRate = "-- Hz"

        const signalLabel = metricValue(data, ["SIGNAL_STRENGTH_LABEL", "signal_strength_label"])
        if (signalLabel !== undefined) liveSignalLabel = String(signalLabel)
        const charger = metricValue(data, ["BAT_CHARGER_STATUS_LABEL", "BATTERY_CHARGER_LABEL"])
        if (charger !== undefined) liveChargerStatus = String(charger)
        const power = metricValue(data, ["POWER_SOURCE_LABEL"])
        if (power !== undefined) livePowerSource = String(power)
        const mqtt = metricValue(data, ["MQTT_DEVICE_STATUS"])
        if (mqtt !== undefined) liveMqttDeviceStatus = String(mqtt)
        else if (data["MQTT_IS_CONNECTION_OK"] !== undefined) liveMqttDeviceStatus = Number(data["MQTT_IS_CONNECTION_OK"]) === 1 ? "ok" : "down"
        const ntp = metricValue(data, ["NTP_STATUS"])
        if (ntp !== undefined) liveNtpStatus = String(ntp)
        else if (data["NTP_IS_CONNECTION_OK"] !== undefined) liveNtpStatus = Number(data["NTP_IS_CONNECTION_OK"]) === 1 ? "ok" : "down"
        if (data["ACC_LOST_SAMPLES_COUNT"] !== undefined) liveLostSamples = formatMetric(data["ACC_LOST_SAMPLES_COUNT"], 0, "", liveLostSamples)
        if (data["DATA_LATENCY_SECONDS"] !== undefined && Number(data["DATA_LATENCY_SECONDS"]) >= 0) {
            const latency = Number(data["DATA_LATENCY_SECONDS"])
            liveDataLatency = latency < 1 ? (latency * 1000).toFixed(0) + " ms" : latency.toFixed(2) + " s"
        }
        if (data["DEVICE_TYPE"] !== undefined && data["DEVICE_TYPE"] !== "") liveDeviceType = data["DEVICE_TYPE"]
    }

    function loadSensorMeta() {
        sensorData = typeof backend !== "undefined" ? (backend.getSensorData(sensorName) || ({})) : ({})
        mapLat = Number(sensorData.gnss_lat || sensorData.GNSS_LAT || -6.917464)
        mapLon = Number(sensorData.gnss_lon || sensorData.GNSS_LON || 107.619123)

        resetLiveMetrics()
        updateLiveMetrics(sensorData, true)
        liveDeviceType = sensorData["DEVICE_TYPE"] || sensorData.device_type || liveDeviceType
        sensorMapCard.recenter()
    }

    function registerCharts() {
        if (typeof backend === "undefined")
            return
        backend.registerLiveCharts(
            sensorName,
            accelChart.seriesAt(0),
            accelChart.seriesAt(1),
            accelChart.seriesAt(2),
            inclinoChart.seriesAt(0),
            inclinoChart.seriesAt(1)
        )
    }

    function loadData() {
        loadSensorMeta()
        renderTimer.restart()
    }

    Timer {
        id: renderTimer
        interval: 30
        repeat: false
        onTriggered: page.registerCharts()
    }

    Timer {
        id: lazyLoadTimer
        interval: 20
        running: true
        repeat: false
        onTriggered: page.loadData()
    }

    onSensorNameChanged: {
        isFrozen = false
        accelChart.clearSeries()
        inclinoChart.clearSeries()
        lazyLoadTimer.restart()
    }

    Popup {
        id: exportOptionsDialog
        width: 420
        height: 250
        modal: true
        dim: true
        anchors.centerIn: Overlay.overlay
        background: Rectangle { color: Theme.card; radius: 12; border.color: Theme.border }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            anchors.bottomMargin: 32
            spacing: 16

            Text {
                text: I18n.format("sensor.exportTitle", {"sensor": sensorData.name || page.sensorName}, "Export " + (sensorData.name || page.sensorName))
                font.pixelSize: 20
                font.bold: true
                color: Theme.text
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: I18n.t("sensor.exportHelp", "Select the time range to export for this sensor.")
                color: Theme.subText
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            ComboBox {
                id: exportRangeComboDialog
                Layout.fillWidth: true
                font.pixelSize: 14
                model: [I18n.t("ranges.hour", "Last 1 Hour"), I18n.t("ranges.day", "Last 24 Hours"), I18n.t("ranges.week", "Last 7 Days"), I18n.t("ranges.all", "All Data")]
                currentIndex: 1
                background: Rectangle { color: Theme.controlBg; radius: 6; border.color: exportRangeComboDialog.activeFocus ? Theme.accent : Theme.border; border.width: exportRangeComboDialog.activeFocus ? 2 : 1 }
                contentItem: Text { text: exportRangeComboDialog.displayText; color: Theme.text; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter; leftPadding: 12 }
                delegate: ItemDelegate {
                    width: exportRangeComboDialog.width
                    contentItem: Text { text: modelData; color: Theme.text; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { color: exportRangeComboDialog.highlightedIndex === index ? Theme.controlHover : "transparent"; radius: 4 }
                }
                popup: Popup {
                    y: exportRangeComboDialog.height + 4
                    width: exportRangeComboDialog.width
                    padding: 4
                    background: Rectangle { color: Theme.dialog; border.color: Theme.border; radius: 6 }
                    contentItem: ListView { clip: true; implicitHeight: contentHeight; model: exportRangeComboDialog.popup.visible ? exportRangeComboDialog.delegateModel : null; currentIndex: exportRangeComboDialog.highlightedIndex }
                }
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Item { Layout.fillWidth: true }
                WinButton { text: I18n.t("common.cancel", "Cancel"); onClicked: exportOptionsDialog.close() }
                WinButton { text: I18n.t("common.chooseExport", "Choose File & Export"); isAccent: true; onClicked: { exportOptionsDialog.close(); exportFileDialog.open() } }
            }
        }
    }

    FileDialog {
        id: exportFileDialog
        title: I18n.t("sensor.saveCsv", "Save Exported CSV")
        fileMode: FileDialog.SaveFile
        nameFilters: ["CSV files (*.csv)"]
        onAccepted: {
            let filepath = selectedFile.toString().replace("file://", "")
            if (Qt.platform.os === "windows" && filepath.startsWith("/")) filepath = filepath.substring(1)
            const now = Date.now() / 1000
            let startTime = 0
            switch (exportRangeComboDialog.currentIndex) {
                case 0: startTime = now - 3600; break
                case 1: startTime = now - 24 * 3600; break
                case 2: startTime = now - 7 * 24 * 3600; break
                default: startTime = 0; break
            }
            if (typeof backend !== "undefined")
                backend.exportSensorData(filepath, page.sensorName, startTime, 0)
        }
    }

    ScrollView {
        id: sensorScroll
        objectName: "sensorScroll"
        anchors.fill: parent
        anchors.margins: 24
        anchors.rightMargin: 0
        rightPadding: 24
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: parent.width
            height: Math.max(implicitHeight, sensorScroll.availableHeight)
            spacing: 16

            GridLayout {
                id: sensorIdentityMapGrid
                objectName: "sensorIdentityMapGrid"
                Layout.fillWidth: true
                columns: width >= 960 ? 2 : 1
                columnSpacing: 16
                rowSpacing: 16

                SensorHeaderCard {
                    id: sensorHeaderCard
                    objectName: "sensorHeaderCardInstance"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 340
                    Layout.minimumHeight: 320
                    Layout.alignment: Qt.AlignTop
                    sensorName: page.sensorName
                    sensorData: page.sensorData
                    editing: page.isEditing
                    onEditRequested: page.isEditing = true
                    onSettingsRequested: {
                        advancedSettingsDialog.sensorName = page.sensorName
                        advancedSettingsDialog.loadSettings()
                        advancedSettingsDialog.open()
                    }
                    onHistoryRequested: historyChartDialog.openHistory(page.sensorName)
                    onExportRequested: exportOptionsDialog.open()
                    onDeleteRequested: {
                        if (typeof backend !== "undefined")
                            backend.deleteSensor(page.sensorName)
                        if (typeof root !== "undefined")
                            root.activePage = "dashboard"
                        if (typeof mainStack !== "undefined")
                            mainStack.replace("Dashboard.qml")
                    }
                    onCancelRequested: {
                        page.isEditing = false
                        page.loadSensorMeta()
                    }
                    onSaveRequested: (newName, newDescription) => {
                        if (typeof backend === "undefined")
                            return
                        const success = backend.updateSensorMeta(page.sensorName, newName, newDescription)
                        if (success) {
                            page.sensorName = newName
                            page.isEditing = false
                            page.loadData()
                        }
                    }
                }

                SensorMapCard {
                    id: sensorMapCard
                    objectName: "sensorMapCardInstance"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 340
                    Layout.minimumHeight: 320
                    latitude: page.mapLat
                    longitude: page.mapLon
                }
            }

            SensorMetricsGrid {
                id: sensorMetricsGrid
                objectName: "sensorMetricsGrid"
                Layout.fillWidth: true
                temperature: page.liveTemp
                battery: page.liveBattery
                sampleRate: page.liveSampleRate
                signalLabel: page.liveSignalLabel
                rssi: page.liveRssi
                chargerStatus: page.liveChargerStatus
                powerSource: page.livePowerSource
                mqttStatus: page.liveMqttDeviceStatus
                ntpStatus: page.liveNtpStatus
                lostSamples: page.liveLostSamples
                latency: page.liveDataLatency
                onBatteryHistoryRequested: historyChartDialog.openBattery(page.sensorName)
            }

            GridLayout {
                id: motionChartsGrid
                objectName: "motionChartsGrid"
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: page.hasAcceleration || page.hasInclination
                Layout.minimumHeight: columns === 2 || !page.hasAcceleration || !page.hasInclination ? 520 : 1056
                columns: width >= 980 ? 2 : 1
                columnSpacing: 16
                rowSpacing: 16

                MotionChartPanel {
                    id: accelPanel
                    visible: page.hasAcceleration
                    Layout.columnSpan: page.hasInclination ? 1 : motionChartsGrid.columns
                    objectName: "accelPanel"
                    titleText: I18n.t("sensor.accelerometer", "Accelerometer")
                    subtitleText: I18n.t("sensor.accelerometerHelp", "Three-axis acceleration")
                    iconText: Icons.chart
                    iconColor: Theme.info
                    frozen: page.isFrozen
                    panMode: page.accelPanMode
                    seriesModel: [
                        {"label": "X", "color": Theme.axisX, "visible": true},
                        {"label": "Y", "color": Theme.axisY, "visible": true},
                        {"label": "Z", "color": Theme.axisZ, "visible": true}
                    ]
                    onFreezeToggled: page.isFrozen = !page.isFrozen
                    onPanModeToggled: page.accelPanMode = !page.accelPanMode
                    onResetRequested: accelChart.resetView()
                    onSeriesToggled: (index, checked) => accelChart.setSeriesVisible(index, checked)

                    MotionChart {
                        id: accelChart
                        anchors.fill: parent
                        frozen: page.isFrozen
                        panMode: page.accelPanMode
                        yAxisTitle: I18n.t("sensor.accelAxis", "Accel (g)")
                        defaultYMin: -2
                        defaultYMax: 2
                        initialXMax: 60
                        seriesDefinitions: [
                            {"name": "X Axis", "color": Theme.axisX},
                            {"name": "Y Axis", "color": Theme.axisY},
                            {"name": "Z Axis", "color": Theme.axisZ}
                        ]
                    }
                }

                MotionChartPanel {
                    id: inclinoPanel
                    visible: page.hasInclination
                    Layout.columnSpan: page.hasAcceleration ? 1 : motionChartsGrid.columns
                    objectName: "inclinoPanel"
                    titleText: I18n.t("sensor.inclinometer", "Inclinometer")
                    subtitleText: I18n.t("sensor.inclinometerHelp", "Pitch and roll angles")
                    iconText: Icons.pinPoint
                    iconColor: Theme.warning
                    frozen: page.isFrozen
                    panMode: page.inclPanMode
                    seriesModel: [
                        {"label": "Pitch", "color": Theme.pitch, "visible": true},
                        {"label": "Roll", "color": Theme.roll, "visible": true}
                    ]
                    onFreezeToggled: page.isFrozen = !page.isFrozen
                    onPanModeToggled: page.inclPanMode = !page.inclPanMode
                    onResetRequested: inclinoChart.resetView()
                    onSeriesToggled: (index, checked) => inclinoChart.setSeriesVisible(index, checked)

                    MotionChart {
                        id: inclinoChart
                        anchors.fill: parent
                        frozen: page.isFrozen
                        panMode: page.inclPanMode
                        yAxisTitle: I18n.t("sensor.angleAxis", "Angle (°)")
                        defaultYMin: -90
                        defaultYMax: 90
                        initialXMax: 60
                        seriesDefinitions: [
                            {"name": "Pitch", "color": Theme.pitch},
                            {"name": "Roll", "color": Theme.roll}
                        ]
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 24 }
        }
    }

    HistoryChartDialog { id: historyChartDialog }
    SensorSettings {
        id: advancedSettingsDialog
        objectName: "advancedSettingsDialog"
        onSettingsApplied: page.loadData()
    }
}
