@echo off

odin build src -linker:msvc -o:none -show-timings -collection:root=.. -collection:shared=shared -out:build\out.exe -debug -strict-style -warnings-as-errors -define:GFX_TARGET_API=Vulkan
slangc shaders\basic.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o build\basic.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
slangc shaders\texture_basic.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o build\texture_basic.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
slangc shaders\skybox.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o build\skybox.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
slangc shaders\blit.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o build\blit.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
slangc shaders\ui.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o build\ui.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1

