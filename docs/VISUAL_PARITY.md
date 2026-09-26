# Godot visual improvements transferred from Three.js

Reference: Three.js `e334b8d` (art introduced by `3a8d903`, refined by `67d2753`).

| Three.js improvement | Godot implementation |
|---|---|
| Beveled Blender units/buildings, baked vertex shading, PBR materials | Same exported GLBs and animation clips, with native material batching and team recoloring. Updated Blender sources and generators are included. |
| Detailed obstacle rocks and resource crystals | Blender scenery replaces placeholder spheres and cones. Rocks are scaled inside their existing collision footprints. |
| Truss bridges | Native MultiMesh instances of the same bridge asset at the existing crossings. |
| Clean map edges | Removed off-map hills and trees; slab matches the exact map size; a thin inset border marks the playable edge. Scenery placement stays inside all seven maps. |
| Soft terrain transitions | One mipmapped, linearly filtered color texture generated when the map loads. Noise and blended terrain samples add detail with no per-frame terrain generation. |
| Improved river channel | Recessed banks, a raised central ford, subtler water ripples and shallow-bank coloring. |
| Clearer selection rings | One native shader plane per selected entity, replacing two torus meshes. Team tint, bright core, soft halo and dashed band respect the combat-motion setting. |
| Bounded decorative detail | Repeated bushes, reeds, trees and rocks use MultiMesh. Decoration scales with map size up to a fixed cap and avoids bases, deposits and crossings. The Detail setting hides optional scenery. |

## Engine differences retained

Godot continues to use its existing fog-of-war, compact HUD, capped combat-effect pools and imported death clips. Three.js JavaScript shaders, DOM UI and PMREM reflection setup cannot be copied directly. High-quality reflection lighting and a larger 3D combat-effects rewrite are separate follow-ups requiring Android frame-time measurements; they are not part of this update.

This is a visual update. Map limits, navigation obstacles, resource quantities and combat rules remain unchanged.

## Verification

- Existing asset tests validate animation tracks, static batching, building picking, team colors and restart cleanup.
- `tests/visual_port_test.gd` checks scenery bounds and budgets on all seven maps, resource visuals, vertex-color preservation and native selection-ring tint.
- Browser inspection covers desktop, map corners and portrait mobile, including shader/runtime errors.
- The normal GitHub workflow retains desktop, mobile, map, control, construction and combat-effect checks.

## Rebuilding the art

Blender is needed only to regenerate assets, not to play or export the Godot game:

```sh
blender --background --python tools/blender/generate_assets.py
blender --background --python tools/blender/generate_environment.py
blender --background --python tools/blender/animate_units.py
```

The Godot-specific generator paths write `assets/models/` and `assets/source/`. The Blender toolkit supplies baked ambient occlusion and beveled geometry without adding runtime rendering passes.
