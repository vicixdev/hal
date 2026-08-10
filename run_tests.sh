#!/bin/sh

slangc ./src/gfx/tests/add.slang -profile glsl_450 -target metallib -o ./src/gfx/tests/shaders/basic.metallib -fvk-use-entrypoint-name
slangc ./src/gfx/tests/add.slang -profile glsl_450 -target spirv -o ./src/gfx/tests/shaders/basic.spv -fvk-use-entrypoint-name
odin test -collection:shared=shared -debug -out:build/tests -define:ODIN_TEST_THREADS=1 src/gfx/tests 

