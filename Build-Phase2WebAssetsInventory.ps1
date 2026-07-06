[CmdletBinding()]
param(
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [string]$HashStamp = '20260703-004335',
    [string]$OutputStamp = '20260704',
    [string]$TargetRoot = 'I:\recover\McNASBackup',
    [switch]$VerifyLiveHash
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

$mediaExts = @('.mp3','.mp4','.avi','.wmv','.mov','.mpg','.mpeg','.mkv','.m4a','.wav','.wma','.flac','.aac','.pst','.ost','.mbox')
$webSupportExts = @('.gif','.png','.pdf','.zip','.doc','.docx','.xlsx','.xls','.rtf','.html','.htm','.css','.js','.crx','.xpi','.ico','.svg','.swf','.jar','.cab','.msi','.exe','.json','.xml','.manifest','.woff','.woff2','.ttf','.eot','.map','.7z')

$webPathPatterns = @(
    'chrome','firefox','safari','appdata\\local','cache','cached','extension','user data','plugin data',
    'google gears','inetcache','temporary internet','ldap\.browsers','!downloads','mcjunk\\test_rename\\recovered',
    'connectedkids','\\email\\','icon-cache','miro\\support','browser','webcache','localserver',
    'participatory culture','seedboxes','divi','theme_assets','browser_extension','\.dropbox\.cache'
)
$toolPathPatterns = @(
    'netwrix','lepide','ldapsearch','auditor','setup','installer','portable','eula','license\.rtf',
    'securityxploded','adminutil','userviewer'
)
$personalKeywords = @(
    'family','real_estate','real estate','closing','buyer','seller','jenni','jim\.','mcguffin','tax','medical',
    'resume','passport','msmoney','insurance','claim','job\.search','natoma','honda','lucky','immuniz','wedding',
    'homedirs','mchomemovies','camera uploads','mcphotos','mcfamily','mcpsts','honda','prelude','easter',
    'closing_docs','purchase_docs','listing','westusa','smellycunt','jenni\.music','moms_stuff','4_3_2010_backup',
    '2008_sales_tax','contact_list','pasofino','addendum','letter to seller','buyer_presentation','buyer_process'
)
$humanMediaPathPatterns = @('mchomemovies','camera uploads','mcphotos\\movies','quicktime movie','avi clip','wave sound','mp4 audio')

function Test-MatchPatterns([string]$text, [string[]]$patterns) {
    $t = $text.ToLowerInvariant()
    foreach ($p in $patterns) { if ($t -match $p) { return $true } }
    return $false
}

function Test-PersonalSignal([string]$fullPath, [string]$fileName) {
    $blob = ($fullPath + ' ' + $fileName).ToLowerInvariant()
    return Test-MatchPatterns $blob $personalKeywords
}
function Test-WebAssetPath([string]$fullPath) {
    return Test-MatchPatterns $fullPath $webPathPatterns
}
function Test-ToolInstallerPath([string]$fullPath, [string]$fileName) {
    return Test-MatchPatterns ($fullPath + ' ' + $fileName) ($toolPathPatterns + @('setup','installer','portable'))
}
function Test-HumanMediaPath([string]$fullPath, [string]$ext) {
    if ($mediaExts -contains $ext.ToLowerInvariant()) { return $true }
    return Test-MatchPatterns $fullPath $humanMediaPathPatterns
}
function Test-GearsCachedPersonal([string]$fullPath, [string]$fileName) {
    $blob = ($fullPath + ' ' + $fileName).ToLowerInvariant()
    if ($blob -notmatch 'google gears|localserver|mail\.google\.com') { return $false }
    if (Test-ToolInstallerPath $fullPath $fileName) { return $false }
    return $true
}

function Test-CarvedWebName([string]$name) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($name).ToLowerInvariant()
    if ($stem -match '^file\d+$') { return $true }
    if ($name -match 'hash\s*\(\d+\)') { return $true }
    if ($stem -match '^(sprite|favicon|icon|tnt_icon|spreadsheet)$') { return $true }
    if ($name -match '\d{1,4}x\d{1,4}') { return $true }
    return $false
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

Write-Host 'Loading McNASBackup duplicate candidates from file_hashes...'
$candidateFiles = New-Object System.Collections.ArrayList
Import-Csv (Join-Path $ReportRoot "file_hashes_$HashStamp.csv") | ForEach-Object {
    $fp = Get-NormPath $_.FullPath
    if (-not $fp.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)) { return }
    if (Test-ExcludedWorkbench $fp) { return }
    $hash = Get-NormHash $_.Hash
    if (-not $dupGroups.ContainsKey($hash)) { return }
    $ext = $_.Extension.ToLowerInvariant()
    if (Test-HumanMediaPath $fp $ext) { return }
    $isWebExt = $webSupportExts -contains $ext
    $isWebPath = Test-WebAssetPath $fp
    $isTool = Test-ToolInstallerPath $fp $_.FileName
    $isCarvedWeb = Test-CarvedWebName $_.FileName
    $isStrongWebExt = $ext -in @('.gif','.crx','.xpi','.css','.js','.html','.htm','.ico','.svg','.swf','.manifest','.woff','.woff2','.ttf','.eot','.map')
    $isDocArchiveWebContext = ($ext -in @('.pdf','.zip','.doc','.docx','.xlsx','.xls','.rtf','.7z','.cab','.jar','.msi','.exe')) -and ($isWebPath -or $isTool)
    if ($ext -eq '.bmp' -or $ext -eq '.txt') { return }
    if (-not $isStrongWebExt -and -not $isWebPath -and -not $isTool -and -not ($isCarvedWeb -and $ext -in @('.gif','.png','.ico')) -and -not $isDocArchiveWebContext) { return }
    [void]$candidateFiles.Add($_)
}
Write-Host "Candidate rows loaded: $($candidateFiles.Count)"

