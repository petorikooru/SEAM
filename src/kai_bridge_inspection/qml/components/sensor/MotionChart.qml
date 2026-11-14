import QtQuick
import QtCharts
import "../../"

Item {
    id: root

    property bool frozen: false
    property bool panMode: true
    property string yAxisTitle: ""
    property real defaultYMin: -2
    property real defaultYMax: 2
    property real frozenYLimit: Math.max(Math.abs(defaultYMin), Math.abs(defaultYMax))
    property real initialXMax: 1
    property real minimumXSpan: 0.0005
    property var seriesDefinitions: []
    property var seriesObjects: []

    readonly property alias chartView: chart

    function initializeSeries() {
        if (seriesObjects.length > 0)
            return
        const created = []
        for (let i = 0; i < seriesDefinitions.length; ++i) {
            const definition = seriesDefinitions[i]
            const series = chart.createSeries(ChartView.SeriesTypeLine, definition.name, axisX, axisY)
            series.color = definition.color
            series.width = definition.width || 2
            series.useOpenGL = false
            series.pointsReplaced.connect(queueLiveFit)
            series.pointsRemoved.connect(queueLiveFit)
            created.push(series)
        }
        seriesObjects = created
    }

    function seriesAt(index) {
        return index >= 0 && index < seriesObjects.length ? seriesObjects[index] : null
    }

    function setSeriesVisible(index, visible) {
        const series = seriesAt(index)
        if (series) {
            series.visible = visible
            queueLiveFit()
        }
    }

    function clearSeries() {
        for (let i = 0; i < seriesObjects.length; ++i)
            seriesObjects[i].clear()
    }

    function dataMaximum() {
        const primary = seriesAt(0)
        if (primary && primary.count > 0)
            return Math.max(initialXMax, primary.at(primary.count - 1).x)
        return initialXMax
    }

    function setFrozenYRange(lower, upper) {
        const span = Math.max(0.0001, Math.min(2 * frozenYLimit, upper - lower))
        const bottom = Math.max(-frozenYLimit, Math.min(frozenYLimit - span, lower))
        // Set the far edge first when moving to a disjoint range.
        if (bottom >= axisY.max) {
            axisY.max = bottom + span
            axisY.min = bottom
        } else {
            axisY.min = bottom
            axisY.max = bottom + span
        }
    }

    function queueLiveFit() {
        if (!frozen)
            liveFitTimer.start()
    }

    Timer {
        id: liveFitTimer
        interval: 50
        onTriggered: if (!root.frozen) root.fitYRange()
    }

    function fitYRange() {
        let lower = Infinity
        let upper = -Infinity
        for (const series of seriesObjects) {
            if (!series.visible)
                continue
            for (let index = 0; index < series.count; ++index) {
                const value = series.at(index).y
                if (Number.isFinite(value)) {
                    lower = Math.min(lower, value)
                    upper = Math.max(upper, value)
                }
            }
        }

        if (lower > upper) {
            setFrozenYRange(frozen ? -frozenYLimit : defaultYMin,
                            frozen ? frozenYLimit : defaultYMax)
            return
        }

        lower = Math.max(-frozenYLimit, Math.min(frozenYLimit, lower))
        upper = Math.max(-frozenYLimit, Math.min(frozenYLimit, upper))
        const padding = Math.max((upper - lower) * 0.08, frozenYLimit / 1000)
        setFrozenYRange(lower - padding, upper + padding)
    }

    function resetView() {
        axisX.min = 0
        axisX.max = frozen ? dataMaximum() : initialXMax
        fitYRange()
    }

    function adjustFrozenRange() {
        if (frozen)
            resetView()
    }

    Component.onCompleted: initializeSeries()
    onFrozenChanged: {
        if (!frozen)
            resetView()
    }

    ChartView {
        id: chart
        anchors.fill: parent
        backgroundColor: "transparent"
        antialiasing: true
        legend.visible: false
        theme: ChartView.ChartThemeDark
        margins.top: 0
        margins.bottom: 0
        margins.left: 0
        margins.right: 0

        ValueAxis {
            id: axisX
            min: 0
            max: root.initialXMax
            titleText: I18n.t("common.time", "Time (s)")
            labelsColor: Theme.chartLabel
            gridLineColor: Theme.chartGrid
            labelFormat: "%g"
        }

        ValueAxis {
            id: axisY
            min: root.defaultYMin
            max: root.defaultYMax
            titleText: root.yAxisTitle
            labelsColor: Theme.chartLabel
            gridLineColor: Theme.chartGrid
            labelFormat: "%g"
        }

        Rectangle {
            id: zoomRect
            color: "transparent"
            border.color: Theme.accent
            border.width: 1
            visible: false
            z: 10
            Rectangle { anchors.fill: parent; color: Theme.accent; opacity: 0.18 }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            preventStealing: true

            property real lastX: 0
            property real lastY: 0
            property real startX: 0
            property real startY: 0

            function clampedXRange(newMin, newMax) {
                const maxLimit = root.dataMaximum()
                const span = newMax - newMin
                if (newMin < 0) {
                    newMin = 0
                    newMax = span
                }
                if (newMax > maxLimit) {
                    newMax = maxLimit
                    newMin = Math.max(0, newMax - span)
                }
                return [newMin, newMax]
            }

            onPressed: mouse => {
                if (!root.frozen)
                    return
                if (root.panMode) {
                    lastX = mouse.x
                    lastY = mouse.y
                } else {
                    startX = mouse.x
                    startY = mouse.y
                    zoomRect.x = startX
                    zoomRect.y = startY
                    zoomRect.width = 0
                    zoomRect.height = 0
                    zoomRect.visible = true
                }
            }

            onPositionChanged: mouse => {
                if (!root.frozen || !pressed)
                    return

                if (root.panMode) {
                    const plot = chart.plotArea
                    if (plot.width <= 0 || plot.height <= 0)
                        return
                    const xSpan = axisX.max - axisX.min
                    const range = clampedXRange(
                        axisX.min - ((mouse.x - lastX) / plot.width) * xSpan,
                        axisX.max - ((mouse.x - lastX) / plot.width) * xSpan
                    )
                    axisX.min = range[0]
                    axisX.max = range[1]

                    const ySpan = axisY.max - axisY.min
                    const yShift = ((mouse.y - lastY) / plot.height) * ySpan
                    root.setFrozenYRange(axisY.min + yShift, axisY.max + yShift)
                    lastX = mouse.x
                    lastY = mouse.y
                } else if (zoomRect.visible) {
                    zoomRect.x = Math.min(startX, mouse.x)
                    zoomRect.y = Math.min(startY, mouse.y)
                    zoomRect.width = Math.abs(mouse.x - startX)
                    zoomRect.height = Math.abs(mouse.y - startY)
                }
            }

            onReleased: {
                if (!root.frozen || root.panMode || !zoomRect.visible)
                    return
                zoomRect.visible = false
                if (zoomRect.width <= 10 || zoomRect.height <= 10)
                    return

                const plot = chart.plotArea
                if (plot.width <= 0 || plot.height <= 0)
                    return
                const left = Math.max(0, Math.min(1, (zoomRect.x - plot.x) / plot.width))
                const right = Math.max(0, Math.min(1, (zoomRect.x + zoomRect.width - plot.x) / plot.width))
                const lower = Math.max(0, Math.min(1, 1 - (zoomRect.y + zoomRect.height - plot.y) / plot.height))
                const upper = Math.max(0, Math.min(1, 1 - (zoomRect.y - plot.y) / plot.height))

                const oldXMin = axisX.min
                const oldXSpan = axisX.max - axisX.min
                const oldYMin = axisY.min
                const oldYSpan = axisY.max - axisY.min
                let newMin = oldXMin + oldXSpan * left
                let newMax = oldXMin + oldXSpan * right
                if (newMax - newMin < root.minimumXSpan) {
                    const center = (newMax + newMin) / 2
                    newMin = center - root.minimumXSpan / 2
                    newMax = center + root.minimumXSpan / 2
                }
                const range = clampedXRange(newMin, newMax)
                axisX.min = range[0]
                axisX.max = range[1]
                root.setFrozenYRange(oldYMin + oldYSpan * lower, oldYMin + oldYSpan * upper)
            }

            onCanceled: zoomRect.visible = false
            onDoubleClicked: {
                if (root.frozen)
                    root.resetView()
            }

            onWheel: wheel => {
                wheel.accepted = root.frozen
                if (!root.frozen)
                    return
                const plot = chart.plotArea
                if (plot.width <= 0 || plot.height <= 0)
                    return

                const factor = wheel.angleDelta.y > 0 ? 0.8 : 1.25
                const maxLimit = root.dataMaximum()
                const oldXSpan = axisX.max - axisX.min
                const newXSpan = Math.max(root.minimumXSpan, Math.min(maxLimit, oldXSpan * factor))
                const xRatio = Math.max(0, Math.min(1, (wheel.x - plot.x) / plot.width))
                const xAtPointer = axisX.min + oldXSpan * xRatio
                const range = clampedXRange(xAtPointer - newXSpan * xRatio, xAtPointer + newXSpan * (1 - xRatio))
                axisX.min = range[0]
                axisX.max = range[1]

                const oldYSpan = axisY.max - axisY.min
                const newYSpan = Math.max(0.0001, Math.min(2 * root.frozenYLimit, oldYSpan * factor))
                const yRatio = Math.max(0, Math.min(1, 1 - (wheel.y - plot.y) / plot.height))
                const yAtPointer = axisY.min + oldYSpan * yRatio
                const lower = yAtPointer - newYSpan * yRatio
                root.setFrozenYRange(lower, lower + newYSpan)
            }
        }
    }
}
