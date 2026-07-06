[CmdletBinding()]
param(
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [string]$Stamp = '20260704',
    [string]$ExpectedPlanHash = '9CCD7D00B413B9F0C63541053CD3F97FC0695896BCFEDBFB351D1FD6A3B8D82D',
    [string]$WorkbenchRoot = 'I:\_RECOVERY_WORKBENCH',
    [switch]$VerifyLiveDestinationHash
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    try { return [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { return $p.Trim() }
}
function Get-NormHash([string]$h) { $h.Trim().ToUpperInvariant() }

function Test-PathInsideRoot {
    param([string]$ChildPath, [string]$RootPath)
    $child = Get-NormPath $ChildPath
    $root = Get-NormPath $RootPath
    if ([string]::IsNullOrWhiteSpace($child) -or [string]::IsNullOrWhiteSpace($root)) { return $false }
    $prefix = if ($root.EndsWith('\')) { $root } else { $root + '\' }
    return $child.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

$planPath = Join-Path $ReportRoot "approved_phase2_mcnasbackup_video_move_extras_plan_$Stamp.csv"
$manifestPath = Join-Path $ReportRoot "phase2_mcnasbackup_video_move_extras_manifest_$Stamp.csv"
$journalPath = Join-Path $ReportRoot "phase2_mcnasbackup_video_move_extras_journal_$Stamp.csv"
$keeperPolicyPath = Join-Path $ReportRoot "phase2_mcnasbackup_video_keeper_policy_sample_$Stamp.csv"
$inventoryPath = Join-Path $ReportRoot "phase2_mcnasbackup_video_duplicate_inventory_$Stamp.csv"
$verificationOut = Join-Path $ReportRoot "phase2_mcnasbackup_video_move_extras_verification_$Stamp.txt"
$snapshotCsv = Join-Path $ReportRoot "workbench_after_phase2_video_extras_snapshot_$Stamp.csv"
$snapshotSummary = Join-Path $ReportRoot "workbench_after_phase2_video_extras_snapshot_summary_$Stamp.txt"

$videoExtrasRoot = 'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW\media\videos\mcnasbackup_duplicate_extras'
$humanReviewRoot = 'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW'
$deleteReviewRoot = 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW'
$videoExt = @('.mp4', '.avi', '.wmv', '.mov', '.mpg', '.mpeg', '.m4v', '.3gp')

$plan = @(Import-Csv -LiteralPath $planPath)
$manifest = @(Import-Csv -LiteralPath $manifestPath)
$journal = @(Import-Csv -LiteralPath $journalPath)
$keeperPolicy = Import-Csv -LiteralPath $keeperPolicyPath
$inventory = Import-Csv -LiteralPath $inventoryPath

$planHash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToUpperInvariant()
$issues = New-Object System.Collections.Generic.List[string]
$checks = New-Object System.Collections.Generic.List[string]

function Add-Check([string]$name, [bool]$ok, [string]$detail) {
    $status = if ($ok) { 'PASS' } else { 'FAIL' }
    [void]$checks.Add("$status`t$name`t$detail")
    if (-not $ok) { [void]$issues.Add("${name}: $detail") }
}

Add-Check 'PlanRowCount' ($plan.Count -eq 650) "plan=$($plan.Count) expected=650"
Add-Check 'ManifestRowCount' ($manifest.Count -eq 650) "manifest=$($manifest.Count)"
Add-Check 'PlanSha256' ($planHash -eq $ExpectedPlanHash.ToUpperInvariant()) "actual=$planHash"

$movedVerified = @($journal | Where-Object { $_.Status -eq 'MOVED_VERIFIED' })
$moveFailed = @($journal | Where-Object { $_.Status -match 'FAIL|ERROR' })
$manifestMoved = @($manifest | Where-Object ExecutionStatus -eq 'MovedVerified')
Add-Check 'JournalMovedVerified' ($movedVerified.Count -eq 650) "count=$($movedVerified.Count)"
Add-Check 'JournalMoveFailed' ($moveFailed.Count -eq 0) "failed=$($moveFailed.Count)"
Add-Check 'ManifestMovedVerified' ($manifestMoved.Count -eq 650) "count=$($manifestMoved.Count)"

$journalBySource = @{}
foreach ($j in $movedVerified) {
    $k = (Get-NormPath $j.StagedDuplicatePath).ToUpperInvariant()
    $journalBySource[$k] = $j
}

$manifestBySource = @{}
foreach ($m in $manifest) {
    $k = (Get-NormPath $m.StagedDuplicatePath).ToUpperInvariant()
    $manifestBySource[$k] = $m
}

$missingDest = 0; $sizeMismatch = 0; $hashMismatch = 0; $sourceStillExists = 0
$destOutsideLane = 0; $manifestDestMismatch = 0
$i = 0
foreach ($row in $plan) {
    $i++
    if ($i % 100 -eq 0) { Write-Host "  verify plan $i / $($plan.Count)" }
    $src = Get-NormPath $row.SourcePath
    $dest = Get-NormPath $row.ReviewPath
    $expectedHash = Get-NormHash $row.Hash
    $expectedSize = [int64]$row.SizeBytes

    if (Test-Path -LiteralPath $src) { $sourceStillExists++ }
    if (-not (Test-PathInsideRoot -ChildPath $dest -RootPath $videoExtrasRoot)) { $destOutsideLane++ }
    if (-not (Test-Path -LiteralPath $dest)) { $missingDest++; continue }

    $item = Get-Item -LiteralPath $dest -Force
    if ([int64]$item.Length -ne $expectedSize) { $sizeMismatch++ }

    $jRow = $journalBySource[$src.ToUpperInvariant()]
    if ($null -eq $jRow) { $hashMismatch++; continue }
    if ((Get-NormHash $jRow.ReviewHashAfter) -ne $expectedHash) { $hashMismatch++ }

    $mRow = $manifestBySource[$src.ToUpperInvariant()]
    if ($null -ne $mRow) {
        if ((Get-NormPath $mRow.PlannedDeleteReviewPath) -ne $dest) { $manifestDestMismatch++ }
        if ([int64]$mRow.SizeBytes -ne $expectedSize) { $sizeMismatch++ }
    }

    if ($VerifyLiveDestinationHash) {
        $live = Get-NormHash (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
        if ($live -ne $expectedHash) { $hashMismatch++ }
    }
}

Add-Check 'ReviewPathExists' ($missingDest -eq 0) "missing=$missingDest"
Add-Check 'ReviewPathUnderExtrasLane' ($destOutsideLane -eq 0) "outside=$destOutsideLane"
Add-Check 'ReviewPathSizeMatch' ($sizeMismatch -eq 0) "mismatch=$sizeMismatch"
Add-Check 'ReviewPathHashMatch' ($hashMismatch -eq 0) "mismatch=$hashMismatch"
Add-Check 'ManifestDestPathMatch' ($manifestDestMismatch -eq 0) "mismatch=$manifestDestMismatch"
Add-Check 'SourcePathGone' ($sourceStillExists -eq 0) "stillExists=$sourceStillExists"

$destFiles = @(Get-ChildItem -LiteralPath $videoExtrasRoot -File -ErrorAction SilentlyContinue)
Add-Check 'DestExtrasFileCount' ($destFiles.Count -eq 650) "count=$($destFiles.Count)"

$badDestExt = @($destFiles | Where-Object { $videoExt -notcontains $_.Extension.ToLowerInvariant() })
Add-Check 'DestVideoExtensionsOnly' ($badDestExt.Count -eq 0) "badExt=$($badDestExt.Count)"

$underDeleteReview = @($destFiles | Where-Object {
    Test-PathInsideRoot -ChildPath $_.FullName -RootPath $deleteReviewRoot
})
Add-Check 'NoDestUnderDeleteReview' ($underDeleteReview.Count -eq 0) "under05=$($underDeleteReview.Count)"

# Keeper safety — unique CandidateKeeperPath per hash group in plan
$keeperByHash = @{}
foreach ($row in $plan) {
    $h = Get-NormHash $row.Hash
    if (-not $keeperByHash.ContainsKey($h)) {
        $keeperByHash[$h] = @{
            KeeperPath = Get-NormPath $row.CandidateKeeperPath
            Hash = $h
        }
    }
}
$keeperMissing = 0; $keeperHashMismatch = 0; $ki = 0
foreach ($kv in $keeperByHash.Values) {
    $ki++
    if ($ki % 50 -eq 0) { Write-Host "  verify keeper $ki / $($keeperByHash.Count)" }
    $kp = $kv.KeeperPath
    $expectedHash = $kv.Hash
    if (-not (Test-Path -LiteralPath $kp)) { $keeperMissing++; continue }
    try {
        $live = Get-NormHash (Get-FileHash -LiteralPath $kp -Algorithm SHA256).Hash
        if ($live -ne $expectedHash) { $keeperHashMismatch++ }
    }
    catch { $keeperMissing++ }
}
Add-Check 'KeeperPathExists' ($keeperMissing -eq 0) "missing=$keeperMissing"
Add-Check 'KeeperPathHashMatch' ($keeperHashMismatch -eq 0) "mismatch=$keeperHashMismatch"

# HOLD group safety
$movedSources = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$plan | ForEach-Object { [void]$movedSources.Add((Get-NormPath $_.SourcePath)) }

$holdLanes = @{
    'HUMAN_REVIEW_SAMPLE_FIRST' = @($keeperPolicy | Where-Object ProposedFutureLane -eq 'HUMAN_REVIEW_SAMPLE_FIRST')
    'MEDIUM_REVIEW_SAMPLE_FIRST' = @($keeperPolicy | Where-Object ProposedFutureLane -eq 'MEDIUM_REVIEW_SAMPLE_FIRST')
    'LOW_RISK_HOLD' = @($keeperPolicy | Where-Object ProposedFutureLane -eq 'LOW_RISK_HOLD')
}
$inventoryByHash = @{}
foreach ($g in ($inventory | Group-Object { Get-NormHash $_.Hash })) {
    $inventoryByHash[(Get-NormHash $g.Name)] = @($g.Group)
}

$holdMoved = 0; $holdMissingOnDisk = 0
foreach ($lane in $holdLanes.Keys) {
    foreach ($grp in $holdLanes[$lane]) {
        $h = Get-NormHash $grp.Hash
        if (-not $inventoryByHash.ContainsKey($h)) { continue }
        foreach ($invRow in $inventoryByHash[$h]) {
            $p = Get-NormPath $invRow.FullName
            if ($movedSources.Contains($p)) { $holdMoved++ }
            if (-not (Test-Path -LiteralPath $p)) { $holdMissingOnDisk++ }
        }
    }
}
Add-Check 'HoldGroupsNotMoved' ($holdMoved -eq 0) "holdRowsMoved=$holdMoved"
Add-Check 'HoldGroupFilesStillOnDisk' ($holdMissingOnDisk -eq 0) "missing=$holdMissingOnDisk"

# Workbench snapshot
Write-Host 'Building workbench snapshot...'
$wbRoot = Get-NormPath $WorkbenchRoot
$snapshotRows = New-Object System.Collections.ArrayList
Get-ChildItem -LiteralPath $wbRoot -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $full = Get-NormPath $_.FullName
    $rel = if ($full.Length -gt $wbRoot.Length) { $full.Substring($wbRoot.Length).TrimStart('\') } else { $_.Name }
    $parts = $rel -split '\\'
    $topLane = if ($parts.Count -gt 0) { $parts[0] } else { '(root)' }
    $subLane = if ($parts.Count -ge 2) { ($parts[0..1] -join '\') } else { $topLane }
    [void]$snapshotRows.Add([pscustomobject]@{
        FullPath = $full
        RelativePath = $rel
        TopLevelLane = $topLane
        SubfolderLane = $subLane
        FileName = $_.Name
        Extension = $_.Extension.ToLowerInvariant()
        SizeBytes = $_.Length
        LastWriteTimeUtc = $_.LastWriteTimeUtc.ToString('o')
    })
}
$snapshotRows | Export-Csv -LiteralPath $snapshotCsv -NoTypeInformation -Encoding utf8

$laneSummary = $snapshotRows | Group-Object TopLevelLane | ForEach-Object {
    [pscustomobject]@{
        Lane = $_.Name
        Files = $_.Count
        Bytes = ($_.Group | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
    }
} | Sort-Object Files -Descending

$videoExtrasCount = @($snapshotRows | Where-Object {
    Test-PathInsideRoot -ChildPath $_.FullPath -RootPath $videoExtrasRoot
}).Count
$videoExtrasBytes = ($snapshotRows | Where-Object {
    Test-PathInsideRoot -ChildPath $_.FullPath -RootPath $videoExtrasRoot
} | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum

$subSummary = $snapshotRows | Group-Object SubfolderLane | Sort-Object Count -Descending | Select-Object -First 25 Name, Count

$verdict = if ($issues.Count -eq 0) { 'VERIFIED_PASS' } else { 'VERIFIED_FAIL' }
$lines = @(
    'Phase 2 McNASBackup Video Move-Extras Verification Receipt'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "Verdict: $verdict"
    "PlanPath: $planPath"
    "PlanSha256: $planHash"
    "ExpectedPlanSha256: $($ExpectedPlanHash.ToUpperInvariant())"
    "ManifestPath: $manifestPath"
    "JournalPath: $journalPath"
    ''
    '=== EXECUTE SUMMARY (from reports) ==='
    'PlanRows=650 MovedVerified=650 MoveFailed=0 TotalBytes=39107870438'
    ''
    '=== CHECKS ==='
)
$lines += $checks
$lines += ''
$lines += "IssueCount: $($issues.Count)"
if ($issues.Count -gt 0) { $lines += $issues }
$lines += ''
$lines += '=== DESTINATION ==='
$lines += "video_extras_root=$videoExtrasRoot"
$lines += "video_extras_file_count=$($destFiles.Count)"
$lines += "video_extras_total_bytes=$videoExtrasBytes"
$lines += ''
$lines += '=== KEEPER SAFETY ==='
$lines += "unique_keeper_groups=$($keeperByHash.Count)"
$lines += "keeper_missing=$keeperMissing"
$lines += "keeper_hash_mismatch=$keeperHashMismatch"
$lines += ''
$lines += '=== HOLD GROUP SAFETY ==='
$lines += "HUMAN_REVIEW_SAMPLE_FIRST_groups=$($holdLanes['HUMAN_REVIEW_SAMPLE_FIRST'].Count)"
$lines += "MEDIUM_REVIEW_SAMPLE_FIRST_groups=$($holdLanes['MEDIUM_REVIEW_SAMPLE_FIRST'].Count)"
$lines += "LOW_RISK_HOLD_groups=$($holdLanes['LOW_RISK_HOLD'].Count)"
$lines += "hold_rows_moved=$holdMoved"
$lines | Set-Content -LiteralPath $verificationOut -Encoding utf8

$sumLines = @(
    'Workbench Snapshot After Phase 2 McNASBackup Video Move-Extras Execute'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "WorkbenchRoot: $wbRoot"
    "TotalFiles: $($snapshotRows.Count)"
    "TotalBytes: $(($snapshotRows | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum)"
    ''
    "VideoExtrasFiles: $videoExtrasCount"
    "VideoExtrasBytes: $videoExtrasBytes"
    ''
    '=== BY TOP-LEVEL LANE ==='
)
$sumLines += $laneSummary | ForEach-Object { "$($_.Lane): files=$($_.Files) bytes=$($_.Bytes)" }
$sumLines += ''
$sumLines += '=== TOP SUBFOLDERS ==='
$sumLines += $subSummary | ForEach-Object { "$($_.Name)`t$($_.Count)" }
$sumLines | Set-Content -LiteralPath $snapshotSummary -Encoding utf8

Write-Host "Verification: $verdict issues=$($issues.Count)"
Write-Host "VerificationOut: $verificationOut"
Write-Host "SnapshotCsv: $snapshotCsv"
Write-Host "SnapshotSummary: $snapshotSummary"
if ($issues.Count -gt 0) { exit 1 }
