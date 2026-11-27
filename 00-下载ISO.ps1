# ============================================================
# 步骤0：获取原版 Win10 Enterprise LTSC 2021 中文版 ISO
# 说明：微软官方免费原版通道（评估中心）和所有镜像站都有人机验证，
#       脚本无法完全静默下载，因此本脚本采用「自动优先 + 官方一键兜底」：
#         [1] 自动打开微软官方评估中心，按提示选一次即可（推荐，正版）
#         [2] 你已有原版ISO → 放进本文件夹，脚本自动校验并改名
#         [3] 你有直链 → 脚本用 BITS 自动下载到本文件夹
#   下载完成后本脚本会校验 ISO 完整性（大小 + ISO9660 标识）。
# ============================================================
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Target = Join-Path $Root 'LTSC.iso'

# 已有则跳过
if (Test-Path $Target) {
    Write-Host "已存在 $Target，跳过下载。" -ForegroundColor Green
    Read-Host '按回车继续'; exit 0
}

function Test-ISO([string]$path, [long]$minGB = 3) {
    try {
        $fi = Get-Item $path
        if ($fi.Length -lt ($minGB * 1GB)) { return $false }
        $fs = [System.IO.File]::OpenRead($path)
        $buf = New-Object byte[] 5
        $fs.Seek(0x8001, [System.IO.SeekOrigin]::Begin) | Out-Null
        $fs.Read($buf, 0, 5) | Out-Null
        $fs.Close()
        return ([System.Text.Encoding]::ASCII.GetString($buf) -eq 'CD001')
    } catch { return $false }
}

Write-Host "未找到 $Target" -ForegroundColor Yellow
Write-Host "请选择获取原版 ISO 的方式：" -ForegroundColor Cyan
Write-Host "  [1] 打开微软官方评估中心下载（推荐，正版，需一次人工点击）"
Write-Host "  [2] 我已下载/已有原版 ISO，放到本文件夹里"
Write-Host "  [3] 我有一个直链，用脚本自动下载"
$sel = Read-Host "请输入 1 / 2 / 3"

if ($sel -eq '1') {
    $url = 'https://www.microsoft.com/zh-cn/evalcenter/evaluate-windows-10-enterprise'
    Write-Host "`n正在打开微软官方评估中心 ..." -ForegroundColor Cyan
    Start-Process $url
    Write-Host @"

请在浏览器里按下面步骤选一次：
  1) 勾选 Windows 10 Enterprise -> 点「继续 / Continue」
  2) 语言选「中文（简体）Chinese (Simplified)」, 位宽选「64 位 / 64-bit」
  3) 找到「Enterprise LTSC」那一行，点「下载 / Download」
  4) 浏览器会自动开始下载 ISO（约 4GB，耐心等待）
  5) 下载完成后，把 ISO 文件放到本文件夹，并改名为：  LTSC.iso
"@ -ForegroundColor Yellow
    $ok = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 10
        if (Test-Path $Target) { $ok = $true; break }
    }
    if (-not $ok) { Write-Host "[提示] 未检测到 LTSC.iso，请手动把它放进来后重跑 一键制作.bat。" -ForegroundColor Yellow; Read-Host '按回车退出'; exit 1 }
} elseif ($sel -eq '2') {
    Write-Host "`n请把你已有的原版 ISO 放到本文件夹，改名为  LTSC.iso，然后重跑 一键制作.bat。" -ForegroundColor Yellow
    $ok = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 10
        if (Test-Path $Target) { $ok = $true; break }
    }
    if (-not $ok) { Read-Host '按回车退出'; exit 1 }
} elseif ($sel -eq '3') {
    $dl = Read-Host "`n请输入 ISO 直链（http/https）"
    if ($dl) {
        Write-Host "正在用 BITS 自动下载（约 4GB，请勿关闭窗口）..." -ForegroundColor Cyan
        try {
            Start-BitsTransfer -Source $dl -Destination $Target -DisplayName '下载 LTSC ISO'
        } catch {
            Write-Host "BITS 下载失败：$($_.Exception.Message)" -ForegroundColor Red
            Write-Host "可改用浏览器直接打开该链接下载。" -ForegroundColor Yellow
            Read-Host '按回车退出'; exit 1
        }
    } else { Write-Host "未输入链接。" -ForegroundColor Red; Read-Host '按回车退出'; exit 1 }
} else {
    Write-Host "无效选择，退出。" -ForegroundColor Red
    Read-Host '按回车退出'; exit 1
}

# 校验
if (Test-Path $Target) {
    if (Test-ISO $Target) {
        $gb = [math]::Round((Get-Item $Target).Length / 1GB, 2)
        Write-Host "`n[通过] LTSC.iso 校验成功（大小 $gb GB，ISO9660 标识正确）。" -ForegroundColor Green
        Write-Host "下一步运行 01-解压镜像.ps1。" -ForegroundColor Green
    } else {
        Write-Host "`n[警告] LTSC.iso 校验未通过：可能不是有效 ISO 或文件不完整。" -ForegroundColor Red
        Write-Host "请确认下载的是完整 ISO 镜像，然后重跑本脚本。" -ForegroundColor Yellow
    }
}
Read-Host '按回车退出'
