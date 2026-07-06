[CmdletBinding()]
param(
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [string]$InventoryStamp = '20260704',
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

function Test-MatchPatterns([string]$text, [string[]]$patterns) {
    $t = $text.ToLowerInvariant()
    foreach ($p in $patterns) { if ($t -match $p) { return $true } }
    return $false
}

$escalationKeywords = @(
    'family','real_estate','real estate','closing','buyer','seller','jenni','jim\.','mcguffin','tax','medical',
    'resume','passport','msmoney','insurance','claim','job\.search','natoma','honda','lucky','immuniz','wedding',
    'homedirs','mchomemovies','camera uploads','mcphotos','mcfamily','mcpsts','prelude','easter',
    'closing_docs','purchase_docs','listing','westusa','smellycunt','jenni\.music','moms_stuff','4_3_2010_backup',
    '2008_sales_tax','contact_list','pasofino','addendum','letter to seller','buyer_presentation','buyer_process',
    '\blease\b','executed','contract','offer','mortgage','deed','w-2','w2','1099','invoice','statement','payroll',
    'diagnosis','prescription','doctor','hospital','ssn','social.security','birth.?cert','passport',
    'school','transcript','diploma','university','college','tuition','enrollment',
    'identity','driver.?lic','credit.?report','bank','checking','savings','loan',
    'mail\.google','gmail','outlook','\.pst','export','mbox','inbox',
    'project','proposal','client','customer','nda','confidential'
)

$webPathPatterns = @(
    'chrome','firefox','safari','appdata\\local','cache','cached','extension','user data','plugin data',
    'google gears','inetcache','temporary internet','ldap\.browsers','!downloads','mcjunk\\test_rename\\recovered',
    'connectedkids','\\email\\','icon-cache','miro\\support','browser','webcache','localserver',
    'participatory culture','seedboxes','divi','theme_assets','browser_extension','\.dropbox\.cache',
    'drobo_bkup\\mcjunk','\\gifs\\','favicon','sprite','thumbnail','thumbcache','crx','xpi'
)

$toolPathPatterns = @(
    'netwrix','lepide','ldapsearch','auditor','setup','installer','portable','eula','license\.rtf',
    'securityxploded','adminutil','userviewer','jasperreports','prtg','training.?kit','jetlxcmmty',
    'map_training','auditor_enterprise','ldap\.browsers','upandown\.free\.monitors'
)

$toolArchiveNames = @(
    'prtg','netwrix','jasperreports','jetlxcmmty','map_training','auditor','ldap','installer','setup',
    'portable','training.?kit','chrome\.zip','firefox','extension','cache','nightly','hlte'
)

$imageExts = @('.gif','.png','.jpg','.jpeg','.ico','.svg','.bmp','.webp')
$archiveExts = @('.zip','.7z','.cab','.jar')
$docExts = @('.doc','.docx','.xls','.xlsx','.ppt','.pptx','.rtf','.csv')

function Test-EscalationSignal([string]$fullPath, [string]$fileName) {
    $blob = ($fullPath + ' ' + $fileName).ToLowerInvariant()
    return Test-MatchPatterns $blob $escalationKeywords
}

function Test-WebAssetPath([string]$fullPath) {
    return Test-MatchPatterns $fullPath $webPathPatterns
}

function Test-ToolInstallerSignal([string]$fullPath, [string]$fileName) {
    return Test-MatchPatterns ($fullPath + ' ' + $fileName) $toolPathPatterns
}

function Test-CarvedWebName([string]$name) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($name).ToLowerInvariant()
    if ($stem -match '^file\d+$') { return $true }
    if ($name -match 'hash\s*\(\d+\)') { return $true }
    if ($stem -match '^(sprite|favicon|icon|tnt_icon|spreadsheet|logo|banner|button|arrow|bullet)$') { return $true }
    if ($name -match '\d{1,4}x\d{1,4}') { return $true }
    return $false
}

function Test-ObviousToolArchive([string]$fullPath, [string]$fileName, [string]$ext) {
    if ($archiveExts -notcontains $ext) { return $false }
    $blob = ($fullPath + ' ' + $fileName).ToLowerInvariant()
    if (Test-MatchPatterns $blob $toolPathPatterns) { return $true }
    if ($blob -match '\.dropbox\.cache|ldap\.browsers|!downloads|mcjunk') { return $true }
    if (Test-MatchPatterns $fileName $toolArchiveNames) { return $true }
    if ($fileName -match '\(deleted [0-9a-f]+\)\.zip$') { return $true }
    return $false
}

