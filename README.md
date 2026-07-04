# Redneck Maestro Drive Path Scout

Version **v0.1.1** is a read-only PowerShell scout for mapping the folder structure of an old drive. It records every accessible folder, direct file count, direct file-size total, common extensions, newest direct file date, depth, and useful path flags.

It writes four timestamped reports to a separate output folder:

- `unique_paths_TIMESTAMP.csv` — sortable inventory with counts and flags
- `unique_paths_TIMESTAMP.txt` — plain full-path list
- `chat_context_paths_TIMESTAMP.md` — low-vision-friendly review report
- `scan_log_TIMESTAMP.txt` — skipped folders and errors

## Safety rails

The scout refuses to write its reports inside `SourceRoot`. It does not move, copy from, rename, or delete source files. It skips reparse points, junctions, symlinks, Windows recycle/system-trash folders, and continues after logging access or long-path errors.

The default report location is:

```text
%USERPROFILE%\Desktop\DrivePathInventory
```

## Run it

Open PowerShell in this project folder. Default source is `I:\`; reports go to your Desktop:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Get-DriveUniquePaths.ps1
```

Same thing, explicit source:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Get-DriveUniquePaths.ps1 -SourceRoot "I:\"
```

Custom output folder:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Get-DriveUniquePaths.ps1 -OutDir "$env:USERPROFILE\Desktop\DrivePathInventory"
```

Sparky hood stamp:

```text
Target drive: I:\
Project folder: I:\DrivePathScout-RedneckMaestro
Report output: Desktop\DrivePathInventory
No E:\.
No guessing.
Jim said I:\ period.
```

Note: because the repo itself is on `I:\`, scanning `I:\` will include `I:\DrivePathScout-RedneckMaestro` in the results. That is expected and not dangerous; the script still writes reports to `OutDir` (Desktop by default), and refuses to write reports inside `SourceRoot`.

When the scan finishes, send `chat_context_paths_TIMESTAMP.md` back to ChatGPT Sparky for review.

## Move staging planner

`Move-RecoveredToRealnameMatches.ps1` v0.1.8 implements move-only staging **preflight** per `STAGING_SPEC.md`. Default mode is DryRun — it does not move, copy, delete, or rename files.

```powershell
.\Move-RecoveredToRealnameMatches.ps1 `
  -MatchCsvPath "C:\Users\jim\Desktop\DrivePathInventory\recovered_to_realname_matches_20260703-004335.csv" `
  -Limit 10
```

v0.1.8 hardens routed `DestinationSubfolder` segment validation and post-join containment checks inside approved `DestinationRoot`. Routed batch Execute `20260703-221211` moved 1,383 staged duplicates with full verification.

## Staged duplicate delete-review move planner

`Move-StagedDuplicatesToDeleteReview.ps1` v0.2.2 plans **MOVE-only** grouping of HIGH-confidence staged duplicate junk into `I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW\high_confidence_junk\` for human review. Default mode is DryRun — it does not delete, copy, or rename files. v0.2.2 adds full execute preflight before any `Move-Item` and mandatory inventory coupling (fail-closed; not transactionally atomic after external I/O failure).

`Move-StagedWorkbenchLaneToReview.ps1` v0.2.6 extends the lane mover with **`PstHumanReview`**, **`SunsPngMedium`**, **`CsvMedium`**, and **`GifMedium`** profiles. MOVE-only grouping for human review — not hard delete.

| Lane | Source | Destination | Status |
|------|--------|-------------|--------|
| HIGH browser_extension | `...\browser_extension_assets` | `05_DELETE_REVIEW\high_confidence_junk\...` | Execute verified (1,280) |
| HIGH theme_assets | `...\theme_assets` | `05_DELETE_REVIEW\high_confidence_junk\...` | Execute verified (51) |
| GIF | `...\images\gif` | `05_DELETE_REVIEW\medium_review\gif` | Execute verified (28) |
| CSV | `...\data\csv` | `05_DELETE_REVIEW\medium_review\csv` | Execute verified (24) |
| Suns/PNG | flat under `recovered_to_realname` | `05_DELETE_REVIEW\medium_review\suns_png` | Execute verified (28) |
| PST | `...\mail\pst` | `06_HUMAN_REVIEW\mail\pst_duplicates` | Execute verified (66) |

**04_DUPLICATES_STAGED:** 0 files (cleared; empty dirs remain). **05_DELETE_REVIEW:** 1,411 files / 35,731,729 bytes. **06_HUMAN_REVIEW:** 66 PST files / 230,307,840 bytes. **02_KEEPERS_REVIEW:** 15 PST keeper review copies (unchanged).

Build plans:

```powershell
.\New-ApprovedGifReviewMovePlan.ps1
.\New-ApprovedCsvReviewMovePlan.ps1
.\New-ApprovedSunsPngReviewMovePlan.ps1
.\New-ApprovedPstHumanReviewMovePlan.ps1

# PST human-review DryRun example
.\Move-StagedWorkbenchLaneToReview.ps1 `
  -InventoryCsvPath "C:\Users\jim\Desktop\DrivePathInventory\pst_policy_inventory_20260704.csv" `
  -ApprovedReviewMovePlan "C:\Users\jim\Desktop\DrivePathInventory\approved_pst_human_review_move_plan_20260704.csv" `
  -ExpectedApprovedReviewMovePlanHash "<sha256>" `
  -LaneProfile PstHumanReview
```

Never moves keepers, `I:\recover\`, or `I:\1tbrecover\` paths. All lane Execute operations verified. Staging lane cleared.

## Parked final-delete tool

`Remove-StagedDuplicateCandidates.ps1` v0.2.0 remains available as a **parked future final-delete** planner only. Do not use `-Execute` for routine cleanup.

## Scope

`Get-DriveUniquePaths.ps1` is an inventory tool, not an organizer. `Move-RecoveredToRealnameMatches.ps1` defaults to DryRun and requires explicit, operation-specific Jim approval before each use of `-Execute`.
