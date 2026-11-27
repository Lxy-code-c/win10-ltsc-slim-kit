# ============================================================
# 步骤2：离线精简镜像（核心步骤，已修漏洞版）
#   移除：OneDrive / IE / Windows Media Player / Xbox·游戏栏
#   写入注册表策略：遥测/广告弹窗/建议应用/OneDrive/Cortana/优化
# 以【管理员】身份运行。修改会写回 install.wim。
# 修复点：hive载入校验、组件删除后回查、esd导出校验、残留挂载清理、失败返回非0
# ============================================================
param(
    [string]$WimPath = '',
    [int]$Index = 1
)
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$Work = Join-Path $Root '工作目录'
$Staging = Join-Path $Work '镜像内容'
$Mount = Join-Path $Work 'Mount'
$Global:Fail = 0
$Global:Warn = 0

function Fail([string]$m) { $Global:Fail++; Write-Host "  [失败] $m" -ForegroundColor Red }
function Warn([string]$m) { $Global:Warn++; Write-Host "  [警告] $m" -ForegroundColor Yellow }

# ---- 管理员检查 ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host '[错误] 必须以管理员身份运行本脚本！' -ForegroundColor Red; Read-Host '按回车退出'; exit 1 }

# ---- 清理上次残留（挂载点 / 已载入的 hive）----
if (Test-Path (Join-Path $Mount 'Windows')) {
    Write-Host '[清理] 检测到上次残留的挂载，先丢弃 ...' -ForegroundColor DarkGray
    & DISM.exe /Unmount-Image /MountDir:"$Mount" /Discard 2>$null | Out-Null
}
& reg.exe unload "HKLM\LTSC_SOFT" 2>$null | Out-Null
& reg.exe unload "HKLM\LTSC_DEF"  2>$null | Out-Null

# ---- 定位 wim（若为 esd 先转 wim，导出校验通过后才删除 esd）----
$src = Join-Path $Staging 'sources'
$wim = Join-Path $src 'install.wim'
$esd = Join-Path $src 'install.esd'
if (-not (Test-Path $wim)) {
    if (Test-Path $esd) {
        Write-Host "[0/6] install.esd 需先转为 install.wim ..." -ForegroundColor Cyan
        & DISM.exe /Export-Image /SourceImageFile:"$esd" /SourceIndex:$Index /DestinationImageFile:"$wim" /Compress:max | Out-Host
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $wim)) {
            Fail 'install.esd 转 wim 失败（已保留原 esd，未删除）'
            Read-Host '按回车退出'; exit 1
        }
        Remove-Item $esd -Force
    } else {
        Fail '未找到 install.wim/esd，请先运行 01 脚本'
        Read-Host '按回车退出'; exit 1
    }
}

# ---- 挂载 ----
Write-Host "[1/6] 挂载 WIM（索引 $Index）..." -ForegroundColor Cyan
& DISM.exe /Mount-Image /ImageFile:"$wim" /Index:$Index /MountDir:"$Mount" | Out-Host
if (-not (Test-Path (Join-Path $Mount 'Windows\System32\cmd.exe'))) {
    Fail '挂载失败。请确认：以管理员运行、索引号正确、磁盘空间足够、wim 未被占用'
    Read-Host '按回车退出'; exit 1
}

# ---- 移除 OneDrive（并回查确认）----
Write-Host "[2/6] 移除 OneDrive ..." -ForegroundColor Cyan
try {
    $onePkg = Get-WindowsPackage -Path $Mount -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -match 'OneDrive' }
    if ($onePkg) {
        foreach ($p in $onePkg) {
            Write-Host "  移除包: $($p.PackageName)" -ForegroundColor Yellow
            Remove-WindowsPackage -Path $Mount -PackageName $p.PackageName -NoRestart -ErrorAction SilentlyContinue
        }
        $left = Get-WindowsPackage -Path $Mount -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -match 'OneDrive' }
        if ($left) { Warn "仍有 OneDrive 包未移除：$($left.PackageName -join ', ')" }
        else { Write-Host '  OneDrive 包已移除。' -ForegroundColor Green }
    } else {
        Write-Host '  LTSC 镜像中未发现 OneDrive 包（正常），继续。'
    }
} catch { Warn "OneDrive 处理异常：$($_.Exception.Message)" }

# ---- 移除可选能力：IE / 媒体播放器 / Xbox 游戏栏（并回查）----
Write-Host "[3/6] 移除可选能力（IE / 媒体播放器 / Xbox / 游戏栏）..." -ForegroundColor Cyan
try {
    $caps = Get-WindowsCapability -Path $Mount -ErrorAction SilentlyContinue
    $toRemove = $caps | Where-Object { $_.Name -match 'Internet-Explorer|Media.WindowsMediaPlayer|Xbox' }
    if ($toRemove) {
        foreach ($c in $toRemove) {
            Write-Host "  移除能力: $($c.Name)" -ForegroundColor Yellow
            Remove-WindowsCapability -Path $Mount -Name $c.Name -NoRestart -ErrorAction SilentlyContinue
        }
        $caps2 = Get-WindowsCapability -Path $Mount -ErrorAction SilentlyContinue
        $left = $caps2 | Where-Object { $_.Name -match 'Internet-Explorer|Media.WindowsMediaPlayer|Xbox' }
        if ($left) { Warn "以下能力未能移除（可能受系统保护），如在意可改用第三方工具：$($left.Name -join ', ')" }
        else { Write-Host '  匹配的可选能力已全部移除。' -ForegroundColor Green }
    } else { Write-Host '  未发现匹配的可选能力，跳过。' }
} catch { Warn "能力处理异常：$($_.Exception.Message)" }