function Test-ObviousWebJunk([string]$fullPath, [string]$fileName, [string]$ext) {
    if ($imageExts -contains $ext) {
        if (Test-CarvedWebName $fileName) { return $true }
        if (Test-WebAssetPath $fullPath) { return $true }
        if ($fullPath -match 'mcjunk|gifs\\|icon|favicon|sprite|thumb|cache|extension|crx|xpi') { return $true }
        return $false
    }
    if ($ext -in @('.css','.js','.html','.htm','.crx','.xpi','.woff','.woff2','.ttf','.eot','.map','.manifest','.swf')) {
        return $true
    }
    if (Test-CarvedWebName $fileName -and $ext -in @('.gif','.png','.ico','.svg')) { return $true }
    if (Test-WebAssetPath $fullPath -and $ext -in @('.gif','.png','.ico','.json','.xml')) { return $true }
    return $false
}

function Test-PdfNeedsReview([string]$fullPath, [string]$fileName, [string]$ext) {
    if ($ext -ne '.pdf') { return $false }
    if (Test-CarvedWebName $fileName) { return $true }
    $blob = ($fullPath + ' ' + $fileName).ToLowerInvariant()
    if ($blob -match 'google gears|localserver|mail\.google|gmail|gears') { return $true }
    if ($blob -match 'cache|browser|webcache|inetcache|chrome|firefox') { return $true }
    if ($fileName -match '^(file\d+|document|doc\d*|untitled|scan\d*|image\d*)\.pdf$') { return $true }
    if ($fileName -match '^\d+\.pdf$|^[a-f0-9]{8,}\.pdf$') { return $true }
    return $true
}

function Test-UnclearPdfName([string]$fileName) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($fileName).ToLowerInvariant()
    if ($stem -match '^file\d+$') { return $true }
    if ($stem -match '^(document|doc\d*|untitled|scan\d*|image\d*)$') { return $true }
    if ($stem -match '^\d+$|^[a-f0-9]{8,}$') { return $true }
    return $false
}

