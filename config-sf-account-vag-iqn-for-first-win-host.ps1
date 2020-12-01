Install-Module SolidFire -Scope CurrentUser # PowerShell 5.1
Import-Module SolidFire

# Per SolidFire cluster
$SFSvip = "192.168.103.30"
$SFMvip = "192.168.1.30"
$SFadmin = "admin"
$SFpassword = "NetApp123$"

# Per Hyper-V cluster
$SFWinAccount = "hyperv01" 
$SFVolNamePattern = "az01-hv01-csv0" # az01-hv01-cvs0[1-4], for example
$SFVolSize = 1 # in GiB
$SFVolQty = 3  # create 3 volumes
$SFVagName = "az-hyperv01-vag01" # VAG Name
$SFQoSPolicy = @{ 'Min' = 1000; 'Max' = 2000; 'Burst' = 5000} # set own values or edit QoS Policy later
$SFQoSpolicyName = "hyperv-low" # this is the name of the first policy; policy is editable, name is not
# Per Hyper-V node
$WinServerIp = "192.168.1.150" # Windows/Hyper-V host which I'm configuring
# $WinServerIscsiIp = "192.168.103.150" # WinNics and this may be needed for NIC Teaming and other stuff
Get-Service -Name msiscsi
Set-Service -Name msiscsi -StartupType Automatic
Start-Service msiscsi
$WinInitiator = (Get-InitiatorPort).NodeAddress  # note there could be multiple (if not teamed)
$WinNics = (Get-NetIPAddress –AddressFamily IPv4 -InterfaceAlias iscsi*) # there could be multiple (iscsi1, iscsi2) if not teamed

New-IscsiTargetPortal -TargetPortalAddress $SFSvip

Connect-SFCluster $SFMvip -username $SFadmin -password $SFpassword

$SFQosPolicyId = (New-SFQoSPolicy -Name $SFQoSPolicyName -MinIOPS $SFQoSPolicy['Min'] -MaxIOPS $SFQoSPolicy['Max'] -BurstIOPS $SFQoSPolicy['Burst'] -Confirm:$false).QoSPolicyID
$SFAccountId  = (New-SFAccount -Username $SFWinAccount).AccountID
$SFWinVols = @()
$i = 1
$j = $SFVolQty + 1
while ($i -lt $j) {
    # Note we're using 4kB blocks (512e is OFF)
	$SFWinVolId = (New-SFVolume -Name $SFVolNamePattern$i -AccountID $SFAccountId -TotalSize $SFVolSize -GiB -Enable512e:$False -AssociateWithQoSPolicy:$true -QoSPolicyID $SFQosPolicyId).VolumeID
	$SFWinVols += $SFWinVolId
	$i = $i+1
	}
Write-Host "SolidFire volumes created:" $SFWinVols
$SFVagId = (New-SFVolumeAccessGroup -Name $SFVagName -Initiators $Initiator).VolumeAccessGroupId
foreach ($vol in $SFWinVols) {
	Add-SFVolumeToVolumeAccessGroup -VolumeAccessGroupId $SFVagId -VolumeId $vol
}

# DNS hostname resolution returns one name only, and it must be in the FQDN format (i.e. resolve in DNS)
$WinHost = (Resolve-DnsName $WinServerIp).Namehost
$SFIqnId = (New-SFInitiator -Alias $WinHost -Name $WinInitiator -VolumeAccessGroupID $SFVagId).InitiatorID

