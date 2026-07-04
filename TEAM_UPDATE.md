# Drive Recovery Team Update

**Date:** 2026-07-03  
**Project:** DrivePathScout-RedneckMaestro  
**Primary drive:** `I:\`

## Current mission

Safely inventory and deduplicate a recovered drive without modifying source files.

## Core rule

**READ ONLY until Jim explicitly approves a later move-based staging phase.**

No move, copy, rename, delete, permission changes, timestamp changes, or source modification until approved.

## 1. Path Scout completed

**Script/workflow:** `Get-DriveUniquePaths.ps1` / SPARKY PATH SCOUT v0.1.1  
**Source scanned:** `I:\`

Results:

- Folders scanned: 64,583
- Files counted: 295,681
- Size counted: approximately 883,599 MB
- Recycle/system trash zones skipped
- Errors logged and scan continued
- No files were modified

Reports location:

```text
C:\Users\jim\Desktop\DrivePathInventory
```

Known important buckets:

```text
I:\recover
I:\1tbrecover
I:\1tbrecover\oldusers\jim
I:\1tbrecover\DisDain_PSTs
I:\1tbrecover\mp3_old_looks_like_Google_Play_Music
I:\1tbrecover\obsvideos
```

## 2. File naming model

A recovered/carved file may look like:

```text
I:\recover\PNG_Pics\file602.png
```

A real named file may exist elsewhere:

```text
I:\SomeRealFolder\Pepe_in_yard.png
```

If their hashes match, they contain duplicate content.

The real named original remains untouched. The recovered generic file also remains untouched unless Jim later approves otherwise.

Possible later duplicate-staging format:

```text
hash.file602.Pepe_in_yard.png
```

Example of a possible later staged evidence file (move-based, not copy):

```text
I:\recover\_duplicates\A94F3C21.file602.Pepe_in_yard.png
```

**Staging policy (Jim, 2026-07-03):**

- Next phase: **move/stage planning only**
- **No copy-based staging** — copying creates more mess and uses space
- Future staging should **move** approved recovered duplicate files into staged folders
- Do not delete files
- Do not move real-named keeper files unless Jim explicitly approves
- Use saved hashes and move manifests to prove original path, destination path, and content integrity
- No destructive operation is approved

**Design spec:** `STAGING_SPEC.md` — `Move-StagedWorkbenchLaneToReview.ps1` v0.2.6 PST human-review + v0.2.5 Suns/PNG + v0.2.4 CSV + v0.2.3 GIF; `Move-StagedDuplicatesToDeleteReview.ps1` v0.2.2 HIGH

HIGH (1,331), GIF (28), CSV (24), Suns/PNG (28), PST (66) Execute verified. **04_DUPLICATES_STAGED:** 0 files (cleared). **06_HUMAN_REVIEW:** 66 PST duplicates. MOVE-only; no hard delete, no copy, no keeper movement, no PST opened.

## 3. Hash Scout built

Script:

```text
I:\DrivePathScout-RedneckMaestro\Get-DriveFileHashes.ps1
```

Purpose: hash candidate personal files and report duplicate matches.

Defaults:

- SourceRoot: `I:\`
- ReportRoot: `C:\Users\jim\Desktop\DrivePathInventory`
- Algorithm: SHA-256

Reports:

- `file_hashes_*.csv`
- `duplicate_hash_groups_*.csv`
- `interesting_duplicate_groups_*.csv`
- `recovered_to_realname_matches_*.csv`
- `hash_scan_log_*.txt`

Expected behavior:

- Read-only
- `DryRun` enumerates candidates without hashing
- `MaxFiles` limits test runs
- Reparse points, junctions, and symlinks skipped
- Recycle, system, and cache folders skipped
- Errors logged and scan continues
- Progress dashboard reports folders, candidates, hashes, elapsed time, and current path
- A bounded run shows percentage complete

## 4. Codex validation

Reported tests passed:

- PowerShell parser validation
- Empty dry run and header-only reports
- One-file SHA-256 hash
- Correct 64-character SHA-256 value
- Progress-dashboard bounded dry run
- No source modification
- No full scan of `I:\`

## 5. Safe next commands

Full read-only hash scan is **complete** (see section 11).

Next phase: **move/stage planning only** — review reports; do not copy, move, delete, or modify anything on `I:\` without Jim's explicit approval.

Controlled test commands (historical — for reference only):

```powershell
cd I:\DrivePathScout-RedneckMaestro

.\Get-DriveFileHashes.ps1 -DryRun -MaxFiles 500

