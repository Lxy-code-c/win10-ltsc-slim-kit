# ============================================================
# 步骤3：把精简后的 install.wim 打包成可启动 ISO（已修漏洞版）
# 需 Windows ADK 的 oscdimg；修复点：管理员检查、含空格路径保护、
#       oscdimg 退出码校验、产物大小校验
# ============================================================
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Staging = Join-Path $Root '工作目录\镜像内容'

# ---- 管理员检查（oscdimg 读写与临时文件需要）----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host '[错误] 必须以管理员身份运行本脚本！' -ForegroundColor Red; Read-Host '按回车退出'; exit 1 }

if (-not (Test-Path (Join-Path $Staging 'sources\install.wim'))) {
    Write-Host '[错误] 未找到精简后的 install.wim，请先运行 02 脚本。' -ForegroundColor Red
    Read-Host '按回车退出'; exit 1
}

# 1) 注入应答文件
Write-Host "[1/4] 注入 autounattend.xml ..." -ForegroundColor Cyan
$xml = Join-Path $Root 'autounattend.xml'
Copy-Item $xml (Join-Path $Staging 'autounattend.xml') -Force
Copy-Item $xml (Join-Path $Staging 'sources\autounattend.xml') -Force

# 2) 定位 oscdimg
Write-Host "[2/4] 查找 oscdimg ..." -ForegroundColor Cyan
$oscdimg = $null
$candidates = @(
    'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\oscdimg\oscdimg.exe',
    'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\oscdimg\oscdimg.exe',
    'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\arm64\oscdimg\oscdimg.exe'
)
foreach ($c in $candidates) { if (Test-Path $c) { $oscdimg = $c; break } }
if (-not $oscdimg) {
    Write-Host '[提示] 未找到 oscdimg。请安装 Windows ADK（含 Deployment Tools）后重跑。' -ForegroundColor Yellow
    Write-Host '       下载：https://learn.microsoft.com/windows-hardware/get-started/adk-install' -ForegroundColor Yellow
    Read-Host '按回车退出'; exit 1
}
Write-Host "  使用 oscdimg: $oscdimg"

# 3) 定位引导文件
$etfsboot = Join-Path $Staging 'boot\etfsboot.com'
$efisys   = Join-Path $Staging 'efi\microsoft\boot\efisys.bin'
if (-not (Test-Path $etfsboot) -or -not (Test-Path $efisys)) {
    Write-Host '[错误] 缺少引导文件（boot\etfsboot.com 或 efi\...\efisys.bin），请重新运行 01 解压。' -ForegroundColor Red
    Read-Host '按回车退出'; exit 1
}

# 4) 打包（含空格路径保护）
$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
$out = Join-Path $Root "Win10LTSC_精简版_$stamp.iso"
# oscdimg 的 -bootdata 参数内部无法安全处理空格路径，故若 $Staging 含空格则中止并提示
if ($Staging -match '\s') {
    Write-Host "[错误] 工作目录路径包含空格，oscdimg 的 -bootdata 参数会解析失败：" -ForegroundColor Red
    Write-Host "        $Staging" -ForegroundColor Red
    Write-Host '        请把整个工具包移动到不含空格/中文的特殊符号路径（如 D:\LTSC）。' -ForegroundColor Yellow
    Read-Host '按回车退出'; exit 1
}
Write-Host "[3/4] 打包 ISO -> $out" -ForegroundColor Cyan
Write-Host '      （需要几分钟，请勿关闭窗口）' -ForegroundColor DarkYellow
$label = 'LTSC_LITE'
& $oscdimg -m -o -u2 -udfver102 `
    "-bootdata:2#p0,e,b$etfsboot#pEF,e,b$efisys" `
    "-l$label" `
    "$Staging" "$out" | Out-Host
$code = $LASTEXITCODE

if ($code -eq 0 -and (Test-Path $out)) {
    $gb = [math]::Round((Get-Item $out).Length / 1GB, 2)
    Write-Host "`n[4/4] 打包成功！大小 $gb GB" -ForegroundColor Green
    Write-Host "  输出文件：$out" -ForegroundColor Green
} else {
    Write-Host "`n[错误] 打包失败（oscdimg 退出码 $code），请检查上方输出。" -ForegroundColor Red
    Read-Host '按回车退出'; exit 1
}
Read-Host '按回车退出'
