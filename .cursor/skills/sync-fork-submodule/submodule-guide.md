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

## Forking and adding a new submodule

Triggered by: "fork and add submodule: https://github.com/OriginalAuthor/SomeRepo"

The user provides the **upstream (original) URL**. The repo name stays the same after a fork — only the owner changes to `KobeTools`.

```bash
# 1. Fork upstream to KobeTools org via GitHub CLI
gh repo fork UPSTREAM_OWNER/REPO --org KobeTools --clone=false

# 2. Add as submodule using the fork URL
git submodule add https://github.com/KobeTools/REPO.git <folder-name>

# 3. Inside the submodule, add upstream remote and set tracking
cd <folder-name>
git remote add upstream https://github.com/UPSTREAM_OWNER/REPO.git
git fetch origin
git branch -u origin/main
cd ..

# 4. Add upstream URL to install-all.sh UPSTREAM_REMOTES array
#    Open scripts/install-all.sh and add:
#    [<folder-name>]="https://github.com/UPSTREAM_OWNER/REPO.git"

# 5. Add a row to the Current submodules table in this file

# 6. Commit everything
git add .gitmodules <folder-name> scripts/install-all.sh
git commit -m "add <folder-name> submodule"
```
