[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$KeeperPolicyPath = 'C:\Users\jim\Desktop\DrivePathInventory\phase2_mcnasbackup_video_keeper_policy_sample_20260704.csv',

    [ValidateNotNullOrEmpty()]
    [string]$InventoryPath = 'C:\Users\jim\Desktop\DrivePathInventory\phase2_mcnasbackup_video_duplicate_inventory_20260704.csv',

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',

    [ValidateNotNullOrEmpty()]
    [string]$PlanStamp = '20260704',

    [ValidateNotNullOrEmpty()]
    [string]$McNasSourceRoot = 'I:\recover\McNASBackup',

    [ValidateNotNullOrEmpty()]
    [string]$HumanReviewVideoExtrasRoot = 'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW\media\videos\mcnasbackup_duplicate_extras',

    [switch]$SkipLiveHashVerification
)

# Phase 2 McNASBackup video move-extras approved plan builder v0.2.9
# MOVE-only grouping for HUMAN_REVIEW_MOVE_EXTRAS_READY duplicate extras only.
# CandidateKeeperPath remains in place. Sample-first, medium, low-risk hold, and blocked groups are HOLD.

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

$allowedExtensions = @('.mp4', '.avi', '.wmv', '.mov', '.mpg', '.mpeg', '.m4v', '.3gp')
$destinationSubfolder = 'media\videos\mcnasbackup_duplicate_extras'
$approvedLane = 'HUMAN_REVIEW_MOVE_EXTRAS_READY'
$mcNasRoot = Get-NormalizedPath $McNasSourceRoot
$reviewRoot = Get-NormalizedPath $HumanReviewVideoExtrasRoot
$deleteReviewRoot = Get-NormalizedPath 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW'
$humanReviewRoot = Get-NormalizedPath 'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW'

if (-not (Test-PathInsideRoot -ChildPath $reviewRoot -RootPath $humanReviewRoot)) {
    throw "Human review video extras root must be under 06_HUMAN_REVIEW: $reviewRoot"
}
if (Test-PathInsideRoot -ChildPath $reviewRoot -RootPath $deleteReviewRoot) {
    throw "Human review video extras root must not be under 05_DELETE_REVIEW: $reviewRoot"
}

$keeperPolicy = @(Import-Csv -LiteralPath $KeeperPolicyPath)
$inventory = @(Import-Csv -LiteralPath $InventoryPath)

$inventoryByHash = @{}
foreach ($g in ($inventory | Group-Object { Get-NormalizedHash $_.Hash })) {
    $inventoryByHash[(Get-NormalizedHash $g.Name)] = @($g.Group)
}

$eligibleGroups = @($keeperPolicy | Where-Object {
    $_.ProposedFutureLane -eq $approvedLane -and
    $_.NeedsHumanSpotCheck -eq 'False' -and
    -not [string]::IsNullOrWhiteSpace($_.CandidateKeeperPath)
} | Sort-Object Hash)

$excludedCounts = [ordered]@{
    HumanReviewSampleFirst = @($keeperPolicy | Where-Object ProposedFutureLane -eq 'HUMAN_REVIEW_SAMPLE_FIRST').Count
    MediumReviewSampleFirst = @($keeperPolicy | Where-Object ProposedFutureLane -eq 'MEDIUM_REVIEW_SAMPLE_FIRST').Count
    LowRiskHold = @($keeperPolicy | Where-Object ProposedFutureLane -eq 'LOW_RISK_HOLD').Count
    BlockedInvestigate = @($keeperPolicy | Where-Object ProposedFutureLane -eq 'BLOCKED_INVESTIGATE').Count
    NeedsHumanSpotCheck = @($keeperPolicy | Where-Object { $_.ProposedFutureLane -eq $approvedLane -and $_.NeedsHumanSpotCheck -eq 'True' }).Count
    MissingKeeperPath = @($keeperPolicy | Where-Object { $_.ProposedFutureLane -eq $approvedLane -and [string]::IsNullOrWhiteSpace($_.CandidateKeeperPath) }).Count
}

$blockedRows = New-Object System.Collections.Generic.List[object]
$selectedRows = New-Object System.Collections.Generic.List[object]
$seenSource = @{}
$rowNum = 0

