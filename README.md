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

`Move-StagedWorkbenchLaneToReview.ps1` v0.3.0 extends the lane mover with **`Phase2McNasBackupMusicExtrasHumanReview`**, **`Phase2McNasBackupVideoExtrasHumanReview`**, **`Phase2WebAssetsTier1`**, **`Phase2BmpMediumReview`**, **`PstHumanReview`**, **`SunsPngMedium`**, **`CsvMedium`**, and **`GifMedium`** profiles. MOVE-only grouping for human review — not hard delete.

| Lane | Source | Destination | Status |
|------|--------|-------------|--------|
| HIGH browser_extension | `...\browser_extension_assets` | `05_DELETE_REVIEW\high_confidence_junk\...` | Execute verified (1,280) |
| HIGH theme_assets | `...\theme_assets` | `05_DELETE_REVIEW\high_confidence_junk\...` | Execute verified (51) |
| GIF | `...\images\gif` | `05_DELETE_REVIEW\medium_review\gif` | Execute verified (28) |
| CSV | `...\data\csv` | `05_DELETE_REVIEW\medium_review\csv` | Execute verified (24) |
| Suns/PNG | flat under `recovered_to_realname` | `05_DELETE_REVIEW\medium_review\suns_png` | Execute verified (28) |
| PST | `...\mail\pst` | `06_HUMAN_REVIEW\mail\pst_duplicates` | Execute verified (66) |
| Phase 2 BMP | `I:\recover\BMPs` (medium-review only) | `05_DELETE_REVIEW\medium_review\images\bmp` | Execute verified (1,619) |
| Phase 2 web-assets Tier1 | `I:\recover\McNASBackup` (Tier1 KEEP only) | `05_DELETE_REVIEW\high_confidence_junk\phase2_web_assets\...` | Execute verified (16,708) |
| Phase 2 McNASBackup video extras | `I:\recover\McNASBackup` (MOVE_EXTRAS_READY duplicate extras only) | `06_HUMAN_REVIEW\media\videos\mcnasbackup_duplicate_extras` | Execute verified (650) |
| Phase 2 McNASBackup music extras | `I:\recover\McNASBackup` (HUMAN_REVIEW_MOVE_EXTRAS_READY duplicate extras only) | `06_HUMAN_REVIEW\media\music\mcnasbackup_duplicate_extras` | Execute verified (2,838) |

**04_DUPLICATES_STAGED:** 0 files (cleared; empty dirs remain). **05_DELETE_REVIEW:** 19,738 files (~2.59 GB incl. Phase 2 web-assets Tier1 + BMP medium-review). **06_HUMAN_REVIEW:** 3,554 files (~45.3 GB: 2,838 music + 650 video duplicate extras + 66 PST). **02_KEEPERS_REVIEW:** 15 PST keeper review copies (unchanged). **Phase 2 BMP human-review:** 4,406 files HOLD under `I:\recover\BMPs` (untouched). **Phase 2 web-assets HOLD:** PDFs, Office docs, shared-human hashes, Tier2 unclear, human-review escalations remain under `I:\recover\McNASBackup`. **Phase 2 McNASBackup video HOLD:** sample-first (294 groups), medium (4), low-risk (1) remain in recover; 650 MOVE_EXTRAS_READY duplicate extras Execute verified (`phase2_mcnasbackup_video_move_extras_verification_20260704.txt`); `CandidateKeeperPath` stayed in place for all 261 moved groups. **Phase 2 McNASBackup music HOLD:** sample-first (2,420 groups), medium sample-first (2,788), medium move-extras-ready (9), low-risk (29) remain in recover; 2,838 HUMAN_REVIEW_MOVE_EXTRAS_READY duplicate extras Execute verified (`phase2_mcnasbackup_music_human_move_extras_verification_20260704.txt`); `CandidateKeeperPath` stayed in place for all 1,286 moved groups.

Build plans:

