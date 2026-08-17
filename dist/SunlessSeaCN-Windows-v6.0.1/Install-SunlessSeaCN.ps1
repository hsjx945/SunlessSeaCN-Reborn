param(
    [string]$GameRoot,
    [string]$DataRoot,
    [switch]$NonInteractive
)
$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PayloadRoot = Join-Path $ScriptRoot "payload"

function Get-DefaultGameRoot {
    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $candidates = @(
        $env:SUNLESS_SEA_GAME_ROOT,
        (Join-Path $pf86 "Steam\steamapps\common\SunlessSea"),
        (Join-Path $env:ProgramFiles "Steam\steamapps\common\SunlessSea"),
        "E:\Program Files (x86)\Steam\steamapps\common\SunlessSea"
    ) | Where-Object { $_ -and (Test-Path (Join-Path $_ "Sunless Sea.exe")) }
    if ($candidates) { return $candidates[0] }
    if ($NonInteractive) { throw "找不到 Sunless Sea 安装目录。请设置 SUNLESS_SEA_GAME_ROOT 或传入 -GameRoot。" }
    return Read-Host "请输入 Sunless Sea 游戏目录（包含 Sunless Sea.exe）"
}

if (-not $GameRoot) { $GameRoot = Get-DefaultGameRoot }
if (-not (Test-Path (Join-Path $GameRoot "Sunless Sea.exe"))) { throw "不是有效的 Sunless Sea 游戏目录: $GameRoot" }
if (-not $DataRoot) { $DataRoot = Join-Path $env:USERPROFILE "AppData\LocalLow\Failbetter Games\Sunless Sea" }
$DataRoot = [IO.Path]::GetFullPath($DataRoot)
$GameRoot = [IO.Path]::GetFullPath($GameRoot)

# Reinstalling should not back up the already-installed translation itself.
# Remove the previous package files (and restore its original backup) first.
$oldManifestPath = Join-Path $GameRoot ".sunlessseacn-install.json"
if (Test-Path -LiteralPath $oldManifestPath) {
    $oldManifest = Get-Content -LiteralPath $oldManifestPath -Raw | ConvertFrom-Json
    foreach ($oldRecord in $oldManifest.Files) {
        $oldRoot = if ($oldRecord.Scope -eq "game") { $oldManifest.GameRoot } else { $oldManifest.DataRoot }
        $oldDestination = Join-Path $oldRoot $oldRecord.Relative
        if (Test-Path -LiteralPath $oldDestination -PathType Leaf) {
            $oldHash = (Get-FileHash -LiteralPath $oldDestination -Algorithm SHA256).Hash
            if ($oldHash -eq $oldRecord.Hash) { Remove-Item -LiteralPath $oldDestination -Force }
        }
    }
    foreach ($pair in @(
        @($oldManifest.BackupGame, $oldManifest.GameRoot),
        @($oldManifest.BackupData, $oldManifest.DataRoot)
    )) {
        $oldBackup = $pair[0]; $oldRoot = $pair[1]
        if ($oldBackup -and (Test-Path -LiteralPath $oldBackup)) {
            Get-ChildItem -LiteralPath $oldBackup -Recurse -File | ForEach-Object {
                $oldRelative = $_.FullName.Substring($oldBackup.Length).TrimStart("\")
                $oldDestination = Join-Path $oldRoot $oldRelative
                New-Item -ItemType Directory -Force -Path (Split-Path $oldDestination -Parent) | Out-Null
                Copy-Item -LiteralPath $_.FullName -Destination $oldDestination -Force
            }
        }
    }
    Remove-Item -LiteralPath $oldManifestPath -Force
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupGame = Join-Path $GameRoot "SunlessSeaCN-backup-$stamp"
$backupData = Join-Path (Split-Path $DataRoot -Parent) "SunlessSeaCN-backup-$stamp"
$records = @()
$backupCreated = $false

function Copy-PayloadFile([IO.FileInfo]$Source, [string]$Scope, [string]$Relative, [string]$DestinationRoot, [string]$BackupRoot) {
    $destination = Join-Path $DestinationRoot $Relative
    if (Test-Path -LiteralPath $destination) {
        $backupDestination = Join-Path $BackupRoot $Relative
        New-Item -ItemType Directory -Force -Path (Split-Path $backupDestination -Parent) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backupDestination -Force
        $script:backupCreated = $true
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath $Source.FullName -Destination $destination -Force
    $hash = (Get-FileHash -LiteralPath $Source.FullName -Algorithm SHA256).Hash
    $script:records += [pscustomobject]@{ Scope = $Scope; Relative = $Relative; Hash = $hash }
}

foreach ($source in Get-ChildItem -LiteralPath (Join-Path $PayloadRoot "game") -Recurse -File) {
    $relative = $source.FullName.Substring((Join-Path $PayloadRoot "game").Length).TrimStart("\")
    Copy-PayloadFile $source "game" $relative $GameRoot $backupGame
}
foreach ($source in Get-ChildItem -LiteralPath (Join-Path $PayloadRoot "data") -Recurse -File) {
    $relative = $source.FullName.Substring((Join-Path $PayloadRoot "data").Length).TrimStart("\")
    Copy-PayloadFile $source "data" $relative $DataRoot $backupData
}

$manifest = [pscustomobject]@{
    Package = "SunlessSeaCN"
    Version = "6.0.0"
    InstalledAt = (Get-Date).ToString("o")
    GameRoot = $GameRoot
    DataRoot = $DataRoot
    BackupGame = $(if ($backupCreated) { $backupGame } else { $null })
    BackupData = $(if ($backupCreated) { $backupData } else { $null })
    Files = $records
}
$manifestPath = Join-Path $GameRoot ".sunlessseacn-install.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host "Sunless Sea 中文补丁已安装。"
Write-Host "游戏目录: $GameRoot"
Write-Host "数据目录: $DataRoot"
if ($backupCreated) { Write-Host "已有文件已备份到: $backupGame / $backupData" }
