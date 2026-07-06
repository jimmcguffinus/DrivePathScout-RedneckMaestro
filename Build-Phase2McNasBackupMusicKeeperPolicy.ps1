[CmdletBinding()]
param(
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [string]$InventoryStamp = '20260704',
    [string]$OutputStamp = '20260704'
)

# Phase 2 McNASBackup music keeper-policy report (read-only)
# No move, copy, delete, rename, cleanup, or move plan.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    try { return [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { return $p.Trim() }
}
function Get-NormHash([string]$h) { $h.Trim().ToUpperInvariant() }
function Get-ShortHash([string]$h) { $n = Get-NormHash $h; if ($n.Length -ge 8) { $n.Substring(0, 8) } else { $n } }

function Test-CarvedAudioName([string]$name) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($name).ToLowerInvariant()
    return ($stem -match '^file\d+$')
}

function Get-KeeperScore([string]$fullPath, [string]$fileName) {
    $path = $fullPath.ToLowerInvariant()
    $name = $fileName.ToLowerInvariant()
    $score = 0
    $reasons = New-Object System.Collections.Generic.List[string]

    if ($path -match 'google play music|\\play music\\|play music') { $score += 130; [void]$reasons.Add('GooglePlayMusic') }
    if ($path -match '\\itunes\\|itunes music|apple music') { $score += 125; [void]$reasons.Add('iTunesLibrary') }
    if ($path -match '\\music\\|\\musics\\|\\my music\\') { $score += 110; [void]$reasons.Add('MusicFolder') }
    if ($path -match 'amazon music|spotify|ripped|rip\\') { $score += 100; [void]$reasons.Add('RippedOrStreaming') }
    if ($path -match '\\album\\|\\artist\\|soundtrack|playlist') { $score += 95; [void]$reasons.Add('AlbumArtistFolder') }
    if ($path -match 'jenni\.music|jenni\\music|mobilemom') { $score += 90; [void]$reasons.Add('JenniMusic') }
    if ($path -match 'mcphotos\\music|mcphotos.*music') { $score += 85; [void]$reasons.Add('McPhotosMusic') }
    if ($path -match 'trainsignal|powershell.*essentials|course|lesson\d|tutorial') { $score += 80; [void]$reasons.Add('TrainingCourseFolder') }
    if ($path -match 'podcast|audiobook|audio book') { $score += 75; [void]$reasons.Add('PodcastAudiobook') }
    if ($path -match 'collection\\|library\\|favorites') { $score += 70; [void]$reasons.Add('LibraryCollection') }
    if ($path -match 'mcpsts\\.*homedirs|homedirs\\') { $score += 65; [void]$reasons.Add('HomeDirMusic') }

    if ($name -match '^\d{2} - |^\d{2}\.\s|track \d{1,2}|disc \d') { $score += 90; [void]$reasons.Add('TrackNumberFilename') }
    if ($name -match ' - .+\.(mp3|m4a|wma|wav|flac|aac|ogg)$') { $score += 85; [void]$reasons.Add('ArtistSongFilename') }
    if ($name -match '^\d{4}-\d{2}-\d{2}') { $score += 70; [void]$reasons.Add('DateFilename') }
    if ($name -match '^[a-z0-9].*[a-z0-9]$' -and -not (Test-CarvedAudioName $fileName) -and $name -notmatch '^file\d') {
        $score += 30; [void]$reasons.Add('MeaningfulName')
    }

    if ($path -match 'mcjunk|test_rename\\recovered') { $score -= 120; [void]$reasons.Add('McJunkPenalty') }
    if ($path -match '\\scratch\\|temp\\|tmp\\|un-named') { $score -= 100; [void]$reasons.Add('ScratchTempPenalty') }
    if ($path -match 'mcdropbox\\dropbox\\drobo_bkup') { $score -= 40; [void]$reasons.Add('NestedDropboxMirror') }
    if ($path -match 'drobo_bkup\\mcdropbox\\dropbox\\drobo_bkup') { $score -= 25; [void]$reasons.Add('DoubleMirrorPenalty') }
    if (Test-CarvedAudioName $fileName) { $score -= 110; [void]$reasons.Add('CarvedFileNamePenalty') }
    if ($name -match 'dummy|sample|beep|click|sfx|silence|echo|test tone') { $score -= 90; [void]$reasons.Add('SampleNamePenalty') }
    if ($path -match 'skype\.calls|callnote') { $score -= 50; [void]$reasons.Add('CallRecordingPenalty') }

    return [pscustomobject]@{ Score = $score; Reasons = ($reasons -join ';') }
}

