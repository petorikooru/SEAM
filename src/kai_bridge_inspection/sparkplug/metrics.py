"""Sparkplug metric data-type identifiers from the Sparkplug B specification."""

from __future__ import annotations

DATA_TYPE_NAMES: dict[int, str] = {
    1: "Int8", 2: "Int16", 3: "Int32", 4: "Int64", 5: "UInt8", 6: "UInt16",
    7: "UInt32", 8: "UInt64", 9: "Float", 10: "Double", 11: "Boolean",
    12: "String", 13: "DateTime", 14: "Text", 15: "UUID", 16: "DataSet",
    17: "Bytes", 18: "File", 19: "Template", 20: "PropertySet", 21: "PropertySetList",
}
