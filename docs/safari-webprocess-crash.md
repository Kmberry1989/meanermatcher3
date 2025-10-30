# Safari Mobile WebProcess Crash Log Analysis

This note captures observations and recommendations based on the sample log
collected from Console.app while debugging Mobile Safari on iOS. The goal is to
spot repeating crash symptoms and offer next steps for local investigation.

## Recurring errors

- `WebProcessProxy::didClose` / `processDidTerminateOrFailedToLaunch` with
  `reason=Crash` shows that Safari's WebKit content process repeatedly exits.
- Follow-on `Failed to terminate process` messages with
  `Error Domain=com.apple.extensionKit.errorDomain Code=18` and
  `No such process found` indicate the system tried to clean up the already
  crashed process, so those errors are secondary.
- `Error acquiring assertion` with failure reason about missing
  `com.apple.developer.web-browser-engine.*` entitlements is another fallout of
  the WebContent process disappearing before Mobile Safari can re-establish a
  connection.
- `perform input operation requires a valid sessionID` from
  `RTIInputSystemClient` is a benign symptom of the same crash loop; the text
  input session is invalid because the renderer process vanished.
- Repeated `ContextService Safari request with no text` and
  `Detected stale pending counter; resetting to 0` messages are noise stemming
  from Safari retrying search suggestions while the renderer restarts.

## Suggested checks

1. **Reproduce on latest iOS & Safari** – Install the newest available iOS
   point release and confirm the issue still occurs. Many WebKit crashes are
   patched in OS updates.
2. **Isolate third-party scripts or extensions** – Load a minimal version of
   the site (disable A/B experiments, remove analytics) to verify whether a
   specific script is provoking the crash.
3. **Use `WKWebView` on macOS or iOS Simulator** – The crash likely happens in
   WebKit, so reproducing it in a simulator or Mac Safari's responsive design
   mode can capture a macOS crash report with stack traces.
4. **Grab a full crash report** – In Console.app select "Crash Reports" and look
   for `com.apple.WebKit.WebContent` entries matching the timestamps. The
   `DiagnosticReports` folder on the device (or synced to macOS) will include
   a `.ips` file with a backtrace that is far more actionable than Console log
   snippets.
5. **Check low-memory warnings** – If the device is under memory pressure you
   will see `Jetsam` events in the log. Absence of jetsam messages suggests the
   crash stems from WebKit or injected scripts rather than the OS killing the
   process.
6. **Temporarily disable Credential Providers** – `CredentialProviderExtension`
   errors appear alongside each crash; disable password manager extensions to
   rule out conflicts.

## Next steps

- Collect the `.ips` crash log and symbolicate it via Xcode's Devices window to
  obtain stack traces.
- Share the symbolicated report with Apple or WebKit bug tracker if the crash is
  reproducible and not caused by app-specific scripts.
- While waiting on a fix, consider implementing a watchdog that detects reload
  loops and prompts the user to open an alternative browser.

