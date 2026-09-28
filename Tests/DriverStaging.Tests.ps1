#Requires -Module Pester

<#
.SYNOPSIS
    Unit tests for the PrinterFleetDeploy driver-staging and Location extensions.
.DESCRIPTION
    Covers Import-DriverMap, Resolve-PrinterDriver, Test-DriverInstalled,
    Install-StagedDriver, and Set-PrinterLocationFromCsv using mocks only --
    no real pnputil/driver-store/Set-Printer calls are made.
#>

# Define mockable stub functions for cmdlets that may be unavailable on a CI runner
# without the PrintManagement module imported.
if (-not (Get-Command -Name Get-PrinterDriver -ErrorAction SilentlyContinue)) {
    function global:Get-PrinterDriver { [CmdletBinding()] param([Parameter(Position=0)]$Name, $ErrorAction) }
}
if (-not (Get-Command -Name Set-Printer -ErrorAction SilentlyContinue)) {
    function global:Set-Printer { [CmdletBinding()] param([Parameter(Position=0)]$Name, $Location, $ErrorAction) }
}
if (-not (Get-Command -Name Get-Printer -ErrorAction SilentlyContinue)) {
    function global:Get-Printer { [CmdletBinding()] param([Parameter(Position=0)]$Name, $ErrorAction) }
}
if (-not (Get-Command -Name Remove-Printer -ErrorAction SilentlyContinue)) {
    function global:Remove-Printer { [CmdletBinding()] param([Parameter(Position=0)]$Name, $ErrorAction) }
}
if (-not (Get-Command -Name Get-PrinterPort -ErrorAction SilentlyContinue)) {
    function global:Get-PrinterPort { [CmdletBinding()] param([Parameter(Position=0)]$Name, $ErrorAction) }
}

$env:PRINTER_MANAGEMENT_TEST_MODE = "true"

BeforeAll {
    $env:PRINTER_MANAGEMENT_TEST_MODE = "true"
    $script:ScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "..\PrinterManagement.ps1"
    . $script:ScriptPath

    $script:TestTempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "PM_DriverStagingTests_$([System.Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:TestTempDir -Force | Out-Null
}

