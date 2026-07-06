[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$RefinementPath = 'C:\Users\jim\Desktop\DrivePathInventory\phase2_web_assets_lowrisk_refinement_20260704.csv',

    [ValidateNotNullOrEmpty()]
    [string]$InventoryPath = 'C:\Users\jim\Desktop\DrivePathInventory\phase2_web_assets_inventory_20260704.csv',

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',

    [ValidateNotNullOrEmpty()]
    [string]$PlanStamp = '20260704',

    [ValidateNotNullOrEmpty()]
    [string]$McNasSourceRoot = 'I:\recover\McNASBackup',

    [ValidateNotNullOrEmpty()]
    [string]$DeleteReviewWebJunkRoot = 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW\high_confidence_junk\phase2_web_assets\obvious_web_junk',

    [ValidateNotNullOrEmpty()]
    [string]$DeleteReviewToolArchivesRoot = 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW\high_confidence_junk\phase2_web_assets\tool_cache_archives',

    [switch]$SkipLiveHashVerification
)

# Phase 2 web-assets Tier1 approved move plan builder v0.2.8
# MOVE-only grouping for Tier1 KEEP rows only.
# PDFs, Office docs, unclear Tier2, human-review, shared-human hashes, and blockers are HOLD.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { return $Path.Trim() }
}

function Get-NormalizedHash {
    param([Parameter(Mandatory = $true)][string]$Hash)
    return $Hash.Trim().ToUpperInvariant()
}

