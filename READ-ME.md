# Apple Weather comprehensive preview 4

iPhone IPA only. Separate test app; no Calibrated Golf or Android changes.
Build once in the existing apple-weather-preview repository. Workflow:
Apple Weather comprehensive preview 4. Sign/install the unsigned IPA as before.

Tap RUN ALL CHECKS once. The app automatically performs twelve checks:
two original projects (background/collision), six loading routes per project:
direct binary URL with default options; URL with exported asset/Metal options;
binary data in memory; lower-level world loader with binary/project URLs;
and VFXWorldLoader with the binary URL.
Missing/unreadable resources or unsupported method layouts are reported and
skipped rather than called. The known missing world.plist folder route is logged,
not repeated. Option names are resolved from Apple's actual exported constants.

The report records hardware/iOS/build/source identity, resources and binary
headers, method ABI and exposed preset factories, complete NSError information,
world-loading outcomes, camera/view/Metal state, native snapshot pixel hashes
and pixel variation, and renderer statistics where available.
Up to four PNG snapshots are retained (8 MB each maximum).

Results/checkpoints are saved before native calls. If the app closes, reopen
it and tap RESUME CHECKS: it skips the interrupted attempt and continues.
STOP stops between calls; an active native call cannot safely be cancelled.
No attempts overlap. Long calls run on a serial worker; UIKit stays on main.
Background/Reduce Motion pauses continuous rendering.

When COMPLETE appears, use SHARE REPORT to send/save the text and snapshots.
COPY REPORT provides the full text if sharing is inconvenient.
Exact Apple per-condition presets are still NOT connected or verified.
A loaded world, nonuniform image or changing pixels is diagnostic evidence,
not proof that all iPhone Weather animations have been reproduced.

The Mac build runs native regression tests for initializer ownership, object
returns, NSError pointers, BOOL results, mutable info, setters and ABI guards
before compiling the iPhone app. Debug symbols and a build proof are exported.
Prepared and source-checked on Windows. Native compilation and iPhone
execution remain unverified until the user's Codemagic/phone run.
No large Apple files, credentials or dependencies are included.
