# ============================================================
# 步骤1：解压 Win10 LTSC 中文版 ISO 到 工作目录（已修漏洞版）
# 修复点：盘符获取更可靠、失败路径也卸载ISO、清只读属性、管理员检查
# ============================================================
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Work = Join-Path $Root '工作目录'
$Staging = Join-Path $Work '镜像内容'
$Mount = Join-Path $Work 'Mount'
$Iso = Join-Path $Root 'LTSC.iso'

# ---- 管理员检查 ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host '[错误] 必须以管理员身份运行本脚本！' -ForegroundColor Red; Read-Host '按回车退出'; exit 1 }

# 清理并重建工作目录
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Staging -Force | Out-Null
New-Item -ItemType Directory -Path $Mount -Force | Out-Null

# 定位 ISO
if (-not (Test-Path $Iso)) {
    Write-Host "未找到 $Iso" -ForegroundColor Yellow
    $Iso = Read-Host '请输入 Win10 LTSC 中文版 ISO 的完整路径'
}
if (-not (Test-Path $Iso)) { Write-Host "[错误] 找不到 ISO：$Iso" -ForegroundColor Red; Read-Host '按回车退出'; exit 1 }

# 挂载 ISO 并获取盘符（用 Get-DiskImage 取卷更可靠，失败则回退）
Write-Host "[1/3] 挂载 ISO ..." -ForegroundColor Cyan
$img = Mount-DiskImage -ImagePath $Iso -PassThru
Start-Sleep -Seconds 2
$dl = $null
try { $dl = (Get-DiskImage -ImagePath $Iso | Get-Volume).DriveLetter } catch { }
if (-not $dl) { try { $dl = ($img | Get-Volume).DriveLetter } catch { } }
if (-not $dl) {
    Write-Host '[错误] 未能获取 ISO 盘符' -ForegroundColor Red
    Dismount-DiskImage -ImagePath $Iso | Out-Null
    Read-Host '按回车退出'; exit 1
}
$drive = "$dl`:\"
Write-Host "  已挂载到 $drive"

# 复制整个镜像内容（含 boot 引导文件，打包 ISO 时必须）
Write-Host "[2/3] 复制镜像内容（约 4GB，请耐心等待）..." -ForegroundColor Cyan
try {
    Copy-Item -Path (Join-Path $drive '*') -Destination $Staging -Recurse -Force
} catch {
    Write-Host "[错误] 复制失败：$($_.Exception.Message)" -ForegroundColor Red
    Dismount-DiskImage -ImagePath $Iso | Out-Null
    Read-Host '按回车退出'; exit 1
}

# 检查 install.wim / install.esd
$src = Join-Path $Staging 'sources'
$haveWim = Test-Path (Join-Path $src 'install.wim')
$haveEsd = Test-Path (Join-Path $src 'install.esd')
if ($haveWim) { Write-Host '  找到 install.wim' }
elseif ($haveEsd) { Write-Host '  找到 install.esd（下一步会自动转成 wim）' }
else {
    Write-Host '[错误] 未在 sources 下找到 install.wim 或 install.esd' -ForegroundColor Red
    Dismount-DiskImage -ImagePath $Iso | Out-Null
    Read-Host '按回车退出'; exit 1
}

# 卸载 ISO
Write-Host "[3/3] 卸载 ISO ..." -ForegroundColor Cyan
Dismount-DiskImage -ImagePath $Iso | Out-Null

# 清除复制自只读ISO带来的只读属性，否则 DISM 无法挂载/写入
foreach ($f in @('install.wim','install.esd')) {
    $p = Join-Path $src $f
    if (Test-Path $p) { Set-ItemProperty -Path $p -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue }
}

Write-Host "`n完成！下一步运行 02-一键精简.ps1" -ForegroundColor Green
Read-Host '按回车退出'
