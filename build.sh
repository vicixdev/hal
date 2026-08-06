#!/bin/sh

set -e

target_api="$1"

case "$target_api" in
	Vulkan)
		odin build src -collection:shared=shared -out:build/out -debug -strict-style -vet -warnings-as-errors -define:GFX_TARGET_API=Vulkan

		slangc ./shaders/basic.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/basic.spv -fvk-use-entrypoint-name
		slangc ./shaders/basic.slang -profile glsl_450 -target glsl -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/basic.glsl -entry computeMain
		slangc ./shaders/basic.slang -profile glsl_450 -target metallib	-capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/basic.metallib -fvk-use-entrypoint-name
	;;
	Metal_3)
		odin build src -collection:shared=shared -out:build/out -debug -strict-style -vet -warnings-as-errors -define:GFX_TARGET_API=Metal_3

		slangc ./shaders/basic.slang -profile glsl_450 -target metal	-capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/basic.metal -fvk-use-entrypoint-name
		slangc ./shaders/basic.slang -profile glsl_450 -target metallib	-capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/basic.metallib -fvk-use-entrypoint-name
	;;
	*)
		echo "Invalid target api (expected Vulkan or Metal_3)".
		exit -1
	;;
esac

