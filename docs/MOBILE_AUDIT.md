# Mobile usability and performance audit

## Delivered

- Web controls use the canvas's CSS dimensions as Godot's logical viewport. DPR 3 phones receive the mobile layout and 44-CSS-pixel buttons instead of tiny desktop controls. Resize handling is deferred until the engine finishes resizing, preserving correct rendering after rotation.
- Main actions use explicit Previous / More actions pages: two full-width actions in portrait and four in landscape.
- Queue changes preserve the current action page; changing selection or order mode returns to the first page.
- A right-hand command panel keeps landscape controls apart from the minimap, notices and navigation.
- Touch tablets use the mobile layout. Rotating or narrowing the viewport releases the previous control widths.
- Deploy, Resume, Settings and result actions use fixed modal footers. Text remains scrollable.
- Action buttons and graphics toggles have a minimum 44-pixel touch height.
- Imported Blender model templates merge static sibling parts by material. Animated nodes and original per-part building hit bounds are preserved; optimized templates are reused when units spawn.

## Verification

`npm run test:browser` covers desktop controls, construction feedback, progression, Medic support, pause/settings, gestures and restarts. Its mobile matrix checks 320×568, 390×844, 667×375, 844×390 and 768×1024, enumerates action pages and asserts that every visible action fits both the command area and viewport. It uses raw touch coordinates; hidden controls are never automatically scrolled into reach. The complete matrix passed locally at DPR 3, and screenshots were visually inspected after rotation.

CI runs the complete suite with `MOBILE_DPR=1`, followed by `npm run test:mobile-density`, which verifies DPR 3 Android Chrome portrait/landscape scaling, actual touch actions, paging, the field guide and modal footers. Running the entire large-screen matrix at DPR 3 exceeded the software-renderer job's 25-minute limit; splitting these checks retains the gameplay/layout coverage and explicitly checks the high-density regression. Local `npm run test:browser` still defaults to DPR 3.

Native checks passed: 47 simulation checks, 37 progression checks, and the asset/UI suite. Added asset checks confirm fewer mesh nodes, unchanged triangle counts, valid animation targets and existing roof/edge picking. Web and Windows exports were validated. Review also covered action-page rebuilding, portrait/landscape transitions, modal footers and scene cleanup on restart.

## Performance sample

Production UI tests explicitly advance the test-only simulation clock so a slow software renderer cannot finish queues while the test navigates buttons. Separate checks enable real time and verify both pause and resume. Normal play and performance benchmarks retain the real-time clock.

Chrome 152, RTX 4080 SUPER desktop GPU, 390×844 viewport, DPR 3, Eco mode, 4× CPU throttling. 129 animation-frame intervals after warm-up; AI disabled and stationary friendly units. This is a desktop proxy, not a physical phone or sustained-battle benchmark.

| Scene | Before median / p95 | After median / p95 | Draw calls before → after |
|---|---:|---:|---:|
| 7 friendly units | 16.7 / 16.9 ms | 16.7 / 16.9 ms | 285 → 197 |
| 100 friendly units | 50.0 / 83.3 ms | 33.6 / 66.9 ms | 1,891 → 1,059 |

The starting scene sustained roughly 60 FPS in this sample. The larger scene improved to about 30 FPS at the median, with visible frame-time spikes still possible. It is not yet a smooth 60-FPS large-army experience. Experimental 3D resolution scaling regressed this browser sample and was removed before shipping.

## Remaining device checks and improvements

The additional Windows Playwright WebKit 26 probe reported `glBlitFramebuffer: Read and write color attachments cannot be the same image` and did not validate the Godot 3D scene or touch flow. The rendering error also occurred in a temporary export using the previous disabled viewport-scaling mode. This does not establish behavior on physical iOS Safari; Safari compatibility remains unverified. Three.js passed its separate WebKit smoke test.

1. Run 15-minute 50–100-unit battles on a midrange Android phone and iPhone. Measure frame time, memory and thermal slowdown; test browser toolbar resizing, notches, orientation and background/resume.
2. If large-army rendering remains the bottleneck, profile animation and material draw submission. Evaluate material atlases and distance-based animation/mesh detail while retaining recognizable units and reliable selection.
3. Re-test CPU/GPU changes independently. Do not run concurrent browser suites while measuring performance, and keep the normal scene and stress scene results separate.
