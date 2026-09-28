-- Validation-build defaults. Set enabled=false before packaging for quiet play,
-- or use lbDebug off in game. This file never changes economic behavior.
BankDebugConfig = {
    enabled = true,
    traceReads = true,
    maxEvents = 120000,
    maxBytes = 64 * 1024 * 1024,
    maxLineBytes = 12000,
    summaryIntervalMs = 60000,
    autoCaptureIntervalMs = 60000,
    minimumCaptureIntervalMs = 15000,
    settleDelayMs = 2000
}