function Get-RefinedLane(
    [string]$fullPath,
    [string]$fileName,
    [string]$ext,
    [bool]$personalOrig,
    [bool]$webOrig,
    [bool]$toolOrig,
    [string[]]$blockers
) {
    if ($blockers.Count -gt 0) {
        return @{
            Lane = 'BLOCKED_STILL_BLOCKED'
            Subfolder = 'investigate\web_assets'
            Reason = ($blockers -join '; ')
            Personal = $false
            Web = $false
            Tool = $false
            PdfRisk = $false
            Blocked = $true
        }
    }

    $escalated = Test-EscalationSignal $fullPath $fileName
    if ($personalOrig -or $escalated) {
        return @{
            Lane = 'HUMAN_REVIEW_ESCALATED'
            Subfolder = 'human_review\documents'
            Reason = if ($personalOrig) { 'Original personal signal on LOW_RISK row; escalate before any move.' } else { 'Refinement detected personal/legal/financial/family/mail/project signal missed in first pass.' }
            Personal = $true
            Web = $webOrig
            Tool = $toolOrig
            PdfRisk = ($ext -eq '.pdf')
            Blocked = $false
        }
    }

    if ($ext -eq '.pdf' -and (Test-PdfNeedsReview $fullPath $fileName $ext)) {
        $parts = @()
        if (Test-CarvedWebName $fileName) { $parts += 'CarvedFileName' }
        if (($fullPath + $fileName) -match 'gears|gmail|localserver') { $parts += 'GearsGmailCache' }
        if (Test-UnclearPdfName $fileName) { $parts += 'UnclearPdfName' }
        if (Test-WebAssetPath $fullPath) { $parts += 'WebCachePath' }
        return @{
            Lane = 'TIER2_PDF_NEEDS_SAMPLE_REVIEW'
            Subfolder = 'medium_review\web_assets\pdf_sample_review'
            Reason = 'PDF from web/cache context or unclear name; sample review before move. ' + ($parts -join '; ')
            Personal = $false
            Web = $true
            Tool = $false
            PdfRisk = $true
            Blocked = $false
        }
    }

    if (Test-ObviousToolArchive $fullPath $fileName $ext) {
        return @{
            Lane = 'TIER1_TOOL_CACHE_ARCHIVES'
            Subfolder = 'high_confidence_junk\phase2_web_assets\tool_cache_archives'
            Reason = 'Obvious tool/installer/cache archive duplicate with no personal signal.'
            Personal = $false
            Web = (Test-WebAssetPath $fullPath)
            Tool = $true
            PdfRisk = $false
            Blocked = $false
        }
    }

    $sizeHint = 0
    if ($imageExts -contains $ext -and (Test-CarvedWebName $fileName -or Test-WebAssetPath $fullPath)) {
        $sizeHint = 1
    }

    $isObviousJunk = $false
    if ($imageExts -contains $ext) {
        if (Test-CarvedWebName $fileName -and -not ($ext -eq '.pdf')) { $isObviousJunk = $true }
        elseif (Test-WebAssetPath $fullPath) { $isObviousJunk = $true }
        elseif ($fullPath -match 'mcjunk|gifs\\|drobo_bkup\\mcjunk') { $isObviousJunk = $true }
        elseif ($fileName -match 'logo|icon|sprite|favicon|thumb|banner|button|arrow|bullet|spacer|pixel') { $isObviousJunk = $true }
    }
    elseif ($ext -in @('.css','.js','.html','.htm','.crx','.xpi','.woff','.woff2','.ttf','.eot','.map','.manifest','.swf','.json')) {
        $isObviousJunk = $true
    }
    elseif (Test-CarvedWebName $fileName -and $ext -in @('.gif','.png','.ico','.svg')) {
        $isObviousJunk = $true
    }
    elseif ($webOrig -and $ext -in @('.gif','.png','.ico') -and -not ($docExts -contains $ext)) {
        if (Test-WebAssetPath $fullPath) { $isObviousJunk = $true }
    }

    if ($isObviousJunk -and $ext -notin @('.pdf','.zip','.7z','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.rtf')) {
        return @{
            Lane = 'TIER1_OBVIOUS_WEB_JUNK'
            Subfolder = 'high_confidence_junk\phase2_web_assets\obvious_web_junk'
            Reason = 'Obvious web/cache/extension image or support asset with no personal signal.'
            Personal = $false
            Web = $true
            Tool = $toolOrig
            PdfRisk = $false
            Blocked = $false
        }
    }

    if ($ext -in @('.doc','.docx','.xls','.xlsx','.ppt','.pptx','.rtf','.csv') -or ($ext -in @('.zip','.7z') -and -not (Test-ObviousToolArchive $fullPath $fileName $ext))) {
        return @{
            Lane = 'TIER2_UNCLEAR_WEB_ASSET'
            Subfolder = 'medium_review\web_assets\unclear'
            Reason = 'Document or ambiguous archive labeled LOW_RISK; not obvious enough for immediate move.'
            Personal = $false
            Web = $webOrig
            Tool = $toolOrig
            PdfRisk = ($ext -eq '.pdf')
            Blocked = $false
        }
    }

    if ($imageExts -contains $ext -and $webOrig) {
        return @{
            Lane = 'TIER1_OBVIOUS_WEB_JUNK'
            Subfolder = 'high_confidence_junk\phase2_web_assets\obvious_web_junk'
            Reason = 'Web-signal image duplicate in McJunk/cache context.'
            Personal = $false
            Web = $true
            Tool = $toolOrig
            PdfRisk = $false
            Blocked = $false
        }
    }

    return @{
        Lane = 'TIER2_UNCLEAR_WEB_ASSET'
        Subfolder = 'medium_review\web_assets\unclear'
        Reason = 'LOW_RISK first pass but insufficient confidence for Tier1 move candidacy.'
        Personal = $false
        Web = $webOrig
        Tool = $toolOrig
        PdfRisk = ($ext -eq '.pdf')
        Blocked = $false
    }
}

$inventoryPath = Join-Path $ReportRoot "phase2_web_assets_inventory_$InventoryStamp.csv"
Write-Host "Loading inventory from $inventoryPath"
$allInventory = Import-Csv -LiteralPath $inventoryPath
$lowRisk = @($allInventory | Where-Object SuggestedPolicyLane -eq 'LOW_RISK_WEB_ASSET')
Write-Host "LOW_RISK_WEB_ASSET rows: $($lowRisk.Count)"

