import QtQuick
import QtQuick.Layouts
import "../"

Rectangle {
    id: card

    required property string labelText
    required property string valueText
    required property string iconText
    property color accentColor: Theme.accent

    Layout.fillWidth: true
    Layout.preferredHeight: 78
    radius: 10
    color: Theme.controlBg
    border.color: Theme.border

    RowLayout {
        anchors.fill: parent
        anchors.margins: 11
        spacing: 9

        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: 9
            color: Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.14)

            LucideIcon {
                anchors.centerIn: parent
                icon: card.iconText
                color: card.accentColor
                size: Theme.iconSizeSmall
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                text: card.labelText
                color: Theme.subText
                font.pixelSize: 10
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: card.valueText
                color: Theme.text
                font.pixelSize: 15
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }
}
