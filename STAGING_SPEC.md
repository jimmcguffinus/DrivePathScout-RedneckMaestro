# Move-RecoveredToRealnameMatches.ps1 — Staging Design Spec

**Status:** Implementation exists as `Move-RecoveredToRealnameMatches.ps1` v0.1.0-v0.1.4. **DryRun planning passed** Codex Sparky review. **Execute remains blocked** pending v0.1.4 OnlyRecoveredPath review and Jim approval.

**Version:** v0.1.4 (`-OnlyRecoveredPath` exact targeting; `-Execute` still not approved)

**Date:** 2026-07-03

---

## Purpose

Move approved **recovered-side** duplicate files into a staged workbench folder while leaving **real-named keeper** files untouched.

**Core rule:** MOVE only. No copy. No delete. No moving real-named keeper files. No execution unless Jim explicitly approves.

---

## Input report (explicit, stamped)

```text
C:\Users\jim\Desktop\DrivePathInventory\recovered_to_realname_matches_20260703-004335.csv
```

- **Rows:** 1,590 (may dedupe to fewer unique recovered sources)
- Script must **refuse to run** without explicit `-MatchCsvPath` — no auto-latest selection

---

## Destination

```text
I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\
```

Destination naming format (full filenames):

```text
{shortHash}.{recoveredFullName}.{realFullName}
```

Example:

```text
0E7A20EC.11-8-2012 11-02-29 AM.png.phx.suns.png
```

- `shortHash` = first 8 chars of SHA-256 (uppercase)
- `recoveredFullName` = `RecoveredFileName` from CSV
- `realFullName` = `RealNamedFileName` from CSV
- `SuggestedDuplicateName` from CSV is **audit reference only** — not the final destination name

---

## v0.1 approved source root policy

**Default approved recovered move source root (v0.1):**

```text
I:\recover\
```

