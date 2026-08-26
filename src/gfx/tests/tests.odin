#+private
package gfx_tests

import "base:runtime"
import "core:mem"
import "core:testing"
import "core:image"
import "core:slice"
import "core:log"
@(require) import "core:image/png"
import gfx ".."

@(init)
init_gfx :: proc "contextless" () {
	context = runtime.default_context()
	context.logger = log.create_console_logger(allocator=context.temp_allocator)

	init_res := gfx.init()
	assert(init_res == nil, "Could not initialize gfx.")

	devices, devices_res := gfx.enumerate_devices()
	assert(devices_res == nil, "No suitable devices found.")

	log.infof("%#v", devices)
	// device_info := &devices[len(devices)-1]
	device_info := &devices[0]
	device := device_info.id
	device_res := gfx.select_device(device)
	assert(device_res == nil, "Could not select a device.")
}

@(fini)
fini_gfx :: proc "contextless" () {
	context = runtime.default_context()
	gfx.fini()
}

@(test)
memory_transfers_with_barriers :: proc(t: ^testing.T) {
	device_info, _ := gfx.selected_device_info()

	upload, upload_res := gfx.alloc(.Staging, device_info.limits.min_allocation_size)
	gpu, gpu_res := gfx.alloc(.Private, device_info.limits.min_allocation_size)
	download, download_res := gfx.alloc(.Readback, device_info.limits.min_allocation_size)
	testing.expect(t, upload_res == nil && gpu_res == nil && download_res == nil)
	defer {
		gfx.dealloc(upload)
		gfx.dealloc(gpu)
		gfx.dealloc(download)
	}

	upload_i64 := cast([^]i64)upload.contents
	gpu_i64 := cast([^]i64)upload.contents
	download_i64 := cast([^]i64)upload.contents

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		upload_i64[i] = cast(i64)i
	}

	sema, sema_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, sema_res, nil)
	defer gfx.destroy_semaphore(sema)

	command_buffer, command_buffer_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, command_buffer_res, nil)

	gfx.mem_copy(command_buffer, gpu, upload, device_info.limits.min_allocation_size)
	gfx.barrier(command_buffer, { .Transfer }, { .Transfer })
	gfx.mem_copy(command_buffer, download, gpu, device_info.limits.min_allocation_size)
	gfx.submit(.Default, { command_buffer }, { sema, 1 })

	gfx.wait_semaphore(sema, 1)

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		testing.expect_value(t, download_i64[i], cast(i64)i)
	}
}

@(test)
memory_transfers_with_fences :: proc(t: ^testing.T) {
	device_info, _ := gfx.selected_device_info()

	fence, fence_res := gfx.create_fence()
	testing.expect_value(t, fence_res, nil)
	defer gfx.destroy_fence(fence)

	upload, upload_res := gfx.alloc(.Staging, device_info.limits.min_allocation_size)
	gpu, gpu_res := gfx.alloc(.Private, device_info.limits.min_allocation_size)
	download, download_res := gfx.alloc(.Readback, device_info.limits.min_allocation_size)
	testing.expect(t, upload_res == nil && gpu_res == nil && download_res == nil)
	defer {
		gfx.dealloc(upload)
		gfx.dealloc(gpu)
		gfx.dealloc(download)
	}

	upload_i64 := cast([^]i64)upload.contents
	gpu_i64 := cast([^]i64)upload.contents
	download_i64 := cast([^]i64)upload.contents

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		upload_i64[i] = cast(i64)i
	}

	sema, sema_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, sema_res, nil)
	defer gfx.destroy_semaphore(sema)

	command_buffer, command_buffer_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, command_buffer_res, nil)

	gfx.mem_copy(command_buffer, gpu, upload, device_info.limits.min_allocation_size)
	gfx.signal(command_buffer, fence)
	testing.expect_value(t, fence_res, nil)

	gfx.wait(command_buffer, fence)
	gfx.mem_copy(command_buffer, download, gpu, device_info.limits.min_allocation_size)
	gfx.submit(.Default, {command_buffer}, {sema, 1})

	gfx.wait_semaphore(sema, 1)

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		testing.expect_value(t, download_i64[i], cast(i64)i)
	}
}

