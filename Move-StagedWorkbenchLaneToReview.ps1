[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InventoryCsvPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApprovedReviewMovePlan,

    [ValidateNotNullOrEmpty()]
    [string]$ExpectedApprovedReviewMovePlanHash,

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',

    [ValidateNotNullOrEmpty()]
    [string]$DeleteReviewRoot = 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW',

    [ValidateNotNullOrEmpty()]
    [string]$HumanReviewRoot = 'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW',

    [ValidateNotNullOrEmpty()]
    [string]$RunStamp,

    [ValidateSet('GifMedium', 'CsvMedium', 'SunsPngMedium', 'PstHumanReview', 'Phase2BmpMediumReview')]
    [string]$LaneProfile = 'GifMedium',

    [switch]$Execute
)

# Workbench Lane Review Move Planner v0.2.7
# MOVE staged duplicate files from an approved workbench lane into review roots. Default is DryRun.
# LaneProfile GifMedium:            04_DUPLICATES_STAGED\...\images\gif -> 05_DELETE_REVIEW\medium_review\gif
# LaneProfile CsvMedium:             04_DUPLICATES_STAGED\...\data\csv   -> 05_DELETE_REVIEW\medium_review\csv
# LaneProfile SunsPngMedium:         04_DUPLICATES_STAGED\...\recovered_to_realname (flat PNG) -> medium_review\suns_png
# LaneProfile PstHumanReview:        04_DUPLICATES_STAGED\...\mail\pst -> 06_HUMAN_REVIEW\mail\pst_duplicates
# LaneProfile Phase2BmpMediumReview: I:\recover\BMPs (MEDIUM_REVIEW_IMAGES_BMP only) -> 05_DELETE_REVIEW\medium_review\images\bmp
# Full execute preflight eliminates predictable per-row blockers before the first Move-Item.
# Not transactionally atomic after external I/O failure; manifest-based recovery may be required.
# No Remove-Item. No Copy-Item. No Rename-Item. Never moves keeper files or I:\recover / I:\1tbrecover sources.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Initialize-LaneProfile {
    param([Parameter(Mandatory = $true)][string]$Profile)
    $script:StagedDuplicatesRoot = 'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname'
    $script:RequiredReviewConfidence = 'MEDIUM'
    $script:DeniedMoveSourcePrefixes = @('I:\recover\', 'I:\1tbrecover\')
    $script:VerifiedMoveStatuses = @('MovedVerified')
    $script:BatchExecuteReadyStatuses = @('DryRunReady', 'CollisionRenamed')
    $script:InventoryCouplingMode = 'StagedDuplicate'
    $script:RequiresKeeperVerification = $true
    $script:RequiresKeeperReviewCopy = $false
    $script:RequiresFlatStagedRoot = $false
    $script:ExcludedStagedSubfolderRoots = @()
    $script:UsesHumanReviewRoot = $false
    $script:PlanSourcePathColumn = 'StagedDuplicatePath'
    $script:PlanDestinationPathColumn = 'DeleteReviewPath'
    $script:ForbiddenDestinationRoots = @()
    $script:UsesPhase2RecoverSource = $false
    $script:Phase2RecoverSourceRoot = ''
    $script:WorkbenchExcludeRoots = @()
    switch ($Profile) {
        'GifMedium' {
            $script:ApprovedStagedSourceRoots = @(
                'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\images\gif'
            )
            $script:ApprovedSourceSubfolders = @('images\gif')
            $script:ReviewLaneBySourceSubfolder = @{ 'images\gif' = 'medium_review\gif' }
            $script:RequiredFileExtension = '.gif'
            $script:DeniedSourceSubfolderPatterns = @('mail\pst', 'data\csv', 'images\png')
            $script:ReportNamePrefix = 'gif_delete_review_move'
        }
        'CsvMedium' {
            $script:ApprovedStagedSourceRoots = @(
                'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\data\csv'
            )
            $script:ApprovedSourceSubfolders = @('data\csv')
            $script:ReviewLaneBySourceSubfolder = @{ 'data\csv' = 'medium_review\csv' }
            $script:RequiredFileExtension = '.csv'
            $script:DeniedSourceSubfolderPatterns = @('mail\pst', 'images\gif', 'images\png')
            $script:ReportNamePrefix = 'csv_delete_review_move'
        }
        'SunsPngMedium' {
            $script:ApprovedStagedSourceRoots = @(
                'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname'
            )
            $script:ApprovedSourceSubfolders = @('suns_png_root')
            $script:ReviewLaneBySourceSubfolder = @{ 'suns_png_root' = 'medium_review\suns_png' }
            $script:RequiredFileExtension = '.png'
            $script:DeniedSourceSubfolderPatterns = @('mail\pst', 'data\csv', 'images\gif', 'images\png')
            $script:ReportNamePrefix = 'suns_png_delete_review_move'
            $script:InventoryCouplingMode = 'SunsPngReport'
            $script:RequiresKeeperVerification = $false
            $script:RequiresFlatStagedRoot = $true
            $script:ExcludedStagedSubfolderRoots = @(
                'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\mail\pst',
                'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\images\gif',
                'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\data\csv',
                'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\images\png'
            )
        }
        'PstHumanReview' {
            $script:ApprovedStagedSourceRoots = @(
                'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\mail\pst'
            )
            $script:ApprovedSourceSubfolders = @('mail\pst')
            $script:ReviewLaneBySourceSubfolder = @{ 'mail\pst' = 'mail\pst_duplicates' }
            $script:RequiredFileExtension = '.pst'
            $script:DeniedSourceSubfolderPatterns = @()
            $script:ReportNamePrefix = 'pst_human_review_move'
            $script:InventoryCouplingMode = 'PstPolicyReport'
            $script:RequiresKeeperVerification = $true
            $script:RequiresKeeperReviewCopy = $true
            $script:UsesHumanReviewRoot = $true
            $script:PlanDestinationPathColumn = 'HumanReviewPath'
            $script:ForbiddenDestinationRoots = @('I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW')
        }
        'Phase2BmpMediumReview' {
            $script:UsesPhase2RecoverSource = $true
            $script:Phase2RecoverSourceRoot = 'I:\recover\BMPs'
            $script:StagedDuplicatesRoot = 'I:\recover\BMPs'
            $script:ApprovedStagedSourceRoots = @('I:\recover\BMPs')
            $script:ApprovedSourceSubfolders = @('medium_review\images\bmp')
            $script:ReviewLaneBySourceSubfolder = @{ 'medium_review\images\bmp' = 'medium_review\images\bmp' }
            $script:RequiredFileExtension = '.bmp'
            $script:DeniedSourceSubfolderPatterns = @()
            $script:DeniedMoveSourcePrefixes = @()
            $script:ReportNamePrefix = 'phase2_bmp_medium_review_move'
            $script:InventoryCouplingMode = 'Phase2BmpInventory'
            $script:RequiresKeeperVerification = $false
            $script:RequiresFlatStagedRoot = $false
            $script:PlanSourcePathColumn = 'SourcePath'
            $script:PlanDestinationPathColumn = 'ReviewPath'
            $script:WorkbenchExcludeRoots = @(
                'I:\_RECOVERY_WORKBENCH\02_KEEPERS_REVIEW',
                'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED',
                'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW',
                'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW'
            )
        }
        default {
            throw "Unsupported LaneProfile: $Profile"
        }
    }
}

Initialize-LaneProfile -Profile $LaneProfile

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try {
        $full = [IO.Path]::GetFullPath($Path)
    }
    catch {
        return $Path.Trim()
    }
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { return $root }
    return $full.TrimEnd([char[]]'\/')
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
    $prefix = if ($root.EndsWith([IO.Path]::DirectorySeparatorChar)) { $root } else { $root + [IO.Path]::DirectorySeparatorChar }
    return $child.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-PathVolumeRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ([IO.Path]::GetPathRoot((Get-NormalizedPath $Path))).ToUpperInvariant()
}

function Test-SameVolume {
    param(
        [Parameter(Mandatory = $true)][string]$PathA,
        [Parameter(Mandatory = $true)][string]$PathB
    )
    $rootA = Get-PathVolumeRoot $PathA
    $rootB = Get-PathVolumeRoot $PathB
    return -not [string]::IsNullOrWhiteSpace($rootA) -and $rootA.Equals($rootB, [StringComparison]::OrdinalIgnoreCase)
}

