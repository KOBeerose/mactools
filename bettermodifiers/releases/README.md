# BetterModifiers release artifacts

This folder holds **timestamped snapshot installers**. Each file is unique and is never overwritten by later builds.

## Create a snapshot (frozen build)

```bash
cd mactools/bettermodifiers
chmod +x scripts/build-snapshot-dmg.sh scripts/build-app-bundle.sh
./scripts/build-snapshot-dmg.sh
```

Output example:

```text
releases/BetterModifiers-1.0.0-snapshot-20260520-143052.dmg
```

Double-click the `.dmg`, drag the app onto **Applications**. The installed app has a unique name (includes the timestamp) and bundle id, so day-to-day dev installs via `build-install-local.sh` (`BetterModifiers.app`) do not replace it.

## Dev installs (overwrites `~/Applications/BetterModifiers.app`)

```bash
./scripts/build-install-local.sh
```

Use snapshots when you want a known-good build to keep while continuing to hack on main.
