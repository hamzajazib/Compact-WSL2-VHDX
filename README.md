# Compact-WSL2-VHDX 🐧💾

A robust PowerShell utility script to automatically reclaim disk space from Windows Subsystem for Linux (WSL 2) virtual hard disks (`.vhdx` files).

## 🛑 The Problem

WSL 2 uses **Dynamic Virtual Hard Disks (VHDX)** to store your Linux files. These disks automatically grow as you add data, but **they do not automatically shrink** when you delete data inside Linux.

Over time, this leads to "bloated" VHDX files that consume significantly more space on your Windows host drive than is actually being used by the Linux filesystem.

## 🚀 The Solution

This script automates the tedious maintenance process required to shrink these files. It performs the following actions safely and efficiently:

1.  **Graceful Shutdown**: Forces a shutdown of the WSL subsystem to release file locks.
    
2.  **Auto-Discovery**: Scans the Windows Registry (`HKCU\...\Lxss`) to locate the exact VHDX paths for **all** installed distributions (Ubuntu, Debian, Fedora, etc.), regardless of where they are installed.
    
3.  **Space Calculation**: Measures the VHDX size before and after compaction to report exactly how much space was reclaimed.
    
4.  **Compaction**: Uses Windows native `DiskPart` utility to safely compact the VHDX files.
    
5.  **Auto-Restart**: Automatically "warms up" the WSL engine after maintenance so it's ready for your next use.
    

## ✨ Features

- **Robust Registry Lookup**: Doesn't guess file paths; looks them up directly from the Windows configuration.
    
- **Safety Checks**: Verifies Administrator privileges and file locks before attempting operations.
    
- **Detailed Metrics**: Displays initial size, final size, and total reclaimed space in GB/MB.
    
- **Visual Feedback**: Includes progress bars for long-running compaction tasks.
    
- **Non-Interactive**: Designed to run cleanly without hanging or waiting for user input inside the Linux shell.
    

## 📋 Prerequisites

- **Windows 10 or Windows 11** with WSL 2 enabled.
    
- **PowerShell** (Pre-installed on Windows).
    
- **Administrator Privileges** (Required to run `DiskPart`).
    

## 🛠️ Usage

### Command Line

Open a PowerShell terminal as **Administrator** and run:

```powershell
.\Compact-WSL2-VHDX.ps1
```

## 📝 Example Output

```
--- 🐧 WSL Disk Compaction & Optimization ---

[1/5] Stopping WSL Subsystem...
    -> Waiting for file handles to release...

[2/5] Scanning Registry for Distributions...
    -> Found 2 distribution(s).

[3/5] Processing (1/2): Ubuntu
    -> Initial Size: 15.40 GB
    -> Final Size:   8.20 GB
    -> Reclaimed:    7,372.80 MB

[3/5] Processing (2/2): Kali-Linux
    -> Initial Size: 32.10 GB
    -> Final Size:   30.05 GB
    -> Reclaimed:    2,099.20 MB

[4/5] Summary
    -> Total Space Reclaimed: 9.25 GB

[5/5] Warming up WSL Engine...
    -> WSL Service is running and ready.

--- ✅ Optimization Complete ---
```

## ⚠️ Disclaimer

This script uses the standard Windows `DiskPart` utility to perform the `compact vdisk` command. While this is a standard procedure supported by Microsoft, always ensure you have backups of critical data before performing disk operations.