**`I:\1tbrecover\` is NOT an approved move source in v0.1.**

`I:\1tbrecover\` also contains real keeper paths, including known keeper examples (e.g. `I:\1tbrecover\prevdrivestuff\Pictures\phx.suns.png`, `I:\1tbrecover\DisDain_PSTs\`).

Any `RecoveredPath` under `I:\1tbrecover\` must be marked:

- `NeedsJimReview`
- `InvalidSourceRoot`

…unless Jim later approves a more specific `I:\1tbrecover\` subtree for recovered-side moves.

**Denied source prefix (always):**

```text
I:\_RECOVERY_WORKBENCH\
```

Status: `AlreadyStaged`

---

## Proposed behavior

### Phase 0 — Startup guards

1. Refuse to run if `-MatchCsvPath` is missing or file does not exist.
2. No auto-latest report selection.
3. Validate `-ReportRoot` is normalized and **rejected if on `I:\`** (`C:\Users\jim\Desktop\DrivePathInventory`).
4. Validate `-DestinationRoot` is on `I:\` (same volume as v0.1 approved sources).
5. Load CSV; validate required columns: `Hash`, `RecoveredPath`, `RecoveredFileName`, `RealNamedPath`, `RealNamedFileName`, `SizeBytes`, `Extension` (+ `SuggestedDuplicateName` for audit).

### Phase 1 — Input normalization and deduplication

For every row:

- Normalize paths (`GetFullPath`, consistent separators).
- Normalize `Hash` (uppercase hex).
- Build dedupe key: `{NormalizedRecoveredPath}|{Hash}`.

**Dedup policy:**

- First row for a key → **work item**.
- Subsequent rows with same key → preflight status `DuplicateInputRow` (audit only; never move twice).

**Path role scan (full input set):**

- If any normalized `RecoveredPath` equals any normalized `RealNamedPath` → `PathRoleConflict`; do not move until reviewed.

### Phase 2 — Preflight validation (per work item)

| # | Check | Fail status |
|---|---|---|
| 1 | `RecoveredPath` under `I:\recover\` (v0.1) | `InvalidSourceRoot` / `NeedsJimReview` if under `I:\1tbrecover\` |
| 2 | `RecoveredPath` not under `I:\_RECOVERY_WORKBENCH\` | `AlreadyStaged` |
| 3 | `RecoveredPath` ≠ `RealNamedPath` (row-level) | `PathRoleConflict` |
| 4 | Source volume = destination volume (`I:\`) | `CrossVolumeRejected` |
| 5 | `RealNamedPath` exists | `KeeperMissing` |
| 6 | `Get-FileHash(RealNamedPath)` == report `Hash` | `KeeperHashMismatch` |
| 7 | `RecoveredPath` exists | `SourceMissing` |
| 8 | `RecoveredPath` full existing path chain has no reparse points | `SourceReparsePoint` / `SourceReparseCheckFailed` |
| 9 | `Get-FileHash(RecoveredPath)` == report `Hash` | `SourceHashMismatch` |
| 10 | Source size == `SizeBytes` | warn/skip as policy defines |
| 11 | Compute destination name; sanitize + length check | shortened name logged if needed |
| 12 | Destination does not exist | if exists → `.collision-NNN` suffix → `CollisionRenamed` |
| 13 | Destination existing parent/root path chain has no reparse points | `DestinationReparsePoint` / `DestinationReparseCheckFailed` |
| 14 | Never overwrite existing destination | — |

**Keeper verification is mandatory.** If keeper is missing or hash wrong, do not move the recovered file. A stale report must not cause relocation of a possibly sole verified copy.

**Same-volume enforcement is mandatory.** `Move-Item` only when source parent and `DestinationRoot` share the same volume (`I:\`). Cross-volume moves are rejected (`CrossVolumeRejected`) because cross-volume `Move-Item` can behave like copy-then-delete.

### Phase 3 — Destination naming and sanitization

Sanitize `recoveredFullName` and `realFullName`:

- Replace Windows-invalid chars `< > : " / \ | ? *` with `_`
- Trim trailing dots/spaces
- Handle reserved device names (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`)
- Enforce path length limits; if too long, use deterministic shortened safe name and record `DesiredDestinationName` vs `PlannedDestinationName` in manifest

**Collision handling (deterministic, never overwrite):**

```text
0E7A20EC.file602.png.Pepe_in_yard.png
0E7A20EC.file602.png.Pepe_in_yard.collision-002.png
0E7A20EC.file602.png.Pepe_in_yard.collision-003.png
```

Suffix inserted before extension. Status: `CollisionRenamed`.

### Phase 4 — Preflight report (always)

Write immutable plan to external `ReportRoot` (default on `C:\`):

```text
move_preflight_plan_YYYYMMDD-HHMMSS.csv
```

Created in **DryRun** and **Execute**. Contains every input row (including `DuplicateInputRow`) plus deduped work items with final preflight status.

**DryRun (default):** stop after preflight + summary. Move nothing.

### Phase 5 — Execute (only with `-Execute` + Jim approval)

**Not approved as of v0.1.4.** Code exists but must pass another Codex Sparky review and Jim approval before use.

1. Re-run full preflight checks.
2. Move only rows with `DryRunReady` or `CollisionRenamed`.
3. **Fresh keeper hash:** recompute `Get-FileHash(RealNamedPath)` immediately before each move; do not rely on preflight keeper cache for the execute gate.
4. **Reparse-point rejection:** walk the full existing path chain from volume root; fail closed on inspection errors.
5. **Crash-safe journal:** append+flush per-item entries to `move_execution_journal_YYYYMMDD-HHMMSS.csv` under `ReportRoot` (on `C:\`) before and after each move.
6. `Move-Item -LiteralPath` from `RecoveredPath` → `DestinationPath` only.
7. Post-move: destination exists; `Get-FileHash(destination)` == report `Hash`.
8. Success → `MOVED_VERIFIED`. Failure → `MOVE_FAILED` / `VERIFY_FAILED` (no delete, no rollback automation).
9. **`-WhatIf`:** no filesystem mutation — destination folder creation is behind `ShouldProcess`; `BEFORE_MOVE` journal only after `ShouldProcess` approves; manifest may show `WhatIfSkipped`.
10. Write final summary:

```text
move_execution_manifest_YYYYMMDD-HHMMSS.csv
```

Only when `-Execute` is used.

### Phase 5b — Execution journal (crash-safe, `-Execute` only)

`move_execution_journal_{timestamp}.csv` under `ReportRoot` (default `C:\Users\jim\Desktop\DrivePathInventory`).

Append and flush one row per journal event:

| Column | Description |
|---|---|
| `RunStamp` | Run timestamp |
| `Sequence` | Monotonic per-run sequence |
| `Phase` | `BEFORE_MOVE`, `AFTER_MOVE`, `MOVE_FAILED`, `VERIFY_FAILED`, `MOVED_VERIFIED`, `SKIPPED` |
| `Hash` | Expected hash |
| `RecoveredPath` | Source path |
| `DestinationPath` | Planned/actual destination |
| `RealNamedPath` | Keeper reference |
| `SourceHashBefore` | Measured pre-move source hash |
| `DestHashAfter` | Measured post-move dest hash |
| `Status` | Same vocabulary as `Phase` plus `KeeperMissing`, `KeeperHashMismatch` |
| `ErrorMessage` | Detail on failure/skip |
| `TimestampUtc` | ISO-8601 UTC |

### Phase 6 — Summary

Console + log:

```text
move_recovered_to_realname_log_YYYYMMDD-HHMMSS.txt
```

Counts by status.

---

## Parameters

| Parameter | Required | Default | Notes |
|---|---|---|---|
| `-MatchCsvPath` | **Yes** | — | Explicit stamped CSV; script refuses without it |
| `-ReportRoot` | No | `C:\Users\jim\Desktop\DrivePathInventory` | Preflight + execution manifests + log |
| `-DestinationRoot` | No | `I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname` | Must be on `I:\` |
| `-Execute` | No | off | **DryRun default** |
| `-Limit` | No | unlimited | Small pilot tests |
| `-WhatIf` | No | off | Optional PS what-if when `-Execute` |
| `-Algorithm` | No | `SHA256` | Must match hash report |

---

## Preflight manifest columns

`move_preflight_plan_{timestamp}.csv`

| Column | Description |
|---|---|
| `PreflightId` | Sequential ID |
| `InputRowNumber` | Original CSV row (1-based) |
| `IsPrimaryWorkItem` | `True` if deduped primary; `False` if duplicate-only row |
| `DedupeKey` | `NormalizedRecoveredPath\|Hash` |
| `MatchCsvPath` | Source report path |
| `MatchCsvStamp` | Parsed from filename, e.g. `20260703-004335` |
| `Hash` | Full SHA-256 |
| `ShortHash` | First 8 chars |
| `RecoveredPath` | Normalized |
| `RealNamedPath` | Normalized keeper reference |
| `RecoveredFileName` | From CSV |
| `RealNamedFileName` | From CSV |
| `SuggestedDuplicateName` | From CSV (audit only) |
| `DesiredDestinationName` | Before length shortening |
| `PlannedDestinationName` | Final filename after sanitize/shorten |
| `PlannedDestinationPath` | Full path under `DestinationRoot` |
| `SizeBytes` | From CSV |
| `Extension` | From CSV |
| `SourceVolume` | e.g. `I:\` |
| `DestinationVolume` | e.g. `I:\` |
| `KeeperExists` | `True`/`False` |
| `KeeperHashMatches` | `True`/`False`/`NotChecked` |
| `SourceExists` | `True`/`False` |
| `SourceHashMatches` | `True`/`False`/`NotChecked` |
| `CollisionSuffix` | e.g. `.collision-002` or empty |
| `PreflightStatus` | See status list |
| `PreflightMessage` | Human-readable detail |
| `RunMode` | `DryRun` or `Execute` |
| `PreflightAtUtc` | Timestamp |

---

## Execution manifest columns

`move_execution_manifest_{timestamp}.csv` — only written with `-Execute`

| Column | Description |
|---|---|
| *(all preflight columns for moved rows)* | |
| `OriginalPath` | `RecoveredPath` at move time |
| `DestinationPath` | Actual path after move |
| `Hash` | Expected from report |
| `KeeperPath` | `RealNamedPath` |
| `KeeperHashBefore` | Measured keeper hash |
| `SourceHashBefore` | Measured pre-move |
| `DestHashAfter` | Measured post-move |
| `SizeBytesBefore` | Source size |
| `SizeBytesAfter` | Dest size |
| `ExecutionStatus` | `MovedVerified`, `MoveFailed`, `Skipped`, etc. |
| `ErrorMessage` | On failure |
| `MovedAtUtc` | Move timestamp |
| `DurationMs` | Per-file |

---

## Status list

| Status | Meaning |
|---|---|
| `DryRunReady` | All preflight checks passed; ready to move |
| `DuplicateInputRow` | Extra CSV row; same `RecoveredPath`+`Hash` already planned |
| `NeedsJimReview` | Source under `I:\1tbrecover\` — not approved in v0.1 |
| `KeeperMissing` | `RealNamedPath` does not exist |
| `KeeperHashMismatch` | Keeper exists but hash ≠ report |
| `SourceMissing` | `RecoveredPath` does not exist |
| `SourceHashMismatch` | Source hash ≠ report |
| `SourceReparsePoint` | Source path chain includes symlink/junction |
| `SourceReparseCheckFailed` | Source reparse chain inspection failed (fail closed) |
| `DestinationReparsePoint` | Destination parent/root path chain includes symlink/junction |
| `DestinationReparseCheckFailed` | Destination reparse chain inspection failed (fail closed) |
| `InvalidSourceRoot` | `RecoveredPath` outside v0.1 approved `I:\recover\` |
| `AlreadyStaged` | Source under `I:\_RECOVERY_WORKBENCH\` |
| `PathRoleConflict` | Recovered path equals a keeper path in input |
| `CrossVolumeRejected` | Source and destination not same volume |
| `DestinationExists` | Collision detected (may transition to `CollisionRenamed`) |
| `CollisionRenamed` | Suffix applied; safe to move |
| `MovedVerified` | Move completed; post-hash OK |
| `MoveFailed` | Move or post-verify failed |
| `Skipped` | Skipped by `-Limit`, `-WhatIf`, or policy |

---

## Safety checks summary

```
INPUT
  ├─ Explicit -MatchCsvPath required
  ├─ Dedupe by NormalizedRecoveredPath + Hash
  ├─ PathRoleConflict scan (RecoveredPath ∩ RealNamedPath)
  └─ DuplicateInputRow logging

KEEPER (before any move)
  ├─ RealNamedPath exists
  └─ RealNamedPath hash == report Hash

SOURCE (v0.1)
  ├─ Under I:\recover\ only
  ├─ I:\1tbrecover\ → NeedsJimReview / InvalidSourceRoot
  ├─ Not under I:\_RECOVERY_WORKBENCH\
  ├─ Exists
  ├─ Not a reparse point on full existing path chain (fail closed on inspect errors)
  ├─ Hash == report Hash
  └─ Same volume as DestinationRoot (I:\)

DESTINATION
  ├─ Sanitized full filename format
  ├─ Path length safe (or deterministic shorten)
  ├─ No overwrite — .collision-NNN suffix
  ├─ Existing parent/root chain not a reparse point (fail closed on inspect errors)
  └─ Create folder only on -Execute (behind ShouldProcess; not under -WhatIf)

EXECUTE
  ├─ Re-preflight all rows
  ├─ Fresh keeper hash before each move (no preflight cache gate)
  ├─ Crash-safe execution journal on C:\ ReportRoot
  ├─ Move-Item -LiteralPath only (RecoveredPath → staging)
  ├─ Never touch RealNamedPath
  ├─ Post-move hash verify
  ├─ -WhatIf: no filesystem mutation
  └─ No Copy-Item / Remove-Item / cleanup
```

---

## Example commands

### Dry run (default — safe, approved for planning)

```powershell
cd I:\DrivePathScout-RedneckMaestro

.\Move-RecoveredToRealnameMatches.ps1 `
  -MatchCsvPath "C:\Users\jim\Desktop\DrivePathInventory\recovered_to_realname_matches_20260703-004335.csv"
```

### Dry run — pilot

```powershell
.\Move-RecoveredToRealnameMatches.ps1 `
  -MatchCsvPath "C:\Users\jim\Desktop\DrivePathInventory\recovered_to_realname_matches_20260703-004335.csv" `
  -Limit 1
```

### Execute (NOT APPROVED — spec only)

```powershell
.\Move-RecoveredToRealnameMatches.ps1 `
  -MatchCsvPath "C:\Users\jim\Desktop\DrivePathInventory\recovered_to_realname_matches_20260703-004335.csv" `
  -Limit 1 `
  -Execute
```

---

## Non-negotiables

Do **not** implement or use:

- `Copy-Item`
- `Remove-Item`
- Delete
- Cleanup automation
- Moving real-named keepers
- Broad folder reorganization
- Auto-latest report selection
- Cross-volume moves

**Mandatory gates:** keeper verification and same-volume enforcement before any move.

---

## Open concerns

1. **Cartesian CSV** — many rows share collision-prone destination base names (e.g. multiple `DAD2.PST` recovered copies).
2. **`I:\1tbrecover\` rows in report** — v0.1 marks these `NeedsJimReview`; Jim must approve specific subtrees before any future expansion.
3. **Partial execute + rerun** — read prior `move_execution_manifest_*.csv` and journal to skip already `MovedVerified` sources.
4. **Large files (PST, etc.)** — keeper + source + dest hashing will be slow; pilot with `-Limit 1` essential.
5. **Unicode / long paths** — use `-LiteralPath`; may need `\\?\` prefix on failure.
6. **Approval layers** — separate approval for: (a) script implementation, (b) DryRun preflight review, (c) any `-Execute` run.

**Resolved in v0.1.4:**

- `-OnlyRecoveredPath` exact normalized recovered-path targeting for one-file pilot DryRun.
- Rejects `-OnlyRecoveredPath` + `-Limit` combination.

**Resolved in v0.1.3:**

- Preserve volume root as ``I:\`` (not bare ``I:``) in path-chain reparse inspection.
- ``Test-PathChainRootComponents`` startup self-test.
- Execute manifest typed ``SourceMissing`` / ``SourceHashMismatch`` statuses.

**Resolved in v0.1.2:**

- Full path-chain reparse inspection (fail closed).
- `ReportRoot` must be outside `I:\`.
- All execute-attempt rows appear in final manifest (including keeper failures).
- `BEFORE_MOVE` journal only after `ShouldProcess` approval.

**Resolved in v0.1.1:**

- Keeper hash caching during preflight only; execute re-checks fresh hash per move.
- Crash-safe execution journal during `-Execute`.
- Reparse-point rejection on source and destination paths.
- `-WhatIf` non-mutating destination folder creation.

---

## Approval status

| Item | Status |
|---|---|
| Design documented (`STAGING_SPEC.md`) | Done |
| `Move-RecoveredToRealnameMatches.ps1` v0.1.0 DryRun implementation | Done |
| v0.1.4 `-OnlyRecoveredPath` exact path targeting | Done |
| v0.1.3 path-chain volume root fix and typed execute source statuses | Done |
| v0.1.2 execute gate tightening (path-chain reparse, ReportRoot off I:\, manifest completeness, WhatIf journal) | Done |
| v0.1.1 execute safety hardening (journal, fresh keeper hash, reparse, WhatIf) | Done |
| Codex Sparky DryRun planning review | **Passed** |
| Codex Sparky Execute review | **Not approved** — pending re-review after v0.1.4 fixes |
| Jim approval for `-Execute` | **Blocked** |
