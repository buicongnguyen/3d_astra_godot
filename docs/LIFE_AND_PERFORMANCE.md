# Living battlefields and phone performance

October 2026, ported from the Three.js edition (`github-io/docs/LIFE_AND_PERFORMANCE.md` in the 3d_astra repository).

## Ambient life

`scripts/ambient_life.gd` gives every map its own cast:

| Map | Life |
|---|---|
| Ashen Frontier | crows, falling ash |
| Meridian Riverlands | gulls, fish, butterflies, dragonflies, pollen |
| Copper Basin | hawks, copper dust, butterflies |
| Frontier Expanse | geese in V formation, fish, butterflies, dragonflies, pollen |
| Amber Dunes | vultures, blowing sand |
| Verdant Crossing | songbirds, butterflies, fireflies, fish, dragonflies |
| Obsidian Highlands | ravens, rising embers |

- **One draw per family.** Each family is one MultiMesh; motes are a single point mesh.
- **Instance data are parameters, not poses.** They ride in the instance transform's origin and basis slots plus the custom data. The spatial shaders compute the motion and write `POSITION` themselves, so GDScript only advances one clock.
- **Hidden under the fog of war.** Creatures sample the visibility and explored textures.
- **Inside the map.** Paths stay inside the map and shrink away before the edge.
- **Lighter on Eco.** Eco (the default on touch devices) draws 60% of the cast.
- **Settings.** The detail setting hides the life, and reduced motion holds it still.

## Frame-time governor

`scripts/governor.gd` judges each second of play:
- **Slow:** the typical frame takes over 37 ms. A steady 30 Hz display cap does not count.
- **Smooth:** 90% of frames finish under 19 ms.
- **Stepping:** two slow seconds step cosmetic motion down (full → calm → still, where still also stops the water ripples), and eight smooth seconds step it back up.
- **Ignored time:** hitches, pauses and the first 3 s of a match.
- **In tests:** the governor stays off, and the `governor` test command feeds it synthetic timings.

## Fog of war

The fog plane used to be rebuilt every 0.25 s with one `set_pixel` call per grid cell from GDScript (up to 9,216 calls on the largest map). It now uploads the simulation's `visible` and `explored` byte arrays as two R8 textures, which takes two native calls, and the shader blends them.

## Verification

- `tests/life_test.gd` (headless, in CI) checks that:
  - plans are deterministic, scale with the budget and stay in bounds;
  - fish stay in the river;
  - each map builds its families;
  - motion levels and reduced motion hold the clock;
  - the governor handles 60 fps, a 30 Hz cap, slow frames, recovery and hitches.
- `npm run test:life` (browser, CI group `visuals`) checks that all seven maps build their families with no shader errors in the exported game, that the clock moves, and that the governor goes full → calm → still → full.

## Units drawn in batches

`scripts/world_view.gd` draws unit and building parts through shared MultiMesh batches. The cloned parts keep their animation and transforms, but sit on render layer 2, which the camera skips and which casts no shadow. Each frame their global transforms are copied into one MultiMesh per mesh and material set; team colours are baked into a mesh copy per team. Picking uses each model's pick boxes, so it is unaffected.

| Real WebGL draws at match start (Riverlands) | Before | After |
|---|---|---|
| Phone, Eco | 355 | 245 |
| Desktop, shadows on | 665 | 445 |

Before batching, each extra unit added several draws (more again with shadows). Now each kind of part costs one draw whatever the army size, so battles gain far more than the match start. About 90 of the remaining phone draws are the 2D interface.
