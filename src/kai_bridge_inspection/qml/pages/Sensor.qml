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
    property string liveSignalLabel: "Not Available"
    property string liveChargerStatus: "Not Available"
    property string livePowerSource: "--"
    property string liveMqttDeviceStatus: "Not Available"
    property string liveNtpStatus: "Not Available"
    property string liveLostSamples: "--"
    property string liveDataLatency: "--"
    property string liveDeviceType: "Sensor"

    readonly property int liveExpiryMs: 15000
    property var liveReadings: Object.create(null)

    function expireReadings(now) {
        let expired = false
        const current = Object.create(null)
        for (const key of Object.keys(liveReadings)) {
            const reading = liveReadings[key]
            if (now - reading.receivedAt >= liveExpiryMs) {
                delete liveReadings[key]
                expired = true
            } else {
                current[key] = reading.value
            }
        }
        if (expired) {
            resetLiveMetrics()
            updateLiveMetrics(current, true)
        }
    }

    property double monitoringStartedAt: Date.now()
    property double accelReceivedAt: 0
    property double inclineReceivedAt: 0
    property double freshnessNow: Date.now()

    Timer {
        interval: 1000
        running: page.visible
        repeat: true
        onTriggered: {
            page.freshnessNow = Date.now()
            page.expireReadings(page.freshnessNow)
        }
    }

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

            const receivedAt = Date.now()
            if (["ACC/X", "ACC/Y", "ACC/Z"].some(key => typeof data[key] === "number" && isFinite(data[key])))
                page.accelReceivedAt = receivedAt
            if (["ACC/ROLL", "ACC/PITCH"].some(key => typeof data[key] === "number" && isFinite(data[key])))
                page.inclineReceivedAt = receivedAt
            page.freshnessNow = receivedAt
            for (const key of Object.keys(data))
                page.liveReadings[key] = {value: data[key], receivedAt: receivedAt}
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
            backend.setHistoryVisible(false)
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
        liveSignalLabel = "Not Available"
        liveChargerStatus = "Not Available"
        livePowerSource = "--"
        liveMqttDeviceStatus = "Not Available"
        liveNtpStatus = "Not Available"
        liveLostSamples = "--"
        liveDataLatency = "--"
    }

    function updateLiveMetrics(data, replaceMissing) {
        if (!data) return
        auxiliaryGrid.updateValues(data, replaceMissing)
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
        sensorData = typeof backend !== "undefined" ? (backend.getSensorData(sensorName, false) || ({})) : ({})
        mapLat = Number(sensorData.gnss_lat || sensorData.GNSS_LAT || -6.917464)
        mapLon = Number(sensorData.gnss_lon || sensorData.GNSS_LON || 107.619123)

        resetLiveMetrics()
        const current = Object.create(null)
        for (const key of Object.keys(liveReadings))
            current[key] = liveReadings[key].value
        updateLiveMetrics(current, true)
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
        liveReadings = Object.create(null)
        resetLiveMetrics()
        auxiliaryGrid.updateValues({}, true)
        freshnessNow = Date.now()
        monitoringStartedAt = freshnessNow
        accelReceivedAt = 0
        inclineReceivedAt = 0
        isFrozen = false
        accelChart.clearSeries()
        inclinoChart.clearSeries()
        lazyLoadTimer.restart()
    }

    Popup {
        id: exportOptionsDialog
        objectName: "exportOptionsDialog"
        width: Math.min(460, parent.width - 32)
        padding: 24
        modal: true
        focus: true
        anchors.centerIn: Overlay.overlay
        background: Rectangle { color: Theme.dialog; radius: 12; border.color: Theme.border }

        property double startSeconds: 0
        property double endSeconds: 0
        property string feedback: ""
        readonly property string dateTimeFormat: "yyyy-MM-dd HH:mm:ss"

        function parseLocalTime(input) {
            const date = Date.fromLocaleString(Qt.locale("en_US"), input.trim(), dateTimeFormat)
            return Qt.formatDateTime(date, dateTimeFormat) === input.trim() ? date.getTime() : NaN
        }

        onAboutToShow: {
            const now = new Date()
            endDateTime.setDateTime(now)
            startDateTime.setDateTime(new Date(now.getTime() - 86400000))
            feedback = ""
        }

        contentItem: ColumnLayout {
            spacing: 10

            Text {
                text: I18n.format("sensor.exportTitle", {"sensor": sensorData.name || page.sensorName}, "Export " + (sensorData.name || page.sensorName))
                font.pixelSize: 20
                font.bold: true
                color: Theme.text
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: I18n.t("sensor.exportHelp", "Export all saved parameters for this sensor within the selected time range.")
                color: Theme.subText
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            FieldLabel { text: I18n.t("sensor.exportFormat", "File format") }
            WinComboBox {
                id: exportFormat
                Layout.fillWidth: true
                model: ["CSV (.csv)", "Excel (.xlsx)"]
                Accessible.name: I18n.t("sensor.exportFormat", "File format")
            }
            FieldLabel { text: I18n.t("sensor.exportStart", "Start (local time)") }
            DateTimeFields {
                id: startDateTime
                Layout.fillWidth: true
                fieldName: I18n.t("sensor.exportStart", "Start (local time)")
                onEdited: exportOptionsDialog.feedback = ""
            }
            FieldLabel { text: I18n.t("sensor.exportEnd", "End (local time)") }
            DateTimeFields {
                id: endDateTime
                Layout.fillWidth: true
                fieldName: I18n.t("sensor.exportEnd", "End (local time)")
                onEdited: exportOptionsDialog.feedback = ""
            }
            Text {
                Layout.fillWidth: true
                text: exportOptionsDialog.feedback || I18n.t("sensor.exportMinuteHint", "Time uses 24-hour format. The end minute is included.")
                color: exportOptionsDialog.feedback ? Theme.danger : Theme.subText
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 8
                Item { Layout.fillWidth: true }
                WinButton { text: I18n.t("common.cancel", "Cancel"); onClicked: exportOptionsDialog.close() }
                WinButton {
                    text: I18n.t("common.chooseExport", "Choose File & Export")
                    isAccent: true
                    onClicked: {
                        const start = exportOptionsDialog.parseLocalTime(startDateTime.value())
                        const end = exportOptionsDialog.parseLocalTime(endDateTime.value())
                        if (!Number.isFinite(start) || !Number.isFinite(end) || start <= 0 || end < start) {
                            exportOptionsDialog.feedback = I18n.t("sensor.exportInvalidRange", "Enter valid dates and times. End must be at or after start.")
                            return
                        }
                        exportOptionsDialog.startSeconds = start / 1000
                        exportOptionsDialog.endSeconds = end / 1000 + 59
                        exportFileDialog.open()
                    }
                }
            }
        }
    }

    FileDialog {
        id: exportFileDialog
        title: I18n.t("sensor.saveExport", "Save Telemetry Export")
        fileMode: FileDialog.SaveFile
        defaultSuffix: exportFormat.currentIndex === 1 ? "xlsx" : "csv"
        nameFilters: defaultSuffix === "xlsx" ? ["Excel files (*.xlsx)"] : ["CSV files (*.csv)"]
        onAccepted: {
            if (typeof backend !== "undefined" && backend.exportSensorData(file.toString(), page.sensorName,
                    exportOptionsDialog.startSeconds, exportOptionsDialog.endSeconds, defaultSuffix)) {
                exportOptionsDialog.close()
            } else {
                exportOptionsDialog.feedback = I18n.t("sensor.exportCouldNotStart", "Could not start export.")
            }
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

            AuxiliaryMetricsGrid {
                id: auxiliaryGrid
                streams: page.sensorData.streams || []
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
                    staleSeconds: Math.max(0, Math.floor((page.freshnessNow - (page.accelReceivedAt || page.monitoringStartedAt)) / 1000))
                    hasLiveSamples: page.accelReceivedAt > 0
                    onHistoryRequested: historyChartDialog.openMotion(page.sensorName, "ACC/X,ACC/Y,ACC/Z")
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
                        autoScaleY: accelPanel.autoScaleY
                        anchors.fill: parent
                        frozen: page.isFrozen
                        panMode: page.accelPanMode
                        yAxisTitle: I18n.t("sensor.accelAxis", "Accel (g)")
                        defaultYMin: -2
                        defaultYMax: 2
                        frozenYLimit: 8
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
                    staleSeconds: Math.max(0, Math.floor((page.freshnessNow - (page.inclineReceivedAt || page.monitoringStartedAt)) / 1000))
                    hasLiveSamples: page.inclineReceivedAt > 0
                    onHistoryRequested: historyChartDialog.openMotion(page.sensorName, "ACC/PITCH,ACC/ROLL")
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
                        autoScaleY: inclinoPanel.autoScaleY
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
