# Fork Change Record and Upstream Handoff Notes

This document records the changes made in the `feature/asymmetric-fan-response`
branch after the upstream base commit `60a57f3` (`Merge pull request #8 from
leornt/fix/autostart`). It is written for maintainers reviewing a future pull
request, not as a replacement for the main README.

## Purpose and scope

This fork was tested on an Apple-silicon MacBook Pro with an M4 Pro. The work
addresses four practical areas:

1. safer and more stable automatic fan control;
2. reliable sensor presentation and history;
3. lower UI CPU use while retaining a live fan indicator; and
4. usability of the app bundle, Dock presence, menu-bar access, and resizing.

It does **not** claim to reproduce Apple's private SMC fan curve. Apple does
not publish the M4 Pro's thresholds, sensor weights, or individual fan-to-zone
mapping. The app continues to use the SMC values that macOS exposes and always
offers a return to the system's automatic controller.

## Change inventory

| Area | Commits / status | Summary |
|---|---|---|
| Initial asymmetric rule response | `9821100` | Separate rise/fall time constants and an emergency bypass; superseded below by a slew-rate limiter. |
| Controlled test load | `92abb50` | Local, bounded CPU and Metal GPU stress-test utility. |
| Sensor reliability and app presence | `b2a2e5d` | Reject implausible sensor values; restore Dock icon and app activation. |
| Resizable layout | `b6bb6bc` | Let the window and cards use available width with a safe minimum size. |
| Monitoring/render CPU | `f365cdc`, `fc36392` | Removed continuous SwiftUI redraw paths and overlapping status reads. |
| Integration update | this contribution | Core Animation indicator, fixed one-second thermal polling, cooling hysteresis, target deadband, cooling confirmation, command-rate limiter, multi-series history, and responsive UI. |

The changes intentionally remain separable. A maintainer can review the
automatic-control work independently from the UI and packaging work.

## Automatic fan-control behaviour

### Existing rule resolution preserved

Rules select the highest requested speed across the enabled CPU, GPU, and
battery rules. Percentages are converted **per fan** from the current SMC range:

```text
target RPM = fan minimum RPM + percentage × (fan maximum RPM - fan minimum RPM)
```

`F<n>Mn` and `F<n>Mx` are refreshed from the SMC during status polling; no
one-time calibration database is introduced. When a rule no longer requests
speed, the controller ramps down before returning the fan(s) to macOS Auto.

### Replaced asymmetric response (`9821100`)

`9821100` initially added a first-order filter with separate rise/fall time
constants. It was useful for early tuning, but it made the actual change rate
depend on the size of a temperature step. It is retained in history for review,
but is replaced by the explicit command-rate limiter described below.

### Asymmetric bounded command rates (current working tree)

- **Rise command rate** defaults to **6% per second** and **fall command rate**
  defaults to **3% per second**; each is selectable from 0.5%/s to 10%/s.
- The first automatic demand is applied immediately as a conservative startup
  behaviour; subsequent increases and decreases obey their respective selected
  rate.
- A request of **90% or more** bypasses the rate limiter.

The values persist in `UserDefaults` under
`maximumCommandRiseRatePercentPerSecond` and
`maximumCommandFallRatePercentPerSecond`, and are exposed under **Fan
response**. Unlike a time-constant filter, the two slew-rate limits give an
explicit upper bound on normal command movement while allowing a faster safety
response to rising demand and a gentler acoustic release during cooling.

### Cooling-only temperature hysteresis (current working tree)

Small sensor changes around a threshold can otherwise cause repeated fan target
changes. The current working tree retains each sensor's most recently accepted
control temperature while it is cooling:

- a temperature rise is accepted immediately;
- a temperature fall is accepted only once it is at least the configured
  **Cooling hysteresis** below the retained value;
- the default hysteresis is **5.0 °C** and the selectable range is 0.0–5.0 °C.

This is a cooling-side deadband, not a delay on heating. It therefore reduces
audible hunting without withholding a response to a new thermal rise. The state
is cleared when the rule engine is disabled or returns all fans to Auto.

### Target deadband (current working tree)

The app accepts a new thermal demand only if it differs by at least **4%** from
the previously accepted demand. The selectable range is 1–5%; the value is
persisted as `minimumCommandChangePercent`. The accepted target is then moved
toward at the bounded command rate, allowing small, regular commands instead
of sporadic 4% or larger jumps. A demand of 90% or higher is accepted
immediately.

This reduces sensor-noise hunting without reducing the one-second sensing
cadence or defeating the acoustic rate limit.

### Cooling confirmation (current working tree)

Before accepting a normal downward target change, the lower thermal demand must
persist for **8 seconds** by default. The setting is adjustable from 0 seconds
(disabled) to 15 seconds. A renewed higher demand cancels and restarts the
confirmation period; temperature rises and requests at or above 90% remain
immediate. This prevents short power dips from rapidly unwinding fan speed,
while the existing fall-rate limiter shapes the later, confirmed reduction.

