import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

import "../"
import "../common"
import "../components"

Page {
    id: page

    property var appBackend: typeof backend !== "undefined" ? backend : null
    property bool isConfiguring: webView.url.toString() === "" || configPanel.visible
    property bool loading: false
    property string loadState: webView.url.toString() === "" ? I18n.t("common.notConnected", "Not connected") : I18n.t("common.ready", "Ready")
    property string lastError: ""

    background: Rectangle { color: Theme.surface }

    function normalizedAddress(value) {
        return value.trim().replace(/\/$/, "")
    }

    function editorUrl(address, port) {
        const root = /^https?:\/\//.test(address) ? address : "http://" + address
        return root + ":" + port
    }

    function connectToNodeRed() {
        const address = normalizedAddress(addressInput.text)
        const port = portInput.text.trim()
        lastError = ""

        const numericPort = Number(port)
        if (address.length === 0 || !Number.isInteger(numericPort) || numericPort < 1 || numericPort > 65535) {
            lastError = I18n.t("nodeRed.invalid", "Enter a valid host and port from 1 to 65535.")
            return
        }
        if (appBackend)
            appBackend.saveNodeRedConfig(address, port)

        loadState = I18n.t("common.connecting", "Connecting")
        webView.url = editorUrl(address, port)
        configPanel.visible = false
    }

    Component.onCompleted: {
        addressInput.text = appBackend ? (appBackend.nodeRedAddress || "127.0.0.1") : "127.0.0.1"
        portInput.text = appBackend ? (appBackend.nodeRedPort || "1880") : "1880"
    }

    component ToolbarButton: WinButton {
        Layout.preferredHeight: 36
        cornerRadius: 8
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: page.width < 760 ? 16 : 22
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            SectionHeader {
                title: I18n.t("nodeRed.title", "Node-RED workspace")
                subtitle: I18n.t("nodeRed.subtitle", "Open the flow editor used to transform, route, and visualize inspection telemetry.")
                Layout.fillWidth: true
            }

            StatusPill {
                text: page.loading ? I18n.t("common.loading", "Loading") : page.loadState
                iconText: page.loading ? Icons.sync : Icons.nodeRed
                accentColor: page.lastError.length > 0 ? Theme.danger :
                             page.loading ? Theme.warning :
                             webView.url.toString() !== "" ? Theme.success : Theme.mutedText
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 58
            radius: 11
            color: Theme.card
            border.color: Theme.border

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 9
                    color: Theme.accentSoft
                    Text {
                        anchors.centerIn: parent
                        text: Icons.nodeRed
                        font.family: Icons.fontFamily
                        font.pixelSize: Theme.iconSizeSmall
                        color: Theme.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: webView.url.toString() !== "" ? webView.url.toString() : I18n.t("nodeRed.noEndpoint", "No Node-RED endpoint configured")
                        color: Theme.text
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                    Text {
                        text: page.lastError.length > 0 ? page.lastError : I18n.t("nodeRed.embedded", "The editor remains embedded inside the dashboard.")
                        color: page.lastError.length > 0 ? Theme.danger : Theme.subText
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                ToolbarButton {
                    text: Icons.refresh + "  " + I18n.t("nodeRed.reload", "Reload")
                    enabled: webView.url.toString() !== ""
                    onClicked: webView.reload()
                }
                ToolbarButton {
                    text: Icons.settings + "  " + I18n.t("nodeRed.connection", "Connection")
                    isAccent: configPanel.visible
                    onClicked: configPanel.visible = !configPanel.visible
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Theme.card
            border.color: Theme.border
            clip: true

            WebEngineView {
                id: webView
                anchors.fill: parent
                visible: url.toString() !== ""

                onLoadingChanged: function(loadRequest) {
                    page.loading = loadRequest.status === WebEngineView.LoadStartedStatus
                    if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                        page.loadState = I18n.t("common.connected", "Connected")
                        page.lastError = ""
                    } else if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                        page.loadState = I18n.t("app.unavailable", "Unavailable")
                        page.lastError = loadRequest.errorString || I18n.t("nodeRed.loadError", "Node-RED could not be loaded. Check the host, port, and service status.")
                        configPanel.visible = true
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: webView.url.toString() === "" && !configPanel.visible
                spacing: 12
                Text {
                    text: Icons.nodeRed
                    font.family: Icons.fontFamily
                    font.pixelSize: 52
                    color: Theme.mutedText
                    opacity: 0.5
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: I18n.t("nodeRed.connect", "Connect a Node-RED instance to open the flow editor.")
                    color: Theme.subText
                    font.pixelSize: 14
                    Layout.alignment: Qt.AlignHCenter
                }
                WinButton {
                    text: Icons.plug + "  " + I18n.t("nodeRed.configure", "Configure connection")
                    isAccent: true
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: configPanel.visible = true
                }
            }

            Rectangle {
                id: configPanel
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: Math.min(390, parent.width)
                visible: webView.url.toString() === ""
                color: Theme.dialog
                border.color: Theme.borderLight

                Behavior on width { NumberAnimation { duration: 160 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: I18n.t("nodeRed.settings", "Connection settings")
                            color: Theme.text
                            font.pixelSize: 20
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        WinButton {
                            visible: webView.url.toString() !== ""
                            text: Icons.cancel
                            isQuiet: true
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            onClicked: configPanel.visible = false
                        }
                    }

                    Text {
                        text: I18n.t("nodeRed.help", "Enter the address of the Node-RED service accessible from this workstation.")
                        color: Theme.subText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: I18n.t("nodeRed.host", "Host or IP address"); color: Theme.subText; font.pixelSize: 12; font.bold: true }
                        WinTextField {
                            id: addressInput
                            Layout.fillWidth: true
                            placeholderText: "127.0.0.1 or https://nodered.example"
                            onAccepted: page.connectToNodeRed()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: I18n.t("nodeRed.port", "HTTP port"); color: Theme.subText; font.pixelSize: 12; font.bold: true }
                        WinTextField {
                            id: portInput
                            Layout.fillWidth: true
                            placeholderText: "1880"
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 1; top: 65535 }
                            onAccepted: page.connectToNodeRed()
                        }
                    }

                    Text {
                        text: I18n.t("nodeRed.sensorEndpoints", "Per-sensor WebSocket routing")
                        color: Theme.text
                        font.pixelSize: 13
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: sensorRoutingHelp.implicitHeight + 24
                        radius: 10
                        color: Theme.controlBg
                        border.color: Theme.border
                        Text {
                            id: sensorRoutingHelp
                            anchors.fill: parent
                            anchors.margins: 12
                            text: I18n.t("nodeRed.sensorEndpointHelp", "Configure one WebSocket Listener/Out path for each sensor in Node-RED, then enter the same path in Add Sensor or Sensor Settings. One endpoint carries all metrics for that sensor.")
                            color: Theme.subText
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 82
                        radius: 10
                        color: Theme.controlBg
                        border.color: Theme.border
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            Text {
                                text: Icons.nodeRed
                                font.family: Icons.fontFamily
                                color: Theme.info
                                font.pixelSize: 17
                            }
                            Text {
                                text: I18n.t("nodeRed.example", "Editor: http://127.0.0.1:1880\nSensor stream: ws://127.0.0.1:1880/kai/sensors/nemosense-01")
                                color: Theme.subText
                                font.pixelSize: 12
                                lineHeight: 1.25
                                Layout.fillWidth: true
                            }
                        }
                    }

                    Text {
                        visible: page.lastError.length > 0
                        text: page.lastError
                        color: Theme.danger
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Item { Layout.fillHeight: true }

                    WinButton {
                        text: Icons.plug + "  " + I18n.t("nodeRed.connectButton", "Connect to Node-RED")
                        isAccent: true
                        Layout.fillWidth: true
                        enabled: addressInput.text.trim().length > 0 && portInput.acceptableInput
                        onClicked: page.connectToNodeRed()
                    }
                }
            }
        }
    }
}
