# Submodule Reference

## Remote setup per submodule

Each submodule that is a fork should have:

| Remote     | Points to                        | Purpose                     |
|------------|----------------------------------|-----------------------------|
| `origin`   | `KobeTools/<repo>`               | Your fork — push/pull here  |
| `upstream` | `<original-author>/<repo>`       | Pull new upstream changes   |

Verify with `git remote -v` inside the submodule directory.

## Current submodules

| Folder     | Fork (origin)                           | Upstream                            |
|------------|------------------------------------------|--------------------------------------|
| `spaceman` | `https://github.com/KobeTools/Spaceman` | `https://github.com/ruittenb/Spaceman` |

## Cloning mactools fresh

```bash
git clone --recurse-submodules https://github.com/KOBeerose/mactools.git
```

If you already cloned without submodules:

```bash
git submodule update --init
```

## Adding a new fork submodule

The user will provide the **upstream (original) URL**. Derive the fork URL by replacing the owner with `KobeTools` — the repo name stays the same after a fork.

Example:
- Upstream: `https://github.com/ruittenb/Spaceman`
- Fork (derived): `https://github.com/KobeTools/Spaceman`

Assume the fork already exists on GitHub under the KobeTools org. Do not run `gh repo fork`.

```bash
# 1. Add as submodule using the fork URL
git submodule add https://github.com/KobeTools/REPO.git <folder-name>

# 2. Inside the submodule, add upstream remote
cd <folder-name>
git remote add upstream https://github.com/UPSTREAM_OWNER/REPO.git
git fetch origin
git branch -u origin/main

# 3. Commit submodule reference
cd ..
git add .gitmodules <folder-name>
git commit -m "add <folder-name> submodule"
```
