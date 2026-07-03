[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$SourceRoot = 'I:\',

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',

    [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MD5')]
    [string]$Algorithm = 'SHA256',

    [string[]]$IncludeExtensions = @(
        '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tif', '.tiff', '.webp',
        '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.mpg', '.mpeg',
        '.mp3', '.wav', '.flac', '.m4a', '.aac',
        '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.rtf', '.csv',
        '.zip', '.7z', '.rar', '.pst', '.ost'
    ),

    [string[]]$SkipExtensions = @('.tmp', '.cache', '.dll', '.exe', '.sys'),

    [ValidateRange(0, [long]::MaxValue)]
    [long]$MinSizeBytes = 1,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$MaxFiles,

    [switch]$BalancedSample,

    [ValidateRange(1, [int]::MaxValue)]
    [int]$MaxFilesPerBucket = 100,

    [ValidateRange(0, [long]::MaxValue)]
    [long]$MinInterestingBytes = 50000,

    [switch]$DryRun
)

# Drive Recovery Hash Scout v0.1.5
# Report-only. No source files are moved, copied, renamed, deleted, or modified.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
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
    $prefix = if ($root.EndsWith([IO.Path]::DirectorySeparatorChar)) { $root } else { $root + [IO.Path]::DirectorySeparatorChar }
    return $child.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-NormalizedExtensionSet {
    param([string[]]$Extensions)
    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($extension in $Extensions) {
        if ([string]::IsNullOrWhiteSpace($extension)) { continue }
        $value = $extension.Trim().ToLowerInvariant()
        if (-not $value.StartsWith('.')) { $value = ".$value" }
        [void]$set.Add($value)
    }
    return $set
}

function Test-ShouldSkipFolder {
    param([Parameter(Mandatory = $true)][IO.DirectoryInfo]$Folder)
    try {
        if (($Folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return 'ReparsePointOrJunction'
        }
    }
    catch { return 'CannotReadAttributes' }

    $skipNames = @(
        '$RECYCLE.BIN', 'System Volume Information', '@Recycle', 'node_modules', '.git',
        '.cache', 'Cache', 'Code Cache', 'GPUCache', 'Crashpad', 'Temp',
        'Temporary Internet Files', 'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData'
    )
    foreach ($name in $skipNames) {
        if ($Folder.Name.Equals($name, [StringComparison]::OrdinalIgnoreCase)) { return "ExcludedFolder:$name" }
    }
    return $null
}

function Test-RecoveredGenericStem {
    param([Parameter(Mandatory = $true)][string]$Stem)
    return $Stem -match '^(?i:(?:file|f|image|img)0*\d+|recovered[_ -]?0*\d+)$'
}

function Test-IsUnderRecoverPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ($Path -replace '/', '\') -match '(?i)\\recover(?:\\|$)'
}

function Test-IsCarvedRecoveryStem {
    param([Parameter(Mandatory = $true)][string]$Stem)
    return $Stem -match '\[\d+\]$' -or $Stem -match '^(?i:\d+-[a-f0-9]{8,})'
}

function Test-IsRecoveredMatchSide {
    param([Parameter(Mandatory = $true)]$Row)
    if ($Row.IsRecoveredGenericName) { return $true }
    if (Test-IsUnderRecoverPath $Row.FullPath) { return $true }
    $stem = [IO.Path]::GetFileNameWithoutExtension($Row.FileName)
    return Test-IsCarvedRecoveryStem $stem
}

function Test-IsRealNamedMatchSide {
    param([Parameter(Mandatory = $true)]$Row)
    return -not (Test-IsRecoveredMatchSide $Row)
}

function Get-RecoveredLabelStem {
    param([Parameter(Mandatory = $true)]$Row)
    if (-not [string]::IsNullOrWhiteSpace($Row.RecoveredGenericStem)) { return $Row.RecoveredGenericStem }
    return [IO.Path]::GetFileNameWithoutExtension($Row.FileName)
}

function Get-FileBucket {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Extension,
        [Parameter(Mandatory = $true)][bool]$IsGeneric
    )
    $p = ($Path -replace '/', '\').ToLowerInvariant()
    if ($IsGeneric -or $p -match '\\recover(?:\\|$)') { return 'RecoveredGeneric' }
    if ($p -match '\\oldusers(?:\\|$)') { return 'OldUserProfile' }
    if ($Extension -in @('.pst', '.ost')) { return 'PSTMail' }
    if ($Extension -in @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tif', '.tiff', '.webp')) { return 'Photos' }
    if ($Extension -in @('.mp4', '.mov', '.avi', '.mkv', '.wmv', '.mpg', '.mpeg')) { return 'Videos' }
    if ($Extension -in @('.mp3', '.wav', '.flac', '.m4a', '.aac')) { return 'Music' }
    if ($Extension -in @('.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.rtf', '.csv')) { return 'Documents' }
    if ($Extension -in @('.zip', '.7z', '.rar')) { return 'Archives' }
    return 'Other'
}

$script:BucketNames = @(
    'RecoveredGeneric', 'OldUserProfile', 'PSTMail', 'Photos', 'Videos', 'Music', 'Documents', 'Archives', 'Other'
)

function Test-AllBucketsFull {
    param(
        [hashtable]$BucketSamples,
        [int]$PerBucketLimit
    )
    foreach ($bucketName in $script:BucketNames) {
        if ($BucketSamples[$bucketName].Count -lt $PerBucketLimit) { return $false }
    }
    return $true
}

function New-HashCandidateRow {
    param(
        [Parameter(Mandatory = $true)][IO.FileInfo]$File,
        [string]$Algorithm,
        [bool]$DryRun,
        [ref]$HashedCount
    )
    $extension = $File.Extension.ToLowerInvariant()
    $stem = [IO.Path]::GetFileNameWithoutExtension($File.Name)
    $generic = Test-RecoveredGenericStem $stem
    $hash = ''
    if (-not $DryRun) {
        try {
            $hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm $Algorithm).Hash
            $HashedCount.Value++
        }
        catch {
            Write-ScanLog "HASH ERROR $($File.FullName) -- $($_.Exception.GetType().Name): $($_.Exception.Message)"
        }
    }
    return [pscustomobject][ordered]@{
        Hash                   = $hash
        Algorithm              = $Algorithm
        SizeBytes              = $File.Length
        Extension              = $extension
        FileName               = $File.Name
        FullPath               = $File.FullName
        ParentPath             = $File.DirectoryName
        IsRecoveredGenericName = $generic
        RecoveredGenericStem   = if ($generic) { $stem } else { '' }
        Bucket                 = Get-FileBucket $File.FullName $extension $generic
        LastWriteTimeUtc       = $File.LastWriteTimeUtc.ToString('o')
        CreationTimeUtc        = $File.CreationTimeUtc.ToString('o')
    }
}

function Write-BucketSummary {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [switch]$ToLog
    )
    Write-Host "`nBucket counts in this run:" -ForegroundColor Cyan
    foreach ($bucketName in $script:BucketNames) {
        $count = @($Rows | Where-Object { $_.Bucket -eq $bucketName }).Count
        $line = "  ${bucketName}: $count"
        Write-Host $line
        if ($ToLog) { Write-ScanLog $line.Trim() }
    }
}

function Export-ReportCsv {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][string[]]$Columns,
        [Parameter(Mandatory = $true)][string]$Path
    )
    if ($Rows.Count -gt 0) {
        $Rows | Select-Object -Property $Columns | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
        return
    }
    (($Columns | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -join ',') |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

$script:MailArchiveDocExtensions = @(
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.rtf', '.csv',
    '.zip', '.7z', '.rar', '.pst', '.ost'
)
$script:PhotoJpegExtensions = @('.jpg', '.jpeg')
$script:StrictImageExtensions = @('.png', '.gif', '.bmp', '.tif', '.tiff', '.webp')
$script:MediaExtensions = @(
    '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.mpg', '.mpeg',
    '.mp3', '.wav', '.flac', '.m4a', '.aac'
)

$script:PersonalFolderFragments = @(
    '\Pictures\', '\Photos\', '\Videos\', '\Music\', '\Documents\',
    '\Desktop\', '\Downloads\', '\oldusers\', '\prevdrivestuff\', '\recover\'
)

$script:LowValuePathPatterns = @(
    '(?i)\\LogoImages\\'
    '(?i)\\OneDrive\\'
    '(?i)\\(chrome|edge|browser|extensions)\\'
    '(?i)\\(tinymce|apidoc|systrace|catapult)\\'
    '(?i)\\(cache|code cache|gpucache|webcache|inetcache)\\'
)

$script:LowValueFileNamePatterns = @(
    '^(?i)object\.gif$'
    '^(?i)crarr\.png$'
    '^(?i)bg-menu\.png$'
    '^(?i)launch\.png$'
    '^(?i)toolbar\..+$'
    '^(?i)arrows-.*\.png$'
    '^(?i)OneDrive.*Tile.*\.png$'
    '^(?i)blurrect\.png$'
    '^(?i)trans\.gif$'
    '^(?i)loader\.gif$'
    '^(?i)anchor\.gif$'
)

function Test-HasPersonalFolderPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = ($Path -replace '/', '\')
    foreach ($fragment in $script:PersonalFolderFragments) {
        if ($normalized -match [regex]::Escape($fragment)) { return $true }
    }
    return $false
}

function Test-IsLowValueDuplicatePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = ($Path -replace '/', '\')
    foreach ($pattern in $script:LowValuePathPatterns) {
        if ($normalized -match $pattern) { return $true }
    }
    return $false
}

function Test-IsLowValueDuplicateFileName {
    param([Parameter(Mandatory = $true)][string]$FileName)
    foreach ($pattern in $script:LowValueFileNamePatterns) {
        if ($FileName -match $pattern) { return $true }
    }
    return $false
}

function Test-HasPhotoLikeFileName {
    param([Parameter(Mandatory = $true)][string]$FileName)
    $stem = [IO.Path]::GetFileNameWithoutExtension($FileName)
    return $stem -match '(?i)(?:^IMG[_\-\s]?\d|^DSC\d|^PXL_|^Screenshot|^\d{1,2}[-/]\d{1,2}[-/]\d{2,4}|^\d{4}[-_]\d{2}[-_]\d{2}|^\d{8})'
}

function Test-GroupLooksLikeUiAsset {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Items)
    if ($Items.Count -eq 0) { return $false }
    foreach ($item in $Items) {
        if (-not (Test-IsLowValueDuplicatePath $item.FullPath) -and -not (Test-IsLowValueDuplicateFileName $item.FileName)) {
            return $false
        }
    }
    return $true
}