$refined = New-Object System.Collections.ArrayList
$rowNum = 0
foreach ($row in $lowRisk) {
    $rowNum++
    if ($rowNum % 2000 -eq 0) { Write-Host "  refine $rowNum / $($lowRisk.Count)" }

    $full = Get-NormPath $row.FullName
    $hash = Get-NormHash $row.Hash
    $fileName = $row.FileName
    $ext = $row.Extension.ToLowerInvariant()
    $personalOrig = ($row.PersonalSignal -eq 'True')
    $webOrig = ($row.WebAssetSignal -eq 'True')
    $toolOrig = ($row.ToolOrInstallerSignal -eq 'True')

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

  $gfc = [int]$row.GroupFileCount
    if ($gfc -lt 2) { [void]$blockers.Add('DuplicateGroupUnclear') }

    $r = Get-RefinedLane $full $fileName $ext $personalOrig $webOrig $toolOrig @($blockers)

    [void]$refined.Add([pscustomobject]@{
        Hash = $hash
        ShortHash = Get-ShortHash $hash
        FullName = $full
        RelativePath = $row.RelativePath
        FileName = $fileName
        ParentFolder = $row.ParentFolder
        Extension = $ext
        SizeBytes = $row.SizeBytes
        LastWriteTime = $row.LastWriteTime
        GroupFileCount = $row.GroupFileCount
        GroupTotalBytes = $row.GroupTotalBytes
        ReclaimEstimateBytes = $row.ReclaimEstimateBytes
        OriginalSuggestedPolicyLane = 'LOW_RISK_WEB_ASSET'
        RefinedPolicyLane = $r.Lane
        SuggestedDestinationSubfolder = $r.Subfolder
        PersonalSignal = $r.Personal
        WebAssetSignal = $r.Web
        ToolOrInstallerSignal = $r.Tool
        PdfRiskSignal = $r.PdfRisk
        MissingOrBlockedSignal = $r.Blocked
        ReviewReason = $r.Reason
    })
}

$csvOut = Join-Path $ReportRoot "phase2_web_assets_lowrisk_refinement_$OutputStamp.csv"
$summaryOut = Join-Path $ReportRoot "phase2_web_assets_lowrisk_refinement_summary_$OutputStamp.txt"
$refined | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding utf8

$byLane = $refined | Group-Object RefinedPolicyLane | ForEach-Object {
    $bytes = ($_.Group | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum
    $groups = ($_.Group | Group-Object Hash).Count
    [pscustomobject]@{ Lane = $_.Name; Files = $_.Count; Bytes = $bytes; Groups = $groups }
} | Sort-Object Files -Descending

$tier1Junk = @($refined | Where-Object RefinedPolicyLane -eq 'TIER1_OBVIOUS_WEB_JUNK')
$tier1Arch = @($refined | Where-Object RefinedPolicyLane -eq 'TIER1_TOOL_CACHE_ARCHIVES')
$tier2Pdf = @($refined | Where-Object RefinedPolicyLane -eq 'TIER2_PDF_NEEDS_SAMPLE_REVIEW')
$escalated = @($refined | Where-Object RefinedPolicyLane -eq 'HUMAN_REVIEW_ESCALATED')
$blocked = @($refined | Where-Object RefinedPolicyLane -eq 'BLOCKED_STILL_BLOCKED')

$humanReviewOrig = @($allInventory | Where-Object SuggestedPolicyLane -eq 'HUMAN_REVIEW_DOCUMENT').Count
$blockedOrig = @($allInventory | Where-Object SuggestedPolicyLane -eq 'BLOCKED_INVESTIGATE').Count
$refinedHashes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$refined | ForEach-Object { [void]$refinedHashes.Add($_.Hash) }
$humanRowsInRefined = @($refined | Where-Object OriginalSuggestedPolicyLane -ne 'LOW_RISK_WEB_ASSET').Count
$sharedHashesWithHuman = @($allInventory | Where-Object { $_.SuggestedPolicyLane -eq 'HUMAN_REVIEW_DOCUMENT' -and $refinedHashes.Contains((Get-NormHash $_.Hash)) } | Select-Object -ExpandProperty Hash -Unique).Count

$lines = @(
    'Phase 2 LOW_RISK_WEB_ASSET Refinement Summary (Read-Only)'
    "GeneratedUtc: $((Get-Date).ToUniversalTime().ToString('o'))"
    "SourceInventory: $inventoryPath"
    "TargetRoot: $targetRoot"
    "InputRows (LOW_RISK_WEB_ASSET only): $($lowRisk.Count)"
    "RefinedRows: $($refined.Count)"
    ''
    '=== COUNTS BY REFINED POLICY LANE ==='
)
$lines += $byLane | ForEach-Object { "$($_.Lane): files=$($_.Files) bytes=$($_.Bytes) groups=$($_.Groups)" }

$lines += ''
$lines += '=== EXTENSION BREAKDOWN BY REFINED LANE ==='
foreach ($laneGrp in ($refined | Group-Object RefinedPolicyLane | Sort-Object Name)) {
    $lines += "--- $($laneGrp.Name) ---"
    $laneGrp.Group | Group-Object Extension | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
        $lines += "  $($_.Name)`t$($_.Count)"
    }
}

