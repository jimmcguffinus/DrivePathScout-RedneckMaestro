[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$ReportInventoryPath = 'C:\Users\jim\Desktop\DrivePathInventory\remaining_png_suns_inventory_20260704.csv',
    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [ValidateNotNullOrEmpty()]
    [string]$PlanStamp = '20260704',
    [ValidateNotNullOrEmpty()]
    [string]$StagedRoot = 'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname',
    [ValidateNotNullOrEmpty()]
    [string]$DeleteReviewSunsRoot = 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW\medium_review\suns_png'
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
$stagedRootN = Get-NormalizedPath $StagedRoot
$reviewRoot = Get-NormalizedPath $DeleteReviewSunsRoot
$rows = @(Import-Csv -LiteralPath $ReportInventoryPath)
$selected = @($rows | Where-Object {
    $_.SuggestedLane -eq 'medium_review\suns_png' -and
    $_.LikelyClass -in @('SunsPngDuplicate', 'CollisionLeftover')
} | Sort-Object FullName)
if ($selected.Count -eq 0) { throw 'No eligible Suns/PNG rows in report inventory.' }
$planRows = New-Object System.Collections.Generic.List[object]
$seen = @{}
foreach ($row in $selected) {
    $staged = Get-NormalizedPath $row.FullName
    if (-not $staged.StartsWith($stagedRootN, [StringComparison]::OrdinalIgnoreCase)) { throw "Staged path outside root: $staged" }
    $parent = Get-NormalizedPath (Split-Path -Parent $staged)
    if (-not $parent.Equals($stagedRootN, [StringComparison]::OrdinalIgnoreCase)) { throw "Staged path not directly under recovered_to_realname: $staged" }
    if ([IO.Path]::GetExtension($staged).ToLowerInvariant() -ne '.png') { throw "Non-PNG extension: $staged" }
    if (-not (Test-Path -LiteralPath $staged)) { throw "Staged PNG missing: $staged" }
    if (Test-Path -LiteralPath $staged -PathType Container) { throw "Staged path is directory: $staged" }
    $key = $staged.ToUpperInvariant()
    if ($seen.ContainsKey($key)) { throw "Duplicate staged path: $staged" }
    $seen[$key] = $true
    $hash = Get-NormalizedHash $row.SHA256
    $short = if ($hash.Length -ge 8) { $hash.Substring(0, 8) } else { $hash }
    $fileName = Split-Path -Leaf $staged
    $deleteReviewPath = Get-NormalizedPath (Join-Path $reviewRoot $fileName)
    [void]$planRows.Add([pscustomobject]@{
        Hash = $hash; ShortHash = $short; SizeBytes = $row.SizeBytes
        StagedDuplicatePath = $staged; DeleteReviewPath = $deleteReviewPath
        DestinationSubfolder = 'suns_png_root'; ReviewConfidence = 'MEDIUM'
        ReviewReason = $row.ReviewReason.Trim()
    })
}
$planPath = Join-Path $ReportRoot "approved_suns_png_delete_review_move_plan_$PlanStamp.csv"
$shaPath = Join-Path $ReportRoot "approved_suns_png_delete_review_move_plan_$PlanStamp.sha256.txt"
$planRows | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
$hashFile = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToUpperInvariant()
Set-Content -LiteralPath $shaPath -Value $hashFile -Encoding UTF8
Write-Host "Suns/PNG review move plan rows: $($planRows.Count)"
Write-Host "TotalBytes: $(($planRows | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum)"
Write-Host "PlanPath=$planPath"; Write-Host "PlanSha256=$hashFile"; Write-Host "ShaPath=$shaPath"
