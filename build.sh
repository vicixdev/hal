#!/bin/sh

set -e

odin build src -collection:shared=shared -out:build/out -debug -strict-style -vet -warnings-as-errors

# ./tools/slang/bin/slang ./shaders/basic.slang -target metal -o ./build/basic.metal
