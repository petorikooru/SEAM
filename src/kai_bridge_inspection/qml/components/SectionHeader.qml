import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: header

    property string title: "Section"
    property string subtitle: ""

    spacing: 4

    Text {
        text: header.title
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 20
        font.bold: true
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }

    Text {
        visible: header.subtitle.length > 0
        text: header.subtitle
        color: Theme.subText
        font.family: Theme.fontFamily
        font.pixelSize: 13
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
}
