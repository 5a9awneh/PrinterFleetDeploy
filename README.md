# Printer Management Suite 🖨️

[![PowerShell Tests & Quality Check](https://github.com/IamCarron/PrinterManagement/actions/workflows/test.yml/badge.svg)](https://github.com/IamCarron/PrinterManagement/actions/workflows/test.yml)
[![PowerShell](https://img.shields.io/badge/Language-PowerShell-5391FE.svg?logo=powershell&logoColor=white)](https://microsoft.com/powershell)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%2F%2011%20%2F%20Server-0078D6.svg?logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![Tests](https://img.shields.io/badge/Tests-Pester%20v5-28A745.svg?logo=pester&logoColor=white)](https://pester.dev)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/IamCarron/PrinterManagement/pulls)

Automated, robust, and enterprise-grade PowerShell automation suite for managing printers in Windows environments. Designed for System Administrators, IT Support, and DevOps to streamline bulk deployments, maintenance, diagnostics, and inventorying.

> **PrinterFleetDeploy** is a fork of [IamCarron/PrinterManagement](https://github.com/IamCarron/PrinterManagement)
> that adds transparent **driver auto-staging** (`pnputil /add-driver`) and **Location**
> (Building/Floor) wiring on top of the original bulk-deployment tool. It is brand/model/driver
> **agnostic** — bring your own inventory CSV, your own driver packages, and your own
> brand→driver map, and it works the same for any organization. See [Credits & Attribution](#-credits--attribution).

---

## 📑 Table of Contents

- [🌟 Features](#-features)
- [🖥️ Interactive Console](#️-interactive-console)
- [📋 Requirements](#-requirements)
- [🚀 Quick Start](#-quick-start)
- [📊 CSV File Specifications](#-csv-file-specifications)
- [🔌 Driver Auto-Staging (`driver-map.csv`)](#-driver-auto-staging-driver-mapcsv)
- [📍 Location Wiring](#-location-wiring)
- [🧪 Automated Unit Tests](#-automated-unit-tests)
- [🛡️ Safety & Parachute Guards](#️-safety--parachute-guards)
- [🤝 Contributing](#-contributing)
- [🙏 Credits & Attribution](#-credits--attribution)
- [📄 License](#-license)

---

## 🌟 Features

- ⚡ **Multi-Protocol Bulk Installation:** Deploy dozens of printers automatically from CSV files via standard TCP/IP (IPv4 / Hostname), Shared Network Printers (`\\server\share`), or Local Ports (`USB001`, `LPT1:`).
- 🗑️ **Dual-Mode Printer Removal:** Remove printers in bulk via CSV lists or interactively using a native Windows `Out-GridView` selection dialog with multi-select support (`Ctrl` / `Shift`).
- 📄 **Automated Test Page Dispatch:** Send hardware test prints via CIM/WMI methods (`Win32_Printer.PrintTestPage()`) with automatic fallback to native Windows `printui.dll`.
- 🧹 **Safe Spooler Queue Purge:** Stops the `Spooler` service cleanly, verifies process termination and file lock releases, clears corrupted print jobs (`.SHD` / `.SPL`), and restarts the Spooler service.
- 📊 **Real-Time Inventory & Console Table Inspection:** Collects system-wide printer data using modern CIM cmdlets, displays an organized, clean table directly in the terminal, and exports to UTF-8 CSV (`inventory.csv`).
- 🗂️ **Hybrid GUI / CLI File Picker:** Open native Windows Explorer dialogs by pressing `[Enter]` or type/paste file paths directly in the console.
- 🛡️ **Smart Delimiter & Header Parser:** Auto-detects delimiters (Semicolon `;`, Comma `,`, or Tab `\t`) and normalizes varied column names (`Driver`/`DriverName`, `Port`/`LocalPort`, `Name`/`PrinterName`).
- 📈 **Native Progress Bars:** Integrated `Write-Progress` tracking provides visual percentage and status updates during batch installations and test page dispatching.
- 📜 **Centralized Activity Logging:** Every operation, warning, success, and error is recorded with timestamps in `PrinterManagement.log`.
- 🌐 **Cross-PowerShell Compatibility:** 100% pure ASCII user interface and robust encoding protection, compatible with Windows PowerShell 5.1 and modern PowerShell 7+ (pwsh).
- 🔌 **Driver Auto-Staging:** Resolves each printer's driver by `Brand` via `config/driver-map.csv` (or an explicit per-row override), and automatically stages it from a local `Drivers/` package with `pnputil /add-driver ... /subdirs /install` when it isn't already installed.
- 📍 **Location Wiring:** Sets the Windows printer `Location` property from a `Location` column, or composes it from `Building`/`Floor` — and the `Remove-Printers` picker sorts by `Location` so a large fleet is easy to navigate visually.
- 🧪 **`-DryRun` Previews:** `Add-Printers -DryRun` previews every driver-staging, port-creation, printer-add, and Location-set action without changing anything on the system.

---

## 🖥️ Interactive Console

```text
  ===========================================================================
    ___      _      __          __  ___
   / _ \____(_)__  / /____ ____/  |/  /__ ____  ___ ____ ____ __ _  ___ ___
  / ___/ __/ / _ \/ __/ -_) __/ /|_/ / _ `/ _ \/ _ `/ _ `/ -_)  ' \/ -_) _ \
 /_/  /_/ /_/_//_/\__/\__/_/ /_/  /_/\_,_/_//_/\_,_/\_, /\__/_/_/_/\__/_//_/
                                                    /___/
  ===========================================================================
   v3.2.0 | Windows Printer Management Suite
   github.com/IamCarron/PrinterManagement
  ===========================================================================

   >> OPERATIONS -------------------------------------------------
      [1]  Add Printers         Bulk CSV / TCP-IP / Shared UNC
      [2]  Remove Printers      CSV or interactive selection

   >> DIAGNOSTICS ------------------------------------------------
      [3]  Send Test Pages      CIM dispatch with printui fallback
      [4]  Clear Print Queue    Purge Spooler & restart service

   >> SYSTEM -----------------------------------------------------
      [5]  Inventory Printers   GUI table & CSV export
      [6]  View Activity Log    Review recent operations

   ---------------------------------------------------------------
      [0]  Exit

                         Made with <3 by IamCarron
```

---

## 📋 Requirements

- **Operating System:** Windows 10 / 11 or Windows Server 2016 / 2019 / 2022 / 2025.
- **PowerShell Version:** Windows PowerShell 5.1 (Built-in) or PowerShell 7.x (Core).
- **Execution Privileges:** Elevated Administrator rights (`Run as Administrator`).
- **Print Drivers:** Required manufacturer printer drivers must be installed prior to bulk deployment.

---

## 🚀 Quick Start

### 1. Clone the Repository
```powershell
git clone <your-fork-url> PrinterFleetDeploy
cd PrinterFleetDeploy
```

### 2. Bring Your Own Data (never committed to git)
- Copy [`config/printers.sample.csv`](config/printers.sample.csv) to `config/printers.csv` and fill in your real inventory.
- Copy [`config/driver-map.sample.csv`](config/driver-map.sample.csv) to `config/driver-map.csv` and fill in your real `Brand → DriverName/DriverFolder` mappings (see [Driver Auto-Staging](#-driver-auto-staging-driver-mapcsv)).
- Extract your vendors' driver packages under `Drivers/<Brand>/<PackageFolder>/` — see [`Drivers/README.md`](Drivers/README.md) for layout and sourcing guidance.
- All of the above are covered by `.gitignore` — real inventory and driver binaries never touch git history.

### 3. Launch with Administrator Privileges
Open PowerShell as **Administrator** and run:
```powershell
.\PrinterManagement.ps1
```

---

## 📊 CSV File Specifications

The parser automatically detects delimiters (`;`, `,`, or `\t`) and tolerates a few common header
aliases (`Printer Name`/`PrinterName`/`Name`, `IP Address`/`Port`/`LocalPort`). Only `Name` and
`LocalPort` are required — every other column is optional and purely additive:

| Column | Required? | Purpose |
| :--- | :--- | :--- |
| **`Name`** | Yes | Display name for the printer in Windows. |
| **`LocalPort`** | Yes | Port identifier (IPv4 address, hostname, UNC path, or USB/local port). |
| **`Brand`** | No\* | Looked up in `config/driver-map.csv` to resolve `DriverName`/`DriverFolder`. |
| **`DriverName`** | No\* | Exact registered driver name (`Get-PrinterDriver`). Overrides the `Brand` lookup if present. |
| **`DriverFolder`** | No\* | Path under `Drivers/` to stage from if the driver isn't installed yet. Overrides the `Brand` lookup if present. |
| **`Model`** | No | Informational only — not used in any staging/install logic. |
| **`Building`** / **`Floor`** | No | Composed into the printer's Windows `Location` property (e.g. `Building HQ, Floor 2`). |
| **`Location`** | No | Freeform override, used verbatim instead of composing from `Building`/`Floor`. |

\*At least one of `DriverName` **or** a `Brand` resolvable via `driver-map.csv` is needed for
driver auto-staging; if neither resolves, the printer add is skipped with a warning (or, if the
driver's already installed, staging is simply skipped and the add proceeds normally).

### Sample `printers.csv` (see [`config/printers.sample.csv`](config/printers.sample.csv)):
```csv
Printer name,IP Address,Brand,DriverName,Model,Building,Floor
Reception - Ground Floor,10.10.1.10,Canon,,Canon imageFORCE 6160,HQ,0
Finance - Shared (UNC),\\printserver01\Finance_Shared,,,,HQ,2
Warehouse - Labels,USB001,,ZDesigner ZD420-203dpi ZPL,Zebra ZD420,Warehouse,0
```

---

## 🔌 Driver Auto-Staging (`driver-map.csv`)

Real-world driver consolidation tends to land on **one driver per brand** (most vendors now ship
a single "universal"/"unified" PCL6 driver covering many models), so repeating a driver name on
every CSV row is needless duplication. `config/driver-map.csv` (see
[`config/driver-map.sample.csv`](config/driver-map.sample.csv)) maps `Brand → DriverName,DriverFolder`:

```csv
Brand,DriverName,DriverFolder
Canon,Canon Generic Plus PCL6,Canon/GPlus_PCL6_Driver_V340_W64_00
Develop/KM,KONICA MINOLTA Universal PCL,Konica-Develop/GEUPDPCL6Win_3912030MU
Sharp,SHARP UD3 PCL6,Sharp/UD3_07_PCL6_2510a
```

- **`DriverName`** must be the *actual* name `Get-PrinterDriver` reports after staging on a real
  test machine — not the vendor's marketing/filename — since this is genuinely
  environment-specific.
- **`DriverFolder`** is a path relative to `Drivers/` (the top-level extracted package folder, not
  the exact `.inf` path) — see [`Drivers/README.md`](Drivers/README.md) for layout and sourcing.
- Matching on `Brand` is case/whitespace-tolerant, and a row's own `DriverName`/`DriverFolder`
  always wins over the `Brand` lookup.
- When a printer's driver isn't already installed, `Add-Printers` automatically runs
  `pnputil /add-driver "Drivers\<Folder>\*.inf" /subdirs /install` before creating the printer —
  no manual pre-staging step required. Use `Add-Printers -DryRun` to preview exactly what would be
  staged/installed/located without making any changes.

---

## 📍 Location Wiring

If a CSV row has a `Location` value, it's applied verbatim; otherwise, if it has `Building`
and/or `Floor`, those are composed into `"Building X, Floor Y"` (or just whichever of the two is
present) and set via `Set-Printer -Location`. This runs after a successful `Add-Printer` for both
shared/UNC and standard TCP/USB printers, and is purely additive — no-op when none of the three
columns are present.

The interactive picker in `Remove-Printers` (option `[2]`) also surfaces each installed printer's
`Location` and sorts the list by it, so you can navigate a large fleet by building/floor instead
of scrolling an alphabetical `Name` list (falls back to plain `Name` sort if `Location` was never
set on any printer).

---

## 🧪 Automated Unit Tests

The repository includes a comprehensive unit and integration test suite built with **Pester 5+**
located in `Tests/`: the inherited baseline suite (`PrinterManagement.Tests.ps1`) plus
`DriverStaging.Tests.ps1`, which covers the driver-map resolution, auto-staging, and Location
wiring added by this fork — entirely via mocks, with no real `pnputil`/driver-store/`Set-Printer`
calls.

### Running Tests Locally:
```powershell
# Automated test runner (installs Pester automatically if not present, discovers all *.Tests.ps1):
.\Tests\Run-Tests.ps1

# Or run directly via Pester:
Invoke-Pester .\Tests\ -Output Detailed
```

### Continuous Integration (CI):
Automated testing is configured via **GitHub Actions** (`.github/workflows/test.yml`), verifying code quality and test execution across both **Windows PowerShell 5.1** and **PowerShell 7+ (pwsh)** on every push and pull request.

---

## 🛡️ Safety & Parachute Guards

- 🪂 **Interactive Deletion Safeguards:** Removal operations require explicit confirmation (`Y/N`) before modifying the system unless `-Force` is supplied programmatically.
- 🔍 **Pre-Execution Driver Validation:** Verifies that the required printer driver exists locally before attempting printer creation, avoiding system errors or corrupt configurations.
- 🧹 **Controlled Spooler Restart:** Stops the print spooler safely and ensures all pending file handles are released before purging `.SPL` / `.SHD` spool files.
- 💉 **CIM / WQL Escape Protection:** Automatically escapes single quotes and special characters in printer names to prevent WMI/CIM injection and query errors.
- 📋 **Zero Pipeline Pollution:** All helper routines are isolated to guarantee pure data pipelines across scripts and test runners.

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

1. Fork the Project.
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`).
3. Commit your Changes (`git commit -m 'feat: add some amazing feature'`).
4. Push to the Branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

## 🙏 Credits & Attribution

This project is a fork of [**IamCarron/PrinterManagement**](https://github.com/IamCarron/PrinterManagement)
(Apache License 2.0) — all of the core bulk-install/remove, test-page dispatch, spooler-purge,
inventory, and CSV-parsing functionality originates there. This fork layers driver auto-staging
and Location wiring on top, kept additive and low-conflict with future
`git fetch upstream && git merge`. See [NOTICE.md](NOTICE.md) for the full attribution statement
required by the Apache License.

---

## 📄 License

Distributed under the **Apache License 2.0**. See the [LICENSE](LICENSE) file for more information.



