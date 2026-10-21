# Async tasks on worker threads

Long running MoonBit work is exported as an async function. The bridge copies
arguments on the JS thread, runs MoonBit on a Node-API worker while holding the
process gate, and resolves the Promise on the JS thread. The UI stays responsive.
