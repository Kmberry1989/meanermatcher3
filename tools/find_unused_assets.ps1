Param(
    [switch]$Move,
    [string]$UnusedFolder = "Assets/_unused"
)

$ErrorActionPreference = 'Stop'

# Gather project files to scan for res:// references
$includeExt = @('*.gd','*.tscn','*.tres','*.cfg','*.json','project.godot')
$files = Get-ChildItem -Recurse -File -Include $includeExt | Where-Object { $_.FullName -notmatch '\\docs\\' }
$regex = 'res://[^\s"\)\]\}\\>]+'
$used = New-Object System.Collections.Generic.HashSet[string]

foreach ($f in $files) {
    try {
        $text = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
    } catch { continue }
    foreach ($m in [regex]::Matches($text, $regex)) { $null = $used.Add($m.Value) }
}

# Enumerate all files under Assets (excluding known special folders)
$assetRoot = Join-Path $PWD 'Assets'
if (-not (Test-Path $assetRoot)) { Write-Output 'No Assets folder found.'; exit 0 }
$allAssets = Get-ChildItem -Recurse -File -Path $assetRoot | Where-Object {
    $_.FullName -notmatch '\\_backup_originals\\' -and $_.FullName -notmatch '\\_unused\\'
}

function To-ResPath($path) {
    $rel = Resolve-Path -LiteralPath $path | ForEach-Object { $_.Path.Replace($PWD.Path + '\\','') }
    $rel = $rel -replace '\\','/'
    return 'res://' + $rel
}

$candidates = @()
foreach ($a in $allAssets) {
    $res = To-ResPath $a.FullName
    if (-not $used.Contains($res)) { $candidates += $a }
}

Write-Host ("Found {0} candidate unused files" -f $candidates.Count)
if (-not $Move) {
    $candidates | Select-Object FullName | ForEach-Object { $_.FullName }
    Write-Host "Run with -Move to relocate these files to '$UnusedFolder'."
    exit 0
}

# Create target folder
if (-not (Test-Path -LiteralPath $UnusedFolder)) { New-Item -ItemType Directory -Path $UnusedFolder | Out-Null }

# Move assets and their .import sidecars together
foreach ($a in $candidates) {
    $dest = Join-Path $UnusedFolder $a.Name
    try {
        Move-Item -LiteralPath $a.FullName -Destination $dest -Force
        $importSidecar = "$($a.FullName).import"
        if (Test-Path -LiteralPath $importSidecar) {
            Move-Item -LiteralPath $importSidecar -Destination "$dest.import" -Force
        }
        Write-Host ("Moved: {0}" -f $a.FullName)
    } catch {
        Write-Warning ("Failed to move: {0} -> {1} ({2})" -f $a.FullName, $dest, $_.Exception.Message)
    }
}

Write-Host "Done. Review '$UnusedFolder' and test in editor."