@(test)
memory_transfers_with_multiple_command_buffers_and_fences :: proc(t: ^testing.T) {
	device_info, _ := gfx.selected_device_info()

	fence, fence_res := gfx.create_fence()
	testing.expect_value(t, fence_res, nil)
	defer gfx.destroy_fence(fence)

	upload, upload_res := gfx.alloc(.Staging, device_info.limits.min_allocation_size)
	gpu, gpu_res := gfx.alloc(.Private, device_info.limits.min_allocation_size)
	download, download_res := gfx.alloc(.Readback, device_info.limits.min_allocation_size)
	testing.expect(t, upload_res == nil && gpu_res == nil && download_res == nil)
	defer {
		gfx.dealloc(upload)
		gfx.dealloc(gpu)
		gfx.dealloc(download)
	}

	upload_i64 := cast([^]i64)upload.contents
	gpu_i64 := cast([^]i64)upload.contents
	download_i64 := cast([^]i64)upload.contents

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		upload_i64[i] = cast(i64)i
	}

	sema, sema_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, sema_res, nil)
	defer gfx.destroy_semaphore(sema)

	cb1, cb1_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, cb1_res, nil)
	cb2, cb2_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, cb2_res, nil)

	gfx.mem_copy(cb1, gpu, upload, device_info.limits.min_allocation_size)
	gfx.signal(cb1, fence)

	gfx.wait(cb2, fence)
	gfx.mem_copy(cb2, download, gpu, device_info.limits.min_allocation_size)
	gfx.submit(.Default, {cb1, cb2}, {sema, 1})

	gfx.wait_semaphore(sema, 1)

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		testing.expect_value(t, download_i64[i], cast(i64)i)
	}
}

@(test)
memory_transfers_with_multiple_command_buffers_and_semaphores :: proc(t: ^testing.T) {
	device_info, _ := gfx.selected_device_info()

	upload, upload_res := gfx.alloc(.Staging, device_info.limits.min_allocation_size)
	gpu, gpu_res := gfx.alloc(.Private, device_info.limits.min_allocation_size)
	download, download_res := gfx.alloc(.Readback, device_info.limits.min_allocation_size)
	testing.expect(t, upload_res == nil && gpu_res == nil && download_res == nil)
	defer {
		gfx.dealloc(upload)
		gfx.dealloc(gpu)
		gfx.dealloc(download)
	}

	upload_i64 := cast([^]i64)upload.contents
	gpu_i64 := cast([^]i64)upload.contents
	download_i64 := cast([^]i64)upload.contents

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		upload_i64[i] = cast(i64)i
	}

	sema, sema_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, sema_res, nil)
	defer gfx.destroy_semaphore(sema)

	on_work_done, on_work_done_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, on_work_done_res, nil)
	defer gfx.destroy_semaphore(on_work_done)

	cb1, cb1_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, cb1_res, nil)
	gfx.mem_copy(cb1, gpu, upload, device_info.limits.min_allocation_size)
	gfx.submit(.Default, { cb1 }, { sema, 1 })

	cb2, cb2_res := gfx.begin_command_encoding(.Default, { sema, 1 })
	gfx.mem_copy(cb2, download, gpu, device_info.limits.min_allocation_size)

	gfx.submit(.Default, { cb2 }, { on_work_done, 1 })

	gfx.wait_semaphore(on_work_done, 1)

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		testing.expect_value(t, download_i64[i], cast(i64)i)
	}
}

