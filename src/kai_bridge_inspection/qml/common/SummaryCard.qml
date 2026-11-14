import QtQuick
import QtQuick.Layouts
import "../"

Rectangle {
    id: card

    property string labelText: ""
    property string valueText: ""
    property string iconText: ""
    property color accentColor: Theme.accent
    property string captionText: ""

    Layout.fillWidth: true
    Layout.preferredHeight: 92
    radius: 10
    color: Theme.card
    border.color: Theme.border

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: 9
            color: Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.14)
            LucideIcon {
                anchors.centerIn: parent
                icon: card.iconText
                color: card.accentColor
                size: Theme.iconSize
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: card.labelText; color: Theme.subText; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: card.valueText; color: Theme.text; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { visible: card.captionText.length > 0; text: card.captionText; color: Theme.mutedText; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
        }
    }
}
