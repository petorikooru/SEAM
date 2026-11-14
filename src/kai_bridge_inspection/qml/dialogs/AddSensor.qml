import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "../"
import "../common"

Popup {
    id: dialog

    width: Math.min(760, Overlay.overlay ? Overlay.overlay.width - 40 : 760)
    height: Math.min(680, Overlay.overlay ? Overlay.overlay.height - 40 : 680)
    modal: true
    dim: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: Overlay.overlay
    Overlay.modal: Rectangle { color: "#B8000000" }

    property string targetLocation: ""
    property var appBackend: typeof backend !== "undefined" ? backend : null
    property bool compact: width < 680

    function resetForm() {
        nameField.text = ""
        descField.text = ""
        deviceIdField.text = ""
        websocketEndpointField.text = ""
        errorLabel.text = ""
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: dialog.compact ? 18 : 24
        spacing: 18

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 12
                color: Theme.accentSoft
                LucideIcon {
                    anchors.centerIn: parent
                    icon: Icons.sensor
                    size: Theme.iconSizeLarge
                    color: Theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: I18n.t("addSensor.title", "Add sensor")
                    color: Theme.text
                    font.pixelSize: 23
                    font.bold: true
                }
                Text {
                    text: I18n.format("addSensor.subtitle", {"location": dialog.targetLocation || I18n.t("addSensor.selectedLocation", "the selected location")}, "Register a telemetry source at " + (dialog.targetLocation || "the selected location") + ".")
                    color: Theme.subText
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
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

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            radius: 10
            color: Theme.accentSoft
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                LucideIcon {
                    icon: Icons.location
                    color: Theme.accent
                    size: 16
                }
                Text {
                    text: I18n.t("addSensor.gnssNote", "GNSS coordinates are discovered from live telemetry and can be corrected later in Sensor Settings.")
                    color: Theme.text
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: parent.width
                spacing: 14

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: identityLayout.implicitHeight + 30
                    radius: 12
                    color: Theme.card
                    border.color: Theme.border

                    RowLayout {
                        id: identityLayout
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 14

                        StepBadge { numberText: "1"; Layout.alignment: Qt.AlignTop }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text { text: I18n.t("addSensor.identity", "Sensor identity"); color: Theme.text; font.pixelSize: 16; font.bold: true }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: dialog.compact ? 1 : 2
                                columnSpacing: 14
                                rowSpacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    FieldLabel { hint: I18n.t("addSensor.sensorName", "Sensor name") + " *" }
                                    WinTextField {
                                        id: nameField
                                        Layout.fillWidth: true
                                        placeholderText: I18n.t("addSensor.identityPlaceholder", "e.g. Pier-02-Inclinometer")
                                        onTextChanged: errorLabel.text = ""
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    FieldLabel { hint: I18n.t("addSensor.location", "Location") }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 42
                                        radius: 8
                                        color: Theme.controlDisabled
                                        border.color: Theme.border
                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: 13
                                            anchors.rightMargin: 13
                                            text: dialog.targetLocation || I18n.t("common.noLocation", "No location selected")
                                            color: Theme.subText
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                            font.pixelSize: 13
                                        }
                                    }
                                }
                            }

                            FieldLabel { hint: I18n.t("addSensor.description", "Description") }
                            WinTextArea {
                                id: descField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 72
                                placeholderText: I18n.t("addSensor.notesPlaceholder", "Installation point, purpose, or maintenance notes")
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: connectionLayout.implicitHeight + 30
                    radius: 12
                    color: Theme.card
                    border.color: Theme.border

                    RowLayout {
                        id: connectionLayout
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 14

                        StepBadge { numberText: "2"; Layout.alignment: Qt.AlignTop }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text { text: I18n.t("addSensor.connection", "Node-RED identity mapping"); color: Theme.text; font.pixelSize: 16; font.bold: true }

                            FieldLabel { hint: I18n.t("addSensor.deviceId", "Node-RED device_id") + " *" }
                            WinTextField {
                                id: deviceIdField
                                Layout.fillWidth: true
                                placeholderText: I18n.t("addSensor.deviceIdPlaceholder", "e.g. NEMOSENSE-01")
                                onTextChanged: {
                                    if (websocketEndpointField.text.trim().length === 0 || websocketEndpointField.autoGenerated) {
                                        const slug = text.trim().replace(/[^A-Za-z0-9_.:-]/g, "-").toLowerCase()
                                        websocketEndpointField.text = slug.length > 0 ? "kai/sensors/" + slug : ""
                                        websocketEndpointField.autoGenerated = true
                                    }
                                }
                            }

                            FieldLabel { hint: I18n.t("addSensor.websocketEndpoint", "Dedicated WebSocket path") + " *" }
                            WinTextField {
                                id: websocketEndpointField
                                property bool autoGenerated: true
                                Layout.fillWidth: true
                                placeholderText: "kai/sensors/nemosense-01"
                                onTextEdited: autoGenerated = false
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                LucideIcon { icon: Icons.nodeRed; color: Theme.info; size: Theme.iconSizeSmall }
                                Text {
                                    text: I18n.t("addSensor.nodeRedHelp", "The device_id must match Node-RED JSON. The WebSocket path must match this sensor's WebSocket Listener/Out path. MQTT remains configured only in Node-RED.")
                                    color: Theme.subText
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                Text {
                    id: errorLabel
                    Layout.fillWidth: true
                    visible: text.length > 0
                    color: Theme.danger
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.divider }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "* " + I18n.t("addSensor.requiredFields", "Required fields")
                color: Theme.mutedText
                font.pixelSize: 11
                Layout.fillWidth: true
            }

            WinButton {
                text: I18n.t("common.cancel", "Cancel")
                Layout.preferredWidth: 96
                onClicked: dialog.close()
            }

            WinButton {
                id: saveBtn
                text: Icons.save + "  " + I18n.t("addSensor.create", "Add sensor")
                isAccent: true
                Layout.preferredWidth: 132
                enabled: nameField.text.trim().length > 0 && deviceIdField.text.trim().length > 0 && websocketEndpointField.text.trim().length > 0

                onClicked: {
                    const success = dialog.appBackend ? dialog.appBackend.saveNewNodeRedSensor(
                        nameField.text.trim(),
                        descField.text.trim(),
                        deviceIdField.text.trim(),
                        websocketEndpointField.text.trim(),
                        dialog.targetLocation
                    ) : false

                    if (success) {
                        dialog.close()
                        dialog.resetForm()
                    } else {
                        errorLabel.text = I18n.t("addSensor.saveError", "The sensor could not be saved. Confirm that the name is unique and the selected location still exists.")
                    }
                }
            }
        }
    }
}
