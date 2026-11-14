import QtQuick

// Renders a bundled Lucide SVG tinted with a theme colour.
// Usage: LucideIcon { icon: Icons.save; size: Theme.iconSize; color: Theme.text }
Item {
    id: root

    property string icon: ""            // Lucide name, normally taken from Icons.*
    property color color: Theme.text
    property real size: Theme.iconSize
    property real strokeWidth: 2.5        // Lucide default; lower (1.5) reads lighter at 12-14 px

    implicitWidth: size
    implicitHeight: size

    function _hex2(v) {
        const s = Math.round(v * 255).toString(16)
        return s.length < 2 ? "0" + s : s
    }
    readonly property string _hex: "#" + _hex2(color.r) + _hex2(color.g) + _hex2(color.b)
    readonly property string _markup: Icons.svg(icon)

    Image {
        anchors.centerIn: parent
        width: root.size
        height: root.size
        sourceSize: Qt.size(Math.ceil(root.size), Math.ceil(root.size))
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: root.color.a
        visible: root._markup.length > 0
        source: root._markup.length === 0 ? "" :
            "data:image/svg+xml;charset=utf-8," + encodeURIComponent(
                root._markup.replace(/currentColor/g, root._hex)
                            .replace(/stroke-width="2"/, 'stroke-width="' + root.strokeWidth + '"'))
    }
}
