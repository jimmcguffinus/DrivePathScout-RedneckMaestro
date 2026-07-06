[CmdletBinding()]
param(
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [string]$InventoryStamp = '20260704',
    [string]$OutputStamp = '20260704'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    try { return [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { return $p.Trim() }
}
function Get-NormHash([string]$h) { $h.Trim().ToUpperInvariant() }
function Get-ShortHash([string]$h) { $n = Get-NormHash $h; if ($n.Length -ge 8) { $n.Substring(0, 8) } else { $n } }

function Test-CarvedVideoName([string]$name) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($name).ToLowerInvariant()
    return ($stem -match '^file\d+$')
}

function Get-KeeperScore([string]$fullPath, [string]$fileName) {
    $path = $fullPath.ToLowerInvariant()
    $name = $fileName.ToLowerInvariant()
    $score = 0
    $reasons = New-Object System.Collections.Generic.List[string]

    if ($path -match 'mchomemovies') { $score += 120; [void]$reasons.Add('McHomeMovies') }
    if ($path -match 'camera uploads') { $score += 110; [void]$reasons.Add('CameraUploads') }
    if ($path -match '\\videos\\') { $score += 90; [void]$reasons.Add('VideosFolder') }
    if ($path -match 'mcphotos') { $score += 80; [void]$reasons.Add('McPhotos') }
    if ($path -match '\\pictures\\') { $score += 70; [void]$reasons.Add('PicturesFolder') }
    if ($path -match 'movies\\|movie file|quicktime movie|avi clip|windows media video') { $score += 60; [void]$reasons.Add('MovieFolder') }
    if ($path -match 'swim|banquet|birthday|holiday|wedding|trip|vacation|easter|fair|sixflags|tortoise') { $score += 50; [void]$reasons.Add('EventFolder') }

    if ($name -match '^\d{4}-\d{2}-\d{2}') { $score += 100; [void]$reasons.Add('DateFilename') }
    elseif ($name -match '^20\d{2}') { $score += 70; [void]$reasons.Add('YearFilename') }
    if ($name -match '^vid[_\d]|^mvi[_\d]') { $score += 80; [void]$reasons.Add('CameraVidPrefix') }
    if ($name -match '^orig_') { $score += 75; [void]$reasons.Add('OrigPrefix') }
    if ($name -match 'x264|_001\.|camera') { $score += 40; [void]$reasons.Add('CameraHint') }
    if ($name -match '^[a-z].*[a-z]$' -and -not (Test-CarvedVideoName $fileName) -and $name -notmatch '^file\d') {
        $score += 25; [void]$reasons.Add('MeaningfulName')
    }

    if ($path -match 'mcjunk|test_rename\\recovered') { $score -= 120; [void]$reasons.Add('McJunkPenalty') }
    if ($path -match '\\scratch\\|temp\\|tmp\\') { $score -= 90; [void]$reasons.Add('ScratchTempPenalty') }
    if ($path -match 'mcdropbox\\dropbox\\drobo_bkup') { $score -= 15; [void]$reasons.Add('NestedDropboxMirror') }
    if (Test-CarvedVideoName $fileName) { $score -= 100; [void]$reasons.Add('CarvedFileNamePenalty') }
    if ($name -match 'dummy|sample|tutorial|logo|intro|test') { $score -= 80; [void]$reasons.Add('SampleNamePenalty') }

    return [pscustomobject]@{ Score = $score; Reasons = ($reasons -join ';') }
}

function Get-ProposedFutureLane(
    [string]$inventoryLane,
    [bool]$needsSpotCheck,
    [int]$keeperScore,
    [bool]$allCarved
) {
    if ($inventoryLane -eq 'BLOCKED_INVESTIGATE') { return 'BLOCKED_INVESTIGATE' }
    if ($inventoryLane -eq 'LOW_RISK_VIDEO_CACHE_OR_SAMPLE') { return 'LOW_RISK_HOLD' }
    if ($inventoryLane -eq 'MEDIUM_REVIEW_VIDEO_DUPLICATE') { return 'MEDIUM_REVIEW_SAMPLE_FIRST' }
    if ($needsSpotCheck -or $allCarved -or $keeperScore -lt 20) { return 'HUMAN_REVIEW_SAMPLE_FIRST' }
    return 'HUMAN_REVIEW_MOVE_EXTRAS_READY'
}

$inventoryPath = Join-Path $ReportRoot "phase2_mcnasbackup_video_duplicate_inventory_$InventoryStamp.csv"
$inventory = Import-Csv -LiteralPath $inventoryPath
Write-Host "Loaded $($inventory.Count) inventory rows"

$groups = $inventory | Group-Object { Get-NormHash $_.Hash }
$sampleRows = New-Object System.Collections.ArrayList

foreach ($g in $groups) {
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
    $allCarved = (@($rows | Where-Object { -not (Test-CarvedVideoName $_.FileName) }).Count -eq 0)
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

    [void]$sampleRows.Add([pscustomobject]@{
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
        PersonalSignal = ($best.Row.PersonalSignal -eq 'True')
        ExistsOnDisk = ($best.Row.ExistsOnDisk -eq 'True')
    })
}

$csvOut = Join-Path $ReportRoot "phase2_mcnasbackup_video_keeper_policy_sample_$OutputStamp.csv"
$summaryOut = Join-Path $ReportRoot "phase2_mcnasbackup_video_keeper_policy_sample_summary_$OutputStamp.txt"
$sampleRows | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding utf8

$byLane = $sampleRows | Group-Object ProposedFutureLane | ForEach-Object {
    [pscustomobject]@{
        Lane = $_.Name
        Groups = $_.Count
        ExtrasFiles = ($_.Group | ForEach-Object { [int]$_.DuplicateExtrasCount } | Measure-Object -Sum).Sum
        ExtrasBytes = ($_.Group | ForEach-Object { [int64]$_.DuplicateExtrasBytes } | Measure-Object -Sum).Sum
    }
} | Sort-Object Groups -Descending

$spotCheck = @($sampleRows | Where-Object NeedsHumanSpotCheck -eq $true)
$moveReady = @($sampleRows | Where-Object ProposedFutureLane -eq 'HUMAN_REVIEW_MOVE_EXTRAS_READY')

$topMoveReady = $moveReady | Sort-Object { [int64]$_.DuplicateExtrasBytes } -Descending | Select-Object -First 25
$topSpotCheck = $spotCheck | Sort-Object { [int64]$_.DuplicateExtrasBytes } -Descending | Select-Object -First 25

$lines = @(
    'Phase 2 McNASBackup Video Keeper Policy Sample (Read-Only)'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "SourceInventory: $inventoryPath"
    "HashGroups: $($sampleRows.Count)"
    "InventoryRows: $($inventory.Count)"
    "TotalDuplicateExtrasBytes: $(($sampleRows | ForEach-Object { [int64]$_.DuplicateExtrasBytes } | Measure-Object -Sum).Sum)"
  ''
    '=== COUNTS BY PROPOSED FUTURE LANE ==='
)
$lines += $byLane | ForEach-Object { "$($_.Lane): groups=$($_.Groups) extrasFiles=$($_.ExtrasFiles) extrasBytes=$($_.ExtrasBytes)" }
$lines += ''
$lines += "NeedsHumanSpotCheck groups: $($spotCheck.Count)"
$lines += "HUMAN_REVIEW_MOVE_EXTRAS_READY groups: $($moveReady.Count)"
$lines += ''
$lines += '=== TOP MOVE-EXTRAS-READY GROUPS ==='
$topMoveReady | ForEach-Object {
    $lines += "  $($_.DuplicateExtrasBytes)`t$($_.GroupFileCount)`t$($_.Extension)`t$($_.CandidateKeeperFileName)`t$($_.CandidateKeeperPath)"
}
$lines += ''
$lines += '=== TOP HUMAN-SPOTCHECK GROUPS ==='
$topSpotCheck | ForEach-Object {
    $lines += "  $($_.DuplicateExtrasBytes)`t$($_.GroupFileCount)`t$($_.Extension)`t$($_.CandidateKeeperFileName)`t$($_.KeeperSelectionReason)"
}
$lines += ''
$lines += '=== KEEPER POLICY CAUTIONS ==='
$lines += '- Carved file### groups may be personal content recovered under McJunk; spot-check before moving extras.'
$lines += '- Camera Uploads / McHomeMovies keepers are preferred but nested Dropbox mirrors may still duplicate.'
$lines += '- MOVE_EXTRAS_READY is policy recommendation only; no move plan created in this task.'
$lines += ''
$lines += '=== RECOMMENDED NEXT ACTION ==='
if ($spotCheck.Count -gt ($sampleRows.Count * 0.3)) {
    $lines += 'RECOMMENDATION: Sample-review top HUMAN_SPOTCHECK groups before any human-review move plan.'
    $lines += "Start with $($moveReady.Count) MOVE_EXTRAS_READY groups after validating carved-vs-personal edge cases."
} else {
    $lines += 'RECOMMENDATION: Review MOVE_EXTRAS_READY groups; build human-review move plan for confirmed extras only after spot-check sample.'
}
$lines += 'No hard delete. No move plan. No -Execute.'
$lines += ''
$lines += 'WARNING: Read-only keeper-policy sample. No move, copy, delete, rename, cleanup, or move plan.'
$lines | Set-Content -LiteralPath $summaryOut -Encoding utf8

Write-Host "Keeper sample: $($sampleRows.Count) groups -> $csvOut"
Write-Host "Summary: $summaryOut"
$byLane | Format-Table -AutoSize
