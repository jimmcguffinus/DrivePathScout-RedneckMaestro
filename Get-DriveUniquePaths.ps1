[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$SourceRoot = 'I:\',

    [ValidateNotNullOrEmpty()]
    [string]$OutDir = (Join-Path $env:USERPROFILE 'Desktop\DrivePathInventory')
)

# Redneck Maestro Drive Path Scout v0.1.1
# Read-only inventory: the only writes are report files beneath OutDir.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    if ($full.Equals($pathRoot, [StringComparison]::OrdinalIgnoreCase)) { return $pathRoot }
    return $full.TrimEnd([char[]]'\/')
}

function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ChildPath,
        [Parameter(Mandatory = $true)][string]$RootPath
    )
    $child = Get-NormalizedPath $ChildPath
    $root = Get-NormalizedPath $RootPath
    $rootWithSlash = if ($root.EndsWith([IO.Path]::DirectorySeparatorChar)) { $root } else { $root + [IO.Path]::DirectorySeparatorChar }
    return $child.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        $child.StartsWith($rootWithSlash, [StringComparison]::OrdinalIgnoreCase)
}

function Test-ShouldSkipFolder {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Folder)

    try {
        if (($Folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return 'ReparsePointOrJunction'
        }
    }
    catch {
        return 'CannotReadAttributes'
    }

    switch -Regex ($Folder.Name) {
        '^(?i:System Volume Information)$' { return 'SystemVolumeInformation' }
        '^(?i:\$Recycle\.Bin)$'           { return 'RecycleBin' }
        '^(?i:RECYCLER)$'                  { return 'LegacyRecycler' }
        '^(?i:Config\.Msi)$'               { return 'ConfigMsiInstallerCache' }
        '^(?i:MSOCache)$'                  { return 'MSOCacheInstallerFiles' }
    }
    return $null
}

function Get-PathFlags {
    param([Parameter(Mandatory = $true)][string]$Path)
    $p = ($Path -replace '/', '\').ToLowerInvariant()
    $flags = [Collections.Generic.List[string]]::new()

    if ($p -match '\\users\\[^\\]+\\appdata(?:\\|$)') { $flags.Add('UserAppData') }
    elseif ($p -match '\\appdata(?:\\|$)') { $flags.Add('AppData_OrphanOrScattered') }
    $rules = [ordered]@{
        'ApplicationData_JunctionName'              = '\\application data(?:\\|$)'
        'LocalSettings_JunctionName'                = '\\local settings(?:\\|$)'
        'DocumentsAndSettings_LegacyProfileRoot'    = '\\documents and settings(?:\\|$)'
        'ProgramData'                               = '\\programdata(?:\\|$)'
        'WindowsOld'                                = '\\windows\.old(?:\\|$)'
        'WindowsSystem'                             = '\\windows(?:\\|$)'
        'BrowserForensics_FirefoxProfile'           = '\\mozilla\\firefox\\profiles(?:\\|$)'
        'BrowserForensics_ChromeProfile'            = '\\google\\chrome\\user data(?:\\|$)'
        'BrowserForensics_EdgeProfile'              = '\\microsoft\\edge\\user data(?:\\|$)'
        'BrowserForensics_BraveProfile'             = '\\bravesoftware\\brave-browser\\user data(?:\\|$)'
        'BrowserForensics_ChromiumProfile'          = '\\chromium\\user data(?:\\|$)'
        'BrowserForensics_OperaProfile'             = '\\opera software(?:\\|$)'
        'BrowserForensics_VivaldiProfile'           = '\\vivaldi\\user data(?:\\|$)'
        'BrowserForensics_TorBrowserProfile'        = '\\tor browser(?:\\|$)'
        'MailForensics_ThunderbirdProfile'          = '\\thunderbird\\profiles(?:\\|$)'
        'ForensicsCandidate_GoogleDesktop'          = '\\google\\google desktop(?:\\|$)'
        'BrowserForensics_WebCache'                 = '\\webcache(?:\\|$)'
        'BrowserForensics_INetCache'                = '\\inetcache(?:\\|$)'
        'BrowserForensics_TemporaryInternetFiles'   = '\\temporary internet files(?:\\|$)'
        'UserContent_Desktop'                       = '\\desktop(?:\\|$)'
        'UserContent_Documents'                     = '\\documents(?:\\|$)'
        'UserContent_Downloads'                     = '\\downloads(?:\\|$)'
        'UserContent_Pictures'                      = '\\pictures(?:\\|$)'
        'UserContent_Music'                         = '\\music(?:\\|$)'
        'UserContent_Videos'                        = '\\videos(?:\\|$)'
        'Code_GitRepo'                              = '\\\.git(?:\\|$)'
        'Code_NodeModules_JunkCandidate'            = '\\node_modules(?:\\|$)'
        'BackupCandidate'                           = '\\[^\\]*backup[^\\]*(?:\\|$)'
        'RecoveredCandidate'                        = '\\[^\\]*recovered[^\\]*(?:\\|$)'
    }
    foreach ($rule in $rules.GetEnumerator()) {
        if ($p -match $rule.Value) { $flags.Add($rule.Key) }
    }
    return ($flags -join ';')
}

$sourceItem = Get-Item -LiteralPath $SourceRoot
if (-not $sourceItem.PSIsContainer) { throw 'SourceRoot must be a folder or drive root.' }
$root = Get-NormalizedPath $sourceItem.FullName
$outFull = Get-NormalizedPath $OutDir
if (Test-PathInsideRoot $outFull $root) {
    throw 'Safety stop: OutDir must be outside SourceRoot.'
}

New-Item -ItemType Directory -Force -Path $outFull | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvOut = Join-Path $outFull "unique_paths_$stamp.csv"
$txtOut = Join-Path $outFull "unique_paths_$stamp.txt"
$mdOut  = Join-Path $outFull "chat_context_paths_$stamp.md"
$logOut = Join-Path $outFull "scan_log_$stamp.txt"

function Write-ScanLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" | Add-Content -LiteralPath $logOut -Encoding UTF8
}

