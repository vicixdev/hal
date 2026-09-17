package main

import la "core:math/linalg"

Camera :: struct {
	position:	[3]f32,
	// pitch and yaw
	rotation:	[2]f32,

	fov:		f32,
	aspect:		f32,
	near:		f32,
	far:		f32,
}

// Minecraft style
move_camera :: proc(camera: ^Camera, direction: [3]f32, speed: f32, dt: f32) {
	if direction == { 0, 0, 0 } {
		return
	}

	input := la.normalize(direction) * speed * dt

	front := [3]f32 {
		la.sin(camera.rotation.y),
		0,
		-la.cos(camera.rotation.y),
	}

	right := la.cross(front, [3]f32{ 0, 1, 0})
	
	camera.position += front * input.z
	camera.position += right * input.x
	camera.position.y += input.y
}

rotate_camera :: proc(camera: ^Camera, rotation: [2]f32) {
	epsilon: f32 = 0.05

	camera.rotation += rotation

	if camera.rotation.x >= (la.PI/2 - epsilon) {
		camera.rotation.x = la.PI/2 - epsilon
	} else if camera.rotation.x <= -(la.PI/2 - epsilon) {
		camera.rotation.x = -(la.PI/2 - epsilon)
	}
}

get_camera_matrices :: proc(camera: Camera) -> (view: matrix[4,4]f32, proj: matrix[4,4]f32) {
	look_direction := [3]f32 {
		 la.cos(camera.rotation.x) * la.sin(camera.rotation.y),
		 la.sin(camera.rotation.x),
		-la.cos(camera.rotation.x) * la.cos(camera.rotation.y),
	}

	view = la.matrix4_look_at_f32(camera.position, camera.position + look_direction, { 0, 1, 0 })
	proj = la.matrix4_perspective_f32(camera.fov, camera.aspect, camera.near, camera.far)

	return
}


