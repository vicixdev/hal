# TODO
- [ ] Implement indirect rendering via `Indirect_Command_Pools` and explicit encoding.
  - [ ] Support MultiDrawIndirect (using ICB under metal)
- [ ] Improve validation
- [ ] Move ALL validation code to `_vl_*` procedures
- [ ] Reorganize device global variables
- [ ] Procedures documentation
- [ ] Project documentation/handguide
- [ ] LRU cache for pointer decoding
- [ ] VK: Analyse resource usage between barriers and change the resource layout accordingly

# MAYBE
- [ ] Move pointer decoding to the backends, to reduce the number of tree lookups.
