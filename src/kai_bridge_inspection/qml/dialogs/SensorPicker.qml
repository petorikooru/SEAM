import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "../"
import "../common"

Popup {
    id: picker

    signal sensorSelected(string profile)
    property string targetLocation: ""

    anchors.centerIn: Overlay.overlay
    width: Math.min(800, Overlay.overlay ? Overlay.overlay.width - 32 : 800)
    padding: 20
    modal: true
    focus: true

    background: Rectangle {
        color: Theme.dialog
        border.color: Theme.borderLight
        radius: 14
    }

    contentItem: ColumnLayout {
        spacing: 16

        Text {
            text: I18n.t("sensorPicker.title", "Choose a sensor")
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: [
                    {profile: "nemosense", name: "NemoSense", photo: "../assets/sensors/nemosense.png"},
                    {profile: "beandevice_accelerometer", name: "BeanDevice", photo: "../assets/sensors/beandevice.png"},
                    {profile: "custom", name: I18n.t("sensorStreams.custom", "Custom"), photo: ""}
                ]

                Button {
                    id: card
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 200
                    padding: 16
                    hoverEnabled: true
                    text: modelData.name
                    onClicked: picker.sensorSelected(modelData.profile)

                    background: Rectangle {
                        radius: 10
                        color: card.down ? Theme.controlPressed : card.hovered ? Theme.controlHover : Theme.card
                        border.color: card.activeFocus || card.hovered ? Theme.accent : Theme.border
                    }

                    contentItem: ColumnLayout {
                        spacing: 10

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Image {
                                anchors.fill: parent
                                visible: card.modelData.photo !== ""
                                source: card.modelData.photo
                                fillMode: Image.PreserveAspectFit
                            }

                            LucideIcon {
                                anchors.centerIn: parent
                                visible: card.modelData.photo === ""
                                icon: Icons.sensor
                                size: 54
                                color: Theme.accent
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: card.text
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                            font.bold: true
                        }
                    }
                }
            }
        }

        WinButton {
            Layout.alignment: Qt.AlignRight
            text: I18n.t("common.cancel", "Cancel")
            onClicked: picker.close()
        }
    }
}
