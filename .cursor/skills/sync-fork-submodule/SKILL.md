---
name: sync-fork-submodule
description: Safely sync one or all fork-based git submodules with upstream, or fork and add a new submodule to mactools. Use when the user explicitly says "sync submodule", "sync all submodules", "fork and add submodule", or "update submodule" with a clear confirmation of intent. Do NOT trigger on casual mentions of updating or syncing — require explicit intent.
---

# Sync Fork Submodule

Guided workflow for pulling upstream changes into a forked submodule safely — with LLM review before merging.

## Before starting

Determine scope first:

- **Single submodule** — user said something like `"sync submodule: spaceman"`
- **All submodules** — user said `"sync all submodules"`; get the list by running `git submodule foreach --quiet 'echo $name'` from the mactools root

Then confirm before doing anything:

> "This will sync `<submodule(s)>` one by one — fetching upstream and walking you through a review for each before anything is merged. Should I proceed?"

Do not begin fetching or running any commands until the user confirms.

For "sync all", work through each submodule **sequentially** — complete the full workflow (steps 1–5) for one before starting the next. After each one, ask before moving to the next:

> "`<submodule>` done. Move on to `<next>`?"

## Steps

### 1. Verify upstream remote, then fetch

First confirm the `upstream` remote exists inside the submodule. If it is missing, add it using the URL from the Current submodules table in [submodule-guide.md](submodule-guide.md) — do not skip this step or proceed with a missing remote.

```bash
cd <submodule-dir>
git remote -v                        # confirm upstream is listed
# if missing:
git remote add upstream <upstream-url>
```

Then fetch:

```bash
git fetch upstream
```

If `git fetch upstream` fails, stop and report the error to the user. Do not proceed with stale or missing refs.

### 2. Review what changed

Each fork's branch is recorded in `.gitmodules` (Maccy uses `master`, not `main`). Read it first:

```bash
BRANCH=$(git config -f .gitmodules submodule.<submodule>.branch || echo main)
```

Then, from the mactools root, run the audit script. It groups the upstream diff into dependencies, permissions, build-time code, updater, network/telemetry, and agent/CI instruction files, and previews conflicts. It never merges:

```bash
scripts/audit-upstream.sh <submodule>
```

Dig deeper with the full diff where a section flags something:

```bash
git log HEAD..upstream/$BRANCH --oneline       # list new commits
git diff HEAD...upstream/$BRANCH -- .          # full diff since the merge base
```

Read the output carefully and check for:

**Security**        
- New or changed network calls (URLs, endpoints, analytics pings)
- New permissions requested (entitlements, Info.plist keys, privacy strings)
- New dependencies or package additions (Package.swift, Podfile, etc.)
- Telemetry, crash reporting, or tracking code

**Functionality / compatibility**
- Changes to files shared with or depended on by other mactools tools
- Build system changes (Xcode version bumps, Swift version, deployment target)
- Renamed or removed public APIs that mactools integrates with
- Makefile / script changes that affect the local build/install workflow

**Agent instructions**
- New or changed `CLAUDE.md`, `AGENTS.md`, `.claude/`, `.cursor/` or Copilot files. Merging them means upstream writes instructions that coding agents will follow inside the fork; read them in full

**General**
- Is this a routine maintenance/bugfix update or a large restructure?
- Are there any changes that seem unrelated to the project's purpose?

### 3. Decision gate — always stop here

Present a summary to the user. **Never proceed past this step automatically, regardless of what the diff looks like.**

```
Upstream has N new commits since last sync.

✅ Looks safe:
- [list routine changes]

⚠️ Needs your attention:
- [list anything that could affect functionality, security, or other tools]

❌ Recommend against merging:
- [list anything suspicious, tracking-related, or breaking]
```

Wait for the user to explicitly say to proceed. Do not merge, do not suggest "it looks fine to go ahead" — just present the summary and stop.

### 4. Merge and push to fork (only on explicit user instruction)

```bash
git merge upstream/$BRANCH
# resolve any conflicts if needed — see conflict resolution below
git push origin $BRANCH
```

### 5. Update the submodule pointer in mactools

```bash
cd ..    # back to mactools root
git add <submodule-dir>
git commit -m "sync <submodule>: pull upstream changes [date]"
git push
```

---

## Conflict resolution

**Priority order — in this sequence, top beats bottom:**

1. **Current working functionality** — nothing that works today should break
2. **Compatibility with other mactools tools** — changes must not break integrations or shared behavior across the repo
3. **Local customizations** — edits made to the fork for mactools-specific needs
4. **Upstream new features** — only adopt if the above three are fully preserved

When a conflict appears in a file:

- Your changes are `<<<<<<< HEAD`, upstream's are `>>>>>>> upstream/$BRANCH`
- Default to keeping your version; only take upstream's change if it does not threaten points 1 or 2 above
- If upstream's change is a new feature that conflicts with working functionality, **reject it** and note it for the user to decide separately
- If unsure, surface the conflict to the user rather than resolving autonomously

After resolving: `git add <file> && git merge --continue`

---

## Reference

- For submodule setup and day-to-day context, see [submodule-guide.md](submodule-guide.md)
