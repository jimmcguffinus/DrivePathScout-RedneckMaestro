[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$SourceRoot = 'I:\recover\McNASBackup',

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',

    [ValidateNotNullOrEmpty()]
    [string]$RunStamp = '20260707'
)

# Phase 2 McNASBackup photo/image inventory v0.1.0 (read-only)
# INVENTORY ONLY — not a mover, not a move plan, not keeper policy, not cleanup.
# Scans photo/image extensions under McNASBackup, hashes each file SHA-256, writes reports to ReportRoot.
# No Move-Item. No Copy-Item. No Remove-Item. No Rename-Item. No -Execute.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormPathSafe([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    try { return [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { return $p.Trim().TrimEnd('\') }
}

function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ChildPath,
        [Parameter(Mandatory = $true)][string]$RootPath
    )
    $child = Get-NormPathSafe $ChildPath
    $root = Get-NormPathSafe $RootPath
    if ([string]::IsNullOrWhiteSpace($child) -or [string]::IsNullOrWhiteSpace($root)) { return $false }
    $prefix = if ($root.EndsWith('\')) { $root } else { $root + '\' }
    return $child.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-MatchPatterns([string]$text, [string[]]$patterns) {
    $t = $text.ToLowerInvariant()
    foreach ($p in $patterns) { if ($t -match $p) { return $true } }
    return $false
}

function Test-ReparsePoint([string]$path) {
    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    }
    catch { return $true }
}

function Get-RelativePath([string]$fullPath, [string]$rootPath) {
    $full = Get-NormPathSafe $fullPath
    $root = Get-NormPathSafe $rootPath
    if ($full.Length -gt $root.Length) { return $full.Substring($root.Length).TrimStart('\') }
    return [IO.Path]::GetFileName($full)
}

function Get-FolderName([string]$path) {
    $n = Get-NormPathSafe $path
    if ([string]::IsNullOrWhiteSpace($n)) { return '' }
    return [IO.Path]::GetFileName($n)
}

function Get-ParentFolderName([string]$fullPath) {
    $dir = [IO.Path]::GetDirectoryName((Get-NormPathSafe $fullPath))
    if ([string]::IsNullOrWhiteSpace($dir)) { return '' }
    return [IO.Path]::GetFileName($dir)
}

function Get-GrandParentFolderName([string]$fullPath) {
    $dir = [IO.Path]::GetDirectoryName((Get-NormPathSafe $fullPath))
    if ([string]::IsNullOrWhiteSpace($dir)) { return '' }
    $parent = [IO.Path]::GetDirectoryName($dir)
    if ([string]::IsNullOrWhiteSpace($parent)) { return '' }
    return [IO.Path]::GetFileName($parent)
}

function Get-SourceSubfolder([string]$fullPath, [string]$rootPath) {
    $rel = Get-RelativePath $fullPath $rootPath
    if ([string]::IsNullOrWhiteSpace($rel)) { return '(root)' }
    $parts = $rel -split '\\'
    if ($parts.Count -ge 2) { return ($parts[0..1] -join '\') }
    return $parts[0]
}

function Test-NamedDateFolder([string]$fullPath) {
    $parts = (Get-NormPathSafe $fullPath) -split '\\'
    foreach ($part in $parts) {
        if ($part -match '^(19|20)\d{2}[-_\.]?\d{2}[-_\.]?\d{2}$') { return $true }
        if ($part -match '^(19|20)\d{2}[-_\.]\d{2}[-_\.]\d{2}') { return $true }
        if ($part -match '^orig_(19|20)\d{2}') { return $true }
        if ($part -match '^(19|20)\d{6}$') { return $true }
    }
    return $false
}

function Get-PathClass([string]$fullPath, [string]$relativePath) {
    $blob = ($fullPath + '\' + $relativePath).ToLowerInvariant()
    if (Test-MatchPatterns $blob @('\\mcjunk\\', '\\scratch\\', 'test_rename', 'icon-cache', 'browser_extension', 'theme_assets', 'seedboxes', '\\temp\\', '\\tmp\\', 'participatory culture', 'miro\\support')) {
        return 'McJunkOrScratch'
    }
    if (Test-MatchPatterns $blob @('test_rename\\recovered', '\\recovered\\', '\\_duplicates\\', 'hash\s*\(\d+\)')) {
        return 'RecoveredCarved'
    }
    if (Test-MatchPatterns $blob @('\\dcim\\', '\\100canon\\', '\\101canon\\')) { return 'DCIM' }
    if (Test-MatchPatterns $blob @('camera uploads', 'camera_uploads', 'camera roll')) { return 'CameraUploads' }
    if (Test-MatchPatterns $blob @('\\mcphotos\\', 'mcphotos\\')) { return 'McPhotos' }
    if (Test-MatchPatterns $blob @('\\pictures\\', '\\my pictures\\', '\\picture\\')) { return 'Pictures' }
    if (Test-NamedDateFolder $fullPath) { return 'NamedDateFolder' }
    return 'Other'
}

function Get-NameClass([string]$fileName) {
    $name = $fileName
    $stem = [IO.Path]::GetFileNameWithoutExtension($name)
    $lower = $stem.ToLowerInvariant()
    $fullLower = $name.ToLowerInvariant()

    if ($lower -match '^file\d+$') { return 'CarvedFileNumberName' }
    if ($fullLower -match 'screenshot|screen shot|screen_shot|snip|screen capture|screen-capture') { return 'Screenshot' }
    if ($fullLower -match '-edit|edited|_edit|export|exported|resized|_sm\b|_small|modified|\(\d+\)|copy of| - copy') {
        return 'EditedOrExportedName'
    }
    if ($lower -match '^(img|dsc|dscn|pict|mvimg|dscf|p\d{7})[_-]?\d{2,8}$') { return 'OriginalCameraName' }
    if ($name -match '^(IMG|DSC|DSCN|PICT|MVI|DSCF)[_-]?\d+\.(jpg|jpeg|jpe|heic|heif|tif|tiff|raw|cr2|cr3|nef|arw|orf|rw2|raf|pef|dng)$') {
        return 'OriginalCameraName'
    }
    if ($lower -match '^(image\d+|photo|picture|untitled|scan\d+|img|new picture|new photo)$') { return 'GenericImageName' }
    if ($name -match '^\d{8}[_-]\d{6}\.(jpg|jpeg|jpe|heic|heif)$') { return 'OriginalCameraName' }
    return 'Other'
}

function Test-LikelyCarvedOrRecoveredName([string]$fileName, [string]$nameClass) {
    if ($nameClass -eq 'CarvedFileNumberName') { return $true }
    $stem = [IO.Path]::GetFileNameWithoutExtension($fileName).ToLowerInvariant()
    if ($stem -match '^file\d+$') { return $true }
    if ($fileName -match 'hash\s*\(\d+\)') { return $true }
    return $false
}

function Test-LikelyScratchJunkPath([string]$pathClass, [string]$fullPath) {
    if ($pathClass -eq 'McJunkOrScratch') { return $true }
    return Test-MatchPatterns $fullPath @('\\mcjunk\\', '\\scratch\\', 'browser_extension', 'theme_assets', 'icon-cache')
}

function Test-LikelyCameraOriginal([string]$pathClass, [string]$nameClass, [bool]$carved, [bool]$scratch) {
    if ($carved -or $scratch) { return $false }
    if ($pathClass -in @('DCIM', 'CameraUploads')) { return $true }
    if ($nameClass -eq 'OriginalCameraName') { return $true }
    return $false
}

$scriptRepoRoot = Get-NormPathSafe (Split-Path -Parent $PSCommandPath)
$sourceRoot = Get-NormPathSafe $SourceRoot
$reportRoot = Get-NormPathSafe $ReportRoot

if (-not (Test-Path -LiteralPath $sourceRoot)) {
    throw "SourceRoot not found: $sourceRoot"
}
if (-not (Test-Path -LiteralPath $reportRoot)) {
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
}
if (Test-PathInsideRoot -ChildPath $reportRoot -RootPath $scriptRepoRoot) {
    throw "ReportRoot must not be inside repo. ReportRoot=$reportRoot Repo=$scriptRepoRoot"
}

$photoExtensions = @(
    '.jpg', '.jpeg', '.jpe',
    '.png',
    '.heic', '.heif',
    '.tif', '.tiff',
    '.bmp',
    '.gif',
    '.webp',
    '.raw', '.dng', '.cr2', '.cr3', '.nef', '.nrw', '.arw', '.srf', '.sr2', '.orf', '.rw2', '.raf', '.pef'
)
$photoExtSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($e in $photoExtensions) { [void]$photoExtSet.Add($e) }

$csvOut = Join-Path $reportRoot "phase2_mcnasbackup_photo_inventory_$RunStamp.csv"
$summaryOut = Join-Path $reportRoot "phase2_mcnasbackup_photo_inventory_summary_$RunStamp.txt"

Write-Host "Phase 2 McNASBackup photo inventory (read-only)"
Write-Host "SourceRoot: $sourceRoot"
Write-Host "ReportRoot: $reportRoot"
Write-Host "RunStamp: $RunStamp"
Write-Host "Extensions: $($photoExtensions.Count)"

$inventory = New-Object System.Collections.ArrayList
$scanErrors = New-Object System.Collections.ArrayList
$fileCount = 0
$hashCount = 0

function Invoke-PhotoInventoryScan {
    param([string]$CurrentPath)

    if (Test-ReparsePoint $CurrentPath) { return }

    try {
        $entries = Get-ChildItem -LiteralPath $CurrentPath -Force -ErrorAction Stop
    }
    catch {
        [void]$script:scanErrors.Add([pscustomobject]@{
            Path = $CurrentPath
            Error = $_.Exception.Message
        })
        return
    }

    foreach ($entry in $entries) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }

        if ($entry.PSIsContainer) {
            Invoke-PhotoInventoryScan -CurrentPath $entry.FullName
            continue
        }

        $ext = $entry.Extension.ToLowerInvariant()
        if (-not $photoExtSet.Contains($ext)) { continue }

        $script:fileCount++
        if ($script:fileCount % 250 -eq 0) {
            Write-Host "  scanned $script:fileCount candidates, hashed $script:hashCount"
        }

        $full = Get-NormPathSafe $entry.FullName
        $rel = Get-RelativePath $full $sourceRoot
        $fileName = $entry.Name
        $dir = [IO.Path]::GetDirectoryName($full)
        $parentFolder = Get-ParentFolderName $full
        $grandParentFolder = Get-GrandParentFolderName $full

        $sha256 = ''
        try {
            $sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
            $script:hashCount++
        }
        catch {
            [void]$script:scanErrors.Add([pscustomobject]@{
                Path = $full
                Error = "HashFailed: $($_.Exception.Message)"
            })
        }

        $pathClass = Get-PathClass $full $rel
        $nameClass = Get-NameClass $fileName
        $likelyCarved = Test-LikelyCarvedOrRecoveredName $fileName $nameClass
        $likelyScratch = Test-LikelyScratchJunkPath $pathClass $full
        $likelyCamera = Test-LikelyCameraOriginal $pathClass $nameClass $likelyCarved $likelyScratch

        [void]$script:inventory.Add([pscustomobject]@{
            RunStamp = $RunStamp
            SourceRoot = $sourceRoot
            FullName = $full
            RelativePath = $rel
            Directory = $dir
            FileName = $fileName
            Extension = $ext
            Length = $entry.Length
            LastWriteTimeUtc = $entry.LastWriteTimeUtc.ToString('o')
            CreationTimeUtc = $entry.CreationTimeUtc.ToString('o')
            SHA256 = $sha256
            ParentFolder = $parentFolder
            GrandParentFolder = $grandParentFolder
            PathClass = $pathClass
            NameClass = $nameClass
            LikelyCameraOriginal = $likelyCamera
            LikelyCarvedOrRecoveredName = $likelyCarved
            LikelyScratchJunkPath = $likelyScratch
        })
    }
}

Write-Host 'Scanning and hashing photo/image files...'
Invoke-PhotoInventoryScan -CurrentPath $sourceRoot

$inventory | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding utf8

$totalBytes = ($inventory | ForEach-Object { [int64]$_.Length } | Measure-Object -Sum).Sum
$byExt = $inventory | Group-Object Extension | Sort-Object Count -Descending
$byPathClass = $inventory | Group-Object PathClass | Sort-Object Count -Descending
$byNameClass = $inventory | Group-Object NameClass | Sort-Object Count -Descending
$byParent = $inventory | Group-Object ParentFolder | Sort-Object Count -Descending | Select-Object -First 25
$bySubfolder = $inventory | Group-Object { Get-SourceSubfolder $_.FullName $sourceRoot } | Sort-Object Count -Descending | Select-Object -First 25

$hashGroups = $inventory | Where-Object { -not [string]::IsNullOrWhiteSpace($_.SHA256) } | Group-Object SHA256
$dupGroups = @($hashGroups | Where-Object { $_.Count -ge 2 })
$dupGroupCount = $dupGroups.Count
$dupFileCount = ($dupGroups | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
$extraCopyEstimate = ($dupGroups | ForEach-Object { $_.Count - 1 } | Measure-Object -Sum).Sum
$dupBytes = ($dupGroups | ForEach-Object {
    ($_.Group | ForEach-Object { [int64]$_.Length } | Measure-Object -Sum).Sum
} | Measure-Object -Sum).Sum

$lines = @(
    'Phase 2 McNASBackup Photo/Image Inventory Summary (Read-Only)'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "RunStamp: $RunStamp"
    "SourceRoot: $sourceRoot"
    "ReportRoot: $reportRoot"
    "InventoryCsv: $csvOut"
    ''
    '=== INVENTORY TOTALS ==='
    "PhotoFiles: $($inventory.Count)"
    "TotalBytes: $totalBytes"
    "HashedFiles: $hashCount"
    "ScanErrors: $($scanErrors.Count)"
    ''
    '=== DUPLICATE HASH GROUP ESTIMATE (within this inventory) ==='
    "DuplicateHashGroups: $dupGroupCount"
    "FilesInDuplicateGroups: $dupFileCount"
    "ExtraCopyEstimate: $extraCopyEstimate"
    "BytesInDuplicateGroups: $dupBytes"
    ''
    '=== COUNT BY EXTENSION ==='
)
$lines += $byExt | ForEach-Object {
    $bytes = ($_.Group | ForEach-Object { [int64]$_.Length } | Measure-Object -Sum).Sum
    "$($_.Name)`tfiles=$($_.Count)`tbytes=$bytes"
}
$lines += ''
$lines += '=== COUNT BY PATH CLASS ==='
$lines += $byPathClass | ForEach-Object { "$($_.Name)`t$($_.Count)" }
$lines += ''
$lines += '=== COUNT BY NAME CLASS ==='
$lines += $byNameClass | ForEach-Object { "$($_.Name)`t$($_.Count)" }
$lines += ''
$lines += '=== TOP PARENT FOLDERS (immediate parent directory name) ==='
$lines += $byParent | ForEach-Object {
    $bytes = ($_.Group | ForEach-Object { [int64]$_.Length } | Measure-Object -Sum).Sum
    "$($_.Name)`tfiles=$($_.Count)`tbytes=$bytes"
}
$lines += ''
$lines += '=== TOP SOURCE SUBFOLDERS (first two levels under SourceRoot) ==='
$lines += $bySubfolder | ForEach-Object {
    $bytes = ($_.Group | ForEach-Object { [int64]$_.Length } | Measure-Object -Sum).Sum
    "$($_.Name)`tfiles=$($_.Count)`tbytes=$bytes"
}
$lines += ''
$lines += '=== LIGHTWEIGHT SIGNAL COUNTS ==='
$lines += "LikelyCameraOriginal: $(@($inventory | Where-Object LikelyCameraOriginal).Count)"
$lines += "LikelyCarvedOrRecoveredName: $(@($inventory | Where-Object LikelyCarvedOrRecoveredName).Count)"
$lines += "LikelyScratchJunkPath: $(@($inventory | Where-Object LikelyScratchJunkPath).Count)"
if ($scanErrors.Count -gt 0) {
    $lines += ''
    $lines += '=== SCAN / HASH ERRORS (first 25) ==='
    $lines += $scanErrors | Select-Object -First 25 | ForEach-Object { "$($_.Path)`t$($_.Error)" }
}
$lines += ''
$lines += '=== NEXT STEP ==='
$lines += 'Read-only inventory complete. No move plan. No keeper policy. No cleanup.'
$lines += 'Recommended next: duplicate hash group review and keeper-policy sample before any move-extras planning.'
$lines += ''
$lines += 'WARNING: Inventory only. Not a mover. No move, copy, delete, rename, or -Execute.'
$lines | Set-Content -LiteralPath $summaryOut -Encoding utf8

Write-Host ''
Write-Host "Inventory rows: $($inventory.Count)"
Write-Host "Total bytes: $totalBytes"
Write-Host "Duplicate hash groups (estimate): $dupGroupCount"
Write-Host "Extra copy estimate: $extraCopyEstimate"
Write-Host ''
Write-Host '=== COUNT BY EXTENSION ==='
$byExt | ForEach-Object {
    $bytes = ($_.Group | ForEach-Object { [int64]$_.Length } | Measure-Object -Sum).Sum
    Write-Host ("{0,-8} files={1,6} bytes={2}" -f $_.Name, $_.Count, $bytes)
}
Write-Host ''
Write-Host '=== TOP PARENT FOLDERS ==='
$byParent | Select-Object -First 15 | ForEach-Object {
    Write-Host ("{0,-40} files={1}" -f $_.Name, $_.Count)
}
Write-Host ''
Write-Host "CsvOut: $csvOut"
Write-Host "SummaryOut: $summaryOut"
