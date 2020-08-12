Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
# THIS CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF
# ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
# PARTICULAR PURPOSE.
# Author: Patrick Shim (pashim@microsoft.com)
# Copyright (c) Microsoft Corporation. All rights reserved

$rsg_name               = "asd-pcmk-resources"
$rsg_location           = "southeastasia"

$os_offer               = "RHEL-HA"
$os_publisher           = "Redhat"
$os_sku                 = "7.6"

#$os_offer               = "UbuntuServer"
#$os_publisher           = "Canonical"
#$os_sku                 = "18.04-LTS"

$vm_sku                 = "Standard_d4s_v3"
$vm_disksize            = 1024
$vm_disk_iops           = 2048
$vm_disk_mbps           = 16
$vm_zone                = 3

$sa_name                = "pcmkvmstgaccount"
$avs_name               = "pmkr-avs-01"
$lb_probe               = 59998

$node_vm_01_name        = "vm-pcmk-01" # node 01
$node_vm_02_name        = "vm-pcmk-02" # node 02
$node_vm_03_name        = "vm-pcmk-03" # node 03
$node_vm_04_name        = "vm-pcmk-04" # test node 

$pip_name_01            = "pip-" + $node_vm_01_name
$pip_name_02            = "pip-" + $node_vm_02_name
$pip_name_03            = "pip-" + $node_vm_03_name
$pip_name_04            = "pip-" + $node_vm_04_name

$nic_name_01_01         = "nic-pcmk-01-01"
$nic_name_01_02         = "nic-pcmk-01-02"
$nic_name_02_01         = "nic-pcmk-02-01"
$nic_name_02_02         = "nic-pcmk-02-02"
$nic_name_03_01         = "nic-pcmk-03-01"
$nic_name_03_02         = "nic-pcmk-03-02"
$nic_name_04_01         = "nic-pcmk-03-01"
$nic_name_04_02         = "nic-pcmk-03-02"

$avs_name               = "avs-pcmk-01"
$nsg_name               = "nsg-pcmk-01"
$ilb_name               = "lib-pcmk-01"

$vnet_subnet_names_01   = "snt-pcmk-01"
$vnet_subnet_names_02   = "snt-pcmk-02"
$vnet_name              = "vnt-pcmk-01"
$vnet_ipaddr_space      = "192.168.0.0/16"
$vnet_subnet_space_01   = "192.168.1.0/24"
$vnet_subnet_space_02   = "192.168.2.0/24"
$vip_01                 = "192.168.1.10"

$iip_01_01              = "192.168.1.11"
$iip_02_01              = "192.168.1.12"
$iip_03_01              = "192.168.1.13"
$iip_04_01              = "192.168.1.14"

$iip_01_02              = "192.168.2.11"
$iip_02_02              = "192.168.2.12"
$iip_03_02              = "192.168.2.13"
$iip_04_02              = "192.168.2.14"

###############################################################################
# Linux OS credential (user / pass) 
###############################################################################

$credential = Get-Credential

###############################################################################
# Resource Group 
###############################################################################

$rsg = New-AzResourceGroup `
    -Name $rsg_name `
    -Location $rsg_location
Write-Host $rsg.ResourceGroupName created...

###############################################################################
# Storage Account
###############################################################################

Write-Host "Creating Storage Account..."
$sta = New-AzStorageAccount `
    -Name $sa_name `
    -Location $rsg_location `
    -SkuName Standard_LRS `
    -ResourceGroupName $rsg_name 
Write-Host $sta.StorageAccountName created...

###############################################################################
# Availability Set
###############################################################################

Write-Host "creating availability set..."
$avs = New-AzAvailabilitySet `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -Name $avs_name `
    -Sku Aligned `
    -PlatformFaultDomainCount  2 `
    -PlatformUpdateDomainCount 5 
Write-Host $avs.Name created...

###############################################################################
# Azure Virtual Network
###############################################################################

Write-Host "creating virtual network..."
$vnet_config_01 = New-AzVirtualNetworkSubnetConfig `
    -Name $vnet_subnet_names_01 `
    -AddressPrefix $vnet_subnet_space_01

$vnet_config_02 = New-AzVirtualNetworkSubnetConfig `
    -Name $vnet_subnet_names_02 `
    -AddressPrefix $vnet_subnet_space_02


$vnet = New-AzVirtualNetwork `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -Name $vnet_name `
    -AddressPrefix $vnet_ipaddr_space `
    -Subnet $vnet_config_01, $vnet_config_02
Write-Host $vnet.Name created...

###############################################################################
# Network Security Group
###############################################################################

Write-Host "creating network security group..."
$nsg_config_01 = New-azNetworkSecurityRuleConfig `
    -Name SSH `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1002 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 22 `
    -Access Allow