function Get-ProposedFutureLane(
    [string]$inventoryLane,
    [bool]$needsSpotCheck,
    [int]$keeperScore,
    [bool]$allCarved
) {
    if ($inventoryLane -eq 'BLOCKED_INVESTIGATE') { return 'BLOCKED_INVESTIGATE' }
    if ($inventoryLane -eq 'LOW_RISK_AUDIO_CACHE_OR_SAMPLE') { return 'LOW_RISK_HOLD' }
    if ($inventoryLane -eq 'MEDIUM_REVIEW_AUDIO_DUPLICATE') {
        if ($needsSpotCheck -or $allCarved -or $keeperScore -lt 25) { return 'MEDIUM_REVIEW_SAMPLE_FIRST' }
        return 'MEDIUM_REVIEW_MOVE_EXTRAS_READY'
    }
    if ($inventoryLane -eq 'HUMAN_REVIEW_MUSIC_DUPLICATE') {
        if ($needsSpotCheck -or $allCarved -or $keeperScore -lt 20) { return 'HUMAN_REVIEW_SAMPLE_FIRST' }
        return 'HUMAN_REVIEW_MOVE_EXTRAS_READY'
    }
    return 'BLOCKED_INVESTIGATE'
}

$inventoryPath = Join-Path $ReportRoot "phase2_mcnasbackup_music_duplicate_inventory_$InventoryStamp.csv"
$inventory = Import-Csv -LiteralPath $inventoryPath
Write-Host "Loaded $($inventory.Count) inventory rows"

$groups = $inventory | Group-Object { Get-NormHash $_.Hash }
$policyRows = New-Object System.Collections.ArrayList
$gi = 0

foreach ($g in $groups) {
    $gi++
    if ($gi % 500 -eq 0) { Write-Host "  policy $gi / $($groups.Count)" }

    $rows = @($g.Group)
    $hash = Get-NormHash $g.Name
    $scored = $rows | ForEach-Object {
        $s = Get-KeeperScore (Get-NormPath $_.FullName) $_.FileName
        [pscustomobject]@{
            Row = $_
            Score = $s.Score
            Reasons = $s.Reasons
        }
    } | Sort-Object @{ Expression = { $_.Score }; Descending = $true }, @{ Expression = { Get-NormPath $_.Row.FullName } }

    $best = $scored[0]
    $secondScore = if ($scored.Count -gt 1) { $scored[1].Score } else { $scored[0].Score }
    $allCarved = (@($rows | Where-Object { -not (Test-CarvedAudioName $_.FileName) }).Count -eq 0)
    $ambiguous = ($scored.Count -gt 1) -and (($best.Score - $secondScore) -lt 15)
    $needsSpot = $allCarved -or $ambiguous -or ($best.Score -lt 0)

    $keeperPath = Get-NormPath $best.Row.FullName
    $keeperFile = $best.Row.FileName
    $sizeEach = [int64]$best.Row.SizeBytes
    $groupCount = [int]$best.Row.GroupFileCount
    $extrasCount = [Math]::Max(0, $groupCount - 1)
    $extrasBytes = $sizeEach * $extrasCount
    $lane = $best.Row.SuggestedPolicyLane.Trim()
    $futureLane = Get-ProposedFutureLane $lane $needsSpot $best.Score $allCarved

    $extraPaths = @($scored | Where-Object { (Get-NormPath $_.Row.FullName) -ne $keeperPath } |
        Select-Object -First 5 | ForEach-Object { Get-NormPath $_.Row.FullName })
    $keeperReason = if ($best.Reasons) { $best.Reasons } else { 'DefaultFirstSorted' }
    if ($allCarved) { $keeperReason += ';AllCopiesCarvedGeneric' }
    if ($ambiguous) { $keeperReason += ';AmbiguousKeeperTie' }

    [void]$policyRows.Add([pscustomobject]@{
        Hash = $hash
        ShortHash = Get-ShortHash $hash
        CandidateKeeperPath = $keeperPath
        CandidateKeeperFileName = $keeperFile
        Extension = $best.Row.Extension.ToLowerInvariant()
        SizeBytesEach = $sizeEach
        GroupFileCount = $groupCount
        DuplicateExtrasCount = $extrasCount
        DuplicateExtrasBytes = $extrasBytes
        KeeperScore = $best.Score
        SuggestedPolicyLane = $lane
        ProposedFutureLane = $futureLane
        NeedsHumanSpotCheck = $needsSpot
        AllCopiesCarvedOrGeneric = $allCarved
        KeeperSelectionReason = $keeperReason
        ExampleExtraPaths = ($extraPaths -join ' | ')
        PersonalLibrarySignal = ($best.Row.PersonalLibrarySignal -eq 'True')
        MusicSignal = ($best.Row.MusicSignal -eq 'True')
        ExistsOnDisk = ($best.Row.ExistsOnDisk -eq 'True')
    })
}

$csvOut = Join-Path $ReportRoot "phase2_mcnasbackup_music_keeper_policy_$OutputStamp.csv"
$summaryOut = Join-Path $ReportRoot "phase2_mcnasbackup_music_keeper_policy_summary_$OutputStamp.txt"
$policyRows | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding utf8

$byLane = $policyRows | Group-Object ProposedFutureLane | ForEach-Object {
    [pscustomobject]@{
        Lane = $_.Name
        Groups = $_.Count
        ExtrasFiles = ($_.Group | ForEach-Object { [int]$_.DuplicateExtrasCount } | Measure-Object -Sum).Sum
        ExtrasBytes = ($_.Group | ForEach-Object { [int64]$_.DuplicateExtrasBytes } | Measure-Object -Sum).Sum
    }
} | Sort-Object Groups -Descending

