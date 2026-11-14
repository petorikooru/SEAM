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
        if (pageId === "nodered")
            nodeRedPage.active = true
        else
            mainStack.replace(qmlFile, properties || {})
    }

    function openAddLocation() {
        locationDialog.open()
    }

    function openAddSensor(locationKey) {
        sensorPicker.targetLocation = locationKey || ""
        sensorPicker.open()
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

    property bool exportInProgress: false
    property bool exportToastDismissed: false
    property int unreadNotifications: 0
    property var latestNotification: null

    function notify(title, message, tone) {
        const entry = { heading: title, detail: message, tone: tone, stamp: Qt.formatTime(new Date(), "HH:mm:ss") }
        notificationHistory.insert(0, entry)
        if (notificationHistory.count > 50)
            notificationHistory.remove(50)
        if (!notificationPanel.visible)
            unreadNotifications++
        latestNotification = entry
        toastTimer.restart()
    }

    ListModel { id: notificationHistory }
    Timer { id: toastTimer; interval: 5500; onTriggered: root.latestNotification = null }

    Connections {
        target: root.appBackend
        function onNotificationRaised(title, message) { root.notify(title, message, "info") }
        function onSensorConnectionChanged(name, online) {
            root.notify(online ? I18n.t("notifications.sensorConnected", "Sensor connected")
                               : I18n.t("notifications.sensorDisconnected", "Sensor disconnected"),
                        name, online ? "success" : "error")
        }
        function onCsvExportStarted() {
            root.latestNotification = null
            toastTimer.stop()
            root.exportToastDismissed = false
            root.exportInProgress = true
        }
        function onCsvExportFinished(error) {
            root.exportInProgress = false
            root.notify(error ? I18n.t("notifications.exportFailed", "Export failed")
                              : I18n.t("notifications.exportDone", "Export complete"),
                        error, error ? "error" : "success")
        }
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

            Loader {
                id: nodeRedPage
                anchors.fill: parent
                active: false
                visible: root.activePage === "nodered"
                source: "pages/NodeRed.qml"
                onVisibleChanged: {
                    if (visible && status === Loader.Ready)
                        nodeRedEnter.restart()
                }
                onLoaded: {
                    if (visible)
                        nodeRedEnter.restart()
                }
                NumberAnimation on opacity {
                    id: nodeRedEnter
                    running: false
                    from: 0
                    to: 1
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            StackView {
                id: mainStack
                visible: root.activePage !== "nodered"
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
                iconText: Icons.info
                Accessible.name: I18n.t("notifications.title", "Notifications")
                ToolTip.visible: hovered
                ToolTip.text: Accessible.name
                onClicked: notificationPanel.visible ? notificationPanel.close() : notificationPanel.open()
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 4
                    width: 7
                    height: 7
                    radius: 4
                    color: Theme.accent
                    visible: root.unreadNotifications > 0
                }
            }
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

    component NotificationText: ColumnLayout {
        property string heading: ""
        property string detail: ""
        property string tone: ""
        property string stamp: ""
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: parent.heading
            font.bold: true
            color: parent.tone === "error" ? Theme.danger : parent.tone === "success" ? Theme.success : Theme.text
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        }
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: parent.detail
            color: Theme.subText
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Text {
            visible: text.length > 0
            text: parent.stamp
            color: Theme.subText
            font.pixelSize: 11
        }
    }

    Rectangle {
        parent: root.contentItem
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 54
        anchors.rightMargin: 16
        z: 998
        width: 320
        height: toastContent.implicitHeight + 28
        visible: !notificationPanel.visible && (root.latestNotification !== null ||
            (root.exportInProgress && !root.exportToastDismissed))
        color: Theme.dialog
        border.color: Theme.border
        radius: 10

        NotificationText {
            id: toastContent
            x: 14
            y: 14
            width: parent.width - 60
            heading: root.latestNotification ? root.latestNotification.heading
                : I18n.t("common.exportingTelemetry", "Exporting telemetry")
            detail: root.latestNotification ? root.latestNotification.detail
                : I18n.t("common.writingExport", "Writing the export file…")
            tone: root.latestNotification ? root.latestNotification.tone : "info"
        }
        WindowControl {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            iconText: Icons.cancel
            Accessible.name: I18n.t("notifications.dismiss", "Dismiss notification")
            onClicked: {
                if (root.latestNotification === null)
                    root.exportToastDismissed = true
                root.latestNotification = null
                toastTimer.stop()
            }
        }

    }

    Popup {
        id: notificationPanel
        objectName: "notificationPanel"
        parent: Overlay.overlay
        x: parent.width - width - 16
        y: 54
        width: 360
        height: Math.min(420, parent.height - y - 16)
        padding: 16
        focus: true
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170 }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 170; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 120 }
        }
        onAboutToShow: root.unreadNotifications = 0
        background: Rectangle { color: Theme.dialog; radius: 10; border.color: Theme.border }

        contentItem: ColumnLayout {
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("notifications.title", "Notifications")
                    color: Theme.text
                    font.pixelSize: 18
                    font.bold: true
                }
                WindowControl {
                    iconText: Icons.cancel
                    Accessible.name: I18n.t("common.close", "Close")
                    onClicked: notificationPanel.close()
                }
            }
            Text {
                visible: root.exportInProgress
                text: I18n.t("common.exportingTelemetry", "Exporting telemetry")
                color: Theme.accent
            }
            Text {
                visible: notificationHistory.count === 0 && !root.exportInProgress
                text: I18n.t("notifications.empty", "No notifications yet")
                color: Theme.subText
            }
            ListView {
                id: notificationList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: notificationHistory
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    width: notificationList.width - 10
                    height: entryText.implicitHeight + 20
                    radius: 8
                    color: Theme.controlBg
                    NotificationText {
                        id: entryText
                        x: 10
                        y: 10
                        width: parent.width - 20
                        heading: model.heading
                        detail: model.detail
                        tone: model.tone
                        stamp: model.stamp
                    }
                }
            }
        }
    }

    AddLocation { id: locationDialog; appBackend: root.appBackend }
    SensorPicker {
        id: sensorPicker
        onSensorSelected: function(profile) {
            close()
            sensorDialog.targetLocation = targetLocation
            sensorDialog.selectedProfile = profile
            sensorDialog.resetForm()
            sensorDialog.open()
        }
    }
    AddSensor { id: sensorDialog; appBackend: root.appBackend }
}
