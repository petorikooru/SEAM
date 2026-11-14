pragma Singleton
import QtQuick

QtObject {
    id: theme

    property string currentTheme: "dark"
    readonly property bool darkMode: currentTheme === "dark"
    readonly property string version: "v2.3.0"

    readonly property string fontFamily: Qt.application.font.family

    // Nerd Font is intentionally resolved from the operating system. The application
    // does not require a bundled font and remains readable when no Nerd Font is installed.
    readonly property var installedFontFamilies: Qt.fontFamilies()
    readonly property string iconFontFamily: resolveIconFont([
        "Symbols Nerd Font Mono",
        "Symbols Nerd Font",
        "JetBrainsMono Nerd Font",
        "JetBrainsMono Nerd Font Mono",
        "FiraCode Nerd Font",
        "FiraCode Nerd Font Mono",
        "Hack Nerd Font",
        "Hack Nerd Font Mono",
        "CaskaydiaCove Nerd Font",
        "CaskaydiaCove Nerd Font Mono",
        "Font Awesome 6 Free",
        "Font Awesome 6 Free Solid",
        "Font Awesome 5 Free",
        "Font Awesome 5 Free Solid"
    ])
    readonly property bool nerdFontAvailable: iconFontFamily.length > 0
    readonly property int iconSizeSmall: 12
    readonly property int iconSize: 14
    readonly property int iconSizeLarge: 16

    property color sidebarBg: darkMode ? "#090F17" : "#F7F9FC"
    property color bg: darkMode ? "#0E1621" : "#E9EEF5"
    property color surface: darkMode ? "#121C29" : "#EEF2F7"
    property color card: darkMode ? "#192536" : "#FFFFFF"
    property color card2: darkMode ? "#202F43" : "#F8FAFC"
    property color dialog: darkMode ? "#172231" : "#FFFFFF"

    property color text: darkMode ? "#F7FAFC" : "#111827"
    property color subText: darkMode ? "#B4C1D0" : "#4B5563"
    property color mutedText: darkMode ? "#7D8EA3" : "#64748B"
    property color disabledText: darkMode ? "#526276" : "#94A3B8"

    property color accent: "#F36F21"
    property color accentHover: "#FF8A45"
    property color accentPressed: "#D95712"
    // Orange is a bright surface; near-black provides materially better contrast than white.
    property color accentText: "#111318"
    property color accentSubText: "#3A2419"
    property color accentSoft: darkMode ? "#2E211C" : "#FFF0E8"

    property color success: "#22C55E"
    property color info: "#38BDF8"
    property color warning: "#F59E0B"
    property color danger: "#EF4444"
    property color dangerHover: "#F87171"
    property color dangerPressed: "#B91C1C"

    property color controlBg: darkMode ? "#202D3E" : "#F8FAFC"
    property color controlHover: darkMode ? "#2A3B50" : "#E6ECF3"
    property color controlPressed: darkMode ? "#141E2B" : "#D8E0EA"
    property color controlFocus: darkMode ? "#111A25" : "#FFFFFF"
    property color controlDisabled: darkMode ? "#1A2634" : "#E2E8F0"

    property color border: darkMode ? "#30445B" : "#D5DEE9"
    property color borderLight: darkMode ? "#40566E" : "#C7D2E2"
    property color divider: darkMode ? "#27394D" : "#E2E8F0"

    property color pitch: "#F59E0B"
    property color roll: "#C084FC"
    property color axisX: "#EF4444"
    property color axisY: "#22C55E"
    property color axisZ: "#38BDF8"

    readonly property color chartGrid: darkMode ? "#354A61" : "#D8E0EA"
    readonly property color chartLabel: subText

    function resolveIconFont(candidates) {
        for (let i = 0; i < candidates.length; ++i) {
            if (installedFontFamilies.indexOf(candidates[i]) >= 0)
                return candidates[i]
        }
        // Also accept user-loaded Nerd Font or Font Awesome family names that
        // are not in the preferred-family list above.
        for (let j = 0; j < installedFontFamilies.length; ++j) {
            const family = String(installedFontFamilies[j])
            const normalized = family.toLowerCase()
            if (normalized.indexOf("nerd font") >= 0 ||
                    normalized.indexOf("font awesome") >= 0 ||
                    normalized.indexOf("symbols nerd") >= 0)
                return family
        }
        return ""
    }

    function applyTheme(name) {
        const normalized = name === "light" || name === "kaiLight" ? "light" : "dark"
        currentTheme = normalized
    }
}
