# GFX
`vicixdev_gfx` is an opinionated Hardware Abstraction Layer (HAL) compatible with Metal 3+Residency Sets and
Vulkan 1.2+VK_KHR_dynamic_rendering. It exposes in a cross-platform and ergonomic manner modern GPU features,
like bindless rendering, persistently mapped resources and more.

It is heavily inspired by the [No Graphics API](https://www.sebastianaaltonen.com/blog/no-graphics-api)
blogpost by [Sebastian Altonen](https://www.sebastianaaltonen.com).

## PLATFORM SUPPORT
`vicixdev_gfx` is expected to run on the following platforms (assuming latest drivers):

| OS | Requirements |
|-------|--------|
| Windows | NVIDIA GTX 9xx series, AMD Radeon RX 4xx series, Intel HD Graphics 530 |
| Linux | NVIDIA GTX 9xx series, AMD Radeon HD 7xxx series, Intel HD Graphics 5500 |
| macOS | Apple Silicon (any M-series or A-series chip), running MacOS 15 or later |
