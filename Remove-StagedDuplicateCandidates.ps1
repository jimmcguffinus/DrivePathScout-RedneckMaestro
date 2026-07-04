[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InventoryCsvPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApprovedDeletePlan,

    [ValidateNotNullOrEmpty()]
    [string]$ExpectedApprovedDeletePlanHash,

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',

    [ValidateNotNullOrEmpty()]
    [string]$RunStamp,

    [switch]$Execute
)

# Staged Duplicate Delete Planner v0.2.0
# DELETE staged duplicate files only when -Execute is passed. Default is DryRun preflight.
# No Copy-Item. No Move-Item. No Rename-Item. No directory deletes. No wildcard deletes.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ApprovedDeleteRoots = @(
    'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\images\png\browser_extension_assets',
    'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\images\png\theme_assets'
)
$script:ApprovedDeleteSubfolders = @(
    'images\png\browser_extension_assets',
    'images\png\theme_assets'
)
$script:DeniedPathPrefixes = @('I:\recover\', 'I:\1tbrecover\')
$script:VerifiedMoveStatuses = @('MovedVerified')
$script:BatchExecuteReadyStatuses = @('DryRunReady')

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

function Test-PathUnderDeniedPrefix {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = Get-NormalizedPath $Path
    foreach ($prefix in $script:DeniedPathPrefixes) {
        if (Test-PathInsideRoot -ChildPath $normalized -RootPath $prefix.TrimEnd('\')) {
            return $true
        }
    }
    return $false
}

function Test-StagedPathInApprovedDeleteRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = Get-NormalizedPath $Path
    foreach ($root in $script:ApprovedDeleteRoots) {
        if (Test-PathInsideRoot -ChildPath $normalized -RootPath $root) {
            return $true
        }
    }
    return $false
}

function Test-SafeLiteralDeletePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Delete path cannot be empty.'
    }
    if ($Path -match '[\*\?]') {
        throw "Delete path must not contain wildcards: $Path"
    }
    if ($Path -match '\.\.') {
        throw "Delete path must not contain '..': $Path"
    }
    return Get-NormalizedPath $Path
}