$nsg_config_02 = New-azNetworkSecurityRuleConfig `
    -Name IcmpV4 `
    -Protocol Icmp `
    -Direction Inbound `
    -Priority 1003 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange * `
    -Access Allow

$nsg = New-AzNetworkSecurityGroup `
    -Name $nsg_name `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -SecurityRules $nsg_config_01, $nsg_config_02
Write-Host $nsg.Name created...

######################################################################
#### Azure Load Balancers 
######################################################################

$frontend_config_01 = New-AzLoadBalancerFrontEndIpConfig `
    -Name "frontend_01" `
    -PrivateIpAddress $vip_01 `
    -SubnetId $vnet.Subnets[0].Id

$backend_config_01 = New-AzLoadBalancerBackendAddressPoolConfig `
    -Name "backend_01" `

$probe_config_01 = New-AzLoadBalancerProbeConfig `
    -Name "probe_01" `
    -Protocol Tcp `
    -Port $lb_probe `
    -IntervalInSeconds 5 `
    -ProbeCount 2

$rule_config_01 = New-AzLoadBalancerRuleConfig `
    -Name "rule_01" `
    -EnableFloatingIP:$true `
    -LoadDistribution Default `
    -Protocol All `
    -FrontendPort 0 `
    -BackendPort  0 `
    -BackendAddressPoolId $backend_config_01.Id `
    -FrontendIpConfigurationId $frontend_config_01.Id `
    -ProbeId $probe_config_01.Id
    
$ilb = New-AzLoadBalancer `
    -ResourceGroupName $rsg_name `
    -Name $ilb_name `
    -Location $rsg_location `
    -Sku Standard `
    -FrontendIpConfiguration $frontend_config_01 `
    -BackendAddressPool $backend_config_01 `
    -LoadBalancingRule $rule_config_01 `
    -Probe $probe_config_01 `
    -Force:$true
Write-Host $ilb.Name created...

###############################################################################
# Public IP Address
###############################################################################

$pip_01 = New-AzPublicIpAddress `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location -Sku Standard `
    -AllocationMethod Static `
    -IpAddressVersion IPv4 `
    -name $pip_name_01 `
    -DomainNameLabel $pip_name_01
Write-Host $pip_01.Name created...

$pip_02 = New-AzPublicIpAddress `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -Sku Standard `
    -AllocationMethod Static `
    -IpAddressVersion IPv4 `
    -name $pip_name_02 `
    -DomainNameLabel $pip_name_02
Write-Host $pip_02.Name created...

$pip_03 = New-AzPublicIpAddress `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -Sku Standard `
    -AllocationMethod Static `
    -IpAddressVersion IPv4 `
    -name $pip_name_03 `
    -DomainNameLabel $pip_name_03
Write-Host $pip_03.Name created...

$pip_04 = New-AzPublicIpAddress `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -Sku Standard  `
    -AllocationMethod Static `
    -IpAddressVersion IPv4 `
    -name $pip_name_04 `
    -DomainNameLabel $pip_name_04
Write-Host $pip_04.Name created...

###############################################################################
# Network Interface Cards
###############################################################################

# NIC 1-1
$nic_01_01 = New-AzNetworkInterface `
    -Name $nic_name_01_01 `
    -Location $rsg_location `
    -ResourceGroupName $rsg_name `
    -SubnetId $vnet.Subnets[0].Id `
    -PublicIpAddressId $pip_01.Id `
    -PrivateIpAddress $iip_01_01 `
    -EnableAcceleratedNetworking `
    -NetworkSecurityGroupId $nsg.Id `
    -LoadBalancerBackendAddressPoolId $backend_config_01.Id
Write-Host $nic_01_01.Name created...

# NIC 1-2
$nic_01_02 = New-AzNetworkInterface `
    -Name $nic_name_01_02 `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -SubnetId $vnet.Subnets[1].Id `
    -PrivateIpAddress $iip_01_02 `
    -EnableAcceleratedNetworking `
    -NetworkSecurityGroupId $nsg.Id
Write-Host $nic_01_02.Name created...

# NIC 2-1
$nic_02_01 = New-AzNetworkInterface `
    -Name $nic_name_02_01 `
    -Location $rsg_location `
    -ResourceGroupName $rsg_name `
    -SubnetId $vnet.Subnets[0].Id `
    -PublicIpAddressId $pip_02.Id `
    -PrivateIpAddress $iip_02_01 `
    -EnableAcceleratedNetworking `
    -NetworkSecurityGroupId $nsg.Id `
    -LoadBalancerBackendAddressPoolId $backend_config_01.Id