# ---- 关闭可选功能（旧镜像 IE/媒体功能走 Feature 通道）----
Write-Host "[4/6] 关闭可选功能（若存在）..." -ForegroundColor Cyan
try {
    $feats = Get-WindowsOptionalFeature -Path $Mount -ErrorAction SilentlyContinue | Where-Object { $_.FeatureName -match 'Internet-Explorer|MediaPlayback' }
    if ($feats) {
        foreach ($f in $feats) {
            Write-Host "  关闭功能: $($f.FeatureName)" -ForegroundColor Yellow
            Disable-WindowsOptionalFeature -Path $Mount -FeatureName $f.FeatureName -NoRestart -ErrorAction SilentlyContinue
        }
    } else { Write-Host '  无可关闭的匹配功能。' }
} catch { Warn "可选功能处理异常：$($_.Exception.Message)" }

# ---- 写入注册表策略（载入失败即报错；始终 finally 卸载）----
Write-Host "[5/6] 写入注册表策略（遥测/广告弹窗/建议应用/OneDrive/Cortana/优化）..." -ForegroundColor Cyan
$cfg  = Join-Path $Mount 'Windows\System32\config\SOFTWARE'
$dflt = Join-Path $Mount 'Windows\System32\config\DEFAULT'
function Set-Hive([string]$hive, [string]$path, [string]$name, [int]$val) {
    & reg.exe add "$hive\$path" /v $name /t REG_DWORD /d $val /f 2>$null | Out-Null
}
try {
    & reg.exe load "HKLM\LTSC_SOFT" $cfg 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'SOFTWARE hive 载入失败，注册表策略将无法写入' }
    & reg.exe load "HKLM\LTSC_DEF" $dflt 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'DEFAULT hive 载入失败，新用户默认优化将无法写入' }

    # 遥测 / 数据收集
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'MaxTelemetry' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
    # 消费者功能 / 建议应用 / 广告ID
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\Privacy' 'DisableAdvertisingId' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0
    # 锁屏 / 聚焦广告
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\Personalization' 'NoLockScreen' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightOnActionCenter' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightOnSettings' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightWindowWelcomeExperience' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\CloudContent' 'AllowTailoredExperiencesWithDiagnosticData' 0
    # 资讯和兴趣 / 搜索建议 / 云推送
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\CurrentVersion\PushNotifications' 'NoCloudApplication' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-314563Enabled' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0
    # 新用户默认优化（DEFAULT 模板）
    Set-Hive 'HKLM\LTSC_DEF'  'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0
    Set-Hive 'HKLM\LTSC_DEF'  'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
    Set-Hive 'HKLM\LTSC_DEF'  'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
    Set-Hive 'HKLM\LTSC_DEF'  'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 0
    Set-Hive 'HKLM\LTSC_DEF'  'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-314563Enabled' 0
    Set-Hive 'HKLM\LTSC_DEF'  'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 0
    Set-Hive 'HKLM\LTSC_DEF'  'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0
    Set-Hive 'HKLM\LTSC_DEF'  'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
    # 浏览器弹窗/广告（Edge、Chrome）
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Edge'    'DefaultPopupsSetting' 2
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Edge'    'AdsSettingForIntrusiveAdsSites' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Google\Chrome'     'DefaultPopupsSetting' 2
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Google\Chrome'     'AdsSettingForIntrusiveAdsSites' 1
    # Cortana / 联网搜索
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
    Set-Hive 'HKLM\LTSC_SOFT' 'Policies\Microsoft\Windows\Windows Search' 'AllowSearchToUseLocation' 0
    # 删除 OneDrive 自启动项（若存在）
    & reg.exe delete "HKLM\LTSC_SOFT\Microsoft\Windows\CurrentVersion\Run" /v OneDrive /f 2>$null | Out-Null
} finally {
    & reg.exe unload "HKLM\LTSC_SOFT" 2>$null | Out-Null
    & reg.exe unload "HKLM\LTSC_DEF"  2>$null | Out-Null
}

# ---- 提交并卸载 ----
Write-Host "[6/6] 提交修改并卸载 WIM ..." -ForegroundColor Cyan
& DISM.exe /Unmount-Image /MountDir:"$Mount" /Commit | Out-Host
if ($LASTEXITCODE -ne 0) { Fail '卸载/提交失败，镜像可能已损坏' }

if ($Global:Fail -gt 0) {
    Write-Host "`n[结果] 存在 $($Global:Fail) 处失败、$($Global:Warn) 处警告，请检查上方红字后再打包。" -ForegroundColor Red
    Read-Host '按回车退出'; exit 1
}
Write-Host "`n精简完成（警告 $($Global:Warn) 处）。下一步运行 03-打包ISO.ps1" -ForegroundColor Green
Read-Host '按回车退出'
