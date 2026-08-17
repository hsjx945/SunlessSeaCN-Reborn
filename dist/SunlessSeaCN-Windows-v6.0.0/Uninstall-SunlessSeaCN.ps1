param(
    [string]$GameRoot,
    [switch]$NonInteractive
)
$ErrorActionPreference = "Stop"
if (-not $GameRoot) {
    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $GameRoot = @($env:SUNLESS_SEA_GAME_ROOT, (Join-Path $pf86 "Steam\steamapps\common\SunlessSea"), (Join-Path $env:ProgramFiles "Steam\steamapps\common\SunlessSea")) | Where-Object { $_ -and (Test-Path (Join-Path $_ ".sunlessseacn-install.json")) } | Select-Object -First 1
}
if (-not $GameRoot) { throw "找不到安装清单。请设置 SUNLESS_SEA_GAME_ROOT 或传入 -GameRoot。" }
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$manifestPath = Join-Path $GameRoot ".sunlessseacn-install.json"
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "未找到安装清单: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$removed = 0
$skipped = 0
foreach ($record in $manifest.Files) {
    $root = if ($record.Scope -eq "game") { $manifest.GameRoot } else { $manifest.DataRoot }
    $destination = Join-Path $root $record.Relative
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($hash -eq $record.Hash) { Remove-Item -LiteralPath $destination -Force; $removed++ }
        else { Write-Host "保留用户已修改文件: $destination"; $skipped++ }
    }
}
if ($manifest.BackupGame -and (Test-Path -LiteralPath $manifest.BackupGame)) {
    Get-ChildItem -LiteralPath $manifest.BackupGame -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($manifest.BackupGame.Length).TrimStart("\")
        $destination = Join-Path $manifest.GameRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }
    Write-Host "已恢复游戏文件备份: $($manifest.BackupGame)"
}
if ($manifest.BackupData -and (Test-Path -LiteralPath $manifest.BackupData)) {
    Get-ChildItem -LiteralPath $manifest.BackupData -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($manifest.BackupData.Length).TrimStart("\")
        $destination = Join-Path $manifest.DataRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }
    Write-Host "已恢复文本数据备份: $($manifest.BackupData)"
}
Remove-Item -LiteralPath $manifestPath -Force
Write-Host "卸载完成。删除文件: $removed；因用户修改而保留: $skipped。备份目录未删除，可手动清理。"
