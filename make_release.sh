#!/bin/sh

set -e

cd ./gfx; ./build_shaders.sh Metal_3 Release; ./build_shaders.sh Vulkan Release; cd ..
find ./gfx -type f -name '.DS_Store' -delete

rm -f ./release.tar.gz
tar -zcvf release.tar.gz ./gfx

