import QtQuick
import QtQuick.Layouts
import "../"

RowLayout {
    id: row
    property string labelText: ""
    property string valueText: ""
    Layout.fillWidth: true
    spacing: 12
    Text { text: row.labelText; color: Theme.subText; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
    Text { text: row.valueText; color: Theme.text; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft; Layout.preferredWidth: 150 }
}
