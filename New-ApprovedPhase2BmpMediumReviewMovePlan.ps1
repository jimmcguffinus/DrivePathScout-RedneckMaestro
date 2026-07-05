[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$BmpInventoryPath = 'C:\Users\jim\Desktop\DrivePathInventory\phase2_bmp_duplicate_inventory_20260704.csv',

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',

    [ValidateNotNullOrEmpty()]
    [string]$PlanStamp = '20260704',

    [ValidateNotNullOrEmpty()]
    [string]$BmpSourceRoot = 'I:\recover\BMPs',

    [ValidateNotNullOrEmpty()]
    [string]$DeleteReviewBmpRoot = 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW\medium_review\images\bmp'
)

# Phase 2 BMP medium-review approved move plan builder v0.2.7
# MOVE-only grouping plan for MEDIUM_REVIEW_IMAGES_BMP rows only.
# HUMAN_REVIEW_IMAGE_BMP rows are HOLD and must never appear in the plan.
# Mixed-lane safety: every selected hash must retain at least one non-selected inventory counterpart.

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

$bmpRoot = Get-NormalizedPath $BmpSourceRoot
$reviewRoot = Get-NormalizedPath $DeleteReviewBmpRoot
$allRows = @(Import-Csv -LiteralPath $BmpInventoryPath)
if ($allRows.Count -eq 0) { throw "BMP inventory contains no rows: $BmpInventoryPath" }

$hashIndex = @{}
foreach ($row in $allRows) {
    $h = Get-NormalizedHash $row.Hash
    if (-not $hashIndex.ContainsKey($h)) { $hashIndex[$h] = New-Object System.Collections.ArrayList }
    [void]$hashIndex[$h].Add($row)
}

$candidateRows = @($allRows | Where-Object {
    $_.SuggestedPolicyLane -eq 'MEDIUM_REVIEW_IMAGES_BMP' -and
    $_.SuggestedDestinationSubfolder -eq 'medium_review\images\bmp' -and
    $_.Extension.ToLowerInvariant() -eq '.bmp'
} | Sort-Object FullName)

$blockedRows = New-Object System.Collections.Generic.List[object]
$selectedRows = New-Object System.Collections.Generic.List[object]
$seenSource = @{}

