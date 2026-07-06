[CmdletBinding()]
param(
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [string]$InventoryStamp = '20260704',
    [string]$RefinementStamp = '20260704',
    [string]$OutputStamp = '20260704',
    [string]$TargetRoot = 'I:\recover\McNASBackup'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    try { return [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { return $p.Trim() }
}
function Get-NormHash([string]$h) { $h.Trim().ToUpperInvariant() }
function Get-ShortHash([string]$h) { $n = Get-NormHash $h; if ($n.Length -ge 8) { $n.Substring(0, 8) } else { $n } }

$targetRoot = Get-NormPath $TargetRoot

function Test-MatchPatterns([string]$text, [string[]]$patterns) {
    $t = $text.ToLowerInvariant()
    foreach ($p in $patterns) { if ($t -match $p) { return $true } }
    return $false
}

$suspicionKeywords = @(
    'personal','legal','medical','tax','financial','bank','real.?estate','real estate','resume','identity',
    'family','school','claim','mail\.google','gmail','outlook','\.pst','export','mbox','inbox',
    'project','customer','invoice','contract','appraisal','mortgage','insurance','lawsuit','court',
    'photo','video','music','jenni','jim\.','mcguffin','closing','buyer','seller','w-2','w2','1099',
    'passport','ssn','social.security','deed','offer','addendum','deposit','statement','payroll',
    'diagnosis','prescription','doctor','hospital','transcript','diploma','university','college',
    'driver.?lic','credit.?report','checking','savings','loan','confidential','nda','signature'
)

function Get-SourceSubfolder([string]$fullPath) {
    $rel = if ($fullPath.Length -gt $targetRoot.Length) { $fullPath.Substring($targetRoot.Length).TrimStart('\') } else { '' }
    if ([string]::IsNullOrWhiteSpace($rel)) { return '(root)' }
    $parts = $rel -split '\\'
    if ($parts.Count -ge 2) { return ($parts[0..1] -join '\') }
    return $parts[0]
}

function Test-SuspicionSignal([string]$fullPath, [string]$fileName) {
    $blob = ($fullPath + ' ' + $fileName).ToLowerInvariant()
    return Test-MatchPatterns $blob $suspicionKeywords
}

function Get-SpotCheckDecision(
    [string]$fullPath,
    [string]$fileName,
    [string]$ext,
    [string]$lane,
    [bool]$sharedHuman,
    [bool]$suspicion,
    [string[]]$blockers
) {
    if ($blockers.Count -gt 0) {
        return @{
            Decision = 'BLOCK_INVESTIGATE'
            FinalLane = 'investigate\web_assets'
            Reason = ($blockers -join '; ')
            Signal = 'Blocked'
        }
    }
    if ($sharedHuman -or $suspicion) {
        $parts = @()
        if ($sharedHuman) { $parts += 'SharedHashWithHumanReviewLane' }
        if ($suspicion) { $parts += 'SuspiciousKeywordInPathOrName' }
        return @{
            Decision = 'ESCALATE_TO_HUMAN_REVIEW'
            FinalLane = 'human_review\documents'
            Reason = 'Tier1 spot-check escalation: ' + ($parts -join '; ')
            Signal = ($parts -join '; ')
        }
    }
    if ($ext -in @('.doc','.docx','.xls','.xlsx','.ppt','.pptx','.rtf','.pdf')) {
        return @{
            Decision = 'ESCALATE_TO_MEDIUM_REVIEW'
            FinalLane = 'medium_review\web_assets\unclear'
            Reason = 'Document-type extension in Tier1; medium review before move.'
            Signal = 'DocumentExtension'
        }
    }
    if ($lane -eq 'TIER1_TOOL_CACHE_ARCHIVES') {
        return @{
            Decision = 'KEEP_TIER1_MOVE_CANDIDATE'
            FinalLane = 'high_confidence_junk\phase2_web_assets\tool_cache_archives'
            Reason = 'Tool/cache archive duplicate; no personal or human-review hash signal.'
            Signal = ''
        }
    }
    return @{
        Decision = 'KEEP_TIER1_MOVE_CANDIDATE'
        FinalLane = 'high_confidence_junk\phase2_web_assets\obvious_web_junk'
        Reason = 'Obvious web/cache image asset; no escalation signal.'
        Signal = ''
    }
}

$refinementPath = Join-Path $ReportRoot "phase2_web_assets_lowrisk_refinement_$RefinementStamp.csv"
$inventoryPath = Join-Path $ReportRoot "phase2_web_assets_inventory_$InventoryStamp.csv"

Write-Host "Loading refinement from $refinementPath"
$refined = Import-Csv -LiteralPath $refinementPath
$tier1 = @($refined | Where-Object RefinedPolicyLane -in @('TIER1_OBVIOUS_WEB_JUNK','TIER1_TOOL_CACHE_ARCHIVES'))
Write-Host "Tier1 rows total: $($tier1.Count)"

Write-Host "Loading inventory for human-review hash cross-check..."
$inventory = Import-Csv -LiteralPath $inventoryPath
$humanHashes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$inventory | Where-Object SuggestedPolicyLane -in @('HUMAN_REVIEW_DOCUMENT','HUMAN_REVIEW_ESCALATED') | ForEach-Object {
    [void]$humanHashes.Add((Get-NormHash $_.Hash))
}
$refinedHumanEsc = @($refined | Where-Object RefinedPolicyLane -eq 'HUMAN_REVIEW_ESCALATED')
$refinedHumanEsc | ForEach-Object { [void]$humanHashes.Add((Get-NormHash $_.Hash)) }

$selected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$spotRows = New-Object System.Collections.ArrayList

function Add-SpotRow([object]$row, [string]$reason) {
    $key = Get-NormPath $row.FullName
    if ($selected.Contains($key)) { return }
    [void]$selected.Add($key)
    [void]$spotRows.Add([pscustomobject]@{ Row = $row; SelectionReason = $reason })
}

# Top 50 largest Tier1 files
$tier1 | Sort-Object { [int64]$_.SizeBytes } -Descending | Select-Object -First 50 | ForEach-Object {
    Add-SpotRow $_ 'Top50LargestFile'
}

# Top 50 largest Tier1 hash groups (by reclaim)
$tier1 | Group-Object Hash | ForEach-Object {
    $g = $_.Group[0]
    [pscustomobject]@{
        Reclaim = [int64]$g.ReclaimEstimateBytes
        Row = $g
    }
} | Sort-Object Reclaim -Descending | Select-Object -First 50 | ForEach-Object {
    Add-SpotRow $_.Row 'Top50LargestGroup'
}

# All TIER1_TOOL_CACHE_ARCHIVES
$tier1 | Where-Object RefinedPolicyLane -eq 'TIER1_TOOL_CACHE_ARCHIVES' | ForEach-Object {
    Add-SpotRow $_ 'AllToolCacheArchives'
}

# Shared hash with human review
$tier1 | Where-Object { $humanHashes.Contains((Get-NormHash $_.Hash)) } | ForEach-Object {
    Add-SpotRow $_ 'SharedHashWithHumanReview'
}

# Suspicious keyword rows
$tier1 | Where-Object { Test-SuspicionSignal $_.FullName $_.FileName } | ForEach-Object {
    Add-SpotRow $_ 'SuspiciousKeyword'
}

# Representative 100 TIER1_OBVIOUS_WEB_JUNK across extensions and source folders
$junkOnly = @($tier1 | Where-Object RefinedPolicyLane -eq 'TIER1_OBVIOUS_WEB_JUNK')
$junkBuckets = $junkOnly | ForEach-Object {
    [pscustomobject]@{
        Row = $_
        Bucket = ($_.Extension + '|' + (Get-SourceSubfolder (Get-NormPath $_.FullName)))
    }
} | Group-Object Bucket

$repTarget = 100
$repAdded = 0
$perBucket = [Math]::Max(1, [Math]::Ceiling($repTarget / [Math]::Max(1, $junkBuckets.Count)))
foreach ($bucket in ($junkBuckets | Sort-Object Count -Descending)) {
    $take = [Math]::Min($perBucket, $bucket.Group.Count)
    $bucket.Group | Select-Object -First $take | ForEach-Object {
        if ($repAdded -ge $repTarget) { return }
        $before = $selected.Count
        Add-SpotRow $_.Row "RepresentativeWebJunk:$($bucket.Name)"
        if ($selected.Count -gt $before) { $repAdded++ }
    }
}
# Fill remaining representative slots if under 100
if ($repAdded -lt $repTarget) {
    $junkOnly | Where-Object { -not $selected.Contains((Get-NormPath $_.FullName)) } |
        Select-Object -First ($repTarget - $repAdded) | ForEach-Object {
            Add-SpotRow $_ 'RepresentativeWebJunk:Fill'
        }
}

Write-Host "Spot-check selection: $($spotRows.Count) unique rows"

$results = New-Object System.Collections.ArrayList
foreach ($item in $spotRows) {
    $row = $item.Row
    $full = Get-NormPath $row.FullName
    $hash = Get-NormHash $row.Hash
    $fileName = $row.FileName
    $ext = $row.Extension.ToLowerInvariant()
    $lane = $row.RefinedPolicyLane

    $blockers = New-Object System.Collections.ArrayList
    if (-not $full.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)) { [void]$blockers.Add('OutsideTargetRoot') }
    if (-not (Test-Path -LiteralPath $full)) { [void]$blockers.Add('MissingFile') }

    $sharedHuman = $humanHashes.Contains($hash)
    $suspicion = Test-SuspicionSignal $full $fileName
    $d = Get-SpotCheckDecision $full $fileName $ext $lane $sharedHuman $suspicion @($blockers)

    [void]$results.Add([pscustomobject]@{
        Hash = $hash
        ShortHash = Get-ShortHash $hash
        FullName = $full
        RelativePath = $row.RelativePath
        FileName = $fileName
        Extension = $ext
        SizeBytes = $row.SizeBytes
        GroupFileCount = $row.GroupFileCount
        GroupTotalBytes = $row.GroupTotalBytes
        RefinedPolicyLane = $lane
        SpotCheckDecision = $d.Decision
        RecommendedFinalLane = $d.FinalLane
        SuspicionSignal = $d.Signal
        SharedWithHumanReview = $sharedHuman
        ReviewReason = $d.Reason
        SelectionReason = $item.SelectionReason
    })
}

$csvOut = Join-Path $ReportRoot "phase2_web_assets_tier1_spotcheck_$OutputStamp.csv"
$summaryOut = Join-Path $ReportRoot "phase2_web_assets_tier1_spotcheck_summary_$OutputStamp.txt"
$results | Select-Object Hash, ShortHash, FullName, RelativePath, FileName, Extension, SizeBytes,
    GroupFileCount, GroupTotalBytes, RefinedPolicyLane, SpotCheckDecision, RecommendedFinalLane,
    SuspicionSignal, SharedWithHumanReview, ReviewReason |
    Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding utf8

$tier1Bytes = ($tier1 | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
$checkedBytes = ($results | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
$byDecision = $results | Group-Object SpotCheckDecision | ForEach-Object {
    [pscustomobject]@{
        Decision = $_.Name
        Files = $_.Count
        Bytes = ($_.Group | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
    }
} | Sort-Object Files -Descending

$keep = @($results | Where-Object SpotCheckDecision -eq 'KEEP_TIER1_MOVE_CANDIDATE')
$escalateHuman = @($results | Where-Object SpotCheckDecision -eq 'ESCALATE_TO_HUMAN_REVIEW')
$escalateMedium = @($results | Where-Object SpotCheckDecision -eq 'ESCALATE_TO_MEDIUM_REVIEW')
$blocked = @($results | Where-Object SpotCheckDecision -eq 'BLOCK_INVESTIGATE')
$sharedCount = @($results | Where-Object SharedWithHumanReview -eq $true).Count
$suspicionCount = @($results | Where-Object { $_.SuspicionSignal -match 'SuspiciousKeyword' }).Count

$topArchiveGroups = $results | Where-Object RefinedPolicyLane -eq 'TIER1_TOOL_CACHE_ARCHIVES' |
    Group-Object Hash | ForEach-Object {
        $g = $_.Group[0]
        $reclaim = [int64]$g.SizeBytes * ([int64]$g.GroupFileCount - 1)
        [pscustomobject]@{
            Reclaim = $reclaim
            DupCount = $g.GroupFileCount
            SizeEach = [int64]$g.SizeBytes
            FileName = $g.FileName
            Decision = (@($_.Group | ForEach-Object { $_.SpotCheckDecision } | Group-Object | Sort-Object { $_.Count } -Descending | Select-Object -First 1).Name)
            SharedHuman = (@($_.Group | Where-Object { $_.SharedWithHumanReview -eq $true }).Count -gt 0)
        }
    } | Sort-Object Reclaim -Descending

$topJunkGroups = $results | Where-Object RefinedPolicyLane -eq 'TIER1_OBVIOUS_WEB_JUNK' |
    Group-Object Hash | ForEach-Object {
        $g = $_.Group[0]
        $reclaim = [int64]$g.SizeBytes * ([int64]$g.GroupFileCount - 1)
        [pscustomobject]@{
            Reclaim = $reclaim
            DupCount = $g.GroupFileCount
            SizeEach = [int64]$g.SizeBytes
            FileName = $g.FileName
            Decision = (@($_.Group | ForEach-Object { $_.SpotCheckDecision } | Group-Object | Sort-Object { $_.Count } -Descending | Select-Object -First 1).Name)
            SharedHuman = (@($_.Group | Where-Object { $_.SharedWithHumanReview -eq $true }).Count -gt 0)
        }
    } | Sort-Object Reclaim -Descending | Select-Object -First 25

$keepTier1Total = @($tier1 | Where-Object {
    $h = Get-NormHash $_.Hash
    -not $humanHashes.Contains($h) -and -not (Test-SuspicionSignal $_.FullName $_.FileName)
})
$keepTier1Bytes = ($keepTier1Total | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum

$lines = @(
    'Phase 2 Tier1 Spot-Check Summary (Read-Only)'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "RefinementSource: $refinementPath"
    "Tier1Population: files=$($tier1.Count) bytes=$tier1Bytes"
    "SpotCheckRows: $($results.Count) bytes=$checkedBytes"
    ''
    '=== COUNTS BY SPOT CHECK DECISION ==='
)
$lines += $byDecision | ForEach-Object { "$($_.Decision): files=$($_.Files) bytes=$($_.Bytes)" }

$lines += ''
$lines += '=== TOP ARCHIVE GROUPS (spot-checked) ==='
$topArchiveGroups | Select-Object -First 15 | ForEach-Object {
    $safe = if ($_.Decision -eq 'KEEP_TIER1_MOVE_CANDIDATE' -and -not $_.SharedHuman) { 'SAFE' } else { 'CAUTION' }
    $lines += "  $safe`t$($_.Reclaim)`t$($_.DupCount)`t$($_.SizeEach)`t$($_.Decision)`t$($_.FileName)"
}

$lines += ''
$lines += '=== TOP WEB-JUNK GROUPS (spot-checked) ==='
$topJunkGroups | ForEach-Object {
    $safe = if ($_.Decision -eq 'KEEP_TIER1_MOVE_CANDIDATE' -and -not $_.SharedHuman) { 'SAFE' } else { 'CAUTION' }
    $lines += "  $safe`t$($_.Reclaim)`t$($_.DupCount)`t$($_.SizeEach)`t$($_.Decision)`t$($_.FileName)"
}

$lines += ''
$lines += '=== SHARED-HASH WITH HUMAN REVIEW ==='
$lines += "Spot-check rows with SharedWithHumanReview: $sharedCount"
$lines += "Tier1 population rows sharing human-review hash: $(@($tier1 | Where-Object { $humanHashes.Contains((Get-NormHash $_.Hash)) }).Count)"

$lines += ''
$lines += '=== SUSPICIOUS KEYWORD HITS ==='
$lines += "Spot-check rows with keyword suspicion: $suspicionCount"

$lines += ''
$lines += '=== TIER1 KEEP ESTIMATE (full population after spot-check rules) ==='
$lines += "Projected KEEP (no human hash, no keywords): files=$($keepTier1Total.Count) bytes=$keepTier1Bytes"
$lines += "Spot-check KEEP: files=$($keep.Count) bytes=$(($keep | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum)"

$lines += ''
$lines += '=== ESCALATIONS IN SPOT-CHECK ==='
$lines += "ESCALATE_TO_HUMAN_REVIEW: $($escalateHuman.Count)"
if ($escalateHuman.Count -gt 0) {
    $escalateHuman | Select-Object -First 15 FileName, RelativePath, ReviewReason | ForEach-Object {
        $lines += "  $($_.FileName)`t$($_.RelativePath)`t$($_.ReviewReason)"
    }
}
$lines += "ESCALATE_TO_MEDIUM_REVIEW: $($escalateMedium.Count)"
$lines += "BLOCK_INVESTIGATE: $($blocked.Count)"

$lines += ''
$lines += '=== TIER1 SAFETY ASSESSMENT ==='
$humanEscPct = if ($results.Count -gt 0) { [math]::Round(100.0 * $escalateHuman.Count / $results.Count, 2) } else { 0 }
if ($escalateHuman.Count -eq 0 -and $blocked.Count -eq 0 -and $sharedCount -le 5) {
    $lines += 'Tier1 spot-check: LIKELY SAFE for future bounded move plan after excluding shared-hash groups.'
    $lines += 'RECOMMENDED MOVE PLAN SCOPE: TIER1_OBVIOUS_WEB_JUNK + TIER1_TOOL_CACHE_ARCHIVES excluding hashes shared with human-review lanes.'
} elseif ($escalateHuman.Count -le 10 -and $humanEscPct -lt 5) {
    $lines += 'Tier1 spot-check: MOSTLY SAFE; exclude escalated rows and shared-hash groups from first bounded plan.'
    $lines += 'RECOMMENDED MOVE PLAN SCOPE: Tier1 KEEP candidates only; hold shared-hash and escalated rows.'
} else {
    $lines += 'Tier1 spot-check: CAUTION; review escalations before any bounded move plan.'
    $lines += 'RECOMMENDED MOVE PLAN SCOPE: TIER1_OBVIOUS_WEB_JUNK images only (exclude tool archives until reviewed) OR hold entirely.'
}
$lines += 'Hold all PDFs and unclear docs separately (not in Tier1 scope).'
$lines += 'No move plan created in this task. No -Execute.'

$lines += ''
$lines += 'WARNING: Read-only spot-check. No move, copy, delete, rename, cleanup, or move plan.'
$lines | Set-Content -LiteralPath $summaryOut -Encoding utf8

Write-Host "Spot-check: $($results.Count) rows -> $csvOut"
Write-Host "Summary: $summaryOut"
$byDecision | Format-Table -AutoSize
