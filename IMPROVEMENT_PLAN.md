# Godot improvement plan

Date: 2026-09-08. Scope: complete the first Godot + Blender release after three code/logic review passes. The original design is preserved in GODOT_BLENDER_PLAN.md.

## Findings and implementation order

1. **Readability and camera framing.** Reduce overexposed lighting, preserve the battlefield width on portrait phones, smooth visual fog without changing the authoritative visibility grid, and keep modal footers reachable. Acceptance: inspected desktop, portrait, and short-landscape screenshots; no clipped essential controls.
2. **First-match guidance.** Add an objective checklist and an idle-worker selector so new players can progress from gathering to production to attack without opening documentation. Acceptance: tutorial state comes from actual economy/construction/army state; selecting idle workers never changes their orders.
3. **Reproducible Blender animation.** Author and export named Idle/Walk/Work/Attack/Death clips for rigid articulated units in Blender, preserve original material names, and play appropriate clips in Godot. Keep .blend source and the generation script. Acceptance: four animated GLBs import, animation names are verified, and native/web runs load them. These mechanical units use rigid part animation rather than a skinned humanoid skeleton.
4. **Information and input robustness.** Retain last-seen enemy building markers without refreshing them out of sight, cancel gestures when released over UI, and pause on focus loss. Acceptance: hidden building changes do not leak through markers; touch cancellation and pause restoration pass browser regressions.
5. **Release evidence.** Run the native simulation suite, desktop/touch web suite, import/animation checks, native export smoke test, and an army-scale rendering sample. Publish through an SSH Git remote and a CI-gated Pages workflow. Record observed limits rather than promising physical-phone performance.

## Deferred work

True elevation/ramps, multiplayer, ships, destructible bridges, complex tech trees, full skeletal character animation, spatial-index optimization beyond the tested prototype scale, and physical Android/iOS profiling remain separate future improvements. The browser game and Godot game stay in separate repositories.

## Status

The five scoped improvements are implemented and locally verified. CI and live deployment verification follow the release commit. See REVIEW_AND_VERIFICATION.md for the final acceptance evidence and any remaining limits.
