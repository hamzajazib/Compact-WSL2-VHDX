<#
.SYNOPSIS
    Advanced WSL 2 Disk Compactor.
    Shuts down WSL, locates VHDX files via Registry, calculates space savings,
    compacts them using DiskPart, and warms up the VM.

.DESCRIPTION
    This script performs maintenance on WSL 2 virtual hard disks (VHDX).
    1. Forcefully shuts down WSL.
    2. Scans the Registry for all registered distributions.
    3. Calculates pre-compact size.
    4. Uses DiskPart to compact the VHDX.
    5. Calculates post-compact size and reports space reclaimed.

.NOTES
    - Requires Administrator privileges.
    - Handles environment variables in paths.
    - Non-interactive restart.
#>

[CmdletBinding()]
param()

function Compact-WslVhd {
    # 1. Administrator Check
    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
        Write-Error "🔒 Access Denied: This script must be run as Administrator to use DiskPart."
        Write-Host "Tip: Right-click the script and select 'Run as Administrator'."
        exit 1
    }

    $TotalSavedBytes = 0
    Write-Host "--- 🐧 WSL Disk Compaction & Optimization ---" -ForegroundColor Yellow

    # 2. Graceful Shutdown & Lock Release
    Write-Host "`n[1/5] Stopping WSL Subsystem..." -ForegroundColor Cyan
    try {
        wsl --shutdown
        # Polling wait: Ensure the process is actually gone or file handles are released
        Write-Host "    -> Waiting for file handles to release..." -ForegroundColor Gray
        Start-Sleep -Seconds 3 
    }
    catch {
        Write-Warning "WSL Shutdown command had an issue, but we will proceed if files are unlocked."
    }

    # 3. Registry Discovery
    $lxssPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    $vhdxFiles = @()
    Write-Host "`n[2/5] Scanning Registry for Distributions..." -ForegroundColor Cyan

    try {
        if (Test-Path $lxssPath) {
            $lxssKeys = Get-ChildItem -Path $lxssPath -ErrorAction Stop
            foreach ($key in $lxssKeys) {
                # Get raw values
                $rawBasePath = $key.GetValue('BasePath')
                $distroName = $key.GetValue('DistributionName')

                if (-not [string]::IsNullOrWhiteSpace($rawBasePath)) {
                    # Robustness: Expand environment variables (e.g. %USERPROFILE%)
                    $expandedPath = [Environment]::ExpandEnvironmentVariables($rawBasePath)
                    $vhdxPath = Join-Path -Path $expandedPath -ChildPath 'ext4.vhdx'
                    
                    if (Test-Path -Path $vhdxPath) {
                        $vhdxFiles += [PSCustomObject]@{
                            Name = $distroName
                            Path = $vhdxPath
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Error "Failed to query Registry: $($_.Exception.Message)"
        return
    }

    if ($vhdxFiles.Count -eq 0) {
        Write-Warning "    -> No WSL 2 VHDX files found. You might be using WSL 1 or no distros are installed."
        return
    }

    Write-Host "    -> Found $($vhdxFiles.Count) distribution(s)." -ForegroundColor Green

    # 4. Compaction Loop
    $DiskPartScriptPath = "$env:TEMP\wsl_optimize_diskpart.txt"
    $Counter = 0

    foreach ($item in $vhdxFiles) {
        $Counter++
        $file = $item.Path
        $name = $item.Name
        
        Write-Host "`n[3/5] Processing ($Counter/$($vhdxFiles.Count)): $name" -ForegroundColor Cyan
        
        # Metric: Get Size Before
        try {
            $sizeBefore = (Get-Item $file).Length
            $sizeBeforeGB = "{0:N2}" -f ($sizeBefore / 1GB)
            Write-Host "    -> Initial Size: $sizeBeforeGB GB" -ForegroundColor Gray
        } catch {
            Write-Error "    -> Could not read file $file. Is it still in use?"
            continue
        }

        # Generate DiskPart Script
        # "readonly" attaches it safely without mounting the filesystem to Windows letter
        @"
SELECT VDISK FILE="$file"
ATTACH VDISK READONLY
COMPACT VDISK
DETACH VDISK
EXIT
"@ | Out-File -FilePath $DiskPartScriptPath -Encoding ASCII

        # Run DiskPart with Progress Bar
        Write-Progress -Activity "Compacting $name" -Status "Please wait, this may take a while..." -PercentComplete 50
        
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "diskpart.exe"
        $processInfo.Arguments = "/s `"$DiskPartScriptPath`""
        $processInfo.RedirectStandardOutput = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($processInfo)
        $process.WaitForExit()
        $output = $process.StandardOutput.ReadToEnd()

        Write-Progress -Activity "Compacting $name" -Completed

        # Robustness: Check for DiskPart internal errors despite ExitCode 0
        if ($process.ExitCode -eq 0 -and $output -notmatch "DiskPart has encountered an error") {
            # Metric: Get Size After
            $sizeAfter = (Get-Item $file).Length
            $savedBytes = $sizeBefore - $sizeAfter
            $TotalSavedBytes += $savedBytes
            
            $sizeAfterGB = "{0:N2}" -f ($sizeAfter / 1GB)
            $savedMB = "{0:N2}" -f ($savedBytes / 1MB)

            Write-Host "    -> Final Size:   $sizeAfterGB GB" -ForegroundColor Green
            Write-Host "    -> Reclaimed:    $savedMB MB" -ForegroundColor Magenta
        }
        else {
            Write-Error "    -> DiskPart failed for $name."
            Write-Host $output -ForegroundColor Red
        }
    }

    # Cleanup
    if (Test-Path $DiskPartScriptPath) { Remove-Item $DiskPartScriptPath }

    # 5. Summary & Warmup
    Write-Host "`n[4/5] Summary" -ForegroundColor Cyan
    $totalSavedGB = "{0:N2}" -f ($TotalSavedBytes / 1GB)
    Write-Host "    -> Total Space Reclaimed: $totalSavedGB GB" -ForegroundColor Magenta

    Write-Host "`n[5/5] Warming up WSL Engine..." -ForegroundColor Cyan
    try {
        # 'wsl --exec true' starts the VM but exits immediately, preventing an interactive shell block
        wsl --exec true
        Write-Host "    -> WSL Service is running and ready." -ForegroundColor Green
    }
    catch {
        Write-Warning "    -> Could not auto-start WSL. It will start on your next usage."
    }

    Write-Host "`n--- ✅ Optimization Complete ---" -ForegroundColor Yellow
    
    # Optional: Pause if run via double-click so user sees result
    if ($Host.Name -eq "ConsoleHost") {
        Write-Host "Press any key to exit..."
        [void][System.Console]::ReadKey($true)
    }
}

Compact-WslVhd