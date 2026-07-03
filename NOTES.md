# Project Notes

## Team

- Jim — sheriff, drive owner, and final approval
- ChatGPT Sparky — architect, policy brain, guardrails, and workflow designer
- Bard/Gemini — outside reviewer, edge-case goblin, and safety critic
- Codex Sparky — builder, script writer, and repo creator
- Cursor Sparky — local repo mechanic, patcher, and debugger
- PowerShell — local mule that does exactly what the script says
- GitHub — audit trail, memory, and receipts

---

## DRIVE RECOVERY TEAM UPDATE

**Date:** 2026-07-03  
**Project:** DrivePathScout-RedneckMaestro  
**Primary drive:** `I:\`

### Current mission

We are safely inventorying and deduping a recovered drive without modifying source files.

### Core rule

**READ ONLY** until Jim explicitly approves a later **move-based** staging phase.

No move, copy, rename, delete, permission changes, timestamp changes, or source modification until approved.

---

### What we did so far

#### 1. Path Scout completed

**Script/workflow:** `Get-DriveUniquePaths.ps1` / SPARKY PATH SCOUT v0.1.1

**Source scanned:** `I:\`

**Results:**

- Folders scanned: 64,583
- Files counted: 295,681
- Size counted: ~883,599 MB
- Recycle/system trash zones skipped
- Errors logged and scan continued
- No files were modified

**Reports location:** `C:\Users\jim\Desktop\DrivePathInventory`

**Known important buckets found:**

- `I:\recover`
- `I:\1tbrecover`
- `I:\1tbrecover\oldusers\jim`
- `I:\1tbrecover\DisDain_PSTs`
- `I:\1tbrecover\mp3_old_looks_like_Google_Play_Music`
- `I:\1tbrecover\obsvideos`

#### 2. File naming model clarified

Recovered/carved files may look like:

```text
I:\recover\PNG_Pics\file602.png
```

Real named files may exist elsewhere, such as:

```text
I:\SomeRealFolder\Pepe_in_yard.png
```

If both have the same hash, they are duplicate content.

**Important:**

- The real named original stays untouched.
- The recovered generic file also stays untouched unless Jim later approves otherwise.

**Later duplicate staging format:**

```text
hash.file602.Pepe_in_yard.png
```

**Example staged duplicate/evidence file (future move-based staging):**

```text
I:\recover\_duplicates\A94F3C21.file602.Pepe_in_yard.png
```

**Staging policy (Jim, 2026-07-03):**

- **Next phase: move/stage planning only** — no execution without Jim approval
- **No copy-based staging** — copying creates more mess and uses space
- **Future staging: move** approved recovered duplicate files into staged folders
- **Do not delete** files
- **Do not move** real-named keeper files unless Jim explicitly approves
- Use saved hashes and **move manifests** to prove original path, destination path, and content integrity
- No destructive operation is approved
- **Design spec:** see `STAGING_SPEC.md` — `Move-RecoveredToRealnameMatches.ps1` v0.1.0/v0.1.1 (DryRun planning passed Codex Sparky review; `-Execute` not approved)

**Meaning:**

- `A94F3C21` = short hash proof
- `file602` = recovered generic filename
- `Pepe_in_yard` = matched real original filename
- `.png` = file extension

#### 3. Hash Scout designed and built

**Script:** `I:\DrivePathScout-RedneckMaestro\Get-DriveFileHashes.ps1` (v0.1.5)

**Purpose:** Hash candidate personal files and produce reports for duplicate matching.

**Default source:** `I:\`

**Default report root:** `C:\Users\jim\Desktop\DrivePathInventory`

**Reports:**

- `file_hashes_*.csv`
- `duplicate_hash_groups_*.csv`
- `interesting_duplicate_groups_*.csv` — triage report; filters low-value app/icon duplicates
- `recovered_to_realname_matches_*.csv`
- `hash_scan_log_*.txt`

**Expected behavior:**

- Read-only
- `-DryRun` enumerates candidates without hashing
- `-MaxFiles` limits test runs (normal mode)
- `-BalancedSample` collects up to `-MaxFilesPerBucket` per bucket for representative small tests
- Hashing uses SHA-256 by default
- Reparse points/junctions/symlinks skipped
- Recycle/system/cache folders skipped
- Errors logged and scan continues

#### 4. Codex reported validation passed

**Reported tests:**

- Empty dry run and header-only reports
- One-file SHA-256 hash
- Correct 64-character hash
- No source modification
- No full scan of `I:\` yet

#### 5. Hash Scout balanced sample — PASSED (v0.1.5, 2026-07-02)

**Command run:**

```powershell
.\Get-DriveFileHashes.ps1 -BalancedSample -MaxFilesPerBucket 100
```

**Results:**

- Eligible matching files examined during enumeration: 155,184 (after extension and minimum-size filters)
- Balanced sample selected: 658
- Files hashed: 658
- Duplicate hash groups: 33
- Interesting duplicate groups: **16**
- Recovered-to-realname matches: 1
- Runtime: 00:19:01
- READ-ONLY RUN: no files were modified

**Bucket counts:**

| Bucket | Count |
|---|---|
| RecoveredGeneric | 100 |
| OldUserProfile | 100 |
| PSTMail | 63 |
| Photos | 100 |
| Videos | 37 |
| Music | 100 |
| Documents | 100 |
| Archives | 58 |
| Other | 0 |

**Confirmed high-interest recovered-to-real match:**

- Hash: `0E7A20EC6532A0FCEFC5BA8EFEBDF0BE6AA31DB07A88040613EA44ECCC928A6D`
- RecoveredPath: `I:\recover\PNG_Pics\11-8-2012 11-02-29 AM.png`
- RealNamedPath: `I:\1tbrecover\prevdrivestuff\Pictures\phx.suns.png`
- SuggestedDuplicateName: `0E7A20EC.11-8-2012 11-02-29 AM.phx.suns.png`

**Interesting report behavior (v0.1.5):**

- `duplicate_hash_groups_*.csv` stayed complete at 33 groups
- `interesting_duplicate_groups_*.csv` reduced to 16 groups
- Tiny UI/app/browser/icon junk dropped out
- Recovered-to-realnamed and large personal/media/archive/doc groups stayed in

**Verdict:**

- Read-only safety: **passed**
- Balanced sampling: **passed**
- Recovered-to-realname matching: **passed**
- Interesting duplicate triage: **passed**
- **v0.1.5 approved for read-only reporting tests**

**Earlier test history:**

- **v0.1.3 balanced sample:** 658 hashed, 33 duplicate groups, 1 match; reporting fixes
- **v0.1.4 interesting report:** added but too broad (33/33 interesting)
- **v0.1.5 interesting tuning:** 16/33 interesting — triage working
- **500-file normal test:** proved `-MaxFiles` alone is not representative

#### 5c. Hash Scout full read-only scan — COMPLETED (v0.1.5, 2026-07-03)

**Command run:**

```powershell
.\Get-DriveFileHashes.ps1
```

**Report stamp:** `20260703-004335`

**Transcript:** `C:\Users\jim\Desktop\DrivePathInventory\overnight_full_hash_run_20260703-004334.txt`

**Reports location:** `C:\Users\jim\Desktop\DrivePathInventory`

- `file_hashes_20260703-004335.csv`
- `duplicate_hash_groups_20260703-004335.csv`
- `interesting_duplicate_groups_20260703-004335.csv`
- `recovered_to_realname_matches_20260703-004335.csv`
- `hash_scan_log_20260703-004335.txt`

**Results:**

- Candidate files found: 155,184
- Files hashed: 155,184
- Duplicate hash groups: 40,693
- Interesting duplicate groups: 19,835
- Recovered-to-realname match rows: 1,590
- Runtime: ~03:20:03 (00:43:35 → 04:03:38)
- **READ-ONLY RUN: no source files were modified**

**Bucket counts (hashed files):**

| Bucket | Count |
|---|---|
| RecoveredGeneric | 151,460 |
| OldUserProfile | 2,072 |
| Documents | 997 |
| Music | 327 |
| Photos | 170 |
| PSTMail | 63 |
| Archives | 58 |
| Videos | 37 |
| Other | 0 |

**Confirmed high-interest recovered-to-real match (same as balanced sample):**

- Hash: `0E7A20EC6532A0FCEFC5BA8EFEBDF0BE6AA31DB07A88040613EA44ECCC928A6D`
- RecoveredPath: `I:\recover\PNG_Pics\11-8-2012 11-02-29 AM.png`
- RealNamedPath: `I:\1tbrecover\prevdrivestuff\Pictures\phx.suns.png`
- SuggestedDuplicateName: `0E7A20EC.11-8-2012 11-02-29 AM.phx.suns.png`

**Verdict:**

- Full `I:\` read-only hash scan: **completed**
- Read-only safety: **confirmed** — enumerate + `Get-FileHash` only; reports written to Desktop `ReportRoot`
- No move, copy, rename, delete, or source modification occurred

**Current approvals:**

- v0.1.5 read-only reporting: **completed on full `I:\`**
- Move/stage **planning**: next phase (Jim approval required before any action)
- **Move-based staging only** when approved — no copy-based staging
- Move/stage **execution**: **not approved**
- Delete: **not approved**
- Move real-named keeper files: **not approved** unless Jim explicitly approves
- Rename/move/delete cleanup: **not approved**
- Any destructive operation: **not approved**

**Observed insight (Codex Sparky, read-only review):**

`BalancedSample` is bucket-balanced but **not randomized**. It selects first-encountered files by traversal order. Because the `Other` bucket found zero files, the script walked the whole eligible tree trying to fill that bucket — which explains why enumeration examined **155,184 eligible matching files** (after extension and minimum-size filters) and took about **19 minutes**.

#### 5b. Interesting duplicate triage report (v0.1.4–v0.1.5)

**v0.1.4:** Added `interesting_duplicate_groups_*.csv` and `-MinInterestingBytes` (default 50000).

**v0.1.5:** Tuned filtering — validated on balanced sample (33 → 16 interesting groups). Tiny `.png`/`.gif` and personal-folder paths no longer qualify alone. `InterestLevel` column: High / Medium / Low.

Still read-only; no staging/copy/delete.

**Not approved:** staging/copy execution, rename/move/delete cleanup.

#### 6. Cursor safety review (2026-07-02)

**Verdict:** Safe for controlled test runs.

**Checked:**

- Script remains read-only (enumerate + `Get-FileHash` only; writes reports to `ReportRoot`)
- `I:\` is default `SourceRoot`
- `ReportRoot` defaults outside `SourceRoot` with guard if inside
- `-DryRun` skips hashing (`Hash` column empty; duplicate/match reports empty)
- `-MaxFiles` limits candidate enumeration when passed (normal mode only)
- `-BalancedSample` collects per-bucket samples without move/copy/rename/delete
- No move/copy/rename/delete/stage behavior
- Duplicate report: only hash groups with `Count > 1`
- Match report: only groups with both a recovered-side file (generic name, recover path, or recognized carved stem) and a real-named file
- `SuggestedDuplicateName` format: `{first8ofHash}.{recoveredStem}.{safeRealStem}{ext}`

**Patch (2026-07-02):** Added `-BalancedSample` and `-MaxFilesPerBucket` after 500-file test showed all-RecoveredGeneric sample.

**Patch (2026-07-02 v0.1.2):** Fixed recovered-to-realname matching. Matcher was too narrow — only `file602`-style stems counted as recovered. This drive uses `I:\recover\` paths and carved names like `ratesheet1[1808].tif`, so 33 duplicate groups produced 0 matches. Matcher now treats recover-path files, carved stems, and generic stems as recovered side.

**Patch (2026-07-02 v0.1.3):** Fixed balanced-sample console reporting and `BalancedMode` switch parameter crash during hashing phase.

**Patch (2026-07-02 v0.1.4):** Added `interesting_duplicate_groups_*.csv` triage report and `-MinInterestingBytes` parameter.

**Patch (2026-07-02 v0.1.5):** Tuned interesting report — tiny PNG/GIF/app assets no longer qualify from `PersonalExtension`/`PersonalFolderPath` alone.

**Files changed:** `Get-DriveFileHashes.ps1`, `NOTES.md`

**Tested:** Hash Scout v0.1.5 balanced sample — Jim run passed (658 hashed, 33 duplicate groups, 16 interesting groups, 1 recovered-to-realname match, read-only confirmed, 00:19:01).

**Safe next step:** DryRun preflight planning is trusted. Re-run DryRun with `-Limit` as needed. **Do not run `-Execute`.** Pending another Codex Sparky Execute review and Jim approval after v0.1.1 safety fixes.

#### 6b. Move staging Codex Sparky review (2026-07-03)

**Script:** `Move-RecoveredToRealnameMatches.ps1` v0.1.0 → v0.1.1

**Codex Sparky safety verdict:**

- **DryRun planning:** passed
- **Execute:** not approved

**Execute-blocking issues addressed in v0.1.1:**

- Crash-safe execution journal (`move_execution_journal_*.csv` on C:\ ReportRoot)
- Fresh keeper hash recompute immediately before each move (no preflight cache gate on Execute)
- Reparse-point rejection (`SourceReparsePoint`) on source and destination paths
- `-WhatIf` non-mutating destination folder creation (behind `ShouldProcess`)

**Not approved yet:**

- `Move-RecoveredToRealnameMatches.ps1` **-Execute** (moves)
- Move/stage **execution**
- Copy-based staging
- Delete
- Move real-named keeper files (unless Jim explicitly approves)
- Rename/move/delete cleanup
- Any destructive operation

#### 7. Maestro status

**Current phase:** Full `I:\` read-only hash scan **completed** (20260703-004335). Move staging DryRun planning **passed** Codex Sparky review. v0.1.1 execute safety hardening applied. **`-Execute` remains blocked** pending re-review and Jim approval.

**Completed:**

- Path Scout full `I:\` inventory
- Hash Scout v0.1.5 balanced sample validation
- Hash Scout v0.1.5 full read-only `I:\` hash scan (155,184 candidates found and hashed; 40,693 duplicate groups; 19,835 interesting groups; 1,590 recovered-to-realname match rows)
- Private GitHub repo initialized (`jimmcguffinus/DrivePathScout-RedneckMaestro`)
- Move-only staging design spec (`STAGING_SPEC.md`)
- `Move-RecoveredToRealnameMatches.ps1` v0.1.0 implemented (DryRun preflight; tested)
- `Move-RecoveredToRealnameMatches.ps1` v0.1.1 execute safety hardening (journal, fresh keeper hash, reparse, WhatIf)
- Codex Sparky DryRun planning review passed

**Not yet approved:**

- `Move-RecoveredToRealnameMatches.ps1` **-Execute** (moves)
- Codex Sparky Execute approval (pending re-review after v0.1.1)
- Move/stage **execution** (planning only for now)
- Copy-based staging
- Delete
- Move real-named keeper files (unless Jim explicitly approves)
- Rename/move/delete cleanup
- Any destructive operation

---

## Team culture — Curiosity with Guardrails

During the Hash Scout v0.1.5 review, Codex Sparky showed useful read-only curiosity about the code after Cursor evolved the script from the original scout into balanced sampling and interesting duplicate filtering.

Jim noticed the “unfinished pattern” feeling and explicitly allowed Codex Sparky to inspect the code read-only.

**Lesson:** Curiosity is welcome when it improves safety, understanding, or architecture review.

**Rule:** Agents may perform read-only review when curiosity would clarify how the system works, but they must **not** make unsupervised changes.

**Allowed:**

- Read-only code inspection
- Safety review
- Architecture notes
- Runtime explanation
- “Smells funny” reports
- Trade-off analysis

**Not allowed without Jim approval:**

- Editing files
- Moving/copying/renaming/deleting data
- Adding staging behavior
- Cleanup automation
- Destructive operations
- Helpful refactors outside the task

**Team principle:** Curiosity plus read-only access is good. Curiosity plus bulldozer keys is not.

**Preferred behavior:** When an agent feels a useful pull to inspect code, it should say so, explain why, and wait for Jim's go-ahead unless the task already grants read-only review.

**Short version:** Let the agents be curious. Keep the seatbelts on.

---

## Safety law

- No move
- No copy from SourceRoot
- No rename
- No delete
- No write to SourceRoot
- Skip reparse points and junctions
- Skip known Windows system-trash zones
- Log errors and continue
- Keep report output outside SourceRoot

Long paths are not rewritten with an aggressive `\\?\` prefix in this release. Failures are logged and scanning continues.

---

## Team rule

After each meaningful change, update this file with:

- What changed
- Files changed
- What was tested
- Safe next command
- What is still not approved
