@echo off
chcp 65001 >nul
title 可选：Hosts 广告/弹窗域名拦截（网络层）
echo ==============================================
echo   此脚本为【可选】网络层广告拦截
echo   作用：屏蔽常见广告/追踪域名（横幅、弹窗、追踪）
echo   不影响正常网页浏览；已在修改前自动备份 hosts
echo ==============================================
echo.

:: 检查管理员
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 请右键本文件 → 以管理员身份运行！
    pause
    exit /b 1
)

set "HOSTS=%SystemRoot%\System32\drivers\etc\hosts"

:: 备份（只在第一次备份，不覆盖已有备份）
if not exist "%HOSTS%.bak" copy /y "%HOSTS%" "%HOSTS%.bak" >nul

:: 若已写入过本段则跳过，避免重复
findstr /c:"LTSC-AdBlock" "%HOSTS%" >nul 2>&1
if %errorlevel% equ 0 (
    echo [提示] 已安装过广告拦截，无需重复执行。
    pause
    exit /b 0
)

:: 写入前先确认 hosts 可写（有些系统/杀软会锁 hosts）
echo. >> "%HOSTS%"
if errorlevel 1 (
    echo [错误] 无法写入 hosts（可能被只读属性或杀毒软件锁定）。
    echo        请确认文件可写后重试：%HOSTS%
    pause
    exit /b 1
)

set "COUNT=15"
echo # === LTSC-AdBlock 广告域名拦截（删除本段即可还原）=== >> "%HOSTS%"
echo 0.0.0.0 doubleclick.net >> "%HOSTS%"
echo 0.0.0.0 ad.doubleclick.net >> "%HOSTS%"
echo 0.0.0.0 pubads.g.doubleclick.net >> "%HOSTS%"
echo 0.0.0.0 googlesyndication.com >> "%HOSTS%"
echo 0.0.0.0 googleadservices.com >> "%HOSTS%"
echo 0.0.0.0 googletagservices.com >> "%HOSTS%"
echo 0.0.0.0 adservice.google.com >> "%HOSTS%"
echo 0.0.0.0 adnxs.com >> "%HOSTS%"
echo 0.0.0.0 amazon-adsystem.com >> "%HOSTS%"
echo 0.0.0.0 mopub.com >> "%HOSTS%"
echo 0.0.0.0 scorecardresearch.com >> "%HOSTS%"
echo 0.0.0.0 criteo.com >> "%HOSTS%"
echo 0.0.0.0 taboola.com >> "%HOSTS%"
echo 0.0.0.0 outbrain.com >> "%HOSTS%"
echo 0.0.0.0 adsafeprotected.com >> "%HOSTS%"

:: 校验是否真的写进去了
findstr /c:"doubleclick.net" "%HOSTS%" >nul 2>&1
if errorlevel 1 (
    echo [警告] 检测到写入可能不完整，请检查 %HOSTS% 内容。
) else (
    echo [完成] 已写入 %COUNT% 条广告域名拦截。
)

ipconfig /flushdns >nul 2>&1
echo        DNS 缓存已刷新。
echo        如需还原：删除 hosts 中「LTSC-AdBlock」那段，或将 %HOSTS%.bak 覆盖回去。
pause
