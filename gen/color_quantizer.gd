class_name ColorQuantizer
extends RefCounted
## Weighted k-means in Lab space.
##
## Pixels are first binned into a 15-bit RGB histogram, so the expensive Lab
## conversion and the clustering run on unique colors rather than on every
## pixel. Clustering trains on coarser 12-bit bins (at most 4096 points) and
## the final assignment uses the finer bins.


## Returns {"centers": PackedVector3Array (Lab), "labels": PackedInt32Array}
## with one label per input color.
static func quantize(colors: PackedColorArray, k: int, seed_value: int, iterations: int = 12) -> Dictionary:
	var fine := _histogram(colors, 5)
	var coarse := _histogram(colors, 4)
	var points: PackedVector3Array = coarse["lab"]
	var weights: PackedFloat32Array = coarse["weight"]
	k = clampi(k, 1, maxi(1, points.size()))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var centers := _init_plus_plus(points, weights, k, rng)
	k = centers.size()
	var assign := PackedInt32Array()
	assign.resize(points.size())
	for iter in iterations:
		var sums := PackedVector3Array()
		sums.resize(k)
		var totals := PackedFloat32Array()
		totals.resize(k)
		var moved := false
		for i in points.size():
			var c := LabColor.nearest(points[i], centers)
			if c != assign[i]:
				moved = true
			assign[i] = c
			sums[c] += points[i] * weights[i]
			totals[c] += weights[i]
		for c in k:
			if totals[c] > 0.0:
				centers[c] = sums[c] / totals[c]
		if not moved and iter > 0:
			break

	# Final assignment through the fine histogram.
	var fine_lab: PackedVector3Array = fine["lab"]
	var fine_label := PackedInt32Array()
	fine_label.resize(fine_lab.size())
	for i in fine_lab.size():
		fine_label[i] = LabColor.nearest(fine_lab[i], centers)
	var bin_of: PackedInt32Array = fine["bin_of"]
	var labels := PackedInt32Array()
	labels.resize(colors.size())
	for i in colors.size():
		labels[i] = fine_label[bin_of[i]]
	return {"centers": centers, "labels": labels}


## Bins colors by their top `bits` bits per channel. Returns the mean Lab and
## pixel count of each used bin, plus the bin index of every input color.
static func _histogram(colors: PackedColorArray, bits: int) -> Dictionary:
	var levels := 1 << bits
	var slot_of := {}
	var sum_rgb := PackedVector3Array()
	var weight := PackedFloat32Array()
	var bin_of := PackedInt32Array()
	bin_of.resize(colors.size())
	for i in colors.size():
		var c := colors[i]
		var key := (mini(int(c.r * levels), levels - 1) * levels + mini(int(c.g * levels), levels - 1)) * levels \
				+ mini(int(c.b * levels), levels - 1)
		var slot: int = slot_of.get(key, -1)
		if slot < 0:
			slot = weight.size()
			slot_of[key] = slot
			sum_rgb.append(Vector3.ZERO)
			weight.append(0.0)
		sum_rgb[slot] += Vector3(c.r, c.g, c.b)
		weight[slot] += 1.0
		bin_of[i] = slot
	var lab := PackedVector3Array()
	lab.resize(weight.size())
	for s in weight.size():
		var m := sum_rgb[s] / weight[s]
		lab[s] = LabColor.from_color(Color(m.x, m.y, m.z))
	return {"lab": lab, "weight": weight, "bin_of": bin_of}


static func _init_plus_plus(points: PackedVector3Array, weights: PackedFloat32Array, k: int,
		rng: RandomNumberGenerator) -> PackedVector3Array:
	var centers := PackedVector3Array()
	# First center: the most common color, so results are stable.
	var best := 0
	for i in points.size():
		if weights[i] > weights[best]:
			best = i
	centers.append(points[best])
	var d2 := PackedFloat32Array()
	d2.resize(points.size())
	for i in points.size():
		d2[i] = points[i].distance_squared_to(centers[0])
	while centers.size() < k:
		var total := 0.0
		for i in points.size():
			total += d2[i] * weights[i]
		if total <= 0.0:
			break
		var pick := rng.randf() * total
		var chosen := points.size() - 1
		for i in points.size():
			pick -= d2[i] * weights[i]
			if pick <= 0.0:
				chosen = i
				break
		centers.append(points[chosen])
		for i in points.size():
			d2[i] = minf(d2[i], points[i].distance_squared_to(points[chosen]))
	return centers
