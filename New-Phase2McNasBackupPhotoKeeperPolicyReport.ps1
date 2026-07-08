[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$InventoryPath = 'C:\Users\jim\Desktop\DrivePathInventory\phase2_mcnasbackup_photo_inventory_20260707.csv',

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',

    [ValidateNotNullOrEmpty()]
    [string]$OutputStamp = '20260707'
)

# Phase 2 McNASBackup photo keeper-policy report v0.1.1 (read-only)
# INVENTORY ANALYSIS ONLY — not a mover, not a move plan, not cleanup.
# Reads photo inventory CSV, scores duplicate hash groups, recommends policy buckets.
# CandidateKeeperPath stays in place. Only duplicate extras may ever be considered later.
# No Move-Item. No Copy-Item. No Remove-Item. No Rename-Item. No -Execute.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    try { return [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { return $p.Trim().TrimEnd('\') }
}

function Get-NormHash([string]$h) {
    if ([string]::IsNullOrWhiteSpace($h)) { return '' }
    return $h.Trim().ToUpperInvariant()
}

function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ChildPath,
        [Parameter(Mandatory = $true)][string]$RootPath
    )
    $child = Get-NormPath $ChildPath
    $root = Get-NormPath $RootPath
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

function Test-IsTrue($value) {
    if ($null -eq $value) { return $false }
    $s = "$value".Trim().ToLowerInvariant()
    return $s -in @('true', '1', 'yes')
}

function Test-CarvedPhotoName([string]$fileName) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($fileName).ToLowerInvariant()
    return ($stem -match '^file\d+$')
}

