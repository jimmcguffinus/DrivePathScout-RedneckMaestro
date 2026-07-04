[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$InventoryCsvPath = 'C:\Users\jim\Desktop\DrivePathInventory\staged_duplicate_inventory_20260703-221211.csv',
    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [ValidateNotNullOrEmpty()]
    [string]$PlanStamp = '20260703',
    [ValidateNotNullOrEmpty()]
    [string]$StagedGifRoot = 'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\images\gif',
    [ValidateNotNullOrEmpty()]
    [string]$DeleteReviewGifRoot = 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW\medium_review\gif'
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { return $Path.Trim() }
}
$stagedRoot = Get-NormalizedPath $StagedGifRoot
$reviewRoot = Get-NormalizedPath $DeleteReviewGifRoot
$inv = @(Import-Csv -LiteralPath $InventoryCsvPath)
$gifRows = @($inv | Where-Object { $_.DestinationSubfolder -eq 'images\gif' } | Sort-Object StagedDuplicatePath)
if ($gifRows.Count -eq 0) { throw 'No images\gif rows found in inventory.' }
$planRows = New-Object System.Collections.Generic.List[object]
$seen = @{}
foreach ($row in $gifRows) {
    $staged = Get-NormalizedPath $row.StagedDuplicatePath
    if (-not $staged.StartsWith($stagedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Staged path outside GIF root: $staged" }
    if ([IO.Path]::GetExtension($staged).ToLowerInvariant() -ne '.gif') { throw "Non-GIF extension: $staged" }
    if (-not (Test-Path -LiteralPath $staged)) { throw "Staged GIF missing: $staged" }
    if (Test-Path -LiteralPath $staged -PathType Container) { throw "Staged path is directory: $staged" }
    $key = $staged.ToUpperInvariant()
    if ($seen.ContainsKey($key)) { throw "Duplicate staged path: $staged" }
    $seen[$key] = $true
    $fileName = Split-Path -Leaf $staged
    $deleteReviewPath = Get-NormalizedPath (Join-Path $reviewRoot $fileName)
    [void]$planRows.Add([pscustomobject]@{
        Hash = $row.Hash.Trim().ToUpperInvariant(); ShortHash = $row.ShortHash.Trim(); SizeBytes = $row.SizeBytes
        StagedDuplicatePath = $staged; DeleteReviewPath = $deleteReviewPath; DestinationSubfolder = 'images\gif'
        ReviewConfidence = 'MEDIUM'; ReviewReason = $row.DeleteReason.Trim()
    })
}
$planPath = Join-Path $ReportRoot "approved_gif_delete_review_move_plan_$PlanStamp.csv"
$shaPath = Join-Path $ReportRoot "approved_gif_delete_review_move_plan_$PlanStamp.sha256.txt"
$planRows | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
$hash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToUpperInvariant()
Set-Content -LiteralPath $shaPath -Value $hash -Encoding UTF8
Write-Host "GIF review move plan rows: $($planRows.Count)"
Write-Host "TotalBytes: $(($planRows | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum)"
Write-Host "PlanPath=$planPath"; Write-Host "PlanSha256=$hash"; Write-Host "ShaPath=$shaPath"
