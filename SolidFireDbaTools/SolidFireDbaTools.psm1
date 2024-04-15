function New-SfDbSnapshot
{
<#
.SYNOPSIS
A PowerShell function to create a SolidFire snapshot of the volume that a database resides on.

.DESCRIPTION
A PowerShell function to create a SolidFire snapshot of the volume that a database resides on, based in the
values of the following parameters:

.PARAMETER Database
The name of the database to refresh, note that it is assumed that source and target database(s) are named the same.
This parameter is MANDATORY.

.PARAMETER SqlInstance
This can be one or multiple SQL Server instance(s) that host the database(s) to be refreshed, in the case that the
function is invoked  to refresh databases  across more than one  instance, the list  of target instances should be
spedcified as an array of strings, otherwise a single string representing the target  instance will suffice. This 
parameter is MANDATORY.

.PARAMETER SfEndpoint
The FQDN or IP address representing the SolidFire array that the volumes for the source and refresh target databases 
reside on. This parameter is MANDATORY.

.PARAMETER SfCredentials
A PSCredential object containing the username and password of the SolidFire array to connect to. For instruction on 
how to store and retrieve these from an encrypted file, refer to this article https://www.purepowershellguy.com/?p=8431

.EXAMPLE
New-SfDbSnapshot -Database      vip          `
                 -SqlInstance   win2025      `
                 -SfEndpoint    192.168.1.30 `
                 -SfCredentials $Cred

Create a snapshot of SolidFire volume that stores the vip database on the default instance.
.NOTES
                               Known Restrictions
                               ------------------

1. This function does not currently work for databases associated with
   failover cluster instances.

2. The function assumes that all database files and the transaction log
   reside on a single SolidFire volume.

                    Obtaining The SolidFireDbaTools Module
                    ----------------------------------------

This function is part of the SolidFireDbaTools module, it is recommended
that the module is always obtained from the Github source:

https://www.github.com/scaleoutsean/solidfire-windows

Note that it has dependencies on SolidFire.Core
modules which are installed as part of the installation of this module.

                                    Licence
                                    -------

This function is available under the Apache 2.0 license, stipulated as follows:

Copyright 2024 scaleoutSean (post-fork modifications)
Copyright 2017 Pure Storage, Inc.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on  an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
.LINK
https://scaleoutsean.github.io/2024/04/01/windows-server-2025-with-solidfire-part-two-sql-server-2022.html
https://www.purepowershellguy.com/?p=8431
#>
    param(
         [parameter(mandatory=$true)] [string]                                    $Database       
        ,[parameter(mandatory=$true)] [string]                                    $SqlInstance
        ,[parameter(mandatory=$true)] [string]                                    $SfEndpoint
        ,[parameter(mandatory=$true)] [string]                                    $SfSnapshotRetention
    )

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

    if ( ! $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) ) {
        Write-Error "This function needs to be invoked within a PowerShell session with elevated admin rights"
        Return
    }

    try {
        $SfCredentials = Get-Credential -UserName admin -Message 'Enter SolidFire admin password'
        $FlashArray = Connect-SFCluster -Target $SfEndpoint -Credential $SfCredentials
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to connect to SolidFire endpoint $SfEndpoint with: $ExceptionMessage"
        Return
    }

    Write-Colour -Text "SolidFire API endpoint    : ", "CONNECTED" -Color Yellow, Green

    try {
        $DestDb = Get-DbaDatabase -SqlInstance $SqlInstance -Database $Database
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to connect to destination database $SqlInstance.$Database with: $ExceptionMessage"
        Return
    }

    Write-Colour -Text "Target SQL Server instance: ", $SqlInstance, " - ", "CONNECTED" -Color Yellow, Green, Green, Green
    Write-Colour -Text "Target windows drive      : ", $DestDb.PrimaryFilePath.Split(':')[0] -Color Yellow, Green

    try {
        $TargetServer  = (Connect-DbaInstance -SqlInstance $SqlInstance).ComputerName
    }
    catch {
        Write-Error "Failed to determine target server name with: $ExceptionMessage"        
    }

    Write-Colour -Text "Target SQL Server host    : ", $TargetServer -ForegroundColor Yellow, Green

    $GetDbDisk = { param ( $Db ) 
        $DbDisk = Get-Partition -DriveLetter $Db.PrimaryFilePath.Split(':')[0]| Get-Disk
        return $DbDisk
    }
    
    try {
        $TargetDisk = Invoke-Command -ComputerName $TargetServer -ScriptBlock $GetDbDisk -ArgumentList $DestDb
    }
    catch {
        $ExceptionMessage  = $_.Exception.Message
        Write-Error "Failed to determine the Windows disk snapshot target with: $ExceptionMessage"
        Return
    }

    Write-Colour -Text "Target SF SCSI EUI Dev ID : ", $TargetDisk.SerialNumber -Color Yellow, Green

    try {
        $TargetVolume = Get-SFVolume -SFConnection $FlashArray | Where-Object { $_.ScsiEUIDeviceID -eq $TargetDisk.SerialNumber } | Select-Object Name
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to determine snapshot SolidFire volume with: $ExceptionMessage"
        Return
    }

    $SnapshotSuffix = $SqlInstance.Replace('\', '-') + '-' + $Database + '-' +  $(Get-Date).Hour +  $(Get-Date).Minute +  $(Get-Date).Second
    Write-Colour -Text "Snapshot target SF volume : ", $TargetVolume.Name -Color Yellow, Green
    Write-Colour -Text "Snapshot name             : ", $SnapshotSuffix -Color Yellow, Green

    try {
        $SfVolumes = (Get-SFVolume -SFConnection $FlashArray)
        foreach ($Vol in $SfVolumes) { 
            if ($Vol.Name -eq $TargetVolume.Name) {
                $TargetVolumeID = $Vol.VolumeID
                $SfSnapshot = (New-SFSnapshot -SFConnection $FlashArray -VolumeID $TargetVolumeID -Name $SnapshotSuffix -Retention $SfSnapshotRetention)
                Write-Colour -Text "Volume ID                 : ", $SfSnapshot.VolumeID -Color Yellow, Green
                Write-Colour -Text "Snapshot ID               : ", $SfSnapshot.SnapshotID -Color Yellow, Green
                Write-Colour -Text "Snapshot name             : ", $SfSnapshot.Name -Color Yellow, Green
                Write-Colour -Text "Snapshot expires          : ", $SfSnapshot.ExpirationTime -Color Yellow, Green
            } 
            else {
                # SEAN - TODO - if the volume cannot be found (e.g. duplicate volume names or volume not found)
                #               we should throw and exception
                # Write-Error "Failed to determine snapshot volume with: $ExceptionMessage"
                # Return
            }}

    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to create snapshot for target database FlashArray volume with: $ExceptionMessage"
        Return
    }
} 

function DbRefresh
{
    param(
        [parameter(mandatory=$true)]  [string] $DestSqlInstance
       ,[parameter(mandatory=$true)]  [string] $RefreshDatabase
       ,[parameter(mandatory=$true)]  [string] $SfEndpoint
       ,[parameter(mandatory=$true)]  [System.Management.Automation.PSCredential] $SfCredentials
       ,[parameter(mandatory=$true)]  [string] $SourceVolume
       ,[parameter(mandatory=$false)] [bool]   $ForceDestDbOffline
       ,[parameter(mandatory=$false)] [bool]   $NoPsRemoting
       ,[parameter(mandatory=$false)] [bool]   $PromptForSnapshot
    )

    try {
        $FlashArray = Connect-SFCluster -Target $SfEndpoint -Credentials $SfCredentials
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to connect to FlashArray endpoint $PfaEndpoint with: $ExceptionMessage"
        Return
    }

    try {
        $DestDb = Get-DbaDatabase -SqlInstance $DestSqlInstance -Database $RefreshDatabase
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to connect to destination database $DestSqlInstance.$Database with: $ExceptionMessage"
        Return
    }

    Write-Host " "
    Write-Colour -Text "Target SQL Server instance: ", $DestSqlInstance, "- CONNECTED" -ForegroundColor Yellow, Green, Green

    try {
        $TargetServer  = (Connect-DbaInstance -SqlInstance $DestSqlInstance).ComputerName
    }
    catch {
        Write-Error "Failed to determine target server name with: $ExceptionMessage"   
    }

    Write-Colour -Text "Target SQL Server host    : ", $TargetServer -ForegroundColor Yellow, Green
 
    $GetDbDisk = { param ( $Db ) 
        $DbDisk = Get-Partition -DriveLetter $Db.PrimaryFilePath.Split(':')[0]| Get-Disk
        return $DbDisk
    }

    $GetVolumeLabel = {  param ( $Db )
        Write-Verbose "Target database drive letter = $Db.PrimaryFilePath.Split(':')[0]"
        $VolumeLabel = $(Get-Volume -DriveLetter $Db.PrimaryFilePath.Split(':')[0]).FileSystemLabel
        Write-Verbose "Target database Windows volume label = <$VolumeLabel>"
        return $VolumeLabel
    }

    try {
        if ( $NoPsRemoting ) {
            $DestDisk = Invoke-Command -ScriptBlock $GetDbDisk -ArgumentList $DestDb
            $DestVolumeLabel = Invoke-Command -ScriptBlock $GetVolumeLabel -ArgumentList $DestDb
        }
        else {
            $DestDisk = Invoke-Command -ComputerName $TargetServer -ScriptBlock $GetDbDisk -ArgumentList $DestDb
            $DestVolumeLabel = Invoke-Command -ComputerName $TargetServer -ScriptBlock $GetVolumeLabel -ArgumentList $DestDb
        }
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to determine destination database disk with: $ExceptionMessage"
        Return
    }

    Write-Colour -Text "Target drive letter       : ", $DestDb.PrimaryFilePath.Split(':')[0] -ForegroundColor Yellow, Green

    try {
        $DestVolume = Get-SFVolume -SFConnection $FlashArray | Where-Object { $_.serial -eq $DestDisk.SerialNumber } | Select-Object Name
        
        if (!$DestVolume) {
            throw "Failed to determine destination SolidFire volume, check that source and destination volumes are on the SAME array"
        } 
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to determine destination SolidFire volume with: $ExceptionMessage"
        Return
    }

    Write-Colour -Text "Target SF volume          : ", $DestVolume.name -ForegroundColor Yellow, Green

    $OfflineDestDisk = { param ( $DiskNumber, $Status ) 
        Set-Disk -Number $DiskNumber -IsOffline $Status
    }

    try {
        if ( $ForceDestDbOffline ) {
            $ForceDatabaseOffline = "ALTER DATABASE [$RefreshDatabase] SET OFFLINE WITH ROLLBACK IMMEDIATE"
            Invoke-DbaQuery -ServerInstance $DestSqlInstance -Database $RefreshDatabase -Query $ForceDatabaseOffline
        }
        else {
            $DestDb.SetOffline()
        }
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to offline database $Database with: $ExceptionMessage"
        Return
    }

    Write-Colour -Text "Target database           : ", "OFFLINE" -ForegroundColor Yellow, Green

    try {
        if ( $NoPsRemoting ) {
            Invoke-Command -ScriptBlock $OfflineDestDisk -ArgumentList $DestDisk.Number, $True
        }
        else {
            Invoke-Command -ComputerName $TargetServer -ScriptBlock $OfflineDestDisk -ArgumentList $DestDisk.Number, $True
        }
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to offline disk with : $ExceptionMessage" 
        Return
    }

    Write-Colour -Text "Target Windows disk       : ", "OFFLINE" -ForegroundColor Yellow, Green

    $StartCopyVolMs = Get-Date

    try {
        Write-Colour -Text "Source SolidFire volume   : ", $SourceVolume -ForegroundColor Yellow, Green
        New-PfaVolume -Array $FlashArray -VolumeName $DestVolume.name -Source $SourceVolume -Overwrite
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to refresh test database volume with : $ExceptionMessage" 
        Set-Disk -Number $DestDisk.Number -IsOffline $False
        $DestDb.SetOnline()
        Return
    }

    Write-Colour -Text "Volume overwrite          : ", "SUCCESSFUL" -ForegroundColor Yellow, Green
    $EndCopyVolMs = Get-Date
    Write-Colour -Text "Overwrite duration (ms)   : ", ($EndCopyVolMs - $StartCopyVolMs).TotalMilliseconds -Color Yellow, Green

    $SetVolumeLabel = { param ( $Db, $DestVolumeLabel )
        Set-Volume -DriveLetter $Db.PrimaryFilePath.Split(':')[0] -NewFileSystemLabel $DestVolumeLabel
    }

    try {
        if ( $NoPsRemoting ) {
            Invoke-Command -ScriptBlock $OfflineDestDisk -ArgumentList $DestDisk.Number, $False
            Invoke-Command -ScriptBlock $SetVolumeLabel -ArgumentList $DestDb, $DestVolumeLabel
        }
        else {
            Invoke-Command -ComputerName $TargetServer -ScriptBlock $OfflineDestDisk -ArgumentList $DestDisk.Number, $False
            Invoke-Command -ComputerName $TargetServer -ScriptBlock $SetVolumeLabel -ArgumentList $DestDb, $DestVolumeLabel
        }
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to online disk with : $ExceptionMessage" 
        Return
    }

    Write-Colour -Text "Target Windows disk       : ", "ONLINE" -ForegroundColor Yellow, Green

    try {
        $DestDb.SetOnline()
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Error "Failed to online database $Database with: $ExceptionMessage"
        Return
    }

    Write-Colour -Text "Target database           : ", "ONLINE" -ForegroundColor Yellow, Green
}

Export-ModuleMember -Function @('New-SfDbSnapshot') 
