pragma Singleton
import QtQuick
import "i18n/en.js" as English
import "i18n/id.js" as Indonesian

QtObject {
    id: localizer

    property string language: "en"
    property var dictionary: English.strings
    property int revision: 1
    readonly property var supportedLanguages: [
        {"code": "en", "label": "English"},
        {"code": "id", "label": "Bahasa Indonesia"}
    ]

    function normalizedLanguage(code) {
        const value = String(code || "en").toLowerCase()
        return value.indexOf("id") === 0 ? "id" : "en"
    }

    function setLanguage(code) {
        const normalized = normalizedLanguage(code)
        language = normalized
        dictionary = normalized === "id" ? Indonesian.strings : English.strings
        revision += 1
        return true
    }

    function t(key, fallback) {
        const dependency = revision
        const parts = String(key).split(".")
        let value = dictionary
        for (let i = 0; i < parts.length; ++i) {
            if (value === undefined || value === null || value[parts[i]] === undefined)
                return fallback !== undefined ? fallback : key
            value = value[parts[i]]
        }
        return typeof value === "string" ? value : (fallback !== undefined ? fallback : key)
    }

    function format(key, values, fallback) {
        let result = t(key, fallback)
        const data = values || ({})
        for (const name in data)
            result = result.replace(new RegExp("\\{" + name + "\\}", "g"), String(data[name]))
        return result
    }
}