### Polling (current working tree)

The SMC is sampled every **1.0 second**, regardless of whether the window is
frontmost, covered, or hidden. Automatic thermal protection must not have a
different response time because of application visibility. A guard prevents
overlapping helper invocations if a read takes longer than one interval.

## Sensor validation and history (`b2a2e5d`)

Apple-silicon SMC keys can occasionally return low non-zero values that are not
physically credible. The helper now accepts candidate values only inside these
bounds:

| Sensor | Accepted range | Maximum accepted jump per sample |
|---|---:|---:|
| CPU / GPU | 10–115 °C | 25 °C |
| Battery | 5–70 °C | 8 °C |

The view model performs the same validation before using a new reading for
display, rules, or history, and cleans legacy history on loading. An invalid
sample keeps the previous live value; an invalid historical sample is omitted.

This is input validation, not thermal smoothing: valid increases remain
available to the automatic controller immediately. History is retained for the
most recent 24 hours (at one sample per 30 seconds). The graph itself is a
user-selectable rolling window ending at the current time: 30 minutes, 1 hour,
2 hours (the default), 12 hours, or 24 hours. The selected duration is stored
locally, so it does not revert to a midnight-based calendar-day view on the
next launch. CPU, GPU, and battery histories can be independently enabled as
overlaid curves; the graph supports any combination, including no selected
curve, and remembers those visibility choices locally.

The current CPU temperature is a conservative aggregate, not a confirmed
Apple-silicon die sensor: the helper takes the highest plausible reading from
its ordered CPU key list (`TC0P`, `TC0D`, `TC0F`, and additional legacy and
Apple-silicon candidates). The interface therefore labels it simply **CPU**.
The individual key that contributed the maximum is not yet reported by the
helper; identifying and exposing exact M4 Pro sensor identities remains a
separate, hardware-validated follow-up.

The same maximum CPU value is the one supplied to CPU automatic-control rules;
the controller therefore does not use an arbitrary lower-priority CPU key for
fan decisions.

The history graph can also show a cyan dashed **Fan target** trace. It records
the highest SMC fan-target percentage across installed fans, normalized against
each fan's own minimum and maximum RPM range. This makes the trace conservative
when fans differ and lets temperature in °C and target percentage share a
0–105 scale (which expands only if a higher valid value is recorded). The fan
value itself is clamped to 0–100%, rendered as a continuous cyan line, and the
additional 5 units are temperature headroom rather than an implied 105% fan
command. Hovering a timestamp marks and reports every displayed series. The
former top-row temperature cards were removed once this multi-series graph was
introduced; its plot area is now 320 points high to use that space for the
history rather than duplicate current-value panels.

The graph controls are intentionally separated from the values: the checkbox
legend only selects curves, while a single compact inspection strip reports the
latest values. While the pointer is over the plot, that same strip switches to
the values at the selected time. A second, always visible compact row reports
the minimum–maximum range for each selected series; it is therefore available
without a disclosure control, but does not change while the pointer moves.
The toggle row and both value rows use matching fixed columns, and the scale
caption sits immediately above the plot, to keep the scanning order stable.

## Fan display and UI performance

### Core Animation fan indicator (current working tree)

The original SwiftUI `Canvas` animation was profiled as a significant source of
CPU use while the window was visible. The current implementation creates the
ring, blades, gradient, and hub once as `CALayer`/`CAShapeLayer` objects and
animates only `transform.rotation.z` with `CABasicAnimation`.

Characteristics:

- the compositing system performs the per-frame rotation;
- the indicator pauses when the app resigns active and resumes at its existing
  angle when the app becomes active;
- its direction is monotonic, so an RPM update cannot make it appear to reverse;
- zero reported RPM removes the animation and leaves a static indicator;
- its visual rate is `2 × (currentRPM / maximumRPM)^0.55` revolutions/second.

The concave visual mapping makes low speeds legible while limiting the visual
rate to 2 revolutions/second at full scale. It is an indicator, not a literal
depiction of thousands of physical revolutions per minute.

The `NSViewRepresentable` is explicitly constrained to 80×80 points and does
not overwrite the AppKit root layer's frame. This fixes a resize defect in which
blades could render outside their ring.

### Earlier reduction work (`f365cdc`, `fc36392`)

The intermediate 15 FPS SwiftUI timeline and then the static Canvas avoided the
original display-rate redraw. They are superseded by the Core Animation version
above, but the status-read overlap guard and scene activity plumbing remain
useful.

## Window, Dock, and menu bar

### Foreground application behaviour (`b2a2e5d`)

The application uses the regular activation policy instead of the accessory
policy. This keeps it in the Dock and allows ordinary application switching.
Closing the window hides it rather than quitting; the menu-bar extra can reopen
the main window. The menu icon was changed to `fanblades`.

The build copies `app_icon.png` into the bundle as `AppIcon.png`, and the app
loads that PNG as a runtime fallback icon. This avoids an unreliable `.icns`
generation step in the local build environment.

### Resizing (`b6bb6bc`)

