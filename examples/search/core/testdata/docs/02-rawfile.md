# Reading packaged resources with RawFile

Applications ship documents under resources/rawfile. The ArkTS resourceManager is
passed to MoonBit as a borrowed rawfile Manager; MoonOHOS acquires a native
resource manager before the call and releases it when the call or task ends.
