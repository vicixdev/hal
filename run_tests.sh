#!/bin/sh

target_api="$1"

if [ "$(uname)" = "Darwin" ]; then
	slangc ./src/gfx/tests/add.slang -profile glsl_450 -target metallib -o ./src/gfx/tests/shaders/basic.metallib -fvk-use-entrypoint-name
fi

slangc ./src/gfx/tests/add.slang -profile glsl_450 -target spirv -o ./src/gfx/tests/shaders/basic.spv -fvk-use-entrypoint-name

case "$target_api" in
	Vulkan)
		odin test -collection:shared=shared -debug -out:build/tests -define:ODIN_TEST_THREADS=8 -define:GFX_TARGET_API=Vulkan src/gfx/tests
	;;
	Metal_3)
		odin test -collection:shared=shared -debug -out:build/tests -define:ODIN_TEST_THREADS=8 -define:GFX_TARGET_API=Metal_3 src/gfx/tests
	;;
	*)
		echo "Invalid target api (expected Vulkan or Metal_3)".
		exit -1
	;;
esac