foreach ($group in $eligibleGroups) {
    $hash = Get-NormalizedHash $group.Hash
    $short = $group.ShortHash.Trim()
    $keeperPath = Get-NormalizedPath $group.CandidateKeeperPath
    $keeperReason = $group.KeeperSelectionReason.Trim()

    if (-not $inventoryByHash.ContainsKey($hash)) {
        throw "Inventory missing hash group: $hash"
    }
    $groupInventory = @($inventoryByHash[$hash])

    $groupFileCount = [int]$group.GroupFileCount
    $groupTotalBytes = [int64]$groupInventory[0].GroupTotalBytes
    $duplicateExtraCount = [int]$group.DuplicateExtrasCount
    $duplicateExtraBytes = [int64]$group.DuplicateExtrasBytes
    $proposedLane = $group.ProposedFutureLane.Trim()
    $riskLevel = if ($group.PersonalSignal -eq 'True') { 'HIGH' } else { 'MEDIUM' }

    if (-not (Test-Path -LiteralPath $keeperPath)) {
        throw "CandidateKeeperPath missing on disk: $keeperPath (hash $hash)"
    }
    if (Test-Path -LiteralPath $keeperPath -PathType Container) {
        throw "CandidateKeeperPath is directory: $keeperPath"
    }
    if (-not (Test-PathInsideRoot -ChildPath $keeperPath -RootPath $mcNasRoot)) {
        throw "CandidateKeeperPath outside McNASBackup: $keeperPath"
    }
    if (Test-UnderWorkbenchRoot -Path $keeperPath) {
        throw "CandidateKeeperPath under workbench: $keeperPath"
    }

    $keeperInv = @($groupInventory | Where-Object { (Get-NormalizedPath $_.FullName) -eq $keeperPath })
    if ($keeperInv.Count -eq 0) {
        throw "CandidateKeeperPath not found in inventory for hash $hash : $keeperPath"
    }

    foreach ($invRow in $groupInventory) {
        $sourcePath = Get-NormalizedPath $invRow.FullName
        if ($sourcePath.Equals($keeperPath, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $rowNum++
        if ($rowNum % 100 -eq 0) { Write-Host "  validate $rowNum" }

        $blockReasons = New-Object System.Collections.Generic.List[string]
        $ext = $invRow.Extension.ToLowerInvariant()

        if ($proposedLane -ne $approvedLane) { [void]$blockReasons.Add('NotMoveExtrasReadyLane') }
        if ($group.NeedsHumanSpotCheck -eq 'True') { [void]$blockReasons.Add('NeedsHumanSpotCheck') }
        if ($proposedLane -eq 'HUMAN_REVIEW_SAMPLE_FIRST') { [void]$blockReasons.Add('HumanReviewSampleFirst') }
        if ($proposedLane -eq 'MEDIUM_REVIEW_SAMPLE_FIRST') { [void]$blockReasons.Add('MediumReviewSampleFirst') }
        if ($proposedLane -eq 'LOW_RISK_HOLD') { [void]$blockReasons.Add('LowRiskHold') }
        if ($proposedLane -eq 'BLOCKED_INVESTIGATE') { [void]$blockReasons.Add('BlockedInvestigate') }
        if ($sourcePath.Equals($keeperPath, [StringComparison]::OrdinalIgnoreCase)) { [void]$blockReasons.Add('SourceIsCandidateKeeper') }
        if ($allowedExtensions -notcontains $ext) { [void]$blockReasons.Add('WrongExtension') }
        if ($invRow.SuggestedPolicyLane -in @('LOW_RISK_VIDEO_CACHE_OR_SAMPLE', 'BLOCKED_INVESTIGATE')) { [void]$blockReasons.Add('WrongInventoryLane') }
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
            [void]$selectedRows.Add([pscustomobject]@{
                InventoryRow = $invRow
                Group = $group
                Hash = $hash
                ShortHash = $short
                SourcePath = $sourcePath
                KeeperPath = $keeperPath
                KeeperReason = $keeperReason
                GroupFileCount = $groupFileCount
                GroupTotalBytes = $groupTotalBytes
                DuplicateExtraCount = $duplicateExtraCount
                DuplicateExtraBytes = $duplicateExtraBytes
                ProposedFutureLane = $proposedLane
                RiskLevel = $riskLevel
                NeedsHumanSpotCheck = $group.NeedsHumanSpotCheck
            })
        }
        else {
            [void]$blockedRows.Add([pscustomobject]@{
                SourcePath = $sourcePath
                Hash = $hash
                ProposedFutureLane = $proposedLane
                BlockReason = ($blockReasons -join ';')
            })
        }
    }
}

if ($blockedRows.Count -gt 0) {
    throw "Plan builder blocked $($blockedRows.Count) candidate row(s). First: $($blockedRows[0].SourcePath) $($blockedRows[0].BlockReason)"
}

$expectedCount = 650
if ($selectedRows.Count -ne $expectedCount) {
    throw "Expected $expectedCount MOVE_EXTRAS_READY duplicate extras; selected $($selectedRows.Count)."
}

$reservedNames = @{}
$planRows = New-Object System.Collections.Generic.List[object]
foreach ($item in ($selectedRows | Sort-Object SourcePath)) {
    $invRow = $item.InventoryRow
    $sourcePath = $item.SourcePath
    $fileName = Split-Path -Leaf $sourcePath
    $destInfo = Get-CollisionSafeReviewFileName -ShortHash $item.ShortHash -OriginalFileName $fileName `
        -DestinationDirectory $reviewRoot -ReservedNames $reservedNames

    [void]$planRows.Add([pscustomobject]@{
        Hash = $item.Hash
        ShortHash = $item.ShortHash
        SizeBytes = $invRow.SizeBytes
        SourcePath = $sourcePath
        ReviewPath = $destInfo.ReviewPath
        DestinationSubfolder = $destinationSubfolder
        FileName = $fileName
        RelativePath = $invRow.RelativePath
        Extension = $invRow.Extension.ToLowerInvariant()
        GroupFileCount = $item.GroupFileCount
        GroupTotalBytes = $item.GroupTotalBytes
        CandidateKeeperPath = $item.KeeperPath
        CandidateKeeperReason = $item.KeeperReason
        DuplicateExtraCount = $item.DuplicateExtraCount
        DuplicateExtraBytes = $item.DuplicateExtraBytes
        ProposedFutureLane = $item.ProposedFutureLane
        RiskLevel = $item.RiskLevel
        NeedsHumanSpotCheck = $item.NeedsHumanSpotCheck
        ReviewConfidence = 'MEDIUM'
        ReviewReason = $invRow.ReviewReason.Trim()
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

Add-BadTest 'CandidateKeeperSelectedForMovement' {
    if (@($planRows | Where-Object { (Get-NormalizedPath $_.SourcePath) -eq (Get-NormalizedPath $_.CandidateKeeperPath) }).Count -gt 0) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'GroupWithoutKeeper' {
    if (@($planRows | Where-Object { [string]::IsNullOrWhiteSpace($_.CandidateKeeperPath) }).Count -gt 0) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'NotMoveExtrasReadyLane' {
    if (@($planRows | Where-Object ProposedFutureLane -ne $approvedLane).Count -gt 0) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'NeedsHumanSpotCheckTrue' {
    if (@($planRows | Where-Object NeedsHumanSpotCheck -eq 'True').Count -gt 0) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'HumanReviewSampleFirstLane' {
    if (@($planRows | Where-Object ProposedFutureLane -eq 'HUMAN_REVIEW_SAMPLE_FIRST').Count -gt 0) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'MediumReviewSampleFirstLane' {
    if (@($planRows | Where-Object ProposedFutureLane -eq 'MEDIUM_REVIEW_SAMPLE_FIRST').Count -gt 0) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'SourceOutsideMcNas' {
    if (Test-PathInsideRoot -ChildPath 'I:\recover\McNASBackup\test.mp4' -RootPath $mcNasRoot) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'SourceUnderWorkbench' {
    if (Test-UnderWorkbenchRoot -Path 'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW\test.mp4') { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'DestinationOutsideHumanReview' {
    $bad = Join-Path 'I:\recover\McNASBackup' 'test.mp4'
    if (-not (Test-PathInsideRoot -ChildPath $sampleGood.ReviewPath -RootPath $humanReviewRoot)) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'DestinationUnderDeleteReview' {
    $bad = Join-Path $deleteReviewRoot 'media\videos\test.mp4'
    if (Test-PathInsideRoot -ChildPath $bad -RootPath $deleteReviewRoot) { throw 'reject' }
    throw 'accept'
}
Add-BadTest 'WrongExtension' {
    if ('.pdf' -in $allowedExtensions) { throw 'accept' }
    throw 'reject'
}
Add-BadTest 'PlanHasDuplicateSourceRows' {
    $dup = @($planRows | Group-Object { (Get-NormalizedPath $_.SourcePath).ToUpperInvariant() } | Where-Object Count -gt 1)
    if ($dup.Count -gt 0) { throw 'reject' }
    throw 'accept'
}

if (@($badTests | Where-Object { $_ -like 'FAIL:*' }).Count -gt 0) {
    throw "Bad plan tests failed:`n$($badTests -join "`n")"
}

$planPath = Join-Path $ReportRoot "approved_phase2_mcnasbackup_video_move_extras_plan_$PlanStamp.csv"
$shaPath = Join-Path $ReportRoot "approved_phase2_mcnasbackup_video_move_extras_plan_$PlanStamp.sha256.txt"
$planRows | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
$hashFile = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToUpperInvariant()
Set-Content -LiteralPath $shaPath -Value $hashFile -Encoding UTF8

$totalBytes = ($planRows | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
Write-Host "McNASBackup video move-extras plan rows: $($planRows.Count)"
Write-Host "EligibleGroups=$($eligibleGroups.Count)"
Write-Host "BlockedPreSelection=$($blockedRows.Count)"
Write-Host "TotalBytes=$totalBytes"
Write-Host "Excluded HumanReviewSampleFirst=$($excludedCounts.HumanReviewSampleFirst)"
Write-Host "Excluded MediumReviewSampleFirst=$($excludedCounts.MediumReviewSampleFirst)"
Write-Host "Excluded LowRiskHold=$($excludedCounts.LowRiskHold)"
Write-Host "Excluded BlockedInvestigate=$($excludedCounts.BlockedInvestigate)"
Write-Host "Excluded NeedsHumanSpotCheck=$($excludedCounts.NeedsHumanSpotCheck)"
Write-Host "PlanPath=$planPath"
Write-Host "PlanSha256=$hashFile"
Write-Host "ShaPath=$shaPath"
Write-Host 'BadPlanTests:'
$badTests | ForEach-Object { Write-Host "  $_" }
