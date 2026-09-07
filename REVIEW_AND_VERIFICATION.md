# Code review, logic review and release verification

Date: 2026-09-08. Engine: Godot 4.7.2 standard build. Blender: 4.5.3 LTS. The review consisted of three distinct passes followed by regression checks while implementing the requested improvement plan. All reviews were performed in this task; no independent external review is claimed.

## Pass 1 — simulation and navigation

Reviewed command validation/ownership, finite resources, construction payments/refunds, production reservations, river footprints, targeting and outcomes. Found that the generic arrival tolerance was larger than the worker interaction gap: workers could stop just outside gathering range. Worker approach tolerance was reduced while ordinary move orders retain a formation-friendly arrival tolerance.

Validation: initial accounting suite, gathering income/depletion, invalid commands, cancellation, five Breakers checked on every simulation tick during a crossing, and full AI matches on both maps.

## Pass 2 — web/UI and device input

Reviewed real WebAssembly execution, desktop/touch selection and orders, settings, pause, small screens and rotation. Fixed modal background input leakage, scrolling layouts, clipped settings footers, portrait camera width and duplicate touch-to-mouse emulation. Q now activates attack-move so WASD can pan consistently. Shift + number supports browser group assignment without relying on reserved Ctrl shortcuts.

The browser test initially cleared selection before Godot processed the queued keyboard event. It now waits for the group assignment before changing the fixture. That was a test-ordering defect, not evidence that group logic was broken.

Validation: actual mouse/right-click/touch dispatch, gathering and training, refunds, pause and settings Apply/Cancel, local persistence, control groups, touch pan/pinch, portrait/landscape, outcome/restart and empty console/error arrays.

## Pass 3 — information boundaries and lifecycle

Reviewed AI notices, blocked production exits, lost supply, destroyed producers, one-time research, destroyed command targets and fresh-match state. Fixed AI feedback leaking into the player's notification area and research being blocked by full supply despite requiring no population. Invalid footprint radii are rejected. Settings preserve pause, gesture releases over UI clear captured state, and focus loss pauses active play.

Validation: dedicated accounting/lifecycle regressions, existing/new-unit upgrade damage, imported animation names, palette application, last-seen building memory, and five scene-restart cycles with equal populated scene-root counts.

## Additional acceptance finding while executing improvements

A worker-completed construction test exposed a grid path whose endpoints were valid but whose connecting segment grazed the headquarters circle. The worker oscillated between repathing and the prior cell. Grid construction now includes a 0.6 m conservative margin; every actual movement still uses the unit's full radius and swept traversal. The completed-building and trained-army victory tests pass with this correction.

The visual review also exposed reversed terrain-face visibility: the flat base could show through instead of the vertex-colored surface. The ground material now renders both faces, and screenshots show the intended roads/ground variation. Lighting was reduced to preserve paint and resource color detail.

## Executed improvement plan

The release implements the bounded plan in IMPROVEMENT_PLAN.md:

- Readable lighting, varied ground, water/bridges/ford, softened visual fog, portrait framing and scrollable panels with fixed settings footer.
- Contextual objective checklist and idle-worker selection.
- Four original animated Blender models, five named clips each, editable .blend sources and a reproducible script; Godot AnimationPlayer integration and paused animation handling.
- Last-seen enemy building markers that retain stale information until the location becomes visible again; gesture cleanup and focus-loss pause.
- A test-gated Web/Windows export workflow and separate SSH repository.

## Test evidence

- **44 native simulation checks pass.** These include a player-style gathering/construction/training sequence that destroys the opposing headquarters through normal combat, plus AI victory against an idle player on each map. Direct setup/damage helpers are used in isolated accounting tests, not as evidence of combat victory.
- **Asset/UI checks pass.** All nine unit/building scenes import, all 20 Blender clips exist, palette and pause behavior work, visibility memory respects hidden changes, and restart does not accumulate scene roots after the initial scene is fully populated.
- **Desktop and touch browser suites pass locally** against the actual exported build at a project subpath. Portrait 390×844 and landscape 844×390 are exercised; these are emulated devices, not physical phones.
- **Windows release executable starts successfully** in headless mode. Visual review uses the web export running the same GDScript/Compatibility renderer. No Windows installer or signing certificate is included.
- CI and live-site results are verified after pushing; the associated GitHub Actions run is the deployment record.

## Performance sample and limits

Windows, RTX 4080 SUPER, Chrome 152, 1280×800, 100 friendly units, short 120-frame sample: median approximately **17.6 ms**, p95 **18.1 ms**, **5,376 draw calls**, 2,864 nodes, no console errors. This sample includes original animated assets and the opt-in benchmark fixture. Results vary with camera, settings and machine. High draw-call count is the next optimization target; it is not a mobile frame-rate guarantee.

The web engine WASM is approximately 39.5 MB before HTTP compression; game data is much smaller. GitHub Pages can gzip static content. Native executable size is approximately 110 MB. Physical phone thermals, iOS audio/browser behavior, long-session soak tests and extensive competitive balance remain unverified.

No blocking defect remains in the tested release flows. Three passes and automated tests do not establish that all possible bugs are eliminated.
