#+private
package vicixdev_gfx_tests

import "base:runtime"
import "core:mem"
import "core:testing"
import gfx ".."

@(test)
memory_transfers_with_barriers :: proc(t: ^testing.T) {
	ELEMENT_COUNT :: 1024

	reference :: proc() -> (reference: []i64) {
		reference = make([]i64, ELEMENT_COUNT, context.temp_allocator)
		for i in 0..<ELEMENT_COUNT {
			reference[i] = cast(i64)i
		}

		return
	}

	test :: proc(results_memory: ^gfx.Arena) -> (output: []i64, res: gfx.Result) {
		device_info, _ := gfx.selected_device_info()

		staging_memory: gfx.Arena
		gfx.create_arena(&staging_memory, .Staging, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(staging_memory)

		private_memory: gfx.Arena
		gfx.create_arena(&private_memory, .Private, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(private_memory)

		upload := gfx.arena_alloc(&staging_memory, []i64, ELEMENT_COUNT) or_return
		gpu := gfx.arena_alloc(&private_memory, []i64, ELEMENT_COUNT) or_return
		output = gfx.arena_alloc(results_memory, []i64, ELEMENT_COUNT) or_return

		for i in 0..<ELEMENT_COUNT {
			upload[i] = cast(i64)i
		}

		sema := gfx.create_semaphore(.Cpu_Waitable) or_return
		defer gfx.destroy_semaphore(sema)

		command_buffer := gfx.begin_command_encoding(.Default) or_return

		gfx.mem_copy(command_buffer, raw_data(gpu), raw_data(upload), 1024 * size_of(i64)) or_return
		gfx.barrier(command_buffer, { .Transfer }, { .Transfer }) or_return
		gfx.mem_copy(command_buffer, raw_data(output), raw_data(gpu), 1024 * size_of(i64)) or_return
		gfx.submit(.Default, { command_buffer }, { sema, 1 }) or_return

		gfx.wait_semaphore(sema, 1)

		return output, nil
	}

	results_memory := acquire_test_resources()
	reference_bytes := reference()

	output, res := test(&results_memory)
	check_result(t, res)
	test_agains_reference_bytes(t, reference_bytes, output)
}

@(test)
memory_transfers_with_fences :: proc(t: ^testing.T) {
	ELEMENT_COUNT :: 1024

	reference :: proc() -> (reference: []i64) {
		reference = make([]i64, ELEMENT_COUNT, context.temp_allocator)
		for i in 0..<ELEMENT_COUNT {
			reference[i] = cast(i64)i
		}

		return
	}

	test :: proc(results_memory: ^gfx.Arena) -> (output: []i64, res: gfx.Result) {
		device_info, _ := gfx.selected_device_info()

		fence := gfx.create_fence() or_return

		staging_memory: gfx.Arena
		gfx.create_arena(&staging_memory, .Staging, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(staging_memory)

		private_memory: gfx.Arena
		gfx.create_arena(&private_memory, .Private, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(private_memory)

		upload := gfx.arena_alloc(&staging_memory, []i64, ELEMENT_COUNT) or_return
		gpu := gfx.arena_alloc(&private_memory, []i64, ELEMENT_COUNT) or_return
		output = gfx.arena_alloc(results_memory, []i64, ELEMENT_COUNT) or_return

		for i in 0..<ELEMENT_COUNT {
			upload[i] = cast(i64)i
		}

		sema := gfx.create_semaphore(.Cpu_Waitable) or_return
		defer gfx.destroy_semaphore(sema)

		command_buffer := gfx.begin_command_encoding(.Default) or_return

		gfx.mem_copy(command_buffer, raw_data(gpu), raw_data(upload), 1024 * size_of(i64)) or_return
		gfx.signal(command_buffer, fence) or_return
		gfx.wait(command_buffer, fence) or_return
		gfx.mem_copy(command_buffer, raw_data(output), raw_data(gpu), 1024 * size_of(i64)) or_return
		gfx.submit(.Default, { command_buffer }, { sema, 1 }) or_return

		gfx.wait_semaphore(sema, 1)

		return output, nil
	}

	results_memory := acquire_test_resources()
	reference_bytes := reference()

	output, res := test(&results_memory)
	check_result(t, res)
	test_agains_reference_bytes(t, reference_bytes, output)
}

@(test)
memory_transfers_with_multiple_command_buffers_and_fences :: proc(t: ^testing.T) {
	ELEMENT_COUNT :: 1024

	reference :: proc() -> (reference: []i64) {
		reference = make([]i64, ELEMENT_COUNT, context.temp_allocator)
		for i in 0..<ELEMENT_COUNT {
			reference[i] = cast(i64)i
		}

		return
	}

	test :: proc(results_memory: ^gfx.Arena) -> (output: []i64, res: gfx.Result) {
		device_info, _ := gfx.selected_device_info()

		fence := gfx.create_fence() or_return

		staging_memory: gfx.Arena
		gfx.create_arena(&staging_memory, .Staging, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(staging_memory)

		private_memory: gfx.Arena
		gfx.create_arena(&private_memory, .Private, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(private_memory)

		upload := gfx.arena_alloc(&staging_memory, []i64, ELEMENT_COUNT) or_return
		gpu := gfx.arena_alloc(&private_memory, []i64, ELEMENT_COUNT) or_return
		output = gfx.arena_alloc(results_memory, []i64, ELEMENT_COUNT) or_return

		for i in 0..<ELEMENT_COUNT {
			upload[i] = cast(i64)i
		}

		sema := gfx.create_semaphore(.Cpu_Waitable) or_return
		defer gfx.destroy_semaphore(sema)

		command_buffer_1 := gfx.begin_command_encoding(.Default) or_return
		command_buffer_2 := gfx.begin_command_encoding(.Default) or_return

		gfx.mem_copy(command_buffer_1, raw_data(gpu), raw_data(upload), 1024 * size_of(i64)) or_return
		gfx.signal(command_buffer_1, fence) or_return

		gfx.wait(command_buffer_2, fence) or_return
		gfx.mem_copy(command_buffer_2, raw_data(output), raw_data(gpu), 1024 * size_of(i64)) or_return
		gfx.submit(.Default, { command_buffer_1, command_buffer_2 }, { sema, 1 }) or_return

		gfx.wait_semaphore(sema, 1)

		return output, nil
	}

	results_memory := acquire_test_resources()
	reference_bytes := reference()

	output, res := test(&results_memory)
	check_result(t, res)
	test_agains_reference_bytes(t, reference_bytes, output)
}

@(test)
memory_transfers_with_multiple_command_buffers_and_semaphores :: proc(t: ^testing.T) {
	ELEMENT_COUNT :: 1024

	reference :: proc() -> (reference: []i64) {
		reference = make([]i64, ELEMENT_COUNT, context.temp_allocator)
		for i in 0..<ELEMENT_COUNT {
			reference[i] = cast(i64)i
		}

		return
	}

	test :: proc(results_memory: ^gfx.Arena) -> (output: []i64, res: gfx.Result) {
		device_info, _ := gfx.selected_device_info()

		fence := gfx.create_fence() or_return

		staging_memory: gfx.Arena
		gfx.create_arena(&staging_memory, .Staging, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(staging_memory)

		private_memory: gfx.Arena
		gfx.create_arena(&private_memory, .Private, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(private_memory)

		upload := gfx.arena_alloc(&staging_memory, []i64, ELEMENT_COUNT) or_return
		gpu := gfx.arena_alloc(&private_memory, []i64, ELEMENT_COUNT) or_return
		output = gfx.arena_alloc(results_memory, []i64, ELEMENT_COUNT) or_return

		for i in 0..<ELEMENT_COUNT {
			upload[i] = cast(i64)i
		}

		sema := gfx.create_semaphore(.Cpu_Waitable) or_return
		defer gfx.destroy_semaphore(sema)

		command_buffer_1 := gfx.begin_command_encoding(.Default) or_return
		gfx.mem_copy(command_buffer_1, raw_data(gpu), raw_data(upload), 1024 * size_of(i64)) or_return
		gfx.submit(.Default, { command_buffer_1 }, { sema, 1 })

		command_buffer_2 := gfx.begin_command_encoding(.Default, { sema, 1 }) or_return
		gfx.mem_copy(command_buffer_2, raw_data(output), raw_data(gpu), 1024 * size_of(i64)) or_return
		gfx.submit(.Default, { command_buffer_2 }, { sema, 2 }) or_return

		gfx.wait_semaphore(sema, 2)

		return output, nil
	}

	results_memory := acquire_test_resources()
	reference_bytes := reference()

	output, res := test(&results_memory)
	check_result(t, res)
	test_agains_reference_bytes(t, reference_bytes, output)
}

@(test)
texture_upload_download :: proc(t: ^testing.T) {

	@(static, rodata)
	REFERENCE := [?]Pixel {
		{ 0, 0, 0, 255 }, { 255, 0, 0, 255 },
		{ 0, 255, 0, 255 }, { 0, 0, 255, 255 },
	}

	test :: proc(results_memory: ^gfx.Arena) -> (output: []Pixel, res: gfx.Result) {

		staging_memory: gfx.Arena
		gfx.create_arena(&staging_memory, .Staging, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(staging_memory)

		private_memory: gfx.Arena
		gfx.create_arena(&private_memory, .Private, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(private_memory)

		texture_desc := gfx.Texture_Descriptor {
			type		= .D2_Array,
			dimensions	= { 2, 2, 1 },
			format		= .RGBA8_Unorm,
			usage		= {},
		}
		texture_size, texture_align := gfx.size_align_of(texture_desc) or_return
		texture_buffer := gfx.arena_alloc(&private_memory, texture_size, texture_align) or_return

		texture := gfx.create_texture(texture_buffer, texture_desc) or_return
		defer gfx.destroy_texture(texture)

		upload_buffer := gfx.arena_alloc(&staging_memory, []Pixel, len(REFERENCE)) or_return
		copy(upload_buffer, REFERENCE[:])

		output = gfx.arena_alloc(results_memory, []Pixel, len(REFERENCE)) or_return

		semaphore := gfx.create_semaphore(.Cpu_Waitable) or_return

		command_buffer := gfx.begin_command_encoding(.Default) or_return
		gfx.copy_buffer_to_texture(command_buffer, raw_data(upload_buffer), texture, gfx.Texture_Region {
			layer_count	= 1,
			size		= { 2, 2, 1 },
		}) or_return
		gfx.barrier(command_buffer, { .Transfer }, { .Transfer }) or_return
		gfx.copy_texture_to_buffer(command_buffer, texture, gfx.Texture_Region {
			layer_count	= 1,
			size		= { 2, 2, 1 },
		}, raw_data(output)) or_return

		gfx.submit(.Default, { command_buffer }, { semaphore, 1 }) or_return

		gfx.wait_semaphore(semaphore, 1)

		return output, nil
	}

	results_memory := acquire_test_resources()

	output, res := test(&results_memory)
	check_result(t, res)
	test_agains_reference_bytes(t, REFERENCE[:], output)
}

@(test)
memory_transfers_with_textures :: proc(t: ^testing.T) {

	@(static, rodata)
	REFERENCE := [?]Pixel {
		{ 0, 0, 0, 255 }, { 255, 0, 0, 255 },
		{ 0, 255, 0, 255 }, { 0, 0, 255, 255 },
	}

	test :: proc(results_memory: ^gfx.Arena) -> (output: []Pixel, res: gfx.Result) {
		
		staging_memory: gfx.Arena
		gfx.create_arena(&staging_memory, .Staging, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(staging_memory)

		private_memory: gfx.Arena
		gfx.create_arena(&private_memory, .Private, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(private_memory)

		texture_desc := gfx.Texture_Descriptor {
			type		= .D2_Array,
			dimensions	= { 2, 2, 1 },
			format		= .RGBA8_Unorm,
			usage		= {},
		}
		texture_size, texture_align := gfx.size_align_of(texture_desc) or_return

		texture_1_buffer := gfx.arena_alloc(&private_memory, texture_size, texture_align) or_return
		texture_1 := gfx.create_texture(texture_1_buffer, texture_desc) or_return
		defer gfx.destroy_texture(texture_1)

		texture_2_buffer := gfx.arena_alloc(&private_memory, texture_size, texture_align) or_return
		texture_2 := gfx.create_texture(texture_2_buffer, texture_desc) or_return
		defer gfx.destroy_texture(texture_2)

		upload_buffer := gfx.arena_alloc(&staging_memory, []Pixel, len(REFERENCE)) or_return
		copy(upload_buffer, REFERENCE[:])

		output = gfx.arena_alloc(results_memory, []Pixel, len(REFERENCE)) or_return

		semaphore := gfx.create_semaphore(.Cpu_Waitable) or_return

		command_buffer := gfx.begin_command_encoding(.Default) or_return
		gfx.copy_buffer_to_texture(command_buffer, raw_data(upload_buffer), texture_1, gfx.Texture_Region {
			layer_count	= 1,
			size		= { 2, 2, 1 },
		}) or_return
		gfx.barrier(command_buffer, { .Transfer }, { .Transfer }) or_return
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
		) or_return
		gfx.barrier(command_buffer, { .Transfer }, { .Transfer })
		gfx.copy_texture_to_buffer(command_buffer, texture_2, gfx.Texture_Region {
			layer_count	= 1,
			size		= { 2, 2, 1 },
		}, raw_data(output)) or_return

		gfx.submit(.Default, { command_buffer }, { semaphore, 1 }) or_return

		gfx.wait_semaphore(semaphore, 1)

		return output, nil
	}

	results_memory := acquire_test_resources()

	output, res := test(&results_memory)
	check_result(t, res)
	test_agains_reference_bytes(t, REFERENCE[:], output)
}

@(test)
copy_texture_with_compute :: proc(t: ^testing.T) {

	@(static, rodata)
	REFERENCE := [?][4]u8 {
		{ 0, 0, 0, 255 }, { 255, 0, 0, 255 },
		{ 0, 255, 0, 255 }, { 0, 0, 255, 255 },
	}

	test :: proc(results_memory: ^gfx.Arena) -> (output: []Pixel, res: gfx.Result) {
		
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

		staging_memory: gfx.Arena
		gfx.create_arena(&staging_memory, .Default, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(staging_memory)

		private_memory: gfx.Arena
		gfx.create_arena(&private_memory, .Private, 64 * mem.Kilobyte) or_return
		defer gfx.destroy_arena(private_memory)

		pipeline := gfx.create_compute_pipeline(
			{
				bytecode	= TEXTURE_COPY_BYTECODE[:],
				entrypoint	= "texture_copy",
				group_size	= { 32, 32, 1 },
			},
		) or_return
		defer gfx.destroy_pipeline(pipeline)

		resource_set := gfx.create_resource_set() or_return
		defer gfx.destroy_resource_set(resource_set)

		texture_desc := gfx.Texture_Descriptor {
			type		= .D2_Array,
			dimensions	= { 2, 2, 1 },
			format		= .RGBA8_Unorm,
			usage		= { .Storage },
		}
		texture_size, texture_align := gfx.size_align_of(texture_desc) or_return
		texture_1_buffer := gfx.arena_alloc(&private_memory, texture_size, texture_align) or_return
		texture_1 := gfx.create_texture(texture_1_buffer, texture_desc) or_return
		defer gfx.destroy_texture(texture_1)

		texture_2_buffer := gfx.arena_alloc(&private_memory, texture_size, texture_align) or_return
		texture_2 := gfx.create_texture(texture_2_buffer, texture_desc) or_return
		defer gfx.destroy_texture(texture_2)

		texture_1_view := gfx.default_view_of(texture_1) or_return
		texture_2_view := gfx.default_view_of(texture_2) or_return
		gfx.set_storage_texture_set(
			resource_set,
			.D2,
			{ texture_1_view, texture_2_view },
		)

		upload := gfx.arena_alloc(&staging_memory, []Pixel, len(REFERENCE)) or_return
		copy(upload, REFERENCE[:])

		output = gfx.arena_alloc(results_memory, []Pixel, len(REFERENCE)) or_return

		semaphore := gfx.create_semaphore(.Cpu_Waitable) or_return

		command_buffer := gfx.begin_command_encoding(.Default) or_return

		gfx.copy_buffer_to_texture(command_buffer, raw_data(upload), texture_1, gfx.Texture_Region {
			layer_count	= 1,
			size		= { 2, 2, 1 },
		})
		gfx.barrier(command_buffer, { .Transfer }, { .Compute })
		gfx.use_resources(command_buffer, resource_set)

		arguments, _ := gfx.arena_alloc(&staging_memory, Texture_Copy_Arguments)
		arguments^ = Texture_Copy_Arguments {
			size		= { 2, 2 },
			texture_in	= 0,
			texture_out	= 1,
		}
		gfx.dispatch(
			command_buffer,
			pipeline,
			arguments,
			{ 1, 1, 1 },
		)

		gfx.barrier(command_buffer, { .Compute }, { .Transfer })
		gfx.copy_texture_to_buffer(command_buffer, texture_2, gfx.Texture_Region {
			layer_count	= 1,
			size		= { 2, 2, 1 },
		}, raw_data(output))

		submit_res := gfx.submit(.Default, { command_buffer }, { semaphore, 1 })
		assert(submit_res == nil)

		gfx.wait_semaphore(semaphore, 1)

		return output, nil
	}

	results_memory := acquire_test_resources()

	output, res := test(&results_memory)
	check_result(t, res)
	test_agains_reference_bytes(t, REFERENCE[:], output)
}

@(test)
clear_render_pass :: proc(t: ^testing.T) {

	FRAMEBUFFER_SIZE :: [2]int{ 4, 4 }
	CLEAR_COLOR :: [4]f32{ 1.0, 0.0, 0.0, 1.0 }
	CLEAR_COLOR_NORMALIZED :: [4]u8{ 255, 0, 0, 255 }

	reference :: proc() -> (pixels: []Pixel) {
		pixels = make([]Pixel, FRAMEBUFFER_SIZE.x * FRAMEBUFFER_SIZE.y, context.temp_allocator)

		for y in 0..<FRAMEBUFFER_SIZE.y do for x in 0..<FRAMEBUFFER_SIZE.x {
			pixels[y * FRAMEBUFFER_SIZE.x + x] = CLEAR_COLOR_NORMALIZED
		}

		return
	}

	test :: proc(results_memory: ^gfx.Arena) -> (output: []Pixel, res: gfx.Result) {

		private_memory: gfx.Arena
		gfx.create_arena(&private_memory, .Private, 4096) or_return
		defer gfx.destroy_arena(private_memory)

		semaphore := gfx.create_semaphore(.Cpu_Waitable) or_return

		output = gfx.arena_alloc(results_memory, []Pixel, FRAMEBUFFER_SIZE.x * FRAMEBUFFER_SIZE.y) or_return

		framebuffer_descriptor := gfx.Texture_Descriptor {
			type		= .D2_Array,
			format		= .RGBA8_Unorm,
			usage		= { .Color_Attachment },
			dimensions	= { **FRAMEBUFFER_SIZE, 1 },
		}
		framebuffer_size, framebuffer_align := gfx.size_align_of(framebuffer_descriptor) or_return
		framebuffer_memory := gfx.arena_alloc(&private_memory, framebuffer_size, framebuffer_align) or_return

		framebuffer := gfx.create_texture(framebuffer_memory, framebuffer_descriptor) or_return
		framebuffer_view := gfx.default_view_of(framebuffer) or_return

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
		command_buffer := gfx.begin_command_encoding(.Default) or_return
		gfx.begin_render_pass(command_buffer, render_pass_descriptor) or_return
		gfx.end_render_pass(command_buffer) or_return

		gfx.barrier(command_buffer, { .Color_Attachment }, { .Transfer }) or_return
		gfx.copy_texture_to_buffer(command_buffer, framebuffer, gfx.Texture_Region {
			layer_count = 1,
			size = { **FRAMEBUFFER_SIZE, 1 },
		}, raw_data(output)) or_return

		gfx.submit(.Default, { command_buffer }, { semaphore, 1 }) or_return

		gfx.wait_semaphore(semaphore, 1)

		return
	}

	results_memory := acquire_test_resources()
	reference_pixels := reference()

	output, res := test(&results_memory)
	check_result(t, res)
	test_agains_reference_bytes(t, reference_pixels, output)
}

@(test)
generic_compute_test :: proc(t: ^testing.T) {

	ARRAY_LENGTH :: 4096

	reference :: proc() -> (values: []f32) {
		values = make([]f32, ARRAY_LENGTH, context.temp_allocator)

		for &value, i in values {
			a	:= cast(f32)i
			b	:= cast(f32)i * 4
			half	:= cast(f32)0.5

			value	= a + b * half
		}

		return
	}

	test :: proc(results_memory: ^gfx.Arena) -> (output: []f32, res: gfx.Result) {

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
		add_pipeline := gfx.create_compute_pipeline({
			bytecode	= ADD_BYTECODE[:],
			entrypoint	= "add",
			constants	= {
				{ type = .F32, value = &half },
			},
			group_size = { 128, 1, 1 },
		}) or_return
		defer gfx.destroy_pipeline(add_pipeline)

		semaphore := gfx.create_semaphore(.Cpu_Waitable) or_return
		defer gfx.destroy_semaphore(semaphore)

		default_memory: gfx.Arena
		gfx.create_arena(&default_memory, .Default, 64 * mem.Kilobyte * 3) or_return
		defer gfx.destroy_arena(default_memory)

		in_a := gfx.arena_alloc(&default_memory, []f32, ARRAY_LENGTH) or_return
		in_b := gfx.arena_alloc(&default_memory, []f32, ARRAY_LENGTH) or_return
		output = gfx.arena_alloc(results_memory, []f32, ARRAY_LENGTH) or_return

		for i := 0; i < ARRAY_LENGTH; i += 1 {
			in_a[i] = cast(f32)i
			in_b[i] = cast(f32)i * 4
		}

		gpu_a := gfx.gpu_address_of(raw_data(in_a)) or_return
		gpu_b := gfx.gpu_address_of(raw_data(in_b)) or_return
		gpu_out := gfx.gpu_address_of(raw_data(output)) or_return

		command_buffer := gfx.begin_command_encoding(.Default) or_return
		arguments := gfx.arena_alloc(&default_memory, Parameters) or_return
		arguments^ = Parameters {
			in_a	= gpu_a,
			in_b	= gpu_b,
			out	= gpu_out,
		}
		gfx.dispatch(command_buffer, add_pipeline, arguments, { ARRAY_LENGTH / 128, 1, 1 }) or_return
		gfx.submit(.Default, {command_buffer}, {semaphore, 1}) or_return

		gfx.wait_semaphore(semaphore, 1)

		return
	}

	results_memory := acquire_test_resources()
	reference_values := reference()

	output, res := test(&results_memory)
	check_result(t, res)
	test_agains_reference_bytes(t, reference_values, output)
}

@(test)
draw_triangle :: proc(t: ^testing.T) {

	FRAMEBUFFER_SIZE :: [2]int{ 640, 480 }

	REFERENCE_PATH :: "./images/triangle.png"

	test :: proc(results_memory: ^gfx.Arena) -> (output: []Pixel, res: gfx.Result) {
		
		when gfx.TARGET_API == .Vulkan {
			TRIANGLE_BYTECODE := #load("./shaders/triangle.spv")
		} else when gfx.TARGET_API == .Metal_3 {
			TRIANGLE_BYTECODE := #load("./shaders/triangle.metallib")
		}

		Vertex :: struct #packed {
			position:	[3]f32,
			color:		[3]f32,
		}
		VERTICES := [?]Vertex {
			{ { -0.5, -0.5, 1.0 }, { 1.0, 0.0, 0.0 } },
			{ {  0.5, -0.5, 1.0 }, { 0.0, 1.0, 0.0 } },
			{ {  0.0,  0.5, 1.0 }, { 0.0, 0.0, 1.0 } },
		}

		Parameters :: struct #packed {
			vertices:	uintptr,
		}

		default_memory: gfx.Arena
		gfx.create_arena(&default_memory, .Default, 16 * mem.Megabyte) or_return
		defer gfx.destroy_arena(default_memory)

		private_memory: gfx.Arena
		gfx.create_arena(&private_memory, .Private, 16 * mem.Megabyte) or_return
		defer gfx.destroy_arena(private_memory)

		vertices := gfx.arena_alloc(&default_memory, []Vertex, len(VERTICES)) or_return
		copy(vertices, VERTICES[:])
		gpu_vertices := gfx.gpu_address_of(raw_data(vertices)) or_return

		output = gfx.arena_alloc(results_memory, []Pixel, FRAMEBUFFER_SIZE.x * FRAMEBUFFER_SIZE.y) or_return

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
			sample_count	= 1,
			color_formats	= { .RGBA8_Unorm },
		}
		pipeline := gfx.create_render_pipeline(pipeline_descriptor) or_return
		defer gfx.destroy_pipeline(pipeline)

		framebuffer_descriptor := gfx.Texture_Descriptor {
			type		= .D2_Array,
			format		= .RGBA8_Unorm,
			dimensions	= { **FRAMEBUFFER_SIZE, 1 },
			usage		= { .Color_Attachment },
		}
		framebuffer_size, framebuffer_align := gfx.size_align_of(framebuffer_descriptor) or_return
		framebuffer_memory := gfx.arena_alloc(&private_memory, framebuffer_size, framebuffer_align) or_return

		framebuffer := gfx.create_texture(framebuffer_memory, framebuffer_descriptor) or_return
		defer gfx.destroy_texture(framebuffer)
		framebuffer_view := gfx.default_view_of(framebuffer) or_return

		semaphore := gfx.create_semaphore(.Cpu_Waitable) or_return
		defer gfx.destroy_semaphore(semaphore)

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
		command_buffer := gfx.begin_command_encoding(.Default) or_return
		gfx.begin_render_pass(command_buffer, render_pass_descriptor) or_return
			arguments := gfx.arena_alloc(&default_memory, Parameters) or_return
			arguments^ = Parameters {
				vertices = gpu_vertices,
			}
			gfx.draw(command_buffer, pipeline, arguments, 3) or_return
		gfx.end_render_pass(command_buffer) or_return

		gfx.barrier(command_buffer, { .Color_Attachment }, { .Transfer }) or_return
		gfx.copy_texture_to_buffer(command_buffer, framebuffer, gfx.Texture_Region {
			layer_count = 1,
			size = { **FRAMEBUFFER_SIZE, 1 },
		}, raw_data(output)) or_return

		gfx.submit(.Default, { command_buffer }, { semaphore, 1 }) or_return
		gfx.wait_semaphore(semaphore, 1)

		return
	}

	results_memory := acquire_test_resources()

	output, res := test(&results_memory)
	check_result(t, res)
	test_against_reference_image(t, REFERENCE_PATH, output)
}

@(test)
draw_quad :: proc(t: ^testing.T) {

	FRAMEBUFFER_SIZE :: [2]int{ 640, 480 }

	REFERENCE_PATH :: "./images/quad.png"

	test :: proc(results_memory: ^gfx.Arena) -> (output: []Pixel, res: gfx.Result) {
		
		when gfx.TARGET_API == .Vulkan {
			TRIANGLE_BYTECODE := #load("./shaders/triangle.spv")
		} else when gfx.TARGET_API == .Metal_3 {
			TRIANGLE_BYTECODE := #load("./shaders/triangle.metallib")
		}

		Vertex :: struct #packed {
			position:	[3]f32,
			color:		[3]f32,
		}
		VERTICES := [?]Vertex {
			{ { -0.5, -0.5, 1.0 }, { 1.0, 0.0, 0.0 } },
			{ {  0.5, -0.5, 1.0 }, { 0.0, 1.0, 0.0 } },
			{ {  0.5,  0.5, 1.0 }, { 0.0, 0.0, 1.0 } },
			{ { -0.5,  0.5, 1.0 }, { 1.0, 1.0, 0.0 } },
		}

		INDICES := [?]u16 {
			0, 1, 2,
			2, 3, 0,
		}

		Parameters :: struct #packed {
			vertices:	uintptr,
		}

		default_memory: gfx.Arena
		gfx.create_arena(&default_memory, .Default, 16 * mem.Megabyte) or_return
		defer gfx.destroy_arena(default_memory)

		private_memory: gfx.Arena
		gfx.create_arena(&private_memory, .Private, 16 * mem.Megabyte) or_return
		defer gfx.destroy_arena(private_memory)

		vertices := gfx.arena_alloc(&default_memory, []Vertex, len(VERTICES)) or_return
		copy(vertices, VERTICES[:])
		gpu_vertices := gfx.gpu_address_of(raw_data(vertices)) or_return

		indices := gfx.arena_alloc(&default_memory, []u16, len(INDICES)) or_return
		copy(indices, INDICES[:])

		output = gfx.arena_alloc(results_memory, []Pixel, FRAMEBUFFER_SIZE.x * FRAMEBUFFER_SIZE.y) or_return

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
			sample_count	= 1,
			color_formats	= { .RGBA8_Unorm },
		}
		pipeline := gfx.create_render_pipeline(pipeline_descriptor) or_return
		defer gfx.destroy_pipeline(pipeline)

		framebuffer_descriptor := gfx.Texture_Descriptor {
			type		= .D2_Array,
			format		= .RGBA8_Unorm,
			dimensions	= { **FRAMEBUFFER_SIZE, 1 },
			usage		= { .Color_Attachment },
		}
		framebuffer_size, framebuffer_align := gfx.size_align_of(framebuffer_descriptor) or_return
		framebuffer_memory := gfx.arena_alloc(&private_memory, framebuffer_size, framebuffer_align) or_return

		framebuffer := gfx.create_texture(framebuffer_memory, framebuffer_descriptor) or_return
		defer gfx.destroy_texture(framebuffer)
		framebuffer_view := gfx.default_view_of(framebuffer) or_return

		semaphore := gfx.create_semaphore(.Cpu_Waitable) or_return
		defer gfx.destroy_semaphore(semaphore)

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
		command_buffer := gfx.begin_command_encoding(.Default) or_return
		gfx.begin_render_pass(command_buffer, render_pass_descriptor) or_return
			arguments := gfx.arena_alloc(&default_memory, Parameters) or_return
			arguments^ = Parameters {
				vertices = gpu_vertices,
			}
			gfx.draw_indexed(command_buffer, pipeline, arguments, raw_data(indices), 6) or_return
		gfx.end_render_pass(command_buffer) or_return

		gfx.barrier(command_buffer, { .Color_Attachment }, { .Transfer }) or_return
		gfx.copy_texture_to_buffer(command_buffer, framebuffer, gfx.Texture_Region {
			layer_count = 1,
			size = { **FRAMEBUFFER_SIZE, 1 },
		}, raw_data(output)) or_return

		gfx.submit(.Default, { command_buffer }, { semaphore, 1 }) or_return
		gfx.wait_semaphore(semaphore, 1)

		return
	}

	results_memory := acquire_test_resources()

	output, res := test(&results_memory)
	check_result(t, res)
	test_against_reference_image(t, REFERENCE_PATH, output)
}