```powershell
.\New-ApprovedGifReviewMovePlan.ps1
.\New-ApprovedCsvReviewMovePlan.ps1
.\New-ApprovedSunsPngReviewMovePlan.ps1
.\New-ApprovedPstHumanReviewMovePlan.ps1
.\New-ApprovedPhase2BmpMediumReviewMovePlan.ps1
.\New-ApprovedPhase2WebAssetsTier1MovePlan.ps1
.\New-ApprovedPhase2McNasBackupVideoMoveExtrasPlan.ps1
.\New-ApprovedPhase2McNasBackupMusicHumanMoveExtrasPlan.ps1

# Phase 2 McNASBackup music human move-extras DryRun example (HUMAN_REVIEW_MOVE_EXTRAS_READY duplicate extras only; keeper stays)
.\Move-StagedWorkbenchLaneToReview.ps1 `
  -InventoryCsvPath "C:\Users\jim\Desktop\DrivePathInventory\phase2_mcnasbackup_music_duplicate_inventory_20260704.csv" `
  -ApprovedReviewMovePlan "C:\Users\jim\Desktop\DrivePathInventory\approved_phase2_mcnasbackup_music_human_move_extras_plan_20260704.csv" `
  -ExpectedApprovedReviewMovePlanHash "<sha256>" `
  -LaneProfile Phase2McNasBackupMusicExtrasHumanReview

# Phase 2 McNASBackup video move-extras DryRun example (MOVE_EXTRAS_READY duplicate extras only; keeper stays)
.\Move-StagedWorkbenchLaneToReview.ps1 `
  -InventoryCsvPath "C:\Users\jim\Desktop\DrivePathInventory\phase2_mcnasbackup_video_duplicate_inventory_20260704.csv" `
  -ApprovedReviewMovePlan "C:\Users\jim\Desktop\DrivePathInventory\approved_phase2_mcnasbackup_video_move_extras_plan_20260704.csv" `
  -ExpectedApprovedReviewMovePlanHash "<sha256>" `
  -LaneProfile Phase2McNasBackupVideoExtrasHumanReview

# Phase 2 web-assets Tier1 DryRun example (Tier1 KEEP rows only)
.\Move-StagedWorkbenchLaneToReview.ps1 `
  -InventoryCsvPath "C:\Users\jim\Desktop\DrivePathInventory\phase2_web_assets_lowrisk_refinement_20260704.csv" `
  -ApprovedReviewMovePlan "C:\Users\jim\Desktop\DrivePathInventory\approved_phase2_web_assets_tier1_move_plan_20260704.csv" `
  -ExpectedApprovedReviewMovePlanHash "<sha256>" `
  -LaneProfile Phase2WebAssetsTier1

# Phase 2 BMP medium-review DryRun example (MEDIUM_REVIEW_IMAGES_BMP only)
.\Move-StagedWorkbenchLaneToReview.ps1 `
  -InventoryCsvPath "C:\Users\jim\Desktop\DrivePathInventory\phase2_bmp_duplicate_inventory_20260704.csv" `
  -ApprovedReviewMovePlan "C:\Users\jim\Desktop\DrivePathInventory\approved_phase2_bmp_medium_review_move_plan_20260704.csv" `
  -ExpectedApprovedReviewMovePlanHash "<sha256>" `
  -LaneProfile Phase2BmpMediumReview

# PST human-review DryRun example
.\Move-StagedWorkbenchLaneToReview.ps1 `
  -InventoryCsvPath "C:\Users\jim\Desktop\DrivePathInventory\pst_policy_inventory_20260704.csv" `
  -ApprovedReviewMovePlan "C:\Users\jim\Desktop\DrivePathInventory\approved_pst_human_review_move_plan_20260704.csv" `
  -ExpectedApprovedReviewMovePlanHash "<sha256>" `
  -LaneProfile PstHumanReview
```

Never moves keepers or `I:\1tbrecover\` paths. Staged-lane profiles never move `I:\recover\` except **`Phase2BmpMediumReview`**, **`Phase2WebAssetsTier1`**, **`Phase2McNasBackupVideoExtrasHumanReview`**, and **`Phase2McNasBackupMusicExtrasHumanReview`**, which move only approved rows from `I:\recover\BMPs`, Tier1 KEEP web-assets, MOVE_EXTRAS_READY video duplicate extras, and HUMAN_REVIEW_MOVE_EXTRAS_READY music duplicate extras from `I:\recover\McNASBackup` respectively. Video and music move-extras never move `CandidateKeeperPath`. Phase 2 McNASBackup music human move-extras Execute verified (2,838 moved; 9,323,075,199 bytes; verification receipt `phase2_mcnasbackup_music_human_move_extras_verification_20260704.txt`). Phase 2 McNASBackup video move-extras Execute verified (650 moved; 39,107,870,438 bytes; verification receipt `phase2_mcnasbackup_video_move_extras_verification_20260704.txt`). Phase 2 web-assets Tier1 Execute verified (16,708 moved; 2,472,457,276 bytes). Phase 2 BMP medium-review Execute verified (1,619 moved; 4,406 human-review BMPs remain in recover). All lane Execute operations verified. Staging lane cleared.

**Next aggressive read-only target:** McNASBackup music sample-first review (`HUMAN_REVIEW_SAMPLE_FIRST` — 2,420 groups HOLD) or McNASBackup video sample-first review (`HUMAN_REVIEW_SAMPLE_FIRST` — 294 groups / ~52.1 GB extras HOLD).

## Parked final-delete tool

`Remove-StagedDuplicateCandidates.ps1` v0.2.0 remains available as a **parked future final-delete** planner only. Do not use `-Execute` for routine cleanup.

## Scope

`Get-DriveUniquePaths.ps1` is an inventory tool, not an organizer. `Move-RecoveredToRealnameMatches.ps1` defaults to DryRun and requires explicit, operation-specific Jim approval before each use of `-Execute`.
