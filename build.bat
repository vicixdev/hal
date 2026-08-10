@echo off

odin build src -collection:shared=shared -out:build/out.exe -debug -strict-style -vet -warnings-as-errors -define:GFX_TARGET_API=Vulkan
slangc ./shaders/basic.slang -profile glsl_450 -target spirv -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/basic.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
slangc ./shaders/basic.slang -profile glsl_450 -target glsl -capability glsl_spirv -capability GL_EXT_buffer_reference -o ./build/basic.glsl -entry computeMain -DGFX_VULKAN=1

