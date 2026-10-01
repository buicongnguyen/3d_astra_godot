extends RefCounted
# Frame-time governor (same rules as the Three.js edition's governor.js, without the render
# scale step). Each second of play is judged: slow when the typical frame takes over 37 ms
# (under 27 fps; a steady ~33 ms is a 30 Hz display cap, not slowness), smooth when 90% of
# frames finish under 19 ms. Two slow seconds step down one level (3 full, 2 calm, 1 still with
# half the creatures hidden, 0 rescue with all hidden); eight smooth seconds step back up. Hitches over 250 ms, pauses and the first
# seconds of a match are ignored.
signal changed(level: int)

var level = 3
var samples: Array = []
var clock = 0.0
var slow = 0
var smooth = 0
var grace = 3.0

func reset():
	samples.clear(); clock = 0.0; slow = 0; smooth = 0; grace = 3.0

func sample(interval: float, playing: bool):
	if not playing or interval > 0.25:
		samples.clear(); clock = 0.0
		return
	if grace > 0:
		grace -= interval
		return
	samples.append(interval*1000.0); clock += interval
	if clock < 1.0: return
	samples.sort()
	var typical = samples[samples.size()/2]; var p90 = samples[int(samples.size()*0.9)]
	samples.clear(); clock = 0.0
	slow = slow+1 if typical > 37.0 else 0
	smooth = smooth+1 if p90 < 19.0 else 0
	if slow >= 2 and level > 0: set_level(level-1)
	elif smooth >= 8 and level < 3: set_level(level+1)

func set_level(value: int):
	level = value; slow = 0; smooth = 0
	changed.emit(level)