Write-ScanLog "START read-only scan: $root"
Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  SPARKY PATH SCOUT v0.1.1' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host "`nSource:`n  $root`n`nReports:`n  $outFull`n"
Write-Host 'READ ONLY: no move, copy, rename, or delete.' -ForegroundColor Yellow
Write-Host 'Scanning... progress updates every 5 seconds. Ctrl+C cancels; nothing on the drive is changed.' -ForegroundColor DarkGray
Write-Host ''

function Show-ScanProgress {
    param(
        [string]$CurrentPath,
        [int]$FoldersScanned,
        [int]$FoldersSkipped,
        [int64]$FilesSeen,
        [double]$MbSeen,
        [int]$QueueDepth,
        [datetime]$StartedAt
    )
    $elapsed = (Get-Date) - $StartedAt
    $displayPath = $CurrentPath
    if ($displayPath.Length -gt 90) {
        $displayPath = '...' + $displayPath.Substring($displayPath.Length - 87)
    }
    $status = "[{0}] Folders: {1:N0} scanned, {2:N0} skipped | Files: {3:N0} | {4:N1} MB | Queue: {5:N0} | Elapsed: {6:hh\:mm\:ss} | {7}" -f (
        (Get-Date -Format 'HH:mm:ss'),
        $FoldersScanned,
        $FoldersSkipped,
        $FilesSeen,
        $MbSeen,
        $QueueDepth,
        $elapsed,
        $displayPath
    )
    Write-Progress -Activity 'Sparky Path Scout (read-only)' -Status $status -PercentComplete -1
    Write-Host "`r$status" -NoNewline -ForegroundColor DarkCyan
}

$results = [Collections.Generic.List[object]]::new()
$stack = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
$stack.Push([IO.DirectoryInfo]::new($root))
$scanStart = Get-Date
$lastProgressAt = [datetime]::MinValue
$progressIntervalSeconds = 5
$foldersScanned = 0
$foldersSkipped = 0
$filesSeen = [int64]0
$mbSeen = [double]0

