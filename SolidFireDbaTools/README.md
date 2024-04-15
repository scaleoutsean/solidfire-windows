# SolidFire DBA Tools PowerShell Module

This is an experimental (and partial) fork of PureStorageDbaTools. Because of the limitations and restrictions (see below), only one function is available in this fork:

- `New-SfDbSnapshot`

### Objective

The objective of this fork is to give an example of mapping a Windows mount points to its corresponding SolidFire volume ID.

Other than that, `New-SfDbSnapshot` (from SolidFire PowerShell Tools) is technically equivalent to `New-SFSnapshot` - it gives the user a crash-consistent snapshot of a SolidFire volume with a SQL Server database.

In the latter case (`New-SFSnapshot`) the user needs to know the Volume ID, but on the other hand they can also do `New-SFSnapshot -VolumeID 200,201` to snapshot multiple volumes, which is something `New-SfDbSnapshot` cannot do. 

The code is permissively licensed, so one could modify `New-SfDbSnapshot` to automatically identify and snapshot multiple SolidFire volumes. `New-SFSnapshot` is much less likely to fail and it completes in 1 second rather than 5 or so, but it requires some awareness of SolidFire-to-OS mapping and more security credentials (SQL, SolidFire) to run, so depending on one's preferences that may or may not be worth the trouble of improving `New-SfDbSnapshot`.

The (removed) DB refresh function from PureStorageDbaTools is similar to SolidFire's `Copy-SFVolume` plus some functions from dbatools cmdlets which SolidFire users who need that can hopefully put together on their own.

Then there were two, also removed, functions that wer mainly wrappers around functions from a 3rd party module (dbatools) and if anyone needs those they could reference `NewSfDbSnapshot` and the original functions to adjust them to work with SolidFire. 

- `Invoke-StaticDataMasking`
- `Invoke-DynamicDataMasking`

If you're interested in data masking, additional details are available at the link in references.

## Getting Started

### Prerequisites

This module uses functions from SolidFire PowerShell Tools for PowerShell 7, and as such it has the following prerequisites:

- Microsoft PowerShell 7.0 or higher.
- [SolidFire.Core](https://www.powershellgallery.com/packages/SolidFire.Core/) aka SolidFire PowerShell Tools for PowerShell 7.
- [dbatools](https://github.com/dataplat/dbatools/)
- NetApp SolidFire (Element) 12 or higher.
- Microsoft SQL Server 2022 or above, required for the T-SQL snapshots and data masking functionality. (T-SQL snapshots from SQL Server 2022 are not used, but may be added.)

### Installation

SolidFireDbaTools may be downloaded and installed from the source code as follows:

```powershell
PS> Import-Module .\SolidFireDbaTools.psm1
```

### Usage

Once installed, full documentation including example can be obtained on the three functions that the module contains via the Get-Help 
cmdlet:

```powershell
Get-Help New-SfDbSnapshot 
```

will provide basic information on how the function can be used

```powershell
Get-Help New-SfDbSnapshot -Detailed
```

will provide detailed information on how the function can be used including examples.

### Examples

`New-SfDbSnapshot` is technically the same as running SolidFire PowerShell cmdlet New-SFSnapshot against the volume ID where SQL database lives, but it is more DBA-friendly in the sense that the user doesn't need to figure out what SolidFire Volume ID to snapshot. Instead, he needs to feed this cmdlet only SQL Server-related information.

This cmdlet finds Windows and SolidFire volume details and uses `New-SFSnapshot` (single volume only - see Restrictions and Limitations) to take a crash consistent snapshot of the database. In this case we snapshot the database `vip` from default instance on WIN2025 and retain it for 10 minutes (recommended range is 5m-24h).

```powershell
New-SfDbSnapshot  -Database           vip           `
                  -SqlInstance        win2025       `
                  -SfEndpoint         192.168.1.30  `
                  -SfCredentials      $Creds        `
                  -SfSnapshotRetetion "00:10:00"
```

With some [RBAC](https://scaleoutsean.github.io/2023/12/07/solidfire-rbac-for-json-rpc-api.html) in place, `New-SfDbSnapshot` could be exposed directly to DBAs who could use SolidFire snapshots without having access to all of the SolidFire API and other volumes.

One can get the same outcome by creating a SolidFire snapshot schedule on the volume (e.g. snapshot every 15 min, retain 2 hours) and let it run without any worries, or running `New-SFSnapshot` (on-demand) [through Ansible](https://scaleoutsean.github.io/2022/02/14/middle-class-rbac-solidfire-ansible.html) or own HTTP proxy with RBAC rules.

## Restrictions and limitations

- This code assumes that each database resides in a single SolidFire volume, i.e. there is one window logical volume per database
- Snapshots are crash-consistent.
- The code does not work with database(s) that reside on SQL Server failover instances (i.e. do not use it with SQL Server HA clusters)
- This script cannot handle SolidFire arrays with duplicate volume names

## Authors

- scaleoutSean (adaptation with enhancements for SolidFire)
- Chris Adkin, EMEA SQL Server Solutions Architect at Pure Storage (original author)

Pull requests and contributions are welcome, but not required by the license.

## License

This module is available to use under the Apache 2.0 license, stipulated as follows and applicable to both "pre-fork" (Pure Storage) and "post-fork" contributions:

Copyright 2024 scaleoutSean (post-fork modifications)
Copyright 2018 Pure Storage, Inc.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on  an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Acknowledgements

Thank you to the original author of this script.

## Reference links

- [SolidFire and SQL Server snapshots and backups](https://scaleoutsean.github.io/2024/04/01/windows-server-2025-with-solidfire-part-two-sql-server-2022.html)
- [Securing your PowerShell credentials](https://www.purepowershellguy.com/?p=8431)