function Test-PathUnderDeniedPrefix {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($script:DeniedMoveSourcePrefixes.Count -eq 0) { return $false }
    $normalized = Get-NormalizedPath $Path
    foreach ($prefix in $script:DeniedMoveSourcePrefixes) {
        if (Test-PathInsideRoot -ChildPath $normalized -RootPath $prefix.TrimEnd('\')) {
            return $true
        }
    }
    return $false
}

function Test-PathUnderWorkbenchExclude {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($script:WorkbenchExcludeRoots.Count -eq 0) { return $false }
    $normalized = Get-NormalizedPath $Path
    foreach ($root in $script:WorkbenchExcludeRoots) {
        if (Test-PathInsideRoot -ChildPath $normalized -RootPath (Get-NormalizedPath $root)) {
            return $true
        }
    }
    return $false
}

function Test-StagedPathInExcludedSubfolder {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = Get-NormalizedPath $Path
    foreach ($excluded in $script:ExcludedStagedSubfolderRoots) {
        $exNorm = Get-NormalizedPath $excluded
        if (Test-PathInsideRoot -ChildPath $normalized -RootPath $exNorm) {
            return $true
        }
    }
    return $false
}

function Test-StagedPathInApprovedSourceRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = Get-NormalizedPath $Path
    if ($script:UsesPhase2RecoverSource) {
        foreach ($root in $script:ApprovedStagedSourceRoots) {
            if (Test-PathInsideRoot -ChildPath $normalized -RootPath $root) {
                return $true
            }
        }
        return $false
    }
    if (Test-StagedPathInExcludedSubfolder -Path $normalized) {
        return $false
    }
    if ($script:RequiresFlatStagedRoot) {
        $parent = Get-NormalizedPath (Split-Path -Parent $normalized)
        if (-not $parent.Equals($script:StagedDuplicatesRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    foreach ($root in $script:ApprovedStagedSourceRoots) {
        if (Test-PathInsideRoot -ChildPath $normalized -RootPath $root) {
            return $true
        }
    }
    return $false
}

function Test-SafeLiteralMovePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Move path cannot be empty.'
    }
    if ($Path -match '[\*\?]') {
        throw "Move path must not contain wildcards: $Path"
    }
    if ($Path -match '\.\.') {
        throw "Move path must not contain '..': $Path"
    }
    return Get-NormalizedPath $Path
}

function Get-PathChainComponents {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = Get-NormalizedPath $Path
    if ([string]::IsNullOrWhiteSpace($normalized)) { return @() }

    $root = [IO.Path]::GetPathRoot($normalized)
    if (-not $root.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $root = $root + [IO.Path]::DirectorySeparatorChar
    }
    $relative = $normalized.Substring($root.Length).TrimStart([char[]]'\/')

    $chain = New-Object System.Collections.Generic.List[string]
    [void]$chain.Add($root)

    if (-not [string]::IsNullOrWhiteSpace($relative)) {
        $current = $root
        foreach ($part in ($relative -split '\\')) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            $current = Join-Path $current $part
            [void]$chain.Add($current)
        }
    }

    return @($chain)
}

function Test-ReparsePathChain {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('Source', 'Destination')][string]$Mode
    )
    $checkFailedStatus = if ($Mode -eq 'Source') { 'SourceReparseCheckFailed' } else { 'DestinationReparseCheckFailed' }
    $reparseStatus = if ($Mode -eq 'Source') { 'SourceReparsePoint' } else { 'DestinationReparsePoint' }

    $normalized = Get-NormalizedPath $Path
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return [pscustomobject]@{
            Safe          = $false
            Status        = $checkFailedStatus
            Message       = 'Path is empty; reparse chain check cannot complete.'
            ComponentPath = ''
        }
    }

    $chain = @(Get-PathChainComponents -Path $normalized)
    if ($chain.Count -eq 0) {
        return [pscustomobject]@{
            Safe          = $false
            Status        = $checkFailedStatus
            Message       = 'Unable to build path chain for reparse inspection.'
            ComponentPath = ''
        }
    }

    if ($Mode -eq 'Destination' -and $chain.Count -gt 1) {
        $chain = $chain[0..($chain.Count - 2)]
    }

    foreach ($component in $chain) {
        if (-not (Test-Path -LiteralPath $component)) {
            if ($Mode -eq 'Source') {
                return [pscustomobject]@{
                    Safe          = $false
                    Status        = $checkFailedStatus
                    Message       = "Source path component missing during reparse inspection: $component"
                    ComponentPath = $component
                }
            }
            continue
        }

        try {
            $item = Get-Item -LiteralPath $component -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return [pscustomobject]@{
                    Safe          = $false
                    Status        = $reparseStatus
                    Message       = "Reparse point detected at $component"
                    ComponentPath = $component
                }
            }
        }
        catch {
            return [pscustomobject]@{
                Safe          = $false
                Status        = $checkFailedStatus
                Message       = "Reparse inspection failed at ${component}: $($_.Exception.Message)"
                ComponentPath = $component
            }
        }
    }

    return [pscustomobject]@{
        Safe          = $true
        Status        = $null
        Message       = $null
        ComponentPath = $null
    }
}

function Get-ExpectedDeleteReviewDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationSubfolder,
        [Parameter(Mandatory = $true)][string]$DeleteReviewRoot
    )
    if (-not $script:ReviewLaneBySourceSubfolder.ContainsKey($DestinationSubfolder)) {
        throw "Unsupported DestinationSubfolder for delete review routing: $DestinationSubfolder"
    }
    $lane = $script:ReviewLaneBySourceSubfolder[$DestinationSubfolder]
    $reviewRootNormalized = Get-NormalizedPath $DeleteReviewRoot
    $destDir = Get-NormalizedPath (Join-Path $reviewRootNormalized $lane)
    if (-not (Test-PathInsideRoot -ChildPath $destDir -RootPath $reviewRootNormalized)) {
        throw "Delete review directory escapes DeleteReviewRoot. Lane=$lane Resolved=$destDir Root=$reviewRootNormalized"
    }
    return $destDir
}

function Get-ExpectedDeleteReviewPath {
    param(
        [Parameter(Mandatory = $true)][string]$StagedDuplicatePath,
        [Parameter(Mandatory = $true)][string]$DestinationSubfolder,
        [Parameter(Mandatory = $true)][string]$DeleteReviewRoot
    )
    $destDir = Get-ExpectedDeleteReviewDirectory -DestinationSubfolder $DestinationSubfolder -DeleteReviewRoot $DeleteReviewRoot
    $fileName = Split-Path -Leaf $StagedDuplicatePath
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        throw "Unable to determine filename for staged duplicate path: $StagedDuplicatePath"
    }
    return Get-NormalizedPath (Join-Path $destDir $fileName)
}

function Get-UniqueDeleteReviewDestination {
    param(
        [Parameter(Mandatory = $true)][string]$BaseFileName,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory,
        [Parameter(Mandatory = $true)][hashtable]$ReservedNames
    )
    $ext = [IO.Path]::GetExtension($BaseFileName)
    $nameWithoutExt = if ([string]::IsNullOrWhiteSpace($ext)) { $BaseFileName } else { $BaseFileName.Substring(0, $BaseFileName.Length - $ext.Length) }
    $candidate = $BaseFileName
    $collisionSuffix = ''
    $statusNote = 'DryRunReady'
    $index = 2
    while ($true) {
        $fullPath = Join-Path $DestinationDirectory $candidate
        $key = $fullPath.ToUpperInvariant()
        if (-not (Test-Path -LiteralPath $fullPath) -and -not $ReservedNames.ContainsKey($key)) {
            [void]$ReservedNames.Add($key, $true)
            if ($collisionSuffix) { $statusNote = 'CollisionRenamed' }
            return [pscustomobject]@{
                PlannedDeleteReviewPath = $fullPath
                CollisionSuffix         = $collisionSuffix
                CollisionStatus         = $statusNote
            }
        }
        $collisionSuffix = '.collision-{0:D3}' -f $index
        $candidate = '{0}{1}{2}' -f $nameWithoutExt, $collisionSuffix, $ext
        $index++
        if ($index -gt 999) { throw "Unable to allocate collision-safe delete review destination for '$BaseFileName'." }
    }
}

function Get-ApprovedReviewMovePlanFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Approved review move plan not found: $Path"
    }
    return Get-NormalizedHash (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Read-ApprovedReviewMovePlan {
    param(
        [Parameter(Mandatory = $true)][string]$PlanPath,
        [Parameter(Mandatory = $true)][string]$DeleteReviewRoot
    )
    if (-not (Test-Path -LiteralPath $PlanPath)) {
        throw "Approved review move plan not found: $PlanPath"
    }
    $rows = @(Import-Csv -LiteralPath $PlanPath)
    if ($rows.Count -eq 0) {
        throw "Approved review move plan contains no rows: $PlanPath"
    }
    $required = @('Hash', 'ShortHash', 'SizeBytes', $script:PlanSourcePathColumn, $script:PlanDestinationPathColumn, 'DestinationSubfolder', 'ReviewConfidence', 'ReviewReason')
    $missing = @($required | Where-Object { $rows[0].PSObject.Properties.Name -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw "Approved review move plan is missing required columns: $($missing -join ', ')"
    }
    $reviewRootNormalized = Get-NormalizedPath $DeleteReviewRoot
    $entries = New-Object System.Collections.Generic.List[object]
    $seenEntries = @{}
    $rawPathCount = 0
    $duplicatePathCount = 0
    foreach ($row in $rows) {
        $stagedPath = Test-SafeLiteralMovePath -Path $row.($script:PlanSourcePathColumn)
        $deleteReviewPath = Test-SafeLiteralMovePath -Path $row.($script:PlanDestinationPathColumn)
        $subfolder = $row.DestinationSubfolder.Trim()
        $confidence = $row.ReviewConfidence.Trim().ToUpperInvariant()
        $hash = Get-NormalizedHash $row.Hash
        $rawPathCount++
        if ($confidence -ne $script:RequiredReviewConfidence) {
            throw "Approved review move plan row is not $($script:RequiredReviewConfidence) confidence: $stagedPath"
        }
        if ([IO.Path]::GetExtension($stagedPath).ToLowerInvariant() -ne $script:RequiredFileExtension) {
            throw "Approved review move plan staged path is not $($script:RequiredFileExtension): $stagedPath"
        }
        foreach ($denied in $script:DeniedSourceSubfolderPatterns) {
            if ($subfolder -eq $denied -or $stagedPath -like "*\$denied\*") {
                throw "Approved review move plan row has denied subfolder pattern '$denied': $stagedPath"
            }
        }
        if ($script:ApprovedSourceSubfolders -notcontains $subfolder) {
            throw "Approved review move plan row has disallowed DestinationSubfolder '$subfolder': $stagedPath"
        }
        if ($script:UsesPhase2RecoverSource) {
            if (-not (Test-StagedPathInApprovedSourceRoot -Path $stagedPath)) {
                throw "Approved review move plan source path is outside approved Phase 2 BMP root: $stagedPath"
            }
            if (Test-PathUnderWorkbenchExclude -Path $stagedPath) {
                throw "Approved review move plan source path is under workbench exclude root: $stagedPath"
            }
            if ($row.PSObject.Properties.Name -contains 'IsPhotoLikeBmp' -and $row.IsPhotoLikeBmp -eq 'True') {
                throw "Approved review move plan row is photo-like BMP (human review hold): $stagedPath"
            }
            if ($row.PSObject.Properties.Name -contains 'NonSelectedSameHashCount' -and
                [int]$row.NonSelectedSameHashCount -lt 1) {
                throw "Approved review move plan row would move all copies of hash group: $stagedPath"
            }
        }
        else {
            if (-not (Test-StagedPathInApprovedSourceRoot -Path $stagedPath)) {
                throw "Approved review move plan staged path is outside approved staged source roots: $stagedPath"
            }
            if ($script:RequiresFlatStagedRoot) {
                $parentDir = Get-NormalizedPath (Split-Path -Parent $stagedPath)
                if (-not $parentDir.Equals($script:StagedDuplicatesRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Approved review move plan staged path must be directly under recovered_to_realname root: $stagedPath"
                }
            }
            if (-not (Test-PathInsideRoot -ChildPath $stagedPath -RootPath $script:StagedDuplicatesRoot)) {
                throw "Approved review move plan staged path is outside staged duplicates root: $stagedPath"
            }
            if (Test-PathUnderDeniedPrefix -Path $stagedPath) {
                throw "Approved review move plan staged path is under denied prefix: $stagedPath"
            }
        }
        if ((Test-Path -LiteralPath $stagedPath) -and (Test-Path -LiteralPath $stagedPath -PathType Container)) {
            throw "Approved review move plan staged path is a directory, not a file: $stagedPath"
        }
        if (-not (Test-PathInsideRoot -ChildPath $deleteReviewPath -RootPath $reviewRootNormalized)) {
            throw "Approved review move plan destination path escapes review root: $deleteReviewPath"
        }
        foreach ($forbiddenRoot in $script:ForbiddenDestinationRoots) {
            $forbiddenNormalized = Get-NormalizedPath $forbiddenRoot
            if (Test-PathInsideRoot -ChildPath $deleteReviewPath -RootPath $forbiddenNormalized) {
                throw "Approved review move plan destination path is under forbidden root '$forbiddenNormalized': $deleteReviewPath"
            }
        }
        $expectedReviewPath = Get-ExpectedDeleteReviewPath -StagedDuplicatePath $stagedPath -DestinationSubfolder $subfolder -DeleteReviewRoot $reviewRootNormalized
        $expectedReviewDir = Split-Path -Parent $expectedReviewPath
        $actualReviewDir = Split-Path -Parent $deleteReviewPath
        if (-not $actualReviewDir.Equals($expectedReviewDir, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Approved review move plan destination path is in wrong review lane: $deleteReviewPath"
        }
        $keeperPath = ''
        if ($row.PSObject.Properties.Name -contains 'KeeperPath') {
            $keeperPath = Get-NormalizedPath $row.KeeperPath
        }
        $key = $stagedPath.ToUpperInvariant()
        if ($seenEntries.ContainsKey($key)) {
            $existing = $seenEntries[$key]
            if ($existing.Hash -ne $hash -or
                $existing.DeleteReviewPath -ne $deleteReviewPath -or
                $existing.DestinationSubfolder -ne $subfolder) {
                throw "Approved review move plan contains conflicting duplicate StagedDuplicatePath: $stagedPath"
            }
            $duplicatePathCount++
            continue
        }
        $entry = [pscustomobject]@{
            Hash                 = $hash
            ShortHash            = $row.ShortHash.Trim()
            SizeBytes            = $row.SizeBytes
            StagedDuplicatePath  = $stagedPath
            DeleteReviewPath     = $deleteReviewPath
            KeeperPath           = $keeperPath
            KeeperReviewCopyPath = if ($row.PSObject.Properties.Name -contains 'KeeperReviewCopyPath') { Get-NormalizedPath $row.KeeperReviewCopyPath } else { '' }
            DestinationSubfolder = $subfolder
            ReviewConfidence     = $confidence
            ReviewReason         = $row.ReviewReason.Trim()
        }
        $seenEntries[$key] = $entry
        [void]$entries.Add($entry)
    }
    if ($entries.Count -eq 0) {
        throw "Approved review move plan contains no usable rows: $PlanPath"
    }
    return [pscustomobject]@{
        Entries            = @($entries.ToArray())
        RawPathCount       = $rawPathCount
        DuplicatePathCount = $duplicatePathCount
    }
}

function Get-InventoryIndex {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Inventory CSV not found: $Path"
    }
    $rows = @(Import-Csv -LiteralPath $Path)
    if ($rows.Count -eq 0) {
        throw "Inventory CSV contains no rows: $Path"
    }
    $index = @{}
    $duplicatePaths = New-Object System.Collections.Generic.List[string]
    foreach ($row in $rows) {
        if ($script:InventoryCouplingMode -eq 'SunsPngReport') {
            $key = (Get-NormalizedPath $row.FullName).ToUpperInvariant()
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if ($index.ContainsKey($key)) {
                [void]$duplicatePaths.Add($row.FullName)
            }
            else {
                $index[$key] = [pscustomobject]@{
                    StagedDuplicatePath  = Get-NormalizedPath $row.FullName
                    Hash                 = Get-NormalizedHash $row.SHA256
                    SizeBytes            = $row.SizeBytes
                    DestinationSubfolder = 'suns_png_root'
                    LikelyClass          = $row.LikelyClass.Trim()
                    SuggestedLane        = $row.SuggestedLane.Trim()
                    ReviewReason         = $row.ReviewReason.Trim()
                }
            }
        }
        elseif ($script:InventoryCouplingMode -eq 'PstPolicyReport') {
            $key = (Get-NormalizedPath $row.StagedDuplicatePath).ToUpperInvariant()
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if ($index.ContainsKey($key)) {
                [void]$duplicatePaths.Add($row.StagedDuplicatePath)
            }
            else {
                $index[$key] = [pscustomobject]@{
                    StagedDuplicatePath    = Get-NormalizedPath $row.StagedDuplicatePath
                    Hash                   = Get-NormalizedHash $row.SHA256
                    SizeBytes              = $row.SizeBytes
                    DestinationSubfolder   = 'mail\pst'
                    SuggestedPolicyLane    = $row.SuggestedPolicyLane.Trim()
                    KeeperPath             = Get-NormalizedPath $row.KeeperPath
                    KeeperReviewCopyPath   = Get-NormalizedPath $row.KeeperReviewCopyPath
                    KeeperExists           = $row.KeeperExists
                    KeeperHashMatches      = $row.KeeperHashMatches
                    KeeperReviewCopyExists = $row.KeeperReviewCopyExists
                    ReviewReason           = $row.PolicyReason.Trim()
                }
            }
        }
        elseif ($script:InventoryCouplingMode -eq 'Phase2BmpInventory') {
            $key = (Get-NormalizedPath $row.FullName).ToUpperInvariant()
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if ($index.ContainsKey($key)) {
                [void]$duplicatePaths.Add($row.FullName)
            }
            else {
                $index[$key] = [pscustomobject]@{
                    FullName             = Get-NormalizedPath $row.FullName
                    Hash                 = Get-NormalizedHash $row.Hash
                    SizeBytes            = $row.SizeBytes
                    DestinationSubfolder = $row.SuggestedDestinationSubfolder.Trim()
                    SuggestedPolicyLane  = $row.SuggestedPolicyLane.Trim()
                    IsPhotoLikeBmp       = $row.IsPhotoLikeBmp
                    ReviewReason         = $row.ReviewReason.Trim()
                }
            }
        }
        else {
            $key = (Get-NormalizedPath $row.StagedDuplicatePath).ToUpperInvariant()
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if ($index.ContainsKey($key)) {
                [void]$duplicatePaths.Add($row.StagedDuplicatePath)
            }
            else {
                $index[$key] = $row
            }
        }
    }
    if ($duplicatePaths.Count -gt 0) {
        throw "Inventory CSV contains duplicate normalized StagedDuplicatePath entries (fail closed): $($duplicatePaths -join '; ')"
    }
    return [pscustomobject]@{
        Rows  = $rows
        Index = $index
    }
}

function Get-PlanInventoryCouplingIssues {
    param(
        [Parameter(Mandatory = $true)]$PlanRow,
        $InventoryRow
    )
    $issues = New-Object System.Collections.Generic.List[string]
    if ($null -eq $InventoryRow) {
        [void]$issues.Add('InventoryRowMissing')
        return @($issues)
    }
    if ($script:InventoryCouplingMode -eq 'SunsPngReport') {
        if ((Get-NormalizedHash $InventoryRow.Hash) -ne $PlanRow.Hash) {
            [void]$issues.Add('InventoryHashMismatch')
        }
        if ([int64]$InventoryRow.SizeBytes -ne [int64]$PlanRow.SizeBytes) {
            [void]$issues.Add('InventorySizeMismatch')
        }
        if ($InventoryRow.DestinationSubfolder.Trim() -ne $PlanRow.DestinationSubfolder) {
            [void]$issues.Add('InventorySubfolderMismatch')
        }
        if ($InventoryRow.SuggestedLane -ne 'medium_review\suns_png') {
            [void]$issues.Add('InventorySuggestedLaneMismatch')
        }
        if ($InventoryRow.LikelyClass -in @('UnknownPng', 'UnexpectedNonPst')) {
            [void]$issues.Add('InventoryLikelyClassRejected')
        }
        if ($InventoryRow.LikelyClass -notin @('SunsPngDuplicate', 'CollisionLeftover')) {
            [void]$issues.Add('InventoryLikelyClassMismatch')
        }
        return @($issues)
    }
    if ($script:InventoryCouplingMode -eq 'PstPolicyReport') {
        if ((Get-NormalizedHash $InventoryRow.Hash) -ne $PlanRow.Hash) {
            [void]$issues.Add('InventoryHashMismatch')
        }
        if ([int64]$InventoryRow.SizeBytes -ne [int64]$PlanRow.SizeBytes) {
            [void]$issues.Add('InventorySizeMismatch')
        }
        if ($InventoryRow.DestinationSubfolder.Trim() -ne $PlanRow.DestinationSubfolder) {
            [void]$issues.Add('InventorySubfolderMismatch')
        }
        if ($InventoryRow.SuggestedPolicyLane -ne 'REVIEW_GROUP_CANDIDATE') {
            [void]$issues.Add('InventoryPolicyLaneMismatch')
        }
        if ($InventoryRow.SuggestedPolicyLane -eq 'BLOCKED') {
            [void]$issues.Add('InventoryPolicyLaneBlocked')
        }
        if ($InventoryRow.SuggestedPolicyLane -eq 'HOLD_MAIL_ARCHIVE') {
            [void]$issues.Add('InventoryPolicyLaneHold')
        }
        if ($InventoryRow.KeeperExists -ne 'True') {
            [void]$issues.Add('InventoryKeeperMissing')
        }
        if ($InventoryRow.KeeperHashMatches -ne 'True') {
            [void]$issues.Add('InventoryKeeperHashMismatch')
        }
        if ($InventoryRow.KeeperReviewCopyExists -ne 'True') {
            [void]$issues.Add('InventoryKeeperReviewCopyMissing')
        }
        if ((Get-NormalizedPath $InventoryRow.KeeperPath) -ne (Get-NormalizedPath $PlanRow.KeeperPath) -and
            -not [string]::IsNullOrWhiteSpace($PlanRow.KeeperPath)) {
            [void]$issues.Add('InventoryKeeperMismatch')
        }
        return @($issues)
    }
    if ($script:InventoryCouplingMode -eq 'Phase2BmpInventory') {
        if ((Get-NormalizedHash $InventoryRow.Hash) -ne $PlanRow.Hash) {
            [void]$issues.Add('InventoryHashMismatch')
        }
        if ([int64]$InventoryRow.SizeBytes -ne [int64]$PlanRow.SizeBytes) {
            [void]$issues.Add('InventorySizeMismatch')
        }
        if ($InventoryRow.DestinationSubfolder.Trim() -ne $PlanRow.DestinationSubfolder) {
            [void]$issues.Add('InventorySubfolderMismatch')
        }
        if ($InventoryRow.SuggestedPolicyLane -ne 'MEDIUM_REVIEW_IMAGES_BMP') {
            [void]$issues.Add('InventoryPolicyLaneMismatch')
        }
        if ($InventoryRow.SuggestedPolicyLane -eq 'HUMAN_REVIEW_IMAGE_BMP') {
            [void]$issues.Add('InventoryHumanReviewLane')
        }
        if ($InventoryRow.SuggestedPolicyLane -eq 'BLOCKED_INVESTIGATE') {
            [void]$issues.Add('InventoryBlockedLane')
        }
        if ($InventoryRow.IsPhotoLikeBmp -eq 'True') {
            [void]$issues.Add('InventoryPhotoLikeBmp')
        }
        return @($issues)
    }
    if ((Get-NormalizedHash $InventoryRow.Hash) -ne $PlanRow.Hash) {
        [void]$issues.Add('InventoryHashMismatch')
    }
    if ([int64]$InventoryRow.SizeBytes -ne [int64]$PlanRow.SizeBytes) {
        [void]$issues.Add('InventorySizeMismatch')
    }
    if ((Get-NormalizedPath $InventoryRow.KeeperPath) -ne (Get-NormalizedPath $PlanRow.KeeperPath) -and
        -not [string]::IsNullOrWhiteSpace($PlanRow.KeeperPath)) {
        [void]$issues.Add('InventoryKeeperMismatch')
    }
    if ($InventoryRow.DestinationSubfolder.Trim() -ne $PlanRow.DestinationSubfolder) {
        [void]$issues.Add('InventorySubfolderMismatch')
    }
    $planConfidence = if ($PlanRow.PSObject.Properties.Name -contains 'ReviewConfidence') {
        $PlanRow.ReviewConfidence.Trim().ToUpperInvariant()
    } else {
        $PlanRow.DeleteConfidence.Trim().ToUpperInvariant()
    }
    if ($InventoryRow.DeleteConfidence.Trim().ToUpperInvariant() -ne $planConfidence) {
        [void]$issues.Add('InventoryReviewConfidenceMismatch')
    }
    if ($InventoryRow.DestinationHashMatches -ne 'True') {
        [void]$issues.Add('InventoryDestinationHashMismatch')
    }
    if ($InventoryRow.KeeperHashMatches -ne 'True') {
        [void]$issues.Add('InventoryKeeperHashMismatch')
    }
    if ($InventoryRow.DestinationExists -ne 'True') {
        [void]$issues.Add('InventoryDestinationMissing')
    }
    if ($InventoryRow.KeeperExists -ne 'True') {
        [void]$issues.Add('InventoryKeeperMissing')
    }
    if ($InventoryRow.SourceGone -ne 'True') {
        [void]$issues.Add('InventorySourceNotGone')
    }
    return @($issues)
}

function Test-InventoryRowEligible {
    param([Parameter(Mandatory = $true)]$Row)
    if ($script:InventoryCouplingMode -eq 'SunsPngReport') {
        return (
            $Row.LikelyClass -in @('SunsPngDuplicate', 'CollisionLeftover') -and
            $Row.SuggestedLane -eq 'medium_review\suns_png' -and
            $script:ApprovedSourceSubfolders -contains $Row.DestinationSubfolder
        )
    }
    if ($script:InventoryCouplingMode -eq 'PstPolicyReport') {
        return (
            $Row.SuggestedPolicyLane -eq 'REVIEW_GROUP_CANDIDATE' -and
            $Row.KeeperExists -eq 'True' -and
            $Row.KeeperHashMatches -eq 'True' -and
            $Row.KeeperReviewCopyExists -eq 'True' -and
            $script:ApprovedSourceSubfolders -contains 'mail\pst'
        )
    }
    if ($script:InventoryCouplingMode -eq 'Phase2BmpInventory') {
        return (
            $Row.SuggestedPolicyLane -eq 'MEDIUM_REVIEW_IMAGES_BMP' -and
            $Row.DestinationSubfolder -eq 'medium_review\images\bmp' -and
            $Row.IsPhotoLikeBmp -ne 'True'
        )
    }
    return (
        $Row.DeleteConfidence -eq $script:RequiredReviewConfidence -and
        $Row.MoveStatus -in $script:VerifiedMoveStatuses -and
        $Row.SourceGone -eq 'True' -and
        $Row.DestinationExists -eq 'True' -and
        $Row.DestinationHashMatches -eq 'True' -and
        $Row.KeeperExists -eq 'True' -and
        $Row.KeeperHashMatches -eq 'True' -and
        $script:ApprovedSourceSubfolders -contains $Row.DestinationSubfolder
    )
}

function Test-ReviewMoveCandidateLive {
    param(
        [Parameter(Mandatory = $true)]$PlanRow,
        [Parameter(Mandatory = $true)][string]$DeleteReviewRoot,
        [Parameter(Mandatory = $true)]$InventoryRow
    )
    $issues = New-Object System.Collections.Generic.List[string]
    $stagedPath = $PlanRow.StagedDuplicatePath
    $keeperPath = ''
    if ($script:RequiresKeeperVerification) {
        $keeperPath = if ($null -ne $InventoryRow -and
            ($InventoryRow.PSObject.Properties.Name -contains 'KeeperPath') -and
            -not [string]::IsNullOrWhiteSpace($InventoryRow.KeeperPath)) {
            Get-NormalizedPath $InventoryRow.KeeperPath
        }
        else {
            Get-NormalizedPath $PlanRow.KeeperPath
        }
    }

    foreach ($couplingIssue in (Get-PlanInventoryCouplingIssues -PlanRow $PlanRow -InventoryRow $InventoryRow)) {
        [void]$issues.Add($couplingIssue)
    }
    if ($null -ne $InventoryRow -and -not (Test-InventoryRowEligible -Row $InventoryRow)) {
        [void]$issues.Add('InventoryRowNotEligible')
    }

    if (-not (Test-StagedPathInApprovedSourceRoot -Path $stagedPath)) {
        [void]$issues.Add('OutsideApprovedStagedRoot')
    }
    if ($script:UsesPhase2RecoverSource) {
        if (Test-PathUnderWorkbenchExclude -Path $stagedPath) {
            [void]$issues.Add('UnderWorkbenchExcludeRoot')
        }
    }
    else {
        if (-not (Test-PathInsideRoot -ChildPath $stagedPath -RootPath $script:StagedDuplicatesRoot)) {
            [void]$issues.Add('OutsideStagedDuplicatesRoot')
        }
        if (Test-PathUnderDeniedPrefix -Path $stagedPath) {
            [void]$issues.Add('DeniedPrefixStaged')
        }
    }
    if ([IO.Path]::GetExtension($stagedPath).ToLowerInvariant() -ne $script:RequiredFileExtension) {
        [void]$issues.Add('WrongExtension')
    }
    $planConfidence = $PlanRow.ReviewConfidence
    if ($planConfidence -ne $script:RequiredReviewConfidence) {
        [void]$issues.Add('NotRequiredReviewConfidence')
    }
    if ($script:ApprovedSourceSubfolders -notcontains $PlanRow.DestinationSubfolder) {
        [void]$issues.Add('WrongSubfolder')
    }
    if (-not (Test-PathInsideRoot -ChildPath $PlanRow.DeleteReviewPath -RootPath $DeleteReviewRoot)) {
        [void]$issues.Add('DeleteReviewOutsideRoot')
    }

    $sourceReparse = Test-ReparsePathChain -Path $stagedPath -Mode Source
    if (-not $sourceReparse.Safe) {
        [void]$issues.Add($sourceReparse.Status)
    }
    $reviewRootReparse = Test-ReparsePathChain -Path $DeleteReviewRoot -Mode Destination
    if (-not $reviewRootReparse.Safe) {
        [void]$issues.Add($reviewRootReparse.Status)
    }
    $destParentForReparse = Split-Path -Parent $PlanRow.DeleteReviewPath
    if (-not [string]::IsNullOrWhiteSpace($destParentForReparse)) {
        $destReparse = Test-ReparsePathChain -Path $destParentForReparse -Mode Destination
        if (-not $destReparse.Safe) {
            [void]$issues.Add($destReparse.Status)
        }
    }

    if (-not (Test-Path -LiteralPath $stagedPath)) {
        [void]$issues.Add('StagedMissing')
    }
    elseif (Test-Path -LiteralPath $stagedPath -PathType Container) {
        [void]$issues.Add('StagedIsDirectory')
    }
    else {
        try {
            $liveHash = Get-NormalizedHash (Get-FileHash -LiteralPath $stagedPath -Algorithm SHA256).Hash
            if ($liveHash -ne $PlanRow.Hash) {
                [void]$issues.Add('StagedHashMismatch')
            }
            $liveSize = (Get-Item -LiteralPath $stagedPath -Force).Length
            if ([int64]$liveSize -ne [int64]$PlanRow.SizeBytes) {
                [void]$issues.Add('StagedSizeMismatch')
            }
        }
        catch {
            [void]$issues.Add('StagedHashCheckFailed')
        }
    }

    if ($script:RequiresKeeperVerification) {
        if (-not (Test-Path -LiteralPath $keeperPath)) {
            [void]$issues.Add('KeeperMissing')
        }
        else {
            try {
                $keeperHash = Get-NormalizedHash (Get-FileHash -LiteralPath $keeperPath -Algorithm SHA256).Hash
                if ($keeperHash -ne $PlanRow.Hash) {
                    [void]$issues.Add('KeeperHashMismatch')
                }
            }
            catch {
                [void]$issues.Add('KeeperHashCheckFailed')
            }
        }
    }

    if ($script:RequiresKeeperReviewCopy) {
        $reviewCopyPath = if ($null -ne $InventoryRow -and
            ($InventoryRow.PSObject.Properties.Name -contains 'KeeperReviewCopyPath') -and
            -not [string]::IsNullOrWhiteSpace($InventoryRow.KeeperReviewCopyPath)) {
            Get-NormalizedPath $InventoryRow.KeeperReviewCopyPath
        }
        elseif ($PlanRow.PSObject.Properties.Name -contains 'KeeperReviewCopyPath' -and
            -not [string]::IsNullOrWhiteSpace($PlanRow.KeeperReviewCopyPath)) {
            Get-NormalizedPath $PlanRow.KeeperReviewCopyPath
        }
        else {
            ''
        }
        if ([string]::IsNullOrWhiteSpace($reviewCopyPath)) {
            [void]$issues.Add('KeeperReviewCopyPathMissing')
        }
        elseif (-not (Test-Path -LiteralPath $reviewCopyPath)) {
            [void]$issues.Add('KeeperReviewCopyMissing')
        }
        else {
            try {
                $reviewCopyHash = Get-NormalizedHash (Get-FileHash -LiteralPath $reviewCopyPath -Algorithm SHA256).Hash
                if ($reviewCopyHash -ne $PlanRow.Hash) {
                    [void]$issues.Add('KeeperReviewCopyHashMismatch')
                }
            }
            catch {
                [void]$issues.Add('KeeperReviewCopyHashCheckFailed')
            }
        }
    }

    if (-not (Test-SameVolume -PathA $stagedPath -PathB $PlanRow.DeleteReviewPath)) {
        [void]$issues.Add('CrossVolumeRejected')
    }

    $ready = ($issues.Count -eq 0)
    return [pscustomobject]@{
        Ready   = $ready
        Status  = if ($ready) { 'DryRunReady' } else { ($issues -join ';') }
        Message = if ($ready) { 'Ready for delete review move.' } else { ($issues -join '; ') }
        Issues  = @($issues)
    }
}

function Test-ExecutePreflightRow {
    param(
        [Parameter(Mandatory = $true)]$PreflightRow,
        [Parameter(Mandatory = $true)][string]$DeleteReviewRoot,
        [Parameter(Mandatory = $true)]$InventoryRow
    )
    $issues = New-Object System.Collections.Generic.List[string]
    $stagedPath = $PreflightRow.StagedDuplicatePath
    $keeperPath = ''
    if ($script:RequiresKeeperVerification) {
        $keeperPath = if ($null -ne $InventoryRow -and
            ($InventoryRow.PSObject.Properties.Name -contains 'KeeperPath') -and
            -not [string]::IsNullOrWhiteSpace($InventoryRow.KeeperPath)) {
            Get-NormalizedPath $InventoryRow.KeeperPath
        }
        else {
            Get-NormalizedPath $PreflightRow.KeeperPath
        }
    }
    $plannedDest = $PreflightRow.PlannedDeleteReviewPath

    foreach ($couplingIssue in (Get-PlanInventoryCouplingIssues -PlanRow $PreflightRow -InventoryRow $InventoryRow)) {
        [void]$issues.Add($couplingIssue)
    }

    if (-not (Test-PathInsideRoot -ChildPath $stagedPath -RootPath $script:StagedDuplicatesRoot)) {
        [void]$issues.Add('OutsideStagedDuplicatesRoot')
    }
    if (-not (Test-StagedPathInApprovedSourceRoot -Path $stagedPath)) {
        [void]$issues.Add('OutsideApprovedStagedRoot')
    }
    if ($script:UsesPhase2RecoverSource) {
        if (Test-PathUnderWorkbenchExclude -Path $stagedPath) {
            [void]$issues.Add('UnderWorkbenchExcludeRoot')
        }
    }
    else {
        if (Test-PathUnderDeniedPrefix -Path $stagedPath) {
            [void]$issues.Add('DeniedPrefixStaged')
        }
    }
    if ([IO.Path]::GetExtension($stagedPath).ToLowerInvariant() -ne $script:RequiredFileExtension) {
        [void]$issues.Add('WrongExtension')
    }
    if (-not (Test-PathInsideRoot -ChildPath $plannedDest -RootPath $DeleteReviewRoot)) {
        [void]$issues.Add('DeleteReviewOutsideRoot')
    }

    $sourceReparse = Test-ReparsePathChain -Path $stagedPath -Mode Source
    if (-not $sourceReparse.Safe) { [void]$issues.Add($sourceReparse.Status) }
    $reviewRootReparse = Test-ReparsePathChain -Path $DeleteReviewRoot -Mode Destination
    if (-not $reviewRootReparse.Safe) { [void]$issues.Add($reviewRootReparse.Status) }

    $destParent = Split-Path -Parent $plannedDest
    if ([string]::IsNullOrWhiteSpace($destParent)) {
        [void]$issues.Add('DestinationParentMissing')
    }
    else {
        if (-not (Test-PathInsideRoot -ChildPath $destParent -RootPath $DeleteReviewRoot)) {
            [void]$issues.Add('DestinationParentOutsideRoot')
        }
        $destReparse = Test-ReparsePathChain -Path $destParent -Mode Destination
        if (-not $destReparse.Safe) { [void]$issues.Add($destReparse.Status) }
        if (Test-Path -LiteralPath $destParent) {
            if (-not (Test-Path -LiteralPath $destParent -PathType Container)) {
                [void]$issues.Add('DestinationParentNotDirectory')
            }
        }
    }

    if (-not (Test-Path -LiteralPath $stagedPath)) {
        [void]$issues.Add('StagedMissing')
    }
    elseif (Test-Path -LiteralPath $stagedPath -PathType Container) {
        [void]$issues.Add('StagedIsDirectory')
    }
    else {
        try {
            $liveHash = Get-NormalizedHash (Get-FileHash -LiteralPath $stagedPath -Algorithm SHA256).Hash
            if ($liveHash -ne $PreflightRow.Hash) { [void]$issues.Add('StagedHashMismatch') }
            $liveSize = (Get-Item -LiteralPath $stagedPath -Force).Length
            if ([int64]$liveSize -ne [int64]$PreflightRow.SizeBytes) { [void]$issues.Add('StagedSizeMismatch') }
        }
        catch {
            [void]$issues.Add('StagedHashCheckFailed')
        }
    }

    if ($script:RequiresKeeperVerification) {
        if (-not (Test-Path -LiteralPath $keeperPath)) {
            [void]$issues.Add('KeeperMissing')
        }
        else {
            try {
                $keeperHash = Get-NormalizedHash (Get-FileHash -LiteralPath $keeperPath -Algorithm SHA256).Hash
                if ($keeperHash -ne $PreflightRow.Hash) { [void]$issues.Add('KeeperHashMismatch') }
            }
            catch {
                [void]$issues.Add('KeeperHashCheckFailed')
            }
        }
    }

    if (Test-Path -LiteralPath $plannedDest) {
        [void]$issues.Add('DestinationCollisionNotPreplanned')
    }

    if (-not (Test-SameVolume -PathA $stagedPath -PathB $plannedDest)) {
        [void]$issues.Add('CrossVolumeRejected')
    }

    $ready = ($issues.Count -eq 0)
    return [pscustomobject]@{
        Ready   = $ready
        Status  = if ($ready) { 'ExecutePreflightReady' } else { ($issues -join ';') }
        Message = if ($ready) { 'Execute preflight passed for row.' } else { ($issues -join '; ') }
        Issues  = @($issues)
    }
}

function Write-LogLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function Write-ReviewMoveJournalEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Entry
    )
    $row = [ordered]@{
        RunStamp            = $Entry.RunStamp
        Sequence            = $Entry.Sequence
        Phase               = $Entry.Phase
        Hash                = $Entry.Hash
        StagedDuplicatePath = $Entry.StagedDuplicatePath
        DeleteReviewPath    = $Entry.DeleteReviewPath
        KeeperPath          = $Entry.KeeperPath
        StagedHashBefore    = $Entry.StagedHashBefore
        ReviewHashAfter     = $Entry.ReviewHashAfter
        KeeperHashBefore    = $Entry.KeeperHashBefore
        Status              = $Entry.Status
        ErrorMessage        = $Entry.ErrorMessage
        TimestampUtc        = $Entry.TimestampUtc
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        [pscustomobject]$row | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    }
    else {
        [pscustomobject]$row | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -Append
    }
}

if ($Execute -and -not $PSBoundParameters.ContainsKey('ExpectedApprovedReviewMovePlanHash')) {
    throw '-ExpectedApprovedReviewMovePlanHash is required when using -Execute.'
}

if (-not (Test-Path -LiteralPath $ApprovedReviewMovePlan)) {
    throw "Approved review move plan not found: $ApprovedReviewMovePlan"
}

$planFileHash = Get-ApprovedReviewMovePlanFileSha256 -Path $ApprovedReviewMovePlan
Write-Host "ApprovedReviewMovePlan SHA-256: $planFileHash"
if ($PSBoundParameters.ContainsKey('ExpectedApprovedReviewMovePlanHash')) {
    $expectedHash = Get-NormalizedHash $ExpectedApprovedReviewMovePlanHash
    if ($planFileHash -ne $expectedHash) {
        throw "Approved review move plan SHA-256 mismatch. Expected=$expectedHash Actual=$planFileHash"
    }
    Write-Host "ApprovedReviewMovePlan expected SHA-256: $expectedHash (verified)"
}

if (-not $PSBoundParameters.ContainsKey('RunStamp')) {
    if ($ApprovedReviewMovePlan -match '(\d{8}-\d{6})') {
        $RunStamp = $Matches[1]
    }
    elseif ($ApprovedReviewMovePlan -match '(\d{8})') {
        $RunStamp = $Matches[1]
    }
    else {
        $RunStamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    }
}

$reportRootNormalized = Get-NormalizedPath $ReportRoot
if ($script:UsesHumanReviewRoot) {
    $deleteReviewRootNormalized = Get-NormalizedPath $HumanReviewRoot
}
else {
    $deleteReviewRootNormalized = Get-NormalizedPath $DeleteReviewRoot
}
if (Test-PathInsideRoot -ChildPath $reportRootNormalized -RootPath 'I:\') {
    throw "ReportRoot must be outside I:\. ReportRoot=$reportRootNormalized"
}
if (-not (Test-Path -LiteralPath $reportRootNormalized)) {
    New-Item -ItemType Directory -Path $reportRootNormalized -Force | Out-Null
}

$runMode = if ($Execute) { 'Execute' } else { 'DryRun' }
$preflightReport = Join-Path $reportRootNormalized "$($script:ReportNamePrefix)_preflight_$RunStamp.csv"
$logReport = Join-Path $reportRootNormalized "$($script:ReportNamePrefix)_log_$RunStamp.txt"
$executionJournal = Join-Path $reportRootNormalized "$($script:ReportNamePrefix)_journal_$RunStamp.csv"
$executionManifest = Join-Path $reportRootNormalized "$($script:ReportNamePrefix)_manifest_$RunStamp.csv"
$executePreflightFailedReport = Join-Path $reportRootNormalized "$($script:ReportNamePrefix)_execute_preflight_failed_$RunStamp.csv"

$inventoryData = Get-InventoryIndex -Path $InventoryCsvPath
$planReadResult = Read-ApprovedReviewMovePlan -PlanPath $ApprovedReviewMovePlan -DeleteReviewRoot $deleteReviewRootNormalized
$planEntries = $planReadResult.Entries

Write-LogLine -Path $logReport -Message "START Move-StagedWorkbenchLaneToReview v0.2.7 LaneProfile=$LaneProfile mode=$runMode stamp=$RunStamp"
Write-LogLine -Path $logReport -Message "InventoryCsvPath=$InventoryCsvPath"
Write-LogLine -Path $logReport -Message "ApprovedReviewMovePlan=$ApprovedReviewMovePlan"
Write-LogLine -Path $logReport -Message "ApprovedReviewMovePlan_FileSha256=$planFileHash"
$reviewRootLabel = if ($script:UsesHumanReviewRoot) { "HumanReviewRoot=$deleteReviewRootNormalized" } else { "DeleteReviewRoot=$deleteReviewRootNormalized" }
Write-LogLine -Path $logReport -Message "$reviewRootLabel ExpectedApprovedReviewMovePlanHash=$ExpectedApprovedReviewMovePlanHash Execute=$Execute"

$started = Get-Date
$preflightRows = New-Object System.Collections.Generic.List[object]
$reservedReviewNames = @{}
$readyCount = 0
$blockedCount = 0
$preflightId = 0

foreach ($planRow in $planEntries) {
    $preflightId++
    $inventoryRow = $null
    $invKey = $planRow.StagedDuplicatePath.ToUpperInvariant()
    if ($inventoryData.Index.ContainsKey($invKey)) {
        $inventoryRow = $inventoryData.Index[$invKey]
        if ($script:RequiresKeeperVerification -and
            ($inventoryRow.PSObject.Properties.Name -contains 'KeeperPath') -and
            -not [string]::IsNullOrWhiteSpace($inventoryRow.KeeperPath)) {
            $planRow.KeeperPath = Get-NormalizedPath $inventoryRow.KeeperPath
        }
        elseif (-not [string]::IsNullOrWhiteSpace($planRow.KeeperPath)) {
            $planRow.KeeperPath = Get-NormalizedPath $planRow.KeeperPath
        }
        if ($script:RequiresKeeperReviewCopy -and
            ($inventoryRow.PSObject.Properties.Name -contains 'KeeperReviewCopyPath') -and
            -not [string]::IsNullOrWhiteSpace($inventoryRow.KeeperReviewCopyPath)) {
            $planRow.KeeperReviewCopyPath = Get-NormalizedPath $inventoryRow.KeeperReviewCopyPath
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($planRow.KeeperPath)) {
        $planRow.KeeperPath = Get-NormalizedPath $planRow.KeeperPath
    }
    if ($planRow.PSObject.Properties.Name -contains 'KeeperReviewCopyPath' -and
        -not [string]::IsNullOrWhiteSpace($planRow.KeeperReviewCopyPath)) {
        $planRow.KeeperReviewCopyPath = Get-NormalizedPath $planRow.KeeperReviewCopyPath
    }
    $live = Test-ReviewMoveCandidateLive -PlanRow $planRow -DeleteReviewRoot $deleteReviewRootNormalized -InventoryRow $inventoryRow
    $plannedDeleteReviewPath = $planRow.DeleteReviewPath
    $collisionSuffix = ''
    $preflightStatus = $live.Status
    $preflightMessage = $live.Message

    if ($live.Ready) {
        $reviewDir = Split-Path -Parent $planRow.DeleteReviewPath
        $baseFileName = Split-Path -Leaf $planRow.DeleteReviewPath
        $laneKey = $reviewDir.ToUpperInvariant()
        if (-not $reservedReviewNames.ContainsKey($laneKey)) {
            $reservedReviewNames[$laneKey] = @{}
        }
        $unique = Get-UniqueDeleteReviewDestination -BaseFileName $baseFileName -DestinationDirectory $reviewDir -ReservedNames $reservedReviewNames[$laneKey]
        $plannedDeleteReviewPath = Get-NormalizedPath $unique.PlannedDeleteReviewPath
        $collisionSuffix = $unique.CollisionSuffix
        if ($unique.CollisionStatus -eq 'CollisionRenamed') {
            $preflightStatus = 'CollisionRenamed'
            $preflightMessage = 'Collision-safe delete review destination allocated.'
        }
        else {
            $preflightStatus = 'DryRunReady'
        }
        $readyCount++
    }
    else {
        $blockedCount++
    }

    [void]$preflightRows.Add([pscustomobject]@{
        PreflightId          = $preflightId
        Hash                 = $planRow.Hash
        ShortHash            = $planRow.ShortHash
        SizeBytes            = $planRow.SizeBytes
        StagedDuplicatePath  = $planRow.StagedDuplicatePath
        PlannedDeleteReviewPath = $plannedDeleteReviewPath
        DeleteReviewPath     = $planRow.DeleteReviewPath
        KeeperPath           = $planRow.KeeperPath
        DestinationSubfolder = $planRow.DestinationSubfolder
        ReviewConfidence     = $planRow.ReviewConfidence
        ReviewReason         = $planRow.ReviewReason
        CollisionSuffix      = $collisionSuffix
        PreflightStatus      = $preflightStatus
        PreflightMessage     = $preflightMessage
        RunMode              = $runMode
        PreflightAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
    })
}

$preflightRows | Export-Csv -LiteralPath $preflightReport -NoTypeInformation -Encoding UTF8

$totalBytes = ($planEntries | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
$laneGroups = $preflightRows | ForEach-Object {
    $lane = Split-Path -Parent $_.PlannedDeleteReviewPath
    [pscustomobject]@{ Lane = $lane; Row = $_ }
} | Group-Object Lane | Sort-Object Name

Write-Host ''
Write-Host 'SUMMARY'
Write-Host "PlanRows=$($planEntries.Count)"
Write-Host "Mode=$runMode Elapsed=$(((Get-Date) - $started).ToString('hh\:mm\:ss'))"
Write-Host "Ready=$readyCount"
Write-Host "Blocked=$blockedCount"
foreach ($g in $laneGroups) {
    $laneName = $g.Name.Replace($deleteReviewRootNormalized + '\', '')
    Write-Host "ReviewLane $laneName=$($g.Count)"
}
Write-Host "TotalBytes=$totalBytes"
Write-Host "PreflightReport=$preflightReport"
Write-Host "LogReport=$logReport"

Write-LogLine -Path $logReport -Message "PlanRows=$($planEntries.Count) Ready=$readyCount Blocked=$blockedCount TotalBytes=$totalBytes"
foreach ($g in $laneGroups) {
    $laneName = $g.Name.Replace($deleteReviewRootNormalized + '\', '')
    Write-LogLine -Path $logReport -Message "ReviewLane $laneName=$($g.Count)"
}

if ($Execute) {
    $batchValidationOffenders = @($preflightRows | Where-Object { $_.PreflightStatus -notin $script:BatchExecuteReadyStatuses })
    if ($batchValidationOffenders.Count -gt 0) {
        Write-Host ''
        Write-Host '=== BatchValidationFailed ==='
        Write-Host 'Batch move aborted before any Move-Item. No files were moved.'
        Write-LogLine -Path $logReport -Message 'BATCH_VALIDATION_FAILED'
        foreach ($offender in $batchValidationOffenders) {
            Write-Host "  StagedDuplicatePath: $($offender.StagedDuplicatePath)"
            Write-Host "  Status:              $($offender.PreflightStatus)"
            Write-Host "  Message:             $($offender.PreflightMessage)"
            Write-LogLine -Path $logReport -Message ("BatchValidationFailed_Offender Path={0} Status={1} Message={2}" -f $offender.StagedDuplicatePath, $offender.PreflightStatus, $offender.PreflightMessage)
        }
        throw 'Batch move aborted: one or more approved review move rows are not ready. No files were moved.'
    }
    Write-LogLine -Path $logReport -Message 'BATCH_VALIDATION_PASSED'
    Write-LogLine -Path $logReport -Message "BatchValidationPassed_ReadyCount=$readyCount"

    $executeReadyRows = @($preflightRows | Where-Object { $_.PreflightStatus -in $script:BatchExecuteReadyStatuses })
    $executePreflightOffenders = New-Object System.Collections.Generic.List[object]
    foreach ($item in $executeReadyRows) {
        $invKey = $item.StagedDuplicatePath.ToUpperInvariant()
        $inventoryRow = $null
        if ($inventoryData.Index.ContainsKey($invKey)) {
            $inventoryRow = $inventoryData.Index[$invKey]
        }
        $ep = Test-ExecutePreflightRow -PreflightRow $item -DeleteReviewRoot $deleteReviewRootNormalized -InventoryRow $inventoryRow
        if (-not $ep.Ready) {
            [void]$executePreflightOffenders.Add([pscustomobject]@{
                PreflightId             = $item.PreflightId
                StagedDuplicatePath     = $item.StagedDuplicatePath
                PlannedDeleteReviewPath = $item.PlannedDeleteReviewPath
                KeeperPath              = $item.KeeperPath
                Hash                    = $item.Hash
                PreflightStatus         = $item.PreflightStatus
                ExecutePreflightStatus  = $ep.Status
                ExecutePreflightMessage = $ep.Message
                Issues                  = ($ep.Issues -join ';')
            })
        }
    }

    if ($executePreflightOffenders.Count -gt 0) {
        Write-Host ''
        Write-Host '=== ExecutePreflightFailed ==='
        Write-Host 'Execute preflight failed before any Move-Item. No predictable per-row blockers were cleared. No files were moved.'
        Write-Host 'This gate is fail-closed; movement is not transactionally atomic after external I/O failure.'
        Write-LogLine -Path $logReport -Message 'EXECUTE_PREFLIGHT_FAILED'
        $executePreflightOffenders | Export-Csv -LiteralPath $executePreflightFailedReport -NoTypeInformation -Encoding UTF8
        foreach ($offender in $executePreflightOffenders) {
            Write-Host "  StagedDuplicatePath: $($offender.StagedDuplicatePath)"
            Write-Host "  Status:              $($offender.ExecutePreflightStatus)"
            Write-Host "  Message:             $($offender.ExecutePreflightMessage)"
            Write-LogLine -Path $logReport -Message ("ExecutePreflightFailed_Offender Path={0} Status={1} Message={2}" -f $offender.StagedDuplicatePath, $offender.ExecutePreflightStatus, $offender.ExecutePreflightMessage)
        }
        Write-Host "ExecutePreflightFailedReport=$executePreflightFailedReport"
        throw 'Execute preflight failed: one or more rows have predictable blockers. No files were moved.'
    }

    Write-LogLine -Path $logReport -Message 'EXECUTE_PREFLIGHT_PASSED'
    Write-LogLine -Path $logReport -Message "ExecutePreflightPassed_ReadyCount=$($executeReadyRows.Count)"
    Write-Host ''
    Write-Host '=== ExecutePreflightPassed ==='
    Write-Host 'No predictable per-row blockers before first Move-Item. Movement is not transactionally atomic after external I/O failure.'

    $movedCount = 0
    $failedCount = 0
    $journalSequence = 0
    $manifestRows = New-Object System.Collections.Generic.List[object]

    foreach ($item in $executeReadyRows) {
        $executionStatus = 'MoveFailed'
        $errorMessage = ''
        $stagedHashBefore = ''
        $keeperHashBefore = ''
        $reviewHashAfter = ''
        try {
            if (-not (Test-Path -LiteralPath $item.StagedDuplicatePath)) {
                throw 'Staged duplicate missing on execute re-check.'
            }
            if (Test-Path -LiteralPath $item.StagedDuplicatePath -PathType Container) {
                throw 'Staged path is a directory; directory moves are not allowed.'
            }
            $stagedHashBefore = Get-NormalizedHash (Get-FileHash -LiteralPath $item.StagedDuplicatePath -Algorithm SHA256).Hash
            if ($stagedHashBefore -ne $item.Hash) {
                throw 'Staged hash mismatch on execute re-check.'
            }
            if ($script:RequiresKeeperVerification) {
                if (-not (Test-Path -LiteralPath $item.KeeperPath)) {
                    throw 'Keeper missing on execute re-check.'
                }
                $keeperHashBefore = Get-NormalizedHash (Get-FileHash -LiteralPath $item.KeeperPath -Algorithm SHA256).Hash
                if ($keeperHashBefore -ne $item.Hash) {
                    throw 'Keeper hash mismatch on execute re-check.'
                }
            }
            if (Test-Path -LiteralPath $item.PlannedDeleteReviewPath) {
                throw 'Delete review destination already exists on execute re-check.'
            }
            if (-not (Test-SameVolume -PathA $item.StagedDuplicatePath -PathB $item.PlannedDeleteReviewPath)) {
                throw 'Cross-volume move rejected on execute re-check.'
            }

            if ($PSCmdlet.ShouldProcess($item.StagedDuplicatePath, "Move to $($item.PlannedDeleteReviewPath)")) {
                $journalSequence++
                Write-ReviewMoveJournalEntry -Path $executionJournal -Entry @{
                    RunStamp            = $RunStamp
                    Sequence            = $journalSequence
                    Phase               = 'BEFORE_MOVE'
                    Hash                = $item.Hash
                    StagedDuplicatePath = $item.StagedDuplicatePath
                    DeleteReviewPath    = $item.PlannedDeleteReviewPath
                    KeeperPath          = $item.KeeperPath
                    StagedHashBefore    = $stagedHashBefore
                    ReviewHashAfter     = ''
                    KeeperHashBefore    = $keeperHashBefore
                    Status              = 'BEFORE_MOVE'
                    ErrorMessage        = ''
                    TimestampUtc        = (Get-Date).ToUniversalTime().ToString('o')
                }

                $destParent = Split-Path -Parent $item.PlannedDeleteReviewPath
                if (-not [string]::IsNullOrWhiteSpace($destParent) -and -not (Test-Path -LiteralPath $destParent)) {
                    New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                }

                Move-Item -LiteralPath $item.StagedDuplicatePath -Destination $item.PlannedDeleteReviewPath

                if (Test-Path -LiteralPath $item.StagedDuplicatePath) {
                    throw 'Staged duplicate still exists after move.'
                }
                if (-not (Test-Path -LiteralPath $item.PlannedDeleteReviewPath)) {
                    throw 'Delete review destination missing after move.'
                }
                $reviewHashAfter = Get-NormalizedHash (Get-FileHash -LiteralPath $item.PlannedDeleteReviewPath -Algorithm SHA256).Hash
                if ($reviewHashAfter -ne $item.Hash) {
                    throw 'Delete review hash mismatch after move.'
                }
                if ($script:RequiresKeeperVerification) {
                    if (-not (Test-Path -LiteralPath $item.KeeperPath)) {
                        throw 'Keeper missing after move.'
                    }
                    $keeperHashAfter = Get-NormalizedHash (Get-FileHash -LiteralPath $item.KeeperPath -Algorithm SHA256).Hash
                    if ($keeperHashAfter -ne $item.Hash) {
                        throw 'Keeper hash mismatch after move.'
                    }
                }

                $executionStatus = 'MovedVerified'
                $movedCount++
                $journalSequence++
                Write-ReviewMoveJournalEntry -Path $executionJournal -Entry @{
                    RunStamp            = $RunStamp
                    Sequence            = $journalSequence
                    Phase               = 'AFTER_MOVE'
                    Hash                = $item.Hash
                    StagedDuplicatePath = $item.StagedDuplicatePath
                    DeleteReviewPath    = $item.PlannedDeleteReviewPath
                    KeeperPath          = $item.KeeperPath
                    StagedHashBefore    = $stagedHashBefore
                    ReviewHashAfter     = $reviewHashAfter
                    KeeperHashBefore    = $keeperHashBefore
                    Status              = 'MOVED_VERIFIED'
                    ErrorMessage        = ''
                    TimestampUtc        = (Get-Date).ToUniversalTime().ToString('o')
                }
            }
            else {
                $executionStatus = 'WhatIfSkipped'
                $errorMessage = 'WhatIf or ShouldProcess declined.'
            }
        }
        catch {
            $failedCount++
            $errorMessage = $_.Exception.Message
            $journalSequence++
            Write-ReviewMoveJournalEntry -Path $executionJournal -Entry @{
                RunStamp            = $RunStamp
                Sequence            = $journalSequence
                Phase               = 'FAILED'
                Hash                = $item.Hash
                StagedDuplicatePath = $item.StagedDuplicatePath
                DeleteReviewPath    = $item.PlannedDeleteReviewPath
                KeeperPath          = $item.KeeperPath
                StagedHashBefore    = $stagedHashBefore
                ReviewHashAfter     = $reviewHashAfter
                KeeperHashBefore    = $keeperHashBefore
                Status              = $executionStatus
                ErrorMessage        = $errorMessage
                TimestampUtc        = (Get-Date).ToUniversalTime().ToString('o')
            }
            throw "Move failed for $($item.StagedDuplicatePath): $errorMessage"
        }
        [void]$manifestRows.Add([pscustomobject]@{
            PreflightId             = $item.PreflightId
            StagedDuplicatePath     = $item.StagedDuplicatePath
            PlannedDeleteReviewPath = $item.PlannedDeleteReviewPath
            KeeperPath              = $item.KeeperPath
            Hash                    = $item.Hash
            SizeBytes               = $item.SizeBytes
            ExecutionStatus         = $executionStatus
            ErrorMessage            = $errorMessage
            MovedAtUtc              = (Get-Date).ToUniversalTime().ToString('o')
        })
    }

    $manifestRows | Export-Csv -LiteralPath $executionManifest -NoTypeInformation -Encoding UTF8
    Write-LogLine -Path $logReport -Message "MovedVerified=$movedCount MoveFailed=$failedCount"
    Write-Host "MovedVerified=$movedCount MoveFailed=$failedCount"
    Write-Host "ExecutionJournal=$executionJournal"
    Write-Host "ExecutionManifest=$executionManifest"
}

Write-Host 'COMPLETE'
Write-LogLine -Path $logReport -Message 'COMPLETE'
