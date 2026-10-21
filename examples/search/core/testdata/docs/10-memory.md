# Memory ownership across the bridge

Strings, bytes, arrays and records are copied at the boundary. Handles keep one
MoonBit reference that is released by close, by garbage collection or when the
environment is destroyed, whichever happens first.
