# GFX
`vicixdev_gfx` is an opinionated Hardware Abstraction Layer (HAL) compatible with Metal 3+Residency Sets and
Vulkan 1.2+VK_KHR_dynamic_rendering. It provides a cross-platform and ergonomic API that exposes modern GPU features,
such as bindless rendering, persistently mapped resources and more.

# PLATFORM SUPPORT
`vicixdev_gfx` is expected to run on the following platforms (assuming latest drivers):
	- macOS:
		Apple silicon (any M-series or A-series chip) running MacOS 15 or later.
	- Windows:
		NVIDIA GTX 9xx series, AMD Radeon RX 4xx series and Intel HD Graphics 530
	- Linux:
		NVIDIA GTX 9xx series, AMD Radeon HD 7xxx series and Intel HD Graphics 5500