foreach ($row in $candidateRows) {
    $sourcePath = Get-NormalizedPath $row.FullName
    $hash = Get-NormalizedHash $row.Hash
    $blockReasons = New-Object System.Collections.Generic.List[string]

    if ($row.SuggestedPolicyLane -eq 'HUMAN_REVIEW_IMAGE_BMP') { [void]$blockReasons.Add('HumanReviewLane') }
    if ($row.SuggestedPolicyLane -eq 'BLOCKED_INVESTIGATE') { [void]$blockReasons.Add('BlockedInvestigateLane') }
    if (-not (Test-PathInsideRoot -ChildPath $sourcePath -RootPath $bmpRoot)) { [void]$blockReasons.Add('OutsideBmpRoot') }
    if (Test-UnderWorkbenchRoot -Path $sourcePath) { [void]$blockReasons.Add('UnderWorkbenchRoot') }
    if (-not (Test-Path -LiteralPath $sourcePath)) { [void]$blockReasons.Add('MissingSource') }
    elseif (Test-Path -LiteralPath $sourcePath -PathType Container) { [void]$blockReasons.Add('SourceIsDirectory') }

    $key = $sourcePath.ToUpperInvariant()
    if ($seenSource.ContainsKey($key)) { [void]$blockReasons.Add('DuplicateSourcePath') }
    else { $seenSource[$key] = $true }

    if ($blockReasons.Count -eq 0) {
        try {
            $liveHash = Get-NormalizedHash (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
            if ($liveHash -ne $hash) { [void]$blockReasons.Add('HashMismatch') }
        }
        catch { [void]$blockReasons.Add('HashCheckFailed') }
    }

    if ($row.IsPhotoLikeBmp -eq 'True') { [void]$blockReasons.Add('PhotoLikeBmp') }

    if ($blockReasons.Count -eq 0) {
        [void]$selectedRows.Add($row)
    }
    else {
        [void]$blockedRows.Add([pscustomobject]@{
            FullName = $sourcePath
            Hash = $hash
            BlockReason = ($blockReasons -join ';')
        })
    }
}

$selectedByHash = @($selectedRows | Group-Object { Get-NormalizedHash $_.Hash })
$mixedLaneBlocked = New-Object System.Collections.Generic.List[object]
$finalSelected = New-Object System.Collections.Generic.List[object]

foreach ($group in $selectedByHash) {
    $hash = Get-NormalizedHash $group.Name
    $groupRows = @($group.Group)
    $inventoryRows = @($hashIndex[$hash])
    $humanReviewCount = @($inventoryRows | Where-Object { $_.SuggestedPolicyLane -eq 'HUMAN_REVIEW_IMAGE_BMP' }).Count
    $selectedCount = $groupRows.Count
    $totalCount = $inventoryRows.Count
    $nonSelectedCount = $totalCount - $selectedCount

    if ($nonSelectedCount -lt 1) {
        foreach ($row in $groupRows) {
            [void]$mixedLaneBlocked.Add([pscustomobject]@{
                FullName = $row.FullName
                Hash = $hash
                BlockReason = 'MixedLaneAllCopiesSelected'
                GroupFileCount = $totalCount
                HumanReviewSameHashCount = $humanReviewCount
                NonSelectedSameHashCount = $nonSelectedCount
            })
        }
        continue
    }

    foreach ($row in $groupRows) {
        [void]$finalSelected.Add($row)
    }
}

if ($blockedRows.Count -gt 0) {
    throw "Plan builder blocked $($blockedRows.Count) candidate row(s) during pre-selection checks. First: $($blockedRows[0].FullName) $($blockedRows[0].BlockReason)"
}
if ($mixedLaneBlocked.Count -gt 0) {
    throw "Mixed-lane safety blocked $($mixedLaneBlocked.Count) row(s). First hash=$($mixedLaneBlocked[0].Hash) reason=$($mixedLaneBlocked[0].BlockReason)"
}
if ($finalSelected.Count -eq 0) { throw 'No eligible MEDIUM_REVIEW_IMAGES_BMP rows after mixed-lane safety.' }

$reservedDest = @{}
$planRows = New-Object System.Collections.Generic.List[object]
foreach ($row in ($finalSelected | Sort-Object FullName)) {
    $sourcePath = Get-NormalizedPath $row.FullName
    $hash = Get-NormalizedHash $row.Hash
    $short = $row.ShortHash.Trim()
    $fileName = Split-Path -Leaf $sourcePath
    $inventoryRows = @($hashIndex[$hash])
    $humanReviewCount = @($inventoryRows | Where-Object { $_.SuggestedPolicyLane -eq 'HUMAN_REVIEW_IMAGE_BMP' }).Count
    $nonSelectedCount = $inventoryRows.Count - 1

    $destInfo = Get-CollisionSafeReviewFileName -ShortHash $short -OriginalFileName $fileName -DestinationDirectory $reviewRoot -ReservedNames $reservedDest
    [void]$planRows.Add([pscustomobject]@{
        Hash = $hash
        ShortHash = $short
        SizeBytes = $row.SizeBytes
        SourcePath = $sourcePath
        ReviewPath = $destInfo.ReviewPath
        DestinationSubfolder = 'medium_review\images\bmp'
        FileName = $fileName
        RelativePath = $row.RelativePath
        Width = $row.Width
        Height = $row.Height
        PixelFormat = $row.PixelFormat
        IsTinyIconOrAsset = $row.IsTinyIconOrAsset
        IsLikelyCarvedBmp = $row.IsLikelyCarvedBmp
        IsPhotoLikeBmp = $row.IsPhotoLikeBmp
        GroupFileCount = $row.GroupFileCount
        NonSelectedSameHashCount = $nonSelectedCount
        HumanReviewSameHashCount = $humanReviewCount
        ReviewConfidence = 'MEDIUM'
        ReviewReason = $row.ReviewReason.Trim()
    })
}

$planPath = Join-Path $ReportRoot "approved_phase2_bmp_medium_review_move_plan_$PlanStamp.csv"
$shaPath = Join-Path $ReportRoot "approved_phase2_bmp_medium_review_move_plan_$PlanStamp.sha256.txt"
$planRows | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
$hashFile = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToUpperInvariant()
Set-Content -LiteralPath $shaPath -Value $hashFile -Encoding UTF8

$totalBytes = ($planRows | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
Write-Host "Phase 2 BMP medium-review move plan rows: $($planRows.Count)"
Write-Host "BlockedPreSelection=$($blockedRows.Count) MixedLaneBlocked=$($mixedLaneBlocked.Count)"
Write-Host "TotalBytes=$totalBytes"
Write-Host "HumanReviewSameHashRowsPresent=$($planRows | Where-Object { [int]$_.HumanReviewSameHashCount -gt 0 } | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host "PlanPath=$planPath"
Write-Host "PlanSha256=$hashFile"
Write-Host "ShaPath=$shaPath"
