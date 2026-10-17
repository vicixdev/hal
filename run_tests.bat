@echo off

slangc gfx\tests\add.slang -profile glsl_450 -target spirv -o gfx\tests\shaders\basic.spv -fvk-use-entrypoint-name
slangc gfx\tests\texture_copy.slang -profile glsl_450 -target spirv -o gfx\tests\shaders\texture_copy.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
slangc gfx\tests\triangle.slang -profile glsl_450 -target spirv -o gfx\tests\shaders\triangle.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
slangc gfx\tests\triangle_with_transform.slang -profile glsl_450 -target spirv -o gfx\tests\shaders\triangle_with_transform.spv -fvk-use-entrypoint-name -DGFX_VULKAN=1
odin test -debug -vet -out:tests.exe -define:ODIN_TEST_THREADS=4 -define:GFX_TARGET_API=Vulkan -keep-executable gfx\tests


