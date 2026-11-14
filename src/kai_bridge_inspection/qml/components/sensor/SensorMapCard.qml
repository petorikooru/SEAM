import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning
import "../../"
import "../../common"

Rectangle {
    id: card

    property real latitude: -6.917464
    property real longitude: 107.619123
    readonly property alias map: sensorMap

    function recenter() {
        sensorMap.center = QtPositioning.coordinate(latitude, longitude)
        sensorMap.zoomLevel = 15
    }

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 250
    color: Theme.card
    radius: 10
    border.color: Theme.border
    clip: true

    Plugin { id: osmPlugin; name: "osm" }

    Map {
        id: sensorMap
        anchors.fill: parent
        plugin: osmPlugin
        center: QtPositioning.coordinate(card.latitude, card.longitude)
        zoomLevel: 15

        MapQuickItem {
            coordinate: QtPositioning.coordinate(card.latitude, card.longitude)
            anchorPoint.x: pin.width / 2
            anchorPoint.y: pin.height
            sourceItem: Text {
                id: pin
                text: Icons.mapPin
                font.family: Icons.fontFamily
                color: Theme.danger
                font.pixelSize: 26
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        property real lastX: 0
        property real lastY: 0

        onPressed: mouse => { lastX = mouse.x; lastY = mouse.y }
        onPositionChanged: mouse => {
            if (!pressed) return
            sensorMap.pan(Math.round(lastX - mouse.x), Math.round(lastY - mouse.y))
            lastX = mouse.x
            lastY = mouse.y
        }
        onWheel: wheel => {
            wheel.accepted = true
            sensorMap.zoomLevel = Math.max(sensorMap.minimumZoomLevel,
                                           Math.min(sensorMap.maximumZoomLevel,
                                                    sensorMap.zoomLevel + (wheel.angleDelta.y > 0 ? 0.75 : -0.75)))
        }
        onDoubleClicked: card.recenter()
    }

    PinchHandler {
        target: null
        property real startZoom: 0
        onActiveChanged: if (active) startZoom = sensorMap.zoomLevel
        onScaleChanged: if (active) sensorMap.zoomLevel = Math.max(sensorMap.minimumZoomLevel,
                                                                   Math.min(sensorMap.maximumZoomLevel,
                                                                            startZoom + Math.log(scale) / Math.log(2)))
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 10
        implicitWidth: mapLabel.implicitWidth + 16
        implicitHeight: mapLabel.implicitHeight + 8
        color: Theme.card
        radius: 6
        border.color: Theme.border
        Text {
            id: mapLabel
            anchors.centerIn: parent
            text: I18n.t("sensor.gnss", "GNSS Location")
            color: Theme.accent
            font.pixelSize: 11
            font.bold: true
        }
    }

    Column {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 6
        MapButton { iconText: Icons.plus; tip: I18n.t("map.zoomIn", "Zoom in"); onClicked: sensorMap.zoomLevel = Math.min(sensorMap.maximumZoomLevel, sensorMap.zoomLevel + 1) }
        MapButton { iconText: Icons.minus; tip: I18n.t("map.zoomOut", "Zoom out"); onClicked: sensorMap.zoomLevel = Math.max(sensorMap.minimumZoomLevel, sensorMap.zoomLevel - 1) }
        MapButton { iconText: Icons.pinPoint; tip: I18n.t("map.reset", "Recenter"); onClicked: card.recenter() }
    }
}
