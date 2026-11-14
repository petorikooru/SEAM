import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning

import "../"
import "../common"

Popup {
    id: dialog

    width: Math.min(880, Overlay.overlay ? Overlay.overlay.width - 40 : 880)
    height: Math.min(720, Overlay.overlay ? Overlay.overlay.height - 40 : 720)
    modal: true
    dim: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: Overlay.overlay
    Overlay.modal: Rectangle { color: "#B8000000" }

    property var appBackend: typeof backend !== "undefined" ? backend : null
    property real pinLat: -6.917464
    property real pinLon: 107.619123
    property bool compact: width < 720

    function setPin(coordinate, recenter) {
        pinLat = coordinate.latitude
        pinLon = coordinate.longitude
        if (recenter)
            pickMap.center = coordinate
    }

    function resetForm() {
        nameField.text = ""
        descField.text = ""
        searchField.text = ""
        pinLat = -6.917464
        pinLon = 107.619123
        pickMap.center = QtPositioning.coordinate(pinLat, pinLon)
        pickMap.zoomLevel = 14
    }

    onOpened: nameField.forceActiveFocus()

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 210; easing.type: Easing.OutCubic }
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

    Plugin {
        id: osmPlugin
        name: "osm"
    }

    GeocodeModel {
        id: geocodeModel
        plugin: osmPlugin
        onStatusChanged: {
            if (status === GeocodeModel.Ready && count > 0)
                searchResultsPopup.open()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: dialog.compact ? 18 : 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 12
                color: Theme.accentSoft
                Text {
                    anchors.centerIn: parent
                    text: Icons.location
                    font.family: Icons.fontFamily
                    font.pixelSize: 19
                    color: Theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: I18n.t("addLocation.title", "Add location"); color: Theme.text; font.pixelSize: 23; font.bold: true }
                Text {
                    text: I18n.t("addLocation.subtitle", "Create a bridge inspection site and place it precisely on the map.")
                    color: Theme.subText
                    font.pixelSize: 13
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            WinButton {
                text: Icons.cancel
                isQuiet: true
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                onClicked: dialog.close()
                ToolTip.visible: hovered
                ToolTip.text: I18n.t("common.close", "Close")
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: dialog.compact ? 1 : 2
            columnSpacing: 16
            rowSpacing: 14

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: dialog.compact ? 0 : 280
                Layout.preferredWidth: dialog.compact ? -1 : 300
                Layout.maximumWidth: dialog.compact ? 10000 : 310
                Layout.minimumHeight: dialog.compact ? 230 : 0
                radius: 12
                color: Theme.card
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text { text: I18n.t("addLocation.details", "Location details"); color: Theme.text; font.pixelSize: 17; font.bold: true }
                    Text {
                        text: I18n.t("addLocation.detailsHelp", "Use a clear operational name so the site is easy to find in the dashboard and sidebar.")
                        color: Theme.subText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    FieldLabel { labelText: I18n.t("addLocation.locationName", "Location name") + " *" }
                    WinTextField {
                        id: nameField
                        Layout.fillWidth: true
                        placeholderText: I18n.t("addLocation.namePlaceholder", "e.g. Cikubang Bridge")
                    }

                    FieldLabel { labelText: I18n.t("addLocation.description", "Description") }
                    WinTextArea {
                        id: descField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 100
                        placeholderText: I18n.t("addLocation.descriptionPlaceholder", "Route, span, structural zone, or inspection notes")
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 88
                        radius: 9
                        color: Theme.controlBg
                        border.color: Theme.border

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 5
                            Text { text: I18n.t("addLocation.coordinates", "Selected coordinates"); color: Theme.subText; font.pixelSize: 11; font.bold: true }
                            Text {
                                text: dialog.pinLat.toFixed(6) + ",  " + dialog.pinLon.toFixed(6)
                                color: Theme.text
                                font.pixelSize: 15
                                font.bold: true
                                font.family: "monospace"
                            }
                            Text {
                                text: I18n.t("addLocation.movePin", "Double-click the map to move the pin.")
                                color: Theme.mutedText
                                font.pixelSize: 11
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: dialog.compact ? 0 : 430
                Layout.minimumHeight: dialog.compact ? 330 : 0
                radius: 12
                color: Theme.card
                border.color: Theme.border
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40

                                WinTextField {
                                    id: searchField
                                    anchors.fill: parent
                                    leftPadding: 38
                                    placeholderText: I18n.t("addLocation.searchPlaceholder", "Search city, bridge, or coordinates")
                                    onAccepted: {
                                        if (text.trim().length > 0) {
                                            geocodeModel.query = text.trim()
                                            geocodeModel.update()
                                        }
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 13
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Icons.search
                                        font.family: Icons.fontFamily
                                        color: searchField.activeFocus ? Theme.accent : Theme.mutedText
                                        font.pixelSize: Theme.iconSizeSmall
                                    }
                                }

                                Popup {
                                    id: searchResultsPopup
                                    y: searchField.height + 5
                                    width: searchField.width
                                    height: Math.min(240, Math.max(48, geocodeModel.count * 52))
                                    padding: 4
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                    background: Rectangle {
                                        color: Theme.dialog
                                        radius: 10
                                        border.color: Theme.borderLight
                                    }
                                    contentItem: ListView {
                                        clip: true
                                        model: geocodeModel
                                        boundsBehavior: Flickable.StopAtBounds
                                        delegate: ItemDelegate {
                                            width: ListView.view.width
                                            implicitHeight: 48
                                            contentItem: RowLayout {
                                                spacing: 9
                                                Text {
                                                    text: Icons.mapPin
                                                    font.family: Icons.fontFamily
                                                    color: highlighted ? Theme.accentText : Theme.accent
                                                    font.pixelSize: Theme.iconSizeSmall
                                                }
                                                Text {
                                                    text: locationData.address.text || (locationData.coordinate.latitude.toFixed(5) + ", " + locationData.coordinate.longitude.toFixed(5))
                                                    color: highlighted ? Theme.accentText : Theme.text
                                                    font.pixelSize: 12
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                            background: Rectangle {
                                                radius: 7
                                                color: highlighted ? Theme.accent : (hovered ? Theme.controlHover : "transparent")
                                            }
                                            onClicked: {
                                                dialog.setPin(locationData.coordinate, true)
                                                searchField.text = locationData.address.text || ""
                                                searchResultsPopup.close()
                                            }
                                        }
                                    }
                                }
                            }

                            WinButton {
                                text: Icons.search + "  " + I18n.t("common.find", "Find")
                                Layout.preferredWidth: 84
                                onClicked: {
                                    if (searchField.text.trim().length > 0) {
                                        geocodeModel.query = searchField.text.trim()
                                        geocodeModel.update()
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.divider }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Map {
                            id: pickMap
                            anchors.fill: parent
                            plugin: osmPlugin
                            center: QtPositioning.coordinate(dialog.pinLat, dialog.pinLon)
                            zoomLevel: 14
                            minimumZoomLevel: 2
                            maximumZoomLevel: 20

                            MapQuickItem {
                                coordinate: QtPositioning.coordinate(dialog.pinLat, dialog.pinLon)
                                anchorPoint.x: pinMarker.width / 2
                                anchorPoint.y: pinMarker.height
                                sourceItem: Item {
                                    id: pinMarker
                                    width: 42
                                    height: 52
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 38
                                        height: 38
                                        radius: 19
                                        color: Theme.accent
                                        border.color: "white"
                                        border.width: 3
                                        Text {
                                            anchors.centerIn: parent
                                            text: Icons.location
                                            font.family: Icons.fontFamily
                                            font.pixelSize: Theme.iconSizeSmall
                                            color: Theme.accentText
                                        }
                                    }
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.topMargin: 33
                                        width: 11
                                        height: 11
                                        rotation: 45
                                        color: Theme.accent
                                    }
                                }
                            }

                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: function(event) {
                                    pickMap.zoomLevel = Math.max(pickMap.minimumZoomLevel,
                                                               Math.min(pickMap.maximumZoomLevel,
                                                                        pickMap.zoomLevel + (event.angleDelta.y > 0 ? 0.75 : -0.75)))
                                }
                            }

                            DragHandler {
                                id: mapDrag
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
                                    pickMap.pan(Math.round(-dx), Math.round(-dy))
                                    lastX = translation.x
                                    lastY = translation.y
                                }
                            }

                            PinchHandler {
                                target: null
                                property real startZoom: 0
                                onActiveChanged: if (active) startZoom = pickMap.zoomLevel
                                onScaleChanged: {
                                    if (active)
                                        pickMap.zoomLevel = Math.max(pickMap.minimumZoomLevel,
                                                                    Math.min(pickMap.maximumZoomLevel,
                                                                             startZoom + Math.log(scale) / Math.log(2)))
                                }
                            }

                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onDoubleTapped: function(eventPoint) {
                                    dialog.setPin(pickMap.toCoordinate(eventPoint.position), false)
                                }
                            }
                        }

                        Column {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 6
                            MapButton { iconText: Icons.plus; tip: "Zoom in"; onClicked: pickMap.zoomLevel = Math.min(pickMap.maximumZoomLevel, pickMap.zoomLevel + 1) }
                            MapButton { iconText: Icons.minus; tip: "Zoom out"; onClicked: pickMap.zoomLevel = Math.max(pickMap.minimumZoomLevel, pickMap.zoomLevel - 1) }
                            MapButton {
                                iconText: Icons.pinPoint
                                tip: "Center on pin"
                                onClicked: pickMap.center = QtPositioning.coordinate(dialog.pinLat, dialog.pinLon)
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 12
                            width: instruction.implicitWidth + 22
                            height: 34
                            radius: 8
                            color: Theme.card
                            border.color: Theme.border
                            Text {
                                id: instruction
                                anchors.centerIn: parent
                                text: I18n.t("addLocation.mapHelp", "Drag to pan · Scroll or pinch to zoom · Double-click to place")
                                color: Theme.subText
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text { text: "* " + I18n.t("common.required", "Required field"); color: Theme.mutedText; font.pixelSize: 11; Layout.fillWidth: true }
            WinButton { text: I18n.t("common.cancel", "Cancel"); Layout.preferredWidth: 96; onClicked: dialog.close() }
            WinButton {
                text: Icons.save + "  " + I18n.t("addLocation.create", "Add location")
                isAccent: true
                Layout.preferredWidth: 142
                enabled: nameField.text.trim().length > 0
                onClicked: {
                    if (dialog.appBackend)
                        dialog.appBackend.saveNewLocation(nameField.text.trim(), descField.text.trim(), dialog.pinLat, dialog.pinLon)
                    dialog.close()
                    dialog.resetForm()
                }
            }
        }
    }
}
