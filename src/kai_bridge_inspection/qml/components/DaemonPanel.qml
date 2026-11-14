import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "../"
import "../common"

Rectangle {
    id: panel

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 32
    color: Theme.card
    radius: 8
    border.color: Theme.border

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    text: I18n.t("nodeRed.bridgeTitle", "Node-RED Stream Bridge")
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.text
                }
                Text {
                    text: I18n.t("nodeRed.bridgeSubtitle", "Direct WebSocket connection from named Node-RED output nodes to application widgets")
                    font.pixelSize: 13
                    color: Theme.subText
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                implicitWidth: stateText.implicitWidth + 18
                implicitHeight: 28
                radius: 14
                color: daemonController.mqttConnected ? "#1F7A4D" :
                       daemonController.running ? Theme.controlBg : Theme.danger
                Text {
                    id: stateText
                    anchors.centerIn: parent
                    text: daemonController.state
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: panel.width > 620 ? 4 : 2
            columnSpacing: 8
            rowSpacing: 8

            WinButton {
                text: I18n.t("nodeRed.connectStreams", "Connect streams")
                isAccent: !daemonController.collectionEnabled
                enabled: !daemonController.collectionEnabled
                onClicked: daemonController.startCollection()
            }
            WinButton {
                text: I18n.t("nodeRed.pauseStreams", "Pause")
                enabled: daemonController.collectionEnabled
                onClicked: daemonController.pauseCollection()
            }
            WinButton {
                text: I18n.t("nodeRed.reconnectStreams", "Reconnect")
                enabled: daemonController.running
                onClicked: daemonController.restartDaemon()
            }
            WinButton {
                text: I18n.t("nodeRed.disconnectStreams", "Disconnect")
                enabled: daemonController.running
                onClicked: daemonController.stopDaemon()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            LucideIcon {
                icon: Icons.nodeRed
                color: daemonController.mqttConnected ? Theme.success : Theme.warning
                size: Theme.iconSize
            }
            Text {
                Layout.fillWidth: true
                text: daemonController.connectedEndpointCount + " widget endpoint(s) connected"
                color: Theme.subText
                font.pixelSize: 12
            }
        }

        Text {
            Layout.fillWidth: true
            visible: daemonController.lastError !== ""
            text: daemonController.lastError
            color: Theme.dangerHover
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }
}
