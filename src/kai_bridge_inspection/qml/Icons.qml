pragma Singleton
import QtQuick

QtObject {
    id: icons

    readonly property bool nerdFontAvailable: Theme.nerdFontAvailable
    readonly property string fontFamily: nerdFontAvailable ? Theme.iconFontFamily : Theme.fontFamily

    function glyph(nerdGlyph, fallbackGlyph) {
        return nerdFontAvailable ? nerdGlyph : fallbackGlyph
    }

    // Stable Font Awesome codepoints included by Nerd Fonts. Older codepoints are
    // preferred here because they render consistently across nf-fa generations.
    readonly property string dashboard   : glyph("\uf015", "⌂")       // house
    readonly property string nodeRed     : glyph("\uf0e8", "⇄")       // sitemap / flow
    readonly property string settings    : glyph("\uf013", "⚙")       // gear

    readonly property string location    : glyph("\uf041", "●")       // map-marker
    readonly property string mapPin      : glyph("\uf041", "●")
    readonly property string sensor      : glyph("\uf2db", "◉")       // microchip
    readonly property string temp        : glyph("\uf2c9", "°")       // thermometer-half
    readonly property string battery     : glyph("\uf240", "▰")       // battery-full
    readonly property string sampleRate  : glyph("\uf0e4", "↯")       // tachometer
    readonly property string signal      : glyph("\uf012", "≋")       // signal
    readonly property string plug        : glyph("\uf1e6", "⌁")       // plug
    readonly property string sync        : glyph("\uf021", "↻")       // refresh
    readonly property string web         : glyph("\uf0ac", "◎")       // globe
    readonly property string database    : glyph("\uf1c0", "▤")       // database
    readonly property string language    : glyph("\uf1ab", "文")       // language
    readonly property string palette     : glyph("\uf1fc", "◐")       // paint-brush / appearance
    readonly property string folder      : glyph("\uf07b", "▣")       // folder
    readonly property string info        : glyph("\uf05a", "i")       // info-circle
    readonly property string warning     : glyph("\uf071", "!")       // warning
    readonly property string connection  : glyph("\uf1e6", "⌁")       // plug
    readonly property string flow        : glyph("\uf0e8", "⇄")       // sitemap

    readonly property string add          : glyph("\uf067", "+")
    readonly property string edit         : glyph("\uf044", "✎")
    readonly property string trash        : glyph("\uf1f8", "×")
    readonly property string chevronRight : glyph("\uf054", "›")
    readonly property string chevronDown  : glyph("\uf078", "⌄")
    readonly property string search       : glyph("\uf002", "⌕")
    readonly property string zoom         : glyph("\uf00e", "⊕")       // search-plus / map zoom
    readonly property string save         : glyph("\uf0c7", "✓")
    readonly property string cancel       : glyph("\uf00d", "×")
    readonly property string close        : glyph("\uf00d", "×")
    readonly property string check        : glyph("\uf00c", "✓")
    readonly property string minimize     : glyph("\uf068", "—")
    readonly property string maximizeOn   : glyph("\uf2d0", "□")
    readonly property string maximizeOff  : glyph("\uf2d2", "▣")

    readonly property string plus         : glyph("\uf067", "+")
    readonly property string minus        : glyph("\uf068", "−")
    readonly property string hand         : glyph("\uf256", "↔")       // hand-paper / pan
    readonly property string pinPoint     : glyph("\uf05b", "⊙")       // crosshairs / select
    readonly property string refresh      : glyph("\uf021", "↻")
    readonly property string download     : glyph("\uf019", "↓")
    readonly property string play         : glyph("\uf04b", "▶")
    readonly property string pause        : glyph("\uf04c", "Ⅱ")
    readonly property string chart        : glyph("\uf201", "↗")       // line-chart
    readonly property string externalLink : glyph("\uf08e", "↗")
}
