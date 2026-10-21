# Testing strategy

Host tests run the generated bridge under AddressSanitizer with a Node-API test
double. Device checks install the application on the HarmonyOS emulator and read
HiLog markers for indexing, search, cancellation and cleanup.
