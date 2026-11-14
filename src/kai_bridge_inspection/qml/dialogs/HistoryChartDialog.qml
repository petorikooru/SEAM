import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCharts

import "../"
import "../common"

Popup {
    id: dialog
    width: parent ? Math.min(920, Math.max(parent.width - 48, 420)) : 920
    height: parent ? Math.min(640, Math.max(parent.height - 48, 420)) : 640
    modal: true
    dim: true
    Overlay.modal: Rectangle { color: "#CC000000" }
    anchors.centerIn: Overlay.overlay

    property string sensorName: ""
    property string dialogTitle: "Historical Graph"
    property bool metricSelectionEnabled: true

    property int presetMetricCount: 0

    Component.onCompleted: presetMetricCount = metricModel.count

    function loadSensorMetrics(name) {
        if (metricModel.count > presetMetricCount)
            metricModel.remove(presetMetricCount, metricModel.count - presetMetricCount)
        if (typeof backend === "undefined")
            return false
        const sensor = backend.getSensorData(name)
        if (!sensor.profile || sensor.profile === "nemosense")
            return false
        const metrics = new Set(sensor.profile_metrics || [])
        for (const metric of sensor.active_metrics || [])
            metrics.add(metric)
        for (const metric of metrics)
            metricModel.append({label: metricLabel(metric), metrics: metric, yTitle: metricLabel(metric)})
        return metrics.size > 0
    }

    function openBattery(name) {
        loadSensorMetrics(name)
        sensorName = name
        dialogTitle = "Battery / Power Telemetry"
        // Keep the selector enabled. NemoSense battery data can arrive as
        // percent, voltage, current, temperature, charger status, or power rail
        // metrics, so a locked single "Battery" option is misleading when only
        // some status packets have arrived.
        metricSelectionEnabled = true
        metricCombo.currentIndex = 0
        rangeCombo.currentIndex = 0
        open()
        refreshTimer.restart()
    }

    function openHistory(name) {
        sensorName = name
        dialogTitle = "Historical Telemetry"
        metricSelectionEnabled = true
        metricCombo.currentIndex = loadSensorMetrics(name) ? presetMetricCount : 3
        rangeCombo.currentIndex = 1
        open()
        refreshTimer.restart()
    }

    function metricLabel(metric) {
        switch (metric) {
        case "BATTERY": return "Battery"
        case "ACC/TEMPERATURE": return "Temperature"
        case "CELLULAR_RSSI": return "Signal"
        case "BAT_CHARGER_STATUS": return "Charger Status"
        case "PWR_VBUS_V": return "VBUS"
        case "PWR_5V_POE_V": return "PoE 5V"
        case "BAT_FUEL_GAUGE_AVGCURRENT": return "Battery Current"
        case "ACC_LOST_SAMPLES_COUNT": return "Lost Samples"
        case "ACC/PITCH": return "Pitch"
        case "ACC/ROLL": return "Roll"
        case "ACC/X": return "X Axis"
        case "ACC/Y": return "Y Axis"
        case "ACC/Z": return "Z Axis"
        default: return metric
        }
    }

    function metricColor(metric, index) {
        switch (metric) {
        case "BATTERY": return Theme.accent
        case "ACC/TEMPERATURE": return "#FFB74D"
        case "CELLULAR_RSSI": return "#64B5F6"
        case "BAT_CHARGER_STATUS": return "#BA68C8"
        case "PWR_VBUS_V": return "#4DB6AC"
        case "PWR_5V_POE_V": return "#7986CB"
        case "BAT_FUEL_GAUGE_AVGCURRENT": return "#F06292"
        case "ACC_LOST_SAMPLES_COUNT": return "#E57373"
        case "ACC/PITCH": return Theme.pitch
        case "ACC/ROLL": return Theme.roll
        case "ACC/X": return Theme.axisX
        case "ACC/Y": return Theme.axisY
        case "ACC/Z": return Theme.axisZ
        default: return index === 0 ? Theme.accent : (index === 1 ? Theme.axisY : Theme.axisZ)
        }
    }

    function setSeriesVisibility(metrics) {
        const series = [lineA, lineB, lineC]
        for (let i = 0; i < series.length; i++) {
            const visible = i < metrics.length
            series[i].visible = visible
            if (visible) {
                series[i].name = metricLabel(metrics[i])
                series[i].color = metricColor(metrics[i], i)
            }
        }
    }

    function applyYAxis(metricKey, minY, maxY) {
        if (metricKey === "BATTERY") {
            axisY.min = Math.max(0, Math.floor(minY - 5))
            axisY.max = Math.min(100, Math.ceil(maxY + 5))
        } else if (metricKey === "CELLULAR_RSSI") {
            axisY.min = Math.floor(minY - 5)
            axisY.max = Math.ceil(maxY + 5)
        } else if (Math.abs(maxY - minY) < 0.0001) {
            axisY.min = minY - 1
            axisY.max = maxY + 1
        } else {
            const pad = Math.max((maxY - minY) * 0.1, 0.5)
            axisY.min = minY - pad
            axisY.max = maxY + pad
        }
    }

    function refreshChart() {
        lineA.clear()
        lineB.clear()
        lineC.clear()

        if (typeof backend === "undefined" || !sensorName) {
            statusText.text = "Backend is not ready."
            emptyState.visible = true
            return
        }

        const metricRow = metricModel.get(metricCombo.currentIndex)
        const rangeRow = rangeModel.get(rangeCombo.currentIndex)
        const metrics = metricRow.metrics.split(",")
        const series = [lineA, lineB, lineC]

        setSeriesVisibility(metrics)

        let totalCount = 0
        let xMax = 0
        let minY = Number.POSITIVE_INFINITY
        let maxY = Number.NEGATIVE_INFINITY
        let xTitle = "Time"
        let startLabel = ""
        let endLabel = ""
        let emptyHint = ""

        for (let i = 0; i < metrics.length && i < series.length; i++) {
            const meta = backend.loadHistorySeries(sensorName, metrics[i], rangeRow.days, series[i])
            if (!meta || meta.empty) {
                if (meta && meta.hint && !emptyHint) emptyHint = meta.hint
                continue
            }

            totalCount += meta.count
            xMax = Math.max(xMax, meta.maxX)
            minY = Math.min(minY, meta.minY)
            maxY = Math.max(maxY, meta.maxY)
            xTitle = meta.xTitle || xTitle
            startLabel = startLabel || meta.startLabel
            endLabel = meta.endLabel || endLabel
        }

        emptyState.visible = totalCount === 0
        if (totalCount === 0) {
            axisX.min = 0
            axisX.max = 1
            axisY.min = 0
            axisY.max = 1
            statusText.text = emptyHint || "No telemetry data for this metric and range. Try All Data, or check whether VAR/DOUBLE status packets are being received."
            return
        }

        axisX.min = 0
        axisX.max = Math.max(xMax, 1)
        axisX.titleText = xTitle
        axisY.titleText = metricRow.yTitle
        applyYAxis(metrics[0], minY, maxY)
        statusText.text = totalCount + " plotted points, " + startLabel + " to " + endLabel
    }

    Timer {
        id: refreshTimer
        interval: 20
        repeat: false
        onTriggered: refreshChart()
    }

    ListModel {
        id: metricModel
        ListElement { label: "Battery %"; metrics: "BATTERY"; yTitle: "Battery (%)" }
        ListElement { label: "Battery Voltage"; metrics: "BAT_FUEL_GAUGE_AVGVCELL"; yTitle: "Voltage (V)" }
        ListElement { label: "Battery Current"; metrics: "BAT_FUEL_GAUGE_AVGCURRENT"; yTitle: "Current (A)" }
        ListElement { label: "Battery Temperature"; metrics: "BAT_FUEL_GAUGE_AVGTA"; yTitle: "Temperature (C)" }
        ListElement { label: "Charger Status"; metrics: "BAT_CHARGER_STATUS"; yTitle: "Status code" }
        ListElement { label: "Power Rails"; metrics: "PWR_VBUS_V,PWR_5V_POE_V"; yTitle: "Voltage (V)" }
        ListElement { label: "Temperature"; metrics: "ACC/TEMPERATURE"; yTitle: "Temperature (C)" }
        ListElement { label: "Signal"; metrics: "CELLULAR_RSSI"; yTitle: "RSSI (dBm)" }
        ListElement { label: "Device Lost Samples"; metrics: "ACC_LOST_SAMPLES_COUNT"; yTitle: "Lost samples" }
        ListElement { label: "Inclination"; metrics: "ACC/PITCH,ACC/ROLL"; yTitle: "Angle (deg)" }
        ListElement { label: "Acceleration"; metrics: "ACC/X,ACC/Y,ACC/Z"; yTitle: "Acceleration (g)" }
    }

    ListModel {
        id: rangeModel
        ListElement { label: "Last 24 Hours"; days: 1 }
        ListElement { label: "Last 5 Days"; days: 5 }
        ListElement { label: "Last 30 Days"; days: 30 }
        ListElement { label: "Last 6 Months"; days: 180 }
        ListElement { label: "Last 12 Months"; days: 365 }
        ListElement { label: "All Data"; days: 0 }
    }



    background: Rectangle {
        color: Theme.dialog
        radius: 12
        border.color: Theme.borderLight
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    text: dialog.dialogTitle
                    color: Theme.text
                    font.pixelSize: 22
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Label {
                    text: dialog.sensorName
                    color: Theme.subText
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            WinComboBox {
                textRole: "label"
                id: metricCombo
                model: metricModel
                enabled: dialog.metricSelectionEnabled
                Layout.preferredWidth: 210
                onActivated: refreshTimer.restart()
            }

            WinComboBox {
                textRole: "label"
                id: rangeCombo
                model: rangeModel
                Layout.preferredWidth: 160
                onActivated: refreshTimer.restart()
            }

            WinButton {
                iconName: Icons.refresh; text: "Refresh"
                Layout.preferredHeight: 36
                onClicked: refreshTimer.restart()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.border
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ChartView {
                id: historyChart
                anchors.fill: parent
                backgroundColor: "transparent"
                antialiasing: true
                legend.visible: true
                legend.labelColor: Theme.subText
                theme: ChartView.ChartThemeDark
                margins.top: 0
                margins.bottom: 0
                margins.left: 0
                margins.right: 0

                ValueAxis {
                    id: axisX
                    min: 0
                    max: 1
                    titleText: "Time"
                    labelsColor: Theme.subText
                    gridLineColor: Theme.border
                    labelFormat: "%.1f"
                }

                ValueAxis {
                    id: axisY
                    min: 0
                    max: 1
                    titleText: "Value"
                    labelsColor: Theme.subText
                    gridLineColor: Theme.border
                    labelFormat: "%.2f"
                }

                LineSeries { id: lineA; axisX: axisX; axisY: axisY; width: 2.2; useOpenGL: false }
                LineSeries { id: lineB; axisX: axisX; axisY: axisY; width: 2.2; useOpenGL: false }
                LineSeries { id: lineC; axisX: axisX; axisY: axisY; width: 2.2; useOpenGL: false }
            }

            Rectangle {
                id: emptyState
                anchors.centerIn: parent
                width: emptyLabel.implicitWidth + 32
                height: emptyLabel.implicitHeight + 20
                radius: 8
                color: Theme.card
                border.color: Theme.border
                visible: false

                Label {
                    id: emptyLabel
                    anchors.centerIn: parent
                    text: "No data"
                    color: Theme.subText
                    font.pixelSize: 14
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Label {
                id: statusText
                text: "Choose a metric and range."
                color: Theme.subText
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            WinButton {
                iconName: Icons.cancel; text: "Close"
                Layout.preferredHeight: 36
                onClicked: dialog.close()
            }
        }
    }
}
