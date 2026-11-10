# TODO
- [ ] Implement indirect rendering via `Indirect_Command_Pools` and explicit encoding.
  - [ ] Support MultiDrawIndirect (using ICB under metal)
  - [X] Metal
  - [ ] Vulkan
- [ ] Improve validation
- [ ] Move ALL validation code to `_vl_*` procedures
- [ ] Optimize surface resizing (it lags...)
- [ ] Reorganize device global variables
- [ ] Procedures documentation
- [ ] Project documentation/handguide
- [ ] Migrate the deferred command emission logic to an immediate one.
  - [ ] Force `gfx::synchronize` to be at the beginning of the command buffer.
- [ ] LRU cache for pointer decoding
- [ ] VK: Analyse resource usage between barriers and change the resource layout accordingly
- [ ] M3: Migrate to non-resource-retaining command buffers

# MAYBE
- [ ] Move pointer decoding to the backends, to reduce the number of tree lookups.