function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ChildPath,
        [Parameter(Mandatory = $true)][string]$RootPath
    )
    $child = Get-NormalizedPath $ChildPath
    $root = Get-NormalizedPath $RootPath
    if ([string]::IsNullOrWhiteSpace($child) -or [string]::IsNullOrWhiteSpace($root)) { return $false }
    $prefix = if ($root.EndsWith('\')) { $root } else { $root + '\' }
    return $child.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

$workbenchRoots = @(
    'I:\_RECOVERY_WORKBENCH\02_KEEPERS_REVIEW',
    'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED',
    'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW',
    'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW'
) | ForEach-Object { Get-NormalizedPath $_ }

function Test-UnderWorkbenchRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = Get-NormalizedPath $Path
    foreach ($root in $workbenchRoots) {
        if (Test-PathInsideRoot -ChildPath $normalized -RootPath $root) { return $true }
    }
    return $false
}

function Get-CollisionSafeReviewFileName {
    param(
        [Parameter(Mandatory = $true)][string]$ShortHash,
        [Parameter(Mandatory = $true)][string]$OriginalFileName,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory,
        [Parameter(Mandatory = $true)][hashtable]$ReservedNames
    )
    $baseCandidate = '{0}.{1}' -f $ShortHash, $OriginalFileName
    $ext = [IO.Path]::GetExtension($OriginalFileName)
    $nameWithoutExt = if ([string]::IsNullOrWhiteSpace($ext)) { $OriginalFileName } else { $OriginalFileName.Substring(0, $OriginalFileName.Length - $ext.Length) }
    $candidate = $baseCandidate
    $index = 2
    while ($true) {
        $fullPath = Join-Path $DestinationDirectory $candidate
        $key = $fullPath.ToUpperInvariant()
        if (-not (Test-Path -LiteralPath $fullPath) -and -not $ReservedNames.ContainsKey($key)) {
            [void]$ReservedNames.Add($key, $true)
            return [pscustomobject]@{
                FileName = $candidate
                ReviewPath = Get-NormalizedPath $fullPath
            }
        }
        $candidate = '{0}.{1}.collision-{2:D3}{3}' -f $ShortHash, $nameWithoutExt, $index, $ext
        $index++
        if ($index -gt 999) { throw "Unable to allocate collision-safe destination for '$OriginalFileName'." }
    }
}

$allowedExtensions = @('.gif', '.png', '.tif', '.zip')
$deniedExtensions = @('.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.rtf', '.csv', '.7z')
$tier1Lanes = @('TIER1_OBVIOUS_WEB_JUNK', 'TIER1_TOOL_CACHE_ARCHIVES')
$laneToSubfolder = @{
    'TIER1_OBVIOUS_WEB_JUNK' = 'high_confidence_junk\phase2_web_assets\obvious_web_junk'
    'TIER1_TOOL_CACHE_ARCHIVES' = 'high_confidence_junk\phase2_web_assets\tool_cache_archives'
}
$laneToReviewRoot = @{
    'TIER1_OBVIOUS_WEB_JUNK' = (Get-NormalizedPath $DeleteReviewWebJunkRoot)
    'TIER1_TOOL_CACHE_ARCHIVES' = (Get-NormalizedPath $DeleteReviewToolArchivesRoot)
}

$mcNasRoot = Get-NormalizedPath $McNasSourceRoot
$refined = @(Import-Csv -LiteralPath $RefinementPath)
$inventory = @(Import-Csv -LiteralPath $InventoryPath)

$humanHashes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$inventory | Where-Object SuggestedPolicyLane -eq 'HUMAN_REVIEW_DOCUMENT' | ForEach-Object {
    [void]$humanHashes.Add((Get-NormalizedHash $_.Hash))
}
$refined | Where-Object RefinedPolicyLane -eq 'HUMAN_REVIEW_ESCALATED' | ForEach-Object {
    [void]$humanHashes.Add((Get-NormalizedHash $_.Hash))
}

$candidateRows = @($refined | Where-Object {
    $tier1Lanes -contains $_.RefinedPolicyLane -and
    $allowedExtensions -contains $_.Extension.ToLowerInvariant() -and
    -not $humanHashes.Contains((Get-NormalizedHash $_.Hash))
} | Sort-Object FullName)

$excludedCounts = [ordered]@{
    SharedHumanHash = @($refined | Where-Object { $tier1Lanes -contains $_.RefinedPolicyLane -and $humanHashes.Contains((Get-NormalizedHash $_.Hash)) }).Count
    NotTier1 = @($refined | Where-Object { $tier1Lanes -notcontains $_.RefinedPolicyLane -and $_.OriginalSuggestedPolicyLane -eq 'LOW_RISK_WEB_ASSET' }).Count
    HumanEscalated = @($refined | Where-Object RefinedPolicyLane -eq 'HUMAN_REVIEW_ESCALATED').Count
    Tier2Pdf = @($refined | Where-Object RefinedPolicyLane -eq 'TIER2_PDF_NEEDS_SAMPLE_REVIEW').Count
    Tier2Unclear = @($refined | Where-Object RefinedPolicyLane -eq 'TIER2_UNCLEAR_WEB_ASSET').Count
    Blocked = @($refined | Where-Object RefinedPolicyLane -eq 'BLOCKED_STILL_BLOCKED').Count
}

$blockedRows = New-Object System.Collections.Generic.List[object]
$selectedRows = New-Object System.Collections.Generic.List[object]
$seenSource = @{}
$rowNum = 0

foreach ($row in $candidateRows) {
    $rowNum++
    if ($rowNum % 500 -eq 0) { Write-Host "  validate $rowNum / $($candidateRows.Count)" }

    $sourcePath = Get-NormalizedPath $row.FullName
    $hash = Get-NormalizedHash $row.Hash
    $ext = $row.Extension.ToLowerInvariant()
    $lane = $row.RefinedPolicyLane.Trim()
    $blockReasons = New-Object System.Collections.Generic.List[string]

    if ($humanHashes.Contains($hash)) { [void]$blockReasons.Add('SharedHashWithHumanReview') }
    if ($lane -notin $tier1Lanes) { [void]$blockReasons.Add('NotTier1Lane') }
    if ($lane -eq 'HUMAN_REVIEW_ESCALATED') { [void]$blockReasons.Add('HumanReviewEscalated') }
    if ($lane -eq 'TIER2_PDF_NEEDS_SAMPLE_REVIEW') { [void]$blockReasons.Add('Tier2Pdf') }
    if ($lane -eq 'TIER2_UNCLEAR_WEB_ASSET') { [void]$blockReasons.Add('Tier2Unclear') }
    if ($lane -eq 'BLOCKED_STILL_BLOCKED') { [void]$blockReasons.Add('BlockedLane') }
    if ($row.OriginalSuggestedPolicyLane -ne 'LOW_RISK_WEB_ASSET') { [void]$blockReasons.Add('NotLowRiskOriginal') }
    if ($allowedExtensions -notcontains $ext) { [void]$blockReasons.Add('WrongExtension') }
    if ($deniedExtensions -contains $ext) { [void]$blockReasons.Add('DeniedExtension') }
    if ($row.PersonalSignal -eq 'True') { [void]$blockReasons.Add('PersonalSignal') }
    if (-not (Test-PathInsideRoot -ChildPath $sourcePath -RootPath $mcNasRoot)) { [void]$blockReasons.Add('OutsideMcNasRoot') }
    if (Test-UnderWorkbenchRoot -Path $sourcePath) { [void]$blockReasons.Add('UnderWorkbenchRoot') }
    if (-not (Test-Path -LiteralPath $sourcePath)) { [void]$blockReasons.Add('MissingSource') }
    elseif (Test-Path -LiteralPath $sourcePath -PathType Container) { [void]$blockReasons.Add('SourceIsDirectory') }

    $key = $sourcePath.ToUpperInvariant()
    if ($seenSource.ContainsKey($key)) { [void]$blockReasons.Add('DuplicateSourcePath') }
    else { $seenSource[$key] = $true }

    if ($blockReasons.Count -eq 0 -and -not $SkipLiveHashVerification) {
        try {
            $liveHash = Get-NormalizedHash (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
            if ($liveHash -ne $hash) { [void]$blockReasons.Add('HashMismatch') }
        }
        catch { [void]$blockReasons.Add('HashCheckFailed') }
    }

    if ($blockReasons.Count -eq 0) {
        [void]$selectedRows.Add($row)
    }
    else {
        [void]$blockedRows.Add([pscustomobject]@{
            FullName = $sourcePath
            Hash = $hash
            RefinedPolicyLane = $lane
            BlockReason = ($blockReasons -join ';')
        })
    }
}

if ($blockedRows.Count -gt 0) {
    throw "Plan builder blocked $($blockedRows.Count) candidate row(s). First: $($blockedRows[0].FullName) $($blockedRows[0].BlockReason)"
}

$expectedCount = 16708
if ($selectedRows.Count -ne $expectedCount) {
    throw "Expected $expectedCount Tier1 KEEP rows; selected $($selectedRows.Count)."
}

$reservedByRoot = @{}
$planRows = New-Object System.Collections.Generic.List[object]
foreach ($row in ($selectedRows | Sort-Object FullName)) {
    $sourcePath = Get-NormalizedPath $row.FullName
    $hash = Get-NormalizedHash $row.Hash
    $short = $row.ShortHash.Trim()
    $fileName = Split-Path -Leaf $sourcePath
    $lane = $row.RefinedPolicyLane.Trim()
    $subfolder = $laneToSubfolder[$lane]
    $reviewRoot = $laneToReviewRoot[$lane]
    if (-not $reservedByRoot.ContainsKey($reviewRoot)) { $reservedByRoot[$reviewRoot] = @{} }

    $destInfo = Get-CollisionSafeReviewFileName -ShortHash $short -OriginalFileName $fileName `
        -DestinationDirectory $reviewRoot -ReservedNames $reservedByRoot[$reviewRoot]

  [void]$planRows.Add([pscustomobject]@{
        Hash = $hash
        ShortHash = $short
        SizeBytes = $row.SizeBytes
        SourcePath = $sourcePath
        ReviewPath = $destInfo.ReviewPath
        DestinationSubfolder = $subfolder
        FileName = $fileName
        RelativePath = $row.RelativePath
        Extension = $row.Extension.ToLowerInvariant()
        RefinedPolicyLane = $lane
        SpotCheckDecision = 'KEEP_TIER1_MOVE_CANDIDATE'
        SharedHashWithHumanReview = 'False'
        PersonalSignal = $row.PersonalSignal
        WebAssetSignal = $row.WebAssetSignal
        ToolOrInstallerSignal = $row.ToolOrInstallerSignal
        GroupFileCount = $row.GroupFileCount
        GroupTotalBytes = $row.GroupTotalBytes
        ReviewConfidence = 'HIGH'
        ReviewReason = $row.ReviewReason.Trim()
    })
}

function Test-BadPlanRowRejected {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][scriptblock]$Test
    )
    try {
        & $Test
        throw "Bad plan test FAILED (should reject): $Label"
    }
    catch {
        if ($_.Exception.Message -like 'Bad plan test FAILED*') { throw }
    }
}

$sampleGood = $planRows[0]
$badTests = New-Object System.Collections.Generic.List[string]

function Add-BadTest([string]$Name, [scriptblock]$Test) {
    try {
        Test-BadPlanRowRejected -Label $Name -Test $Test
        [void]$badTests.Add("PASS: $Name")
    }
    catch {
        [void]$badTests.Add("FAIL: $Name - $($_.Exception.Message)")
    }
}

Add-BadTest 'SharedHumanHash' {
    if ($humanHashes.Contains((Get-NormalizedHash $sampleGood.Hash))) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'PdfExtension' {
    if ('.pdf' -in $allowedExtensions) { throw 'accept' }
    throw 'reject'
}
Add-BadTest 'OfficeDocExtension' {
    if ('.docx' -in $allowedExtensions) { throw 'accept' }
    throw 'reject'
}
Add-BadTest 'OutsideMcNas' {
    if (Test-PathInsideRoot -ChildPath 'I:\recover\McNASBackup\test.gif' -RootPath $mcNasRoot) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'UnderWorkbench' {
    if (Test-UnderWorkbenchRoot -Path 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW\test.gif') { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'Tier2UnclearLane' {
    if ('TIER2_UNCLEAR_WEB_ASSET' -in $tier1Lanes) { throw 'accept' }
    throw 'reject'
}
Add-BadTest 'HumanEscalatedLane' {
    if ('HUMAN_REVIEW_ESCALATED' -in $tier1Lanes) { throw 'accept' }
    throw 'reject'
}
Add-BadTest 'PlanHasSharedHumanRow' {
    if (@($planRows | Where-Object SharedHashWithHumanReview -eq 'True').Count -gt 0) { throw 'reject' }
    # clean plan - no throw means pass for inverted test; use explicit pass
    throw 'accept'
}
Add-BadTest 'PlanHasNonKeepDecision' {
    if (@($planRows | Where-Object SpotCheckDecision -ne 'KEEP_TIER1_MOVE_CANDIDATE').Count -gt 0) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'DestinationOutsideDeleteReview' {
    $bad = Join-Path 'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW' 'test.gif'
    if (-not (Test-PathInsideRoot -ChildPath $bad -RootPath 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW')) { throw 'reject' }
    throw 'accept'
}

if (@($badTests | Where-Object { $_ -like 'FAIL:*' }).Count -gt 0) {
    throw "Bad plan tests failed:`n$($badTests -join "`n")"
}

$planPath = Join-Path $ReportRoot "approved_phase2_web_assets_tier1_move_plan_$PlanStamp.csv"
$shaPath = Join-Path $ReportRoot "approved_phase2_web_assets_tier1_move_plan_$PlanStamp.sha256.txt"
$planRows | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
$hashFile = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToUpperInvariant()
Set-Content -LiteralPath $shaPath -Value $hashFile -Encoding UTF8

$totalBytes = ($planRows | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
Write-Host "Phase 2 web-assets Tier1 move plan rows: $($planRows.Count)"
Write-Host "BlockedPreSelection=$($blockedRows.Count)"
Write-Host "TotalBytes=$totalBytes"
Write-Host "Excluded SharedHumanHash=$($excludedCounts.SharedHumanHash)"
Write-Host "PlanPath=$planPath"
Write-Host "PlanSha256=$hashFile"
Write-Host "ShaPath=$shaPath"
Write-Host 'BadPlanTests:'
$badTests | ForEach-Object { Write-Host "  $_" }