$hashStats = @{}
foreach ($f in $candidateFiles) {
    $h = Get-NormHash $f.Hash
    if (-not $hashStats.ContainsKey($h)) {
        $dg = $dupGroups[$h]
        $hashStats[$h] = @{
            McNasCount = 0
            McNasTotalBytes = 0
            SizeEach = [int64]$f.SizeBytes
            GroupCount = $dg.Count
            GroupTotalBytes = $dg.TotalBytes
        }
    }
    $hashStats[$h].McNasCount++
    $hashStats[$h].McNasTotalBytes += [int64]$f.SizeBytes
}

$inventory = New-Object System.Collections.ArrayList
$rowNum = 0
$total = $candidateFiles.Count
foreach ($f in $candidateFiles) {
    $rowNum++
    if ($rowNum % 1000 -eq 0) { Write-Host "  classify $rowNum / $total" }

    $full = Get-NormPath $f.FullPath
    $hash = Get-NormHash $f.Hash
    $short = Get-ShortHash $hash
    $fileName = $f.FileName
    $ext = $f.Extension.ToLowerInvariant()
    $rel = if ($full.Length -gt $targetRoot.Length) { $full.Substring($targetRoot.Length).TrimStart('\') } else { $fileName }

    $blockers = New-Object System.Collections.ArrayList
    if (-not $full.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)) { [void]$blockers.Add('OutsideTargetRoot') }
    if (Test-ExcludedWorkbench $full) { [void]$blockers.Add('UnderWorkbench') }

    $exists = Test-Path -LiteralPath $full
    $isDir = $false
    if ($exists) { $isDir = Test-Path -LiteralPath $full -PathType Container }
    if (-not $exists) { [void]$blockers.Add('MissingFile') }
    if ($isDir) { [void]$blockers.Add('IsDirectory') }

    if ($VerifyLiveHash -and $exists -and -not $isDir) {
        try {
            $liveHash = Get-NormHash (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
            if ($liveHash -ne $hash) { [void]$blockers.Add('HashMismatch') }
        } catch { [void]$blockers.Add('HashCheckFailed') }
    }

    $g = $hashStats[$hash]
    if ($null -eq $g -or $g.GroupCount -lt 2) { [void]$blockers.Add('DuplicateGroupUnclear') }

    $personal = Test-PersonalSignal $full $fileName
    $webPath = Test-WebAssetPath $full
    $gearsPersonal = Test-GearsCachedPersonal $full $fileName
    $carvedWeb = Test-CarvedWebName $fileName

    $lane = 'MEDIUM_REVIEW_WEB_ASSET'
    $subfolder = 'medium_review\web_assets'
    $reason = 'Unclear web/download artifact; medium review recommended.'

    $toolSig = Test-ToolInstallerPath $full $fileName
    $webExt = $webSupportExts -contains $ext

    if ($blockers.Count -eq 0 -and $gearsPersonal) {
        $lane = 'HUMAN_REVIEW_DOCUMENT'
        $subfolder = 'human_review\documents'
        $reason = 'Google Gears / Gmail localserver cached document mirror; treat as personal until reviewed.'
    }
    elseif ($blockers.Count -gt 0) {
        $lane = 'BLOCKED_INVESTIGATE'
        $subfolder = 'investigate\web_assets'
        $reason = ($blockers -join '; ')
    }
    elseif ($personal) {
        $lane = 'HUMAN_REVIEW_DOCUMENT'
        $subfolder = 'human_review\documents'
        $reason = 'Personal/legal/family/financial path or filename signal; hold for human review.'
    }
    elseif ($webPath -or $toolSig -or ($carvedWeb -and $ext -in @('.gif','.png','.ico','.svg'))) {
        if ($webPath -and -not $personal) {
            $lane = 'LOW_RISK_WEB_ASSET'
            $subfolder = 'high_confidence_junk\phase2_web_assets'
            $parts = @()
            if ($webPath) { $parts += 'WebCacheOrBrowserPath' }
            if ($toolSig) { $parts += 'ToolOrInstallerArtifact' }
            if ($carvedWeb) { $parts += 'CarvedOrIconName' }
            $reason = 'Browser/cache/extension or generic web artifact with no personal signal. ' + ($parts -join '; ')
        }
        else {
            $lane = 'MEDIUM_REVIEW_WEB_ASSET'
            $reason = 'Web-like artifact but mixed signals; medium review.'
        }
    }
    elseif ($toolSig -and -not $personal) {
        $lane = 'LOW_RISK_WEB_ASSET'
        $subfolder = 'high_confidence_junk\phase2_web_assets'
        $reason = 'Tool/installer/download artifact with no personal signal.'
    }
    elseif ($ext -in @('.pdf','.zip','.doc','.docx','.xlsx','.rtf') -and -not $personal) {
        $lane = 'MEDIUM_REVIEW_WEB_ASSET'
        $reason = 'Document/archive duplicate without clear web-cache path; medium review.'
    }
    elseif ($webExt -and $carvedWeb) {
        $lane = 'LOW_RISK_WEB_ASSET'
        $subfolder = 'high_confidence_junk\phase2_web_assets'
        $reason = 'Generic carved/icon web support file.'
    }

    $reclaimGroup = [int64]$g.SizeEach * ([int64]$g.GroupCount - 1)

    [void]$inventory.Add([pscustomobject]@{
        Hash = $hash
        ShortHash = $short
        FullName = $full
        RelativePath = $rel
        FileName = $fileName
        ParentFolder = $f.ParentPath
        Extension = $ext
        SizeBytes = $f.SizeBytes
        LastWriteTime = $f.LastWriteTimeUtc
        GroupFileCount = $g.GroupCount
        GroupTotalBytes = $g.GroupTotalBytes
        ReclaimEstimateBytes = $reclaimGroup
        SuggestedPolicyLane = $lane
        SuggestedDestinationSubfolder = $subfolder
        PersonalSignal = $personal
        WebAssetSignal = ($webPath -or $carvedWeb -or ($webExt -and $ext -in @('.gif','.png','.html','.htm','.css','.js','.crx')))
        ToolOrInstallerSignal = $toolSig
        ReviewReason = $reason
        SourceSubfolder = Get-SourceSubfolder $full
    })
}

$inventoryOut = Join-Path $ReportRoot "phase2_web_assets_inventory_$OutputStamp.csv"
$summaryOut = Join-Path $ReportRoot "phase2_web_assets_summary_$OutputStamp.txt"
$inventory | Export-Csv -LiteralPath $inventoryOut -NoTypeInformation -Encoding utf8

$uniqueGroups = @($inventory | Group-Object Hash)
$byLane = $inventory | Group-Object SuggestedPolicyLane | ForEach-Object {
    [pscustomobject]@{
        Lane = $_.Name
        Files = $_.Count
        Bytes = ($_.Group | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
        Groups = ($_.Group | Group-Object Hash).Count
    }
} | Sort-Object Files -Descending

$lowReclaim = ($inventory | Where-Object SuggestedPolicyLane -eq 'LOW_RISK_WEB_ASSET' | Group-Object Hash | ForEach-Object {
    $g = $_.Group[0]
    [int64]$g.SizeBytes * ([int64]$g.GroupFileCount - 1)
} | Measure-Object -Sum).Sum

$topGroups = $uniqueGroups | ForEach-Object {
    $g = $_.Group[0]
    [pscustomobject]@{
        Reclaim = $g.ReclaimEstimateBytes
        Count = $g.GroupFileCount
        SizeEach = $g.SizeBytes
        Lane = $g.SuggestedPolicyLane
        Ext = $g.Extension
        Example = $g.FileName
    }
} | Sort-Object Reclaim -Descending | Select-Object -First 25

$topFiles = $inventory | Sort-Object { [int64]$_.SizeBytes } -Descending | Select-Object -First 25 SizeBytes, SuggestedPolicyLane, Extension, FullName
$byExt = $inventory | Group-Object Extension | Sort-Object Count -Descending | Select-Object -First 20 Name, Count
$bySub = $inventory | Group-Object SourceSubfolder | Sort-Object Count -Descending | Select-Object -First 20 Name, Count

$lines = @(
    'Phase 2 LOW_RISK_WEB_ASSETS Inventory Summary (Read-Only)'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "TargetRoot: $targetRoot"
    "InventoryRows: $($inventory.Count)"
    "UniqueDuplicateGroups: $($uniqueGroups.Count)"
    "TotalBytes: $(($inventory | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum)"
    ''
    '=== COUNTS BY SUGGESTED POLICY LANE ==='
)
$lines += $byLane | ForEach-Object { "$($_.Lane): files=$($_.Files) bytes=$($_.Bytes) groups=$($_.Groups)" }
$lines += ''
$lines += '=== RECLAIM / GROUPING ESTIMATE ==='
$lines += "LowRiskWebAssetGroups: $(@($inventory | Where-Object SuggestedPolicyLane -eq 'LOW_RISK_WEB_ASSET' | Group-Object Hash).Count)"
$lines += "LowRiskReclaimEstimateBytes: $lowReclaim"
$lines += 'Note: Reclaim assumes one keeper per hash (GroupFileCount-1).'
$lines += ''
$lines += '=== EXTENSION BREAKDOWN (top 20) ==='
$lines += $byExt | ForEach-Object { "$($_.Name)`t$($_.Count)" }
$lines += ''
$lines += '=== SOURCE SUBFOLDER BREAKDOWN (top 20) ==='
$lines += $bySub | ForEach-Object { "$($_.Name)`t$($_.Count)" }
$lines += ''
$lines += '=== TOP 25 LARGEST GROUPS ==='
$lines += $topGroups | ForEach-Object { "$($_.Reclaim)`t$($_.Count)`t$($_.SizeEach)`t$($_.Lane)`t$($_.Ext)`t$($_.Example)" }
$lines += ''
$lines += '=== TOP 25 LARGEST FILES ==='
$lines += $topFiles | ForEach-Object { "$($_.SizeBytes)`t$($_.SuggestedPolicyLane)`t$($_.Extension)`t$($_.FullName)" }
$lines += ''
$lines += '=== HUMAN-REVIEW CAUTIONS ==='
$lines += "HumanReviewDocumentFiles: $(@($inventory | Where-Object SuggestedPolicyLane -eq 'HUMAN_REVIEW_DOCUMENT').Count)"
$lines += "PersonalSignalFlagged: $(@($inventory | Where-Object PersonalSignal -eq $true).Count)"
$lines += '- Chrome Gears cache can mirror personal PDFs/docs from Gmail; verify before any move.'
$lines += '- Real-estate/buyer/seller/Jenni/Jim paths -> HUMAN_REVIEW_DOCUMENT even if under cache.'
$lines += ''
$lines += '=== BLOCKERS ==='
$blocked = @($inventory | Where-Object SuggestedPolicyLane -eq 'BLOCKED_INVESTIGATE')
$lines += "BlockedInvestigateFiles: $($blocked.Count)"
if ($blocked.Count -gt 0) {
    $blocked | Group-Object ReviewReason | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
        $lines += "  $($_.Name): $($_.Count)"
    }
} else { $lines += 'None' }
$lines += ''
$lines += '=== PHASE2 TARGET COMPARISON ==='
$lines += 'Phase2 target selection (all sources): 697 groups / 5879 files / ~1.14 GB reclaim estimate'
$lines += "This inventory (McNASBackup web-path dup candidates): $($uniqueGroups.Count) groups / $($inventory.Count) files"
$lines += 'Per-file classification is broader than phase2 aggregate; review LOW_RISK rows before any bounded move plan.'
$lines += ''
$lines += '=== RECOMMENDED NEXT ACTION ==='
$lines += 'Review phase2_web_assets_inventory CSV; refine LOW_RISK vs MEDIUM vs HUMAN lanes before bounded move plan.'
$lines += 'Do not auto-move personal-signal rows. No move plan in this task.'
$lines += ''
$lines += 'WARNING: Read-only inventory. No move, copy, delete, rename, cleanup, or move plan.'
$lines | Set-Content -LiteralPath $summaryOut -Encoding utf8

Write-Host "Inventory: $($inventory.Count) rows -> $inventoryOut"
Write-Host "Summary: $summaryOut"
$byLane | Format-Table -AutoSize
