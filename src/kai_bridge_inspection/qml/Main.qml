import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import "./common"
import "./dialogs"
import "./components"

ApplicationWindow {
    id: root

    width: 1320
    height: 820
    minimumWidth: 920
    minimumHeight: 640
    visible: true
    title: I18n.t("app.title", "SEAM")
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    font.family: Theme.fontFamily

    property string activePage: "dashboard"
    property var sidebarLocations: []
    property int sidebarDataRevision: 0
    property var appBackend: typeof backend !== "undefined" ? backend : null
    property var daemonApi: typeof daemonController !== "undefined" ? daemonController : null
    property bool sidebarCollapsed: false
    property bool compactUi: width < 1080

    readonly property int expandedSidebarWidth: Math.max(250, Math.min(310, width * 0.235))
    readonly property int collapsedSidebarWidth: 76
    readonly property int activeSidebarWidth: sidebarCollapsed ? collapsedSidebarWidth : expandedSidebarWidth
    readonly property int windowRadius: 16

    function refreshSidebar() {
        const names = appBackend ? appBackend.getLocationNames() : []
        // The location list can remain identical when only a sensor is removed.
        // Incrementing the revision forces existing location delegates to re-read
        // their sensor lists without destroying expansion or scroll state.
        sidebarLocations = names
        sidebarDataRevision += 1
    }

    function navigateTo(pageId, qmlFile, properties) {
        activePage = pageId
        mainStack.replace(qmlFile, properties || {})
    }

    function openAddLocation() {
        locationDialog.open()
    }

    function openAddSensor(locationKey) {
        sensorDialog.targetLocation = locationKey || ""
        sensorDialog.open()
    }

    function toggleMaximized() {
        if (visibility === Window.Maximized)
            showNormal()
        else
            showMaximized()
    }

    function activeTitle() {
        if (activePage === "dashboard") return I18n.t("app.bridgeOperations", "Bridge Operations")
        if (activePage === "settings") return I18n.t("nav.settings", "Settings")
        if (activePage === "nodered") return "Node-RED"
        if (activePage.indexOf("loc_") === 0) return I18n.t("app.locationOverview", "Location Overview")
        if (activePage.indexOf("sensor_") === 0) return I18n.t("app.sensorTelemetry", "Sensor Telemetry")
        return I18n.t("app.title", "KAI Bridge Inspection")
    }

    Component.onCompleted: {
        if (appBackend) {
            Theme.applyTheme(appBackend.getSetting("theme", "dark"))
            I18n.setLanguage(appBackend.getSetting("language", "en"))
        }
        refreshSidebar()
    }

    Connections {
        target: root.appBackend
        function onLocationAdded() { root.refreshSidebar() }
        function onSensorAdded() { root.refreshSidebar() }
    }

    component WindowControl: Button {
        id: control
        property string iconText: ""
        property bool danger: false

        implicitWidth: 32
        implicitHeight: 32
        padding: 0
        hoverEnabled: true

        background: Rectangle {
            radius: 7
            color: control.danger && control.hovered ? Theme.danger :
                   control.down ? Theme.controlPressed :
                   control.hovered ? Theme.controlHover : "transparent"
        }

        contentItem: LucideIcon {
            icon: control.iconText
            size: Theme.iconSizeSmall
            color: control.danger && control.hovered ? "white" : Theme.text
        }
    }

    Rectangle {
        id: appContainer
        anchors.fill: parent
        color: Theme.sidebarBg
        radius: root.visibility === Window.Maximized ? 0 : root.windowRadius
        border.color: root.visibility === Window.Maximized ? "transparent" : Theme.border
        border.width: root.visibility === Window.Maximized ? 0 : 1
        clip: true

        Sidebar {
            id: appSidebar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: root.activeSidebarWidth
            activePage: root.activePage
            sidebarLocations: root.sidebarLocations
            dataRevision: root.sidebarDataRevision
            appBackend: root.appBackend
            collapsed: root.sidebarCollapsed
            z: 20

            onToggleCollapsedRequested: root.sidebarCollapsed = !root.sidebarCollapsed
            onNavigateRequested: function(pageId, qmlFile, properties) {
                root.navigateTo(pageId, qmlFile, properties)
            }
            onAddLocationRequested: root.openAddLocation()
            onAddSensorRequested: function(locationKey) { root.openAddSensor(locationKey) }

            Behavior on width {
                NumberAnimation { duration: 210; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            id: topBar
            anchors.top: parent.top
            anchors.left: appSidebar.right
            anchors.right: parent.right
            height: root.compactUi ? 44 : 48
            color: Theme.sidebarBg
            z: 25

            DragHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse
                onActiveChanged: if (active) root.startSystemMove()
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onDoubleTapped: root.toggleMaximized()
            }

            RowLayout {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    text: root.activeTitle()
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }

                Rectangle {
                    width: 1
                    height: 18
                    color: Theme.border
                }

                StatusPill {
                    text: root.daemonApi ? root.daemonApi.state : I18n.t("app.unavailable", "Unavailable")
                    iconText: root.daemonApi && root.daemonApi.mqttConnected ? Icons.signal : Icons.plug
                    accentColor: root.daemonApi && root.daemonApi.mqttConnected ? Theme.success :
                                 root.daemonApi && root.daemonApi.running ? Theme.warning : Theme.mutedText
                }
            }
        }

        Rectangle {
            anchors.top: topBar.bottom
            anchors.left: appSidebar.right
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 8
            anchors.bottomMargin: 8
            color: Theme.surface
            radius: root.visibility === Window.Maximized ? 0 : 12
            border.color: Theme.border
            border.width: 1
            clip: true

            StackView {
                id: mainStack
                anchors.fill: parent
                clip: true
                initialItem: "pages/Dashboard.qml"

                replaceEnter: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "y"; from: 42; to: 0; duration: 240; easing.type: Easing.OutQuint }
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 }
                    }
                }
                replaceExit: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "y"; from: 0; to: -24; duration: 170; easing.type: Easing.OutQuint }
                        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160 }
                    }
                }
            }
        }

        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 8
            anchors.rightMargin: 8
            z: 999
            spacing: 6

            WindowControl {
                iconText: Icons.minimize
                onClicked: root.showMinimized()
            }
            WindowControl {
                iconText: root.visibility === Window.Maximized ? Icons.maximizeOn : Icons.maximizeOff
                onClicked: root.toggleMaximized()
            }
            WindowControl {
                iconText: Icons.cancel
                danger: true
                onClicked: root.close()
            }
        }
    }

    MouseArea { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 6; z: 1000; cursorShape: Qt.SizeHorCursor; acceptedButtons: Qt.LeftButton; onPressed: root.startSystemResize(Qt.RightEdge) }
    MouseArea { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 6; z: 1000; cursorShape: Qt.SizeHorCursor; acceptedButtons: Qt.LeftButton; onPressed: root.startSystemResize(Qt.LeftEdge) }
    MouseArea { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; acceptedButtons: Qt.LeftButton; onPressed: root.startSystemResize(Qt.TopEdge) }
    MouseArea { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 6; z: 1000; cursorShape: Qt.SizeVerCursor; acceptedButtons: Qt.LeftButton; onPressed: root.startSystemResize(Qt.BottomEdge) }
    MouseArea { anchors.right: parent.right; anchors.bottom: parent.bottom; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; acceptedButtons: Qt.LeftButton; onPressed: root.startSystemResize(Qt.BottomRightCorner) }
    MouseArea { anchors.left: parent.left; anchors.bottom: parent.bottom; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; acceptedButtons: Qt.LeftButton; onPressed: root.startSystemResize(Qt.BottomLeftCorner) }
    MouseArea { anchors.right: parent.right; anchors.top: parent.top; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeBDiagCursor; acceptedButtons: Qt.LeftButton; onPressed: root.startSystemResize(Qt.TopRightCorner) }
    MouseArea { anchors.left: parent.left; anchors.top: parent.top; width: 12; height: 12; z: 1001; cursorShape: Qt.SizeFDiagCursor; acceptedButtons: Qt.LeftButton; onPressed: root.startSystemResize(Qt.TopLeftCorner) }

    AddLocation { id: locationDialog; appBackend: root.appBackend }
    AddSensor { id: sensorDialog; appBackend: root.appBackend }
}
