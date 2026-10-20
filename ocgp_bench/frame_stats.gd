# Frame-time "lows" without storing or sorting every frame.
#
# "X% low" = average frame rate of the slowest X% of frames (k = max(1, ceil(X% * frames)) frames).
# Only the slowest ceil(1% * total_frames) frames are kept, in an ascending array, so adding a frame is
# one comparison for the vast majority and one native binary search + insert for the rare slow ones.
extends RefCounted

var cap := 1
var worst := PackedInt32Array()   # slowest frames in microseconds, ascending (worst = last element)


func _init(total_frames: int) -> void:
	cap = maxi(1, ceili(0.01 * float(total_frames)))


func add(dt_us: int) -> void:
	if worst.size() < cap:
		worst.insert(worst.bsearch(dt_us), dt_us)
	elif dt_us > worst[0]:
		worst.remove_at(0)
		worst.insert(worst.bsearch(dt_us), dt_us)


# frac: 0.01 for the 1% low, 0.001 for 0.1%, 0.0001 for 0.01%. n_frames: frames seen so far.
func low_fps(frac: float, n_frames: int) -> float:
	if worst.is_empty():
		return 0.0
	var k := clampi(ceili(frac * float(n_frames)), 1, worst.size())
	var sum := 0.0
	for j in k:
		sum += float(worst[worst.size() - 1 - j])
	return 1.0e6 / maxf(sum / float(k), 1.0)


func worst_ms() -> float:
	return 0.0 if worst.is_empty() else float(worst[worst.size() - 1]) / 1000.0


func min_fps() -> float:
	return 0.0 if worst.is_empty() else 1.0e6 / maxf(float(worst[worst.size() - 1]), 1.0)
