import QtQuick
import "../"

Text {
    property string labelText: ""
    property string hint: ""
    text: labelText.length > 0 ? labelText : hint
    color: Theme.subText
    font.family: Theme.fontFamily
    font.pixelSize: 12
    font.bold: true
}
