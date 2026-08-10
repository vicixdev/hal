@echo off

slangc ./src/gfx/tests/add.slang -profile glsl_450 -target spirv -o ./src/gfx/tests/shaders/basic.spv -fvk-use-entrypoint-name
odin test -collection:shared=shared -debug -out:build/tests.exe -define:ODIN_TEST_THREADS=1 src/gfx/tests 


