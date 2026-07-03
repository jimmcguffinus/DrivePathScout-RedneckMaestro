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

`Move-RecoveredToRealnameMatches.ps1` v0.1.4 implements move-only staging **preflight** per `STAGING_SPEC.md`. Default mode is DryRun — it does not move, copy, delete, or rename files.

```powershell
.\Move-RecoveredToRealnameMatches.ps1 `
  -MatchCsvPath "C:\Users\jim\Desktop\DrivePathInventory\recovered_to_realname_matches_20260703-004335.csv" `
  -Limit 10
```

v0.1.4 adds ``-OnlyRecoveredPath`` exact targeting and fixes path-chain volume root (`I:\` not `I:`) and typed execute statuses for source validation failures. DryRun planning and the Execute code passed Codex Sparky review. Jim authorized one exact-target pilot on 2026-07-03; it moved and verified one Suns PNG successfully. That authorization is consumed. No second file, batch/full Execute, copy, delete, or cleanup operation is authorized. v0.1 approved recovered move sources remain limited to `I:\recover\`.

## Scope

`Get-DriveUniquePaths.ps1` is an inventory tool, not an organizer. `Move-RecoveredToRealnameMatches.ps1` defaults to DryRun and requires explicit, operation-specific Jim approval before each use of `-Execute`.