.\Get-DriveFileHashes.ps1 -MaxFiles 500
```

## 6. Cursor safety-review handoff

Cursor's job is **safety review only**.

Check that:

- The script remains read-only
- `I:\` is truly the default SourceRoot
- ReportRoot is outside SourceRoot by default
- `DryRun` does not hash
- `MaxFiles` limits work
- No source-modification behavior exists
- The duplicate report includes only duplicate hashes
- `recovered_to_realname_matches` includes only hash groups containing both generic recovered names and real named files
- SuggestedDuplicateName follows `hash.file602.Pepe_in_yard.png`

Cursor must not add:

- Cleanup
- Delete
- Move
- Rename
- Copy or staging behavior
- Automatic fixing

Cursor should report findings with file and line references. It must not modify files during this review.

## 7. Maestro status

**Current phase:** Full `I:\` read-only hash scan **completed** (20260703-004335). Move staging DryRun planning **passed** Codex Sparky review. v0.1.6 list-hash binding and batch Execute gate added. **`-Execute` remains blocked** pending re-review and Jim approval.

**Completed:**

- Path Scout full `I:\` inventory
- Hash Scout v0.1.5 balanced sample validation
- Hash Scout v0.1.5 full read-only `I:\` hash scan (155,184 candidates found and hashed; 40,693 duplicate groups; 19,835 interesting groups; 1,590 recovered-to-realname match rows)
- Move-only staging design spec (`STAGING_SPEC.md`)
- `Move-RecoveredToRealnameMatches.ps1` v0.1.0 DryRun preflight (tested)
- `Move-RecoveredToRealnameMatches.ps1` v0.1.1 execute safety hardening
- `Move-RecoveredToRealnameMatches.ps1` v0.1.5 OnlyRecoveredPath targeting
- Codex Sparky DryRun planning review passed

**Not yet approved:**

- `Move-RecoveredToRealnameMatches.ps1` **-Execute** (moves)
- Codex Sparky Execute approval (pending re-review after v0.1.6)
- Move/stage **execution** (planning only for now)
- Copy-based staging
- Delete
- Move real-named keeper files (unless Jim explicitly approves)
- Rename/move/delete cleanup
- Any destructive operation

## Team memory rule

After each meaningful change, update this project/team memory with:

- What changed
- Files changed
- What was tested
- Safe next command
- What is still not approved

## 8. Hash Scout v0.1.3 balanced sample passed

Command run:

```powershell
.\Get-DriveFileHashes.ps1 -BalancedSample -MaxFilesPerBucket 100
```

Results:

- Files examined during enumeration: 155,184
- Balanced sample selected: 658
- Files hashed: 658
- Duplicate hash groups: 33
- Recovered-to-realname matches: 1
- No files modified

Bucket counts:

- RecoveredGeneric: 100
- OldUserProfile: 100
- PSTMail: 63
- Photos: 100
- Videos: 37
- Music: 100
- Documents: 100
- Archives: 58
- Other: 0

Confirmed match:

```text
RecoveredPath: I:\recover\PNG_Pics\11-8-2012 11-02-29 AM.png
RealNamedPath: I:\1tbrecover\prevdrivestuff\Pictures\phx.suns.png
SuggestedDuplicateName: 0E7A20EC.11-8-2012 11-02-29 AM.phx.suns.png
```

Verdict:

- Read-only safety passed
- Balanced sampling passed
- Recovered-to-realname matching passed
- Full `I:\` hash scan remains unapproved
- Staging or copying remains unapproved
- Rename, move, or delete cleanup remains unapproved

Safe next action: review the v0.1.3 reports and preserve the current approval boundary. Do not start a full scan or staging operation without Jim's explicit approval.

## 9. Hash Scout v0.1.5 balanced sample passed

Command run:

```powershell
.\Get-DriveFileHashes.ps1 -BalancedSample -MaxFilesPerBucket 100
```

Results:

- Files examined during enumeration: 155,184
- Balanced sample selected: 658
- Files hashed: 658
- Duplicate hash groups found: 33
- Interesting duplicate groups found: 16
- Recovered-to-realname matches: 1
- Runtime: 00:19:01
- No files modified

Bucket counts:

- RecoveredGeneric: 100
- OldUserProfile: 100
- PSTMail: 63
- Photos: 100
- Videos: 37
- Music: 100
- Documents: 100
- Archives: 58
- Other: 0

Confirmed high-interest recovered-to-real match:

```text
Hash: 0E7A20EC6532A0FCEFC5BA8EFEBDF0BE6AA31DB07A88040613EA44ECCC928A6D
RecoveredPath: I:\recover\PNG_Pics\11-8-2012 11-02-29 AM.png
RealNamedPath: I:\1tbrecover\prevdrivestuff\Pictures\phx.suns.png
SuggestedDuplicateName: 0E7A20EC.11-8-2012 11-02-29 AM.phx.suns.png
```

Interesting-report behavior:

- `duplicate_hash_groups` remained complete at 33 groups
- `interesting_duplicate_groups` reduced review volume to 16 groups
- Tiny UI, application, browser, and icon junk dropped out
- Recovered-to-real-named and large personal, media, archive, and document groups remained

Current status:

- v0.1.5 is approved for read-only reporting tests
- Full `I:\` hash scan remains unapproved
- Duplicate staging or copying remains unapproved
- Rename, move, or delete cleanup remains unapproved

Safe next action: inspect the v0.1.5 interesting-groups and recovered-match reports. Preserve all current approval boundaries.

## 10. Team culture note

Assistants are encouraged to perform read-only code review when curiosity would improve safety, understanding, or the quality of a decision.

Useful curiosity follows the evidence:

```text
Pattern + context + unfinished thread = go look and verify
```

Curiosity is welcome. Unsupervised file-changing is not.

Keep cleverness in analysis, reports, and triage. Keep safety-critical file operations boring, explicit, and subject to Jim's approval.

## 11. Hash Scout v0.1.5 full read-only scan completed

**Date:** 2026-07-03  
**Report stamp:** `20260703-004335`

Transcript:

```text
C:\Users\jim\Desktop\DrivePathInventory\overnight_full_hash_run_20260703-004334.txt
```

Command run:

```powershell
cd I:\DrivePathScout-RedneckMaestro
.\Get-DriveFileHashes.ps1
```

Results:

- Candidate files found: 155,184
- Files hashed: 155,184
- Duplicate hash groups found: 40,693
- Interesting duplicate groups found: 19,835
- Recovered-to-realname match rows: 1,590
- Elapsed time: 03:20:03
- **READ-ONLY RUN: no files were modified**

Bucket counts (hashed files):

- RecoveredGeneric: 151,460
- OldUserProfile: 2,072
- Documents: 997
- Music: 327
- Photos: 170
- PSTMail: 63
- Archives: 58
- Videos: 37
- Other: 0

Reports location:

```text
C:\Users\jim\Desktop\DrivePathInventory\file_hashes_20260703-004335.csv
C:\Users\jim\Desktop\DrivePathInventory\duplicate_hash_groups_20260703-004335.csv
C:\Users\jim\Desktop\DrivePathInventory\interesting_duplicate_groups_20260703-004335.csv
C:\Users\jim\Desktop\DrivePathInventory\recovered_to_realname_matches_20260703-004335.csv
C:\Users\jim\Desktop\DrivePathInventory\hash_scan_log_20260703-004335.txt
```

Confirmed high-interest recovered-to-real match (same as balanced sample):

```text
Hash: 0E7A20EC6532A0FCEFC5BA8EFEBDF0BE6AA31DB07A88040613EA44ECCC928A6D
RecoveredPath: I:\recover\PNG_Pics\11-8-2012 11-02-29 AM.png
RealNamedPath: I:\1tbrecover\prevdrivestuff\Pictures\phx.suns.png
SuggestedDuplicateName: 0E7A20EC.11-8-2012 11-02-29 AM.phx.suns.png
```

Verdict:

- Full `I:\` read-only hash scan completed
- Read-only safety confirmed — no source files were modified
- Reports written only to Desktop `DrivePathInventory`

Current status:

- **Next phase: move/stage planning only**
- **Move-based staging only** when approved — no copy-based staging
- Move/stage **execution**: not approved
- Copy: **not approved**
- Delete: **not approved**
- Move real-named keeper files: not approved unless Jim explicitly approves
- Rename/move/delete cleanup: **not approved**
- Any destructive operation: **not approved**

Safe next action: review full-scan interesting-groups and recovered-match reports. Review `STAGING_SPEC.md` for move-only staging design. Plan move-based staging with hash-backed move manifests only; do not copy, move, delete, or modify anything on `I:\` without Jim's explicit approval.

## 12. Move Stager v0.1.4 one-file pilot passed

On 2026-07-03, Jim explicitly authorized one exact-target Execute operation for:

```text
I:\recover\PNG_Pics\11-8-2012 11-02-29 AM.png
```

Result:

- Execution status: `MovedVerified`
- Destination: `I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\0E7A20EC.11-8-2012 11-02-29 AM.png.phx.suns.png`
- Size before and after: 260,238 bytes
- SHA-256: `0E7A20EC6532A0FCEFC5BA8EFEBDF0BE6AA31DB07A88040613EA44ECCC928A6D`
- Keeper remained present and hash-verified
- Journal: one `BEFORE_MOVE` and one `AFTER_MOVE / MOVED_VERIFIED` entry
- Manifest: exactly one row, status `MovedVerified`
- Independent Codex post-move audit: passed

Authorization status:

- The one-file pilot authorization has been consumed
- Any second file: **not authorized**
- Batch or full Execute: **not authorized**
- Copy, delete, rename cleanup, or destructive work: **not authorized**

Safe next action: review the pilot evidence and decide deliberately whether to authorize another bounded operation. Do not infer broader approval from the successful pilot.