while ($stack.Count -gt 0) {
    $dir = $stack.Pop()
    try {
        $reason = Test-ShouldSkipFolder $dir
        if ($null -ne $reason) {
            $foldersSkipped++
            Write-ScanLog "SKIP [$reason] $($dir.FullName)"
            if (((Get-Date) - $lastProgressAt).TotalSeconds -ge $progressIntervalSeconds) {
                Show-ScanProgress -CurrentPath $dir.FullName -FoldersScanned $foldersScanned -FoldersSkipped $foldersSkipped `
                    -FilesSeen $filesSeen -MbSeen $mbSeen -QueueDepth $stack.Count -StartedAt $scanStart
                $lastProgressAt = Get-Date
            }
            continue
        }

        $relative = $dir.FullName.Substring($root.TrimEnd([char[]]'\/').Length).TrimStart([char[]]'\/')
        $depth = if ($relative.Length -eq 0) { 0 } else { ($relative -split '[\\/]').Count }
        $count = 0; [int64]$bytes = 0; $extensions = @{}; $newest = $null
        try {
            foreach ($file in $dir.EnumerateFiles()) {
                $count++; $bytes += $file.Length
                $ext = if ([string]::IsNullOrWhiteSpace($file.Extension)) { '[no extension]' } else { $file.Extension.ToLowerInvariant() }
                $extensions[$ext] = 1 + $(if ($extensions.ContainsKey($ext)) { $extensions[$ext] } else { 0 })
                if ($null -eq $newest -or $file.LastWriteTime -gt $newest) { $newest = $file.LastWriteTime }
            }
        }
        catch { Write-ScanLog "FILE ENUMERATION ERROR $($dir.FullName) -- $($_.Exception.GetType().Name): $($_.Exception.Message)" }

        $topExt = ($extensions.GetEnumerator() |
            Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Name'; Descending = $false } |
            Select-Object -First 10 |
            ForEach-Object { "$($_.Key):$($_.Value)" }) -join ';'
        $folderMb = [math]::Round($bytes / 1MB, 2)
        $results.Add([pscustomobject]@{
            FullPath=$dir.FullName; RelativePath=$relative; Depth=$depth; FileCount=$count
            TotalMB=$folderMb; TopExtensions=$topExt
            NewestWrite=$newest; Flags=(Get-PathFlags $dir.FullName)
        })
        $foldersScanned++
        $filesSeen += $count
        $mbSeen += $folderMb

        try {
            foreach ($child in $dir.EnumerateDirectories()) {
                try {
                    $reason = Test-ShouldSkipFolder $child
                    if ($null -ne $reason) { Write-ScanLog "SKIP CHILD [$reason] $($child.FullName)"; continue }
                    $stack.Push($child)
                }
                catch { Write-ScanLog "CHILD INSPECTION ERROR $($child.FullName) -- $($_.Exception.GetType().Name): $($_.Exception.Message)" }
            }
        }
        catch { Write-ScanLog "FOLDER ENUMERATION ERROR $($dir.FullName) -- $($_.Exception.GetType().Name): $($_.Exception.Message)" }
    }
    catch { Write-ScanLog "SCAN ERROR $($dir.FullName) -- $($_.Exception.GetType().Name): $($_.Exception.Message)" }

    if (((Get-Date) - $lastProgressAt).TotalSeconds -ge $progressIntervalSeconds) {
        Show-ScanProgress -CurrentPath $dir.FullName -FoldersScanned $foldersScanned -FoldersSkipped $foldersSkipped `
            -FilesSeen $filesSeen -MbSeen $mbSeen -QueueDepth $stack.Count -StartedAt $scanStart
        $lastProgressAt = Get-Date
    }
}

Write-Progress -Activity 'Sparky Path Scout (read-only)' -Completed
Write-Host ''

$sorted = @($results | Sort-Object FullPath)
$sorted | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding UTF8
$sorted.FullPath | Out-File -LiteralPath $txtOut -Encoding UTF8
$flagged = @($sorted | Where-Object { $_.Flags })
$totalFiles = [int64](($sorted | Measure-Object FileCount -Sum).Sum)
$totalMB = [double](($sorted | Measure-Object TotalMB -Sum).Sum)
$md = [Collections.Generic.List[string]]::new()
@('# Drive Path Inventory','','Generated by Redneck Maestro Path Scout v0.1.1','','## Source Root','','```text',$root,'```','',"Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",'','## Summary','',"- Total folders scanned: $($sorted.Count)","- Total files counted: $totalFiles","- Total MB counted: $([math]::Round($totalMB,2))",'','## Safety','','- Read-only scan','- No move, copy, rename, or delete','- Reparse points, junctions, and known system trash zones skipped','- Errors logged; scan continued','','## Flagged Paths','') | ForEach-Object { $md.Add($_) }
if ($flagged.Count -eq 0) { $md.Add('_No flagged paths found._') }
foreach ($row in ($flagged | Select-Object -First 500)) {
    @('### PATH','','```text',$row.FullPath,'```','',"- Flags: $($row.Flags)","- Files: $($row.FileCount)","- Size MB: $($row.TotalMB)","- Top extensions: $($row.TopExtensions)",'','---','') | ForEach-Object { $md.Add($_) }
}
$md.Add('## Top 50 Folders by Size'); $md.Add('')
foreach ($row in ($sorted | Sort-Object TotalMB -Descending | Select-Object -First 50)) {
    @("- Size MB: $($row.TotalMB); Files: $($row.FileCount)",'','```text',$row.FullPath,'```','') | ForEach-Object { $md.Add($_) }
}
$md.Add('## Top 50 Folders by File Count'); $md.Add('')
foreach ($row in ($sorted | Sort-Object FileCount -Descending | Select-Object -First 50)) {
    @("- Files: $($row.FileCount); Size MB: $($row.TotalMB)",'','```text',$row.FullPath,'```','') | ForEach-Object { $md.Add($_) }
}
$md.Add('## Shallow Folder Map (Depth 0-4)'); $md.Add('')
foreach ($row in ($sorted | Where-Object Depth -le 4 | Select-Object -First 1000)) { $md.Add("- ``$($row.FullPath)``") }
$md | Out-File -LiteralPath $mdOut -Encoding UTF8
Write-ScanLog "COMPLETE folders=$($sorted.Count) files=$totalFiles"

Write-Host "`n========================================" -ForegroundColor Green
Write-Host '  SPARKY PATH SCOUT COMPLETE' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Green
Write-Host "`nCSV:`n  $csvOut`n`nPaths:`n  $txtOut`n`nChat report:`n  $mdOut`n`nLog:`n  $logOut`n"
Write-Host 'Nothing was moved, copied, renamed, or deleted.' -ForegroundColor Yellow
