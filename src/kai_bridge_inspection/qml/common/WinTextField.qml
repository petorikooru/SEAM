import QtQuick
import QtQuick.Controls

import "../"

TextField {
    id: control

    color: Theme.text
    placeholderTextColor: Theme.mutedText
    selectionColor: Theme.accent
    selectedTextColor: Theme.accentText

    palette.text: Theme.text
    palette.placeholderText: Theme.mutedText
    palette.windowText: Theme.text

    font.pixelSize: 14
    leftPadding: 13
    rightPadding: 13
    implicitHeight: 42
    selectByMouse: true

    background: Rectangle {
        color: control.activeFocus ? Theme.controlFocus : Theme.controlBg
        radius: 8
        border.color: control.activeFocus ? Theme.accent : Theme.border
        border.width: control.activeFocus ? 2 : 1
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }
}
