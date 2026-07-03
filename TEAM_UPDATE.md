# Drive Recovery Team Update

**Date:** 2026-07-02  
**Project:** DrivePathScout-RedneckMaestro  
**Primary drive:** `I:\`

## Current mission

Safely inventory and deduplicate a recovered drive without modifying source files.

## Core rule

**READ ONLY until Jim explicitly approves a later staging/copy phase.**

No move, copy, rename, delete, permission changes, timestamp changes, or source modification.

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

Example of a possible later staged evidence copy:

```text
I:\recover\_duplicates\A94F3C21.file602.Pepe_in_yard.png
```

Meaning:

- `A94F3C21` — short hash proof
- `file602` — recovered generic filename
- `Pepe_in_yard` — matched real original filename
- `.png` — file extension

This staging behavior is **not implemented or approved**.

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

## 5. Current safe next commands

Do **not** run the full hash scan yet.

Run controlled tests first:

```powershell
cd I:\DrivePathScout-RedneckMaestro

.\Get-DriveFileHashes.ps1 -DryRun -MaxFiles 500

.\Get-DriveFileHashes.ps1 -MaxFiles 500
```

Review all generated reports before considering a full run.

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

**Current phase:** Hash Scout safety review and 500-file test.

Not yet approved:

- Full `I:\` hash scan
- Duplicate staging or copying
- Rename, move, or delete cleanup
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
