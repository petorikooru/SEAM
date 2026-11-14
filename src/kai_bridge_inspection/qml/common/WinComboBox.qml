import QtQuick
import QtQuick.Controls

import "../"

ComboBox {
    id: control

    implicitHeight: 40
    leftPadding: 12
    rightPadding: 34
    hoverEnabled: true

    indicator: LucideIcon {
        x: control.width - width - 12
        anchors.verticalCenter: parent.verticalCenter
        icon: Icons.chevronDown
        size: Theme.iconSizeSmall
        color: control.enabled ? Theme.subText : Theme.disabledText
    }

    contentItem: Text {
        text: control.displayText
        color: control.enabled ? Theme.text : Theme.disabledText
        font.family: Theme.fontFamily
        font.pixelSize: 13
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 8
        color: !control.enabled ? Theme.controlDisabled : control.hovered ? Theme.controlHover : Theme.controlBg
        border.color: control.activeFocus ? Theme.accent : Theme.border
    }

    delegate: ItemDelegate {
        id: option
        required property int index
        width: ListView.view ? ListView.view.width : control.width
        text: control.textAt(index)
        highlighted: control.highlightedIndex === index

        contentItem: Text {
            text: option.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: option.highlighted ? Theme.accentText : Theme.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 4
            color: option.highlighted ? Theme.accent : option.hovered ? Theme.controlHover : "transparent"
        }
    }

    popup: Popup {
        y: control.height + 4
        width: control.width
        padding: 4

        contentItem: ListView {
            clip: true
            implicitHeight: Math.min(contentHeight, 240)
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
        }

        background: Rectangle {
            color: Theme.card
            border.color: Theme.border
            radius: 8
        }
    }
}
