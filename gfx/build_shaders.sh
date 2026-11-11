#!/bin/sh

set -e

target="$1"
opt_level="$2"

case "$target" in
	Metal_3)
		case "$opt_level" in
			Release)
				xcrun -sdk macosx metal -O3 -o ./m3_shaders.air -c ./m3_shaders.metal
			;;
			""|Debug)
				xcrun -sdk macosx metal -g -frecord-sources -o ./m3_shaders.air -c ./m3_shaders.metal
			;;
			*)
				echo "Invalid optimization target (expected Debug or Release)."
				exit -1
			;;
		esac

		xcrun -sdk macosx metallib ./m3_shaders.air -o ./m3_shaders.metallib
		rm ./m3_shaders.air
	;;
	Vulkan)
		case "$opt_level" in
			Release)
				slangc ./vk_shaders.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./vk_shaders.spv -fvk-use-entrypoint-name
			;;
			""|Debug)
				slangc ./vk_shaders.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./vk_shaders.spv -fvk-use-entrypoint-name -g2
			;;
			*)
				echo "Invalid optimization target (expected Debug or Release)."
				exit -1
			;;
		esac
	;;
	*)
		echo "Invalid target (expected Vulkan or Metal_3)."
		exit -1
	;;
esac
