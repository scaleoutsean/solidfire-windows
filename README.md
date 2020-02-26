# solidfire-windows: Notes on Microsoft Windows with NetApp SolidFire

Notes on Windows Server Hyper-V clusters with NetApp SolidFire, including (but not limited to) NeApp HCI H410C (servers) and Mellanox SN2010 switches.

For additional SolidFire information, please refer to (Awesome SolidFire](https://github.com/scaleoutsean/awesome-solidfire).

## General Notes

- Each SolidFire volume is available on one network (subnet and VLAN)
  - Balancing across cluster nodes is done via RFC-standard iSCSI redirection
  - Teaming (LACP) gives you one path per volume and link redundancy, which is enough for 90% of workloads
- Multiple connections from one host to single volume (and MPIO) are rarely needed
  - One way to set up multiple connections is to create two Teams pairs and then in iSCSI Intiator setup create one connection from each adapter
  - Another way would be to use a pair of non-teamed interfaces
  - It is *not* possible to establish two connections to one volume with one initiator
- Windows Network Controller is available only in [Datacenter Edition](https://docs.microsoft.com/en-us/windows-server/get-started-19/editions-comparison-19). Network Controller doesn't matter to SolidFire, but Datacenter Edition has fewer other limtiations and may be used without Network Controller

## Windows Host and Guest Configuration Notes

- Networking
  - Consider using Jumbo Frames on networks used for iSCSI, Live Migration or backup
  - Consider using enterprise network switches such as Mellanox SN2010 (which you can get from NetApp)
  - Consider disabling IPv6 on interfaces on iSCSI network
  - Consider disabling NIC registration in DNS for interfaces on iSCSI network
  - Consider disabling DHCP service on iSCSI and Live Migration network(s)
  - It may be more convenient to combine 2 or 4 Mellanox NICs into 1 or 2 LACP Teams, and use Trunk mode and VLANs to segregate workloads
  - It looks like it's not easy to create workloads for which networking needs special tuning
- iSCSI
  - Increase the maximum duration of timeouts and lower the frequency of checks (not sure how much it matters)
- Multipath I/O
  - When adding vendor and product ID to MPIO configuration, use `SolidFir` and `SSD SAN`, respectively (only recommended if you use Multipath I/O)
  - There are no recent comparisons of various Multipath options so it's recommended to spend 30 minutes to evaluate them in your environment
- Disks
  - Maximum SolidFire volume size is 16TB
  - In the case of very large volumes or very busy workloads (e.g. sustained 30,000 IOPS or 300 MB/s) striped Dynamic Volumes may be used to spread I/O over several volumes, although they have some limitations (in terms of manageability Windows)
  - Another way to spread the workload is to put VM data on several disks, each placed on a different (Cluster Shared or other) SolidFire volume. This assumes it's not just one hot database table or file
  - The (Default) 4kB NTFS block size ought to work best in terms of efficiency, but there is no recent anectodal evidence so further investigation is needed
- Hyper-V
  - Note that Virtual Switches configured through the GUI have certain default values not immediately obvious to the user
  - Once you create up Virtual Switches, re-check IPv6, NIC binding order, and packet sizes on vEthernet NICs
  - Re-check Hyper-V Live Migration settings - make sure iSCSI and Management networks are lowest preference for Live Migration
- Automation
  - Deploy SolidFire PowerShell Tools for Windows - it is recommended to use SolidFire PowerShell Tools for PowerShell 5.1: `Install-Module -Name SolidFire  -Scope CurrentUser`
  - SolidFire VSS Provider for Windows Server 2019 and 2016
  - SolidFire is easy to automate (`New-SFVolume`, `Add-SFVolumeToVolumeAccessGroup`, after you've set up cluster, added iSCSI initiators and created QoS policies and Volume Access Groups)
  - It should be possible to automate SolidFire with Terraform or Ansible, but unless you already use (or want to use) those tools it's easy enough to put together a PowerShell script of your own
- Direct VM Access to iSCSI
  - Like with VMware "RDM", you need to make sure the VMs may access iSCSI network(s), and they must use unique (to each VM or clustered group of VMs) initiators, VAGs, SolidFire (CHAP) accounts and volumes
  - The NetApp Interoperability Matrix has information about supported SolidFire iSCSI clients (see Awesome-SolidFire for details)

## Generic workflow for Hyper-V Clusters with NetApp SolidFire

- Analyze all requirements (availability, security, performance, networking...)
- Formulate deployment plan
- Configure network switches
  - If you use NetApp HCI compute nodes, it's probably best to get NetApp H-Series SN2010 (Mellanox) L2 switches
- Deploy Windows hosts
  - Install base OS (Windows Server 2019 Datacenter Edition, for example)
  - Install drivers, plugins, modules, etc.
    - Solidfire VSS Provider v2 (hosts only)
    - SolidFire PowerShell Tools 1.5.1 for PowerShell 5.1 (management clients only)
    - Drivers: Mellanox (1), Intel (2) (NetApp HCI H410C)
  - Install required Windows features (Multipath I/O, Failover-Cluster, etc.) on Hyper-V hosts
  - Update OS
- Configure Windows hosts
  - Hostnames, timezone, network interfaces, routes, DNS (A & PTR including virtual IPs), DHCP, IPv6, etc.
  - Join Active Directory (recommended)
  - Make sure cluster members' DNS is pointed at ADS, and ADS can forward other requests upstream - DNS must function
  - Configure Hyper-V and virtual switches
    - If Hyper-V is configured for Kerberos, make sure Windows AD delegation for required resources is allowed with Kerberos
- Configure SolidFire storage
  - Create SolidFire cluster
  - Create DNS entries for SolidFire cluster (management interfaces, IPMI, out-of-band mNode)
  - Create and upload TLS certificates to SolidFire cluster (management, IPMI, out-of-band mNode)
  - Add Windows hosts' initiators, create volume access groups (VAGs), add initiators to the VAG
  - Create one low performance QoS policy for quorum volumes (e.g. Min 100, Max 300, Burst 500)
  - Create 1 quorum volume with the Quorum QoS storage policy and add it to the VAG
  - Configure iSCSI initiators and MultiPath I/O
  - Create one more (or several) QoS policies and several volumes for VMs (Cluster Shared Volumes) and add them to the Hyper-V VAG
    - Some scripts to get you started are available on Github
- Prepare hosts for Windows Failover Clustering
  - Login to quorum disk, bring it online and create NTFS volume on it
  - Check firewall, DNS, AD configuration
  - Recheck adapter binding, IPv6, DNS, as it may be messed up after Viritual Switch configuration
- Create Windows Failover Cluster
  - Validate configuration, especially DNS and firewall configuration
  - [Optionally](https://social.technet.microsoft.com/Forums/en-US/bf5285bc-fc72-474f-a0f4-232a2bd230b1/smb-signing-breaks-csv-access-crossnode?forum=winserverClustering) disable SMB signing/encryption
  - Create Failover Cluster
    - If you use Failover Cluster to protect VMs, that becomes default location (Hyper-V Manager is no longer used)
  - Add quorum disk to Failover Cluster
- Deploy Cluster Shared Volumes
  - On all Windows hosts, login to SolidFire volumes meant for data
  - On one Windows host, bring those volumes online and format them
  - In Failover Cluster GUI (assuming you use it to provide HA to VMs), add new cluster disk(s) and convert them to Cluster Shared Volumes
  - When deploying VMs, place them on a CSV or change Hyper-V defaults
- [Optional] Install (out-of-band) SolidFire Management VM on cluster shared storage
- [Optional] Install and configure NetApp OneCollect for period gathering of sytem events and configuration changes

## Microsoft Windows on NetApp HCI Servers ("Compute Nodes")

### NetApp H410C

- There are no "official" drivers and firmware for Microsoft Windows, so we can use latest & greatest vendor-released drivers and firmware
- Drivers (example) for NetApp H410C
  - Intel C620 chpiset driver ([v10.1.17903.8106](https://downloadcenter.intel.com/download/28531/Intel-Server-Chipset-Driver-for-Windows-))
  - Mellanox ConnectX-4 Lx NIC driver ([v2.30.51000](https://www.mellanox.com/products/adapter-software/ethernet/windows/winof-2))
  - Intel X550 NIC driver ([v25.0](https://downloadcenter.intel.com/download/28396/Intel-Network-Adapter-Driver-for-Windows-Server-2019-?product=88207))

#### Network adapters and ports

- SIOM Port 1 & 2 are 1/10 GigE Intel X550 (RJ-45)
- The rest are Mellanox Connect-4 Lx with SFP28 (2 dual-ported NICs)
  - Starting from left, there are 6 ports that may be used, A to F (see the HCI Port column)
- IPMI (RJ-45) is not shown

```
| PCI | NIC  | Bus | Device | Func | HCI Port | Default OS Name   | Description (numeric suffix varies)        |
|-----|------|-----|--------|------|----------|-------------------|--------------------------------------------|
| 6   |  x   | 24  | 0      | 0    | A        | SIOM Port 1       | Intel(R) Ethernet Controller X550          |
| 6   |  x   | 24  | 0      | 1    | B        | SIOM Port 2       | Intel(R) Ethernet Controller X550          |
| 7   | NIC1 | 25  | 0      | 0    | C        | Ethernet 1        | Mellanox ConnectX-4 Lx Ethernet Adapter    |
| 7   | NIC1 | 25  | 0      | 1    | D        | Ethernet 2        | Mellanox ConnectX-4 Lx Ethernet Adapter    |
| 1   | NIC2 | 59  | 0      | 1    | E        | CPU1 Slot1 Port 1 | Mellanox ConnectX-4 Lx Ethernet Adapter    |
| 1   | NIC2 | 59  | 0      | 0    | F        | CPU1 Slot1 Port 2 | Mellanox ConnectX-4 Lx Ethernet Adapter    |
```

### NetApp H615C

- Two Mellanox Connect-4 Lx
- IPMI (RJ-45)

## Demo Videos

- [Cluster Shared Volumes](https://youtu.be/GL9S6GkP-Z8) (Windows Server 2019 (Hyper-V) on NetApp H410C, SolidFire 11.7 on NetApp H410S and Mellanox SN2010)

## Frequently Asked Questions

Q: Is this what NetApp recommends?

A: No. While some of this may be correct, please refer to the official documentation.

## License and Trademarks

- NetApp, SolidFire and other marks are owned by NetApp, Inc. Other marks may be owned by their respective owners.
- See [LICENSE](LICENSE).