$lines += ''
$lines += '=== TOP 25 LARGEST GROUPS BY REFINED LANE ==='
foreach ($laneName in @('TIER1_OBVIOUS_WEB_JUNK','TIER1_TOOL_CACHE_ARCHIVES','TIER2_PDF_NEEDS_SAMPLE_REVIEW','TIER2_UNCLEAR_WEB_ASSET','HUMAN_REVIEW_ESCALATED','BLOCKED_STILL_BLOCKED')) {
    $laneRows = @($refined | Where-Object RefinedPolicyLane -eq $laneName)
    if ($laneRows.Count -eq 0) { continue }
    $lines += "--- $laneName ---"
    $laneRows | Group-Object Hash | ForEach-Object {
        $g = $_.Group[0]
        [pscustomobject]@{ Reclaim = [int64]$g.ReclaimEstimateBytes; Count = $g.GroupFileCount; SizeEach = [int64]$g.SizeBytes; Ext = $g.Extension; Example = $g.FileName }
    } | Sort-Object Reclaim -Descending | Select-Object -First 25 | ForEach-Object {
        $lines += "  $($_.Reclaim)`t$($_.Count)`t$($_.SizeEach)`t$($_.Ext)`t$($_.Example)"
    }
}

$lines += ''
$lines += '=== TOP 25 LARGEST FILES BY REFINED LANE ==='
foreach ($laneName in @('TIER1_OBVIOUS_WEB_JUNK','TIER1_TOOL_CACHE_ARCHIVES','TIER2_PDF_NEEDS_SAMPLE_REVIEW','TIER2_UNCLEAR_WEB_ASSET','HUMAN_REVIEW_ESCALATED','BLOCKED_STILL_BLOCKED')) {
    $laneRows = @($refined | Where-Object RefinedPolicyLane -eq $laneName)
    if ($laneRows.Count -eq 0) { continue }
    $lines += "--- $laneName ---"
    $laneRows | Sort-Object { [int64]$_.SizeBytes } -Descending | Select-Object -First 25 | ForEach-Object {
        $lines += "  $($_.SizeBytes)`t$($_.Extension)`t$($_.FileName)`t$($_.RelativePath)"
    }
}

$lines += ''
$lines += '=== TOP SUSPICIOUS PDFs (TIER2_PDF_NEEDS_SAMPLE_REVIEW) ==='
$tier2Pdf | Sort-Object { [int64]$_.SizeBytes } -Descending | Select-Object -First 30 | ForEach-Object {
    $lines += "  $($_.SizeBytes)`t$($_.FileName)`t$($_.RelativePath)"
}

$lines += ''
$lines += '=== TOP TIER1 MOVE CANDIDATES (OBVIOUS WEB JUNK + TOOL ARCHIVES) ==='
@($tier1Junk + $tier1Arch) | Sort-Object { [int64]$_.ReclaimEstimateBytes } -Descending | Select-Object -First 30 | ForEach-Object {
    $lines += "  $($_.RefinedPolicyLane)`t$($_.ReclaimEstimateBytes)`t$($_.GroupFileCount)`t$($_.Extension)`t$($_.FileName)"
}

$lines += ''
$lines += '=== HUMAN-REVIEW ESCALATIONS ==='
$lines += "EscalatedFromLowRisk: $($escalated.Count)"
if ($escalated.Count -gt 0) {
    $escalated | Group-Object Extension | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
        $lines += "  ext $($_.Name): $($_.Count)"
    }
    $lines += 'Top escalated examples:'
    $escalated | Sort-Object { [int64]$_.SizeBytes } -Descending | Select-Object -First 15 | ForEach-Object {
        $lines += "  $($_.SizeBytes)`t$($_.Extension)`t$($_.FileName)`t$($_.ReviewReason)"
    }
}

$lines += ''
$lines += '=== BLOCKERS ==='
$lines += "BlockedInRefinement: $($blocked.Count)"
if ($blocked.Count -gt 0) {
    $blocked | Group-Object ReviewReason | Sort-Object Count -Descending | ForEach-Object {
        $lines += "  $($_.Name): $($_.Count)"
    }
}

