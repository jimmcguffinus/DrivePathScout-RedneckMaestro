[CmdletBinding()]
param(
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [string]$HashStamp = '20260703-004335',
    [string]$OutputStamp = '20260704',
    [string]$TargetRoot = 'I:\recover\McNASBackup',
    [switch]$VerifyLiveHash
)

# Phase 2 McNASBackup music/audio duplicate inventory (read-only)
# No move, copy, delete, rename, cleanup, or move plan.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    try { return [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { return $p.Trim() }
}
function Get-NormHash([string]$h) { $h.Trim().ToUpperInvariant() }
function Get-ShortHash([string]$h) { $n = Get-NormHash $h; if ($n.Length -ge 8) { $n.Substring(0, 8) } else { $n } }

$targetRoot = Get-NormPath $TargetRoot
$audioExts = @('.mp3', '.m4a', '.wma', '.wav', '.flac', '.aac', '.ogg')
$excludedPrefixes = @(
    'I:\_RECOVERY_WORKBENCH\02_KEEPERS_REVIEW',
    'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED',
    'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW',
    'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW'
) | ForEach-Object { Get-NormPath $_ }

function Test-ExcludedWorkbench([string]$path) {
    $n = Get-NormPath $path
    foreach ($prefix in $excludedPrefixes) {
        if ($n.StartsWith($prefix + '\', [StringComparison]::OrdinalIgnoreCase) -or $n.Equals($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-MatchPatterns([string]$text, [string[]]$patterns) {
    $t = $text.ToLowerInvariant()
    foreach ($p in $patterns) { if ($t -match $p) { return $true } }
    return $false
}

$musicLibraryPatterns = @(
    '\\music\\', '\\musics\\', '\\my music\\', '\\itunes\\', 'google play music', 'play music',
    'amazon music', 'spotify', 'ripped', 'rip\\', 'album', 'artist', 'soundtrack', 'playlist',
    'jenni\.music', 'jenni\\music', 'mobilemom', 'mcphotos\\music', 'drobo_bkup\\music',
    'dropbox\\.*music', 'mcdropbox\\.*music', 'audio books', 'audiobook', 'podcast',
    'gracenote', 'mp3tag', 'winamp', 'media player', 'library\\', 'collection\\',
    'beatles', 'classical', 'jazz', 'rock\\', 'country\\', 'christian\\', 'worship\\',
    'karaoke', 'ringtone', 'ringtones', 'voice memo', 'recorder'
)

$personalLibraryPatterns = @(
    'family','mcfamily','mcphotos','mchomemovies','jenni','jim\.','mcguffin','moms_stuff',
    'smellycunt','mobilemom','camera uploads','home','personal','favorites','my songs',
    'imported','purchased','amazon mp3', 'itunes music'
)

$cacheSamplePatterns = @(
    'cache','webcache','browser','temp\\','tmp\\','appdata\\local','sample\\','samples\\',
    'sound effect','sfx\\','notification','alert','beep','click','ding','ui\\','system\\',
    'windows\\winsxs','microsoft\\','office\\','skype','teams\\','zoom\\',
    'tutorial','demo','dummy','placeholder','test tone','test\\.wav','silence\\.',
    'total training','theme_assets','browser_extension','icon-cache','miro\\support',
    'participatory culture','seedboxes'
)

function Test-MusicSignal([string]$fullPath, [string]$fileName, [string]$ext) {
    if ($audioExts -contains $ext.ToLowerInvariant()) { return $true }
    return Test-MatchPatterns ($fullPath + ' ' + $fileName) @('\.mp3', '\.m4a', '\.wma', '\.wav', '\.flac', '\.aac', '\.ogg')
}
function Test-PersonalLibrarySignal([string]$fullPath, [string]$fileName) {
    $text = $fullPath + ' ' + $fileName
    if (Test-MatchPatterns $text $personalLibraryPatterns) { return $true }
    if (Test-MatchPatterns $text $musicLibraryPatterns) { return $true }
    if ($fileName -match '^\d{2} - |^\d{2}\.\s|track \d|disc \d|cd \d') { return $true }
    if ($fileName -match ' - .+\.(mp3|m4a|wma|wav|flac|aac|ogg)$') { return $true }
    return $false
}
function Test-CacheOrSampleSignal([string]$fullPath, [string]$fileName, [int64]$sizeBytes) {
    if (Test-MatchPatterns ($fullPath + ' ' + $fileName) $cacheSamplePatterns) { return $true }
    if ($sizeBytes -lt 200000 -and $fileName -match 'sample|demo|test|beep|click|sfx|alert|intro|outro|silence') { return $true }
    if ($sizeBytes -lt 50000) { return $true }
    return $false
}
function Test-CarvedAudioName([string]$name) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($name).ToLowerInvariant()
    return ($stem -match '^file\d+$')
}

function Get-SourceSubfolder([string]$fullPath) {
    $rel = if ($fullPath.Length -gt $targetRoot.Length) { $fullPath.Substring($targetRoot.Length).TrimStart('\') } else { '' }
    if ([string]::IsNullOrWhiteSpace($rel)) { return '(root)' }
    $parts = $rel -split '\\'
    if ($parts.Count -ge 2) { return ($parts[0..1] -join '\') }
    return $parts[0]
}

Write-Host 'Loading duplicate group index...'
$dupGroups = @{}
Import-Csv (Join-Path $ReportRoot "duplicate_hash_groups_$HashStamp.csv") | ForEach-Object {
    $c = [int]$_.Count
    if ($c -ge 2) {
        $h = Get-NormHash $_.Hash
        $dupGroups[$h] = [pscustomobject]@{ Count = $c; TotalBytes = [int64]$_.TotalBytes }
    }
}

Write-Host 'Loading McNASBackup music/audio duplicate candidates...'
$candidateFiles = New-Object System.Collections.ArrayList
Import-Csv (Join-Path $ReportRoot "file_hashes_$HashStamp.csv") | ForEach-Object {
    $fp = Get-NormPath $_.FullPath
    if (-not $fp.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)) { return }
    if (Test-ExcludedWorkbench $fp) { return }
    $hash = Get-NormHash $_.Hash
    if (-not $dupGroups.ContainsKey($hash)) { return }
    $ext = $_.Extension.ToLowerInvariant()
    if ($audioExts -notcontains $ext) { return }
    [void]$candidateFiles.Add($_)
}
Write-Host "Candidate rows: $($candidateFiles.Count)"

$hashStats = @{}
foreach ($f in $candidateFiles) {
    $h = Get-NormHash $f.Hash
    if (-not $hashStats.ContainsKey($h)) {
        $dg = $dupGroups[$h]
        $hashStats[$h] = @{
            GroupCount = $dg.Count
            GroupTotalBytes = $dg.TotalBytes
            SizeEach = [int64]$f.SizeBytes
        }
    }
}

$inventory = New-Object System.Collections.ArrayList
$rowNum = 0
$total = $candidateFiles.Count
foreach ($f in $candidateFiles) {
    $rowNum++
    if ($rowNum % 2000 -eq 0) { Write-Host "  classify $rowNum / $total" }

    $full = Get-NormPath $f.FullPath
    $hash = Get-NormHash $f.Hash
    $fileName = $f.FileName
    $ext = $f.Extension.ToLowerInvariant()
    $rel = if ($full.Length -gt $targetRoot.Length) { $full.Substring($targetRoot.Length).TrimStart('\') } else { $fileName }
    $size = [int64]$f.SizeBytes
    $g = $hashStats[$hash]

    $blockers = New-Object System.Collections.ArrayList
    $hashStatus = 'NotChecked'
    if (-not $full.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)) { [void]$blockers.Add('OutsideTargetRoot') }
    if (Test-ExcludedWorkbench $full) { [void]$blockers.Add('UnderWorkbench') }
    if ($audioExts -notcontains $ext) { [void]$blockers.Add('ExtensionMismatch') }

    $exists = Test-Path -LiteralPath $full
    $isDir = $false
    if ($exists) { $isDir = Test-Path -LiteralPath $full -PathType Container }
    if (-not $exists) { [void]$blockers.Add('MissingFile') }
    if ($isDir) { [void]$blockers.Add('IsDirectory') }
    if ($null -eq $g -or $g.GroupCount -lt 2) { [void]$blockers.Add('DuplicateGroupUnclear') }

    if ($VerifyLiveHash -and $exists -and -not $isDir -and $blockers.Count -eq 0) {
        try {
            $liveHash = Get-NormHash (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
            if ($liveHash -ne $hash) { [void]$blockers.Add('HashMismatch'); $hashStatus = 'Mismatch' }
            else { $hashStatus = 'Verified' }
        }
        catch { [void]$blockers.Add('HashCheckFailed'); $hashStatus = 'CheckFailed' }
    }
    elseif ($exists -and -not $isDir) { $hashStatus = 'AssumedFromIndex' }

    $musicSig = Test-MusicSignal $full $fileName $ext
    $personalLib = Test-PersonalLibrarySignal $full $fileName
    $cacheSample = Test-CacheOrSampleSignal $full $fileName $size
    $carved = Test-CarvedAudioName $fileName

    $lane = 'MEDIUM_REVIEW_AUDIO_DUPLICATE'
    $subfolder = 'medium_review\media\music\mcnasbackup_unclear'
    $reason = 'Audio duplicate without clear personal-library or cache/sample signal; medium review.'

    if ($blockers.Count -gt 0) {
        $lane = 'BLOCKED_INVESTIGATE'
        $subfolder = 'investigate\media\music'
        $reason = ($blockers -join '; ')
    }
    elseif ($personalLib -or (Test-MatchPatterns ($full + ' ' + $fileName) $musicLibraryPatterns)) {
        $lane = 'HUMAN_REVIEW_MUSIC_DUPLICATE'
        $subfolder = 'human_review\media\music\mcnasbackup_duplicates'
        $reason = 'Personal music library, ripped/Google Play/Dropbox mirror, or named album/artist collection; hold for human review.'
    }
    elseif ($cacheSample -and -not $personalLib -and ($carved -or $size -lt 1000000)) {
        $lane = 'LOW_RISK_AUDIO_CACHE_OR_SAMPLE'
        $subfolder = 'high_confidence_junk\phase2_audio_cache_or_samples'
        $reason = 'Likely app sample, cache audio, or non-personal sound effect with no library signal.'
    }
    elseif ($carved) {
        $lane = 'MEDIUM_REVIEW_AUDIO_DUPLICATE'
        $reason = 'Carved generic audio filename; unclear content without preview.'
    }
    elseif (-not $personalLib -and -not (Test-MatchPatterns ($full + ' ' + $fileName) $musicLibraryPatterns)) {
        $lane = 'MEDIUM_REVIEW_AUDIO_DUPLICATE'
        $reason = 'Incomplete folder context or unclear duplicate without strong library signal.'
    }

    $reclaim = [int64]$g.SizeEach * ([int64]$g.GroupCount - 1)

    [void]$inventory.Add([pscustomobject]@{
        Hash = $hash
        ShortHash = Get-ShortHash $hash
        FullName = $full
        RelativePath = $rel
        FileName = $fileName
        ParentFolder = $f.ParentPath
        Extension = $ext
        SizeBytes = $f.SizeBytes
        LastWriteTime = $f.LastWriteTimeUtc
        GroupFileCount = $g.GroupCount
        GroupTotalBytes = $g.GroupTotalBytes
        ReclaimEstimateBytes = $reclaim
        SuggestedPolicyLane = $lane
        SuggestedDestinationSubfolder = $subfolder
        MusicSignal = $musicSig
        PersonalLibrarySignal = $personalLib
        CacheOrSampleSignal = $cacheSample
        ReviewReason = $reason
        SourceRoot = $targetRoot
        ExistsOnDisk = $exists
        HashCheckStatus = $hashStatus
    })
}

$csvOut = Join-Path $ReportRoot "phase2_mcnasbackup_music_duplicate_inventory_$OutputStamp.csv"
$summaryOut = Join-Path $ReportRoot "phase2_mcnasbackup_music_duplicate_summary_$OutputStamp.txt"
$inventory | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding utf8

$uniqueGroups = @($inventory | Group-Object Hash)
$byLane = $inventory | Group-Object SuggestedPolicyLane | ForEach-Object {
    [pscustomobject]@{
        Lane = $_.Name
        Files = $_.Count
        Bytes = ($_.Group | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
        Groups = ($_.Group | Group-Object Hash).Count
    }
} | Sort-Object Files -Descending

$reclaimEst = ($inventory | Group-Object Hash | ForEach-Object {
    $g = $_.Group[0]
    [int64]$g.SizeBytes * ([int64]$g.GroupFileCount - 1)
} | Measure-Object -Sum).Sum

$topGroups = $uniqueGroups | ForEach-Object {
    $g = $_.Group[0]
    [pscustomobject]@{
        Reclaim = $g.ReclaimEstimateBytes
        Count = $g.GroupFileCount
        SizeEach = [int64]$g.SizeBytes
        Lane = $g.SuggestedPolicyLane
        Ext = $g.Extension
        Example = $g.FileName
    }
} | Sort-Object Reclaim -Descending | Select-Object -First 50

$topFiles = $inventory | Sort-Object { [int64]$_.SizeBytes } -Descending | Select-Object -First 50 SizeBytes, SuggestedPolicyLane, Extension, FileName, RelativePath
$byExt = $inventory | Group-Object Extension | Sort-Object Count -Descending
$bySub = $inventory | Group-Object { Get-SourceSubfolder (Get-NormPath $_.FullName) } | Sort-Object Count -Descending | Select-Object -First 20

$humanExamples = $inventory | Where-Object SuggestedPolicyLane -eq 'HUMAN_REVIEW_MUSIC_DUPLICATE' | Sort-Object { [int64]$_.SizeBytes } -Descending | Select-Object -First 15 FileName, RelativePath, SizeBytes
$lowExamples = $inventory | Where-Object SuggestedPolicyLane -eq 'LOW_RISK_AUDIO_CACHE_OR_SAMPLE' | Select-Object -First 15 FileName, RelativePath, SizeBytes

$lines = @(
    'Phase 2 McNASBackup Music/Audio Duplicate Inventory Summary (Read-Only)'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "TargetRoot: $targetRoot"
    "Extensions: $($audioExts -join ', ')"
    "InventoryRows: $($inventory.Count)"
    "UniqueDuplicateGroups: $($uniqueGroups.Count)"
    "TotalBytes: $(($inventory | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum)"
    "ReclaimEstimateBytes: $reclaimEst"
    ''
    '=== COUNTS BY SUGGESTED POLICY LANE ==='
)
$lines += $byLane | ForEach-Object { "$($_.Lane): files=$($_.Files) bytes=$($_.Bytes) groups=$($_.Groups)" }
$lines += ''
$lines += '=== EXTENSION BREAKDOWN ==='
$lines += $byExt | ForEach-Object { "$($_.Name)`t$($_.Count)" }
$lines += ''
$lines += '=== SOURCE SUBFOLDER BREAKDOWN (top 20) ==='
$lines += $bySub | ForEach-Object { "$($_.Name)`t$($_.Count)" }
$lines += ''
$lines += '=== TOP 50 LARGEST GROUPS (reclaim estimate) ==='
$lines += $topGroups | ForEach-Object { "$($_.Reclaim)`t$($_.Count)`t$($_.SizeEach)`t$($_.Lane)`t$($_.Ext)`t$($_.Example)" }
$lines += ''
$lines += '=== TOP 50 LARGEST FILES ==='
$lines += $topFiles | ForEach-Object { "$($_.SizeBytes)`t$($_.SuggestedPolicyLane)`t$($_.Extension)`t$($_.FileName)`t$($_.RelativePath)" }
$lines += ''
$lines += '=== LIKELY MUSIC-LIBRARY DUPLICATE EXAMPLES ==='
$lines += $humanExamples | ForEach-Object { "$($_.SizeBytes)`t$($_.FileName)`t$($_.RelativePath)" }
$lines += ''
$lines += '=== LOW-RISK CACHE/SAMPLE EXAMPLES ==='
if (@($lowExamples).Count -eq 0) { $lines += 'None classified' }
else { $lines += $lowExamples | ForEach-Object { "$($_.SizeBytes)`t$($_.FileName)`t$($_.RelativePath)" } }
$lines += ''
$lines += '=== BLOCKERS ==='
$blocked = @($inventory | Where-Object SuggestedPolicyLane -eq 'BLOCKED_INVESTIGATE')
$lines += "BlockedInvestigateFiles: $($blocked.Count)"
if ($blocked.Count -gt 0) {
    $blocked | Group-Object ReviewReason | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
        $lines += "  $($_.Name): $($_.Count)"
    }
}
$lines += ''
$lines += '=== HUMAN-REVIEW MUSIC CAUTIONS ==='
$humanFiles = @($inventory | Where-Object SuggestedPolicyLane -eq 'HUMAN_REVIEW_MUSIC_DUPLICATE').Count
$humanGroups = @($inventory | Where-Object SuggestedPolicyLane -eq 'HUMAN_REVIEW_MUSIC_DUPLICATE' | Group-Object Hash).Count
$lines += "HumanReviewMusicFiles: $humanFiles"
$lines += "HumanReviewMusicGroups: $humanGroups"
$lines += 'Large personal-library duplicate volume; keeper-policy sample required before any move-extras plan.'
$lines += 'Google Play Music, Dropbox mirrors, and carved scratch copies may share hashes across library trees.'
$lines += ''
$lines += '=== RECOMMENDED NEXT ACTION ==='
if ($humanGroups -gt 500) {
    $lines += 'RECOMMENDATION: A - Build keeper-policy sample for music duplicates first.'
    $lines += 'Then C - sample-review before any human-review move-extras plan (B).'
    $lines += 'Do not skip to move plan; volume too large for blind extras move.'
}
elseif ($humanFiles -gt 500) {
    $lines += 'RECOMMENDATION: A - Build keeper-policy sample; then C - sample-review first.'
}
else {
    $lines += 'RECOMMENDATION: A - Build keeper-policy sample for music duplicates.'
}
$lines += 'D - HOLD all lanes until keeper policy and sample review complete.'
$lines += 'No hard delete. No move plan in this task. No -Execute.'
$lines += ''
$lines += 'WARNING: Read-only inventory. No move, copy, delete, rename, cleanup, or move plan.'
$lines | Set-Content -LiteralPath $summaryOut -Encoding utf8

Write-Host "Inventory: $($inventory.Count) rows -> $csvOut"
Write-Host "Summary: $summaryOut"
$byLane | Format-Table -AutoSize
