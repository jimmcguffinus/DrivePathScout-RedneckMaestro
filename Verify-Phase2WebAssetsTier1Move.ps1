[CmdletBinding()]
param(
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [string]$Stamp = '20260704',
    [string]$ExpectedPlanHash = '614B9B7CA17642322F00949A8B66389059B5B5B4E00288E89203E2F40616EDE7',
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

$planPath = Join-Path $ReportRoot "approved_phase2_web_assets_tier1_move_plan_$Stamp.csv"
$manifestPath = Join-Path $ReportRoot "phase2_web_assets_tier1_move_manifest_$Stamp.csv"
$journalPath = Join-Path $ReportRoot "phase2_web_assets_tier1_move_journal_$Stamp.csv"
$refinementPath = Join-Path $ReportRoot "phase2_web_assets_lowrisk_refinement_$Stamp.csv"
$inventoryPath = Join-Path $ReportRoot "phase2_web_assets_inventory_$Stamp.csv"
$verificationOut = Join-Path $ReportRoot "phase2_web_assets_tier1_move_verification_$Stamp.txt"
$snapshotCsv = Join-Path $ReportRoot "workbench_after_phase2_web_assets_snapshot_$Stamp.csv"
$snapshotSummary = Join-Path $ReportRoot "workbench_after_phase2_web_assets_snapshot_summary_$Stamp.txt"

$webJunkRoot = 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW\high_confidence_junk\phase2_web_assets\obvious_web_junk'
$toolArchRoot = 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW\high_confidence_junk\phase2_web_assets\tool_cache_archives'
$humanReviewRoot = 'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW'
$allowedDestExt = @('.gif', '.png', '.tif', '.zip')
$deniedDestExt = @('.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.rtf')

$plan = @(Import-Csv -LiteralPath $planPath)
$manifest = @(Import-Csv -LiteralPath $manifestPath)
$journal = @(Import-Csv -LiteralPath $journalPath)
$refinement = Import-Csv -LiteralPath $refinementPath
$inventory = Import-Csv -LiteralPath $inventoryPath

$planHash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToUpperInvariant()
$issues = New-Object System.Collections.Generic.List[string]
$checks = New-Object System.Collections.Generic.List[string]

function Add-Check([string]$name, [bool]$ok, [string]$detail) {
    $status = if ($ok) { 'PASS' } else { 'FAIL' }
    [void]$checks.Add("$status`t$name`t$detail")
    if (-not $ok) { [void]$issues.Add("${name}: $detail") }
}

Add-Check 'PlanRowCount' ($plan.Count -eq 16708) "plan=$($plan.Count) expected=16708"
Add-Check 'ManifestRowCount' ($manifest.Count -eq 16708) "manifest=$($manifest.Count)"
Add-Check 'PlanSha256' ($planHash -eq $ExpectedPlanHash.ToUpperInvariant()) "actual=$planHash"

$movedVerified = @($journal | Where-Object { $_.Status -eq 'MOVED_VERIFIED' })
$moveFailed = @($journal | Where-Object { $_.Status -match 'FAIL|ERROR' })
Add-Check 'JournalMovedVerified' ($movedVerified.Count -eq 16708) "count=$($movedVerified.Count)"
Add-Check 'JournalMoveFailed' ($moveFailed.Count -eq 0) "failed=$($moveFailed.Count)"
Add-Check 'ManifestMovedVerified' (@($manifest | Where-Object ExecutionStatus -eq 'MovedVerified').Count -eq 16708) "count=$(@($manifest | Where-Object ExecutionStatus -eq 'MovedVerified').Count)"

$journalBySource = @{}
foreach ($j in $movedVerified) {
    $k = (Get-NormPath $j.StagedDuplicatePath).ToUpperInvariant()
    $journalBySource[$k] = $j
}

$missingDest = 0; $sizeMismatch = 0; $hashMismatch = 0; $sourceStillExists = 0
$i = 0
foreach ($row in $plan) {
    $i++
    if ($i % 1000 -eq 0) { Write-Host "  verify $i / $($plan.Count)" }
    $src = Get-NormPath $row.SourcePath
    $dest = Get-NormPath $row.ReviewPath
    $expectedHash = Get-NormHash $row.Hash
    $expectedSize = [int64]$row.SizeBytes

    if (Test-Path -LiteralPath $src) { $sourceStillExists++ }
    if (-not (Test-Path -LiteralPath $dest)) { $missingDest++; continue }
    $item = Get-Item -LiteralPath $dest -Force
    if ([int64]$item.Length -ne $expectedSize) { $sizeMismatch++ }

    $jRow = $journalBySource[$src.ToUpperInvariant()]
    if ($null -eq $jRow) { $hashMismatch++; continue }
    if ((Get-NormHash $jRow.ReviewHashAfter) -ne $expectedHash) { $hashMismatch++ }

    if ($VerifyLiveDestinationHash) {
        $live = Get-NormHash (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
        if ($live -ne $expectedHash) { $hashMismatch++ }
    }
}

Add-Check 'ReviewPathExists' ($missingDest -eq 0) "missing=$missingDest"
Add-Check 'ReviewPathSizeMatch' ($sizeMismatch -eq 0) "mismatch=$sizeMismatch"
Add-Check 'ReviewPathHashMatch' ($hashMismatch -eq 0) "mismatch=$hashMismatch"
Add-Check 'SourcePathGone' ($sourceStillExists -eq 0) "stillExists=$sourceStillExists"

$webJunkFiles = @(Get-ChildItem -LiteralPath $webJunkRoot -File -Recurse -ErrorAction SilentlyContinue)
$toolArchFiles = @(Get-ChildItem -LiteralPath $toolArchRoot -File -Recurse -ErrorAction SilentlyContinue)
Add-Check 'DestWebJunkCount' ($webJunkFiles.Count -eq 16651) "count=$($webJunkFiles.Count)"
Add-Check 'DestToolArchCount' ($toolArchFiles.Count -eq 57) "count=$($toolArchFiles.Count)"

$badExt = @($webJunkFiles + $toolArchFiles | Where-Object {
    $allowedDestExt -notcontains $_.Extension.ToLowerInvariant()
})
$deniedInDest = @($webJunkFiles + $toolArchFiles | Where-Object {
    $deniedDestExt -contains $_.Extension.ToLowerInvariant()
})
$underHuman = @($webJunkFiles + $toolArchFiles | Where-Object {
    (Get-NormPath $_.FullName).StartsWith((Get-NormPath $humanReviewRoot), [StringComparison]::OrdinalIgnoreCase)
})
Add-Check 'DestAllowedExtensionsOnly' ($badExt.Count -eq 0) "badExt=$($badExt.Count)"
Add-Check 'NoPdfInDest' ($deniedInDest.Count -eq 0) "denied=$($deniedInDest.Count)"
Add-Check 'NoDestUnderHumanReview' ($underHuman.Count -eq 0) "under06=$($underHuman.Count)"

$movedSources = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$plan | ForEach-Object { [void]$movedSources.Add((Get-NormPath $_.SourcePath)) }

$holdLanes = @{
    'TIER2_PDF_NEEDS_SAMPLE_REVIEW' = @($refinement | Where-Object RefinedPolicyLane -eq 'TIER2_PDF_NEEDS_SAMPLE_REVIEW')
    'TIER2_UNCLEAR_WEB_ASSET' = @($refinement | Where-Object RefinedPolicyLane -eq 'TIER2_UNCLEAR_WEB_ASSET')
    'HUMAN_REVIEW_ESCALATED' = @($refinement | Where-Object RefinedPolicyLane -eq 'HUMAN_REVIEW_ESCALATED')
}
$holdMoved = 0
foreach ($lane in $holdLanes.Keys) {
    foreach ($r in $holdLanes[$lane]) {
        if ($movedSources.Contains((Get-NormPath $r.FullName))) { $holdMoved++ }
    }
}
$humanInvMoved = @($inventory | Where-Object {
    $_.SuggestedPolicyLane -eq 'HUMAN_REVIEW_DOCUMENT' -and $movedSources.Contains((Get-NormPath $_.FullName))
}).Count
Add-Check 'HoldLanesNotMoved' ($holdMoved -eq 0) "holdRowsMoved=$holdMoved"
Add-Check 'HumanReviewDocumentNotMoved' ($humanInvMoved -eq 0) "humanDocMoved=$humanInvMoved"

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

$subSummary = $snapshotRows | Group-Object SubfolderLane | Sort-Object Count -Descending | Select-Object -First 25 Name, Count

$verdict = if ($issues.Count -eq 0) { 'VERIFIED_PASS' } else { 'VERIFIED_FAIL' }
$lines = @(
    'Phase 2 Web-Assets Tier1 Move Verification Receipt'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "Verdict: $verdict"
    "PlanPath: $planPath"
    "PlanSha256: $planHash"
    "ExpectedPlanSha256: $($ExpectedPlanHash.ToUpperInvariant())"
    ''
    '=== CHECKS ==='
)
$lines += $checks
$lines += ''
$lines += "IssueCount: $($issues.Count)"
if ($issues.Count -gt 0) { $lines += $issues }
$lines += ''
$lines += '=== DESTINATION COUNTS ==='
$lines += "obvious_web_junk=$($webJunkFiles.Count)"
$lines += "tool_cache_archives=$($toolArchFiles.Count)"
$lines += "total_dest=$($webJunkFiles.Count + $toolArchFiles.Count)"
$lines | Set-Content -LiteralPath $verificationOut -Encoding utf8

$sumLines = @(
    'Workbench Snapshot After Phase 2 Web-Assets Tier1 Execute'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "WorkbenchRoot: $wbRoot"
    "TotalFiles: $($snapshotRows.Count)"
    "TotalBytes: $(($snapshotRows | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum)"
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
if ($issues.Count -gt 0) { exit 1 }
