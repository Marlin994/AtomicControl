# Operation Modes

## NORMAL

NORMAL is the standard mode.

It tries to produce only slightly more steam than the turbines actually need:

```text
target = turbine demand × 1.03
```

The active reactor controller then adjusts the rods to match that target.

## CYANITE

CYANITE mode burns fuel intentionally:

- active reactors: rods 0%
- turbines: still regulated around 1800 RPM
- energy storage full: turbine generators disengage, rotor stays ready via idle flow
