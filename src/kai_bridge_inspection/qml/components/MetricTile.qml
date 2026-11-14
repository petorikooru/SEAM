import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: tile

    property string label: "Metric"
    property string value: "0"
    property string unit: ""
    property string caption: ""
    property string iconText: Icons.chart
    property color accentColor: Theme.accent

    Layout.fillWidth: true
    Layout.minimumWidth: 190
    Layout.preferredHeight: 108
    radius: 12
    color: Theme.card
    border.color: Theme.border
    border.width: 1

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 4
        radius: 2
        color: tile.accentColor
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 16
        anchors.topMargin: 15
        anchors.bottomMargin: 15
        spacing: 14

        Rectangle {
            Layout.preferredWidth: 42
            Layout.preferredHeight: 42
            radius: 10
            color: Qt.rgba(tile.accentColor.r, tile.accentColor.g, tile.accentColor.b, Theme.darkMode ? 0.16 : 0.11)

            Text {
                anchors.centerIn: parent
                text: tile.iconText
                font.family: Icons.fontFamily
                font.pixelSize: 17
                color: tile.accentColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: tile.label
                color: Theme.subText
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            RowLayout {
                spacing: 6
                Text {
                    text: tile.value
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 25
                    font.bold: true
                }
                Text {
                    visible: tile.unit.length > 0
                    text: tile.unit
                    color: tile.accentColor
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 3
                }
            }

            Text {
                visible: tile.caption.length > 0
                text: tile.caption
                color: Theme.mutedText
                font.family: Theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }
}
