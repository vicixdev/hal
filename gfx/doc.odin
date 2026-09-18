/*
`vicixdev_gfx` is an opinionated Hardware Abstraction Layer (HAL) compatible with Metal 3+Residency Sets and
Vulkan 1.2+VK_KHR_dynamic_rendering. It provides a cross-platform and ergonomic API that exposes modern GPU features,
like bindless rendering, persistently mapped resources and more.

# PLATFORM SUPPORT
`vicixdev_gfx` is expected to run on the following platforms (assuming latest drivers):
	- MacOS: Apple silicon (any M-series or A-series chip) running MacOS 15 or later.
		In the future, previous versions of MacOS might be considered.
	- Windows:
		NVIDIA GTX 9xx series, AMD Radeon RX 4xx series, Intel HD Graphics 530
	- Linux:
		NVIDIA GTX 9xx series, AMD Radeon HD 7xxx series, Intel HD Graphics 5500

## HARDWARE CATEGORIES
Hardware is categorized depending on its memory architecture:
	- Unified Memory Access (UMA):
		Present in integrated GPUs, the device memory is shared with the CPU.
	- Resizable bar enabled (ReBAR):
		Present in modern systems with dedicated GPUs, ReBAR allows huge amount of device memory to be
		accessed from the CPU.
	- Classic:
		Present in older systems with dedicated GPUs. Only a small amount of device memory is directly
		accessible from the CPU (typically 128/256 MB).

# INITIALIZATION & DEVICE SELECTION

# MEMORY MANAGEMENT
The library exposes different types of memory, each with a different use case:
	- Default:
		Default memory is both CPU and GPU accessible. It resides on the device. Default memory should be used
		for temporary or frame-local data.
	- Staging:
		Staging memory is both CPU and GPU accessible and is used to upload large amounts of data to the GPU
		Private memory. On UMA/ReBAR systems, Staging memory resides on-device, however on Classic systems
		it resides in system RAM.
	- Readback:
		Readback memory is both CPU and GPU accessible and is used to download large amounts of data from the
		GPU Private memory. On UMA/ReBAR systems, Readback memory resides on-device, however on Classic systems
		it resides in system RAM.
	- Private:
		Private memory is only GPU accessible. It is used to store gpu-only resources, thus resides on-device.

The library handles buffers and gpu allocations via addresses (instead of the commonly used objects/handles in the other
APIs). Every allocation is thus identified by its Gpu Virtual Address (GVA), by which the GPU is able to access the
contents.
> Fun fact: all modern GPUs support pointers from a hardware standpoint, however they are rarely used in practice due
> to the rendering APIs preferring to use opaque objects instead.

If the allocation references CPU accessible memory, a Cpu Mapped Virtual Address (CMVA) is also associated with the
allocation. The CMVA is persistent (doen't change, nor does it get invalidated) and can be used by the CPU to access the
contents.

### IMPLEMENTATION DETAILS & PERFORMANCE
Both Metal and Vulkan, from a CPU API standpoint, do not work with raw pointers; instead they require opaque objects,
even if the GVA and CMVA addresses are real and obtainable.

A lookup is thus required a lookup to convert the provided addresses to their relative opaque objects. Every address
lookup has logarithmic complexity over the total number of allocations (O(log(n))). The user should therefore allocate
as few buffers as possible. Always prefer allocating big buffer to suballocate (by using `Arena` or `scratch`, or
implementing custom allocators).

*/
package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

