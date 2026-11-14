import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: pill

    property string text: "Unknown"
    property color accentColor: Theme.mutedText
    property string iconText: ""

    implicitWidth: content.implicitWidth + 20
    implicitHeight: 28
    radius: 7
    color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, Theme.darkMode ? 0.16 : 0.11)
    border.color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.65)
    border.width: 1

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 7

        Text {
            visible: pill.iconText.length > 0
            text: pill.iconText
            font.family: Icons.fontFamily
            font.pixelSize: 11
            color: pill.accentColor
        }

        Text {
            text: pill.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            color: pill.accentColor
        }
    }
}
