# Apple Weather native preview 3

This is a separate diagnostic iPhone app, not an update to Calibrated Golf and
not a completed reproduction of Apple's weather backgrounds.

Scope: Apple iPhone IPA only. Android and the shared web application are not
modified. Any later integration must remain in the iOS native layer.

Its purpose is to test whether the installed iOS 27.2 WeatherUI/VFX engine can
load its original scene in an ordinary sideloaded app. It uses the phone's own
installed frameworks and assets. No large Apple files, API keys, npm packages or
Calibrated Golf files are included.

The actual weather-condition presets are NOT connected. It may show a default
or black scene, a load error, or encounter an unavailable private interface.
None of those outcomes proves a visual match. The source checks exposed method
signatures before invoking them, logs errors, respects Reduce Motion and pauses
continuous rendering in the background. Native failures can still terminate the
preview; physical-device testing is required.

Build in a NEW Codemagic repository/application using the supplied workflow.
Do not replace, disable or upload over the Calibrated Golf build repository.
The workflow compiles directly with Xcode and produces an unsigned IPA.
Sign/install it using the existing Sideloadly method.

The app is named **CG Weather Preview** and uses the distinct bundle identifier
`com.calibratedgolf.weatherpreview`; it is intended to coexist with Calibrated
Golf. Confirm the signing tool preserves that separate identifier.

On the iPhone, tap **Load native scene**, then **Copy test report**. Inspect and
record the visible result. If it crashes, retain the iPhone crash report.
Required evidence before integration: native scene/effect loading result,
displayed output, errors or crash logs, exact iOS build and device model.

Prepared on Windows. Source/plist/workflow checks can run here; compilation and
Apple VFX playback have NOT run here. The earlier framework was extracted from
iOS 27.2.1; this preview deliberately loads the phone's installed iOS version.

Next stage after a successful engine test: recover/invoke Apple's per-condition
configuration pipeline, then compare every day/night condition against the
phone before integrating anything into the golf app.

Build 2 fixes the preview's ARC receiver ownership when a native initializer returns nil. The Codemagic build now runs a native macOS ownership regression test before compiling the iPhone app. Physical iPhone scene loading remains unverified.

Build 3 makes one targeted API change: VFXWorld.worldWithURL:options:error: and VFXView.setWorld:, as requested by the installed engine error. No VFXScene loading fallback is used. One build and one physical-phone test; no broader research.
