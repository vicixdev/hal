/*
	vx_gfx is an opinionated hardware abstraction layer compatible with Metal 3+Residency Sets and
	Vulkan 1.2+VK_KHR_dynamic_rendering.

	# PLATFORM SUPPORT
	vx_gfx is expected to run on the following platforms (assuming latest drivers):
		- MacOS: Apple silicon (any M-series or A-series chip) running MacOS 15 or later.
			In the future, previous versions of MacOS might be considered.
		- Windows:
			NVIDIA GTX 9xx series, AMD Radeon RX 4xx series, Intel HD Graphics 530
		- Linux:
			NVIDIA GTX 9xx series, AMD Radeon HD 7xxx series, Intel HD Graphics 5500
	In general it should run on anything produces after 2015.

	# HARDWARE CATEGORIES
	Hardware is categorized depending on its memory architecture:
		- Unified Memory Access (UMA):
			Present in integrated GPUs, the device memory is shared with the CPU.
		- ReBAR-enabled:
			Present in modern systems with dedicated GPUs, ReBAR allows huge amount of device memory to be
			accessed from the CPU.
		- Classic:
			Present in older systems with dedicated GPUs. Only a small amount of device memory is directly
			accessible from the CPU.
*/
package gfx