@(test)
texture_upload_download :: proc(t: ^testing.T) {

	@(static, rodata)
	TEXTURE_DATA := [?][4]u8 {
		{ 0, 0, 0, 255 }, { 255, 0, 0, 255 },
		{ 0, 255, 0, 255 }, { 0, 0, 255, 255 },
	}

	memory: gfx.Arena
	memory_res := gfx.create_arena(&memory, .Default, 4096)
	assert(memory_res == nil)
	defer gfx.destroy_arena(memory)

	private_memory: gfx.Arena
	private_memory_res := gfx.create_arena(&private_memory, .Private, 4096)
	assert(private_memory_res == nil)
	defer gfx.destroy_arena(private_memory)

	texture_desc := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= { 2, 2, 1 },
		format		= .RGBA8_Unorm,
		usage		= {},
	}
	texture_size, texture_align, size_align_res := gfx.size_align_of(texture_desc)
	assert(size_align_res == nil)

	texture_buffer, texture_buffer_res := gfx.arena_alloc(&private_memory, texture_size, texture_align)
	assert(texture_buffer_res == nil)

	texture, texture_res := gfx.create_texture(texture_buffer, texture_desc)
	assert(texture_res == nil)
	defer gfx.destroy_texture(texture)

	upload_buffer, upload_buffer_res := gfx.arena_alloc(&memory, size_of(TEXTURE_DATA))
	assert(upload_buffer_res == nil)
	mem.copy(upload_buffer.contents, &TEXTURE_DATA[0], size_of(TEXTURE_DATA))

	download_buffer, download_buffer_res := gfx.arena_alloc(&memory, size_of(TEXTURE_DATA))
	assert(download_buffer_res == nil)

	semaphore, semaphore_res := gfx.create_semaphore(.Cpu_Waitable)
	assert(semaphore_res == nil)

	command_buffer, command_buffer_res := gfx.begin_command_encoding(.Default)
	assert(command_buffer_res == nil)

	gfx.copy_buffer_to_texture(command_buffer, upload_buffer, texture, gfx.Texture_Region {
		layer_count	= 1,
		size		= { 2, 2, 1 },
	})
	gfx.barrier(command_buffer, { .Transfer }, { .Transfer })
	gfx.copy_texture_to_buffer(command_buffer, texture, gfx.Texture_Region {
		layer_count	= 1,
		size		= { 2, 2, 1 },
	}, download_buffer)

	submit_res := gfx.submit(.Default, { command_buffer }, { semaphore, 1 })
	assert(submit_res == nil)

	gfx.wait_semaphore(semaphore, 1)

	download_pixels := cast([^][4]u8)download_buffer.contents
	for i in 0..<len(TEXTURE_DATA) {
		testing.expect_value(t, download_pixels[i], TEXTURE_DATA[i])
	}
}

@(test)
memory_transfers_with_textures :: proc(t: ^testing.T) {

	@(static, rodata)
	TEXTURE_DATA := [?][4]u8 {
		{ 0, 0, 0, 255 }, { 255, 0, 0, 255 },
		{ 0, 255, 0, 255 }, { 0, 0, 255, 255 },
	}

	memory: gfx.Arena
	memory_res := gfx.create_arena(&memory, .Default, 4096)
	assert(memory_res == nil)
	defer gfx.destroy_arena(memory)

	private_memory: gfx.Arena
	private_memory_res := gfx.create_arena(&private_memory, .Private, 4096)
	assert(private_memory_res == nil)
	defer gfx.destroy_arena(private_memory)

	texture_desc := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= { 2, 2, 1 },
		format		= .RGBA8_Unorm,
		usage		= {},
	}
	texture_size, texture_align, size_align_res := gfx.size_align_of(texture_desc)
	assert(size_align_res == nil)

	texture_1_buffer, texture_1_buffer_res := gfx.arena_alloc(&private_memory, texture_size, texture_align)
	assert(texture_1_buffer_res == nil)

	texture_1, texture_1_res := gfx.create_texture(texture_1_buffer, texture_desc)
	assert(texture_1_res == nil)
	defer gfx.destroy_texture(texture_1)

	texture_2_buffer, texture_2_buffer_res := gfx.arena_alloc(&private_memory, texture_size, texture_align)
	assert(texture_2_buffer_res == nil)

	texture_2, texture_2_res := gfx.create_texture(texture_2_buffer, texture_desc)
	assert(texture_2_res == nil)
	defer gfx.destroy_texture(texture_2)

	upload_buffer, upload_buffer_res := gfx.arena_alloc(&memory, size_of(TEXTURE_DATA))
	assert(upload_buffer_res == nil)
	mem.copy(upload_buffer.contents, &TEXTURE_DATA[0], size_of(TEXTURE_DATA))

	download_buffer, download_buffer_res := gfx.arena_alloc(&memory, size_of(TEXTURE_DATA))
	assert(download_buffer_res == nil)

	semaphore, semaphore_res := gfx.create_semaphore(.Cpu_Waitable)
	assert(semaphore_res == nil)

	command_buffer, command_buffer_res := gfx.begin_command_encoding(.Default)
	assert(command_buffer_res == nil)

	gfx.copy_buffer_to_texture(command_buffer, upload_buffer, texture_1, gfx.Texture_Region {
		layer_count	= 1,
		size		= { 2, 2, 1 },
	})
	gfx.barrier(command_buffer, { .Transfer }, { .Transfer })
	gfx.copy_texture_to_texture(
		command_buffer,
		texture_1,
		gfx.Texture_Region {
			layer_count	= 1,
			size		= { 2, 2, 1 },
		},
		texture_2,
		gfx.Texture_Region {
			layer_count	= 1,
			size		= { 2, 2, 1 },
		},
	)
	gfx.barrier(command_buffer, { .Transfer }, { .Transfer })
	gfx.copy_texture_to_buffer(command_buffer, texture_2, gfx.Texture_Region {
		layer_count	= 1,
		size		= { 2, 2, 1 },
	}, download_buffer)

	submit_res := gfx.submit(.Default, { command_buffer }, { semaphore, 1 })
	assert(submit_res == nil)

	gfx.wait_semaphore(semaphore, 1)

	download_pixels := cast([^][4]u8)download_buffer.contents
	for i in 0..<len(TEXTURE_DATA) {
		testing.expect_value(t, download_pixels[i], TEXTURE_DATA[i])
	}
}

