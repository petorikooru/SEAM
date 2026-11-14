import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning

import ".."
import "../components"

Page {
    id: page

    property var appBackend: typeof backend !== "undefined" ? backend : null
    property var daemonApi: typeof daemonController !== "undefined" ? daemonController : null
    property var locations: []
    property var filteredLocations: []
    property bool mapView: false
    property int totalSensors: 0
    property int cardColumns: width >= 1180 ? 3 : (width >= 760 ? 2 : 1)
    property int metricColumns: width >= 1050 ? 4 : (width >= 650 ? 2 : 1)

    background: Rectangle { color: Theme.surface }

    function loadLocations() {
        const names = appBackend ? appBackend.getLocationNames() : []
        let nextLocations = []
        let sensorTotal = 0
        for (let i = 0; i < names.length; ++i) {
            const raw = appBackend ? appBackend.getLocationData(names[i]) : ({})
            const sensors = raw.sensors || []
            sensorTotal += sensors.length
            nextLocations.push({
                "key": names[i],
                "name": raw.name || names[i],
                "description": raw.description || "No location description has been provided.",
                "lat": Number(raw.lat || 0),
                "lon": Number(raw.lon || 0),
                "sensors": sensors
            })
        }
        locations = nextLocations
        totalSensors = sensorTotal
        filterLocations()
    }

    function filterLocations() {
        const term = searchField.text.toLowerCase().trim()
        if (term.length === 0) {
            filteredLocations = locations
            return
        }
        let result = []
        for (let i = 0; i < locations.length; ++i) {
            const location = locations[i]
            let haystack = (location.name + " " + location.description).toLowerCase()
            for (let j = 0; j < location.sensors.length; ++j) {
                const sensor = appBackend ? appBackend.getSensorData(location.sensors[j]) : ({})
                haystack += " " + (sensor.name || location.sensors[j]) + " " + (sensor.description || "")
            }
            if (haystack.toLowerCase().indexOf(term) >= 0)
                result.push(location)
        }
        filteredLocations = result
    }

    function openLocation(locationKey) {
        if (typeof root !== "undefined" && root.navigateTo)
            root.navigateTo("loc_" + locationKey, "pages/Location.qml", {"locationName": locationKey})
    }

    function addLocation() {
        if (typeof root !== "undefined" && root.openAddLocation)
            root.openAddLocation()
    }

    function addSensor(locationKey) {
        if (typeof root !== "undefined" && root.openAddSensor)
            root.openAddSensor(locationKey)
    }

    function deleteLocation(locationKey) {
        if (appBackend) {
            appBackend.deleteLocation(locationKey)
            loadLocations()
            if (typeof root !== "undefined" && root.refreshSidebar)
                root.refreshSidebar()
        }
    }

    Component.onCompleted: loadLocations()

    Connections {
        target: page.appBackend
        function onLocationAdded() { page.loadLocations() }
        function onSensorAdded() { page.loadLocations() }
    }

    Plugin {
        id: osmPlugin
        name: "osm"
    }

    component ActionButton: Button {
        id: control
        property bool accent: false
        property bool danger: false
        property string iconText: ""

        implicitHeight: 38
        padding: 0
        hoverEnabled: true

        background: Rectangle {
            radius: 9
            color: !control.enabled ? Theme.controlDisabled :
                   control.accent ? (control.down ? Theme.accentPressed : (control.hovered ? Theme.accentHover : Theme.accent)) :
                   control.danger ? (control.hovered ? Qt.rgba(0.94, 0.27, 0.27, 0.16) : "transparent") :
                   control.down ? Theme.controlPressed : (control.hovered ? Theme.controlHover : Theme.controlBg)
            border.color: control.accent ? "transparent" : (control.danger ? Theme.danger : Theme.border)
            border.width: control.accent ? 0 : 1
        }

        contentItem: Row {
            anchors.centerIn: parent
            spacing: control.iconText.length > 0 ? 8 : 0
            Text {
                visible: control.iconText.length > 0
                text: control.iconText
                font.family: Icons.fontFamily
                font.pixelSize: Theme.iconSizeSmall
                color: !control.enabled ? Theme.disabledText :
                       control.accent ? Theme.accentText :
                       control.danger ? Theme.danger : Theme.text
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: control.text
                color: !control.enabled ? Theme.disabledText :
                       control.accent ? Theme.accentText :
                       control.danger ? Theme.danger : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: control.accent
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    component LocationCard: Rectangle {
        id: card
        required property var location

        Layout.fillWidth: true
        Layout.minimumWidth: 280
        Layout.preferredHeight: 238
        radius: 12
        color: Theme.card
        border.color: cardHover.containsMouse ? Theme.accent : Theme.border
        border.width: cardHover.containsMouse ? 2 : 1

        Behavior on border.color { ColorAnimation { duration: 140 } }

        MouseArea {
            id: cardHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 11

                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: 10
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.darkMode ? 0.16 : 0.11)
                    Text {
                        anchors.centerIn: parent
                        text: Icons.location
                        font.family: Icons.fontFamily
                        font.pixelSize: 17
                        color: Theme.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: card.location.name
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: card.location.sensors.length + (card.location.sensors.length === 1 ? " configured sensor" : " configured sensors")
                        color: Theme.subText
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        Layout.fillWidth: true
                    }
                }

                StatusPill {
                    text: page.daemonApi && page.daemonApi.mqttConnected ? "Live" : "Configured"
                    iconText: page.daemonApi && page.daemonApi.mqttConnected ? Icons.signal : Icons.check
                    accentColor: page.daemonApi && page.daemonApi.mqttConnected ? Theme.success : Theme.info
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

            Text {
                text: card.location.description
                color: Theme.subText
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: Icons.mapPin
                    font.family: Icons.fontFamily
                    font.pixelSize: Theme.iconSizeSmall
                    color: Theme.mutedText
                }
                Text {
                    text: card.location.lat.toFixed(5) + ", " + card.location.lon.toFixed(5)
                    color: Theme.mutedText
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ActionButton {
                    text: I18n.t("common.open", "Open")
                    iconText: Icons.chevronRight
                    accent: true
                    Layout.preferredWidth: 96
                    onClicked: page.openLocation(card.location.key)
                }
                ActionButton {
                    text: I18n.t("nav.addSensor", "Add sensor")
                    iconText: Icons.add
                    Layout.preferredWidth: 112
                    onClicked: page.addSensor(card.location.key)
                }
                Item { Layout.fillWidth: true }
                ActionButton {
                    text: ""
                    iconText: Icons.trash
                    danger: true
                    Layout.preferredWidth: 38
                    onClicked: page.deleteLocation(card.location.key)
                    ToolTip.visible: hovered
                    ToolTip.text: I18n.t("nav.deleteLocation", "Delete location")
                }
            }
        }
    }

    ScrollView {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        contentHeight: contentColumn.implicitHeight + pageMargin * 2
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        property int pageMargin: page.width < 720 ? 16 : 24

        ColumnLayout {
            id: contentColumn
            width: Math.max(0, scroller.availableWidth - scroller.pageMargin * 2)
            x: scroller.pageMargin
            y: scroller.pageMargin
            spacing: 20

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                SectionHeader {
                    title: "Structure Inspection Dashboard"
                    subtitle: "Operational overview of bridge locations, sensors, Node-RED streams, and inspection telemetry."
                    Layout.fillWidth: true
                }

                ActionButton {
                    visible: page.width >= 760
                    text: I18n.t("nav.addLocation", "Add location")
                    iconText: Icons.add
                    accent: true
                    Layout.preferredWidth: 128
                    onClicked: page.addLocation()
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: page.metricColumns
                rowSpacing: 14
                columnSpacing: 14

                MetricTile {
                    label: "Structure locations"
                    value: String(page.locations.length)
                    caption: "Configured inspection sites"
                    iconText: Icons.location
                    accentColor: Theme.accent
                }
                MetricTile {
                    label: "Registered sensors"
                    value: String(page.totalSensors)
                    caption: "Across all bridge locations"
                    iconText: Icons.sensor
                    accentColor: Theme.info
                }
                MetricTile {
                    label: "Node-RED bridge"
                    value: page.daemonApi ? page.daemonApi.state : "Unavailable"
                    caption: page.daemonApi && page.daemonApi.collectionEnabled ? "Widget streams enabled" : "Widget streams paused"
                    iconText: Icons.sync
                    accentColor: page.daemonApi && page.daemonApi.running ? Theme.success : Theme.warning
                }
                MetricTile {
                    label: "Node-RED streams"
                    value: page.daemonApi && page.daemonApi.mqttConnected ? "Online" : "Offline"
                    caption: page.daemonApi && page.daemonApi.mqttConnected ? "Receiving normalized telemetry" : "Check Node-RED endpoints"
                    iconText: Icons.signal
                    accentColor: page.daemonApi && page.daemonApi.mqttConnected ? Theme.success : Theme.danger
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: page.width < 650 ? 112 : 68
                radius: 12
                color: Theme.card
                border.color: Theme.border

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    columns: page.width < 650 ? 1 : 3
                    columnSpacing: 12
                    rowSpacing: 8

                    Rectangle {
                        Layout.preferredWidth: page.width < 650 ? -1 : 200
                        Layout.fillWidth: page.width < 650
                        Layout.preferredHeight: 40
                        radius: 10
                        color: Theme.controlBg
                        border.color: Theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4

                            Button {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                padding: 0
                                onClicked: page.mapView = false
                                background: Rectangle {
                                    radius: 7
                                    color: !page.mapView ? Theme.accent : "transparent"
                                }
                                contentItem: Text {
                                    text: Icons.dashboard + "  Grid"
                                    color: !page.mapView ? Theme.accentText : Theme.subText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: !page.mapView
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Button {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                padding: 0
                                onClicked: page.mapView = true
                                background: Rectangle {
                                    radius: 7
                                    color: page.mapView ? Theme.accent : "transparent"
                                }
                                contentItem: Text {
                                    text: Icons.mapPin + "  Map"
                                    color: page.mapView ? Theme.accentText : Theme.subText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: page.mapView
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    Item { visible: page.width >= 650; Layout.fillWidth: true }

                    TextField {
                        id: searchField
                        Layout.fillWidth: page.width < 650
                        Layout.preferredWidth: page.width >= 650 ? Math.min(330, page.width * 0.32) : -1
                        Layout.preferredHeight: 40
                        placeholderText: I18n.t("nav.search", "Search locations or sensors...")
                        color: Theme.text
                        placeholderTextColor: Theme.mutedText
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        leftPadding: 38
                        rightPadding: 12
                        onTextChanged: page.filterLocations()

                        background: Rectangle {
                            radius: 9
                            color: searchField.activeFocus ? Theme.controlFocus : Theme.controlBg
                            border.color: searchField.activeFocus ? Theme.accent : Theme.border
                            border.width: searchField.activeFocus ? 2 : 1
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 13
                                anchors.verticalCenter: parent.verticalCenter
                                text: Icons.search
                                font.family: Icons.fontFamily
                                font.pixelSize: Theme.iconSizeSmall
                                color: searchField.activeFocus ? Theme.accent : Theme.mutedText
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 310
                visible: page.filteredLocations.length === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    Text {
                        text: page.locations.length === 0 ? Icons.location : Icons.search
                        font.family: Icons.fontFamily
                        font.pixelSize: 54
                        color: Theme.mutedText
                        opacity: 0.55
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: page.locations.length === 0 ? "No bridge locations have been configured." : "No locations match the current search."
                        color: Theme.subText
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignHCenter
                    }
                    ActionButton {
                        visible: page.locations.length === 0
                        text: I18n.t("nav.addLocation", "Add location")
                        iconText: Icons.add
                        accent: true
                        Layout.preferredWidth: 150
                        Layout.alignment: Qt.AlignHCenter
                        onClicked: page.addLocation()
                    }
                }
            }

            GridLayout {
                visible: !page.mapView && page.filteredLocations.length > 0
                Layout.fillWidth: true
                columns: page.cardColumns
                columnSpacing: 16
                rowSpacing: 16

                Repeater {
                    model: page.filteredLocations
                    LocationCard {
                        required property var modelData
                        location: modelData
                    }
                }
            }

            Rectangle {
                visible: page.mapView && page.filteredLocations.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(450, page.height - 330)
                radius: 12
                color: Theme.card
                border.color: Theme.border
                clip: true

                Map {
                    id: locationMap
                    anchors.fill: parent
                    anchors.margins: 1
                    plugin: osmPlugin
                    zoomLevel: 5
                    minimumZoomLevel: 2
                    maximumZoomLevel: 20
                    center: page.filteredLocations.length > 0
                            ? QtPositioning.coordinate(page.filteredLocations[0].lat, page.filteredLocations[0].lon)
                            : QtPositioning.coordinate(-2.5, 118.0)

                    MapItemView {
                        model: page.filteredLocations
                        delegate: MapQuickItem {
                            required property var modelData
                            coordinate: QtPositioning.coordinate(modelData.lat, modelData.lon)
                            anchorPoint.x: marker.width / 2
                            anchorPoint.y: marker.height

                            sourceItem: Item {
                                id: marker
                                width: 48
                                height: 58

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 42
                                    height: 42
                                    radius: 21
                                    color: Theme.accent
                                    border.color: "white"
                                    border.width: 3
                                    scale: markerMouse.pressed ? 0.92 : (markerMouse.containsMouse ? 1.08 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 110 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: Icons.location
                                        font.family: Icons.fontFamily
                                        font.pixelSize: 17
                                        color: Theme.accentText
                                    }
                                }

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.topMargin: 38
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 12
                                    height: 12
                                    rotation: 45
                                    color: Theme.accent
                                }

                                MouseArea {
                                    id: markerMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page.openLocation(modelData.key)
                                }

                                ToolTip.visible: markerMouse.containsMouse
                                ToolTip.text: modelData.name + "\n" + modelData.sensors.length + " sensor" + (modelData.sensors.length === 1 ? "" : "s")
                                ToolTip.delay: 250
                            }
                        }
                    }

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function(event) {
                            locationMap.zoomLevel = Math.max(locationMap.minimumZoomLevel,
                                                             Math.min(locationMap.maximumZoomLevel,
                                                                      locationMap.zoomLevel + (event.angleDelta.y > 0 ? 0.75 : -0.75)))
                        }
                    }

                    DragHandler {
                        id: dashboardMapDrag
                        target: null
                        acceptedButtons: Qt.LeftButton
                        property real lastX: 0
                        property real lastY: 0
                        onActiveChanged: {
                            if (active) {
                                lastX = translation.x
                                lastY = translation.y
                            }
                        }
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
                        onScaleChanged: {
                            if (active)
                                locationMap.zoomLevel = Math.max(locationMap.minimumZoomLevel,
                                                                 Math.min(locationMap.maximumZoomLevel,
                                                                          startZoom + Math.log(scale) / Math.log(2)))
                        }
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onDoubleTapped: function(eventPoint) {
                            locationMap.center = locationMap.toCoordinate(eventPoint.position)
                            locationMap.zoomLevel = Math.min(locationMap.maximumZoomLevel, locationMap.zoomLevel + 1)
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 14
                    width: mapCaptionRow.implicitWidth + 24
                    height: 42
                    radius: 10
                    color: Theme.card
                    border.color: Theme.border

                    Row {
                        id: mapCaptionRow
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: Icons.location
                            font.family: Icons.fontFamily
                            color: Theme.accent
                            font.pixelSize: Theme.iconSizeSmall
                        }
                        Text {
                            text: page.filteredLocations.length + " bridge location" + (page.filteredLocations.length === 1 ? "" : "s")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                }

                Column {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 6

                    Repeater {
                        model: [
                            {"icon": Icons.plus, "tip": "Zoom in", "action": "in"},
                            {"icon": Icons.minus, "tip": "Zoom out", "action": "out"},
                            {"icon": Icons.pinPoint, "tip": "Reset map", "action": "reset"}
                        ]
                        delegate: Button {
                            required property var modelData
                            width: 40
                            height: 40
                            padding: 0
                            hoverEnabled: true
                            background: Rectangle {
                                radius: 9
                                color: parent.down ? Theme.controlPressed : (parent.hovered ? Theme.controlHover : Theme.card)
                                border.color: Theme.border
                            }
                            contentItem: Text {
                                text: modelData.icon
                                font.family: Icons.fontFamily
                                font.pixelSize: Theme.iconSizeSmall
                                color: Theme.text
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: modelData.tip
                            ToolTip.delay: 300
                            onClicked: {
                                if (modelData.action === "in")
                                    locationMap.zoomLevel = Math.min(locationMap.maximumZoomLevel, locationMap.zoomLevel + 1)
                                else if (modelData.action === "out")
                                    locationMap.zoomLevel = Math.max(locationMap.minimumZoomLevel, locationMap.zoomLevel - 1)
                                else {
                                    locationMap.zoomLevel = 5
                                    locationMap.center = page.filteredLocations.length > 0
                                            ? QtPositioning.coordinate(page.filteredLocations[0].lat, page.filteredLocations[0].lon)
                                            : QtPositioning.coordinate(-2.5, 118.0)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 14
                    width: mapHelp.implicitWidth + 22
                    height: 34
                    radius: 8
                    color: Theme.card
                    border.color: Theme.border
                    Text {
                        id: mapHelp
                        anchors.centerIn: parent
                        text: I18n.t("map.help", "Drag to pan · Scroll or pinch to zoom · Double-click to focus")
                        color: Theme.subText
                        font.pixelSize: 11
                    }
                }
            }

            Item { Layout.preferredHeight: 4 }
        }
    }
}
