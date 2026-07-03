[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$MatchCsvPath,

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',

    [ValidateNotNullOrEmpty()]
    [string]$DestinationRoot = 'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname',

    [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MD5')]
    [string]$Algorithm = 'SHA256',

    [int]$Limit,

    [ValidateNotNullOrEmpty()]
    [string]$OnlyRecoveredPath,

    [switch]$Execute
)

# Drive Recovery Move Stager v0.1.4
# MOVE only when -Execute is passed. Default is DryRun preflight planning.
# No Copy-Item. No Remove-Item. Never moves RealNamedPath keepers.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ApprovedSourceRoots = @('I:\recover\')
$script:JimReviewSourceRoots = @('I:\1tbrecover\')
$script:DeniedSourcePrefixes = @('I:\_RECOVERY_WORKBENCH\')
$script:ReservedDeviceNames = @(
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
)
$script:MaxDestinationPathLength = 248

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

function Get-NormalizedHash {
    param([Parameter(Mandatory = $true)][string]$Hash)
    return $Hash.Trim().ToUpperInvariant()
}

function Get-ShortHash {
    param([Parameter(Mandatory = $true)][string]$Hash)
    $normalized = Get-NormalizedHash $Hash
    if ($normalized.Length -lt 8) { return $normalized }
    return $normalized.Substring(0, 8)
}

function Get-DedupeKey {
    param(
        [Parameter(Mandatory = $true)][string]$RecoveredPath,
        [Parameter(Mandatory = $true)][string]$Hash
    )
    return '{0}|{1}' -f (Get-NormalizedPath $RecoveredPath), (Get-NormalizedHash $Hash)
}

function Get-MatchCsvStamp {
    param([Parameter(Mandatory = $true)][string]$Path)
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    if ($name -match 'recovered_to_realname_matches_(.+)$') { return $Matches[1] }
    return (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Test-IsReservedDeviceName {
    param([Parameter(Mandatory = $true)][string]$Name)
    $base = [IO.Path]::GetFileNameWithoutExtension($Name)
    if ([string]::IsNullOrWhiteSpace($base)) { return $false }
    $upper = $base.ToUpperInvariant()
    foreach ($reserved in $script:ReservedDeviceNames) {
        if ($upper -eq $reserved) { return $true }
    }
    return $false
}

function Get-SafeFileNamePart {
    param([Parameter(Mandatory = $true)][string]$FileName)
    if ([string]::IsNullOrWhiteSpace($FileName)) { return '_' }
    $value = $FileName.Trim().TrimEnd('.', ' ')
    $value = $value -replace '[<>:"/\\|?*]', '_'
    if (Test-IsReservedDeviceName $value) { $value = "_$value" }
    if ([string]::IsNullOrWhiteSpace($value)) { return '_' }
    return $value
}

function Get-DesiredDestinationName {
    param(
        [Parameter(Mandatory = $true)][string]$Hash,
        [Parameter(Mandatory = $true)][string]$RecoveredFileName,
        [Parameter(Mandatory = $true)][string]$RealNamedFileName
    )
    $shortHash = Get-ShortHash $Hash
    $recovered = Get-SafeFileNamePart $RecoveredFileName
    $real = Get-SafeFileNamePart $RealNamedFileName
    return '{0}.{1}.{2}' -f $shortHash, $recovered, $real
}

function Get-ShortenedDestinationName {
    param(
        [Parameter(Mandatory = $true)][string]$DesiredName,
        [Parameter(Mandatory = $true)][string]$Hash,
        [Parameter(Mandatory = $true)][string]$RecoveredFileName,
        [Parameter(Mandatory = $true)][string]$RealNamedFileName,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )
    $ext = [IO.Path]::GetExtension($DesiredName)
    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = [IO.Path]::GetExtension($RealNamedFileName) }
    $shortHash = Get-ShortHash $Hash
    $recStem = Get-SafeFileNamePart ([IO.Path]::GetFileNameWithoutExtension($RecoveredFileName))
    $realStem = Get-SafeFileNamePart ([IO.Path]::GetFileNameWithoutExtension($RealNamedFileName))
    if ($recStem.Length -gt 40) { $recStem = $recStem.Substring(0, 40) }
    if ($realStem.Length -gt 40) { $realStem = $realStem.Substring(0, 40) }
    $candidate = '{0}.{1}.{2}{3}' -f $shortHash, $recStem, $realStem, $ext
    $candidatePath = Join-Path $DestinationRoot $candidate
    if ($candidatePath.Length -le $script:MaxDestinationPathLength) { return $candidate }
    $hashOnly = '{0}{1}' -f $shortHash, $ext
    return $hashOnly
}

function Get-UniqueDestinationName {
    param(
        [Parameter(Mandatory = $true)][string]$BaseFileName,
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][hashtable]$ReservedNames
    )
    $ext = [IO.Path]::GetExtension($BaseFileName)
    $nameWithoutExt = if ([string]::IsNullOrWhiteSpace($ext)) { $BaseFileName } else { $BaseFileName.Substring(0, $BaseFileName.Length - $ext.Length) }
    $candidate = $BaseFileName
    $collisionSuffix = ''
    $statusNote = 'DryRunReady'
    $index = 2
    while ($true) {
        $fullPath = Join-Path $DestinationRoot $candidate
        $key = $fullPath.ToUpperInvariant()
        if (-not (Test-Path -LiteralPath $fullPath) -and -not $ReservedNames.ContainsKey($key)) {
            [void]$ReservedNames.Add($key, $true)
            if ($collisionSuffix) { $statusNote = 'CollisionRenamed' }
            return [pscustomobject]@{
                PlannedDestinationName = $candidate
                PlannedDestinationPath = $fullPath
                CollisionSuffix        = $collisionSuffix
                CollisionStatus        = $statusNote
            }
        }
        $collisionSuffix = '.collision-{0:D3}' -f $index
        $candidate = '{0}{1}{2}' -f $nameWithoutExt, $collisionSuffix, $ext
        $index++
        if ($index -gt 999) { throw "Unable to allocate collision-safe destination for '$BaseFileName'." }
    }
}

function Get-FileHashSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$AlgorithmName
    )
    return (Get-FileHash -LiteralPath $Path -Algorithm $AlgorithmName).Hash.ToUpperInvariant()
}

function Export-ReportCsv {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][string[]]$Columns,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if ($Rows.Count -gt 0) {
        $Rows | Select-Object -Property $Columns | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
        return
    }
    (($Columns | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -join ',') |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-LogLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
    Write-Host $Message
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

function Test-PathChainRootComponents {
    param(
        [string]$SamplePath = 'I:\recover\PNG_Pics\example.png'
    )
    $chain = @(Get-PathChainComponents -Path $SamplePath)
    if ($chain.Count -lt 2) {
        throw "Path chain self-test failed: expected at least 2 components for $SamplePath"
    }
    if ($chain[0] -ne 'I:\') {
        throw "Path chain self-test failed: first component must be 'I:\' but was '$($chain[0])'"
    }
    if ($chain[1] -ne 'I:\recover') {
        throw "Path chain self-test failed: second component must be 'I:\recover' but was '$($chain[1])'"
    }
    if ($chain -contains 'I:') {
        throw 'Path chain self-test failed: chain must not contain bare I:'
    }
    return $true
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

function Write-ExecutionJournalEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Entry
    )
    $columns = @(
        'RunStamp', 'Sequence', 'Phase', 'Hash', 'RecoveredPath', 'DestinationPath', 'RealNamedPath',
        'SourceHashBefore', 'DestHashAfter', 'Status', 'ErrorMessage', 'TimestampUtc'
    )
    $line = ($columns | ForEach-Object {
            $value = if ($null -eq $Entry[$_]) { '' } else { [string]$Entry[$_] }
            '"' + ($value -replace '"', '""') + '"'
        }) -join ','
    if (-not (Test-Path -LiteralPath $Path)) {
        $header = ($columns | ForEach-Object { '"' + $_ + '"' }) -join ','
        [System.IO.File]::WriteAllText($Path, $header + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
    }
    $stream = [System.IO.File]::Open($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try {
        $writer = New-Object System.IO.StreamWriter($stream, (New-Object System.Text.UTF8Encoding $false))
        $writer.WriteLine($line)
        $writer.Flush()
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
}

function Test-SourceRootPolicy {
    param([Parameter(Mandatory = $true)][string]$RecoveredPath)
    foreach ($denied in $script:DeniedSourcePrefixes) {
        if (Test-PathInsideRoot -ChildPath $RecoveredPath -RootPath $denied) {
            return [pscustomobject]@{ Status = 'AlreadyStaged'; Message = "Source is under denied prefix '$denied'." }
        }
    }
    foreach ($review in $script:JimReviewSourceRoots) {
        if (Test-PathInsideRoot -ChildPath $RecoveredPath -RootPath $review) {
            return [pscustomobject]@{ Status = 'NeedsJimReview'; Message = "Source under '$review' requires Jim review in v0.1." }
        }
    }
    foreach ($approved in $script:ApprovedSourceRoots) {
        if (Test-PathInsideRoot -ChildPath $RecoveredPath -RootPath $approved) {
            return [pscustomobject]@{ Status = $null; Message = $null }
        }
    }
    return [pscustomobject]@{ Status = 'InvalidSourceRoot'; Message = 'Source is outside v0.1 approved recovered roots.' }
}

if ($PSBoundParameters.ContainsKey('Limit') -and $Limit -lt 1) {
    throw '-Limit must be at least 1 when specified.'
}

if ($PSBoundParameters.ContainsKey('OnlyRecoveredPath') -and $PSBoundParameters.ContainsKey('Limit')) {
    throw '-OnlyRecoveredPath and -Limit cannot be used together. Use -OnlyRecoveredPath for exact single-path targeting, or -Limit for first-N primary items in CSV order.'
}

$onlyRecoveredPathNormalized = $null
if ($PSBoundParameters.ContainsKey('OnlyRecoveredPath')) {
    $onlyRecoveredPathNormalized = Get-NormalizedPath $OnlyRecoveredPath
    if ([string]::IsNullOrWhiteSpace($onlyRecoveredPathNormalized)) {
        throw '-OnlyRecoveredPath resolved to an empty path.'
    }
}

[void](Test-PathChainRootComponents)

$started = Get-Date
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runMode = if ($Execute) { 'Execute' } else { 'DryRun' }

if (-not (Test-Path -LiteralPath $MatchCsvPath)) {
    throw "Match CSV not found: $MatchCsvPath"
}

$matchCsvStamp = Get-MatchCsvStamp $MatchCsvPath
$destinationRootNormalized = Get-NormalizedPath $DestinationRoot
$reportRootNormalized = Get-NormalizedPath $ReportRoot

if (-not (Test-SameVolume -PathA $destinationRootNormalized -PathB 'I:\')) {
    throw "DestinationRoot must be on I:\ for same-volume moves: $DestinationRoot"
}

if (Test-SameVolume -PathA $reportRootNormalized -PathB 'I:\') {
    throw "ReportRoot must be outside I:\. Reports, journals, and logs must not be written to the recovery drive. ReportRoot=$ReportRoot"
}

if (-not (Test-Path -LiteralPath $reportRootNormalized)) {
    New-Item -ItemType Directory -Path $reportRootNormalized -Force | Out-Null
}

$preflightReport = Join-Path $reportRootNormalized "move_preflight_plan_$stamp.csv"
$executionReport = Join-Path $reportRootNormalized "move_execution_manifest_$stamp.csv"
$executionJournal = Join-Path $reportRootNormalized "move_execution_journal_$stamp.csv"
$logReport = Join-Path $reportRootNormalized "move_recovered_to_realname_log_$stamp.txt"

$requiredColumns = @(
    'Hash', 'RecoveredPath', 'RecoveredFileName', 'RealNamedPath', 'RealNamedFileName', 'SizeBytes', 'Extension'
)
$inputRows = @(Import-Csv -LiteralPath $MatchCsvPath)
if ($inputRows.Count -eq 0) {
    throw "Match CSV contains no rows: $MatchCsvPath"
}
$missingColumns = @($requiredColumns | Where-Object { $inputRows[0].PSObject.Properties.Name -notcontains $_ })
if ($missingColumns.Count -gt 0) {
    throw "Match CSV is missing required columns: $($missingColumns -join ', ')"
}

Write-LogLine -Path $logReport -Message "START Move-RecoveredToRealnameMatches v0.1.4 mode=$runMode stamp=$stamp"
Write-LogLine -Path $logReport -Message "MatchCsvPath=$MatchCsvPath"
Write-LogLine -Path $logReport -Message "ReportRoot=$reportRootNormalized DestinationRoot=$destinationRootNormalized Algorithm=$Algorithm Limit=$Limit OnlyRecoveredPath=$OnlyRecoveredPath Execute=$Execute"

$recoveredPathSet = @{}
$realNamedPathSet = @{}
foreach ($row in $inputRows) {
    $recoveredPathSet[(Get-NormalizedPath $row.RecoveredPath).ToUpperInvariant()] = $true
    $realNamedPathSet[(Get-NormalizedPath $row.RealNamedPath).ToUpperInvariant()] = $true
}
$pathRoleConflicts = @{}
foreach ($key in $recoveredPathSet.Keys) {
    if ($realNamedPathSet.ContainsKey($key)) { $pathRoleConflicts[$key] = $true }
}

if ($null -ne $onlyRecoveredPathNormalized) {
    $onlyPathMatches = @(
        $inputRows | Where-Object {
            $rp = Get-NormalizedPath $_.RecoveredPath
            $rp.Equals($onlyRecoveredPathNormalized, [StringComparison]::OrdinalIgnoreCase)
        }
    )
    if ($onlyPathMatches.Count -eq 0) {
        throw "-OnlyRecoveredPath did not match any row in the match CSV: $OnlyRecoveredPath"
    }
    $onlyDistinctDedupeKeys = @{}
    foreach ($matchRow in $onlyPathMatches) {
        $matchKey = Get-DedupeKey -RecoveredPath (Get-NormalizedPath $matchRow.RecoveredPath) -Hash (Get-NormalizedHash $matchRow.Hash)
        $onlyDistinctDedupeKeys[$matchKey] = $true
    }
    if ($onlyDistinctDedupeKeys.Count -gt 1) {
        throw "-OnlyRecoveredPath matched multiple distinct RecoveredPath+Hash combinations ($($onlyDistinctDedupeKeys.Count)). Ambiguous targeting is not allowed."
    }
}

$seenDedupeKeys = @{}
$primaryWorkCount = 0
$keeperHashCache = @{}
$reservedDestinationNames = @{}
$preflightRows = New-Object System.Collections.Generic.List[object]
$preflightId = 0

foreach ($rowIndex in 0..($inputRows.Count - 1)) {
    $row = $inputRows[$rowIndex]
    $inputRowNumber = $rowIndex + 1
    $hash = Get-NormalizedHash $row.Hash
    $recoveredPath = Get-NormalizedPath $row.RecoveredPath
    $realNamedPath = Get-NormalizedPath $row.RealNamedPath
    $dedupeKey = Get-DedupeKey -RecoveredPath $recoveredPath -Hash $hash
    $shortHash = Get-ShortHash $hash
    $suggested = if ($row.PSObject.Properties.Name -contains 'SuggestedDuplicateName') { $row.SuggestedDuplicateName } else { '' }

    $isPrimary = $false
    $preflightStatus = 'DryRunReady'
    $preflightMessage = ''
    $keeperExists = 'False'
    $keeperHashMatches = 'NotChecked'
    $sourceExists = 'False'
    $sourceHashMatches = 'NotChecked'
    $collisionSuffix = ''
    $desiredDestinationName = ''
    $plannedDestinationName = ''
    $plannedDestinationPath = ''
    $sourceVolume = Get-PathVolumeRoot $recoveredPath
    $destinationVolume = Get-PathVolumeRoot $destinationRootNormalized

    $isOnlyRecoveredPathSelected = $true
    if ($null -ne $onlyRecoveredPathNormalized) {
        $isOnlyRecoveredPathSelected = $recoveredPath.Equals($onlyRecoveredPathNormalized, [StringComparison]::OrdinalIgnoreCase)
    }

    if ($seenDedupeKeys.ContainsKey($dedupeKey)) {
        $preflightStatus = 'DuplicateInputRow'
        $preflightMessage = 'Duplicate normalized RecoveredPath+Hash row; primary work item already planned.'
        $isPrimary = $false
    }
    elseif ($null -ne $onlyRecoveredPathNormalized -and -not $isOnlyRecoveredPathSelected) {
        $seenDedupeKeys[$dedupeKey] = $true
        $isPrimary = $false
        $preflightStatus = 'Skipped'
        $preflightMessage = 'Not selected by -OnlyRecoveredPath.'
    }
    else {
        $seenDedupeKeys[$dedupeKey] = $true
        $isPrimary = $true
        $primaryWorkCount++

        if ($PSBoundParameters.ContainsKey('Limit') -and $primaryWorkCount -gt $Limit) {
            $preflightStatus = 'Skipped'
            $preflightMessage = "Beyond -Limit $Limit."
        }
        elseif ($pathRoleConflicts.ContainsKey($recoveredPath.ToUpperInvariant())) {
            $preflightStatus = 'PathRoleConflict'
            $preflightMessage = 'RecoveredPath equals a RealNamedPath in the input set.'
        }
        elseif ($recoveredPath.Equals($realNamedPath, [StringComparison]::OrdinalIgnoreCase)) {
            $preflightStatus = 'PathRoleConflict'
            $preflightMessage = 'RecoveredPath equals RealNamedPath on this row.'
        }
        else {
            $rootPolicy = Test-SourceRootPolicy -RecoveredPath $recoveredPath
            if ($rootPolicy.Status -eq 'NeedsJimReview') {
                $preflightStatus = 'NeedsJimReview'
                $preflightMessage = $rootPolicy.Message
            }
            elseif ($null -ne $rootPolicy.Status) {
                $preflightStatus = $rootPolicy.Status
                $preflightMessage = $rootPolicy.Message
            }
            elseif (-not (Test-SameVolume -PathA $recoveredPath -PathB $destinationRootNormalized)) {
                $preflightStatus = 'CrossVolumeRejected'
                $preflightMessage = "Source volume '$sourceVolume' does not match destination volume '$destinationVolume'."
            }
            else {
                if (Test-Path -LiteralPath $realNamedPath) { $keeperExists = 'True' }
                else {
                    $preflightStatus = 'KeeperMissing'
                    $preflightMessage = "Keeper not found: $realNamedPath"
                }

                if ($preflightStatus -eq 'DryRunReady') {
                    try {
                        if (-not $keeperHashCache.ContainsKey($realNamedPath)) {
                            $keeperHashCache[$realNamedPath] = Get-FileHashSafe -Path $realNamedPath -AlgorithmName $Algorithm
                        }
                        if ($keeperHashCache[$realNamedPath] -eq $hash) { $keeperHashMatches = 'True' }
                        else {
                            $preflightStatus = 'KeeperHashMismatch'
                            $preflightMessage = 'Keeper hash does not match report hash.'
                            $keeperHashMatches = 'False'
                        }
                    }
                    catch {
                        $preflightStatus = 'KeeperHashMismatch'
                        $preflightMessage = "Keeper hash check failed: $($_.Exception.Message)"
                        $keeperHashMatches = 'False'
                    }
                }

                if ($preflightStatus -eq 'DryRunReady') {
                    if (Test-Path -LiteralPath $recoveredPath) { $sourceExists = 'True' }
                    else {
                        $preflightStatus = 'SourceMissing'
                        $preflightMessage = "Recovered source not found: $recoveredPath"
                    }
                }

                if ($preflightStatus -eq 'DryRunReady') {
                    $sourceReparse = Test-ReparsePathChain -Path $recoveredPath -Mode Source
                    if (-not $sourceReparse.Safe) {
                        $preflightStatus = $sourceReparse.Status
                        $preflightMessage = $sourceReparse.Message
                    }
                }

                if ($preflightStatus -eq 'DryRunReady') {
                    try {
                        $sourceInfo = Get-Item -LiteralPath $recoveredPath -Force
                        if ($sourceInfo.PSIsContainer) {
                            $preflightStatus = 'Skipped'
                            $preflightMessage = 'RecoveredPath is a directory, not a file.'
                        }
                        else {
                            $expectedSize = [long]$row.SizeBytes
                            if ($sourceInfo.Length -ne $expectedSize) {
                                $preflightStatus = 'SourceHashMismatch'
                                $preflightMessage = "Source size $($sourceInfo.Length) does not match report SizeBytes $expectedSize."
                            }
                            else {
                                $sourceHash = Get-FileHashSafe -Path $recoveredPath -AlgorithmName $Algorithm
                                if ($sourceHash -eq $hash) { $sourceHashMatches = 'True' }
                                else {
                                    $preflightStatus = 'SourceHashMismatch'
                                    $preflightMessage = 'Source hash does not match report hash.'
                                    $sourceHashMatches = 'False'
                                }
                            }
                        }
                    }
                    catch {
                        $preflightStatus = 'SourceHashMismatch'
                        $preflightMessage = "Source validation failed: $($_.Exception.Message)"
                        $sourceHashMatches = 'False'
                    }
                }

                if ($preflightStatus -eq 'DryRunReady') {
                    $desiredDestinationName = Get-DesiredDestinationName -Hash $hash -RecoveredFileName $row.RecoveredFileName -RealNamedFileName $row.RealNamedFileName
                    $plannedDestinationName = $desiredDestinationName
                    $plannedDestinationPath = Join-Path $destinationRootNormalized $plannedDestinationName
                    if ($plannedDestinationPath.Length -gt $script:MaxDestinationPathLength) {
                        $plannedDestinationName = Get-ShortenedDestinationName -DesiredName $desiredDestinationName -Hash $hash `
                            -RecoveredFileName $row.RecoveredFileName -RealNamedFileName $row.RealNamedFileName `
                            -DestinationRoot $destinationRootNormalized
                        $plannedDestinationPath = Join-Path $destinationRootNormalized $plannedDestinationName
                        $preflightMessage = 'Destination path shortened to fit length limits.'
                    }
                    $unique = Get-UniqueDestinationName -BaseFileName $plannedDestinationName -DestinationRoot $destinationRootNormalized -ReservedNames $reservedDestinationNames
                    $plannedDestinationName = $unique.PlannedDestinationName
                    $plannedDestinationPath = $unique.PlannedDestinationPath
                    $collisionSuffix = $unique.CollisionSuffix
                    if ($unique.CollisionStatus -eq 'CollisionRenamed') {
                        $preflightStatus = 'CollisionRenamed'
                        if ([string]::IsNullOrWhiteSpace($preflightMessage)) {
                            $preflightMessage = 'Destination name collision resolved with deterministic suffix.'
                        }
                    }
                    if ($preflightStatus -in @('DryRunReady', 'CollisionRenamed')) {
                        $destReparse = Test-ReparsePathChain -Path $plannedDestinationPath -Mode Destination
                        if (-not $destReparse.Safe) {
                            $preflightStatus = $destReparse.Status
                            $preflightMessage = $destReparse.Message
                        }
                    }
                }
            }
        }
    }

    $preflightId++
    [void]$preflightRows.Add([pscustomobject][ordered]@{
            PreflightId             = $preflightId
            InputRowNumber          = $inputRowNumber
            IsPrimaryWorkItem       = if ($isPrimary) { 'True' } else { 'False' }
            DedupeKey               = $dedupeKey
            MatchCsvPath            = $MatchCsvPath
            MatchCsvStamp           = $matchCsvStamp
            Hash                    = $hash
            ShortHash               = $shortHash
            RecoveredPath           = $recoveredPath
            RealNamedPath           = $realNamedPath
            RecoveredFileName       = $row.RecoveredFileName
            RealNamedFileName       = $row.RealNamedFileName
            SuggestedDuplicateName  = $suggested
            DesiredDestinationName  = $desiredDestinationName
            PlannedDestinationName  = $plannedDestinationName
            PlannedDestinationPath  = $plannedDestinationPath
            SizeBytes               = $row.SizeBytes
            Extension               = $row.Extension
            SourceVolume            = $sourceVolume
            DestinationVolume       = $destinationVolume
            KeeperExists            = $keeperExists
            KeeperHashMatches       = $keeperHashMatches
            SourceExists            = $sourceExists
            SourceHashMatches       = $sourceHashMatches
            CollisionSuffix         = $collisionSuffix
            PreflightStatus         = $preflightStatus
            PreflightMessage        = $preflightMessage
            RunMode                 = $runMode
            PreflightAtUtc          = (Get-Date).ToUniversalTime().ToString('o')
        })
}

$preflightColumns = @(
    'PreflightId', 'InputRowNumber', 'IsPrimaryWorkItem', 'DedupeKey', 'MatchCsvPath', 'MatchCsvStamp',
    'Hash', 'ShortHash', 'RecoveredPath', 'RealNamedPath', 'RecoveredFileName', 'RealNamedFileName',
    'SuggestedDuplicateName', 'DesiredDestinationName', 'PlannedDestinationName', 'PlannedDestinationPath',
    'SizeBytes', 'Extension', 'SourceVolume', 'DestinationVolume', 'KeeperExists', 'KeeperHashMatches',
    'SourceExists', 'SourceHashMatches', 'CollisionSuffix', 'PreflightStatus', 'PreflightMessage',
    'RunMode', 'PreflightAtUtc'
)
Export-ReportCsv -Rows ([object[]]$preflightRows) -Columns $preflightColumns -Path $preflightReport

$selectedCandidate = $null
if ($null -ne $onlyRecoveredPathNormalized) {
    $selectedPrimaryRows = @(
        $preflightRows | Where-Object {
            $_.IsPrimaryWorkItem -eq 'True' -and
            (Get-NormalizedPath $_.RecoveredPath).Equals($onlyRecoveredPathNormalized, [StringComparison]::OrdinalIgnoreCase)
        }
    )
    if ($selectedPrimaryRows.Count -ne 1) {
        throw "-OnlyRecoveredPath expected exactly one primary selected row but found $($selectedPrimaryRows.Count)."
    }
    $selectedCandidate = $selectedPrimaryRows[0]
}

$executionRows = New-Object System.Collections.Generic.List[object]
$movedCount = 0
$failedCount = 0
$journalSequence = 0

if ($Execute) {
    $movableRows = @(
        $preflightRows | Where-Object {
            $_.IsPrimaryWorkItem -eq 'True' -and $_.PreflightStatus -in @('DryRunReady', 'CollisionRenamed')
        }
    )

    foreach ($item in $movableRows) {
        $moveStarted = Get-Date
        $executionStatus = 'MoveFailed'
        $errorMessage = ''
        $sourceHashBefore = ''
        $destHashAfter = ''
        $keeperHashBefore = ''
        $sizeBefore = 0
        $sizeAfter = 0
        $terminalStatuses = @(
            'VerifyFailed', 'KeeperMissing', 'KeeperHashMismatch', 'Skipped', 'WhatIfSkipped',
            'SourceMissing', 'SourceHashMismatch',
            'SourceReparsePoint', 'DestinationReparsePoint', 'SourceReparseCheckFailed',
            'DestinationReparseCheckFailed', 'MovedVerified'
        )

        try {
            if (-not (Test-Path -LiteralPath $item.RealNamedPath)) {
                $executionStatus = 'KeeperMissing'
                $errorMessage = "Keeper not found: $($item.RealNamedPath)"
                $journalSequence++
                Write-ExecutionJournalEntry -Path $executionJournal -Entry @{
                    RunStamp         = $stamp
                    Sequence         = $journalSequence
                    Phase            = 'SKIPPED'
                    Hash             = $item.Hash
                    RecoveredPath    = $item.RecoveredPath
                    DestinationPath  = $item.PlannedDestinationPath
                    RealNamedPath    = $item.RealNamedPath
                    SourceHashBefore = ''
                    DestHashAfter    = ''
                    Status           = 'KeeperMissing'
                    ErrorMessage     = $errorMessage
                    TimestampUtc     = (Get-Date).ToUniversalTime().ToString('o')
                }
            }
            elseif (($keeperHashBefore = Get-FileHashSafe -Path $item.RealNamedPath -AlgorithmName $Algorithm) -ne $item.Hash) {
                $executionStatus = 'KeeperHashMismatch'
                $errorMessage = 'Keeper hash does not match report hash on execute re-check.'
                $journalSequence++
                Write-ExecutionJournalEntry -Path $executionJournal -Entry @{
                    RunStamp         = $stamp
                    Sequence         = $journalSequence
                    Phase            = 'SKIPPED'
                    Hash             = $item.Hash
                    RecoveredPath    = $item.RecoveredPath
                    DestinationPath  = $item.PlannedDestinationPath
                    RealNamedPath    = $item.RealNamedPath
                    SourceHashBefore = ''
                    DestHashAfter    = ''
                    Status           = 'KeeperHashMismatch'
                    ErrorMessage     = $errorMessage
                    TimestampUtc     = (Get-Date).ToUniversalTime().ToString('o')
                }
            }
            else {
                if (-not (Test-Path -LiteralPath $item.RecoveredPath)) {
                    $executionStatus = 'SourceMissing'
                    $errorMessage = 'Recovered source missing on execute re-check.'
                    throw $errorMessage
                }

                $sourceReparse = Test-ReparsePathChain -Path $item.RecoveredPath -Mode Source
                if (-not $sourceReparse.Safe) {
                    $executionStatus = $sourceReparse.Status
                    $errorMessage = $sourceReparse.Message
                    throw $sourceReparse.Message
                }

                if (Test-Path -LiteralPath $item.PlannedDestinationPath) {
                    throw 'Destination already exists on execute re-check.'
                }

                $destReparse = Test-ReparsePathChain -Path $item.PlannedDestinationPath -Mode Destination
                if (-not $destReparse.Safe) {
                    $executionStatus = $destReparse.Status
                    $errorMessage = $destReparse.Message
                    throw $destReparse.Message
                }

                $sourceHashBefore = Get-FileHashSafe -Path $item.RecoveredPath -AlgorithmName $Algorithm
                if ($sourceHashBefore -ne $item.Hash) {
                    $executionStatus = 'SourceHashMismatch'
                    $errorMessage = 'Source hash mismatch on execute re-check.'
                    throw $errorMessage
                }
                $sizeBefore = (Get-Item -LiteralPath $item.RecoveredPath -Force).Length

                if ($PSCmdlet.ShouldProcess($item.RecoveredPath, "Move to $($item.PlannedDestinationPath)")) {
                    $journalSequence++
                    Write-ExecutionJournalEntry -Path $executionJournal -Entry @{
                        RunStamp         = $stamp
                        Sequence         = $journalSequence
                        Phase            = 'BEFORE_MOVE'
                        Hash             = $item.Hash
                        RecoveredPath    = $item.RecoveredPath
                        DestinationPath  = $item.PlannedDestinationPath
                        RealNamedPath    = $item.RealNamedPath
                        SourceHashBefore = $sourceHashBefore
                        DestHashAfter    = ''
                        Status           = 'BEFORE_MOVE'
                        ErrorMessage     = ''
                        TimestampUtc     = (Get-Date).ToUniversalTime().ToString('o')
                    }

                    $destParent = Split-Path -Parent $item.PlannedDestinationPath
                    if (-not (Test-Path -LiteralPath $destinationRootNormalized)) {
                        New-Item -ItemType Directory -Path $destinationRootNormalized -Force | Out-Null
                    }
                    if (-not [string]::IsNullOrWhiteSpace($destParent) -and -not (Test-Path -LiteralPath $destParent)) {
                        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                    }

                    Move-Item -LiteralPath $item.RecoveredPath -Destination $item.PlannedDestinationPath

                    if (-not (Test-Path -LiteralPath $item.PlannedDestinationPath)) { throw 'Destination missing after move.' }
                    if (Test-Path -LiteralPath $item.RecoveredPath) { throw 'Source still exists after move.' }

                    $destHashAfter = Get-FileHashSafe -Path $item.PlannedDestinationPath -AlgorithmName $Algorithm
                    $sizeAfter = (Get-Item -LiteralPath $item.PlannedDestinationPath -Force).Length
                    if ($destHashAfter -ne $item.Hash) {
                        $executionStatus = 'VerifyFailed'
                        $errorMessage = 'Destination hash mismatch after move.'
                        $failedCount++
                        $journalSequence++
                        Write-ExecutionJournalEntry -Path $executionJournal -Entry @{
                            RunStamp         = $stamp
                            Sequence         = $journalSequence
                            Phase            = 'VERIFY_FAILED'
                            Hash             = $item.Hash
                            RecoveredPath    = $item.RecoveredPath
                            DestinationPath  = $item.PlannedDestinationPath
                            RealNamedPath    = $item.RealNamedPath
                            SourceHashBefore = $sourceHashBefore
                            DestHashAfter    = $destHashAfter
                            Status           = 'VERIFY_FAILED'
                            ErrorMessage     = $errorMessage
                            TimestampUtc     = (Get-Date).ToUniversalTime().ToString('o')
                        }
                    }
                    else {
                        $executionStatus = 'MovedVerified'
                        $movedCount++
                        $journalSequence++
                        Write-ExecutionJournalEntry -Path $executionJournal -Entry @{
                            RunStamp         = $stamp
                            Sequence         = $journalSequence
                            Phase            = 'AFTER_MOVE'
                            Hash             = $item.Hash
                            RecoveredPath    = $item.RecoveredPath
                            DestinationPath  = $item.PlannedDestinationPath
                            RealNamedPath    = $item.RealNamedPath
                            SourceHashBefore = $sourceHashBefore
                            DestHashAfter    = $destHashAfter
                            Status           = 'MOVED_VERIFIED'
                            ErrorMessage     = ''
                            TimestampUtc     = (Get-Date).ToUniversalTime().ToString('o')
                        }
                    }
                }
                else {
                    $executionStatus = 'WhatIfSkipped'
                    $errorMessage = 'WhatIf or ShouldProcess declined.'
                }
            }
        }
        catch {
            if ($executionStatus -notin $terminalStatuses) {
                $executionStatus = 'MoveFailed'
                $errorMessage = $_.Exception.Message
                $failedCount++
                $journalSequence++
                Write-ExecutionJournalEntry -Path $executionJournal -Entry @{
                    RunStamp         = $stamp
                    Sequence         = $journalSequence
                    Phase            = 'MOVE_FAILED'
                    Hash             = $item.Hash
                    RecoveredPath    = $item.RecoveredPath
                    DestinationPath  = $item.PlannedDestinationPath
                    RealNamedPath    = $item.RealNamedPath
                    SourceHashBefore = $sourceHashBefore
                    DestHashAfter    = $destHashAfter
                    Status           = 'MOVE_FAILED'
                    ErrorMessage     = $errorMessage
                    TimestampUtc     = (Get-Date).ToUniversalTime().ToString('o')
                }
            }
            elseif ($executionStatus -in @('SourceReparsePoint', 'DestinationReparsePoint', 'SourceReparseCheckFailed', 'DestinationReparseCheckFailed', 'SourceMissing', 'SourceHashMismatch')) {
                if ([string]::IsNullOrWhiteSpace($errorMessage)) { $errorMessage = $_.Exception.Message }
                $failedCount++
                $journalSequence++
                Write-ExecutionJournalEntry -Path $executionJournal -Entry @{
                    RunStamp         = $stamp
                    Sequence         = $journalSequence
                    Phase            = 'SKIPPED'
                    Hash             = $item.Hash
                    RecoveredPath    = $item.RecoveredPath
                    DestinationPath  = $item.PlannedDestinationPath
                    RealNamedPath    = $item.RealNamedPath
                    SourceHashBefore = $sourceHashBefore
                    DestHashAfter    = ''
                    Status           = $executionStatus
                    ErrorMessage     = $errorMessage
                    TimestampUtc     = (Get-Date).ToUniversalTime().ToString('o')
                }
            }
        }

        [void]$executionRows.Add([pscustomobject][ordered]@{
                PreflightId        = $item.PreflightId
                OriginalPath       = $item.RecoveredPath
                DestinationPath    = $item.PlannedDestinationPath
                Hash               = $item.Hash
                KeeperPath         = $item.RealNamedPath
                KeeperHashBefore   = $keeperHashBefore
                SourceHashBefore   = $sourceHashBefore
                DestHashAfter      = $destHashAfter
                SizeBytesBefore    = $sizeBefore
                SizeBytesAfter     = $sizeAfter
                ExecutionStatus    = $executionStatus
                ErrorMessage       = $errorMessage
                MovedAtUtc         = (Get-Date).ToUniversalTime().ToString('o')
                DurationMs         = [int](((Get-Date) - $moveStarted).TotalMilliseconds)
            })
    }

    $executionColumns = @(
        'PreflightId', 'OriginalPath', 'DestinationPath', 'Hash', 'KeeperPath', 'KeeperHashBefore',
        'SourceHashBefore', 'DestHashAfter', 'SizeBytesBefore', 'SizeBytesAfter', 'ExecutionStatus',
        'ErrorMessage', 'MovedAtUtc', 'DurationMs'
    )
    Export-ReportCsv -Rows ([object[]]$executionRows) -Columns $executionColumns -Path $executionReport
}

$statusGroups = $preflightRows | Group-Object PreflightStatus | Sort-Object Name
$elapsed = (Get-Date) - $started

Write-LogLine -Path $logReport -Message 'SUMMARY'
Write-LogLine -Path $logReport -Message "RowsInReport=$($inputRows.Count)"
Write-LogLine -Path $logReport -Message "PrimaryWorkItems=$primaryWorkCount"
Write-LogLine -Path $logReport -Message "Mode=$runMode Elapsed=$($elapsed.ToString('hh\:mm\:ss'))"
foreach ($group in $statusGroups) {
    Write-LogLine -Path $logReport -Message ("Status {0}={1}" -f $group.Name, $group.Count)
}
if ($Execute) {
    Write-LogLine -Path $logReport -Message "ExecutionJournal=$executionJournal"
    Write-LogLine -Path $logReport -Message "MovedVerified=$movedCount MoveFailed=$failedCount"
}
Write-LogLine -Path $logReport -Message "PreflightReport=$preflightReport"
Write-LogLine -Path $logReport -Message "LogReport=$logReport"
if ($Execute) { Write-LogLine -Path $logReport -Message "ExecutionReport=$executionReport" }
if ($null -ne $selectedCandidate) {
    Write-Host ''
    Write-Host '=== -OnlyRecoveredPath Selected Candidate ==='
    Write-Host "RecoveredPath:     $($selectedCandidate.RecoveredPath)"
    Write-Host "RealNamedPath:     $($selectedCandidate.RealNamedPath)"
    Write-Host "Hash:              $($selectedCandidate.Hash)"
    Write-Host "SizeBytes:         $($selectedCandidate.SizeBytes)"
    Write-Host "DestinationPath:   $($selectedCandidate.PlannedDestinationPath)"
    Write-Host "PreflightStatus:   $($selectedCandidate.PreflightStatus)"
    Write-Host "CollisionSuffix:   $($selectedCandidate.CollisionSuffix)"
    Write-LogLine -Path $logReport -Message 'ONLYRECOVEREDPATH_SELECTED'
    Write-LogLine -Path $logReport -Message "OnlyRecoveredPath_RecoveredPath=$($selectedCandidate.RecoveredPath)"
    Write-LogLine -Path $logReport -Message "OnlyRecoveredPath_RealNamedPath=$($selectedCandidate.RealNamedPath)"
    Write-LogLine -Path $logReport -Message "OnlyRecoveredPath_Hash=$($selectedCandidate.Hash)"
    Write-LogLine -Path $logReport -Message "OnlyRecoveredPath_SizeBytes=$($selectedCandidate.SizeBytes)"
    Write-LogLine -Path $logReport -Message "OnlyRecoveredPath_DestinationPath=$($selectedCandidate.PlannedDestinationPath)"
    Write-LogLine -Path $logReport -Message "OnlyRecoveredPath_PreflightStatus=$($selectedCandidate.PreflightStatus)"
    Write-LogLine -Path $logReport -Message "OnlyRecoveredPath_CollisionSuffix=$($selectedCandidate.CollisionSuffix)"
}
Write-LogLine -Path $logReport -Message 'COMPLETE'

Write-Host ''
Write-Host '=== Move-RecoveredToRealnameMatches Summary ==='
Write-Host "Mode:              $runMode"
Write-Host "Rows in report:    $($inputRows.Count)"
Write-Host "Primary work items:$primaryWorkCount"
Write-Host "Elapsed:           $($elapsed.ToString('hh\:mm\:ss'))"
Write-Host 'Preflight statuses:'
foreach ($group in $statusGroups) {
    Write-Host ('  {0,-22} {1}' -f $group.Name, $group.Count)
}
Write-Host "Preflight report:  $preflightReport"
Write-Host "Log report:        $logReport"
if ($Execute) {
    Write-Host "Execution journal: $executionJournal"
    Write-Host "Execution report:  $executionReport"
}
