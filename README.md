# solidfire-windows: Notes on Microsoft Windows with NetApp SolidFire

Notes on Windows Server Hyper-V clusters with NetApp SolidFire, including (but not limited to) NeApp HCI H410C (servers) and Mellanox SN2010 switches.

For additional SolidFire information, please refer to [awesome-solidfire](https://github.com/scaleoutsean/awesome-solidfire).

- [solidfire-windows: Notes on Microsoft Windows with NetApp SolidFire](#solidfire-windows-notes-on-microsoft-windows-with-netapp-solidfire)
  - [General Notes](#general-notes)
  - [Host and Guest Configuration Notes](#host-and-guest-configuration-notes)
    - [Networking](#networking)
    - [iSCSI](#iscsi)
    - [Multipath I/O](#multipath-io)
    - [Disks](#disks)
    - [Hyper-V](#hyper-v)
    - [Automation](#automation)
    - [Direct VM Access to iSCSI targets](#direct-vm-access-to-iscsi-targets)
    - [Monitoring, Backup and other Integrations](#monitoring-backup-and-other-integrations)
  - [Application Notes](#application-notes)
  - [Generic workflow for Hyper-V Clusters with NetApp SolidFire](#generic-workflow-for-hyper-v-clusters-with-netapp-solidfire)
  - [Microsoft Windows on NetApp HCI Servers ("Compute Nodes")](#microsoft-windows-on-netapp-hci-servers-compute-nodes)
    - [NetApp H410C](#netapp-h410c)
      - [Network adapters and ports](#network-adapters-and-ports)
    - [NetApp H615C](#netapp-h615c)
  - [Demo Videos](#demo-videos)
  - [Frequently Asked Questions](#frequently-asked-questions)
  - [License and Trademarks](#license-and-trademarks)

## General Notes

- Each SolidFire volume is available on one network (subnet and VLAN). Different targets may be served over multiple networks and VLANs when SolidFire uses Trunk Mode switch ports.
  - iSCSI clients connect to portal - Storage Virtual IP (SVIP) - which redirects each login to the SolidFire node which hosts the target (volume) of interest (standard iSCSI redirection)
  - Active nodes are ocassionally rebalanced transparently to the client
- Multiple connections from one host to single volume (and MPIO) are rarely needed (NetApp AFF and E-Series are more suitable one or few large workloads)
  - Network adapter team (bonding) creates one path per volume and provides link redundancy, which is enough for 90% of use cases
  - It is not possible to establish two connections (sessions) to the same volume with one initiator IP
  - Ways to get to multiple connections requires Multipath I/O and:
    - Use four NICs to create two teams on the same network, set up one connection from each adapter team's IP address
    - Use two non-teamed NICs on the same network, set up one connection from each interface's IP address
    - Use one teamed interface with two vEthernet NICs for ManagementOS, set up one connection from each vEthernet interface's IP address
    - Use Windows Network Controller (available only in Windows Server [Datacenter Edition](https://docs.microsoft.com/en-us/windows-server/get-started-19/editions-comparison-19))

## Host and Guest Configuration Notes

### Networking

- Consider using Jumbo Frames on networks used for iSCSI, Live Migration and/or backup
- Consider using enterprise-grade network switches such as Mellanox SN2010 (which you can purchase from NetApp)
- Consider disabling IPv6 on interfaces on iSCSI network
- Consider disabling NIC registration in DNS for interfaces on iSCSI network (also Live Migration and other networks which don't need it)
- Consider disabling DHCP service on iSCSI and Live Migration network(s), but if you need it, hand out MTU 9000 or such through DHCP options
- It may be more convenient to combine 2 or 4 Mellanox NICs into 1 or 2 LACP Teams, use Trunk mode and VLANs to segregate workloads and tenants
- Some network and other configuration changes may require Windows to be restarted although it won't prompt you
- It appears light and moderate workloads don't require any tuning (even Jumbo Frames)

### iSCSI

- (Optional) Increase the maximum duration of I/O timeouts and lower the frequency of accessibility checks (not sure how much it matters)

### Multipath I/O

- If you don't have multiple links to SolidFire or other iSCSI target, don't install it
- When adding vendor and product ID to MPIO configuration, use `SolidFir` and `SSD SAN`, respectively (only recommended if you use Multipath I/O)
- There are no recent comparisons of various Multipath load balancing options (LQD should give best results), so it's recommended to spend 30 minutes to evaluate them in your environment

### Disks

- Maximum SolidFire volume size is 16TB; it's hard to generalize but for an N-node SolidFire cluster one should create N*2 to N*4 volumes of 1-4 TB each
- Maximum SolidFire volume performance depends on request sizes and read-write ratio but it tends to be somewhere between traditional flash storage and virtualized distributed flash storage
- In the case of very large volumes or very busy workloads (e.g. sustained 30,000 IOPS or 300 MB/s) striped Dynamic Volumes may be used to spread I/O over several volumes, although they have some limitations (in terms of manageability on Windows, for example backup and restore)
- Another way to spread the workload is to spread single VM's disks over several different (Cluster Shared or other) SolidFire volumes. This helps if worklaod isn't concentrated on one hot file (in which case striped Dynamic Volumes can be used)
- The (Default) 4kB NTFS block size ought to work best in terms of efficiency, but there is no anectodal evidence so this should be confirmed in practice through testing
- Windows Storage Spaces aren't supported with iSCSI (they can be configured and work similarly to striped Dynamic Volumes, although with Storage Spaces strips are wider)

### Hyper-V

- Note that Virtual Switches configured through Hyper-V Manager have default values not immediately obvious to the user
- Once you create Virtual Switches, re-check IPv6 addresses (best eliminate them), adapter binding order and packet sizes on vEthernet NICs (including ManagementOS)
- Re-check Hyper-V Live Migration settings - make sure iSCSI and Management networks have lowest preference for Live Migration
- You may want to verify SMB3 if you set Hyper-V to use it for Live Migration
  
### Automation

- Deploy SolidFire PowerShell Tools for Windows on your management VM. It is recommended to use SolidFire PowerShell Tools for Microsoft PowerShell 5.1: `Install-Module -Name SolidFire  -Scope CurrentUser`
- Install SolidFire VSS Hardware Provider for Windows Server 2019 and 2016 on your Hyper-V hosts (and VMs, if you have them configured to directly access iSCSI)
- SolidFire is easy to automate (`New-SFVolume`, `Add-SFVolumeToVolumeAccessGroup`, after you've set up cluster, added iSCSI initiators and created QoS policies and Volume Access Groups; to remove a volume from Hyper-V CSVs you'd remove it from WFC and OS as per usual procedures for iSCSI devices, remove it from VAG (`Remove-SFVolumeFromVolumeAccessGroup`) and then delete it (`Remove-SFVolume`), assuming it didn't have replication or SnapMirror relationships in place
- It's possible to automate SolidFire with Terraform or Ansible, but unless one already uses (or wants to use) these tools it's easy enough to put together a custom PowerShell script that works for your needs

### Direct VM Access to iSCSI targets

- Like with VMware "RDM", you need to make sure the VMs may access iSCSI network(s), and they must use unique (to each VM or clustered group of VMs) initiators, VAGs, SolidFire (CHAP) accounts and volumes
- The NetApp Interoperability Matrix has information about supported SolidFire iSCSI clients (see [awesome-solidfire](https://github.com/scaleoutsean/awesome-solidfire))

### Monitoring, Backup and other Integrations

- See [awesome-solidfire](https://github.com/scaleoutsean/awesome-solidfire) for general information about various SolidFire integrations

## Application Notes

NetApp has published several TR's (Technical Reports) for Windows-based workloads. If you google it you may find more or less recent TR's that may help you.

## Generic workflow for Hyper-V Clusters with NetApp SolidFire

- Analyze all requirements (availability, security, performance, networking...)
  - If you want to use SMB or NFS to connect to NetApp AFF/FAS, or iSCSI to connect AFF/FAS/E-Series or other storage, consider those requirements as well. NetApp E-Series iSCSI targets, for example, have different requirements and multipathing works differently from SolidFire and such cases it may be better to use separate networks for that traffic (or vEthernet's on separate VLANs)
- Formulate a deployment plan
- Configure network switches
  - If you use NetApp HCI compute nodes, it's probably best to get NetApp H-Series SN2010 (Mellanox) L2 switches
- Deploy Windows hosts
  - Install base OS (Windows Server 2019 Datacenter Edition, for example)
  - Install drivers, plugins, modules, etc.
    - Solidfire VSS Hardware Provider v2 (only on Hyper-V hosts)
    - SolidFire PowerShell Tools 1.5.1 or newer for Microsoft PowerShell 5.1 (management clients only)
    - Drivers (NetApp HCI H41C node needs one for Mellanox and two for Intel - see under Drivers)
  - Install required Windows features (Multipath I/O, Failover-Cluster, etc.) on Hyper-V hosts
  - Update OS and reboot (maybe more than once)
- Configure Windows hosts
  - Hostnames, timezone, network interfaces, routes, DNS (A & PTR including virtual IPs), DHCP, IPv6, etc.
  - Join Active Directory (recommended)
  - Make sure cluster members' DNS server is pointed at ADS DNS and that ADS forwards other requests upstream (DNS resolution must work!)
  - Configure Hyper-V and virtual switches
    - If Hyper-V is configured for Kerberos make sure Windows AD delegation for required resources is allowed with Kerberos
    - Recheck VMSwitch and vEthernet NIC settings (Jumbo Frames, IPv6, binding order and so on) because some options can be set only when VMSwitches are created and cannot be changed later
    - Recheck Live Migraiton network preference in Hyper-V
- Configure SolidFire storage
  - Create SolidFire cluster
  - Create DNS entries for SolidFire cluster (management interfaces, IPMI, out-of-band mNode)
  - Point NTP client to Windows ADS (primary and secondary) and one public NTP server
  - Create and upload valid TLS certificates to SolidFire cluster nodes (each node's management IP, hardware BMC IP, out-of-band mNode IP)
  - Add Windows Hyper-V (and other, if necessary) hosts' initiators to Initiators list and create one or more Volume Access Groups (VAGs). Then add initiators to appropriate VAGs
  - Create one low performance QoS policy for Quorum volumes (e.g. Min 100, Max 300, Burst 500) and several other policies for regular worklaods (Bronze, Silver, Gold)
  - Create one quorum volume with the Quorum QoS storage policy and add it to the VAG
  - Enable and start iSCSI initiator service on each Windows Hyper-V host
  - Configure iSCSI initiators and Multipath I/O - only one Portal (SolidFire Storage Virtual IP) needs to be added and Multipath I/O only if you have multiple paths to SVIP
  - Create one or several volumes for VMs (Cluster Shared Volumes) and add them to the same Hyper-V VAG
    - Some scripts to get you started are available in the SolidFire PowerShell Tools repo on Github
- Prepare Hyper-V for Windows Failover Clustering
  - Check firewall, DNS, AD configuration
  - Recheck adapter binding, IPv6, DNS, as it may look different after Virtual Switch and vEthernet adapter creation
  - Login iSCSI clients to Portal and connect to Quorum disk. On one Hyper-V host, bring the disk online and create NTFS volume on it using default settings
- Create Windows Failover Cluster
  - Validate configuration, especially DNS and firewall configuration
  - [Optionally](https://social.technet.microsoft.com/Forums/en-US/bf5285bc-fc72-474f-a0f4-232a2bd230b1/smb-signing-breaks-csv-access-crossnode?forum=winserverClustering) disable SMB signing/encryption
  - Create Failover Cluster
    - If you use Failover Cluster to protect VMs, that becomes default location to create protected VMs (Hyper-V Manager is no longer used)
  - Add quorum disk to Failover Cluster
- Deploy Cluster Shared Volumes
  - On all Windows hosts, login to SolidFire volumes meant for data
  - On one Windows host, bring those volumes online and format them
  - In the Failover Cluster GUI (assuming you use it to provide HA to VMs), add new cluster disk(s) and convert them to Cluster Shared Volumes
  - When deploying VMs, place them on a CSV or change Hyper-V defaults
- [Optional] Install (out-of-band) SolidFire Management VM on cluster shared storage. It can monitor SolidFire events and hardware and alert NetApp Support to problems, as well as give you actionable info via NetApp ActiveIQ analytics
- [Optional] Install and configure NetApp OneCollect for scheduled gathering of sytem events and configuration changes. It can be extremely helpful in case of technical issues with the cluster

## Microsoft Windows on NetApp HCI Servers ("Compute Nodes")

### NetApp H410C

- There are no "official" NetApp-released drivers and firmware for Microsoft Windows, so we can use latest & greatest vendor-released drivers and firmware
- Links to must-install drivers for Windows on NetApp H410C. The URLs link to a recent driver file for each
  - Intel C620 chpiset driver ([v10.1.17903.8106](https://downloadcenter.intel.com/download/28531/Intel-Server-Chipset-Driver-for-Windows-))
  - Mellanox ConnectX-4 Lx NIC driver ([v2.30.51000](https://www.mellanox.com/products/adapter-software/ethernet/windows/winof-2))
  - Intel X550 NIC driver ([v25.0](https://downloadcenter.intel.com/download/28396/Intel-Network-Adapter-Driver-for-Windows-Server-2019-?product=88207))

#### Network adapters and ports

- SIOM Port 1 & 2 are 1/10 GigE Intel X550 (RJ-45)
- The rest are Mellanox Connect-4 Lx with SFP28 (2 dual-ported NICs)
  - Up to 6 ports that may be used by Windows, from left to right we label them A through F (HCI Port column)
- IPMI (RJ-45) port is not shown

```
| PCI | NIC  | Bus | Device | Func | HCI Port | Default OS Name   | Description (numeric suffix varies)     |
|-----|------|-----|--------|------|----------|-------------------|-----------------------------------------|
| 6   |  x   | 24  | 0      | 0    | A        | SIOM Port 1       | Intel(R) Ethernet Controller X550       |
| 6   |  x   | 24  | 0      | 1    | B        | SIOM Port 2       | Intel(R) Ethernet Controller X550       |
| 7   | NIC1 | 25  | 0      | 0    | C        | Ethernet 1        | Mellanox ConnectX-4 Lx Ethernet Adapter |
| 7   | NIC1 | 25  | 0      | 1    | D        | Ethernet 2        | Mellanox ConnectX-4 Lx Ethernet Adapter |
| 1   | NIC2 | 59  | 0      | 1    | E        | CPU1 Slot1 Port 1 | Mellanox ConnectX-4 Lx Ethernet Adapter |
| 1   | NIC2 | 59  | 0      | 0    | F        | CPU1 Slot1 Port 2 | Mellanox ConnectX-4 Lx Ethernet Adapter |
```

- NetApp HCI H410C with 6 cables and ESXi uses vSS (switch) and assigns ports as per below. With Windows Server we may configure them differently

```
| HCI Port | Mode   | Purpose                       |
|----------|--------|-------------------------------|
| A        | Access | Management                    |
| B        | Access | Management                    |
| C        | Trunk  | VM Network & Live Migration   |
| D        | Trunk  | iSCSI                         |
| E        | Trunk  | iSCSI                         |
| F        | Trunk  | VM Network & Live Migration   |
```

- NetApp HCI H410C with 2 cables uses vDS (see H615C below)

### NetApp H615C

- Two Mellanox Connect-4 Lx
- IPMI (RJ-45) port is not shown
- NetApp HCI with ESXi uses vDS with switch ports in Trunk Mode which roughly translates to Windows Server Datacenter Edition with Network Controller

## Demo Videos

- [Cluster Shared Volumes](https://youtu.be/GL9S6GkP-Z8) (Windows Server 2019 (Hyper-V) on NetApp H410C connected to SolidFire 11.7 (NetApp HCI H410S) using Mellanox SN2010 25G Ethernet)

## Frequently Asked Questions

Q: Is this what NetApp recommends?

A: No. While some of this may be correct, please refer to the official documentation.

## License and Trademarks

- NetApp, SolidFire and other marks are owned by NetApp, Inc. Other marks may be owned by their respective owners.
- See [LICENSE](LICENSE).