$lines += ''
$lines += '=== CROSS-CHECK: ORIGINAL INVENTORY LANES NOT SELECTED ==='
$lines += "HUMAN_REVIEW_DOCUMENT in original inventory: $humanReviewOrig"
$lines += "HUMAN_REVIEW_DOCUMENT rows in refinement output: $humanRowsInRefined (expect 0)"
$lines += "Shared hashes with HUMAN_REVIEW_DOCUMENT (sibling dup copies): $sharedHashesWithHuman"
$lines += "BLOCKED_INVESTIGATE in original inventory: $blockedOrig (unchanged; not in refinement input)"
$lines += "Refinement input was LOW_RISK_WEB_ASSET only ($($lowRisk.Count) rows)."

$tier1JunkReclaim = ($tier1Junk | Group-Object Hash | ForEach-Object {
    $g = $_.Group[0]; [int64]$g.SizeBytes * ([int64]$g.GroupFileCount - 1)
} | Measure-Object -Sum).Sum
$tier1ArchReclaim = ($tier1Arch | Group-Object Hash | ForEach-Object {
    $g = $_.Group[0]; [int64]$g.SizeBytes * ([int64]$g.GroupFileCount - 1)
} | Measure-Object -Sum).Sum
$tier1TotalReclaim = $tier1JunkReclaim + $tier1ArchReclaim

$lines += ''
$lines += '=== TIER1 MOVE CANDIDATE SUMMARY ==='
$lines += "TIER1_OBVIOUS_WEB_JUNK: files=$($tier1Junk.Count) groups=$(@($tier1Junk | Group-Object Hash).Count) reclaimEstimate=$tier1JunkReclaim"
$lines += "TIER1_TOOL_CACHE_ARCHIVES: files=$($tier1Arch.Count) groups=$(@($tier1Arch | Group-Object Hash).Count) reclaimEstimate=$tier1ArchReclaim"
$lines += "Combined Tier1 reclaim estimate: $tier1TotalReclaim"
$lines += "TIER2_PDF_NEEDS_SAMPLE_REVIEW: files=$($tier2Pdf.Count) - hold for sample review"
$lines += "TIER2_UNCLEAR_WEB_ASSET: files=$(@($refined | Where-Object RefinedPolicyLane -eq 'TIER2_UNCLEAR_WEB_ASSET').Count)"

$lines += ''
$lines += '=== PDF CAUTIONS ==='
$lines += "All $($tier2Pdf.Count) LOW_RISK PDFs routed to TIER2_PDF_NEEDS_SAMPLE_REVIEW."
$lines += 'Carved file###.pdf names and Gears/Gmail/cache-path PDFs must be spot-checked before any move.'
$lines += 'Do not include PDFs in an initial bounded move plan without sample validation.'

$lines += ''
$lines += '=== RECOMMENDED NEXT ACTION ==='
if ($escalated.Count -gt 0) {
    $lines += "Review $($escalated.Count) HUMAN_REVIEW_ESCALATED rows before any move plan."
}
if ($tier2Pdf.Count -gt 0) {
    $lines += "Hold $($tier2Pdf.Count) PDFs (TIER2_PDF_NEEDS_SAMPLE_REVIEW) for separate sample review (option C)."
}
if ($tier1Junk.Count -gt 5000 -and $escalated.Count -lt 100) {
    $lines += 'RECOMMENDATION: B - Future bounded move plan may target TIER1_OBVIOUS_WEB_JUNK + TIER1_TOOL_CACHE_ARCHIVES after spot-checking top reclaim groups.'
    $lines += 'Rationale: Large obvious image/web junk plus tool/cache archives; PDFs and unclear docs held separately.'
} elseif ($tier1Junk.Count -gt 0) {
    $lines += 'RECOMMENDATION: A - Start with TIER1_OBVIOUS_WEB_JUNK only if escalations or unclear rows are significant.'
    $lines += 'If escalations are low and tool archives verified, upgrade to B.'
} else {
    $lines += 'RECOMMENDATION: D - No move yet; insufficient Tier1 confidence.'
}
$lines += 'No hard delete. No move plan in this task. No -Execute.'

$lines += ''
$lines += 'WARNING: Read-only refinement. No move, copy, delete, rename, cleanup, or move plan.'
$lines | Set-Content -LiteralPath $summaryOut -Encoding utf8

Write-Host "Refined: $($refined.Count) rows -> $csvOut"
Write-Host "Summary: $summaryOut"
$byLane | Format-Table -AutoSize