@(test)
copy_texture_with_compute :: proc(t: ^testing.T) {

	@(static, rodata)
	TEXTURE_DATA := [?][4]u8 {
		{ 0, 0, 0, 255 }, { 255, 0, 0, 255 },
		{ 0, 255, 0, 255 }, { 0, 0, 255, 255 },
	}

	when gfx.TARGET_API == .Vulkan {
		TEXTURE_COPY_BYTECODE := #load("./shaders/texture_copy.spv")
	} else when gfx.TARGET_API == .Metal_3 {
		TEXTURE_COPY_BYTECODE := #load("./shaders/texture_copy.metallib")
	}

	Texture_Copy_Arguments :: struct #packed {
		size:		[2]u32,
		texture_in:	u32,
		texture_out:	u32,
	}

	memory: gfx.Arena
	memory_res := gfx.create_arena(&memory, .Default, 4096)
	assert(memory_res == nil)
	defer gfx.destroy_arena(memory)

	private_memory: gfx.Arena
	private_memory_res := gfx.create_arena(&private_memory, .Private, 4096)
	assert(private_memory_res == nil)
	defer gfx.destroy_arena(private_memory)

	pipeline, pipeline_res := gfx.create_compute_pipeline(
		{
			bytecode	= TEXTURE_COPY_BYTECODE[:],
			entrypoint	= "texture_copy",
			group_size	= { 32, 32, 1 },
		},
	)
	assert(pipeline_res == nil)
	defer gfx.destroy_pipeline(pipeline)

	resource_set, resource_set_res := gfx.create_resource_set()
	assert(resource_set_res == nil)
	defer gfx.destroy_resource_set(resource_set)

	texture_desc := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= { 2, 2, 1 },
		format		= .RGBA8_Unorm,
		usage		= { .Storage },
	}
	texture_size, texture_align, size_align_res := gfx.size_align_of(texture_desc)
	assert(size_align_res == nil)

	texture_1_buffer, texture_1_buffer_res := gfx.arena_alloc(&private_memory, texture_size, texture_align)
	assert(texture_1_buffer_res == nil)

	texture_1, texture_1_res := gfx.create_texture(texture_1_buffer, texture_desc)
	assert(texture_1_res == nil)
	defer gfx.destroy_texture(texture_1)

	texture_2_buffer, texture_2_buffer_res := gfx.arena_alloc(&private_memory, texture_size, texture_align)
	assert(texture_2_buffer_res == nil)

	texture_2, texture_2_res := gfx.create_texture(texture_2_buffer, texture_desc)
	assert(texture_2_res == nil)
	defer gfx.destroy_texture(texture_2)

	texture_1_view, texture_1_view_res := gfx.default_view_of(texture_1)
	assert(texture_1_view_res == nil)
	texture_2_view, texture_2_view_res := gfx.default_view_of(texture_2)
	assert(texture_2_view_res == nil)
	gfx.set_storage_texture_set(
		resource_set,
		.D2,
		{ texture_1_view, texture_2_view },
	)

	upload_buffer, upload_buffer_res := gfx.arena_alloc(&memory, size_of(TEXTURE_DATA))
	assert(upload_buffer_res == nil)
	mem.copy(upload_buffer.contents, &TEXTURE_DATA[0], size_of(TEXTURE_DATA))

	download_buffer, download_buffer_res := gfx.arena_alloc(&memory, size_of(TEXTURE_DATA))
	assert(download_buffer_res == nil)

	semaphore, semaphore_res := gfx.create_semaphore(.Cpu_Waitable)
	assert(semaphore_res == nil)

	command_buffer, command_buffer_res := gfx.begin_command_encoding(.Default)
	assert(command_buffer_res == nil)

	gfx.copy_buffer_to_texture(command_buffer, upload_buffer, texture_1, gfx.Texture_Region {
		layer_count	= 1,
		size		= { 2, 2, 1 },
	})
	gfx.barrier(command_buffer, { .Transfer }, { .Compute })
	gfx.use_resources(command_buffer, resource_set)
	gfx.dispatch(
		command_buffer,
		pipeline,
		Texture_Copy_Arguments {
			size		= { 2, 2 },
			texture_in	= 0,
			texture_out	= 1,
		},
		{ 1, 1, 1 },
	)
	gfx.barrier(command_buffer, { .Compute }, { .Transfer })
	gfx.copy_texture_to_buffer(command_buffer, texture_2, gfx.Texture_Region {
		layer_count	= 1,
		size		= { 2, 2, 1 },
	}, download_buffer)

	submit_res := gfx.submit(.Default, { command_buffer }, { semaphore, 1 })
	assert(submit_res == nil)

	gfx.wait_semaphore(semaphore, 1)

	download_pixels := cast([^][4]u8)download_buffer.contents
	for i in 0..<len(TEXTURE_DATA) {
		testing.expect_value(t, download_pixels[i], TEXTURE_DATA[i])
	}
}

