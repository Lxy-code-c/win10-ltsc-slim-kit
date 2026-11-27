@echo off
chcp 65001 >nul
title 装机后 - 一键最终优化
echo ==========================================================
echo    Win10 LTSC 装机后 一键最终优化（以管理员运行）
echo    --------------------------------------------------
echo    内容：
echo      1. 电源计划 → 高性能
echo      2. 关闭休眠（释放 C 盘空间、加快关机）
echo      3. 关闭后台/遥测服务（SysMain、DiagTrack、dmwappushservice）
echo      4. 关闭 Windows 搜索索引（可选，注释掉则跳过）
echo      5. 关闭全部视觉动画效果（更流畅）
echo      6. 清理临时文件 + 刷新 DNS
echo    --------------------------------------------------
echo    说明：本脚本更激进，全部操作均可反向恢复，见最后提示。
echo ==========================================================
echo.

:: ---- 管理员检查 ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 请右键本文件 → 以管理员身份运行！
    pause
    exit /b 1
)

:: ---- 1. 电源计划：高性能 ----
echo [1/6] 设置电源计划为「高性能」...
powercfg -setactive SCHEME_MIN >nul 2>&1
echo       已设置（笔记本耗电会略增，可在控制面板改回「平衡」）。

:: ---- 2. 关闭休眠 ----
echo [2/6] 关闭休眠...
powercfg /h off
echo       已关闭（hiberfil.sys 释放）。注意：会同时关闭「快速启动」，开机可能慢几秒。

:: ---- 3. 后台/遥测服务 ----
echo [3/6] 关闭后台/遥测服务...
for %%S in (SysMain DiagTrack dmwappushservice) do (
    sc config "%%S" start= disabled >nul 2>&1
    net stop "%%S" >nul 2>&1
    echo       - %%S  已禁用
)

:: ---- 4. 关闭 Windows 搜索索引（注释掉可跳过）----
echo [4/6] Windows 搜索索引...
rem 若你不常使用「开始菜单搜索」，可去掉下面两行的 rem 启用：
rem sc config WSearch start= disabled >nul 2>&1
rem net stop WSearch >nul 2>&1
echo       已保留默认开启（搜索仍然可用）。如需禁用，打开本文件去掉第4节前的 rem。

:: ---- 5. 关闭全部视觉动画效果 ----
echo [5/6] 关闭视觉动画效果（当前用户）...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f >nul
echo       已设为「最佳性能」。注意：会连带关闭字体平滑(ClearType)，文字可能略发虚，可在性能选项改回。

:: ---- 6. 清理临时文件 + 刷新 DNS ----
echo [6/6] 清理临时文件...
del /f /q "%TEMP%\*" >nul 2>&1
del /f /q "C:\Windows\Temp\*" >nul 2>&1
echo       临时文件已清理。
ipconfig /flushdns >nul 2>&1
echo       DNS 缓存已刷新。

echo.
echo ==========================================================
echo   完成！恢复方法（需要时）：
echo     · 电源计划：控制面板 → 电源选项 → 改回「平衡」
echo     · 休眠：     管理员运行  powercfg /h on
echo     · 服务：     管理员运行  sc config SysMain start= auto
echo                            sc config DiagTrack start= auto
echo                            sc config dmwappushservice start= auto
echo     · 动画：     设置 → 辅助功能 → 视觉效果 → 重新打开
echo     · 搜索索引： 若启用了禁用，同样用 sc config WSearch start= auto 还原
echo ==========================================================
pause
