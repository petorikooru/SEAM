import QtQuick
import "../"

Rectangle {
    id: badge

    required property string numberText

    implicitWidth: 28
    implicitHeight: 28
    radius: 14
    color: Theme.accentSoft
    border.color: Theme.accent

    Text {
        anchors.centerIn: parent
        text: badge.numberText
        color: Theme.accent
        font.pixelSize: 12
        font.bold: true
    }
}
