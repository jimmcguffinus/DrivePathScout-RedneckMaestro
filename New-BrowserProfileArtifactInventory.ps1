[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string[]]$ScanRoots = @(
        'I:\recover\McNASBackup',
        'I:\1tbrecover'
    ),

    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',

    [ValidateNotNullOrEmpty()]
    [string]$RunStamp = '20260707'
)

# Browser profile artifact inventory v0.1.0 (read-only).
# INVENTORY ONLY: no hashing, move, copy, rename, delete, corral, or move-plan behavior.
# Writes only the three stamped inventory reports under ReportRoot.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedPathSafe([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { return $Path.Trim().TrimEnd('\') }
}

function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ChildPath,
        [Parameter(Mandatory = $true)][string]$RootPath
    )
    $child = Get-NormalizedPathSafe $ChildPath
    $root = Get-NormalizedPathSafe $RootPath
    if (-not $child -or -not $root) { return $false }
    $prefix = if ($root.EndsWith('\')) { $root } else { $root + '\' }
    return $child.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-RelativePathSafe {
    param([string]$FullPath, [string]$RootPath)
    $full = Get-NormalizedPathSafe $FullPath
    $root = Get-NormalizedPathSafe $RootPath
    if ((Test-PathInsideRoot -ChildPath $full -RootPath $root) -and $full.Length -gt $root.Length) {
        return $full.Substring($root.Length).TrimStart('\')
    }
    if ($full.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { return '.' }
    return $full
}

function Test-ReparsePointItem($Item) {
    return (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-BrowserFamily {
    param([string]$FullPath, [string]$ArtifactName)
    $path = $FullPath.ToLowerInvariant()
    $name = $ArtifactName.ToLowerInvariant()

    if ($path -match '\\google\\chrome(?: beta| sxs)?\\user data(\\|$)') { return 'Chrome' }
    if ($path -match '\\microsoft\\edge\\user data(\\|$)') { return 'Edge' }
    if ($path -match '\\chromium\\user data(\\|$)') { return 'Chromium' }
    if ($path -match '\\mozilla\\(firefox|seamonkey)\\profiles(\\|$)') { return 'Firefox' }
    if ($path -match '\\opera software(\\|$)') { return 'Opera' }
    if ($script:firefoxArtifactNames.Contains($name)) { return 'Firefox' }
    return 'Unknown'
}

function Get-ProfileName {
    param([string]$FullPath, [string]$BrowserFamily)
    $path = Get-NormalizedPathSafe $FullPath

    if ($BrowserFamily -in @('Chrome', 'Edge', 'Chromium')) {
        if ($path -match '(?i)\\User Data\\(Default|Profile \d+)(\\|$)') { return $Matches[1] }
    }
    elseif ($BrowserFamily -eq 'Firefox') {
        if ($path -match '(?i)\\(?:Firefox|SeaMonkey)\\Profiles\\([^\\]+)(\\|$)') { return $Matches[1] }
    }
    elseif ($BrowserFamily -eq 'Opera') {
        if ($path -match '(?i)\\Opera Software\\([^\\]+)(\\|$)') { return $Matches[1] }
    }
    return ''
}

function Get-ArtifactKind([string]$Name) {
    switch ($Name.ToLowerInvariant()) {
        { $_ -in @('history', 'history-journal', 'visited links') } { return 'History' }
        { $_ -in @('bookmarks', 'bookmarks.bak') } { return 'Bookmarks' }
        { $_ -in @('cookies', 'cookies-journal', 'cookies.sqlite', 'cookies.sqlite-wal', 'cookies.sqlite-shm') } { return 'Cookies' }
        { $_ -in @('login data', 'login data-journal', 'logins.json') } { return 'Logins' }
        { $_ -in @('web data', 'web data-journal', 'formhistory.sqlite') } { return 'AutofillWebData' }
        { $_ -in @('favicons', 'favicons-journal', 'favicons.sqlite', 'favicons.sqlite-wal', 'favicons.sqlite-shm') } { return 'Favicons' }
        { $_ -in @('current session', 'current tabs', 'last session', 'last tabs', 'sessions', 'sessionstore.jsonlz4', 'recovery.jsonlz4', 'previous.jsonlz4', 'top sites', 'top sites-journal') } { return 'SessionsTabs' }
        { $_ -in @('preferences', 'secure preferences', 'prefs.js', 'network persistent state') } { return 'Preferences' }
        { $_ -in @('places.sqlite', 'places.sqlite-wal', 'places.sqlite-shm') } { return 'FirefoxPlaces' }
        { $_ -in @('key4.db', 'key3.db', 'cert9.db', 'cert8.db') } { return 'FirefoxKeyMaterial' }
        { $_ -in @('permissions.sqlite', 'content-prefs.sqlite', 'webappsstore.sqlite') } { return 'UnknownBrowserArtifact' }
        default { return 'UnknownBrowserArtifact' }
    }
}

function Get-ArtifactClassification {
    param([string]$FullPath, [string]$Name, [bool]$IsProfileFolder)
    $lowerPath = $FullPath.ToLowerInvariant()
    $lowerName = $Name.ToLowerInvariant()
    $kind = if ($IsProfileFolder) { 'UnknownBrowserArtifact' } else { Get-ArtifactKind $Name }

    if ($lowerPath -match '(\\|^)(cache|code cache|gpucache|media cache|icon-cache|flash player|#sharedobjects|google gears|temporary internet files)(\\|$)') {
        return [pscustomobject]@{ Kind = 'CacheOrOfflineStorage'; Tier = 'LOW_VALUE_CACHE'; Reason = 'Path is inside a named browser cache or offline-storage area.' }
    }
    if ($lowerName -eq 'formhistory.sqlite') {
        return [pscustomobject]@{ Kind = 'AutofillWebData'; Tier = 'SENSITIVE_HOLD'; Reason = 'Firefox form history may contain typed searches and saved form entries; protect and review carefully.' }
    }
    if ($lowerName -in @('cookies', 'cookies-journal', 'cookies.sqlite', 'cookies.sqlite-wal', 'cookies.sqlite-shm',
            'login data', 'login data-journal', 'web data', 'web data-journal', 'logins.json',
            'key4.db', 'key3.db', 'cert9.db', 'cert8.db')) {
        return [pscustomobject]@{ Kind = $kind; Tier = 'SENSITIVE_HOLD'; Reason = 'Contains browser authentication, cookie, credential, certificate, or autofill material; protect and review carefully.' }
    }
    if ($lowerName -in @('history', 'history-journal', 'bookmarks', 'bookmarks.bak',
            'places.sqlite', 'places.sqlite-wal', 'places.sqlite-shm',
            'favicons', 'favicons-journal', 'favicons.sqlite', 'favicons.sqlite-wal', 'favicons.sqlite-shm',
            'preferences', 'secure preferences', 'prefs.js', 'current session', 'current tabs',
            'last session', 'last tabs', 'sessions', 'sessionstore.jsonlz4', 'recovery.jsonlz4',
            'previous.jsonlz4', 'top sites', 'top sites-journal')) {
        return [pscustomobject]@{ Kind = $kind; Tier = 'KEEPER_HIGH'; Reason = 'High-value browser history, bookmark, preference, favicon, or session artifact.' }
    }
    if ($IsProfileFolder) {
        return [pscustomobject]@{ Kind = $kind; Tier = 'REVIEW'; Reason = 'Detected browser profile root; directory recorded without scanning file contents or hashing.' }
    }
    return [pscustomobject]@{ Kind = $kind; Tier = 'REVIEW'; Reason = 'Recognized browser-profile artifact requiring contextual review.' }
}

function Get-ProfileFolderSignature([string]$FullPath) {
    $path = (Get-NormalizedPathSafe $FullPath).ToLowerInvariant()
    if ($path -match '\\google\\chrome\\user data$') { return 'Google\Chrome\User Data' }
    if ($path -match '\\google\\chrome beta\\user data$') { return 'Google\Chrome Beta\User Data' }
    if ($path -match '\\google\\chrome sxs\\user data$') { return 'Google\Chrome SxS\User Data' }
    if ($path -match '\\microsoft\\edge\\user data$') { return 'Microsoft\Edge\User Data' }
    if ($path -match '\\chromium\\user data$') { return 'Chromium\User Data' }
    if ($path -match '\\mozilla\\firefox\\profiles$') { return 'Mozilla\Firefox\Profiles' }
    if ($path -match '\\mozilla\\seamonkey\\profiles$') { return 'Mozilla\SeaMonkey\Profiles' }
    if ($path -match '\\opera software$') { return 'Opera Software' }
    return ''
}

function Add-ScanError {
    param([string]$Root, [string]$Path, [string]$Operation, [string]$Message)
    [void]$script:errors.Add([pscustomobject]@{
        Root = $Root
        Path = $Path
        Operation = $Operation
        ErrorMessage = $Message
    })
}

function Add-InventoryHit {
    param($Item, [string]$Root, [bool]$IsProfileFolder)
    try {
        $full = Get-NormalizedPathSafe $Item.FullName
        $relative = Get-RelativePathSafe -FullPath $full -RootPath $Root
        $family = Get-BrowserFamily -FullPath $full -ArtifactName $Item.Name
        $profile = Get-ProfileName -FullPath $full -BrowserFamily $family
        $classification = Get-ArtifactClassification -FullPath $full -Name $Item.Name -IsProfileFolder $IsProfileFolder
        $pathLength = $full.Length
        $reason = $classification.Reason
        if ($IsProfileFolder) {
            $signature = Get-ProfileFolderSignature $full
            $reason = "Detected browser profile folder: $signature. $reason"
        }

        [void]$script:hits.Add([pscustomobject][ordered]@{
            Root = $Root
            FullName = $full
            RelativePath = $relative
            Name = $Item.Name
            Extension = if ($Item.PSIsContainer) { '' } else { $Item.Extension.ToLowerInvariant() }
            Length = if ($Item.PSIsContainer) { [int64]0 } else { [int64]$Item.Length }
            LastWriteTimeUtc = $Item.LastWriteTimeUtc.ToString('o')
            DirectoryName = if ($Item.PSIsContainer) { $full } else { $Item.DirectoryName }
            BrowserFamily = $family
            ProfileName = $profile
            ArtifactKind = $classification.Kind
            ArtifactTier = $classification.Tier
            Reason = $reason
            PathLength = $pathLength
            TooLongRisk = ($pathLength -ge 240)
        })
    }
    catch {
        Add-ScanError -Root $Root -Path $Item.FullName -Operation 'ClassifyHit' -Message $_.Exception.Message
    }
}

function Write-CsvWithHeader {
    param([array]$Rows, [string]$Path, [string[]]$Columns)
    if ($Rows.Count -gt 0) {
        $Rows | Select-Object $Columns | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
    }
    else {
        (($Columns | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -join ',') |
            Set-Content -LiteralPath $Path -Encoding utf8
    }
}

$artifactNames = @(
    'History', 'History-journal', 'Bookmarks', 'Bookmarks.bak', 'Cookies', 'Cookies-journal',
    'Login Data', 'Login Data-journal', 'Web Data', 'Web Data-journal', 'Favicons', 'Favicons-journal',
    'Top Sites', 'Top Sites-journal', 'Preferences', 'Secure Preferences', 'Current Session', 'Current Tabs',
    'Last Session', 'Last Tabs', 'Sessions', 'Visited Links', 'Network Persistent State',
    'places.sqlite', 'places.sqlite-wal', 'places.sqlite-shm', 'favicons.sqlite', 'favicons.sqlite-wal',
    'favicons.sqlite-shm', 'cookies.sqlite', 'cookies.sqlite-wal', 'cookies.sqlite-shm', 'formhistory.sqlite',
    'permissions.sqlite', 'content-prefs.sqlite', 'webappsstore.sqlite', 'logins.json', 'key4.db', 'key3.db',
    'cert9.db', 'cert8.db', 'prefs.js', 'sessionstore.jsonlz4', 'recovery.jsonlz4', 'previous.jsonlz4'
)
$artifactNameSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in $artifactNames) { [void]$artifactNameSet.Add($name) }

$script:firefoxArtifactNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in @(
        'places.sqlite', 'places.sqlite-wal', 'places.sqlite-shm', 'favicons.sqlite', 'favicons.sqlite-wal',
        'favicons.sqlite-shm', 'cookies.sqlite', 'cookies.sqlite-wal', 'cookies.sqlite-shm', 'formhistory.sqlite',
        'permissions.sqlite', 'content-prefs.sqlite', 'webappsstore.sqlite', 'logins.json', 'key4.db', 'key3.db',
        'cert9.db', 'cert8.db', 'prefs.js', 'sessionstore.jsonlz4', 'recovery.jsonlz4', 'previous.jsonlz4')) {
    [void]$script:firefoxArtifactNames.Add($name)
}

$reportRootNormalized = Get-NormalizedPathSafe $ReportRoot
$repoRoot = Get-NormalizedPathSafe (Split-Path -Parent $PSCommandPath)
if (Test-PathInsideRoot -ChildPath $reportRootNormalized -RootPath $repoRoot) {
    throw "ReportRoot must be outside the repo. ReportRoot=$reportRootNormalized RepoRoot=$repoRoot"
}
foreach ($root in $ScanRoots) {
    if (Test-PathInsideRoot -ChildPath $reportRootNormalized -RootPath $root) {
        throw "ReportRoot must be outside every ScanRoot. ReportRoot=$reportRootNormalized ScanRoot=$root"
    }
}
if (-not (Test-Path -LiteralPath $reportRootNormalized -PathType Container)) {
    New-Item -ItemType Directory -Path $reportRootNormalized -Force | Out-Null
}

$inventoryOut = Join-Path $reportRootNormalized "browser_profile_artifact_inventory_$RunStamp.csv"
$summaryOut = Join-Path $reportRootNormalized "browser_profile_artifact_inventory_summary_$RunStamp.txt"
$errorsOut = Join-Path $reportRootNormalized "browser_profile_artifact_inventory_errors_$RunStamp.csv"

$script:hits = New-Object System.Collections.ArrayList
$script:errors = New-Object System.Collections.ArrayList
$directoriesExamined = 0
$filesExamined = 0
$skippedReparsePoints = 0

Write-Host 'Browser profile artifact inventory (read-only)'
Write-Host "RunStamp: $RunStamp"
Write-Host "ReportRoot: $reportRootNormalized"
Write-Host 'No hashing. No move. No copy. No rename. No delete. No move plan.'

foreach ($configuredRoot in $ScanRoots) {
    $root = Get-NormalizedPathSafe $configuredRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Add-ScanError -Root $root -Path $root -Operation 'ValidateRoot' -Message 'Scan root not found or not a directory.'
        continue
    }

    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($root)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        $directoriesExamined++
        if (($directoriesExamined % 1000) -eq 0) {
            Write-Host "  directories=$directoriesExamined files=$filesExamined hits=$($script:hits.Count) errors=$($script:errors.Count)"
        }

        try {
            $currentItem = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (Test-ReparsePointItem $currentItem) {
                $skippedReparsePoints++
                continue
            }
        }
        catch {
            Add-ScanError -Root $root -Path $current -Operation 'InspectDirectory' -Message $_.Exception.Message
            continue
        }

        try {
            $entries = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)
        }
        catch {
            Add-ScanError -Root $root -Path $current -Operation 'EnumerateDirectory' -Message $_.Exception.Message
            continue
        }

        foreach ($entry in $entries) {
            try {
                if (Test-ReparsePointItem $entry) {
                    $skippedReparsePoints++
                    continue
                }

                if ($entry.PSIsContainer) {
                    $profileSignature = Get-ProfileFolderSignature $entry.FullName
                    if ($profileSignature) {
                        Add-InventoryHit -Item $entry -Root $root -IsProfileFolder $true
                    }
                    if ($artifactNameSet.Contains($entry.Name)) {
                        Add-InventoryHit -Item $entry -Root $root -IsProfileFolder $false
                    }
                    $stack.Push($entry.FullName)
                    continue
                }

                $filesExamined++
                if ($artifactNameSet.Contains($entry.Name)) {
                    Add-InventoryHit -Item $entry -Root $root -IsProfileFolder $false
                }
            }
            catch {
                Add-ScanError -Root $root -Path $entry.FullName -Operation 'InspectEntry' -Message $_.Exception.Message
            }
        }
    }
}

$inventoryColumns = @(
    'Root', 'FullName', 'RelativePath', 'Name', 'Extension', 'Length', 'LastWriteTimeUtc',
    'DirectoryName', 'BrowserFamily', 'ProfileName', 'ArtifactKind', 'ArtifactTier', 'Reason',
    'PathLength', 'TooLongRisk'
)
$errorColumns = @('Root', 'Path', 'Operation', 'ErrorMessage')
$sortedHits = @($script:hits | Sort-Object Root, FullName -Unique)
$sortedErrors = @($script:errors | Sort-Object Root, Path, Operation)
Write-CsvWithHeader -Rows $sortedHits -Path $inventoryOut -Columns $inventoryColumns
Write-CsvWithHeader -Rows $sortedErrors -Path $errorsOut -Columns $errorColumns

$byTier = @($sortedHits | Group-Object ArtifactTier | Sort-Object Name)
$byFamily = @($sortedHits | Group-Object BrowserFamily | Sort-Object Name)
$byKind = @($sortedHits | Group-Object ArtifactKind | Sort-Object Name)
$profileRoots = @($sortedHits | Where-Object { $_.Reason -like 'Detected browser profile folder:*' })
$sensitiveCount = @($sortedHits | Where-Object ArtifactTier -eq 'SENSITIVE_HOLD').Count
$keeperCount = @($sortedHits | Where-Object ArtifactTier -eq 'KEEPER_HIGH').Count
$cacheCount = @($sortedHits | Where-Object ArtifactTier -eq 'LOW_VALUE_CACHE').Count
$tooLongCount = @($sortedHits | Where-Object TooLongRisk -eq $true).Count

$summary = @(
    'Browser Profile Artifact Inventory Summary (Read-Only)'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "RunStamp: $RunStamp"
    "ScanRoots: $((@($ScanRoots) | ForEach-Object { Get-NormalizedPathSafe $_ }) -join ' | ')"
    "TotalHits: $($sortedHits.Count)"
    "DirectoriesExamined: $directoriesExamined"
    "FilesExamined: $filesExamined"
    "SkippedReparsePoints: $skippedReparsePoints"
    "TooLongRiskCount: $tooLongCount"
    "SENSITIVE_HOLDCount: $sensitiveCount"
    "KEEPER_HIGHCount: $keeperCount"
    "LOW_VALUE_CACHECount: $cacheCount"
    "ErrorsCount: $($sortedErrors.Count)"
    ''
    '=== HITS BY ARTIFACT TIER ==='
)
$summary += $byTier | ForEach-Object { "$($_.Name): $($_.Count)" }
$summary += ''
$summary += '=== HITS BY BROWSER FAMILY ==='
$summary += $byFamily | ForEach-Object { "$($_.Name): $($_.Count)" }
$summary += ''
$summary += '=== HITS BY ARTIFACT KIND ==='
$summary += $byKind | ForEach-Object { "$($_.Name): $($_.Count)" }
$summary += ''
$summary += '=== TOP PROFILE ROOTS ==='
$summary += $profileRoots | Select-Object -First 50 | ForEach-Object { "$($_.BrowserFamily)`t$($_.FullName)" }
$summary += ''
$summary += '=== LARGEST 25 ARTIFACTS ==='
$summary += $sortedHits | Where-Object Length -gt 0 | Sort-Object { [int64]$_.Length } -Descending | Select-Object -First 25 | ForEach-Object {
    "$($_.Length)`t$($_.ArtifactTier)`t$($_.BrowserFamily)`t$($_.FullName)"
}
$summary += ''
$summary += '=== SECURITY WARNINGS ==='
$summary += '- SENSITIVE_HOLD artifacts may contain cookies, saved logins, autofill data, encryption keys, or certificates.'
$summary += '- Do not open, upload, share, move, or delete sensitive browser artifacts without an explicit reviewed plan.'
$summary += '- This scan did not hash files or inspect browser database contents.'
$summary += '- Reparse points and junctions were skipped; access/path errors were logged and scanning continued.'
$summary += ''
$summary += "InventoryCsv: $inventoryOut"
$summary += "ErrorsCsv: $errorsOut"
$summary | Set-Content -LiteralPath $summaryOut -Encoding utf8

Write-Host ''
Write-Host 'SUMMARY'
Write-Host "TotalHits=$($sortedHits.Count)"
Write-Host "KEEPER_HIGH=$keeperCount SENSITIVE_HOLD=$sensitiveCount LOW_VALUE_CACHE=$cacheCount"
Write-Host "Errors=$($sortedErrors.Count) ReparsePointsSkipped=$skippedReparsePoints TooLongRisk=$tooLongCount"
Write-Host "Inventory=$inventoryOut"
Write-Host "Summary=$summaryOut"
Write-Host "ErrorsReport=$errorsOut"
Write-Host 'COMPLETE'
