#!/bin/sh

set -e

target="$1"

case "$target" in
	Vulkan)
		odin build src -show-timings -collection:root=.. -out:build/out -debug -strict-style -warnings-as-errors -define:GFX_TARGET_API=Vulkan
	;;
	Metal_3)
		odin build src -show-timings -collection:root=.. -out:build/out -debug -strict-style -warnings-as-errors -define:GFX_TARGET_API=Metal_3
	;;
	Shaders)
		slangc ./shaders/basic.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/basic.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
		slangc ./shaders/texture_basic.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/texture_basic.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
		slangc ./shaders/skybox.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/skybox.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
		slangc ./shaders/ui_render.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/ui_render.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
		slangc ./shaders/blit.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/blit.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1

		if [[ "$(uname)" == "Darwin" ]]; then
			slangc ./shaders/basic.slang -profile glsl_450 -target metallib	-capability METAL_3_0 -capability GL_EXT_buffer_reference -o ./build/basic.metallib -fvk-use-entrypoint-name -DGFX_METAL=1 -Xmetal -frecord-sources -Xmetal -gline-tables-only
			slangc ./shaders/texture_basic.slang -profile glsl_450 -target metallib	-capability METAL_3_0 -capability GL_EXT_buffer_reference -o ./build/texture_basic.metallib -fvk-use-entrypoint-name -DGFX_METAL=1 -Xmetal -frecord-sources -Xmetal -gline-tables-only
			slangc ./shaders/skybox.slang -profile glsl_450 -target metallib	-capability METAL_3_0 -capability GL_EXT_buffer_reference -o ./build/skybox.metallib -fvk-use-entrypoint-name -DGFX_METAL=1 -Xmetal -frecord-sources -Xmetal -gline-tables-only
			slangc ./shaders/ui_render.slang -profile glsl_450 -target metallib	-capability METAL_3_0 -capability GL_EXT_buffer_reference -o ./build/ui_render.metallib -fvk-use-entrypoint-name -DGFX_METAL=1 -Xmetal -frecord-sources -Xmetal -gline-tables-only
			slangc ./shaders/blit.slang -profile glsl_450 -target metallib	-capability METAL_3_0 -capability GL_EXT_buffer_reference -o ./build/blit.metallib -fvk-use-entrypoint-name -DGFX_METAL=1 -Xmetal -frecord-sources -Xmetal -gline-tables-only
		fi
	;;
	*)
		echo "Invalid target (expected Vulkan, Metal_3 or Shaders)".
		exit -1
	;;
esac