// @(test)
clear_render_pass :: proc(t: ^testing.T) {

	FRAMEBUFFER_SIZE := [2]int{ 4, 4 }

	memory: gfx.Arena
	memory_res := gfx.create_arena(&memory, .Default, 4096)
	assert(memory_res == nil)
	defer gfx.destroy_arena(memory)

	private_memory: gfx.Arena
	private_memory_res := gfx.create_arena(&private_memory, .Private, 4096)
	assert(private_memory_res == nil)
	defer gfx.destroy_arena(private_memory)

	semaphore, semaphore_res := gfx.create_semaphore(.Cpu_Waitable)
	assert(semaphore_res == nil)

	download, download_res := gfx.arena_alloc(&memory, FRAMEBUFFER_SIZE.x * FRAMEBUFFER_SIZE.y * size_of([4]u8))
	assert(download_res == nil)

	framebuffer_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		format		= .RGBA8_Unorm,
		usage		= { .Color_Attachment },
		dimensions	= { **FRAMEBUFFER_SIZE, 1 },
	}
	framebuffer_size, framebuffer_align, _ := gfx.size_align_of(framebuffer_descriptor)
	framebuffer_memory, _ := gfx.arena_alloc(&private_memory, framebuffer_size, framebuffer_align)
	framebuffer, framebuffer_res := gfx.create_texture(framebuffer_memory, framebuffer_descriptor)
	framebuffer_view, _ := gfx.default_view_of(framebuffer)
	assert(framebuffer_res == nil)

	render_pass_descriptor := gfx.Render_Pass_Descriptor {
		color_attachments = {
			gfx.Render_Attachment {
				view		= framebuffer_view,
				load_operation	= .Clear,
				store_operation	= .Store,
				clear_value	= [4]f64{ 1.0, 0.0, 0.0, 1.0 },
			},
		},
	}
	command_buffer, command_buffer_res := gfx.begin_command_encoding(.Default)
	gfx.begin_render_pass(command_buffer, render_pass_descriptor)
	gfx.end_render_pass(command_buffer)

	gfx.barrier(command_buffer, { .Color_Attachment }, { .Transfer })
	gfx.copy_texture_to_buffer(command_buffer, framebuffer, gfx.Texture_Region {
		layer_count = 1,
		size = { **FRAMEBUFFER_SIZE, 1 },
	}, download)

	gfx.submit(.Default, { command_buffer }, { semaphore, 1 })

	gfx.wait_semaphore(semaphore, 1)

	download_pixels := cast([^][4]u8)download.contents
	for x in 0..<FRAMEBUFFER_SIZE.x do for y in 0..<FRAMEBUFFER_SIZE.y {

		index := y * FRAMEBUFFER_SIZE.x + x
		testing.expect_value(t, download_pixels[index], [4]u8{ 255, 0, 0, 255 })
	}
}

