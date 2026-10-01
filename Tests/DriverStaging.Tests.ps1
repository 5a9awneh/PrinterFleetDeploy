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
if (-not (Get-Command -Name Add-PrinterDriver -ErrorAction SilentlyContinue)) {
    function global:Add-PrinterDriver { [CmdletBinding()] param([Parameter(Position=0)]$Name, $InfPath, $ErrorAction) }
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
if (-not (Get-Command -Name Set-PrintConfiguration -ErrorAction SilentlyContinue)) {
    function global:Set-PrintConfiguration { [CmdletBinding()] param($PrinterName, $DuplexingMode, $ErrorAction) }
}
if (-not (Get-Command -Name Out-GridView -ErrorAction SilentlyContinue)) {
    function global:Out-GridView { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject, $Title, [switch]$PassThru) process { } }
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
    # Keep test output out of the real activity log.
    $script:LogFile = Join-Path -Path $script:TestTempDir -ChildPath "test.log"
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

Describe "10a. INF Name Detection (Get-InfDriverNames)" {
    BeforeAll {
        # Get-InfDriverNames resolves under $PSScriptRoot\Drivers of PrinterManagement.ps1, so the
        # fixture lives in a uniquely-named subfolder there and is removed afterwards.
        $script:InfFixtureRel = "PfdInfTest_$([System.Guid]::NewGuid().ToString('N'))"
        $script:InfFixtureDir = Join-Path -Path (Join-Path -Path (Split-Path -Parent $script:ScriptPath) -ChildPath "Drivers") -ChildPath $script:InfFixtureRel
        New-Item -ItemType Directory -Path $script:InfFixtureDir -Force | Out-Null
        @'
[Manufacturer]
%Acme% = Acme,NTamd64

[Acme.NTamd64]
%Model1% = DRV,LPTENUM\AcmeUniversal
"Acme Direct Name" = DRV,USBPRINT\Acme
%Guid% = DRV,ROOT\Acme

[Other]
%NotAModel% = x,y

[Strings]
Model1 = "Acme Universal PCL6"
Guid = "{0155544A-1772-4668-BD55-240A62521160}"
NotAModel = "Should Not Appear"
'@ | Set-Content -Path (Join-Path $script:InfFixtureDir "acme.inf") -Encoding ASCII
    }
    AfterAll {
        Remove-Item -Path $script:InfFixtureDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Returns model names from Manufacturer-referenced sections, resolving %token% strings" {
        $names = Get-InfDriverNames -DriverFolder $script:InfFixtureRel
        $names | Should -Contain "Acme Universal PCL6"
        $names | Should -Contain "Acme Direct Name"
    }

    It "Ignores GUID pseudo-names and entries outside model sections" {
        $names = Get-InfDriverNames -DriverFolder $script:InfFixtureRel
        $names | Should -Not -Contain "{0155544A-1772-4668-BD55-240A62521160}"
        $names | Should -Not -Contain "Should Not Appear"
    }

    It "Returns an empty list for a missing folder" {
        @(Get-InfDriverNames -DriverFolder "DoesNotExist_$([System.Guid]::NewGuid().ToString('N'))").Count | Should -Be 0
    }
}

Describe "10b. Convention-based driver discovery (Resolve-PrinterDriver, no driver-map)" {
    BeforeAll {
        $script:DrvRoot  = Join-Path -Path (Split-Path -Parent $script:ScriptPath) -ChildPath "Drivers"
        $script:BrandKey = "PfdBrand_$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
        $script:BrandRaw = "$($script:BrandKey)/KM"
        $script:BrandDir = Join-Path -Path $script:DrvRoot -ChildPath "$($script:BrandKey)-KM"
        $pkg = Join-Path -Path $script:BrandDir -ChildPath "PkgA"
        New-Item -ItemType Directory -Path $pkg -Force | Out-Null
        @'
[Manufacturer]
%Acme% = Acme,NTamd64
[Acme.NTamd64]
"Acme Convention PCL" = DRV,USBPRINT\Acme
'@ | Set-Content -Path (Join-Path $pkg "acme.inf") -Encoding ASCII
        $script:NoMap = Join-Path -Path $script:TestTempDir -ChildPath "no_such_map.csv"
    }
    AfterAll { Remove-Item -Path $script:BrandDir -Recurse -Force -ErrorAction SilentlyContinue }
    BeforeEach { $script:DriverMapCache = $null }

    It "Finds Drivers\<Brand>\<package> and the .inf name from Brand alone ('/' becomes '-')" {
        $r = Resolve-PrinterDriver -Printer ([PSCustomObject]@{ Name = "T"; Brand = $script:BrandRaw; DriverName = ""; DriverFolder = "" }) -DriverMapPath $script:NoMap
        $r.DriverName | Should -Be "Acme Convention PCL"
        $r.DriverFolder | Should -Be "$($script:BrandKey)-KM/PkgA"
    }

    It "Returns `$null when the brand folder holds more than one package" {
        New-Item -ItemType Directory -Path (Join-Path $script:BrandDir "PkgB") -Force | Out-Null
        $r = Resolve-PrinterDriver -Printer ([PSCustomObject]@{ Name = "T"; Brand = $script:BrandRaw; DriverName = ""; DriverFolder = "" }) -DriverMapPath $script:NoMap
        Remove-Item (Join-Path $script:BrandDir "PkgB") -Recurse -Force
        $r | Should -BeNullOrEmpty
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

    It "Invokes pnputil with /subdirs /install, then registers the driver with Add-PrinterDriver, returning `$true on success" {
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*DriverStagingUnitTest*" }
        Mock pnputil.exe { $global:LASTEXITCODE = 0; "driver added successfully" } -Verifiable -ParameterFilter {
            ($args -contains "/subdirs") -and ($args -contains "/install") -and ($args -contains "/add-driver")
        }
        Mock Add-PrinterDriver { return } -Verifiable -ParameterFilter { $Name -eq "Test Driver Name" }

        $result = Install-StagedDriver -DriverFolder "DriverStagingUnitTest\SomeModel" -DriverName "Test Driver Name"

        $result | Should -BeTrue
        Should -InvokeVerifiable
    }

    It "Returns `$false when pnputil exits with a non-zero code" {
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*DriverStagingUnitTest*" }
        Mock pnputil.exe { $global:LASTEXITCODE = 1; "some pnputil error" }

        $result = Install-StagedDriver -DriverFolder "DriverStagingUnitTest\SomeModel" -DriverName "Test Driver Name"

        $result | Should -BeFalse
    }

    It "Returns `$false and warns when pnputil succeeds but no DriverName was given to register" {
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*DriverStagingUnitTest*" }
        Mock pnputil.exe { $global:LASTEXITCODE = 0; "driver added successfully" }
        Mock Add-PrinterDriver { return }

        $result = Install-StagedDriver -DriverFolder "DriverStagingUnitTest\SomeModel"

        $result | Should -BeFalse
        Should -Invoke Add-PrinterDriver -Times 0 -Exactly
    }

    It "Returns `$false when Add-PrinterDriver registration fails after successful staging" {
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*DriverStagingUnitTest*" }
        Mock pnputil.exe { $global:LASTEXITCODE = 0; "driver added successfully" }
        Mock Add-PrinterDriver { throw "spooler registration failed" }

        $result = Install-StagedDriver -DriverFolder "DriverStagingUnitTest\SomeModel" -DriverName "Test Driver Name"

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

Describe "14b. Artifact rotation" {
    It "Rotates the activity log to <name>.1 once it passes 1 MB" {
        $log = Join-Path -Path $script:TestTempDir -ChildPath "rot.log"
        [System.IO.File]::WriteAllBytes($log, (New-Object byte[] (1MB + 1024)))

        Write-Log -Message "after rotation" -Level "INFO" -CustomLogPath $log

        Test-Path "$log.1" | Should -BeTrue
        (Get-Item $log).Length | Should -BeLessThan 1KB
    }

    It "Keeps only the newest 10 state backups" {
        Mock Get-Printer { @() }
        Mock Get-PrinterPort { @() }
        Mock Get-PrinterDriver { @() }
        $dir = Join-Path -Path $script:TestTempDir -ChildPath "retention"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        1..12 | ForEach-Object {
            $f = Join-Path $dir ("printers-backup-old{0:D2}.json" -f $_)
            "{}" | Set-Content $f
            (Get-Item $f).LastWriteTime = (Get-Date).AddDays(-$_)
        }

        $new = Backup-PrinterState -OutputDir $dir

        @(Get-ChildItem $dir -Filter "printers-backup-*.json").Count | Should -Be 10
        Test-Path $new | Should -BeTrue
    }
}

Describe "14a. Duplex Wiring (Set-PrinterDuplexFromCsv)" {
    It "Defaults to TwoSidedLongEdge when the Duplex column is blank" {
        Mock Set-PrintConfiguration { return } -Verifiable -ParameterFilter { $PrinterName -eq "P1" -and $DuplexingMode -eq "TwoSidedLongEdge" }

        $printer = [PSCustomObject]@{ Name = "P1"; Duplex = "" }
        Set-PrinterDuplexFromCsv -Printer $printer

        Should -InvokeVerifiable
    }

    It "Honors an explicit Simplex override (e.g. label printers)" {
        Mock Set-PrintConfiguration { return } -Verifiable -ParameterFilter { $PrinterName -eq "P2" -and $DuplexingMode -eq "OneSided" }

        $printer = [PSCustomObject]@{ Name = "P2"; Duplex = "Simplex" }
        Set-PrinterDuplexFromCsv -Printer $printer

        Should -InvokeVerifiable
    }

    It "Honors an explicit ShortEdge override, case/whitespace-tolerant" {
        Mock Set-PrintConfiguration { return } -Verifiable -ParameterFilter { $PrinterName -eq "P3" -and $DuplexingMode -eq "TwoSidedShortEdge" }

        $printer = [PSCustomObject]@{ Name = "P3"; Duplex = "  ShortEdge  " }
        Set-PrinterDuplexFromCsv -Printer $printer

        Should -InvokeVerifiable
    }

    It "Warns and does not call Set-PrintConfiguration for an unrecognized Duplex value" {
        Mock Set-PrintConfiguration { return }

        $printer = [PSCustomObject]@{ Name = "P4"; Duplex = "garbage-value" }
        Set-PrinterDuplexFromCsv -Printer $printer

        Should -Invoke Set-PrintConfiguration -Times 0 -Exactly
    }

    It "-DryRun does not call Set-PrintConfiguration" {
        Mock Set-PrintConfiguration { return }

        $printer = [PSCustomObject]@{ Name = "P5"; Duplex = "" }
        Set-PrinterDuplexFromCsv -Printer $printer -DryRun

        Should -Invoke Set-PrintConfiguration -Times 0 -Exactly
    }

    It "Warns (does not throw) when the device doesn't support the requested duplex mode" {
        Mock Set-PrintConfiguration { throw "device does not support duplex" }

        $printer = [PSCustomObject]@{ Name = "P6"; Duplex = "" }
        { Set-PrinterDuplexFromCsv -Printer $printer } | Should -Not -Throw
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

Describe "15a. Printer picker (Select-PrintersFromList)" {
    BeforeAll {
        $script:Rows = @(
            [PSCustomObject]@{ Name = "A"; LocalPort = "10.0.0.1"; Brand = "Canon"; Model = "m"; Building = "B"; Floor = "1" }
            [PSCustomObject]@{ Name = "B"; LocalPort = "10.0.0.2"; Brand = "Sharp"; Model = "m"; Building = "A"; Floor = "0" }
            [PSCustomObject]@{ Name = "C"; LocalPort = "10.0.0.3"; Brand = "Sharp"; Model = "m"; Building = "A"; Floor = "2" }
        )
    }

    It "Returns only the rows the user picked, as the original objects" {
        Mock Out-GridView { $InputObject | Where-Object { $_.Name -in @("B", "C") } }
        $r = @(Select-PrintersFromList -PrinterList $script:Rows)
        $r.Name | Should -Be @("B", "C")
        $r[0].LocalPort | Should -Be "10.0.0.2"
    }

    It "Returns nothing when the user cancels" {
        Mock Out-GridView { }
        @(Select-PrintersFromList -PrinterList $script:Rows).Count | Should -Be 0
    }

    It "Send-TestPages -Select tests only the picked printers" {
        $csv = Join-Path -Path $script:TestTempDir -ChildPath "pick_test.csv"
        "Name;LocalPort;DriverName`nA;10.0.0.1;D1`nB;10.0.0.2;D1" | Set-Content -Path $csv -Encoding UTF8
        Mock Get-Printer { [PSCustomObject]@{ Name = $Name } }
        Mock Get-CimInstance { [PSCustomObject]@{ Name = "x" } }
        Mock Invoke-CimMethod { [PSCustomObject]@{ ReturnValue = 0 } } -RemoveParameterType InputObject
        Mock Out-GridView { $InputObject | Where-Object { $_.Name -eq "A" } }

        $r = Send-TestPages -FilePath $csv -Select

        $r.Total | Should -Be 1
        Should -Invoke Invoke-CimMethod -Times 1 -Exactly
    }

    It "Add-Printers -Select installs only the picked rows and nothing when cancelled" {
        $csv = Join-Path -Path $script:TestTempDir -ChildPath "pick.csv"
        "Name;LocalPort;DriverName`nA;10.0.0.1;D1`nB;10.0.0.2;D1" | Set-Content -Path $csv -Encoding UTF8
        Mock Get-Printer { @() }
        Mock Get-PrinterPort { [PSCustomObject]@{ Name = "x" } }
        Mock Get-PrinterDriver { [PSCustomObject]@{ Name = "D1" } }
        Mock Add-Printer { }
        Mock Set-PrintConfiguration { }
        Mock Backup-PrinterState { }

        Mock Out-GridView { $InputObject | Where-Object { $_.Name -eq "B" } }
        $r = Add-Printers -FilePath $csv -Select
        $r.Total | Should -Be 1
        Should -Invoke Add-Printer -Times 1 -Exactly -ParameterFilter { $Name -eq "B" }

        Mock Out-GridView { }
        (Add-Printers -FilePath $csv -Select).Total | Should -Be 0
    }
}

Describe "15b. Port removal retry (Remove-Printers)" {
    It "Retries a port the spooler is still holding, then removes it" {
        $script:portTries = 0
        Mock Get-Printer { [PSCustomObject]@{ Name = "P" } }
        Mock Remove-Printer { }
        Mock Get-PrinterPort { [PSCustomObject]@{ Name = "10.0.0.9" } }
        Mock Start-Sleep { }
        Mock Remove-PrinterPort { $script:portTries++; if ($script:portTries -lt 3) { throw "The specified port is in use by one or more printers." } }

        $r = Remove-Printers -PrinterList @([PSCustomObject]@{ Name = "P"; LocalPort = "10.0.0.9" }) -Force

        $r.Success | Should -Be 1
        Should -Invoke Remove-PrinterPort -Times 3 -Exactly
    }

    It "Gives up after 3 tries with a warning instead of throwing" {
        Mock Get-Printer { [PSCustomObject]@{ Name = "P" } }
        Mock Remove-Printer { }
        Mock Get-PrinterPort { [PSCustomObject]@{ Name = "10.0.0.9" } }
        Mock Start-Sleep { }
        Mock Remove-PrinterPort { throw "in use" }

        { Remove-Printers -PrinterList @([PSCustomObject]@{ Name = "P"; LocalPort = "10.0.0.9" }) -Force } | Should -Not -Throw
        Should -Invoke Remove-PrinterPort -Times 3 -Exactly
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

    It "Removes a printer whose differently-named port resolves to the same host address (e.g. PrinterLogic-style 'IP_x.x.x.x' ports)" {
        Mock Get-Printer { return @([PSCustomObject]@{ Name = "HQA-Legacy-Name"; PortName = "IP_10.10.1.10" }) }
        Mock Get-PrinterPort { return [PSCustomObject]@{ Name = "IP_10.10.1.10"; PrinterHostAddress = "10.10.1.10" } } -ParameterFilter { $Name -eq "IP_10.10.1.10" }
        Mock Remove-Printer { return } -Verifiable -ParameterFilter { $Name -eq "HQA-Legacy-Name" }

        Remove-ConflictingPrinters -Name "Reception" -PortName "10.10.1.10"

        Should -InvokeVerifiable
    }

    It "-DryRun does not call Remove-Printer" {
        Mock Get-Printer { return @([PSCustomObject]@{ Name = "Reception"; PortName = "10.10.1.99" }) }
        Mock Remove-Printer { return }

        Remove-ConflictingPrinters -Name "Reception" -PortName "10.10.1.10" -DryRun

        Should -Invoke Remove-Printer -Times 0 -Exactly
    }
}
