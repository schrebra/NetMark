<#
.SYNOPSIS
    Idempotent installation of NetMark. Extracts publish.zip to C:\Program Files\NetMark 
    and creates/updates a Scheduled Task to auto-start and watchdog it.
#>

[CmdletBinding()]
param(
    # Path to the downloaded publish.zip (defaults to the current user's Downloads folder)
    [string]$ZipPath = "$env:USERPROFILE\Downloads\publish.zip",
    
    # Installation directory
    [string]$InstallDir = "C:\Program Files\NetMark",
    
    # Name of the Scheduled Task
    [string]$TaskName = "NetMarkAutoStart"
)

 $ErrorActionPreference = 'Stop'

# Helper functions for clean output
function Write-Step  { param([string]$m) Write-Host "`n[ .. ] $m" -ForegroundColor Cyan }
function Write-Ok    { param([string]$m) Write-Host "[ OK ] $m" -ForegroundColor Green }
function Write-Info  { param([string]$m) Write-Host "      $m" -ForegroundColor Gray }
function Write-Warn  { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err   { param([string]$m) Write-Host "[ERR ] $m" -ForegroundColor Red }

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " NetMark Installer" -ForegroundColor White
Write-Host "==============================================================" -ForegroundColor Cyan

# ---------------------------------------------------------
# Phase 1: Prerequisites
# ---------------------------------------------------------
Write-Step "Checking Prerequisites..."

# 1. Ensure we are running as Administrator
 $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Err "Administrator rights required."
    Write-Info "This script writes to $InstallDir."
    Write-Info "Please close PowerShell, right-click it, and select 'Run as Administrator'."
    exit 1
}
Write-Ok "Administrator privileges verified."

# 2. Check paths
 $exePath = Join-Path $InstallDir "NetMark.exe"
 $zipExists = Test-Path -LiteralPath $ZipPath
 $exeExists = Test-Path -LiteralPath $exePath

if (-not $zipExists -and -not $exeExists) {
    Write-Err "'publish.zip' not found."
    Write-Info "Expected location: $ZipPath"
    Write-Info "Please download publish.zip from GitHub releases, save it to your Downloads folder, and run this script again."
    exit 1
}

if ($zipExists) {
    Write-Ok "Found 'publish.zip' in Downloads folder."
} else {
    Write-Info "No zip found, but existing NetMark installation detected. Will update task settings."
}

# ---------------------------------------------------------
# Phase 2: File Installation
# ---------------------------------------------------------
if ($zipExists) {
    Write-Step "Installing Files to $InstallDir..."
    
    if (-not (Test-Path -LiteralPath $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Write-Info "Created installation directory."
    }

    # Extract to a temporary directory first so we can handle nested folders
    $tempExtractDir = Join-Path $env:TEMP "NetMark_Extract_$(Get-Random)"
    Write-Info "Extracting archive to temporary location..."
    
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $tempExtractDir -Force
    } catch {
        Write-Err "Failed to extract the zip file."
        throw
    }

    # Check if the zip contained a single root folder (like 'publish' or 'netmark')
    $extractedItems = Get-ChildItem -Path $tempExtractDir
    $sourcePath = $tempExtractDir
    
    if ($extractedItems.Count -eq 1 -and $extractedItems.PSIsContainer) {
        $nestedExe = Join-Path $extractedItems.FullName "NetMark.exe"
        if (Test-Path -LiteralPath $nestedExe) {
            $sourcePath = $extractedItems.FullName
            Write-Info "Detected nested folder '$($extractedItems.Name)'. Flattening structure..."
        }
    }

    Write-Info "Copying files to final destination..."
    Copy-Item -Path (Join-Path $sourcePath "*") -Destination $InstallDir -Recurse -Force

    Write-Info "Cleaning up temporary files and downloaded zip..."
    Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $ZipPath -Force -ErrorAction SilentlyContinue
    
    Write-Ok "Files installed successfully."
}

# Final validation
if (-not (Test-Path -LiteralPath $exePath)) {
    Write-Err "NetMark.exe missing at: $exePath"
    Write-Info "Extraction completed, but the executable was not found. Verify the contents of the zip file."
    exit 1
}

# ---------------------------------------------------------
# Phase 3: Scheduled Task Configuration
# ---------------------------------------------------------
Write-Step "Configuring Scheduled Task Watchdog..."

# Define the Watchdog Action
 $watchdogScript = "if (-not (Get-Process -Name 'NetMark' -ErrorAction SilentlyContinue)) { Start-Process -FilePath '$exePath' -WorkingDirectory '$InstallDir' }"
 $action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -Command `"$watchdogScript`""

# Triggers
 $triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
 $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
 $triggers = @($triggerLogon, $triggerRepeat)

 $settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

 $principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

# Clean up existing task if present
 $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Info "Existing task found. Removing old configuration..."
    if ($existingTask.State -eq 'Running') {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Register new task
Register-ScheduledTask -TaskName $TaskName `
    -Action $action `
    -Trigger $triggers `
    -Settings $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Ok "Task '$TaskName' registered successfully."
Write-Info "Trigger 1: At user logon."
Write-Info "Trigger 2: Every 5 minutes (auto-restart if closed)."

# ---------------------------------------------------------
# Phase 4: Launch
# ---------------------------------------------------------
Write-Step "Launching NetMark..."

 $running = Get-Process -Name "NetMark" -ErrorAction SilentlyContinue
if (-not $running) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Info "Waiting for application to initialize..."
    
    # Wait up to 10 seconds for the single-file exe to extract and launch
    $loops = 0
    do {
        Start-Sleep -Seconds 2
        $running = Get-Process -Name "NetMark" -ErrorAction SilentlyContinue
        $loops++
    } until ($running -or $loops -ge 5)
}

# ---------------------------------------------------------
# Final Summary
# ---------------------------------------------------------
Write-Host "`n==============================================================" -ForegroundColor Cyan
if ($running) {
    Write-Host " INSTALLATION COMPLETE " -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host " NetMark is installed, up to date, and currently running." -ForegroundColor Green
} else {
    Write-Host " INSTALLATION COMPLETE (WITH WARNINGS) " -ForegroundColor Black -BackgroundColor Yellow
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Warn "NetMark did not appear in the process list immediately."
    Write-Info "The task is registered, so Windows may still be launching it."
    Write-Info "If it doesn't appear in a few moments, try launching it manually:"
    Write-Info "  $exePath" -ForegroundColor White
}
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " Install Location : $InstallDir"
Write-Host " Task Name        : $TaskName"
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " To uninstall later, run these commands:" -ForegroundColor Gray
Write-Host "   Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Host "   Remove-Item -Path '$InstallDir' -Recurse -Force"
Write-Host "==============================================================`n" -ForegroundColor Cyan