AfterAll {
    $env:PRINTER_MANAGEMENT_TEST_MODE = $null
    if ($null -ne $script:TestTempDir -and (Test-Path -Path $script:TestTempDir)) {
        Remove-Item -Path $script:TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "9. Driver Map Loader (Import-DriverMap)" {
    BeforeEach {
        # Resolve-PrinterDriver caches the map in $script:DriverMapCache after first use --
        # reset it so each test observes only its own driver-map.csv.
        $script:DriverMapCache = $null
    }

    It "Parses Brand/DriverName/DriverFolder rows, skipping comments and blank lines" {
        $mapPath = Join-Path -Path $script:TestTempDir -ChildPath "map_basic.csv"
        @"
# comment line, should be ignored

Brand,DriverName,DriverFolder
Canon,Canon Generic Plus PCL6,Canon/GPlus_PCL6_Driver_V340_W64_00
Sharp,SHARP UD3 PCL6,Sharp/UD3_07_PCL6_2510a
"@ | Set-Content -Path $mapPath -Encoding UTF8

        $map = Import-DriverMap -Path $mapPath

        $map.Count | Should -Be 2
        $map["canon"].DriverName | Should -Be "Canon Generic Plus PCL6"
        $map["sharp"].DriverFolder | Should -Be "Sharp/UD3_07_PCL6_2510a"
    }

    It "Returns an empty map when the file does not exist" {
        $map = Import-DriverMap -Path (Join-Path -Path $script:TestTempDir -ChildPath "does_not_exist.csv")
        $map.Count | Should -Be 0
    }
}

Describe "10. Driver Resolution (Resolve-PrinterDriver)" {
    BeforeEach {
        $script:DriverMapCache = $null
    }

    It "Prefers row-level DriverName/DriverFolder over any Brand lookup" {
        $printer = [PSCustomObject]@{ Name = "P1"; Brand = "Canon"; DriverName = "Row Override Driver"; DriverFolder = "Row/Override" }

        $resolved = Resolve-PrinterDriver -Printer $printer -DriverMapPath (Join-Path -Path $script:TestTempDir -ChildPath "unused_map.csv")

        $resolved.DriverName | Should -Be "Row Override Driver"
        $resolved.DriverFolder | Should -Be "Row/Override"
    }

    It "Falls back to a Brand lookup in driver-map.csv when row-level DriverName is blank" {
        $mapPath = Join-Path -Path $script:TestTempDir -ChildPath "map_fallback.csv"
        @"
Brand,DriverName,DriverFolder
Canon,Canon Generic Plus PCL6,Canon/GPlus_PCL6_Driver_V340_W64_00
"@ | Set-Content -Path $mapPath -Encoding UTF8

        $printer = [PSCustomObject]@{ Name = "P2"; Brand = "Canon"; DriverName = ""; DriverFolder = "" }

        $resolved = Resolve-PrinterDriver -Printer $printer -DriverMapPath $mapPath

        $resolved.DriverName | Should -Be "Canon Generic Plus PCL6"
        $resolved.DriverFolder | Should -Be "Canon/GPlus_PCL6_Driver_V340_W64_00"
    }

    It "Matches Brand case/whitespace-tolerantly" {
        $mapPath = Join-Path -Path $script:TestTempDir -ChildPath "map_tolerant.csv"
        @"
Brand,DriverName,DriverFolder
Develop/KM,KONICA MINOLTA Universal PCL,Konica-Develop/GEUPDPCL6Win_3912030MU
"@ | Set-Content -Path $mapPath -Encoding UTF8

        $printer = [PSCustomObject]@{ Name = "P3"; Brand = "  DEVELOP/KM  "; DriverName = ""; DriverFolder = "" }

        $resolved = Resolve-PrinterDriver -Printer $printer -DriverMapPath $mapPath

        $resolved.DriverName | Should -Be "KONICA MINOLTA Universal PCL"
    }

    It "Returns `$null and does not throw when neither DriverName nor a resolvable Brand exists" {
        $printer = [PSCustomObject]@{ Name = "P4"; Brand = ""; DriverName = ""; DriverFolder = "" }

        $resolved = Resolve-PrinterDriver -Printer $printer -DriverMapPath (Join-Path -Path $script:TestTempDir -ChildPath "does_not_exist.csv")

        $resolved | Should -BeNullOrEmpty
    }
}

Describe "11. Driver Presence Check (Test-DriverInstalled)" {
    It "Returns `$true when Get-PrinterDriver finds a match" {
        Mock Get-PrinterDriver { return [PSCustomObject]@{ Name = "Canon Generic Plus PCL6" } }
        Test-DriverInstalled -DriverName "Canon Generic Plus PCL6" | Should -BeTrue
    }

    It "Returns `$false when Get-PrinterDriver finds nothing" {
        Mock Get-PrinterDriver { return $null }
        Test-DriverInstalled -DriverName "Missing Driver" | Should -BeFalse
    }
}

Describe "12. Driver Auto-Staging (Install-StagedDriver)" {
    It "Returns `$false and does not call pnputil when DriverFolder is blank" {
        Mock pnputil.exe { $global:LASTEXITCODE = 0 }

        $result = Install-StagedDriver -DriverFolder ""

        $result | Should -BeFalse
        Should -Invoke pnputil.exe -Times 0 -Exactly
    }

    It "Returns `$false and does not call pnputil when the staging folder does not exist on disk" {
        Mock pnputil.exe { $global:LASTEXITCODE = 0 }

        $result = Install-StagedDriver -DriverFolder "DriverStagingUnitTest_$([System.Guid]::NewGuid().ToString('N'))"

        $result | Should -BeFalse
        Should -Invoke pnputil.exe -Times 0 -Exactly
    }

    It "-DryRun previews the pnputil command without invoking it" {
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*DriverStagingUnitTest*" }
        Mock pnputil.exe { $global:LASTEXITCODE = 0 }

        $result = Install-StagedDriver -DriverFolder "DriverStagingUnitTest\SomeModel" -DryRun

        $result | Should -BeTrue
        Should -Invoke pnputil.exe -Times 0 -Exactly
    }

    It "Invokes pnputil with /subdirs /install and returns `$true on success" {
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*DriverStagingUnitTest*" }
        Mock pnputil.exe { $global:LASTEXITCODE = 0; "driver added successfully" } -Verifiable -ParameterFilter {
            ($args -contains "/subdirs") -and ($args -contains "/install") -and ($args -contains "/add-driver")
        }

        $result = Install-StagedDriver -DriverFolder "DriverStagingUnitTest\SomeModel"

        $result | Should -BeTrue
        Should -InvokeVerifiable
    }

    It "Returns `$false when pnputil exits with a non-zero code" {
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*DriverStagingUnitTest*" }
        Mock pnputil.exe { $global:LASTEXITCODE = 1; "some pnputil error" }

        $result = Install-StagedDriver -DriverFolder "DriverStagingUnitTest\SomeModel"

        $result | Should -BeFalse
    }
}

Describe "13. Location Wiring (Set-PrinterLocationFromCsv)" {
    It "Composes Location from Building and Floor when Location column is blank" {
        Mock Set-Printer { return } -Verifiable -ParameterFilter { $Name -eq "P1" -and $Location -eq "Building A, Floor 2" }

        $printer = [PSCustomObject]@{ Name = "P1"; Location = ""; Building = "A"; Floor = "2" }
        Set-PrinterLocationFromCsv -Printer $printer

        Should -InvokeVerifiable
    }

    It "Uses the Location column verbatim, ignoring Building/Floor, when present" {
        Mock Set-Printer { return } -Verifiable -ParameterFilter { $Name -eq "P2" -and $Location -eq "Room 101" }

        $printer = [PSCustomObject]@{ Name = "P2"; Location = "Room 101"; Building = "X"; Floor = "9" }
        Set-PrinterLocationFromCsv -Printer $printer

        Should -InvokeVerifiable
    }

    It "Composes from Floor alone when Building is blank" {
        Mock Set-Printer { return } -Verifiable -ParameterFilter { $Name -eq "P3" -and $Location -eq "Floor 2" }

        $printer = [PSCustomObject]@{ Name = "P3"; Location = ""; Building = ""; Floor = "2" }
        Set-PrinterLocationFromCsv -Printer $printer

        Should -InvokeVerifiable
    }

    It "Does not call Set-Printer when Location, Building, and Floor are all blank" {
        Mock Set-Printer { return }

        $printer = [PSCustomObject]@{ Name = "P4"; Location = ""; Building = ""; Floor = "" }
        Set-PrinterLocationFromCsv -Printer $printer

        Should -Invoke Set-Printer -Times 0 -Exactly
    }

    It "-DryRun does not call Set-Printer" {
        Mock Set-Printer { return }

        $printer = [PSCustomObject]@{ Name = "P5"; Location = ""; Building = "A"; Floor = "1" }
        Set-PrinterLocationFromCsv -Printer $printer -DryRun

        Should -Invoke Set-Printer -Times 0 -Exactly
    }
}

Describe "14. Printer State Backup (Backup-PrinterState)" {
    It "Writes a JSON snapshot containing printers, ports, and drivers" {
        Mock Get-Printer { return @([PSCustomObject]@{ Name = "P1"; DriverName = "D1"; PortName = "192.168.1.1"; Shared = $false; Published = $false; Location = "" }) }
        Mock Get-PrinterPort { return @([PSCustomObject]@{ Name = "192.168.1.1"; PrinterHostAddress = "192.168.1.1"; Description = "Standard TCP/IP Port" }) }
        Mock Get-PrinterDriver { return @([PSCustomObject]@{ Name = "D1"; Manufacturer = "Test"; DriverVersion = 1 }) }

        $outDir = Join-Path -Path $script:TestTempDir -ChildPath "backups"
        $path = Backup-PrinterState -OutputDir $outDir

        $path | Should -Not -BeNullOrEmpty
        Test-Path -Path $path | Should -BeTrue
        $content = Get-Content -Path $path -Raw | ConvertFrom-Json
        $content.Printers.Count | Should -Be 1
        $content.PrinterPorts.Count | Should -Be 1
        $content.PrinterDrivers.Count | Should -Be 1
    }

    It "Handles zero installed printers without error" {
        Mock Get-Printer { return @() }
        Mock Get-PrinterPort { return @() }
        Mock Get-PrinterDriver { return @() }

        $outDir = Join-Path -Path $script:TestTempDir -ChildPath "backups_empty"
        $path = Backup-PrinterState -OutputDir $outDir

        $path | Should -Not -BeNullOrEmpty
        (Get-Content -Path $path -Raw | ConvertFrom-Json).Printers.Count | Should -Be 0
    }
}

Describe "15. Reconcile-to-Desired-State (Remove-ConflictingPrinters)" {
    It "Removes an existing printer that matches by Name (different port)" {
        Mock Get-Printer { return @([PSCustomObject]@{ Name = "Reception"; PortName = "10.10.1.99" }) }
        Mock Remove-Printer { return } -Verifiable -ParameterFilter { $Name -eq "Reception" }

        Remove-ConflictingPrinters -Name "Reception" -PortName "10.10.1.10"

        Should -InvokeVerifiable
    }

    It "Removes an existing printer that matches by Port (different name)" {
        Mock Get-Printer { return @([PSCustomObject]@{ Name = "Old_Reception_Name"; PortName = "10.10.1.10" }) }
        Mock Remove-Printer { return } -Verifiable -ParameterFilter { $Name -eq "Old_Reception_Name" }

        Remove-ConflictingPrinters -Name "Reception" -PortName "10.10.1.10"

        Should -InvokeVerifiable
    }

    It "Removes multiple distinct conflicting printers (one by Name, one by Port)" {
        Mock Get-Printer { return @(
            [PSCustomObject]@{ Name = "Reception"; PortName = "10.10.1.99" }
            [PSCustomObject]@{ Name = "Old_Reception_Name"; PortName = "10.10.1.10" }
        ) }
        Mock Remove-Printer { return }

        Remove-ConflictingPrinters -Name "Reception" -PortName "10.10.1.10"

        Should -Invoke Remove-Printer -Times 2 -Exactly
    }

    It "Does not remove printers matching neither Name nor Port" {
        Mock Get-Printer { return @([PSCustomObject]@{ Name = "Unrelated"; PortName = "10.10.1.50" }) }
        Mock Remove-Printer { return }

        Remove-ConflictingPrinters -Name "Reception" -PortName "10.10.1.10"

        Should -Invoke Remove-Printer -Times 0 -Exactly
    }

    It "-DryRun does not call Remove-Printer" {
        Mock Get-Printer { return @([PSCustomObject]@{ Name = "Reception"; PortName = "10.10.1.99" }) }
        Mock Remove-Printer { return }

        Remove-ConflictingPrinters -Name "Reception" -PortName "10.10.1.10" -DryRun

        Should -Invoke Remove-Printer -Times 0 -Exactly
    }
}
