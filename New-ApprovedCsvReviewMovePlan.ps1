[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$InventoryCsvPath = 'C:\Users\jim\Desktop\DrivePathInventory\staged_duplicate_inventory_20260703-221211.csv',
    [ValidateNotNullOrEmpty()]
    [string]$ReportRoot = 'C:\Users\jim\Desktop\DrivePathInventory',
    [ValidateNotNullOrEmpty()]
    [string]$PlanStamp = '20260704',
    [ValidateNotNullOrEmpty()]
    [string]$StagedCsvRoot = 'I:\_RECOVERY_WORKBENCH\04_DUPLICATES_STAGED\recovered_to_realname\data\csv',
    [ValidateNotNullOrEmpty()]
    [string]$DeleteReviewCsvRoot = 'I:\_RECOVERY_WORKBENCH\05_DELETE_REVIEW\medium_review\csv'
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { return $Path.Trim() }
}
$stagedRoot = Get-NormalizedPath $StagedCsvRoot
$reviewRoot = Get-NormalizedPath $DeleteReviewCsvRoot
$inv = @(Import-Csv -LiteralPath $InventoryCsvPath)
$csvRows = @($inv | Where-Object { $_.DestinationSubfolder -eq 'data\csv' } | Sort-Object StagedDuplicatePath)
if ($csvRows.Count -eq 0) { throw 'No data\csv rows found in inventory.' }
$planRows = New-Object System.Collections.Generic.List[object]
$seen = @{}
foreach ($row in $csvRows) {
    $staged = Get-NormalizedPath $row.StagedDuplicatePath
    if (-not $staged.StartsWith($stagedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Staged path outside CSV root: $staged" }
    if ([IO.Path]::GetExtension($staged).ToLowerInvariant() -ne '.csv') { throw "Non-CSV extension: $staged" }
    if (-not (Test-Path -LiteralPath $staged)) { throw "Staged CSV missing: $staged" }
    if (Test-Path -LiteralPath $staged -PathType Container) { throw "Staged path is directory: $staged" }
    $key = $staged.ToUpperInvariant()
    if ($seen.ContainsKey($key)) { throw "Duplicate staged path: $staged" }
    $seen[$key] = $true
    $fileName = Split-Path -Leaf $staged
    $deleteReviewPath = Get-NormalizedPath (Join-Path $reviewRoot $fileName)
    [void]$planRows.Add([pscustomobject]@{
        Hash = $row.Hash.Trim().ToUpperInvariant(); ShortHash = $row.ShortHash.Trim(); SizeBytes = $row.SizeBytes
        StagedDuplicatePath = $staged; DeleteReviewPath = $deleteReviewPath; DestinationSubfolder = 'data\csv'
        ReviewConfidence = 'MEDIUM'; ReviewReason = $row.DeleteReason.Trim()
    })
}
$planPath = Join-Path $ReportRoot "approved_csv_delete_review_move_plan_$PlanStamp.csv"
$shaPath = Join-Path $ReportRoot "approved_csv_delete_review_move_plan_$PlanStamp.sha256.txt"
$planRows | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
$hash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToUpperInvariant()
Set-Content -LiteralPath $shaPath -Value $hash -Encoding UTF8
Write-Host "CSV review move plan rows: $($planRows.Count)"
Write-Host "TotalBytes: $(($planRows | ForEach-Object { [int64]$_.SizeBytes } | Measure-Object -Sum).Sum)"
Write-Host "PlanPath=$planPath"; Write-Host "PlanSha256=$hash"; Write-Host "ShaPath=$shaPath"
