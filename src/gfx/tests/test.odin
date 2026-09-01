package vicixdev_gfx_tests

import "base:runtime"
import "core:mem"
import "core:image"
import "core:testing"
import "core:fmt"
import "core:slice"
import "core:log"
@(require) import "core:image/png"
import gfx ".."

Pixel :: [4]u8

Reference_Image_Test_Parameters :: struct {
	logged_error_count:	int,
	max_absolute_error:	f32,
	max_relative_error:	f32,
}

Reference_Bytes_Test_Parameters :: struct {
	logged_error_count:	int,
}

@(deferred_out=_release_test_resources)
acquire_test_resources :: proc() -> (results_memory: gfx.Arena) {
	memory_res := gfx.create_arena(&results_memory, .Readback, 16 * mem.Megabyte)
	assert(memory_res == nil)

	return
}

_release_test_resources :: proc(results_memory: gfx.Arena) {
	gfx.destroy_arena(results_memory)
}

test_against_reference_image :: proc(
	t:			^testing.T,
	$REFERENCE_PATH:	string,
	pixels:			[]Pixel,
	params :=		Reference_Image_Test_Parameters{},
	location :=		#caller_location,
) {

	REFERENCE_BYTES :: #load(REFERENCE_PATH)

	params := params
	if params.logged_error_count == 0 {
		params.logged_error_count = 10
	}

	reference, reference_res := image.load_from_bytes(REFERENCE_BYTES)
	ensure(reference_res == nil, "Could not parse image " + REFERENCE_PATH + ".")
	defer image.destroy(reference)

	assert(reference.channels == 4, "The testing framework only supports images with 4 channels.")
	assert(reference.depth == 8, "The testing framework only supports images with 8 bit channels.")
	reference_pixels := slice.reinterpret([][4]u8, reference.pixels.buf[:])

	ensure(len(pixels) == len(reference_pixels), "The provided pixel count does not match with the reference.")

	matches := true
	errors: int
	for reference_pixel, i in reference_pixels {
		pixel := pixels[i]
		if check_pixels(reference_pixel, pixel, params) {
			continue
		}

		matches = false
		if errors < params.logged_error_count {
			log.errorf(
				"Pixel %v (index %d) does not conform with reference pixel %v",
				pixel,
				i,
				reference_pixel,
				location=location,
			)
		}

		errors += 1
	}

	if !matches {
		message := fmt.tprintf(
			"The provided pixels do not match with the reference ones at %s. Got %d unmatched pixels " +
			"(%f%%).",
			REFERENCE_PATH,
			errors,
			cast(f32)errors / cast(f32)len(pixels),
		)
		log.panic(message, location)
	}
}

test_agains_reference_bytes :: proc(
	t:		^testing.T,
	reference:	[]$T,
	bytes:		[]T,
	params :=	Reference_Bytes_Test_Parameters{},
	location :=	#caller_location,
) {

	ensure(len(bytes) == len(reference), "The provided bytes length does not match with the reference.")

	params := params
	if params.logged_error_count == 0 {
		params.logged_error_count = 10
	}

	matches := true
	errors: int
	for reference_byte, i in reference {
		test_byte := bytes[i]
		if test_byte == reference_byte {
			continue
		}

		matches = false
		if errors < params.logged_error_count {
			testing.expect_value(t, test_byte, reference_byte, location)
		}

		errors += 1
	}

	if !matches {
		message := fmt.tprintf(
			"The provided bytes do not match with the reference ones. Got %d unmatched pixels (%f%%).",
			errors,
			cast(f32)errors / cast(f32)len(reference),
		)
		log.panic(message, location)
	}
}

check_result :: proc(t: ^testing.T, res: gfx.Result) {
	testing.expect_value(t, res, nil)
}

check_pixels :: proc(a: Pixel, b: Pixel, parameters: Reference_Image_Test_Parameters) -> bool {
	error := abs(cast(int)a.r - cast(int)b.r)
	error += abs(cast(int)a.g - cast(int)b.g)
	error += abs(cast(int)a.b - cast(int)b.b)
	error += abs(cast(int)a.a - cast(int)b.a)

	if cast(f32)error > parameters.max_absolute_error {
		return false
	}

	error /= 4
	if cast(f32)error > parameters.max_relative_error {
		return false
	}

	return true
}

@(init, private)
init_gfx :: proc "contextless" () {
	context = runtime.default_context()
	context.logger = log.create_console_logger(allocator=context.temp_allocator)

	init_res := gfx.init()
	assert(init_res == nil, "Could not initialize gfx.")

	devices, devices_res := gfx.enumerate_devices()
	assert(devices_res == nil, "Could not enumerate devices.")
	assert(len(devices) > 0, "No suitable devices found.")
	log.debugf("Available devices for testing: %#v", devices)

	device := devices[0].id
	when gfx.TARGET_API == .Vulkan {
		for device_info in devices {
			// NOTE: MoltenVK has issues with the deallocation of resources from multiple threads.
			//	Prefer using KosmicKrisp since it does not have this problem.
			if device_info.driver == "KosmicKrisp" {
				device = device_info.id
				break
			}
		}
	}
	log.debugf("Testing using device with Device_ID %d (%s - %s).", device, devices[device].name, devices[device].driver)

	device_res := gfx.select_device(device)
	assert(device_res == nil, "Could not select a device.")
}

@(fini, private)
fini_gfx :: proc "contextless" () {
	context = runtime.default_context()
	gfx.fini()
}