@(test)
generic_compute_test :: proc(t: ^testing.T) {
	ARRAY_LENGTH :: 4096

	when gfx.TARGET_API == .Vulkan {
		ADD_BYTECODE := #load("./shaders/basic.spv")
	} else when gfx.TARGET_API == .Metal_3 {
		ADD_BYTECODE := #load("./shaders/basic.metallib")
	}

	Parameters :: struct {
		in_a:	uintptr,
		in_b:	uintptr,
		out:	uintptr,
	}

	half: f32 = 0.5
	add_pipeline, add_pipeline_res := gfx.create_compute_pipeline({
		bytecode	= ADD_BYTECODE[:],
		entrypoint	= "add",
		constants	= {
			{ type = .F32, value = &half },
		},
		group_size = { 128, 1, 1 },
	})
	testing.expect_value(t, add_pipeline_res, nil)
	defer gfx.destroy_pipeline(add_pipeline)

	semaphore, semaphore_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, semaphore_res, nil)
	defer gfx.destroy_semaphore(semaphore)

	memory: gfx.Arena
	memory_res := gfx.create_arena(&memory, .Default, size_of(f32) * ARRAY_LENGTH * 3)
	testing.expect_value(t, memory_res, nil)
	defer gfx.destroy_arena(memory)

	in_a, in_a_res := gfx.arena_alloc(&memory, size_of(f32) * ARRAY_LENGTH)
	in_b, in_b_res := gfx.arena_alloc(&memory, size_of(f32) * ARRAY_LENGTH)
	out, out_res := gfx.arena_alloc(&memory, size_of(f32) * ARRAY_LENGTH)
	testing.expect(t, in_a_res == nil && in_b_res == nil && out_res == nil)

	floats_a := cast([^]f32)in_a.address
	floats_b := cast([^]f32)in_b.address
	floats_out := cast([^]f32)out.address
	for i := 0; i < ARRAY_LENGTH; i += 1 {
		floats_a[i] = cast(f32)i
		floats_b[i] = cast(f32)i * 4
	}

	gpu_a, gpu_a_res := gfx.gpu_address_of(in_a)
	gpu_b, gpu_b_res := gfx.gpu_address_of(in_b)
	gpu_out, gpu_out_res := gfx.gpu_address_of(out)
	testing.expect(t, gpu_a_res == nil && gpu_b_res == nil && gpu_out_res == nil)

	command_buffer, command_buffer_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, command_buffer_res, nil)
	gfx.dispatch(command_buffer, add_pipeline, Parameters {
		in_a	= gpu_a,
		in_b	= gpu_b,
		out	=  gpu_out,
	}, { ARRAY_LENGTH / 128, 1, 1 })
	gfx.submit(.Default, {command_buffer}, {semaphore, 1})

	gfx.wait_semaphore(semaphore, 1)
	for i := 0; i < ARRAY_LENGTH; i += 1 {
		testing.expect_value(t, floats_out[i], floats_a[i] + floats_b[i] * half)
	}
}

