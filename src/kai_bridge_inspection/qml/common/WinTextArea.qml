import QtQuick
import QtQuick.Controls

import "../"

TextArea {
    id: control

    color: Theme.text
    placeholderTextColor: Theme.mutedText
    selectionColor: Theme.accent
    selectedTextColor: Theme.accentText

    palette.text: Theme.text
    palette.placeholderText: Theme.mutedText
    palette.windowText: Theme.text

    font.pixelSize: 14
    padding: 13
    wrapMode: Text.WordWrap
    selectByMouse: true

    background: Rectangle {
        color: control.activeFocus ? Theme.controlFocus : Theme.controlBg
        radius: 8
        border.color: control.activeFocus ? Theme.accent : Theme.border
        border.width: control.activeFocus ? 2 : 1
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }
}