function Test-GroupHasMeaningfulSmallPhoto {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Items)
    foreach ($item in $Items) {
        if (Test-IsLowValueDuplicatePath $item.FullPath) { continue }
        if (Test-IsLowValueDuplicateFileName $item.FileName) { continue }
        if ($item.Extension -in $script:PhotoJpegExtensions) { return $true }
        if ($item.Extension -in @('.png', '.gif', '.tif', '.tiff') -and (Test-HasPhotoLikeFileName $item.FileName)) {
            return $true
        }
    }
    return $false
}

function Get-SuggestedInterestingAction {
    param(
        [string]$InterestLevel,
        [bool]$HasRecoverToReal,
        [bool]$AboveThreshold,
        [bool]$HasMailArchiveDoc
    )
    if ($HasRecoverToReal) { return 'Review recovered-to-realname duplicate' }
    if ($AboveThreshold -and $HasMailArchiveDoc) { return 'Review personal duplicate group' }
    if ($AboveThreshold) { return 'Review large duplicate group' }
    if ($InterestLevel -eq 'Low') { return 'Review personal duplicate group' }
    return 'Review duplicate group'
}

function Get-InterestingDuplicateRows {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$DuplicateGroups,
        [long]$MinBytes
    )
    $interesting = [Collections.Generic.List[object]]::new()
    foreach ($group in $DuplicateGroups) {
        $items = @($group.Group)
        $recoveredCount = @($items | Where-Object { Test-IsRecoveredMatchSide $_ }).Count
        $realNamedCount = @($items | Where-Object { Test-IsRealNamedMatchSide $_ }).Count
        $hasRecoverToReal = $recoveredCount -gt 0 -and $realNamedCount -gt 0
        $totalBytes = [long](($items | Measure-Object SizeBytes -Sum).Sum)
        $aboveThreshold = $totalBytes -ge $MinBytes
        $hasPersonalPath = @($items | Where-Object { Test-HasPersonalFolderPath $_.FullPath }).Count -gt 0
        $hasPersonalExtension = @($items | Where-Object {
            $_.Extension -in ($script:PhotoJpegExtensions + $script:StrictImageExtensions + $script:MediaExtensions + $script:MailArchiveDocExtensions)
        }).Count -gt 0
        $hasMailArchiveDoc = @($items | Where-Object { $_.Extension -in $script:MailArchiveDocExtensions }).Count -gt 0
        $hasMedia = @($items | Where-Object { $_.Extension -in $script:MediaExtensions }).Count -gt 0

        if ((Test-GroupLooksLikeUiAsset $items) -and -not $hasRecoverToReal) { continue }

        $reasons = [Collections.Generic.List[string]]::new()
        $level = ''
        $include = $false

        if ($hasRecoverToReal) {
            $include = $true
            $level = 'High'
            [void]$reasons.Add('RecoveredToRealNamed')
        }
        elseif ($aboveThreshold) {
            $include = $true
            $level = 'Medium'
            [void]$reasons.Add('LargeGroup')
            if ($hasMailArchiveDoc) { [void]$reasons.Add('MailArchiveDocument') }
            if ($hasMedia) { [void]$reasons.Add('Media') }
        }
        elseif (Test-GroupHasMeaningfulSmallPhoto $items) {
            $include = $true
            $level = 'Low'
            [void]$reasons.Add('PhotoLikeFilename')
        }

        if (-not $include) { continue }

        if ($hasPersonalExtension) { [void]$reasons.Add('PersonalExtension') }
        if ($hasPersonalPath) { [void]$reasons.Add('PersonalFolderPath') }

        $interesting.Add([pscustomobject][ordered]@{
            Hash                = $group.Name
            Count               = $group.Count
            TotalBytes          = $totalBytes
            Extensions          = (($items.Extension | Sort-Object -Unique) -join ';')
            InterestLevel       = $level
            InterestReason      = ($reasons -join ';')
            RecoveredSideCount  = $recoveredCount
            RealNamedSideCount  = $realNamedCount
            Buckets             = (($items.Bucket | Sort-Object -Unique) -join ';')
            ExampleNames        = (($items.FileName | Select-Object -First 5) -join ';')
            ExamplePaths        = (($items.FullPath | Select-Object -First 5) -join ';')
            SuggestedAction     = Get-SuggestedInterestingAction -InterestLevel $level -HasRecoverToReal $hasRecoverToReal `
                -AboveThreshold $aboveThreshold -HasMailArchiveDoc $hasMailArchiveDoc
        })
    }
    return @($interesting)
}

$sourceItem = Get-Item -LiteralPath $SourceRoot
if (-not $sourceItem.PSIsContainer) { throw 'SourceRoot must be a folder or drive root.' }
$source = Get-NormalizedPath $sourceItem.FullName
$reports = Get-NormalizedPath $ReportRoot
if (Test-PathInsideRoot $reports $source) {
    throw 'Safety stop: ReportRoot must be outside SourceRoot.'
}

$includeSet = Get-NormalizedExtensionSet $IncludeExtensions
$skipSet = Get-NormalizedExtensionSet $SkipExtensions
New-Item -ItemType Directory -Path $reports -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$hashReport = Join-Path $reports "file_hashes_$stamp.csv"
$duplicateReport = Join-Path $reports "duplicate_hash_groups_$stamp.csv"
$interestingReport = Join-Path $reports "interesting_duplicate_groups_$stamp.csv"
$matchReport = Join-Path $reports "recovered_to_realname_matches_$stamp.csv"
$logReport = Join-Path $reports "hash_scan_log_$stamp.txt"
$started = Get-Date

function Write-ScanLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" | Add-Content -LiteralPath $logReport -Encoding UTF8
}

function Show-ScanProgress {
    param(
        [int]$FoldersVisited,
        [int]$FilesHashed,
        [string]$CurrentPath,
        [timespan]$Elapsed,
        [bool]$HasLimit,
        [int]$Limit,
        [int]$CandidatesFound = 0,
        [int]$FilesExamined = 0,
        [switch]$BalancedMode,
        [int]$SampleTarget = 0
    )
    if ($BalancedMode) {
        $status = 'Folders: {0:N0} | Examined: {1:N0} | Sample selected: {2:N0} | Hashed: {3:N0} | Elapsed: {4:hh\:mm\:ss}' -f `
            $FoldersVisited, $FilesExamined, $CandidatesFound, $FilesHashed, $Elapsed
        $percentBase = if ($SampleTarget -gt 0) { $SampleTarget } else { [math]::Max($CandidatesFound, 1) }
        $percent = if ($DryRun) {
            [math]::Min(100, [math]::Floor(($CandidatesFound / [double]$percentBase) * 100))
        }
        else {
            [math]::Min(100, [math]::Floor(($FilesHashed / [double]$percentBase) * 100))
        }
    }
    else {
        $status = 'Folders: {0:N0} | Candidates: {1:N0} | Hashed: {2:N0} | Elapsed: {3:hh\:mm\:ss}' -f `
            $FoldersVisited, $CandidatesFound, $FilesHashed, $Elapsed
        $percent = if ($HasLimit) {
            [math]::Min(100, [math]::Floor(($CandidatesFound / [double]$Limit) * 100))
        }
        else { -1 }
    }
    $progress = @{
        Activity         = 'Drive Recovery Hash Scout — READ ONLY'
        Status           = $status
        CurrentOperation = $CurrentPath
        PercentComplete  = $percent
    }
    Write-Progress @progress
}

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  DRIVE RECOVERY HASH SCOUT — READ ONLY' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host "`nSource:`n  $source`n`nReports:`n  $reports`n"
Write-Host 'No move. No copy. No rename. No delete. No source modification.' -ForegroundColor Yellow
if ($DryRun) { Write-Host "`nDRY RUN: candidates will be reported but not hashed." -ForegroundColor Yellow }
if ($BalancedSample) {
    Write-Host ("`nBALANCED SAMPLE: up to {0:N0} candidates per bucket ({1})." -f $MaxFilesPerBucket, ($script:BucketNames -join ', ')) -ForegroundColor Yellow
    Write-Host 'Enumeration continues until each bucket is full or the drive is exhausted.' -ForegroundColor DarkGray
}
Write-Host ''
Write-ScanLog "START source=$source algorithm=$Algorithm dryRun=$DryRun balancedSample=$BalancedSample maxFilesPerBucket=$MaxFilesPerBucket"

$rows = [Collections.Generic.List[object]]::new()
$stack = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
$stack.Push([IO.DirectoryInfo]::new($source))
$candidateCount = 0
$hashedCount = 0
$folderCount = 0
$filesExamined = 0
$limitReached = $false
$hasFileLimit = $PSBoundParameters.ContainsKey('MaxFiles') -and -not $BalancedSample
$bucketSamples = @{}
if ($BalancedSample) {
    foreach ($bucketName in $script:BucketNames) {
        $bucketSamples[$bucketName] = [Collections.Generic.List[IO.FileInfo]]::new()
    }
}

while ($stack.Count -gt 0 -and -not $limitReached) {
    $folder = $stack.Pop()
    $folderCount++
    if ($BalancedSample) {
        Show-ScanProgress -FoldersVisited $folderCount -CandidatesFound $candidateCount -FilesHashed $hashedCount `
            -CurrentPath $folder.FullName -Elapsed ((Get-Date) - $started) -HasLimit $hasFileLimit -Limit $MaxFiles `
            -FilesExamined $filesExamined -BalancedMode
    }
    else {
        Show-ScanProgress -FoldersVisited $folderCount -CandidatesFound $candidateCount -FilesHashed $hashedCount `
            -CurrentPath $folder.FullName -Elapsed ((Get-Date) - $started) -HasLimit $hasFileLimit -Limit $MaxFiles `
            -FilesExamined $filesExamined
    }
    try {
        $reason = Test-ShouldSkipFolder $folder
        if ($null -ne $reason) { Write-ScanLog "SKIP [$reason] $($folder.FullName)"; continue }

        try {
            foreach ($file in $folder.EnumerateFiles()) {
                try {
                    $extension = $file.Extension.ToLowerInvariant()
                    if (-not $includeSet.Contains($extension) -or $skipSet.Contains($extension)) { continue }
                    if ($file.Length -lt $MinSizeBytes) { continue }

                    if ($BalancedSample) {
                        $filesExamined++
                        $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
                        $generic = Test-RecoveredGenericStem $stem
                        $bucket = Get-FileBucket $file.FullName $extension $generic
                        if ($bucketSamples[$bucket].Count -ge $MaxFilesPerBucket) { continue }

                        [void]$bucketSamples[$bucket].Add($file)
                        $candidateCount++
                        if (($candidateCount % 100) -eq 0) {
                            Show-ScanProgress -FoldersVisited $folderCount -CandidatesFound $candidateCount -FilesHashed $hashedCount `
                                -CurrentPath $file.FullName -Elapsed ((Get-Date) - $started) -HasLimit $false -Limit 0 `
                                -FilesExamined $filesExamined -BalancedMode
                        }
                        if (Test-AllBucketsFull -BucketSamples $bucketSamples -PerBucketLimit $MaxFilesPerBucket) {
                            $limitReached = $true
                            Write-ScanLog "BALANCED SAMPLE all buckets reached per-bucket limit $MaxFilesPerBucket"
                            break
                        }
                        continue
                    }

                    if ($hasFileLimit -and $candidateCount -ge $MaxFiles) {
                        $limitReached = $true
                        break
                    }

                    $candidateCount++
                    $row = New-HashCandidateRow -File $file -Algorithm $Algorithm -DryRun $DryRun -HashedCount ([ref]$hashedCount)
                    $rows.Add($row)
                    if (($candidateCount % 100) -eq 0) {
                        Show-ScanProgress -FoldersVisited $folderCount -CandidatesFound $candidateCount -FilesHashed $hashedCount `
                            -CurrentPath $file.FullName -Elapsed ((Get-Date) - $started) -HasLimit $hasFileLimit -Limit $MaxFiles
                    }
                    if (($candidateCount % 500) -eq 0) {
                        Write-Host ("  Candidates: {0:N0}    Hashed: {1:N0}" -f $candidateCount, $hashedCount)
                    }
                }
                catch { Write-ScanLog "FILE ERROR $($file.FullName) -- $($_.Exception.GetType().Name): $($_.Exception.Message)" }
            }
        }
        catch { Write-ScanLog "FILE ENUMERATION ERROR $($folder.FullName) -- $($_.Exception.GetType().Name): $($_.Exception.Message)" }

        if (-not $limitReached) {
            try {
                foreach ($child in $folder.EnumerateDirectories()) {
                    try {
                        $reason = Test-ShouldSkipFolder $child
                        if ($null -ne $reason) { Write-ScanLog "SKIP CHILD [$reason] $($child.FullName)"; continue }
                        $stack.Push($child)
                    }
                    catch { Write-ScanLog "CHILD ERROR $($child.FullName) -- $($_.Exception.GetType().Name): $($_.Exception.Message)" }
                }
            }
            catch { Write-ScanLog "FOLDER ENUMERATION ERROR $($folder.FullName) -- $($_.Exception.GetType().Name): $($_.Exception.Message)" }
        }
    }
    catch { Write-ScanLog "SCAN ERROR $($folder.FullName) -- $($_.Exception.GetType().Name): $($_.Exception.Message)" }
}
Write-Progress -Activity 'Drive Recovery Hash Scout' -Completed

if ($BalancedSample) {
    Write-ScanLog "BALANCED SAMPLE enumeration complete examined=$filesExamined selected=$candidateCount"
    Write-Host ("`nBalanced sample selection complete: {0:N0} files selected ({1:N0} matching files examined)." -f $candidateCount, $filesExamined) -ForegroundColor Cyan
    if (-not $DryRun) { Write-Host 'Hashing selected balanced sample...' -ForegroundColor DarkGray }
    $sampleIndex = 0
    foreach ($bucketName in $script:BucketNames) {
        foreach ($file in $bucketSamples[$bucketName]) {
            $sampleIndex++
            $rows.Add((New-HashCandidateRow -File $file -Algorithm $Algorithm -DryRun $DryRun -HashedCount ([ref]$hashedCount)))
            if (($sampleIndex % 100) -eq 0) {
                Show-ScanProgress -FoldersVisited $folderCount -CandidatesFound $candidateCount -FilesHashed $hashedCount `
                    -CurrentPath $file.FullName -Elapsed ((Get-Date) - $started) -HasLimit $false -Limit 0 `
                    -FilesExamined $filesExamined -BalancedMode -SampleTarget $candidateCount
            }
        }
    }
}

$hashColumns = @('Hash', 'Algorithm', 'SizeBytes', 'Extension', 'FileName', 'FullPath', 'ParentPath', 'IsRecoveredGenericName', 'RecoveredGenericStem', 'Bucket', 'LastWriteTimeUtc', 'CreationTimeUtc')
Export-ReportCsv -Rows @($rows) -Columns $hashColumns -Path $hashReport

$validRows = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Hash) })
$duplicateGroups = @($validRows | Group-Object Hash | Where-Object Count -gt 1)
$duplicateRows = @(
    foreach ($group in $duplicateGroups) {
        [pscustomobject][ordered]@{
            Hash         = $group.Name
            Count        = $group.Count
            TotalBytes   = [long](($group.Group | Measure-Object SizeBytes -Sum).Sum)
            Extensions   = (($group.Group.Extension | Sort-Object -Unique) -join ';')
            ExampleNames = (($group.Group.FileName | Select-Object -First 5) -join ';')
            ExamplePaths = (($group.Group.FullPath | Select-Object -First 5) -join ';')
        }
    }
)
$duplicateColumns = @('Hash', 'Count', 'TotalBytes', 'Extensions', 'ExampleNames', 'ExamplePaths')
Export-ReportCsv -Rows $duplicateRows -Columns $duplicateColumns -Path $duplicateReport

$interestingRows = @(Get-InterestingDuplicateRows -DuplicateGroups $duplicateGroups -MinBytes $MinInterestingBytes)
$interestingColumns = @(
    'Hash', 'Count', 'TotalBytes', 'Extensions', 'InterestLevel', 'InterestReason', 'RecoveredSideCount',
    'RealNamedSideCount', 'Buckets', 'ExampleNames', 'ExamplePaths', 'SuggestedAction'
)
Export-ReportCsv -Rows $interestingRows -Columns $interestingColumns -Path $interestingReport

$matchRows = @(
    foreach ($group in $duplicateGroups) {
        $recovered = @($group.Group | Where-Object { Test-IsRecoveredMatchSide $_ })
        $realNamed = @($group.Group | Where-Object { Test-IsRealNamedMatchSide $_ })
        if ($recovered.Count -eq 0 -or $realNamed.Count -eq 0) { continue }
        foreach ($recoveredFile in $recovered) {
            foreach ($realFile in $realNamed) {
                $realStem = [IO.Path]::GetFileNameWithoutExtension($realFile.FileName)
                $safeRealStem = $realStem -replace '[<>:"/\\|?*]', '_'
                $safeRecoveredStem = (Get-RecoveredLabelStem $recoveredFile) -replace '[<>:"/\\|?*]', '_'
                $suggested = '{0}.{1}.{2}{3}' -f $group.Name.Substring(0, [Math]::Min(8, $group.Name.Length)), $safeRecoveredStem, $safeRealStem, $realFile.Extension
                [pscustomobject][ordered]@{
                    Hash                   = $group.Name
                    RecoveredPath          = $recoveredFile.FullPath
                    RecoveredFileName      = $recoveredFile.FileName
                    RealNamedPath          = $realFile.FullPath
                    RealNamedFileName      = $realFile.FileName
                    SuggestedDuplicateName = $suggested
                    SizeBytes              = $recoveredFile.SizeBytes
                    Extension              = $recoveredFile.Extension
                }
            }
        }
    }
)
$matchColumns = @('Hash', 'RecoveredPath', 'RecoveredFileName', 'RealNamedPath', 'RealNamedFileName', 'SuggestedDuplicateName', 'SizeBytes', 'Extension')
Export-ReportCsv -Rows $matchRows -Columns $matchColumns -Path $matchReport

$elapsed = (Get-Date) - $started
Write-ScanLog "COMPLETE candidates=$candidateCount hashed=$hashedCount duplicateGroups=$($duplicateGroups.Count) interestingGroups=$($interestingRows.Count) matches=$($matchRows.Count)"
Write-Host ''
Write-Host '================================================' -ForegroundColor Green
Write-Host '  HASH SCOUT COMPLETE' -ForegroundColor Green
Write-Host '================================================' -ForegroundColor Green
if ($BalancedSample) {
    Write-Host ("`nFiles examined during enumeration:  {0:N0}" -f $filesExamined)
    Write-Host ("Balanced sample selected:            {0:N0}" -f $candidateCount)
    Write-Host ("Files hashed:                        {0:N0}" -f $hashedCount)
}
else {
    Write-Host ("`nCandidate files found:               {0:N0}" -f $candidateCount)
    Write-Host ("Files hashed:                        {0:N0}" -f $hashedCount)
}
Write-Host ("Duplicate hash groups found:         {0:N0}" -f $duplicateGroups.Count)
Write-Host ("Interesting duplicate groups found:  {0:N0}" -f $interestingRows.Count)
Write-Host ("Recovered-to-realname matches:     {0:N0}" -f $matchRows.Count)
Write-Host ("Elapsed time:                      {0:hh\:mm\:ss}" -f $elapsed)
Write-BucketSummary -Rows @($rows) -ToLog
Write-Host "`nFile hashes:`n  $hashReport"
Write-Host "`nDuplicate groups:`n  $duplicateReport"
Write-Host "`nInteresting duplicate groups:`n  $interestingReport"
Write-Host "`nRecovered-name matches:`n  $matchReport"
Write-Host "`nScan log:`n  $logReport`n"
Write-Host 'READ-ONLY RUN: no files were modified.' -ForegroundColor Yellow