// @(test)
draw_triangle :: proc(t: ^testing.T) {

	when gfx.TARGET_API == .Vulkan {
		TRIANGLE_BYTECODE := #load("./shaders/triangle.spv")
	} else when gfx.TARGET_API == .Metal_3 {
		TRIANGLE_BYTECODE := #load("./shaders/triangle.metallib")
	}

	REFERENCE := #load("./images/triangle.png")

	default_memory: gfx.Arena
	default_memory_res := gfx.create_arena(&default_memory, .Default, 16 * mem.Megabyte)
	assert(default_memory_res == nil)

	private_memory: gfx.Arena
	private_memory_res := gfx.create_arena(&private_memory, .Private, 16 * mem.Megabyte)
	assert(private_memory_res == nil)

	Vertex :: struct #packed {
		position:	[3]f32,
		color:		[3]f32,
	}
	VERTICES := [?]Vertex {
		{ { -0.5, -0.5, 1.0 }, { 1.0, 0.0, 0.0 } },
		{ {  0.5, -0.5, 1.0 }, { 0.0, 1.0, 0.0 } },
		{ {  0.0,  0.5, 1.0 }, { 0.0, 0.0, 1.0 } },
	}
	vertices, _ := gfx.arena_alloc(&default_memory, size_of(VERTICES))
	mem.copy(vertices.contents, &VERTICES[0], size_of(VERTICES))
	gpu_vertices, _ := gfx.gpu_address_of(vertices)

	download, _ := gfx.arena_alloc(&default_memory, size_of([4]u8) * 640 * 480)

	pipeline_descriptor := gfx.Render_Pipeline_Descriptor {
		vertex_stage	= {
			bytecode	= TRIANGLE_BYTECODE[:],
			entrypoint	= "vertex_main",
		},
		fragment_stage	= {
			bytecode	= TRIANGLE_BYTECODE[:],
			entrypoint	= "fragment_main",
		},
		topology	= .Triangle_List,
		cull		= .None,
		sample_count	= 4,
		color_formats	= { .RGBA8_Unorm },
	}
	pipeline, pipeline_res := gfx.create_render_pipeline(pipeline_descriptor)
	assert(pipeline_res == nil)

	framebuffer_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		format		= .RGBA8_Unorm,
		dimensions	= { 640, 480, 1 },
		usage		= { .Color_Attachment },
	}
	framebuffer_size, framebuffer_align, _ := gfx.size_align_of(framebuffer_descriptor)
	framebuffer_memory, _ := gfx.arena_alloc(&private_memory, framebuffer_size, framebuffer_align)

	framebuffer, framebuffer_res := gfx.create_texture(framebuffer_memory, framebuffer_descriptor)
	assert(framebuffer_res == nil)
	defer gfx.destroy_texture(framebuffer)
	framebuffer_view, _ := gfx.default_view_of(framebuffer)

	semaphore, _ := gfx.create_semaphore(.Cpu_Waitable)
	defer gfx.destroy_semaphore(semaphore)

	Parameters :: struct #packed {
		vertices:	uintptr,
	}

	render_pass_descriptor := gfx.Render_Pass_Descriptor {
		color_attachments = {
			gfx.Render_Attachment {
				view		= framebuffer_view,
				load_operation	= .Clear,
				store_operation	= .Store,
				clear_value	= [4]f64{ 0.1, 0.025, 0.2, 1.0 },
			},
		},
	}
	command_buffer, _ := gfx.begin_command_encoding(.Default)
	gfx.begin_render_pass(command_buffer, render_pass_descriptor)
	gfx.draw(command_buffer, pipeline, Parameters {
		vertices = gpu_vertices,
	}, 3)
	gfx.end_render_pass(command_buffer)

	gfx.barrier(command_buffer, { .Color_Attachment }, { .Transfer })
	gfx.copy_texture_to_buffer(command_buffer, framebuffer, gfx.Texture_Region {
		layer_count = 1,
		size = { 640, 480, 1 },
	}, download)

	gfx.submit(.Default, { command_buffer }, { semaphore, 1 })
	gfx.wait_semaphore(semaphore, 1)

	img, img_res := image.load_from_bytes(REFERENCE[:])
	assert(img_res == nil)
	defer image.destroy(img)

	reference_pixels := slice.reinterpret([][4]u8, img.pixels.buf[:])
	download_pixels := cast([^][4]u8)download.contents
	for x in 0..<640 do for y in 0..<480 {
		i := y * 640 + x

		assert(reference_pixels[i] == download_pixels[i])
	}
}

