# Harvester behavior parity

Scope: harvesting reliability in Godot and Three.js. This does not claim parity for unrelated map selection, enemy counts or other game features.

Both editions gather up to 10 resources, return cargo to a completed friendly Command core, and resume work. Gather approach uses a 0.8-unit margin and 0.2-unit arrival tolerance, safely inside the 1.4-unit work margin. Route and stall state reset during work and when changing between gathering and delivery.

When a deposit runs out, the worker delivers any partial cargo first. Explicit queued commands take priority. Otherwise it chooses the nearest reachable, explored deposit of the same type within 30 world units of its current position. It does not scout unknown or distant resources automatically. Missing replacements or completed cores produce a message. Cargo remains carried if delivery cannot happen.

Godot's movement already detects failed paths rather than using the defective per-frame distance threshold previously present in Three.js. Its six-second blocked-route timeout now reports why the order was cleared.

Regression scenarios in both repositories cover crowded five-minute gathering, movement at 30/60/144/240 FPS, partial-load accounting, depletion recovery, queued movement, exploration/distance limits, and missing-core recovery. Godot checks its four existing maps and both factions; Three.js checks seven maps and four factions. Headless tests exercise simulation timing, not physical phone performance.
