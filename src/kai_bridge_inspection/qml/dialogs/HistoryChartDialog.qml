import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCharts

import "../"
import "../common"

Popup {
    id: dialog
    width: parent ? Math.min(1080, Math.max(parent.width - 48, 420)) : 1080
    height: parent ? Math.min(760, Math.max(parent.height - 48, 420)) : 760
    modal: true
    dim: true
    Overlay.modal: Rectangle { color: "#CC000000" }
    anchors.centerIn: Overlay.overlay

    property string sensorName: ""
    property string dialogTitle: "Historical Graph"
    property bool metricSelectionEnabled: true

    property int presetMetricCount: 0
    property int metricLookup: 0
    property bool discoverMetrics: false
    property bool panMode: true
    property bool chartReady: false
    property var fullView: null
    property var plottedSeries: []
    property var lossBands: []
    property real yLimit: 0
    property bool fullScaleY: false
    property bool statusError: false

    function useRecentRange() {
        const now = new Date()
        fromTime.setDateTime(new Date(now.getTime() - 3600000))
        toTime.setDateTime(now)
    }

    function resetView() {
        if (!chartReady)
            return
        setTimeRange(fullView.xMin, fullView.xMax)
        fullScaleY = false
        fitVisibleY()
    }

    function setTimeRange(start, end) {
        const first = new Date(Math.floor(start))
        const last = new Date(Math.max(Math.ceil(end), first.getTime() + 1))
        if (first > axisX.max)
            axisX.max = last
        axisX.min = first
        axisX.max = last
    }

    function fitVisibleY() {
        if (!chartReady)
            return
        if (fullScaleY) {
            axisY.min = -yLimit
            axisY.max = yLimit
            return
        }

        const start = axisX.min.getTime()
        const end = axisX.max.getTime()
        let lower = Infinity
        let upper = -Infinity
        for (const points of plottedSeries) {
            for (const [time, value] of points) {
                if (time < start)
                    continue
                if (time > end)
                    break
                lower = Math.min(lower, value)
                upper = Math.max(upper, value)
            }
        }
        if (lower === Infinity)
            return

        if (yLimit > 0) {
            const pad = Math.max((upper - lower) * 0.1, yLimit / 200)
            const min = Math.max(-yLimit, Math.min(yLimit - pad, lower - pad))
            const max = Math.min(yLimit, Math.max(-yLimit + pad, upper + pad))
            axisY.min = min
            axisY.max = max
        } else {
            applyYAxis(metricModel.get(metricCombo.currentIndex).metrics.split(",")[0], lower, upper)
        }
    }

    function panTime(deltaPixels, plotWidth) {
        if (plotWidth <= 0)
            return
        const start = axisX.min.getTime()
        const span = Math.min(axisX.max.getTime() - start, fullView.xMax - fullView.xMin)
        const target = start + deltaPixels * span / plotWidth
        const next = Math.round(Math.max(fullView.xMin, Math.min(fullView.xMax - span, target)))
        if (next !== start) {
            setTimeRange(next, next + span)
            fitVisibleY()
        }
    }

    function seconds(fields) {
        const input = fields.value()
        const format = "yyyy-MM-dd HH:mm:ss"
        const date = Date.fromLocaleString(Qt.locale("en_US"), input, format)
        return Qt.formatDateTime(date, format) === input ? date.getTime() / 1000 : NaN
    }

    onVisibleChanged: if (typeof backend !== "undefined") backend.setHistoryVisible(visible)
    onClosed: {
        metricLookup = 0
        historyRequest = 0
        refreshTimer.stop()
        chartReady = false
        panMode = true
    }

    Component.onCompleted: presetMetricCount = metricModel.count

    function loadSensorMetrics(name) {
        if (metricModel.count > presetMetricCount)
            metricModel.remove(presetMetricCount, metricModel.count - presetMetricCount)
        if (typeof backend === "undefined")
            return false
        const sensor = backend.getSensorData(name, false)
        discoverMetrics = !!sensor.profile && sensor.profile !== "nemosense"
        if (!discoverMetrics)
            return false
        appendMetrics(sensor.profile_metrics || [])
        return metricModel.count > presetMetricCount
    }

    function appendMetrics(metrics) {
        const existing = new Set()
        for (let i = presetMetricCount; i < metricModel.count; ++i)
            existing.add(metricModel.get(i).metrics)
        for (const metric of metrics) {
            if (!metric || existing.has(metric))
                continue
            const label = metricLabel(metric)
            metricModel.append({label: label, metrics: metric, yTitle: label})
            existing.add(metric)
        }
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
        useRecentRange()
        rangeCombo.currentIndex = 0
        open()
        queueRefresh()
    }

    function openHistory(name) {
        sensorName = name
        dialogTitle = "Historical Telemetry"
        metricSelectionEnabled = true
        metricCombo.currentIndex = loadSensorMetrics(name) ? presetMetricCount : 3
        useRecentRange()
        rangeCombo.currentIndex = 0
        open()
        queueRefresh()
    }

    function openMotion(name, metrics) {
        sensorName = name
        dialogTitle = I18n.t("sensor.motionHistory", "Motion history")
        metricSelectionEnabled = true
        loadSensorMetrics(name)
        for (let i = 0; i < presetMetricCount; ++i) {
            if (metricModel.get(i).metrics === metrics) {
                metricCombo.currentIndex = i
                break
            }
        }
        useRecentRange()
        rangeCombo.currentIndex = 0
        open()
        queueRefresh()
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

    property int historyRequest: 0
    property int historyPercent: 0

    Connections {
        target: typeof backend !== "undefined" ? backend : null
        function onHistoryMetricsReady(request, metrics) {
            if (dialog.visible && request === dialog.metricLookup)
                dialog.appendMetrics(metrics)
        }
        function onHistoryProgress(request, percent) {
            if (dialog.visible && request === dialog.historyRequest)
                dialog.historyPercent = percent
        }
        function onHistoryReady(request, results) {
            if (dialog.visible && request === dialog.historyRequest) {
                dialog.historyRequest = 0
                dialog.displayHistory(results)
            }
        }
    }

    function queueRefresh() {
        historyRequest = 0
        refreshTimer.restart()
    }

    function refreshChart() {
        const rangeRow = rangeModel.get(rangeCombo.currentIndex)
        const custom = rangeRow.hours < 0
        const start = custom ? seconds(fromTime) : 0
        const end = custom ? seconds(toTime) : 0
        if (custom && (!Number.isFinite(start) || !Number.isFinite(end) || start <= 0 || end < start)) {
            statusError = true
            statusText.text = "Choose a valid start and end. End must be at or after start."
            return
        }

        chartReady = false
        lineA.clear()
        lineB.clear()
        lineC.clear()

        if (typeof backend === "undefined" || !sensorName) {
            statusError = true
            statusText.text = "Backend is not ready."
            emptyState.visible = true
            return
        }

        const metricRow = metricModel.get(metricCombo.currentIndex)
        const metrics = metricRow.metrics.split(",")
        setSeriesVisibility(metrics)
        emptyState.visible = false
        statusError = false
        statusText.text = "Loading history…"
        historyPercent = 0
        historyRequest = custom ? backend.requestHistoryRange(sensorName, metricRow.metrics, start, end + 59)
                                : backend.requestHistoryHours(sensorName, metricRow.metrics, rangeRow.hours)
        if (discoverMetrics) {
            discoverMetrics = false
            metricLookup = backend.requestHistoryMetrics(sensorName)
        }
    }

    function displayHistory(results) {
        const metricRow = metricModel.get(metricCombo.currentIndex)
        const metrics = metricRow.metrics.split(",")
        const series = [lineA, lineB, lineC]

        setSeriesVisibility(metrics)

        let totalCount = 0
        let xMin = Infinity
        let xMax = -Infinity
        let rangeStart = null
        let rangeEnd = null
        const loadedSeries = []
        const gaps = []
        let emptyHint = ""

        for (let i = 0; i < metrics.length && i < series.length; i++) {
            const meta = results[i]
            if (!meta || meta.empty) {
                if (meta && meta.error) statusError = true
                if (meta && meta.hint && !emptyHint) emptyHint = meta.hint
                continue
            }

            backend.setHistoryPoints(series[i], meta.points)
            totalCount += meta.count
            xMin = Math.min(xMin, meta.minX)
            xMax = Math.max(xMax, meta.maxX)
            rangeStart = meta.rangeStartMs ?? rangeStart
            rangeEnd = meta.rangeEndMs ?? rangeEnd
            loadedSeries.push(meta.points)
            for (const gap of (meta.gaps || []))
                gaps.push(gap)
        }

        emptyState.visible = totalCount === 0
        if (totalCount === 0) {
            axisY.min = 0
            axisY.max = 1
            statusText.text = emptyHint || "No telemetry data for this metric and range. Choose a different metric or widen the date range."
            return
        }

        setTimeRange(rangeStart ?? xMin, rangeEnd ?? xMax)
        axisY.titleText = metricRow.yTitle
        fullView = {xMin: axisX.min.getTime(), xMax: axisX.max.getTime()}
        plottedSeries = loadedSeries
        // Use the combined extent of all plotted metrics for the outside bands.
        if (rangeStart !== null && rangeStart < xMin)
            gaps.unshift([rangeStart, xMin, true])
        if (rangeEnd !== null && xMax < rangeEnd)
            gaps.push([xMax, rangeEnd, true])
        lossBands = gaps
        yLimit = /^ACC\/[XYZ]$/.test(metrics[0]) ? 8 :
            /^ACC\/(PITCH|ROLL)$/.test(metrics[0]) ? 90 : 0
        fullScaleY = false
        chartReady = true
        fitVisibleY()
        const format = "yyyy-MM-dd HH:mm:ss"
        statusText.text = totalCount.toLocaleString(Qt.locale(), "f", 0) + " plotted points  •  " +
            Qt.formatDateTime(new Date(xMin), format) + " to " + Qt.formatDateTime(new Date(xMax), format)
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
        ListElement { label: "Last 1 Hour"; hours: 1 }
        ListElement { label: "Last 24 Hours"; hours: 24 }
        ListElement { label: "Last 5 Days"; hours: 120 }
        ListElement { label: "Last 30 Days"; hours: 720 }
        ListElement { label: "Last 6 Months"; hours: 4320 }
        ListElement { label: "Last 12 Months"; hours: 8760 }
        ListElement { label: "All Data"; hours: 0 }
        ListElement { label: "Custom date and time"; hours: -1 }
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
        spacing: 12

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
                onActivated: queueRefresh()
            }

            WinComboBox {
                textRole: "label"
                id: rangeCombo
                model: rangeModel
                Layout.preferredWidth: 195
                onActivated: if (rangeModel.get(currentIndex).hours >= 0) queueRefresh()
            }

            WinButton {
                iconName: Icons.refresh; text: "Apply"
                Layout.preferredHeight: 36
                onClicked: queueRefresh()
            }
        }

        GridLayout {
            visible: rangeModel.get(rangeCombo.currentIndex).hours < 0
            Layout.fillWidth: true
            columns: width >= 760 ? 2 : 1
            columnSpacing: 20
            rowSpacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 370
                spacing: 4
                FieldLabel { labelText: "Start (local time)" }
                DateTimeFields { id: fromTime; fieldName: "Start"; Layout.fillWidth: true }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 370
                spacing: 4
                FieldLabel { labelText: "End (local time, inclusive)" }
                DateTimeFields { id: toTime; fieldName: "End"; Layout.fillWidth: true }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            WinButton { text: "Pan"; isAccent: dialog.panMode; enabled: dialog.chartReady; onClicked: { dialog.panMode = true; dialog.fitVisibleY() } }
            WinButton { text: "Select"; isAccent: !dialog.panMode; enabled: dialog.chartReady; onClicked: dialog.panMode = false }
            WinButton { text: "Reset"; enabled: dialog.chartReady; onClicked: dialog.resetView() }
            WinButton {
                text: dialog.fullScaleY ? "Auto Y" : "Full Y"
                visible: dialog.yLimit > 0
                enabled: dialog.chartReady
                onClicked: {
                    dialog.fullScaleY = !dialog.fullScaleY
                    dialog.fitVisibleY()
                }
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: Theme.subText
                text: dialog.panMode ? "Drag to pan" : "Drag a box to zoom"
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

                DateTimeAxis {
                    id: axisX
                    visible: dialog.chartReady
                    min: new Date(0)
                    max: new Date(1000)
                    tickCount: historyChart.width >= 750 ? 5 : 3
                    titleText: "Local time"
                    labelsColor: Theme.subText
                    gridLineColor: Theme.border
                    format: {
                        const span = max.getTime() - min.getTime()
                        if (span >= 86400000)
                            return "yyyy-MM-dd"
                        const clock = span < 600000 ? "HH:mm:ss" : "HH:mm"
                        return min.toDateString() === max.toDateString() ? clock : "MM-dd " + clock
                    }
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

            Item {
                anchors.fill: parent
                visible: dialog.chartReady
                Repeater {
                    model: dialog.lossBands
                    delegate: Rectangle {
                        required property var modelData
                        readonly property rect plot: historyChart.plotArea
                        readonly property real start: axisX.min.getTime()
                        readonly property real span: Math.max(1, axisX.max.getTime() - start)
                        readonly property real leftRatio: Math.max(0, (modelData[0] - start) / span)
                        readonly property real rightRatio: Math.min(1, (modelData[1] - start) / span)
                        visible: rightRatio > leftRatio
                        x: plot.x + plot.width * leftRatio
                        y: plot.y
                        width: plot.width * Math.max(0, rightRatio - leftRatio)
                        height: plot.height
                        readonly property bool outsideReadings: modelData[2] === true
                        color: Qt.rgba(0.5, 0.5, 0.5, outsideReadings ? 0.20 : 0.38)
                        readonly property string gapTitle: outsideReadings
                            ? I18n.t("history.noRecordedData", "No recorded data")
                            : I18n.t("history.dataLoss", "Data loss")
                        readonly property string interval: Qt.formatDateTime(new Date(modelData[0]), "yyyy-MM-dd HH:mm:ss") +
                            " – " + Qt.formatDateTime(new Date(modelData[1]), "yyyy-MM-dd HH:mm:ss")
                        HoverHandler { id: gapHover }
                        ToolTip.visible: gapHover.hovered
                        ToolTip.delay: 250
                        ToolTip.text: gapTitle + "\n" + interval
                        Text {
                            id: gapDetails
                            anchors.centerIn: parent
                            text: parent.gapTitle + "\n" + parent.interval
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.text
                            visible: parent.width >= implicitWidth + 12 && parent.height >= implicitHeight + 8
                        }
                        Text {
                            anchors.centerIn: parent
                            text: parent.gapTitle
                            color: Theme.text
                            visible: !gapDetails.visible &&
                                parent.width >= implicitWidth + 12 && parent.height >= implicitHeight + 8
                        }
                    }
                }
            }

            MouseArea {
                id: chartDrag
                anchors.fill: parent
                enabled: dialog.chartReady
                hoverEnabled: true
                cursorShape: !containsMouse || !insidePlot(mouseX, mouseY)
                    ? Qt.ArrowCursor : dialog.panMode
                    ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.CrossCursor
                property point origin
                property point previous

                function insidePlot(x, y) {
                    const plot = historyChart.plotArea
                    return x >= plot.x && x <= plot.x + plot.width &&
                        y >= plot.y && y <= plot.y + plot.height
                }

                onPressed: function(mouse) {
                    origin = Qt.point(mouse.x, mouse.y)
                    mouse.accepted = insidePlot(origin.x, origin.y)
                    previous = origin
                }
                onPositionChanged: function(mouse) {
                    if (!pressed || !dialog.panMode)
                        return
                    dialog.panTime(previous.x - mouse.x, historyChart.plotArea.width)
                    previous = Qt.point(mouse.x, mouse.y)
                }
                onWheel: function(wheel) {
                    const delta = wheel.angleDelta.y || wheel.pixelDelta.y
                    const horizontal = wheel.pixelDelta.x || wheel.angleDelta.x / 3
                    if ((!delta && !horizontal) || !insidePlot(wheel.x, wheel.y)) {
                        wheel.accepted = false
                        return
                    }
                    const plot = historyChart.plotArea
                    if (horizontal && Math.abs(horizontal) >= Math.abs(wheel.pixelDelta.y || wheel.angleDelta.y / 3)) {
                        dialog.panTime(-horizontal, plot.width)
                        wheel.accepted = true
                        return
                    }
                    const ratio = (wheel.x - plot.x) / plot.width
                    const start = axisX.min.getTime()
                    const span = axisX.max.getTime() - start
                    const bounds = dialog.fullView
                    const total = bounds.xMax - bounds.xMin
                    const nextSpan = Math.min(total, Math.max(1, Math.round(span * (delta > 0 ? 0.8 : 1.25))))
                    const left = Math.max(bounds.xMin, Math.min(bounds.xMax - nextSpan,
                        Math.round(start + (span - nextSpan) * ratio)))
                    dialog.setTimeRange(left, left + nextSpan)
                    dialog.fitVisibleY()
                    wheel.accepted = true
                }
                onReleased: {
                    if (!dialog.panMode && selection.width >= 10 && selection.height >= 10) {
                        historyChart.zoomIn(Qt.rect(selection.x, selection.y, selection.width, selection.height))
                        if (dialog.fullScaleY)
                            dialog.fitVisibleY()
                    }
                }
            }

            Rectangle {
                id: selection
                visible: chartDrag.pressed && !dialog.panMode
                readonly property rect plot: historyChart.plotArea
                readonly property real pointerX: Math.min(plot.x + plot.width, Math.max(plot.x, chartDrag.mouseX))
                readonly property real pointerY: Math.min(plot.y + plot.height, Math.max(plot.y, chartDrag.mouseY))
                x: Math.min(chartDrag.origin.x, pointerX)
                y: Math.min(chartDrag.origin.y, pointerY)
                width: Math.abs(chartDrag.origin.x - pointerX)
                height: Math.abs(chartDrag.origin.y - pointerY)
                color: Qt.alpha(Theme.accent, 0.2)
                border.color: Theme.accent
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

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: statusContent.implicitHeight + 20
                radius: 8
                color: dialog.statusError ? Qt.alpha(Theme.danger, 0.12) : Theme.controlBg
                border.color: dialog.statusError ? Theme.danger : Theme.border

                RowLayout {
                    id: statusContent
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10
                    LucideIcon {
                        icon: dialog.statusError ? Icons.warning : Icons.info
                        color: dialog.statusError ? Theme.danger : Theme.info
                        size: Theme.iconSizeSmall
                    }
                    Label {
                        id: statusText
                        text: "Choose a metric and range."
                        color: Theme.text
                        font.pixelSize: 14
                        font.bold: true
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    ProgressBar {
                        id: historyProgressBar
                        visible: dialog.historyRequest > 0
                        Layout.preferredWidth: Math.min(130, statusContent.width * 0.25)
                        to: 100
                        value: dialog.historyPercent
                        Accessible.name: "History loading progress"
                        background: Rectangle {
                            implicitHeight: 8
                            radius: 4
                            color: Theme.dialog
                            border.color: Theme.borderLight
                        }
                        contentItem: Item {
                            implicitHeight: 8
                            Rectangle {
                                width: parent.width * historyProgressBar.visualPosition
                                height: parent.height
                                radius: 4
                                color: Theme.accent
                                Behavior on width { NumberAnimation { duration: 100 } }
                            }
                        }
                    }
                    Label {
                        visible: historyProgressBar.visible
                        text: dialog.historyPercent + "%"
                        color: Theme.text
                        font.bold: true
                    }
                }
            }

            WinButton {
                iconName: Icons.cancel; text: "Close"
                Layout.preferredHeight: 36
                onClicked: dialog.close()
            }
        }
    }
}