function Get-SourceSubfolder([string]$fullPath, [string]$rootPath) {
    $full = Get-NormPath $fullPath
    $root = Get-NormPath $rootPath
    $rel = if ($full.Length -gt $root.Length) { $full.Substring($root.Length).TrimStart('\') } else { [IO.Path]::GetFileName($full) }
    if ([string]::IsNullOrWhiteSpace($rel)) { return '(root)' }
    $parts = $rel -split '\\'
    if ($parts.Count -ge 2) { return ($parts[0..1] -join '\') }
    return $parts[0]
}

function Get-GroupPathBlob {
    param(
        [array]$Rows,
        [string]$CandidateKeeperPath = '',
        [string]$SamplePaths = ''
    )
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($row in $Rows) {
        if ($row.PSObject.Properties.Name -contains 'FullName' -and -not [string]::IsNullOrWhiteSpace($row.FullName)) {
            [void]$parts.Add((Get-NormPath $row.FullName))
        }
        if ($row.PSObject.Properties.Name -contains 'RelativePath' -and -not [string]::IsNullOrWhiteSpace($row.RelativePath)) {
            [void]$parts.Add($row.RelativePath)
        }
        if ($row.PSObject.Properties.Name -contains 'Directory' -and -not [string]::IsNullOrWhiteSpace($row.Directory)) {
            [void]$parts.Add((Get-NormPath $row.Directory))
        }
        if ($row.PSObject.Properties.Name -contains 'FileName' -and -not [string]::IsNullOrWhiteSpace($row.FileName)) {
            [void]$parts.Add($row.FileName)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($CandidateKeeperPath)) {
        [void]$parts.Add((Get-NormPath $CandidateKeeperPath))
    }
    if (-not [string]::IsNullOrWhiteSpace($SamplePaths)) {
        foreach ($p in ($SamplePaths -split '\|')) {
            $trimmed = $p.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                [void]$parts.Add((Get-NormPath $trimmed))
            }
        }
    }
    return ($parts -join ' ').ToLowerInvariant()
}

function Get-SafetyDemotion {
    param(
        [array]$Rows,
        [string]$CandidateKeeperPath = '',
        [string]$SamplePaths = ''
    )

    $blob = Get-GroupPathBlob -Rows $Rows -CandidateKeeperPath $CandidateKeeperPath -SamplePaths $SamplePaths

    $holdChecks = @(
        @{ Pattern = 'medical'; Term = 'medical' }
        @{ Pattern = 'immuniz'; Term = 'immunization' }
        @{ Pattern = 'doctor'; Term = 'doctor' }
        @{ Pattern = 'hospital'; Term = 'hospital' }
        @{ Pattern = 'safedeposit|safe_deposit|safedepositbox'; Term = 'safedeposit' }
        @{ Pattern = '(\\|_|^)safe(\\|_|$)'; Term = 'safe' }
        @{ Pattern = 'savings_bonds|us_savings_bonds'; Term = 'savings_bonds' }
        @{ Pattern = '(\\|_|^)bonds(\\|_|$)'; Term = 'bonds' }
        @{ Pattern = 'tax|taxes'; Term = 'tax' }
        @{ Pattern = 'legal'; Term = 'legal' }
        @{ Pattern = 'court'; Term = 'court' }
        @{ Pattern = 'claim'; Term = 'claim' }
        @{ Pattern = 'insurance'; Term = 'insurance' }
        @{ Pattern = 'passport'; Term = 'passport' }
        @{ Pattern = 'license'; Term = 'license' }
        @{ Pattern = 'birth'; Term = 'birth' }
        @{ Pattern = 'death'; Term = 'death' }
        @{ Pattern = 'ssn|social_security'; Term = 'ssn' }
        @{ Pattern = 'bank'; Term = 'bank' }
        @{ Pattern = 'financial'; Term = 'financial' }
    )
    foreach ($check in $holdChecks) {
        if ($blob -match $check.Pattern) {
            return [pscustomobject]@{
                Bucket = 'HOLD_UNTOUCHED'
                Risk = 'HIGH'
                MatchedTerm = $check.Term
            }
        }
    }

    $sampleChecks = @(
        @{ Pattern = 'mcphotos'; Term = 'McPhotos' }
        @{ Pattern = '\\pictures\\|my pictures'; Term = 'Pictures' }
        @{ Pattern = 'pictureit'; Term = 'PictureIt' }
        @{ Pattern = 'digital_camera'; Term = 'digital_camera' }
        @{ Pattern = 'camera uploads|camera_uploads|camera roll'; Term = 'Camera Uploads' }
        @{ Pattern = '\\dcim\\'; Term = 'DCIM' }
        @{ Pattern = '(\\|_|^)camera(\\|_|$)'; Term = 'camera' }
        @{ Pattern = '\\katie\\|(^|_)katie(_|$|\\)'; Term = 'Katie' }
        @{ Pattern = '\\sam\\|(^|_)sam(_|$|\\)'; Term = 'Sam' }
        @{ Pattern = '\\jake\\|(^|_)jake(_|$|\\)'; Term = 'Jake' }
        @{ Pattern = '\\mom\\|(^|_)mom(_|$|\\)'; Term = 'Mom' }
        @{ Pattern = '\\dad\\|(^|_)dad(_|$|\\)'; Term = 'Dad' }
        @{ Pattern = 'family'; Term = 'family' }
        @{ Pattern = 'calendar'; Term = 'calendar' }
        @{ Pattern = 'abc_book'; Term = 'abc_book' }
        @{ Pattern = 'tennis'; Term = 'tennis' }
        @{ Pattern = '\\photos\\|(^|_)photos(_|$|\\)'; Term = 'photos' }
        @{ Pattern = '(\\|_|^)photo(\\|_|$)'; Term = 'photo' }
    )
    foreach ($check in $sampleChecks) {
        if ($blob -match $check.Pattern) {
            return [pscustomobject]@{
                Bucket = 'PHOTO_SAMPLE_FIRST'
                Risk = 'MEDIUM'
                MatchedTerm = $check.Term
            }
        }
    }

    return $null
}

function Apply-WebReadySafetyDemotion {
    param(
        [pscustomobject]$Policy,
        [System.Collections.Generic.List[string]]$NoteParts,
        [array]$Rows,
        [string]$CandidateKeeperPath = '',
        [string]$SamplePaths = ''
    )
    if ($Policy.Bucket -ne 'WEB_ASSET_DUPLICATES_READY') {
        return [pscustomobject]@{ Policy = $Policy; Demoted = $false; MatchedTerm = '' }
    }

    $demotion = Get-SafetyDemotion -Rows $Rows -CandidateKeeperPath $CandidateKeeperPath -SamplePaths $SamplePaths
    if ($null -eq $demotion) {
        return [pscustomobject]@{ Policy = $Policy; Demoted = $false; MatchedTerm = '' }
    }

    $updated = [pscustomobject]@{
        Bucket = $demotion.Bucket
        Risk = $demotion.Risk
        Notes = $Policy.Notes
    }
    [void]$NoteParts.Add('SafetyDemotedFromWebReady')
    $tokenName = if ($demotion.Bucket -eq 'HOLD_UNTOUCHED') { 'SensitiveHoldToken' } else { 'PhotoSampleToken' }
    [void]$NoteParts.Add("${tokenName}:$($demotion.MatchedTerm)")

    return [pscustomobject]@{
        Policy = $updated
        Demoted = $true
        MatchedTerm = $demotion.MatchedTerm
        DemotedTo = $demotion.Bucket
    }
}

function Get-WebAssetSignalScore {
    param(
        [string]$FullPath,
        [string]$FileName,
        [string]$Extension,
        [int64]$Length,
        [string]$PathClass,
        [string]$NameClass
    )
    $path = $FullPath.ToLowerInvariant()
    $name = $FileName.ToLowerInvariant()
    $ext = $Extension.ToLowerInvariant()
    $score = 0

    if ($path -match '\\_vti_cnf\\') { $score += 160 }
    if ($path -match '\\_derived\\') { $score += 150 }
    if ($path -match '\\themes\\|\\theme_assets\\|\\browser_extension\\') { $score += 140 }
    if ($path -match 'frontpage|fp to ew|california nature site|lesson \d+\\') { $score += 120 }
    if ($path -match '\\images\\|\\image\\|\\img\\') { $score += 70 }
    if ($path -match '\\appdata\\|\\extensions\\|\\chrome\\content\\|\\firefox\\profiles\\') { $score += 110 }
    if ($path -match 'icon-cache|browser_extension|theme_assets|seedboxes|participatory culture') { $score += 130 }
    if ($path -match '\\mcjunk\\|test_rename\\recovered') { $score += 40 }

    if ($ext -in @('.gif', '.png', '.bmp') -and $Length -lt 15000) { $score += 80 }
    if ($ext -in @('.gif', '.png', '.bmp') -and $Length -lt 3000) { $score += 40 }
    if ($name -match 'navbar|favicon|sprite|cleardot|bg\.gif|logo|button|banner|spacer|bullet|arrow|icon|thumb') { $score += 90 }
    if ($name -match 'dummy|sample|placeholder|test|tutorial|intro|outro') { $score += 70 }
    if ($PathClass -eq 'McJunkOrScratch') { $score += 50 }
    if ($NameClass -eq 'CarvedFileNumberName') { $score += 35 }
    if ($NameClass -eq 'GenericImageName') { $score += 45 }

    return $score
}

function Get-PhotoSignalScore {
    param(
        [string]$FullPath,
        [string]$FileName,
        [string]$Extension,
        [string]$PathClass,
        [string]$NameClass,
        [bool]$LikelyCameraOriginal,
        [bool]$LikelyCarved,
        [bool]$LikelyScratch
    )
    $path = $FullPath.ToLowerInvariant()
    $name = $FileName.ToLowerInvariant()
    $ext = $Extension.ToLowerInvariant()
    $score = 0

    if ($LikelyScratch) { return 0 }
    if ($PathClass -eq 'McPhotos') { $score += 130 }
    if ($PathClass -eq 'CameraUploads') { $score += 125 }
    if ($PathClass -eq 'DCIM') { $score += 120 }
    if ($PathClass -eq 'Pictures') { $score += 110 }
    if ($PathClass -eq 'NamedDateFolder') { $score += 85 }
    if ($path -match 'camera uploads|camera roll|my pictures|mcphotos') { $score += 40 }
    if ($path -match 'birthday|wedding|holiday|vacation|trip|family|graduation|party|tennis|swim') { $score += 55 }

    if ($LikelyCameraOriginal) { $score += 100 }
    if ($NameClass -eq 'OriginalCameraName') { $score += 95 }
    if ($NameClass -eq 'EditedOrExportedName') { $score += 35 }
    if ($ext -in @('.jpg', '.jpeg', '.jpe', '.heic', '.heif', '.tif', '.tiff', '.raw', '.dng', '.cr2', '.cr3', '.nef', '.nrw', '.arw', '.orf', '.rw2', '.raf', '.pef')) {
        $score += 80
    }
    if ($name -match '^(img|dsc|dscn|mvi|dscf)[_-]?\d+') { $score += 70 }
    if ($name -match '^\d{8}[_-]\d{6}') { $score += 65 }
    if ($LikelyCarved) { $score -= 80 }
    if ($NameClass -eq 'CarvedFileNumberName') { $score -= 90 }
    if ($NameClass -eq 'Screenshot') { $score += 20 }

    return [Math]::Max(0, $score)
}

function Get-KeeperScore {
    param(
        [string]$FullPath,
        [string]$FileName,
        [string]$Extension,
        [int64]$Length,
        [string]$PathClass,
        [string]$NameClass,
        [bool]$LikelyCameraOriginal,
        [bool]$LikelyCarved,
        [bool]$LikelyScratch
    )
    $path = $FullPath.ToLowerInvariant()
    $name = $FileName.ToLowerInvariant()
    $score = 0
    $reasons = New-Object System.Collections.Generic.List[string]

    if ($PathClass -eq 'McPhotos') { $score += 140; [void]$reasons.Add('McPhotos') }
    if ($PathClass -eq 'CameraUploads') { $score += 135; [void]$reasons.Add('CameraUploads') }
    if ($PathClass -eq 'DCIM') { $score += 130; [void]$reasons.Add('DCIM') }
    if ($PathClass -eq 'Pictures') { $score += 120; [void]$reasons.Add('Pictures') }
    if ($PathClass -eq 'NamedDateFolder') { $score += 90; [void]$reasons.Add('NamedDateFolder') }
    if ($LikelyCameraOriginal) { $score += 100; [void]$reasons.Add('LikelyCameraOriginal') }
    if ($NameClass -eq 'OriginalCameraName') { $score += 95; [void]$reasons.Add('OriginalCameraName') }
    if ($NameClass -eq 'EditedOrExportedName') { $score += 40; [void]$reasons.Add('EditedOrExportedName') }
    if ($Extension.ToLowerInvariant() -in @('.jpg', '.jpeg', '.jpe', '.heic', '.heif', '.tif', '.tiff', '.raw', '.dng', '.cr2', '.cr3', '.nef', '.arw', '.orf', '.rw2', '.raf', '.pef')) {
        $score += 70; [void]$reasons.Add('PhotoExtension')
    }
    if ($name -match '^(img|dsc|dscn|mvi|dscf)[_-]?\d+') { $score += 80; [void]$reasons.Add('CameraFilename') }
    if ($name -match '^\d{4}-\d{2}-\d{2}|^\d{8}[_-]\d{6}') { $score += 60; [void]$reasons.Add('DateFilename') }
    if ($name -match '^[a-z0-9].*[a-z0-9]$' -and -not (Test-CarvedPhotoName $FileName) -and $name -notmatch '^file\d') {
        $score += 25; [void]$reasons.Add('MeaningfulName')
    }

    if ($LikelyScratch -or $PathClass -eq 'McJunkOrScratch') { $score -= 130; [void]$reasons.Add('ScratchJunkPenalty') }
    if ($PathClass -eq 'RecoveredCarved') { $score -= 120; [void]$reasons.Add('RecoveredCarvedPenalty') }
    if ($path -match '\\_vti_cnf\\') { $score -= 160; [void]$reasons.Add('VtiCnfPenalty') }
    if ($path -match '\\_derived\\') { $score -= 150; [void]$reasons.Add('DerivedPenalty') }
    if ($path -match '\\themes\\|\\theme_assets\\|\\browser_extension\\') { $score -= 140; [void]$reasons.Add('ThemePenalty') }
    if ($path -match '\\appdata\\|\\extensions\\|\\chrome\\content\\|\\firefox\\profiles\\') { $score -= 120; [void]$reasons.Add('AppProfilePenalty') }
    if ($path -match 'frontpage|fp to ew|california nature site') { $score -= 90; [void]$reasons.Add('FrontPageSitePenalty') }
    if ($path -match '\\scratch\\|\\temp\\|\\tmp\\|test_rename\\recovered') { $score -= 110; [void]$reasons.Add('ScratchTempPenalty') }
    if ($LikelyCarved -or (Test-CarvedPhotoName $FileName)) { $score -= 120; [void]$reasons.Add('CarvedFileNamePenalty') }
    if ($NameClass -eq 'GenericImageName') { $score -= 70; [void]$reasons.Add('GenericImagePenalty') }
    if ($name -match 'navbar|favicon|sprite|cleardot|bg\.gif|logo|button|banner|spacer') { $score -= 100; [void]$reasons.Add('WebDecorNamePenalty') }
    if ($Extension.ToLowerInvariant() -in @('.gif', '.png', '.bmp') -and $Length -lt 15000 -and $PathClass -ne 'McPhotos') {
        $score -= 60; [void]$reasons.Add('TinyWebImagePenalty')
    }

    return [pscustomobject]@{ Score = $score; Reasons = ($reasons -join ';') }
}

function Get-PolicyBucket {
    param(
        [array]$Rows,
        [int]$KeeperScore,
        [bool]$Ambiguous,
        [bool]$AllCarved,
        [int]$WebSignalTotal,
        [int]$PhotoSignalTotal,
        [int]$WebSignalMax,
        [int]$PhotoSignalMax,
        [int]$KeeperWebScore,
        [string]$KeeperPathClass,
        [string]$KeeperExtension,
        [int64]$KeeperLength
    )
    $groupCount = $Rows.Count
    $notes = New-Object System.Collections.Generic.List[string]

    if ($groupCount -lt 2) {
        [void]$notes.Add('SingletonGroup')
        return [pscustomobject]@{ Bucket = 'HOLD_UNTOUCHED'; Risk = 'HIGH'; Notes = ($notes -join ';') }
    }

    $pathClasses = @($Rows | ForEach-Object { $_.PathClass.Trim() } | Sort-Object -Unique)
    $hasMcPhotos = $pathClasses -contains 'McPhotos'
    $hasPictures = $pathClasses -contains 'Pictures' -or $pathClasses -contains 'DCIM' -or $pathClasses -contains 'CameraUploads'
    $hasNamedDate = $pathClasses -contains 'NamedDateFolder'
    $allScratch = (@($Rows | Where-Object { -not (Test-IsTrue $_.LikelyScratchJunkPath) -and $_.PathClass.Trim() -ne 'McJunkOrScratch' }).Count -eq 0)
    $majorityWeb = ($WebSignalTotal -ge ($groupCount * 2)) -or ($WebSignalMax -ge 160)
    $majorityPhoto = ($PhotoSignalTotal -ge ($groupCount * 2)) -or ($PhotoSignalMax -ge 110)
    $keeperWeb = ($KeeperPathClass -in @('McJunkOrScratch', 'RecoveredCarved')) -or ($KeeperWebScore -ge 120)

    $tinyWebKeeper = $KeeperExtension -in @('.gif', '.png', '.bmp') -and $KeeperLength -lt 15000 -and -not $hasMcPhotos

    if ($majorityWeb -or ($keeperWeb -and $KeeperScore -lt 25) -or ($tinyWebKeeper -and -not $hasMcPhotos -and -not $hasPictures)) {
        if (-not $hasMcPhotos -and -not $hasPictures -and -not (Test-IsTrue $Rows[0].LikelyCameraOriginal)) {
            [void]$notes.Add('WebAssetDominant')
            if ($allScratch) { [void]$notes.Add('AllScratchOrJunkPaths') }
            return [pscustomobject]@{ Bucket = 'WEB_ASSET_DUPLICATES_READY'; Risk = 'LOW'; Notes = ($notes -join ';') }
        }
    }

    if ($AllCarved -or ($KeeperScore -lt 0) -or ($allScratch -and -not $majorityPhoto)) {
        [void]$notes.Add('RiskyOrUnclearGroup')
        if ($AllCarved) { [void]$notes.Add('AllCopiesCarved') }
        return [pscustomobject]@{ Bucket = 'HOLD_UNTOUCHED'; Risk = 'HIGH'; Notes = ($notes -join ';') }
    }

    if ($Ambiguous -or ($majorityPhoto -and $majorityWeb) -or ($KeeperScore -ge 20 -and $KeeperScore -lt 55) -or
        ($hasMcPhotos -and $AllCarved) -or ($hasNamedDate -and $WebSignalMax -ge 120)) {
        [void]$notes.Add('NeedsSampling')
        if ($Ambiguous) { [void]$notes.Add('AmbiguousKeeperTie') }
        if ($majorityPhoto -and $majorityWeb) { [void]$notes.Add('MixedPhotoAndWebSignals') }
        return [pscustomobject]@{ Bucket = 'PHOTO_SAMPLE_FIRST'; Risk = 'MEDIUM'; Notes = ($notes -join ';') }
    }

    if (($hasMcPhotos -or $hasPictures -or $hasNamedDate -or $majorityPhoto) -and $KeeperScore -ge 55 -and -not $Ambiguous) {
        [void]$notes.Add('StrongPhotoKeeper')
        if ($hasMcPhotos) { [void]$notes.Add('McPhotosContext') }
        return [pscustomobject]@{ Bucket = 'PHOTO_HUMAN_REVIEW'; Risk = 'MEDIUM'; Notes = ($notes -join ';') }
    }

    if ($KeeperScore -ge 40 -and $PhotoSignalMax -ge 80 -and -not $keeperWeb) {
        [void]$notes.Add('PhotoSignalsWithoutWebDominance')
        return [pscustomobject]@{ Bucket = 'PHOTO_HUMAN_REVIEW'; Risk = 'MEDIUM'; Notes = ($notes -join ';') }
    }

    if ($KeeperScore -ge 15 -or $PhotoSignalTotal -gt 0) {
        [void]$notes.Add('AmbiguousPhotoContext')
        return [pscustomobject]@{ Bucket = 'PHOTO_SAMPLE_FIRST'; Risk = 'MEDIUM'; Notes = ($notes -join ';') }
    }

    if ($majorityWeb -or $tinyWebKeeper) {
        [void]$notes.Add('ResidualWebAssetGroup')
        return [pscustomobject]@{ Bucket = 'WEB_ASSET_DUPLICATES_READY'; Risk = 'LOW'; Notes = ($notes -join ';') }
    }

    [void]$notes.Add('DefaultHoldUnclear')
    return [pscustomobject]@{ Bucket = 'HOLD_UNTOUCHED'; Risk = 'HIGH'; Notes = ($notes -join ';') }
}

$scriptRepoRoot = Get-NormPath (Split-Path -Parent $PSCommandPath)
$reportRoot = Get-NormPath $ReportRoot
$inventoryPath = Get-NormPath $InventoryPath

if (-not (Test-Path -LiteralPath $inventoryPath)) {
    throw "Inventory not found: $inventoryPath"
}
if (-not (Test-Path -LiteralPath $reportRoot)) {
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
}
if (Test-PathInsideRoot -ChildPath $reportRoot -RootPath $scriptRepoRoot) {
    throw "ReportRoot must not be inside repo. ReportRoot=$reportRoot Repo=$scriptRepoRoot"
}

$csvOut = Join-Path $reportRoot "phase2_mcnasbackup_photo_keeper_policy_$OutputStamp.csv"
$summaryOut = Join-Path $reportRoot "phase2_mcnasbackup_photo_keeper_policy_summary_$OutputStamp.txt"

Write-Host 'Phase 2 McNASBackup photo keeper-policy report (read-only)'
Write-Host "InventoryPath: $inventoryPath"
Write-Host "ReportRoot: $reportRoot"

$inventory = @(Import-Csv -LiteralPath $inventoryPath)
Write-Host "Loaded $($inventory.Count) inventory rows"

$sourceRoot = if ($inventory.Count -gt 0) { Get-NormPath $inventory[0].SourceRoot } else { 'I:\recover\McNASBackup' }
$allGroups = $inventory | Where-Object { -not [string]::IsNullOrWhiteSpace($_.SHA256) } | Group-Object { Get-NormHash $_.SHA256 }
$dupGroups = @($allGroups | Where-Object { $_.Count -ge 2 })
Write-Host "Duplicate hash groups: $($dupGroups.Count)"

$policyRows = New-Object System.Collections.ArrayList
$demotedRows = New-Object System.Collections.ArrayList
$gi = 0

foreach ($g in $dupGroups) {
    $gi++
    if ($gi % 250 -eq 0) { Write-Host "  policy $gi / $($dupGroups.Count)" }

    $rows = @($g.Group)
    $hash = Get-NormHash $g.Name
    $groupTotalBytes = ($rows | ForEach-Object { [int64]$_.Length } | Measure-Object -Sum).Sum
    $extrasCount = [Math]::Max(0, $rows.Count - 1)
    $sizeEach = [int64]$rows[0].Length
    $extrasBytes = $sizeEach * $extrasCount

    $webSignals = @($rows | ForEach-Object {
        Get-WebAssetSignalScore (Get-NormPath $_.FullName) $_.FileName $_.Extension ([int64]$_.Length) $_.PathClass.Trim() $_.NameClass.Trim()
    })
    $photoSignals = @($rows | ForEach-Object {
        Get-PhotoSignalScore (Get-NormPath $_.FullName) $_.FileName $_.Extension $_.PathClass.Trim() $_.NameClass.Trim() `
            (Test-IsTrue $_.LikelyCameraOriginal) (Test-IsTrue $_.LikelyCarvedOrRecoveredName) (Test-IsTrue $_.LikelyScratchJunkPath)
    })

    $scored = $rows | ForEach-Object {
        $full = Get-NormPath $_.FullName
        $s = Get-KeeperScore $full $_.FileName $_.Extension ([int64]$_.Length) $_.PathClass.Trim() $_.NameClass.Trim() `
            (Test-IsTrue $_.LikelyCameraOriginal) (Test-IsTrue $_.LikelyCarvedOrRecoveredName) (Test-IsTrue $_.LikelyScratchJunkPath)
        [pscustomobject]@{
            Row = $_
            FullName = $full
            Score = $s.Score
            Reasons = $s.Reasons
        }
    } | Sort-Object @{ Expression = { $_.Score }; Descending = $true }, @{ Expression = { $_.FullName } }

    $best = $scored[0]
    $secondScore = if ($scored.Count -gt 1) { $scored[1].Score } else { $scored[0].Score }
    $allCarved = (@($rows | Where-Object { -not (Test-CarvedPhotoName $_.FileName) }).Count -eq 0)
    $ambiguous = ($scored.Count -gt 1) -and (($best.Score - $secondScore) -lt 15)

    $keeperPath = $best.FullName
    $keeperReason = if ($best.Reasons) { $best.Reasons } else { 'DefaultFirstSorted' }
    if ($allCarved) { $keeperReason += ';AllCopiesCarvedGeneric' }
    if ($ambiguous) { $keeperReason += ';AmbiguousKeeperTie' }

    $keeperWebScore = Get-WebAssetSignalScore $keeperPath $best.Row.FileName $best.Row.Extension ([int64]$best.Row.Length) $best.Row.PathClass.Trim() $best.Row.NameClass.Trim()

    $policy = Get-PolicyBucket -Rows $rows -KeeperScore $best.Score -Ambiguous $ambiguous -AllCarved $allCarved `
        -WebSignalTotal ($webSignals | Measure-Object -Sum).Sum -PhotoSignalTotal ($photoSignals | Measure-Object -Sum).Sum `
        -WebSignalMax ($webSignals | Measure-Object -Maximum).Maximum -PhotoSignalMax ($photoSignals | Measure-Object -Maximum).Maximum `
        -KeeperWebScore $keeperWebScore -KeeperPathClass $best.Row.PathClass.Trim() -KeeperExtension $best.Row.Extension.ToLowerInvariant() -KeeperLength ([int64]$best.Row.Length)

    $pathClasses = ($rows | ForEach-Object { $_.PathClass.Trim() } | Sort-Object -Unique) -join '|'
    $nameClasses = ($rows | ForEach-Object { $_.NameClass.Trim() } | Sort-Object -Unique) -join '|'
    $extensions = ($rows | ForEach-Object { $_.Extension.ToLowerInvariant() } | Sort-Object -Unique) -join '|'
    $samplePaths = ($scored | Select-Object -First 8 | ForEach-Object { $_.FullName }) -join ' | '

    $noteParts = New-Object System.Collections.Generic.List[string]
    if ($policy.Notes) { [void]$noteParts.Add($policy.Notes) }
    if ($allCarved) { [void]$noteParts.Add('AllCopiesCarvedOrGeneric') }
    if ($ambiguous) { [void]$noteParts.Add('KeeperTieWithin15Points') }

    $demotionResult = Apply-WebReadySafetyDemotion -Policy $policy -NoteParts $noteParts -Rows $rows `
        -CandidateKeeperPath $keeperPath -SamplePaths $samplePaths
    $policy = $demotionResult.Policy
    if ($demotionResult.Demoted) {
        [void]$demotedRows.Add([pscustomobject]@{
            Hash = $hash
            DemotedTo = $demotionResult.DemotedTo
            MatchedTerm = $demotionResult.MatchedTerm
            DuplicateExtraCount = $extrasCount
            DuplicateExtraBytes = $extrasBytes
            CandidateKeeperPath = $keeperPath
        })
    }

    [void]$policyRows.Add([pscustomobject]@{
        Hash = $hash
        GroupFileCount = $rows.Count
        GroupTotalBytes = $groupTotalBytes
        DuplicateExtraCount = $extrasCount
        DuplicateExtraBytes = $extrasBytes
        CandidateKeeperPath = $keeperPath
        CandidateKeeperReason = $keeperReason
        PolicyBucket = $policy.Bucket
        RiskLevel = $policy.Risk
        PathClasses = $pathClasses
        NameClasses = $nameClasses
        Extensions = $extensions
        SamplePaths = $samplePaths
        Notes = ($noteParts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join ';'
    })
}

$demotedCount = $demotedRows.Count
$demotedExtras = ($demotedRows | ForEach-Object { [int]$_.DuplicateExtraCount } | Measure-Object -Sum).Sum
$demotedBytes = ($demotedRows | ForEach-Object { [int64]$_.DuplicateExtraBytes } | Measure-Object -Sum).Sum
$demotedToHold = @($demotedRows | Where-Object DemotedTo -eq 'HOLD_UNTOUCHED').Count
$demotedToSample = @($demotedRows | Where-Object DemotedTo -eq 'PHOTO_SAMPLE_FIRST').Count

$policyRows | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding utf8

$byBucket = $policyRows | Group-Object PolicyBucket | ForEach-Object {
    [pscustomobject]@{
        Bucket = $_.Name
        Groups = $_.Count
        Files = ($_.Group | ForEach-Object { [int]$_.GroupFileCount } | Measure-Object -Sum).Sum
        ExtrasFiles = ($_.Group | ForEach-Object { [int]$_.DuplicateExtraCount } | Measure-Object -Sum).Sum
        ExtrasBytes = ($_.Group | ForEach-Object { [int64]$_.DuplicateExtraBytes } | Measure-Object -Sum).Sum
        GroupBytes = ($_.Group | ForEach-Object { [int64]$_.GroupTotalBytes } | Measure-Object -Sum).Sum
    }
} | Sort-Object Groups -Descending

$extByBucket = $policyRows | ForEach-Object {
    foreach ($ext in ($_.Extensions -split '\|')) {
        if ([string]::IsNullOrWhiteSpace($ext)) { continue }
        [pscustomobject]@{ Bucket = $_.PolicyBucket; Extension = $ext; Groups = 1 }
    }
} | Group-Object Bucket, Extension | ForEach-Object {
    [pscustomobject]@{
        Bucket = ($_.Name -split ', ')[0]
        Extension = ($_.Name -split ', ')[1]
        Groups = $_.Count
    }
} | Sort-Object Bucket, Groups -Descending

$topFolders = $policyRows | ForEach-Object {
    $sub = Get-SourceSubfolder $_.CandidateKeeperPath $sourceRoot
    [pscustomobject]@{
        Subfolder = $sub
        Bucket = $_.PolicyBucket
        Groups = 1
        ExtrasBytes = [int64]$_.DuplicateExtraBytes
    }
} | Group-Object Subfolder | ForEach-Object {
    [pscustomobject]@{
        Subfolder = $_.Name
        Groups = $_.Count
        ExtrasBytes = ($_.Group | ForEach-Object { [int64]$_.ExtrasBytes } | Measure-Object -Sum).Sum
        TopBucket = ($_.Group | Group-Object Bucket | Sort-Object Count -Descending | Select-Object -First 1).Name
    }
} | Sort-Object ExtrasBytes -Descending | Select-Object -First 25

$webReady = @($policyRows | Where-Object PolicyBucket -eq 'WEB_ASSET_DUPLICATES_READY')
$photoHuman = @($policyRows | Where-Object PolicyBucket -eq 'PHOTO_HUMAN_REVIEW')
$photoSample = @($policyRows | Where-Object PolicyBucket -eq 'PHOTO_SAMPLE_FIRST')
$hold = @($policyRows | Where-Object PolicyBucket -eq 'HOLD_UNTOUCHED')

$lines = @(
    'Phase 2 McNASBackup Photo Keeper Policy Summary (Read-Only)'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "SourceInventory: $inventoryPath"
    "InventoryRows: $($inventory.Count)"
    "DuplicateHashGroups: $($dupGroups.Count)"
    "PolicyRows: $($policyRows.Count)"
    "UniqueInventoryFiles: $($allGroups.Count - $dupGroups.Count)"
    "TotalDuplicateExtraBytes: $(($policyRows | ForEach-Object { [int64]$_.DuplicateExtraBytes } | Measure-Object -Sum).Sum)"
    ''
    '=== WEB_READY SAFETY DEMOTIONS ==='
    "DemotedFromWebReadyGroups: $demotedCount"
    "DemotedDuplicateExtras: $demotedExtras"
    "DemotedDuplicateExtraBytes: $demotedBytes"
    "DemotedToHOLD_UNTOUCHED: $demotedToHold"
    "DemotedToPHOTO_SAMPLE_FIRST: $demotedToSample"
    ''
    '=== FINAL GROUP COUNTS BY POLICY BUCKET ==='
)
$lines += $byBucket | ForEach-Object {
    "$($_.Bucket): groups=$($_.Groups) files=$($_.Files) extrasFiles=$($_.ExtrasFiles) extrasBytes=$($_.ExtrasBytes) groupBytes=$($_.GroupBytes)"
}
$lines += ''
$lines += '=== DUPLICATE EXTRA BYTES BY POLICY BUCKET ==='
$lines += $byBucket | Sort-Object ExtrasBytes -Descending | ForEach-Object { "$($_.Bucket)`t$($_.ExtrasBytes)" }
$lines += ''
$lines += '=== EXTENSION BREAKDOWN BY BUCKET ==='
foreach ($bucket in ($byBucket | Sort-Object Bucket).Bucket) {
    $lines += "[$bucket]"
    $extByBucket | Where-Object Bucket -eq $bucket | Select-Object -First 12 | ForEach-Object {
        $lines += "  $($_.Extension)`tgroups=$($_.Groups)"
    }
}
$lines += ''
$lines += '=== TOP DUPLICATE SOURCE SUBFOLDERS (keeper path anchor) ==='
$lines += $topFolders | ForEach-Object { "$($_.Subfolder)`tgroups=$($_.Groups)`textrasBytes=$($_.ExtrasBytes)`ttopBucket=$($_.TopBucket)" }
$lines += ''
$lines += '=== TOP WEB_ASSET_DUPLICATES_READY GROUPS ==='
$webReady | Sort-Object { [int64]$_.DuplicateExtraBytes } -Descending | Select-Object -First 15 | ForEach-Object {
    $lines += "  $($_.DuplicateExtraBytes)`t$($_.GroupFileCount)`t$($_.Extensions)`t$($_.CandidateKeeperPath)"
}
$lines += ''
$lines += '=== TOP PHOTO_HUMAN_REVIEW GROUPS ==='
$photoHuman | Sort-Object { [int64]$_.DuplicateExtraBytes } -Descending | Select-Object -First 15 | ForEach-Object {
    $lines += "  $($_.DuplicateExtraBytes)`t$($_.GroupFileCount)`t$($_.Extensions)`t$($_.CandidateKeeperPath)"
}
$lines += ''
$lines += '=== TOP PHOTO_SAMPLE_FIRST GROUPS ==='
$photoSample | Sort-Object { [int64]$_.DuplicateExtraBytes } -Descending | Select-Object -First 15 | ForEach-Object {
    $lines += "  $($_.DuplicateExtraBytes)`t$($_.GroupFileCount)`t$($_.Notes)`t$($_.CandidateKeeperPath)"
}
$lines += ''
$lines += '=== TOP SAFETY-DEMOTED GROUPS ==='
$demotedRows | Sort-Object { [int64]$_.DuplicateExtraBytes } -Descending | Select-Object -First 15 | ForEach-Object {
    $lines += "  $($_.DemotedTo)`t$($_.DuplicateExtraBytes)`t$($_.MatchedTerm)`t$($_.CandidateKeeperPath)"
}
$lines += ''
$lines += '=== KEEPER POLICY CAUTIONS ==='
$lines += '- WEB_ASSET_DUPLICATES_READY groups with sensitive/personal/photo-family path terms are demoted before final bucket assignment.'
$lines += '- CandidateKeeperPath remains in place; only duplicate extras may ever be considered later.'
$lines += '- GIF/PNG/BMP dominate this inventory; many groups are FrontPage/_vti_cnf/web-theme cruft.'
$lines += '- McPhotos groups may still contain web GIF decor mixed with real photos; sample before move plan.'
$lines += '- Carved file### groups and mixed McPhotos/web paths need PHOTO_SAMPLE_FIRST review.'
$lines += '- This report does not create a move plan and does not modify the inventory.'
$lines += ''
$lines += '=== RECOMMENDED NEXT STEP ==='
if ($photoSample.Count -gt ($policyRows.Count * 0.20) -or $hold.Count -gt ($policyRows.Count * 0.15)) {
    $lines += 'RECOMMENDATION: Sample-review PHOTO_SAMPLE_FIRST and HOLD_UNTOUCHED groups before any move-extras planning.'
    $lines += "WEB_ASSET_DUPLICATES_READY: $($webReady.Count) groups may be separable later after spot-check of largest McPhotos-adjacent web groups."
}
else {
    $lines += 'RECOMMENDATION: Sample-review largest PHOTO_SAMPLE_FIRST groups; then consider separate web-asset vs photo-human planners.'
}
$lines += "WEB_ASSET_DUPLICATES_READY groups: $($webReady.Count); PHOTO_HUMAN_REVIEW: $($photoHuman.Count); PHOTO_SAMPLE_FIRST: $($photoSample.Count); HOLD_UNTOUCHED: $($hold.Count)"
$lines += 'No hard delete. No move plan. No -Execute.'
$lines += ''
$lines += 'WARNING: Read-only keeper policy report. No move, copy, delete, rename, cleanup, or move plan.'
$lines | Set-Content -LiteralPath $summaryOut -Encoding utf8

Write-Host ''
Write-Host "Keeper policy rows: $($policyRows.Count) -> $csvOut"
Write-Host "Summary: $summaryOut"
$byBucket | Format-Table -AutoSize