function Get-ApprovedDeletePlanFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Approved delete plan not found: $Path"
    }
    return Get-NormalizedHash (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Read-ApprovedDeletePlan {
    param([Parameter(Mandatory = $true)][string]$PlanPath)
    if (-not (Test-Path -LiteralPath $PlanPath)) {
        throw "Approved delete plan not found: $PlanPath"
    }
    $rows = @(Import-Csv -LiteralPath $PlanPath)
    if ($rows.Count -eq 0) {
        throw "Approved delete plan contains no rows: $PlanPath"
    }
    $required = @('Hash', 'ShortHash', 'SizeBytes', 'StagedDuplicatePath', 'KeeperPath', 'DestinationSubfolder', 'DeleteConfidence', 'DeleteReason')
    $missing = @($required | Where-Object { $rows[0].PSObject.Properties.Name -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw "Approved delete plan is missing required columns: $($missing -join ', ')"
    }
    $entries = New-Object System.Collections.Generic.List[object]
    $seenEntries = @{}
    $rawPathCount = 0
    $duplicatePathCount = 0
    foreach ($row in $rows) {
        $stagedPath = Test-SafeLiteralDeletePath -Path $row.StagedDuplicatePath
        $keeperPath = Get-NormalizedPath $row.KeeperPath
        $subfolder = $row.DestinationSubfolder.Trim()
        $confidence = $row.DeleteConfidence.Trim().ToUpperInvariant()
        $hash = Get-NormalizedHash $row.Hash
        $rawPathCount++
        if ($confidence -ne 'HIGH') {
            throw "Approved delete plan row is not HIGH confidence: $stagedPath"
        }
        if ($script:ApprovedDeleteSubfolders -notcontains $subfolder) {
            throw "Approved delete plan row has disallowed DestinationSubfolder '$subfolder': $stagedPath"
        }
        if (-not (Test-StagedPathInApprovedDeleteRoot -Path $stagedPath)) {
            throw "Approved delete plan row is outside approved delete roots: $stagedPath"
        }
        if (Test-PathUnderDeniedPrefix -Path $stagedPath) {
            throw "Approved delete plan row is under denied prefix: $stagedPath"
        }
        if ((Test-Path -LiteralPath $stagedPath) -and (Test-Path -LiteralPath $stagedPath -PathType Container)) {
            throw "Approved delete plan row is a directory, not a file: $stagedPath"
        }
        $key = $stagedPath.ToUpperInvariant()
        if ($seenEntries.ContainsKey($key)) {
            $existing = $seenEntries[$key]
            if ($existing.Hash -ne $hash -or
                $existing.KeeperPath -ne $keeperPath -or
                $existing.DestinationSubfolder -ne $subfolder) {
                throw "Approved delete plan contains conflicting duplicate StagedDuplicatePath: $stagedPath"
            }
            $duplicatePathCount++
            continue
        }
        $entry = [pscustomobject]@{
            Hash                 = $hash
            ShortHash            = $row.ShortHash.Trim()
            SizeBytes            = $row.SizeBytes
            StagedDuplicatePath  = $stagedPath
            KeeperPath           = $keeperPath
            DestinationSubfolder = $subfolder
            DeleteConfidence     = $confidence
            DeleteReason         = $row.DeleteReason.Trim()
        }
        $seenEntries[$key] = $entry
        [void]$entries.Add($entry)
    }
    if ($entries.Count -eq 0) {
        throw "Approved delete plan contains no usable rows: $PlanPath"
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
    foreach ($row in $rows) {
        $key = (Get-NormalizedPath $row.StagedDuplicatePath).ToUpperInvariant()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $index[$key] = $row
        }
    }
    return [pscustomobject]@{
        Rows  = $rows
        Index = $index
    }
}

function Test-InventoryRowEligible {
    param([Parameter(Mandatory = $true)]$Row)
    return (
        $Row.DeleteConfidence -eq 'HIGH' -and
        $Row.MoveStatus -in $script:VerifiedMoveStatuses -and
        $Row.SourceGone -eq 'True' -and
        $Row.DestinationExists -eq 'True' -and
        $Row.DestinationHashMatches -eq 'True' -and
        $Row.KeeperExists -eq 'True' -and
        $Row.KeeperHashMatches -eq 'True' -and
        $script:ApprovedDeleteSubfolders -contains $Row.DestinationSubfolder
    )
}

function Test-DeleteCandidateLive {
    param(
        [Parameter(Mandatory = $true)]$PlanRow,
        $InventoryRow
    )
    $issues = New-Object System.Collections.Generic.List[string]
    $stagedPath = $PlanRow.StagedDuplicatePath
    $keeperPath = $PlanRow.KeeperPath

    if ($null -ne $InventoryRow) {
        if (-not (Test-InventoryRowEligible -Row $InventoryRow)) {
            [void]$issues.Add('InventoryRowNotEligible')
        }
        if ((Get-NormalizedHash $InventoryRow.Hash) -ne $PlanRow.Hash) {
            [void]$issues.Add('InventoryHashMismatch')
        }
    }

    if (-not (Test-StagedPathInApprovedDeleteRoot -Path $stagedPath)) {
        [void]$issues.Add('OutsideApprovedDeleteRoot')
    }
    if (Test-PathUnderDeniedPrefix -Path $stagedPath) {
        [void]$issues.Add('DeniedPrefixStaged')
    }
    if ($PlanRow.DeleteConfidence -ne 'HIGH') {
        [void]$issues.Add('NotHighConfidence')
    }
    if ($script:ApprovedDeleteSubfolders -notcontains $PlanRow.DestinationSubfolder) {
        [void]$issues.Add('WrongSubfolder')
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

    if ($null -ne $InventoryRow -and $InventoryRow.SourceGone -ne 'True') {
        [void]$issues.Add('SourceNotGone')
    }

    $ready = ($issues.Count -eq 0)
    return [pscustomobject]@{
        Ready   = $ready
        Status  = if ($ready) { 'DryRunReady' } else { ($issues -join ';') }
        Message = if ($ready) { 'Ready for staged duplicate delete.' } else { ($issues -join '; ') }
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

function Write-DeleteJournalEntry {
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
        KeeperPath          = $Entry.KeeperPath
        StagedHashBefore    = $Entry.StagedHashBefore
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

if ($Execute -and -not $PSBoundParameters.ContainsKey('ExpectedApprovedDeletePlanHash')) {
    throw '-ExpectedApprovedDeletePlanHash is required when using -Execute.'
}

if (-not (Test-Path -LiteralPath $ApprovedDeletePlan)) {
    throw "Approved delete plan not found: $ApprovedDeletePlan"
}

$planFileHash = Get-ApprovedDeletePlanFileSha256 -Path $ApprovedDeletePlan
Write-Host "ApprovedDeletePlan SHA-256: $planFileHash"
if ($PSBoundParameters.ContainsKey('ExpectedApprovedDeletePlanHash')) {
    $expectedHash = Get-NormalizedHash $ExpectedApprovedDeletePlanHash
    if ($planFileHash -ne $expectedHash) {
        throw "Approved delete plan SHA-256 mismatch. Expected=$expectedHash Actual=$planFileHash"
    }
    Write-Host "ApprovedDeletePlan expected SHA-256: $expectedHash (verified)"
}

if (-not $PSBoundParameters.ContainsKey('RunStamp')) {
    if ($ApprovedDeletePlan -match '(\d{8}-\d{6})') {
        $RunStamp = $Matches[1]
    }
    else {
        $RunStamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    }
}

$reportRootNormalized = Get-NormalizedPath $ReportRoot
if (Test-PathInsideRoot -ChildPath $reportRootNormalized -RootPath 'I:\') {
    throw "ReportRoot must be outside I:\. ReportRoot=$reportRootNormalized"
}
if (-not (Test-Path -LiteralPath $reportRootNormalized)) {
    New-Item -ItemType Directory -Path $reportRootNormalized -Force | Out-Null
}

$runMode = if ($Execute) { 'Execute' } else { 'DryRun' }
$preflightReport = Join-Path $reportRootNormalized "delete_preflight_plan_$RunStamp.csv"
$logReport = Join-Path $reportRootNormalized "delete_staged_duplicates_log_$RunStamp.txt"
$executionJournal = Join-Path $reportRootNormalized "delete_execution_journal_$RunStamp.csv"
$executionManifest = Join-Path $reportRootNormalized "delete_execution_manifest_$RunStamp.csv"

$inventoryData = Get-InventoryIndex -Path $InventoryCsvPath
$planReadResult = Read-ApprovedDeletePlan -PlanPath $ApprovedDeletePlan
$planEntries = $planReadResult.Entries

Write-LogLine -Path $logReport -Message "START Remove-StagedDuplicateCandidates v0.2.0 mode=$runMode stamp=$RunStamp"
Write-LogLine -Path $logReport -Message "InventoryCsvPath=$InventoryCsvPath"
Write-LogLine -Path $logReport -Message "ApprovedDeletePlan=$ApprovedDeletePlan"
Write-LogLine -Path $logReport -Message "ApprovedDeletePlan_FileSha256=$planFileHash"
Write-LogLine -Path $logReport -Message "ExpectedApprovedDeletePlanHash=$ExpectedApprovedDeletePlanHash Execute=$Execute"

$started = Get-Date
$preflightRows = New-Object System.Collections.Generic.List[object]
$preflightId = 0
$readyCount = 0
$blockedCount = 0

foreach ($planRow in $planEntries) {
    $preflightId++
    $inventoryRow = $null
    $invKey = $planRow.StagedDuplicatePath.ToUpperInvariant()
    if ($inventoryData.Index.ContainsKey($invKey)) {
        $inventoryRow = $inventoryData.Index[$invKey]
    }
    $live = Test-DeleteCandidateLive -PlanRow $planRow -InventoryRow $inventoryRow
    if ($live.Ready) { $readyCount++ } else { $blockedCount++ }
    [void]$preflightRows.Add([pscustomobject]@{
        PreflightId          = $preflightId
        Hash                 = $planRow.Hash
        ShortHash            = $planRow.ShortHash
        SizeBytes            = $planRow.SizeBytes
        StagedDuplicatePath  = $planRow.StagedDuplicatePath
        KeeperPath           = $planRow.KeeperPath
        DestinationSubfolder = $planRow.DestinationSubfolder
        DeleteConfidence     = $planRow.DeleteConfidence
        DeleteReason         = $planRow.DeleteReason
        PreflightStatus      = $live.Status
        PreflightMessage     = $live.Message
        RunMode              = $runMode
        PreflightAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
    })
}

$preflightRows | Export-Csv -LiteralPath $preflightReport -NoTypeInformation -Encoding UTF8

$totalBytes = ($planEntries | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
$subfolderGroups = $planEntries | Group-Object DestinationSubfolder | Sort-Object Name
$confidenceGroups = $planEntries | Group-Object DeleteConfidence | Sort-Object Name

Write-Host ''
Write-Host 'SUMMARY'
Write-Host "PlanRows=$($planEntries.Count)"
Write-Host "Mode=$runMode Elapsed=$(((Get-Date) - $started).ToString('hh\:mm\:ss'))"
Write-Host "Ready=$readyCount"
Write-Host "Blocked=$blockedCount"
foreach ($g in $subfolderGroups) {
    Write-Host "Subfolder $($g.Name)=$($g.Count)"
}
Write-Host "TotalBytes=$totalBytes"
Write-Host "PreflightReport=$preflightReport"
Write-Host "LogReport=$logReport"

Write-LogLine -Path $logReport -Message "PlanRows=$($planEntries.Count) Ready=$readyCount Blocked=$blockedCount TotalBytes=$totalBytes"
foreach ($g in $subfolderGroups) {
    Write-LogLine -Path $logReport -Message "Subfolder $($g.Name)=$($g.Count)"
}

if ($Execute) {
    $batchValidationOffenders = @($preflightRows | Where-Object { $_.PreflightStatus -notin $script:BatchExecuteReadyStatuses })
    if ($batchValidationOffenders.Count -gt 0) {
        Write-Host ''
        Write-Host '=== BatchValidationFailed ==='
        Write-Host 'Batch delete aborted before any Remove-Item. No files were deleted.'
        Write-LogLine -Path $logReport -Message 'BATCH_VALIDATION_FAILED'
        foreach ($offender in $batchValidationOffenders) {
            Write-Host "  StagedDuplicatePath: $($offender.StagedDuplicatePath)"
            Write-Host "  Status:              $($offender.PreflightStatus)"
            Write-Host "  Message:             $($offender.PreflightMessage)"
            Write-LogLine -Path $logReport -Message ("BatchValidationFailed_Offender Path={0} Status={1} Message={2}" -f $offender.StagedDuplicatePath, $offender.PreflightStatus, $offender.PreflightMessage)
        }
        throw 'Batch delete aborted: one or more approved delete rows are not ready. No files were deleted.'
    }
    Write-LogLine -Path $logReport -Message 'BATCH_VALIDATION_PASSED'
    Write-LogLine -Path $logReport -Message "BatchValidationPassed_ReadyCount=$readyCount"

    $deletedCount = 0
    $failedCount = 0
    $journalSequence = 0
    $manifestRows = New-Object System.Collections.Generic.List[object]

    foreach ($item in ($preflightRows | Where-Object { $_.PreflightStatus -eq 'DryRunReady' })) {
        $executionStatus = 'DeleteFailed'
        $errorMessage = ''
        $stagedHashBefore = ''
        $keeperHashBefore = ''
        try {
            if (-not (Test-Path -LiteralPath $item.StagedDuplicatePath)) {
                throw 'Staged duplicate missing on execute re-check.'
            }
            if (Test-Path -LiteralPath $item.StagedDuplicatePath -PathType Container) {
                throw 'Staged path is a directory; directory deletes are not allowed.'
            }
            $stagedHashBefore = Get-NormalizedHash (Get-FileHash -LiteralPath $item.StagedDuplicatePath -Algorithm SHA256).Hash
            if ($stagedHashBefore -ne $item.Hash) {
                throw 'Staged hash mismatch on execute re-check.'
            }
            if (-not (Test-Path -LiteralPath $item.KeeperPath)) {
                throw 'Keeper missing on execute re-check.'
            }
            $keeperHashBefore = Get-NormalizedHash (Get-FileHash -LiteralPath $item.KeeperPath -Algorithm SHA256).Hash
            if ($keeperHashBefore -ne $item.Hash) {
                throw 'Keeper hash mismatch on execute re-check.'
            }

            if ($PSCmdlet.ShouldProcess($item.StagedDuplicatePath, 'Delete staged duplicate file')) {
                $journalSequence++
                Write-DeleteJournalEntry -Path $executionJournal -Entry @{
                    RunStamp            = $RunStamp
                    Sequence            = $journalSequence
                    Phase               = 'BEFORE_DELETE'
                    Hash                = $item.Hash
                    StagedDuplicatePath = $item.StagedDuplicatePath
                    KeeperPath          = $item.KeeperPath
                    StagedHashBefore    = $stagedHashBefore
                    KeeperHashBefore    = $keeperHashBefore
                    Status              = 'BEFORE_DELETE'
                    ErrorMessage        = ''
                    TimestampUtc        = (Get-Date).ToUniversalTime().ToString('o')
                }

                Remove-Item -LiteralPath $item.StagedDuplicatePath -Force

                if (Test-Path -LiteralPath $item.StagedDuplicatePath) {
                    throw 'Staged duplicate still exists after delete.'
                }
                if (-not (Test-Path -LiteralPath $item.KeeperPath)) {
                    throw 'Keeper missing after delete.'
                }
                $keeperHashAfter = Get-NormalizedHash (Get-FileHash -LiteralPath $item.KeeperPath -Algorithm SHA256).Hash
                if ($keeperHashAfter -ne $item.Hash) {
                    throw 'Keeper hash mismatch after delete.'
                }

                $executionStatus = 'DeletedVerified'
                $deletedCount++
                $journalSequence++
                Write-DeleteJournalEntry -Path $executionJournal -Entry @{
                    RunStamp            = $RunStamp
                    Sequence            = $journalSequence
                    Phase               = 'AFTER_DELETE'
                    Hash                = $item.Hash
                    StagedDuplicatePath = $item.StagedDuplicatePath
                    KeeperPath          = $item.KeeperPath
                    StagedHashBefore    = $stagedHashBefore
                    KeeperHashBefore    = $keeperHashBefore
                    Status              = 'DELETED_VERIFIED'
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
            Write-DeleteJournalEntry -Path $executionJournal -Entry @{
                RunStamp            = $RunStamp
                Sequence            = $journalSequence
                Phase               = 'FAILED'
                Hash                = $item.Hash
                StagedDuplicatePath = $item.StagedDuplicatePath
                KeeperPath          = $item.KeeperPath
                StagedHashBefore    = $stagedHashBefore
                KeeperHashBefore    = $keeperHashBefore
                Status              = $executionStatus
                ErrorMessage        = $errorMessage
                TimestampUtc        = (Get-Date).ToUniversalTime().ToString('o')
            }
            throw "Delete failed for $($item.StagedDuplicatePath): $errorMessage"
        }
        [void]$manifestRows.Add([pscustomobject]@{
            PreflightId         = $item.PreflightId
            StagedDuplicatePath = $item.StagedDuplicatePath
            KeeperPath          = $item.KeeperPath
            Hash                = $item.Hash
            SizeBytes           = $item.SizeBytes
            ExecutionStatus     = $executionStatus
            ErrorMessage        = $errorMessage
            DeletedAtUtc        = (Get-Date).ToUniversalTime().ToString('o')
        })
    }

    $manifestRows | Export-Csv -LiteralPath $executionManifest -NoTypeInformation -Encoding UTF8
    Write-LogLine -Path $logReport -Message "DeletedVerified=$deletedCount DeleteFailed=$failedCount"
    Write-Host "DeletedVerified=$deletedCount DeleteFailed=$failedCount"
    Write-Host "ExecutionJournal=$executionJournal"
    Write-Host "ExecutionManifest=$executionManifest"
}

Write-Host 'COMPLETE'
Write-LogLine -Path $logReport -Message 'COMPLETE'
