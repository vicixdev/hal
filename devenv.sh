#!/bin/sh

export VK_LAYER_PATH=/opt/homebrew/opt/vulkan-validationlayers/share/vulkan/explicit_layer.d
export VK_LAYER_PATH=$VK_LAYER_PATH:/opt/homebrew/opt/vulkan-profiles/share/vulkan/explicit_layer.d

export DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH:/opt/homebrew/opt/vulkan-validationlayers/lib
