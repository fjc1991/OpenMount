# Contributing to OpenMount

Thanks for helping. A few ground rules keep the project useful and legally clean.

## Ground rules

- **No vendor material.** Don't commit be quiet! binaries, decompiled code, firmware, images or
  fonts. Describe protocol findings in your own words in `docs/PROTOCOL.md`.
- **No firmware flashing.** OpenMount deliberately blocks the firmware-update feature (`0x02`)
  and the serial-number commands. PRs that add them won't be merged.
- **Test on hardware.** For protocol changes, include the bytes you sent and received. Add a unit
  test in `Tests/OpenMountKitTests` that uses them.

## Development

```sh
swift test                  # unit tests (no keyboard needed)
swift build && .build/debug/omctl -v info
./scripts/build-app.sh      # dist/OpenMount.app
./scripts/make-icns.sh      # regenerate the icon after editing scripts/make-icon.swift
```

`omctl -v` prints every frame sent and received, which is the quickest way to investigate the
keyboard.

## Wanted

- **Language layouts.** Adding one takes about 15 minutes; see [Layouts/README.md](Layouts/README.md).

- Layout drawings for the Light Mount TKL and Dark Mount
- The meaning of the optional 3 bytes at the end of a lighting layer config
- Localised legends (DE/FR/UK)
