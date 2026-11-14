import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../"
import "../../common"

Rectangle {
    id: card
    objectName: "sensorHeaderCard"

    property string sensorName: ""
    property var sensorData: ({})
    property bool editing: false

    signal editRequested()
    signal settingsRequested()
    signal historyRequested()
    signal exportRequested()
    signal deleteRequested()
    signal cancelRequested()
    signal saveRequested(string name, string description)

    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    implicitHeight: contentColumn.implicitHeight + 40
    color: Theme.card
    radius: 12
    border.color: Theme.border
    border.width: 1

    onEditingChanged: {
        if (editing) {
            editNameField.text = sensorData.name || sensorName
            editDescriptionField.text = sensorData.description || ""
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        spacing: 14

        GridLayout {
            Layout.fillWidth: true
            columns: card.width >= 860 ? 2 : 1
            columnSpacing: 20
            rowSpacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 260
                spacing: 7

                Text {
                    id: sensorNameLabel
                    objectName: "sensorNameLabel"
                    visible: !card.editing
                    text: card.sensorData.name || card.sensorName
                    color: Theme.text
                    font.pixelSize: 27
                    font.bold: true
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                WinTextField {
                    id: editNameField
                    objectName: "sensorNameEditor"
                    visible: card.editing
                    Layout.fillWidth: true
                    text: card.sensorData.name || card.sensorName
                    font.pixelSize: 21
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    LucideIcon {
                        icon: Icons.location
                        color: Theme.accent
                        size: Theme.iconSizeSmall
                    }

                    Text {
                        text: card.sensorData.location_name || I18n.t("sensor.gnssPending", "GNSS pending")
                        color: Theme.subText
                        font.pixelSize: 13
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            Flow {
                id: actionFlow
                objectName: "sensorPageActions"
                Layout.fillWidth: card.width < 860
                Layout.alignment: card.width >= 860 ? Qt.AlignRight | Qt.AlignTop : Qt.AlignLeft
                Layout.preferredWidth: card.width >= 860 ? implicitWidth : -1
                spacing: 8

                WinButton {
                    objectName: "sensorEditButton"
                    visible: !card.editing
                    iconName: Icons.edit; text: I18n.t("common.edit", "Edit")
                    implicitHeight: 36
                    onClicked: card.editRequested()
                }

                WinButton {
                    objectName: "sensorSettingsButton"
                    visible: !card.editing
                    iconName: Icons.settings; text: I18n.t("sensorSettings.title", "Sensor settings")
                    implicitHeight: 36
                    onClicked: card.settingsRequested()
                }

                WinButton {
                    objectName: "sensorHistoryButton"
                    visible: !card.editing
                    iconName: Icons.chart; text: I18n.t("common.history", "History")
                    implicitHeight: 36
                    onClicked: card.historyRequested()
                }

                WinButton {
                    objectName: "sensorExportButton"
                    visible: !card.editing
                    iconName: Icons.download; text: I18n.t("sensor.exportAllParameters", "Export All Parameters")
                    isAccent: true
                    implicitHeight: 36
                    onClicked: card.exportRequested()
                }

                WinButton {
                    objectName: "sensorDeleteButton"
                    visible: card.editing
                    iconName: Icons.trash; text: I18n.t("common.delete", "Delete")
                    isDanger: true
                    implicitHeight: 36
                    onClicked: card.deleteRequested()
                }

                WinButton {
                    objectName: "sensorCancelButton"
                    visible: card.editing
                    iconName: Icons.cancel; text: I18n.t("common.cancel", "Cancel")
                    implicitHeight: 36
                    onClicked: card.cancelRequested()
                }

                WinButton {
                    objectName: "sensorSaveButton"
                    visible: card.editing
                    iconName: Icons.save; text: I18n.t("common.save", "Save")
                    isAccent: true
                    implicitHeight: 36
                    enabled: editNameField.text.trim().length > 0
                    onClicked: card.saveRequested(editNameField.text.trim(), editDescriptionField.text.trim())
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.divider
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            FieldLabel {
                labelText: I18n.t("common.description", "Description")
            }

            Text {
                id: sensorDescriptionLabel
                objectName: "sensorDescriptionLabel"
                visible: !card.editing
                text: card.sensorData.description || I18n.t("sensor.descriptionEmpty", "No description provided for this sensor.")
                color: Theme.subText
                wrapMode: Text.WordWrap
                font.pixelSize: 14
                Layout.fillWidth: true
                Layout.minimumHeight: 42
            }

            WinTextArea {
                id: editDescriptionField
                objectName: "sensorDescriptionEditor"
                visible: card.editing
                Layout.fillWidth: true
                Layout.preferredHeight: 88
                text: card.sensorData.description || ""
            }
        }
    }
}
