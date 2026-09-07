# Original plan execution

The copied GODOT_BLENDER_PLAN.md is the source design. Its formerly deferred implementation was explicitly activated by the user on 2026-09-08.

| Original milestone | Godot implementation |
|---|---|
| Foundation | Independent Godot/GDScript project, 3D RTS camera, selection, commands, radius-aware navigation |
| Economy | Finite alloy/energy, worker carry/delivery cycles, placement, construction, cancellation |
| Production | Five building types, four unit types, queues, population reservations, blocked exits and rally points |
| Complete match | Counter/splash combat, weapon research, developing AI, victory/defeat/draw and restart |
| Presentation | Original Blender source/GLBs, named animation clips, paint materials, health UI and command audio |
| Information | Authoritative visibility grid, visual fog, minimap and last-known structure markers |
| Release | Windows executable and single-threaded web export, regression suites and GitHub Pages workflow |

Implementation choices: reuse the proven 96×96 m map and tuning from the Three.js edition instead of the plan's provisional 128×128 m values. The initial roster includes a barracks and three defenders, matching that edition. Mechanical unit animation uses rigid articulated Blender parts instead of skinned humanoid skeletons. Dynamic scenery and true elevation remain future features. The engine implementation is GDScript, not embedded JavaScript gameplay.

The follow-up polish plan and its execution evidence are in IMPROVEMENT_PLAN.md and REVIEW_AND_VERIFICATION.md. The Three.js repository remains independently runnable and deployed.