Write-Host $nic_02_01.Name created...

# NIC 2-1
Write-Host "Creating Network Interface 02-02..."    
$nic_02_02 = New-AzNetworkInterface `
    -Name $nic_name_02_02 `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -SubnetId $vnet.Subnets[1].Id `
    -PrivateIpAddress $iip_02_02 `
    -EnableAcceleratedNetworking `
    -NetworkSecurityGroupId $nsg.Id
Write-Host $nic_02_02.Name created...

# NIC 3-1
$nic_03_01 = New-AzNetworkInterface `
    -Name $nic_name_03_01 `
    -Location $rsg_location `
    -ResourceGroupName $rsg_name `
    -SubnetId $vnet.Subnets[0].Id `
    -PublicIpAddressId $pip_03.Id `
    -PrivateIpAddress $iip_03_01 `
    -EnableAcceleratedNetworking `
    -NetworkSecurityGroupId $nsg.Id `
    -LoadBalancerBackendAddressPoolId $backend_config_01.Id
Write-Host $nic_03_01.Name created...

# NIC 3-2
Write-Host "Creating Network Interface 02-02..."    
$nic_03_02 = New-AzNetworkInterface `
    -Name $nic_name_03_02 `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -SubnetId $vnet.Subnets[1].Id `
    -PrivateIpAddress $iip_03_02 `
    -EnableAcceleratedNetworking `
    -NetworkSecurityGroupId $nsg.Id
Write-Host $nic_03_02.Name created...

# NIC 4-1
$nic_04_01 = New-AzNetworkInterface `
    -Name $nic_name_04_01 `
    -Location $rsg_location `
    -ResourceGroupName $rsg_name `
    -SubnetId $vnet.Subnets[0].Id `
    -PublicIpAddressId $pip_04.Id `
    -PrivateIpAddress $iip_04_01 `
    -EnableAcceleratedNetworking `
    -NetworkSecurityGroupId $nsg.Id
Write-Host $nic_04_01.Name created...

# NIC 4-2
$nic_04_02 = New-AzNetworkInterface `
    -Name $nic_name_04_02 `
    -Location $rsg_location `
    -ResourceGroupName $rsg_name `
    -SubnetId $vnet.Subnets[1].Id `
    -PrivateIpAddress $iip_04_02 `
    -EnableAcceleratedNetworking `
    -NetworkSecurityGroupId $nsg.Id
Write-Host $nic_04_02.Name created...

###############################################################################
# Linux (Red Hat Enterprise 8.0) Virtual Machines
###############################################################################

# VM-01
Write-Host "Creating VM-01... "
$vm_config_01 = New-AzVMConfig `
    -VMName $node_vm_01_name `
    -VMSize $vm_sku `
    -Zone $vm_zone | `
Set-AzVMOperatingSystem `
    -Linux `
    -ComputerName $node_vm_01_name `
    -Credential $credential | `
Set-AzVMSourceImage `
    -PublisherName $os_publisher `
    -Offer $os_offer `
    -Skus $os_sku `
    -Version "latest" | `
Add-AzVMNetworkInterface `
    -Id $nic_01_01.Id -Primary | `
Add-AzVMNetworkInterface `
    -Id $nic_01_02.Id
New-AzVM `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -VM $vm_config_01 `
    -Zone $vm_zone `
    -AsJob

# VM-02
Write-Host "Creating VM-02... "
$vm_config_02 = New-AzVMConfig `
    -VMName $node_vm_02_name `
    -VMSize $vm_sku `
    -Zone $vm_zone | `
Set-AzVMOperatingSystem `
    -Linux `
    -ComputerName $node_vm_02_name `
    -Credential $credential | `
Set-AzVMSourceImage `
    -PublisherName $os_publisher `
    -Offer $os_offer `
    -Skus $os_sku `
    -Version "latest" | `
Add-AzVMNetworkInterface `
    -Id $nic_02_01.Id -Primary | `
Add-AzVMNetworkInterface `
    -Id $nic_02_02.Id
New-AzVM `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -VM $vm_config_02 `
    -Zone $vm_zone `
    -AsJob

# VM-03
Write-Host "Creating VM-03... "
$vm_config_03 = New-AzVMConfig `
    -VMName $node_vm_03_name `
    -VMSize $vm_sku -Zone $vm_zone | `
Set-AzVMOperatingSystem `
    -Linux `
    -ComputerName $node_vm_03_name `
    -Credential $credential | `
Set-AzVMSourceImage `
    -PublisherName $os_publisher `
    -Offer $os_offer `
    -Skus $os_sku `
    -Version "latest" | `