$humanMoveReady = @($policyRows | Where-Object ProposedFutureLane -eq 'HUMAN_REVIEW_MOVE_EXTRAS_READY')
$mediumMoveReady = @($policyRows | Where-Object ProposedFutureLane -eq 'MEDIUM_REVIEW_MOVE_EXTRAS_READY')
$sampleFirst = @($policyRows | Where-Object {
    $_.ProposedFutureLane -in @('HUMAN_REVIEW_SAMPLE_FIRST', 'MEDIUM_REVIEW_SAMPLE_FIRST')
})
$spotCheck = @($policyRows | Where-Object NeedsHumanSpotCheck -eq $true)

$topHumanMove = $humanMoveReady | Sort-Object { [int64]$_.DuplicateExtrasBytes } -Descending | Select-Object -First 25
$topMediumMove = $mediumMoveReady | Sort-Object { [int64]$_.DuplicateExtrasBytes } -Descending | Select-Object -First 25
$topSampleFirst = $sampleFirst | Sort-Object { [int64]$_.DuplicateExtrasBytes } -Descending | Select-Object -First 25

$lines = @(
    'Phase 2 McNASBackup Music Keeper Policy (Read-Only)'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "SourceInventory: $inventoryPath"
    "HashGroups: $($policyRows.Count)"
    "InventoryRows: $($inventory.Count)"
    "TotalDuplicateExtrasBytes: $(($policyRows | ForEach-Object { [int64]$_.DuplicateExtrasBytes } | Measure-Object -Sum).Sum)"
    ''
    '=== COUNTS BY PROPOSED FUTURE LANE ==='
)
$lines += $byLane | ForEach-Object { "$($_.Lane): groups=$($_.Groups) extrasFiles=$($_.ExtrasFiles) extrasBytes=$($_.ExtrasBytes)" }
$lines += ''
$lines += "NeedsHumanSpotCheck groups: $($spotCheck.Count)"
$lines += "HUMAN_REVIEW_MOVE_EXTRAS_READY groups: $($humanMoveReady.Count)"
$lines += "MEDIUM_REVIEW_MOVE_EXTRAS_READY groups: $($mediumMoveReady.Count)"
$lines += ''
$lines += '=== TOP HUMAN MOVE-EXTRAS-READY GROUPS ==='
$topHumanMove | ForEach-Object {
    $lines += "  $($_.DuplicateExtrasBytes)`t$($_.GroupFileCount)`t$($_.Extension)`t$($_.CandidateKeeperFileName)`t$($_.CandidateKeeperPath)"
}
$lines += ''
$lines += '=== TOP MEDIUM MOVE-EXTRAS-READY GROUPS ==='
$topMediumMove | ForEach-Object {
    $lines += "  $($_.DuplicateExtrasBytes)`t$($_.GroupFileCount)`t$($_.Extension)`t$($_.CandidateKeeperFileName)`t$($_.CandidateKeeperPath)"
}
$lines += ''
$lines += '=== TOP SAMPLE-FIRST GROUPS ==='
$topSampleFirst | ForEach-Object {
    $lines += "  $($_.ProposedFutureLane)`t$($_.DuplicateExtrasBytes)`t$($_.GroupFileCount)`t$($_.CandidateKeeperFileName)`t$($_.KeeperSelectionReason)"
}
$lines += ''
$lines += '=== KEEPER POLICY CAUTIONS ==='
$lines += '- Dropbox mirror trees dominate extras; keeper scoring penalizes nested McDropBox paths.'
$lines += '- TrainSignal/PowerShell training MP3s may be medium-review MOVE_EXTRAS_READY but deserve spot-check.'
$lines += '- Carved file### groups and Skype call recordings need human validation before extras move.'
$lines += '- Human music volume (11,900 files) far exceeds video; do not skip sample-review.'
$lines += '- MOVE_EXTRAS_READY is policy recommendation only; no move plan created in this task.'
$lines += ''
$lines += '=== RECOMMENDED NEXT ACTION ==='
if ($spotCheck.Count -gt ($policyRows.Count * 0.25)) {
    $lines += 'RECOMMENDATION: Sample-review top SAMPLE_FIRST groups before any move-extras plan.'
    $lines += "Human MOVE_EXTRAS_READY: $($humanMoveReady.Count) groups; Medium MOVE_EXTRAS_READY: $($mediumMoveReady.Count) groups - validate carved-vs-library edge cases first."
} else {
    $lines += 'RECOMMENDATION: Sample-review largest SAMPLE_FIRST groups; then consider separate human vs medium move-extras planners.'
}
$lines += 'No hard delete. No move plan. No -Execute.'
$lines += ''
$lines += 'WARNING: Read-only keeper policy. No move, copy, delete, rename, cleanup, or move plan.'
$lines | Set-Content -LiteralPath $summaryOut -Encoding utf8

Write-Host "Keeper policy: $($policyRows.Count) groups -> $csvOut"
Write-Host "Summary: $summaryOut"
$byLane | Format-Table -AutoSize
