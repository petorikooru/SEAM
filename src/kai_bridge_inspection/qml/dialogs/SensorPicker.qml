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
    dim: true
    transformOrigin: Popup.Center
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 210; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 120 }
    }
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

        GridLayout {
            Layout.fillWidth: true
            columns: picker.availableWidth >= 570 ? 3 : 1
            columnSpacing: 12
            rowSpacing: 8

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
                    implicitHeight: picker.availableWidth >= 570 ? 180 : 92
                    padding: 16
                    hoverEnabled: true
                    text: modelData.name
                    onClicked: picker.sensorSelected(modelData.profile)

                    background: Rectangle {
                        radius: 10
                        color: card.down ? Theme.controlPressed : card.hovered ? Theme.controlHover : Theme.card
                        border.color: card.visualFocus || card.hovered ? Theme.accent : Theme.border
                        border.width: card.visualFocus ? 2 : 1
                    }

                    contentItem: ColumnLayout {
                        spacing: 6

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 28

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
                                size: picker.availableWidth >= 570 ? 48 : 28
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
                            font.pixelSize: 16
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