Add-AzVMNetworkInterface `
    -Id $nic_03_01.Id -Primary | `
Add-AzVMNetworkInterface `
    -id $nic_03_02.Id 
New-AzVM `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -VM $vm_config_03 `
    -Zone $vm_zone `
    -AsJob

# VM-04
Write-Host "Creating VM-04... "
$vm_config_04 = New-AzVMConfig `
    -VMName $node_vm_04_name `
    -VMSize $vm_sku `
    -Zone $vm_zone | `
Set-AzVMOperatingSystem `
    -Linux `
    -ComputerName $node_vm_04_name `
    -Credential $credential | `
Set-AzVMSourceImage `
    -PublisherName $os_publisher `
    -Offer $os_offer `
    -Skus $os_sku `
    -Version "latest" | `
Add-AzVMNetworkInterface `
    -Id $nic_04_01.Id -Primary | `
Add-AzVMNetworkInterface `
    -Id $nic_04_02.Id
New-AzVM `
    -ResourceGroupName $rsg_name `
    -Location $rsg_location `
    -VM $vm_config_04 `
    -Zone $vm_zone `
    -AsJob

Get-Job | Wait-Job
Write-Host VMs created...

###############################################################################
# Azure Shared Disk
###############################################################################

$disk_config_01 = New-AzDiskConfig `
    -Location $rsg_location `
    -DiskSizeGB $vm_disksize `
    -AccountType UltraSSD_LRS `
    -DiskIOPSReadWrite $vm_disk_iops `
    -DiskMBpsReadWrite $vm_disk_mbps `
    -CreateOption Empty `
    -MaxSharesCount 3 `
    -Zone $vm_zone    
$dsk = New-AzDisk -ResourceGroupName $rsg_name -DiskName 'disk_01' -Disk $disk_config_01
Write-Host $dsk.Name created...

#########################################################################
##### Enable Ultra SSD Support on each VMs
#########################################################################

Stop-AzVM -ResourceGroupName $rsg_name -Name $node_vm_01_name -Force -AsJob
Stop-AzVM -ResourceGroupName $rsg_name -Name $node_vm_02_name -Force -AsJob
Stop-AzVM -ResourceGroupName $rsg_name -Name $node_vm_03_name -Force -AsJob

Get-Job | Wait-Job

$node_vm_01 = Get-azVM -ResourceGroupName $rsg_name -Name $node_vm_01_name 
$node_vm_02 = Get-azVM -ResourceGroupName $rsg_name -Name $node_vm_02_name 
$node_vm_03 = Get-azVM -ResourceGroupName $rsg_name -Name $node_vm_03_name 

Update-AzVM -ResourceGroupName $rsg_name -VM $node_vm_01 -UltraSSDEnabled $true -AsJob
Update-AzVM -ResourceGroupName $rsg_name -VM $node_vm_02 -UltraSSDEnabled $true -AsJob
Update-AzVM -ResourceGroupName $rsg_name -VM $node_vm_03 -UltraSSDEnabled $true -AsJob

Get-Job | Wait-Job

Start-AzVM -ResourceGroupName $rsg_name -Name $node_vm_01_name -AsJob
Start-AzVM -ResourceGroupName $rsg_name -Name $node_vm_02_name -AsJob
Start-AzVM -ResourceGroupName $rsg_name -Name $node_vm_03_name -AsJob

Get-Job | Wait-Job

#########################################################################
##### Attach Shared Disk to both VMs
#########################################################################

$node_vm_01 = Get-AzVM -ResourceGroupName $rsg_name -Name $node_vm_01_name
$node_vm_01 = Add-AzVMDataDisk -VM $node_vm_01 -Name "disk_01" -CreateOption Attach -ManagedDiskId $dsk.Id -Lun 0

$node_vm_02 = Get-AzVM -ResourceGroupName $rsg_name -Name $node_vm_02_name
$node_vm_02 = Add-AzVMDataDisk -VM $node_vm_02 -Name "disk_01" -CreateOption Attach -ManagedDiskId $dsk.Id -Lun 0

$node_vm_03 = Get-AzVM -ResourceGroupName $rsg_name -Name $node_vm_03_name
$node_vm_03 = Add-AzVMDataDisk -VM $node_vm_03 -Name "disk_01" -CreateOption Attach -ManagedDiskId $dsk.Id -Lun 0

Update-AzVM -VM $node_vm_01 -ResourceGroupName $rsg_name 
Update-AzVM -VM $node_vm_02 -ResourceGroupName $rsg_name
Update-AzVM -VM $node_vm_03 -ResourceGroupName $rsg_name
Write-Host Attaching $dsk.Name to virtual machines completed...