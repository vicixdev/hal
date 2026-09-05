#!/bin/sh

target_api="$1"

case "$target_api" in
	Vulkan)
		slangc ./gfx/tests/add.slang -profile glsl_450 -target spirv -o ./gfx/tests/shaders/basic.spv -fvk-use-entrypoint-name
		slangc ./gfx/tests/texture_copy.slang -profile glsl_450 -target spirv -o ./gfx/tests/shaders/texture_copy.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
		slangc ./gfx/tests/triangle.slang -profile glsl_450 -target spirv -o ./gfx/tests/shaders/triangle.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
		slangc ./gfx/tests/triangle_with_transform.slang -profile glsl_450 -target spirv -o ./gfx/tests/shaders/triangle_with_transform.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
		odin test -debug -vet -out:tests -define:ODIN_TEST_THREADS=4 -define:GFX_TARGET_API=Vulkan -keep-executable ./gfx/tests
	;;
	Metal_3)
		slangc ./gfx/tests/add.slang -target metallib -o ./gfx/tests/shaders/basic.metallib -fvk-use-entrypoint-name
		slangc ./gfx/tests/texture_copy.slang -target metallib -o ./gfx/tests/shaders/texture_copy.metallib -fvk-use-entrypoint-name -DGFX_METAL=1
		slangc ./gfx/tests/triangle.slang -target metallib -o ./gfx/tests/shaders/triangle.metallib -fvk-use-entrypoint-name -DGFX_METAL=1
		slangc ./gfx/tests/triangle_with_transform.slang -target metallib -o ./gfx/tests/shaders/triangle_with_transform.metallib -fvk-use-entrypoint-name -DGFX_METAL=1
		odin test -debug -vet -out:tests -define:ODIN_TEST_THREADS=4 -define:GFX_TARGET_API=Metal_3 -keep-executable ./gfx/tests
	;;
	*)
		echo "Invalid target api (expected Vulkan or Metal_3)".
		exit -1
	;;
esac

