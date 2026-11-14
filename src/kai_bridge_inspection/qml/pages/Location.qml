import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning
import QtCharts

import "../"
import "../common"
import "../components"
import "../components/sensor"

Page {
    id: page

    property string locationName: "Unknown Location"
    property bool isEditing: false
    property var locData: ({})
    property var sensorList: []
    property int selectedSensorIndex: -1
    property string selectedSensorName: ""
    property var selectedSensorData: ({})
    property real tempLat: 0
    property real tempLon: 0
    property string liveTemp: "-- °C"
    property string liveBattery: "-- %"
    property string liveRssi: "-- dBm"
    property string liveSampleRate: "-- Hz"
    property var appBackend: typeof backend !== "undefined" ? backend : null
    property bool compact: width < 920
    property bool isFrozen: false
    property bool accelPanMode: true
    property bool inclPanMode: true

    onIsFrozenChanged: {
        if (page.appBackend)
            page.appBackend.setLiveChartsPaused(isFrozen)
        accelChart.frozen = isFrozen
        inclinoChart.frozen = isFrozen
        if (!isFrozen) {
            accelChart.resetView()
            inclinoChart.resetView()
        } else {
            accelChart.adjustFrozenRange()
            inclinoChart.adjustFrozenRange()
        }
    }

    background: Rectangle { color: Theme.surface }

    function loadData() {
        if (!appBackend) return
        locData = appBackend.getLocationData(locationName) || ({})
        sensorList = locData.sensors || []
        tempLat = Number(locData.lat || 0)
        tempLon = Number(locData.lon || 0)
        editNameField.text = locData.name || locationName
        editDescField.text = locData.description || ""
        locationMap.center = QtPositioning.coordinate(tempLat, tempLon)

        if (sensorList.length === 0) {
            selectSensor(-1)
        } else {
            let nextIndex = selectedSensorIndex
            if (nextIndex < 0 || nextIndex >= sensorList.length)
                nextIndex = 0
            selectSensor(nextIndex)
        }
    }

    function selectSensor(index) {
        if (appBackend && selectedSensorName.length > 0)
            appBackend.registerLiveCharts(selectedSensorName, null, null, null, null, null)

        // A frozen state belongs to the previously selected chart only.
        // Reset it before binding another sensor so the global backend render
        // timer cannot remain paused.
        isFrozen = false
        selectedSensorIndex = index
        selectedSensorName = index >= 0 && index < sensorList.length ? sensorList[index] : ""
        selectedSensorData = selectedSensorName.length > 0 && appBackend ? (appBackend.getSensorData(selectedSensorName) || ({})) : ({})

        accelChart.clearSeries()
        inclinoChart.clearSeries()
        resetLiveMetrics()
        updateLiveMetrics(selectedSensorData, true)

        if (appBackend && selectedSensorName.length > 0)
            appBackend.registerLiveCharts(
                selectedSensorName,
                accelChart.seriesAt(0), accelChart.seriesAt(1), accelChart.seriesAt(2),
                inclinoChart.seriesAt(0), inclinoChart.seriesAt(1)
            )
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

    function formattedMetric(value, decimals, suffix, fallback) {
        const numeric = Number(value)
        return isFinite(numeric) ? numeric.toFixed(decimals) + suffix : fallback
    }

    function resetLiveMetrics() {
        liveTemp = "-- °C"
        liveBattery = "-- %"
        liveRssi = "-- dBm"
        liveSampleRate = "-- Hz"
    }

    function updateLiveMetrics(data, replaceMissing) {
        if (!data) return
        const temp = metricValue(data, ["ACC/TEMPERATURE", "TEMPERATURE", "temp", "temperature"])
        const battery = metricValue(data, ["BATTERY", "BAT_FUEL_GAUGE_REPSOC", "battery"])
        const rssi = metricValue(data, ["CELLULAR_RSSI", "SIGNAL", "RSSI", "cellular_rssi"])
        const sampleRate = metricValue(data, ["INFERRED_SAMPLE_RATE", "INFERED_SAMPLE_RATE", "inferred_sample_rate", "infered_sample_rate", "sample_rate"])

        if (temp !== undefined) liveTemp = formattedMetric(temp, 2, " °C", liveTemp)
        else if (replaceMissing) liveTemp = "-- °C"
        if (battery !== undefined) liveBattery = formattedMetric(battery, 1, " %", liveBattery)
        else if (replaceMissing) liveBattery = "-- %"
        if (rssi !== undefined) liveRssi = formattedMetric(rssi, 0, " dBm", liveRssi)
        else if (replaceMissing) liveRssi = "-- dBm"
        if (sampleRate !== undefined) liveSampleRate = formattedMetric(sampleRate, 1, " Hz", liveSampleRate)
        else if (replaceMissing) liveSampleRate = "-- Hz"
    }

    function saveLocation() {
        if (!appBackend || editNameField.text.trim().length === 0) return
        const oldName = locationName
        const newName = editNameField.text.trim()
        appBackend.updateLocationMeta(oldName, newName, editDescField.text.trim(), tempLat, tempLon)
        locationName = newName
        isEditing = false
        loadData()
        if (typeof root !== "undefined") {
            root.activePage = "loc_" + newName
            if (root.refreshSidebar) root.refreshSidebar()
        }
    }

    function openSelectedSensor() {
        if (selectedSensorName.length === 0) return
        if (typeof root !== "undefined" && root.navigateTo)
            root.navigateTo("sensor_" + selectedSensorName, "pages/Sensor.qml", {"sensorName": selectedSensorName})
    }

    function addSensor() {
        if (typeof root !== "undefined" && root.openAddSensor)
            root.openAddSensor(locationName)
    }

    Component.onCompleted: {
        if (appBackend)
            appBackend.setLiveChartsPaused(false)
        loadData()
    }
    Component.onDestruction: {
        if (appBackend) {
            appBackend.setLiveChartsPaused(false)
            if (selectedSensorName.length > 0)
                appBackend.registerLiveCharts(selectedSensorName, null, null, null, null, null)
        }
    }

    Connections {
        target: page.appBackend
        function onSensorAdded() { page.loadData() }
        function onLocationAdded() { page.loadData() }
        function onIndicatorsUpdated(data) {
            if (data.device_id !== page.selectedSensorName)
                return
            for (const key in data)
                page.selectedSensorData[key] = data[key]
            // Telemetry batches are partial.  Preserve the last known values for
            // metrics that are not present in this particular batch.
            page.updateLiveMetrics(data, false)
        }
    }

    Plugin { id: osmPlugin; name: "osm" }

    GeocodeModel {
        id: geocodeModel
        plugin: osmPlugin
        onStatusChanged: if (status === GeocodeModel.Ready && count > 0) searchResults.open()
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: parent.width
            spacing: 16

            Item { Layout.preferredHeight: page.width < 720 ? 14 : 22 }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: page.width < 720 ? 16 : 22
                Layout.rightMargin: page.width < 720 ? 16 : 22
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                    radius: 12
                    color: Theme.accentSoft
                    LucideIcon { anchors.centerIn: parent; icon: Icons.location; size: Theme.iconSizeLarge; color: Theme.accent }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        visible: !page.isEditing
                        text: page.locData.name || page.locationName
                        color: Theme.text
                        font.pixelSize: 26
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    WinTextField {
                        id: editNameField
                        visible: page.isEditing
                        Layout.fillWidth: true
                        font.pixelSize: 18
                    }
                    Text {
                        text: page.sensorList.length + " registered sensor" + (page.sensorList.length === 1 ? "" : "s") +
                              "  ·  " + page.tempLat.toFixed(5) + ", " + page.tempLon.toFixed(5)
                        color: Theme.subText
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                ActionButton {
                    visible: !page.isEditing
                    text: Icons.add + " Add sensor"
                    isAccent: true
                    onClicked: page.addSensor()
                }
                ActionButton {
                    visible: !page.isEditing
                    text: Icons.edit + " Edit"
                    onClicked: page.isEditing = true
                }
                ActionButton {
                    visible: page.isEditing
                    text: I18n.t("common.cancel", "Cancel")
                    onClicked: {
                        page.isEditing = false
                        page.tempLat = Number(page.locData.lat || 0)
                        page.tempLon = Number(page.locData.lon || 0)
                        page.loadData()
                    }
                }
                ActionButton {
                    visible: page.isEditing
                    text: Icons.save + " Save"
                    isAccent: true
                    enabled: editNameField.text.trim().length > 0
                    onClicked: page.saveLocation()
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: page.width < 720 ? 16 : 22
                Layout.rightMargin: page.width < 720 ? 16 : 22
                columns: page.compact ? 1 : 2
                columnSpacing: 16
                rowSpacing: 16

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 320
                    radius: 12
                    color: Theme.card
                    border.color: Theme.border

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: I18n.t("location.overview", "Location overview"); color: Theme.text; font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
                            LucideIcon { icon: Icons.location; color: Theme.accent; size: Theme.iconSizeSmall }
                        }

                        Text {
                            visible: !page.isEditing
                            text: page.locData.description || "No location description has been provided."
                            color: Theme.subText
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        WinTextArea {
                            id: editDescField
                            visible: page.isEditing
                            Layout.fillWidth: true
                            Layout.preferredHeight: 100
                            placeholderText: I18n.t("location.descriptionPlaceholder", "Location description")
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.divider }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 10
                            MetricBox { labelText: I18n.t("location.sensorsCount", "Sensors"); valueText: String(page.sensorList.length); iconText: Icons.sensor; accentColor: Theme.info }
                            MetricBox { labelText: I18n.t("location.mapZoom", "Map zoom"); valueText: Number(locationMap.zoomLevel).toFixed(1); iconText: Icons.zoom; accentColor: Theme.accent }
                            MetricBox { labelText: I18n.t("location.latitude", "Latitude"); valueText: page.tempLat.toFixed(5); iconText: Icons.mapPin; accentColor: Theme.warning }
                            MetricBox { labelText: I18n.t("location.longitude", "Longitude"); valueText: page.tempLon.toFixed(5); iconText: Icons.mapPin; accentColor: Theme.warning }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 320
                    radius: 12
                    color: Theme.card
                    border.color: page.isEditing ? Theme.accent : Theme.border
                    border.width: page.isEditing ? 2 : 1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Item {
                            visible: page.isEditing
                            Layout.fillWidth: true
                            Layout.preferredHeight: 58

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    WinTextField {
                                        id: mapSearchField
                                        anchors.fill: parent
                                        leftPadding: 38
                                        placeholderText: I18n.t("location.searchPlaceholder", "Search place or coordinates")
                                        onAccepted: {
                                            if (text.trim().length > 0) {
                                                geocodeModel.query = text.trim()
                                                geocodeModel.update()
                                            }
                                        }
                                        LucideIcon { anchors.left: parent.left; anchors.leftMargin: 13; anchors.verticalCenter: parent.verticalCenter; icon: Icons.search; color: mapSearchField.activeFocus ? Theme.accent : Theme.mutedText; size: Theme.iconSizeSmall }
                                    }

                                    Popup {
                                        id: searchResults
                                        y: mapSearchField.height + 5
                                        width: mapSearchField.width
                                        height: Math.min(230, Math.max(48, geocodeModel.count * 50))
                                        padding: 4
                                        background: Rectangle { color: Theme.dialog; radius: 9; border.color: Theme.borderLight }
                                        contentItem: ListView {
                                            clip: true
                                            model: geocodeModel
                                            delegate: ItemDelegate {
                                                width: ListView.view.width
                                                implicitHeight: 46
                                                contentItem: Text {
                                                    text: locationData.address.text || (locationData.coordinate.latitude.toFixed(5) + ", " + locationData.coordinate.longitude.toFixed(5))
                                                    color: highlighted ? Theme.accentText : Theme.text
                                                    font.pixelSize: 12
                                                    elide: Text.ElideRight
                                                }
                                                background: Rectangle { radius: 7; color: highlighted ? Theme.accent : (hovered ? Theme.controlHover : "transparent") }
                                                onClicked: {
                                                    page.tempLat = locationData.coordinate.latitude
                                                    page.tempLon = locationData.coordinate.longitude
                                                    locationMap.center = locationData.coordinate
                                                    mapSearchField.text = locationData.address.text || ""
                                                    searchResults.close()
                                                }
                                            }
                                        }
                                    }
                                }

                                WinButton {
                                    text: Icons.search + " Find"
                                    Layout.preferredWidth: 82
                                    onClicked: {
                                        if (mapSearchField.text.trim().length > 0) {
                                            geocodeModel.query = mapSearchField.text.trim()
                                            geocodeModel.update()
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { visible: page.isEditing; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.divider }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Map {
                                id: locationMap
                                anchors.fill: parent
                                plugin: osmPlugin
                                center: QtPositioning.coordinate(page.tempLat, page.tempLon)
                                zoomLevel: 16
                                minimumZoomLevel: 2
                                maximumZoomLevel: 20

                                MapQuickItem {
                                    coordinate: QtPositioning.coordinate(page.tempLat, page.tempLon)
                                    anchorPoint.x: locationPin.width / 2
                                    anchorPoint.y: locationPin.height
                                    sourceItem: Item {
                                        id: locationPin
                                        width: 42
                                        height: 52
                                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 38; height: 38; radius: 19; color: Theme.accent; border.color: "white"; border.width: 3; LucideIcon { anchors.centerIn: parent; icon: Icons.location; color: Theme.accentText; size: Theme.iconSizeSmall } }
                                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: 34; width: 10; height: 10; rotation: 45; color: Theme.accent }
                                    }
                                }

                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: function(event) {
                                        locationMap.zoomLevel = Math.max(locationMap.minimumZoomLevel, Math.min(locationMap.maximumZoomLevel, locationMap.zoomLevel + (event.angleDelta.y > 0 ? 0.75 : -0.75)))
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
                                        locationMap.pan(Math.round(-dx), Math.round(-dy))
                                        lastX = translation.x
                                        lastY = translation.y
                                    }
                                }
                                PinchHandler {
                                    target: null
                                    property real startZoom: 0
                                    onActiveChanged: if (active) startZoom = locationMap.zoomLevel
                                    onScaleChanged: if (active) locationMap.zoomLevel = Math.max(locationMap.minimumZoomLevel, Math.min(locationMap.maximumZoomLevel, startZoom + Math.log(scale) / Math.log(2)))
                                }
                                TapHandler {
                                    enabled: page.isEditing
                                    acceptedButtons: Qt.LeftButton
                                    onDoubleTapped: function(eventPoint) {
                                        const coord = locationMap.toCoordinate(eventPoint.position)
                                        page.tempLat = coord.latitude
                                        page.tempLon = coord.longitude
                                    }
                                }
                            }

                            Column {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 5
                                MapButton { iconText: Icons.plus; tip: "Zoom in"; onClicked: locationMap.zoomLevel = Math.min(locationMap.maximumZoomLevel, locationMap.zoomLevel + 1) }
                                MapButton { iconText: Icons.minus; tip: "Zoom out"; onClicked: locationMap.zoomLevel = Math.max(locationMap.minimumZoomLevel, locationMap.zoomLevel - 1) }
                                MapButton { iconText: Icons.pinPoint; tip: "Center on location"; onClicked: locationMap.center = QtPositioning.coordinate(page.tempLat, page.tempLon) }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 10
                                width: mapHelp.implicitWidth + 20
                                height: 32
                                radius: 8
                                color: Theme.card
                                border.color: Theme.border
                                Text { id: mapHelp; anchors.centerIn: parent; text: page.isEditing ? "Pan/zoom · Double-click to move location" : "Pan with mouse · Scroll or pinch to zoom"; color: Theme.subText; font.pixelSize: 10 }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: sensorSection
                Layout.fillWidth: true
                Layout.leftMargin: page.width < 720 ? 16 : 22
                Layout.rightMargin: page.width < 720 ? 16 : 22
                Layout.minimumHeight: 470
                Layout.preferredHeight: Math.max(Layout.minimumHeight, sensorSectionContent.implicitHeight + 32)
                radius: 12
                color: Theme.card
                border.color: Theme.border

                ColumnLayout {
                    id: sensorSectionContent
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { text: I18n.t("location.sensors", "Sensors at this location"); color: Theme.text; font.pixelSize: 19; font.bold: true }
                            Text { text: I18n.t("location.sensorsHelp", "Select a sensor to review its current state and live motion channels."); color: Theme.subText; font.pixelSize: 11 }
                        }
                        ActionButton { text: Icons.add + " Add sensor"; isAccent: true; onClicked: page.addSensor() }
                    }

                    GridLayout {
                        id: sensorDetailGrid
                        Layout.fillWidth: true
                        Layout.preferredHeight: page.compact
                            ? 120 + sensorDetailPane.implicitHeight + rowSpacing
                            : Math.max(470, sensorDetailPane.implicitHeight)
                        columns: page.compact ? 1 : 2
                        columnSpacing: 14
                        rowSpacing: 12

                        Rectangle {
                            id: sensorListPane
                            Layout.fillWidth: page.compact
                            Layout.fillHeight: !page.compact
                            Layout.preferredWidth: page.compact ? -1 : 230
                            Layout.preferredHeight: page.compact ? 120 : sensorDetailPane.implicitHeight
                            Layout.minimumHeight: page.compact ? 120 : 0
                            radius: 10
                            color: Theme.controlBg
                            border.color: Theme.border

                            ListView {
                                id: sensorListView
                                anchors.fill: parent
                                anchors.margins: 7
                                model: page.sensorList
                                spacing: 5
                                clip: true
                                orientation: page.compact ? ListView.Horizontal : ListView.Vertical

                                delegate: Button {
                                    id: sensorItem
                                    width: page.compact ? Math.max(170, sensorListView.width / Math.max(1, Math.min(page.sensorList.length, 3))) : sensorListView.width
                                    height: page.compact ? sensorListView.height : 56
                                    padding: 0
                                    onClicked: page.selectSensor(index)
                                    background: Rectangle {
                                        radius: 8
                                        color: page.selectedSensorIndex === index ? Theme.accent : (sensorItem.hovered ? Theme.controlHover : "transparent")
                                    }
                                    contentItem: RowLayout {
                                        anchors.leftMargin: 11
                                        anchors.rightMargin: 9
                                        spacing: 9
                                        LucideIcon { icon: Icons.sensor; color: page.selectedSensorIndex === index ? Theme.accentText : Theme.info; size: Theme.iconSizeSmall }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text { text: modelData; color: page.selectedSensorIndex === index ? Theme.accentText : Theme.text; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Text { text: I18n.t("location.inspectionSensor", "Inspection sensor"); color: page.selectedSensorIndex === index ? Theme.accentSubText : Theme.subText; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                                        }
                                        LucideIcon { visible: !page.compact; icon: Icons.chevronRight; color: page.selectedSensorIndex === index ? Theme.accentText : Theme.mutedText; size: 10 }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: sensorDetailPane
                            Layout.fillWidth: true
                            Layout.fillHeight: !page.compact
                            implicitHeight: Math.max(330, selectedSensorContent.visible ? selectedSensorContent.implicitHeight + 26 : 330)
                            radius: 10
                            color: Theme.bg
                            border.color: Theme.border

                            ColumnLayout {
                                id: selectedSensorContent
                                anchors.fill: parent
                                anchors.margins: 13
                                spacing: 10
                                visible: page.selectedSensorName.length > 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text { text: page.selectedSensorData.name || page.selectedSensorName; color: Theme.text; font.pixelSize: 18; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                        Text { text: page.selectedSensorData.description || "No sensor description"; color: Theme.subText; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                    ActionButton { text: I18n.t("common.open", "Open"); onClicked: page.openSelectedSensor() }
                                    ActionButton {
                                        text: Icons.trash
                                        isDanger: true
                                        Layout.preferredWidth: 38
                                        onClicked: {
                                            if (page.appBackend) page.appBackend.deleteSensor(page.selectedSensorName)
                                            page.loadData()
                                        }
                                        ToolTip.visible: hovered
                                        ToolTip.text: I18n.t("nav.deleteSensor", "Delete sensor")
                                    }
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: page.width >= 1040 ? 4 : 2
                                    columnSpacing: 8
                                    rowSpacing: 8
                                    MetricBox { labelText: I18n.t("sensor.temperature", "Temperature"); valueText: page.liveTemp; iconText: Icons.temp; accentColor: Theme.warning }
                                    MetricBox { labelText: I18n.t("sensor.battery", "Battery"); valueText: page.liveBattery; iconText: Icons.battery; accentColor: Theme.success }
                                    MetricBox { labelText: I18n.t("sensor.signal", "Signal"); valueText: page.liveRssi; iconText: Icons.signal; accentColor: Theme.info }
                                    MetricBox { labelText: I18n.t("sensor.sampleRate", "Sample rate"); valueText: page.liveSampleRate; iconText: Icons.sampleRate; accentColor: Theme.accent }
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: columns === 2 ? 510 : 1036
                                    columns: page.width >= 1080 ? 2 : 1
                                    columnSpacing: 10
                                    rowSpacing: 10

                                    MotionChartPanel {
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
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: page.selectedSensorName.length === 0
                                spacing: 10
                                LucideIcon { icon: Icons.sensor; color: Theme.mutedText; opacity: 0.45; size: 46; Layout.alignment: Qt.AlignHCenter }
                                Text { text: page.sensorList.length === 0 ? "No sensors are installed at this location." : "Select a sensor to view telemetry."; color: Theme.subText; font.pixelSize: 13; Layout.alignment: Qt.AlignHCenter }
                                ActionButton { visible: page.sensorList.length === 0; text: Icons.add + " Add first sensor"; isAccent: true; Layout.alignment: Qt.AlignHCenter; onClicked: page.addSensor() }
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 18 }
        }
    }
}
