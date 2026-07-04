[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$PolicyInventoryPath = 'C:\Users\jim\Desktop\DrivePathInventory\pst_policy_inventory_20260704.csv',
    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [ValidateNotNullOrEmpty()]
    [string]$PlanStamp = '20260704',
    [ValidateNotNullOrEmpty()]
    [string]$StagedPstRoot = 'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\mail\pst',
    [ValidateNotNullOrEmpty()]
    [string]$HumanReviewPstRoot = 'I:\_RECOVERY_WORKBENCH\06_HUMAN_REVIEW\mail\pst_duplicates'
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { return $Path.Trim() }
}
function Get-NormalizedHash {
    param([Parameter(Mandatory = $true)][string]$Hash)
    return $Hash.Trim().ToUpperInvariant()
}
$stagedRoot = Get-NormalizedPath $StagedPstRoot
$humanRoot = Get-NormalizedPath $HumanReviewPstRoot
$rows = @(Import-Csv -LiteralPath $PolicyInventoryPath)
$selected = @($rows | Where-Object {
    $_.SuggestedPolicyLane -eq 'REVIEW_GROUP_CANDIDATE' -and
    $_.KeeperExists -eq 'True' -and
    $_.KeeperHashMatches -eq 'True' -and
    $_.KeeperReviewCopyExists -eq 'True'
} | Sort-Object StagedDuplicatePath)
if ($selected.Count -eq 0) { throw 'No eligible REVIEW_GROUP_CANDIDATE PST rows in policy inventory.' }
$planRows = New-Object System.Collections.Generic.List[object]
$seen = @{}
foreach ($row in $selected) {
    $staged = Get-NormalizedPath $row.StagedDuplicatePath
    if (-not $staged.StartsWith($stagedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Staged path outside mail\pst root: $staged" }
    if ([IO.Path]::GetExtension($staged).ToLowerInvariant() -ne '.pst') { throw "Non-PST extension: $staged" }
    if (-not (Test-Path -LiteralPath $staged)) { throw "Staged PST missing: $staged" }
    if (Test-Path -LiteralPath $staged -PathType Container) { throw "Staged path is directory: $staged" }
    $liveHash = Get-NormalizedHash (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash
    $expectedHash = Get-NormalizedHash $row.SHA256
    if ($liveHash -ne $expectedHash) { throw "Staged hash mismatch: $staged" }
    $key = $staged.ToUpperInvariant()
    if ($seen.ContainsKey($key)) { throw "Duplicate staged path: $staged" }
    $seen[$key] = $true
    $hash = $expectedHash
    $short = if ($hash.Length -ge 8) { $hash.Substring(0, 8) } else { $hash }
    $fileName = Split-Path -Leaf $staged
    $humanPath = Get-NormalizedPath (Join-Path $humanRoot $fileName)
    [void]$planRows.Add([pscustomobject]@{
        Hash = $hash
        ShortHash = $short
        SizeBytes = $row.SizeBytes
        StagedDuplicatePath = $staged
        HumanReviewPath = $humanPath
        DestinationSubfolder = 'mail\pst'
        KeeperPath = Get-NormalizedPath $row.KeeperPath
        KeeperFileName = $row.KeeperFileName
        KeeperReviewCopyPath = Get-NormalizedPath $row.KeeperReviewCopyPath
        DuplicateGroupKey = Get-NormalizedHash $row.DuplicateGroupKey
        ReviewConfidence = 'MEDIUM'
        ReviewReason = $row.PolicyReason.Trim()
    })
}
$planPath = Join-Path $ReportRoot "approved_pst_human_review_move_plan_$PlanStamp.csv"
$shaPath = Join-Path $ReportRoot "approved_pst_human_review_move_plan_$PlanStamp.sha256.txt"
$planRows | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
$hashFile = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToUpperInvariant()
Set-Content -LiteralPath $shaPath -Value $hashFile -Encoding UTF8
Write-Host "PST human review move plan rows: $($planRows.Count)"
Write-Host "TotalBytes: $(($planRows | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum)"
Write-Host "PlanPath=$planPath"
Write-Host "PlanSha256=$hashFile"
Write-Host "ShaPath=$shaPath"
