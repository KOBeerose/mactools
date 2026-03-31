---
name: sync-fork-submodule
description: Safely sync a fork-based git submodule with its upstream repo. Use when the user asks to update a submodule, sync with upstream, pull new changes into a fork, or update a tool inside mactools that is a GitHub fork.
---

# Sync Fork Submodule

Guided workflow for pulling upstream changes into a forked submodule safely — with LLM review before merging.

## Steps

### 1. Fetch upstream (do not merge yet)

```bash
cd <submodule-dir>
git fetch upstream
```

### 2. Review what changed

Generate a diff and changelog before touching anything:

```bash
git log HEAD..upstream/main --oneline          # list new commits
git diff HEAD upstream/main -- .               # full diff
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
git merge upstream/main
# resolve any conflicts if needed — see conflict resolution below
git push origin main
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

- Your changes are `<<<<<<< HEAD`, upstream's are `>>>>>>> upstream/main`
- Default to keeping your version; only take upstream's change if it does not threaten points 1 or 2 above
- If upstream's change is a new feature that conflicts with working functionality, **reject it** and note it for the user to decide separately
- If unsure, surface the conflict to the user rather than resolving autonomously

After resolving: `git add <file> && git merge --continue`

---

## Reference

- For submodule setup and day-to-day context, see [submodule-guide.md](submodule-guide.md)
