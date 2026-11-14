# Sensor page header regression fix

The modular QML release placed the sensor identity card and GNSS map inside the same constrained two-column grid. At normal application widths, the action toolbar could overflow its column and the identity card could collapse or appear missing.

The sensor page now keeps `SensorHeaderCard` as a full-width first section. The component has an explicit implicit height and a responsive action flow. It always exposes the sensor name, location, description, Edit, Sensor settings, History, and Export CSV actions. The map and operational metric cards are arranged in a separate responsive overview grid below it.

A static contract test protects the identity header and its actions from being omitted by later QML refactors.