The main window has a 600×680 minimum. Content,
cards, rule engine, history view, and fan rows expand to available width instead
of retaining a fixed 580×680 content frame.

The current working tree raises the default window to 960×900 points (subject
to macOS's usable-display limit). It uses the actual available window height
as a responsive breakpoint: below 900 points, the heading margins and the
history plot contract modestly. The visual order remains history, manual fan
controls, then automatic rules. In that compact layout, each fan card retains
its Auto/Manual control, manual target slider, and all five speed presets; the
presets use reduced spacing and type size while the explanatory Auto text is
omitted. This keeps the automatic-rules card
discoverable on the first screen of a compact notebook display rather than
relying on a global scale factor that would make sliders and labels harder to
use. When no history series is selected, the empty graph area collapses to a
short icon-and-message row, reclaiming space immediately.

The populated history plot is 240 points high in the regular layout and 160
points in the compact layout. Fan cards use a horizontal composition: the
larger status indicator is on the left, while the RPM, Auto/Manual selector,
target slider, and (when space permits) preset buttons are grouped to its
right. This removes the previous full-width target-control stack from beneath
each fan and leaves more vertical room before the automatic-rules card.
The fan indicator is vertically centered in that control group and uses a
140×140 point regular visual column (88×88 in the compact layout), avoiding
the former top-aligned badge appearance.

## Controlled thermal-load utility (`92abb50`)

`tools/thermal-load` is a local, opt-in Swift command-line utility. It creates
a bounded CPU workload and, when Metal is available, a bounded GPU compute
workload. It is not shipped inside the application bundle.

- CPU load is limited to 80%; GPU load is limited to 70%.
- The default four-minute plan is warm-up, CPU, CPU+GPU, then cooling.
- A custom plan is expressed as `seconds:cpu:gpu` steps.
- Control-C stops the workload immediately.

Use it only while supervising the Mac. The intended comparison workflow is:

1. reset Fan Control to Auto and capture the system's native response;
2. repeat with a candidate rule configuration;
3. compare temperatures, target RPM, actual RPM, and the smoothness of the
   transitions; and
4. return to Auto after every test.

The tool does not identify which physical fan cools which die region. That
requires measured CPU-only and GPU-only trials; the physical fan-to-zone
mapping is not inferred by this fork.

## Build and local-install notes

`build.sh` continues to build the helper and app for macOS 13 or later. The
signing identity is now overridable:

```bash
ARCHS=arm64 SIGNING_IDENTITY=- ./build.sh
```

This supports local ad-hoc ARM64 builds when the upstream Developer ID
certificate is unavailable. A release for other users should be signed and
notarized by its publisher; an ad-hoc signature is not a distribution strategy.

The helper remains a privileged, setuid-root component, as in the upstream
design. This fork does not broaden its command surface. Any upstream security
review should nevertheless treat helper installation, ownership, and code
signing as a first-class release concern.

## Validation performed locally

- ARM64 compilation succeeds with macOS 13 deployment target.
- The app and helper pass `codesign --verify --deep --strict` after an ad-hoc
  local build.
- CPU/GPU temperature histories no longer accept the previously observed
  implausible ~2 °C CPU-die samples.
- Core Animation replaced the observed continuous SwiftUI drawing cost; manual
  interactive testing reported substantially lower idle/visible CPU use.

The local build environment can fail while creating the optional DMG with
`hdiutil` because no device service is available. This occurs after the usable
`.app` bundle is built and signed, and is not evidence of an application build
failure.

## Known limitations and proposed follow-up

1. **Apple SMC policy is private.** Do not describe this as Apple's fan curve or
   claim that the two fans map exclusively to CPU and GPU.
2. **Defaults require broader validation.** The 6%/s rise and 3%/s fall
   command-rate limits, 5 °C cooling hysteresis, and 4% target deadband are documented starting
   values, chosen for conservative cooling and reduced hunting. They should be
   tested across ambient temperatures and workloads.
3. **No fan fault diagnosis.** The app reads actual RPM but does not yet expose
   a sustained target-versus-actual fault alarm.
4. **Linked manual slider semantics need review.** The global percentage path is
   correctly per-fan, but the `linkedFans` path currently applies the initiating
   slider's raw RPM to each fan and clamps it. A future change should project the
   initiating fan's percentage into every other fan's own min/max range.
5. **No native policy logger yet.** The history graph is useful, but an exportable
   CSV trace of CPU/GPU temperatures, each fan's actual/target RPM, rule demand,
   and final filtered command would make native-vs-custom comparison easier.

## Suggested upstream PR structure

For reviewability, split a future submission into independent pull requests:

1. sensor validation and resizable/Dock UI fixes;
2. automatic control: command-rate limiter, hysteresis, target deadband, and
   settings UI;
3. Core Animation performance work; and
4. optional `tools/thermal-load` developer utility.

Each PR should include hardware/model information, a brief manual test matrix,
and an explicit statement that users can reset to macOS Auto at any time.
