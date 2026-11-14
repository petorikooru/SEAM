import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: sidebarRoot

    property string activePage: "dashboard"
    property var sidebarLocations: []
    property int dataRevision: 0
    property var appBackend: null
    property bool collapsed: false
    property string searchText: ""
    property string contextLocationKey: ""
    property string contextSensorName: ""

    signal navigateRequested(string pageId, string qmlFile, var properties)
    signal addLocationRequested()
    signal addSensorRequested(string locationKey)
    signal toggleCollapsedRequested()

    color: Theme.sidebarBg

    function locationMatches(locationKey) {
        // Register the catalog revision as a binding dependency. This matters
        // when a sensor changes but the top-level location-name list does not.
        const revision = dataRevision
        if (searchText.trim().length === 0)
            return true
        const data = appBackend ? appBackend.getLocationData(locationKey) : ({})
        const term = searchText.toLowerCase().trim()
        const locationText = ((data.name || locationKey) + " " + (data.description || "")).toLowerCase()
        if (locationText.indexOf(term) >= 0)
            return true
        const sensors = data.sensors || []
        for (let i = 0; i < sensors.length; ++i) {
            const sensor = appBackend ? appBackend.getSensorData(sensors[i]) : ({})
            if (((sensor.name || sensors[i]) + " " + (sensor.description || "")).toLowerCase().indexOf(term) >= 0)
                return true
        }
        return false
    }

    component StyledMenu: Menu {
        topPadding: 6
        bottomPadding: 6
        background: Rectangle {
            implicitWidth: 210
            radius: 10
            color: Theme.dialog
            border.color: Theme.borderLight
            border.width: 1
        }
    }

    component StyledMenuItem: MenuItem {
        id: menuItem
        property string iconText: ""
        property bool danger: false
        leftPadding: 14
        rightPadding: 14
        implicitHeight: 38

        contentItem: RowLayout {
            spacing: 10
            LucideIcon {
                icon: menuItem.iconText
                size: Theme.iconSizeSmall
                color: menuItem.danger ? Theme.danger : (menuItem.highlighted ? Theme.accent : Theme.text)
            }
            Text {
                text: menuItem.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: menuItem.danger ? Theme.danger : Theme.text
                Layout.fillWidth: true
            }
        }

        background: Rectangle {
            x: 6
            width: parent.width - 12
            radius: 7
            color: menuItem.highlighted ? Theme.controlHover : "transparent"
        }
    }

    StyledMenu {
        id: locationMenu
        StyledMenuItem {
            iconText: Icons.add
            text: I18n.t("nav.addSensor", "Add sensor")
            onTriggered: sidebarRoot.addSensorRequested(sidebarRoot.contextLocationKey)
        }
        StyledMenuItem {
            iconText: Icons.edit
            text: I18n.t("nav.editLocation", "Edit location")
            onTriggered: sidebarRoot.navigateRequested(
                "loc_" + sidebarRoot.contextLocationKey,
                "pages/Location.qml",
                {"locationName": sidebarRoot.contextLocationKey, "isEditing": true}
            )
        }
        MenuSeparator { contentItem: Rectangle { implicitHeight: 1; color: Theme.border } }
        StyledMenuItem {
            iconText: Icons.trash
            text: I18n.t("nav.deleteLocation", "Delete location")
            danger: true
            onTriggered: {
                if (sidebarRoot.appBackend)
                    sidebarRoot.appBackend.deleteLocation(sidebarRoot.contextLocationKey)
                sidebarRoot.navigateRequested("dashboard", "pages/Dashboard.qml", {})
            }
        }
    }

    StyledMenu {
        id: sensorMenu
        StyledMenuItem {
            iconText: Icons.edit
            text: I18n.t("nav.editSensor", "Edit sensor")
            onTriggered: sidebarRoot.navigateRequested(
                "sensor_" + sidebarRoot.contextSensorName,
                "pages/Sensor.qml",
                {"sensorName": sidebarRoot.contextSensorName, "isEditing": true}
            )
        }
        MenuSeparator { contentItem: Rectangle { implicitHeight: 1; color: Theme.border } }
        StyledMenuItem {
            iconText: Icons.trash
            text: I18n.t("nav.deleteSensor", "Delete sensor")
            danger: true
            onTriggered: {
                if (sidebarRoot.appBackend)
                    sidebarRoot.appBackend.deleteSensor(sidebarRoot.contextSensorName)
                sidebarRoot.navigateRequested("dashboard", "pages/Dashboard.qml", {})
            }
        }
    }

    component NavButton: Button {
        id: control

        property string iconText: ""
        property string labelText: ""
        property string tooltipText: labelText
        property bool active: false
        property int indent: 0
        property bool subtle: false
        property bool expandable: false
        property bool expanded: false

        signal rightClicked()
        signal expansionRequested()

        Layout.fillWidth: true
        Layout.preferredHeight: sidebarRoot.collapsed ? 46 : 42
        padding: 0
        hoverEnabled: true

        contentItem: Item {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: sidebarRoot.collapsed ? 0 : 14 + control.indent
                anchors.rightMargin: sidebarRoot.collapsed ? 0 : 10
                spacing: 11

                LucideIcon {
                    icon: control.iconText
                    size: Theme.iconSize
                    color: control.active ? Theme.accentText : (control.subtle ? Theme.subText : Theme.text)
                    Layout.preferredWidth: sidebarRoot.collapsed ? parent.width : 18
                }

                Text {
                    visible: !sidebarRoot.collapsed
                    text: control.labelText
                    color: control.active ? Theme.accentText : (control.subtle ? Theme.subText : Theme.text)
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: control.active
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Item {
                    visible: !sidebarRoot.collapsed && control.expandable
                    Layout.preferredWidth: 26
                    Layout.fillHeight: true

                    LucideIcon {
                        anchors.centerIn: parent
                        icon: Icons.chevronRight
                        size: Theme.iconSizeSmall
                        color: control.active ? Theme.accentText : Theme.subText
                        rotation: control.expanded ? 90 : 0
                        Behavior on rotation { NumberAnimation { duration: 150 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            control.expansionRequested()
                            mouse.accepted = true
                        }
                    }
                }
            }
        }

        background: Rectangle {
            radius: 10
            color: control.active ? Theme.accent :
                   control.down ? Theme.controlPressed :
                   control.hovered ? Theme.controlHover : "transparent"
            border.color: control.active ? Theme.accent : "transparent"
            Behavior on color { ColorAnimation { duration: 130 } }
        }

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: control.rightClicked()
        }

        ToolTip.visible: sidebarRoot.collapsed && control.hovered
        ToolTip.text: control.tooltipText
        ToolTip.delay: 450
    }

    component SearchField: TextField {
        id: field
        visible: !sidebarRoot.collapsed
        Layout.fillWidth: true
        Layout.preferredHeight: 38
        placeholderText: I18n.t("nav.search", "Search locations or sensors...")
        color: Theme.text
        placeholderTextColor: Theme.mutedText
        font.family: Theme.fontFamily
        font.pixelSize: 12
        leftPadding: 36
        rightPadding: 10
        selectByMouse: true

        background: Rectangle {
            radius: 9
            color: field.activeFocus ? Theme.controlFocus : Theme.controlBg
            border.color: field.activeFocus ? Theme.accent : Theme.border
            border.width: field.activeFocus ? 2 : 1

            LucideIcon {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                icon: Icons.search
                size: Theme.iconSizeSmall
                color: field.activeFocus ? Theme.accent : Theme.mutedText
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: sidebarRoot.collapsed ? 10 : 12
        anchors.rightMargin: sidebarRoot.collapsed ? 10 : 12
        anchors.bottomMargin: 12
        spacing: 5

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 74

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: sidebarRoot.collapsed ? 1 : 4
                anchors.rightMargin: sidebarRoot.collapsed ? 1 : 4
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                    radius: 12
                    color: "white"
                    border.color: Theme.darkMode ? "transparent" : Theme.border

                    Image {
                        anchors.centerIn: parent
                        source: "assets/KAI.svg"
                        width: 34
                        height: 24
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }

                ColumnLayout {
                    visible: !sidebarRoot.collapsed
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: "SEAM"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                    }
                    Text {
                        text: "Structure Evaluation and Acquisition Measurement"
                        color: Theme.subText
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            MouseArea {
                id: brandArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: sidebarRoot.toggleCollapsedRequested()
            }

            ToolTip.visible: sidebarRoot.collapsed && brandArea.containsMouse
            ToolTip.text: I18n.t("nav.expand", "Expand navigation")
            ToolTip.delay: 450
        }

        NavButton {
            iconText: Icons.dashboard
            labelText: I18n.t("nav.dashboard", "Dashboard")
            active: sidebarRoot.activePage === "dashboard"
            onClicked: sidebarRoot.navigateRequested("dashboard", "pages/Dashboard.qml", {})
        }

        NavButton {
            iconText: Icons.nodeRed
            labelText: I18n.t("nav.nodeRed", "Node-RED")
            active: sidebarRoot.activePage === "nodered"
            onClicked: sidebarRoot.navigateRequested("nodered", "pages/NodeRed.qml", {})
        }

        NavButton {
            iconText: Icons.settings
            labelText: I18n.t("nav.settings", "Settings")
            active: sidebarRoot.activePage === "settings"
            onClicked: sidebarRoot.navigateRequested("settings", "pages/Settings.qml", {})
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 7
            Layout.bottomMargin: 4
            color: Theme.border
        }

        Text {
            visible: !sidebarRoot.collapsed
            text: I18n.t("nav.bridgeLocations", "BRIDGE LOCATIONS")
            color: Theme.mutedText
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
            Layout.leftMargin: 10
            Layout.bottomMargin: 3
        }

        SearchField {
            id: searchField
            text: sidebarRoot.searchText
            onTextChanged: sidebarRoot.searchText = text
            Layout.bottomMargin: 4
        }

        ScrollView {
            id: locationScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: sidebarRoot.collapsed ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded

            ColumnLayout {
                width: locationScroll.availableWidth
                spacing: 5

                Text {
                    visible: !sidebarRoot.collapsed && sidebarRoot.sidebarLocations.length === 0
                    text: I18n.t("nav.emptyLocations", "No locations yet. Add one to begin.")
                    color: Theme.mutedText
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                }

                Repeater {
                    model: sidebarRoot.sidebarLocations

                    delegate: ColumnLayout {
                        id: locationDelegate
                        required property var modelData

                        property string locationKey: String(modelData)
                        property var locationData: {
                            const revision = sidebarRoot.dataRevision
                            return sidebarRoot.appBackend
                                    ? sidebarRoot.appBackend.getLocationData(locationKey)
                                    : ({})
                        }
                        property var sensors: locationData.sensors || []
                        property bool expanded: true
                        property bool matches: sidebarRoot.locationMatches(locationKey)

                        visible: matches
                        Layout.fillWidth: true
                        spacing: 4

                        NavButton {
                            iconText: Icons.location
                            labelText: locationDelegate.locationData.name || locationDelegate.locationKey
                            tooltipText: labelText
                            active: sidebarRoot.activePage === "loc_" + locationDelegate.locationKey
                            expandable: locationDelegate.sensors.length > 0
                            expanded: locationDelegate.expanded
                            onClicked: sidebarRoot.navigateRequested(
                                "loc_" + locationDelegate.locationKey,
                                "pages/Location.qml",
                                {"locationName": locationDelegate.locationKey}
                            )
                            onExpansionRequested: locationDelegate.expanded = !locationDelegate.expanded
                            onRightClicked: {
                                sidebarRoot.contextLocationKey = locationDelegate.locationKey
                                locationMenu.popup()
                            }
                        }

                        ColumnLayout {
                            visible: locationDelegate.expanded
                            Layout.fillWidth: true
                            spacing: 3

                            Repeater {
                                model: locationDelegate.sensors

                                NavButton {
                                    required property var modelData
                                    property var sensorData: {
                                        const revision = sidebarRoot.dataRevision
                                        return sidebarRoot.appBackend
                                                ? sidebarRoot.appBackend.getSensorData(String(modelData))
                                                : ({})
                                    }

                                    iconText: Icons.sensor
                                    labelText: sensorData.name || String(modelData)
                                    tooltipText: (locationDelegate.locationData.name || locationDelegate.locationKey) + " / " + labelText
                                    indent: sidebarRoot.collapsed ? 0 : 14
                                    active: sidebarRoot.activePage === "sensor_" + String(modelData)
                                    subtle: !active
                                    onClicked: sidebarRoot.navigateRequested(
                                        "sensor_" + String(modelData),
                                        "pages/Sensor.qml",
                                        {"sensorName": String(modelData)}
                                    )
                                    onRightClicked: {
                                        sidebarRoot.contextLocationKey = locationDelegate.locationKey
                                        sidebarRoot.contextSensorName = String(modelData)
                                        sensorMenu.popup()
                                    }
                                }
                            }

                            NavButton {
                                visible: !sidebarRoot.collapsed
                                iconText: Icons.add
                                labelText: I18n.t("nav.addSensor", "Add sensor")
                                indent: 14
                                subtle: true
                                onClicked: sidebarRoot.addSensorRequested(locationDelegate.locationKey)
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            color: Theme.border
        }

        Button {
            id: addLocationButton
            Layout.fillWidth: true
            Layout.preferredHeight: sidebarRoot.collapsed ? 48 : 56
            padding: 0
            hoverEnabled: true
            onClicked: sidebarRoot.addLocationRequested()

            contentItem: Item {
                LucideIcon {
                    visible: sidebarRoot.collapsed
                    anchors.centerIn: parent
                    icon: Icons.add
                    size: Theme.iconSizeLarge
                    color: Theme.accentText
                }

                RowLayout {
                    visible: !sidebarRoot.collapsed
                    anchors.fill: parent
                    anchors.leftMargin: 15
                    anchors.rightMargin: 14
                    spacing: 12

                    LucideIcon {
                        icon: Icons.add
                        size: Theme.iconSize
                        color: Theme.accentText
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: I18n.t("nav.addLocation", "Add location")
                            color: Theme.accentText
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Text {
                            text: I18n.t("nav.addLocationHint", "Create a bridge inspection site")
                            color: Theme.accentSubText
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            background: Rectangle {
                radius: 10
                color: addLocationButton.down ? Theme.accentPressed :
                       addLocationButton.hovered ? Theme.accentHover : Theme.accent
            }

            ToolTip.visible: sidebarRoot.collapsed && addLocationButton.hovered
            ToolTip.text: I18n.t("nav.addLocation", "Add location")
            ToolTip.delay: 450
        }

        Text {
            Layout.fillWidth: true
            text: sidebarRoot.collapsed ? Theme.version : "KAI Bridge Inspection  " + Theme.version
            color: Theme.mutedText
            font.family: Theme.fontFamily
            font.pixelSize: sidebarRoot.collapsed ? 9 : 10
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
