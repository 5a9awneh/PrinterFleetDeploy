# Drivers/

This folder holds the actual printer driver payloads used for staging (`pnputil /add-driver`).
It is **gitignored** — nothing here is ever committed. Driver packages are proprietary/
EULA-restricted (assume this for *any* vendor unless you've checked otherwise), so this repo
only documents where to get them and how to lay them out locally.

This tool is brand/model agnostic — the structure below uses our own local example (Canon /
Konica-Develop / Sharp) purely as a worked example. Bring your own vendor(s) the same way.

## Layout

```
Drivers/
├── <Brand>/
│   └── <ExtractedPackageFolder>/
│       └── ... (vendor's own internal structure, including the .inf file(s)) ...
```

`config/driver-map.csv` (see `config/driver-map.sample.csv`) points `DriverFolder` at
`<Brand>/<ExtractedPackageFolder>` — the **top-level extracted folder**, not the exact `.inf`
path. `Install-StagedDriver` runs `pnputil /add-driver "...\<Folder>\*.inf" /subdirs /install`,
so it traverses into whatever subfolders the vendor's package actually uses.

## Where to get drivers

Get each vendor's official "universal"/"unified" PCL6 driver from their support site — most
manufacturers now ship one driver package that covers many/most models, which is why a
brand-keyed lookup (`config/driver-map.csv`) usually beats listing a driver per printer.

## Our own local example (for reference only — not a general requirement)

| Brand | Package | Real `.inf` location(s) found inside it |
|---|---|---|
| Canon | Generic Plus PCL6 (`GPlus_PCL6_Driver_V340_W64_00`) | `Driver\CNP60MA64.INF`, `etc\CNP60MA64.INF`, `misc\NullDriver\lasernull.inf` |
| Konica Minolta / Develop | Universal PCL (`GEUPDPCL6Win_3912030MU`) | `driver\win_x64\KOAWNJA_.inf` (64-bit), `driver\win_x86\KOAWNJA_.inf` (32-bit) |
| Sharp | UD3 (`UD3_07_PCL6_2510a`) — one universal binary confirmed to cover all of our BP-50C31 / MX-3051 / MX-5051 / DX-2500N models | `PCL6\64bit\sv0emenu.inf` (64-bit), `PCL6\32bit\sv0ejenu.inf` (32-bit) |

Note none of these `.inf` files sit at the top level of their package folder — this is normal;
it's exactly why `/subdirs` is required (see §6c of the project plan).

## Trimming a package down for portability

The whole project folder is meant to be zippable/sendable as a self-contained package (emailed
to another tech, copied to a shared drive), so keep `Drivers/` lean. For **any** vendor's
package, once you've confirmed which architecture you actually need (almost always 64-bit only
for a modern fleet):

1. Extract the vendor's downloaded package normally.
2. Delete anything for the architecture(s) you don't need — e.g. `win_x86`/`32bit`/`x86` folders,
   once you've confirmed your fleet is 64-bit only.
3. Delete standalone installer `.exe` wrappers — `pnputil` only needs the `.inf` (plus its
   sibling `.cat`/`.dll`/data files in the *same* folder as that `.inf`); a full installer isn't
   used by this tool.
4. Delete language packs / help files / bundled utilities (scanner tools, status monitors,
   fax software, etc.) that live in their own subfolders separate from the driver `.inf` — these
   aren't touched by `pnputil` either.
5. Leave whatever's left exactly where it sits (don't flatten folder structure) — `/subdirs`
   handles the traversal, so there's no need to move files around.

This step is optional and can be done later — the tool works fine against an untrimmed package;
trimming only matters for keeping the shareable project folder small.
