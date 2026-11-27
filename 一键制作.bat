@echo off
chcp 65001 >nul
setlocal
title LTSC 一键精简镜像工具包

:: ---- 自动提权到管理员（否则 01/02/03 的挂载与DISM会失败）----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 正在请求管理员权限 ...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ==============================================
echo   Win10 LTSC 一键精简镜像制作（管理员运行）
echo ==============================================
echo.
echo 请确认：
echo   1. 已安装 Windows ADK（用于打包 ISO，没有也能先跑到第2步）
echo   2. 若本文件夹还没有 LTSC.iso，会自动进入下载引导
echo.
pause

if exist "%~dp0LTSC.iso" goto have_iso
echo.
echo [步骤 0/4] 本文件夹没有 LTSC.iso，开始获取原版 ISO ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp000-下载ISO.ps1"
if not exist "%~dp0LTSC.iso" ( echo 未取得 ISO，退出 & pause & exit /b 1 )
:have_iso

echo.
echo [步骤 1/4] 解压镜像 ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp001-解压镜像.ps1"
if errorlevel 1 ( echo 解压失败，按任意键退出 & pause >nul & exit /b 1 )

echo.
echo [步骤 2/4] 一键精简（移除 OneDrive/IE/媒体播放器/游戏栏 + 关闭遥测/广告）...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp002-一键精简.ps1"
if errorlevel 1 ( echo 精简存在失败，已中止，未打包。 & pause >nul & exit /b 1 )

echo.
echo [步骤 3/4] 打包 ISO ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp003-打包ISO.ps1"
if errorlevel 1 ( echo 打包失败。 & pause >nul & exit /b 1 )

echo.
echo 全部完成。ISO 已生成在本文件夹。按任意键退出。
pause >nul
