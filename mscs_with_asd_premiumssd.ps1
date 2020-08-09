# THIS CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF
# ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
# PARTICULAR PURPOSE.
# Author: Patrick Shim (pashim@microsoft.com)
# Copyright (c) Microsoft Corporation. All rights reserved

#Connect-AzAccount

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
$resourceGroupName = "asd-test-resources" # 리소스 그룹 이름
$location = "westcentralus"

$avsName = "asd_test_avs_01"
$nsgName = "asd_test_nsg_01"

$vntName = "asd_test_vnt_01"
$vNetAddressPrefix = "192.168.0.0/16"

$subNetName_01 = "asd_subnet_01"
$subNetName_02 = "asd_subnet_02"

$subNetAddressPrefix_01 = "192.168.1.0/24"
$subNetAddressPrefix_02 = "192.168.2.0/24"

#VM 용 스토리지 계정 (이름 변경 후 사용)
$storageAccountName = "asdtestpstrgacct"
$storageAccountSku = "Standard_LRS"

$ilbIpAddress_01_01 = "192.168.1.101"
$ilbIpAddress_01_02 = "192.168.1.102"

$healthProbe_01_01 = 59998
$healthProbe_01_02 = 59999

$VmSku    = "Standard_d32S_V3"
$VmSku_DC = "Standard_d4s_v3"
$windowsSku = "2016-Datacenter"

$disksize = 8192

# MSCS 파일 서비스 이름
$fileservername = "asd-files-smb"

# 클라우드 쿼럼용 스토리지 계정 (이름 변경 후 사용)
# 스토리지 계정 키는 스크립트 실행 후 화면에 표시됨
$witnessStorageAccountName = "asdtestpwitness"
$vmConfigurationStorageAccountName = "csustorageaccountstdv2"
$vmConfigurationStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName csu-core-resources -Name $vmConfigurationStorageAccountName).Value[0]

#######################################################
### ASD 울트라인 경우 Availability Zone으로 구성
### ASD 프리미엄 은 Availability Set (AVS)으로 구성
### $zone = 2
#######################################################

# Windows 어드민 계정 (변경 후 사용)
 
$credential = Get-Credential -Message "Enter Windows admin user name and password"
$OSAdmin = $credential.UserName

# 도메인컨트롤러 도메인 명 및 계정 설정 (변경 후 사용)
$domainName = Read-Host -Prompt "Enter domain name (example.com)"
$domainPassword = Read-Host -Prompt "Enter password for the dmain ($domainName)" 
$domainNamNetBios = ($domainName.Split(".", 2).ToUpper() | Select-Object -Index 0)
$domainUserName = ($domainNamNetBios + "\" + $OSAdmin)
$domainCredential = Get-Credential -Message "Enter domain admin password for $domainUserName" -UserName $domainUserName

# VM에 할당될 이름 (변경 후 사용)
$vmName_01 = "mscs-asd-01"
$vmName_02 = "mscs-asd-02"
$vmName_03 = "mscs-asd-03"
$vmName_04 = "mscs-asd-04"

# 공인 IP에 설정된 DNS 이름 (변경 후 사용)
$domainLeafNameForPublicIp_01 = "pip-" + $vmName_01 # 애져 상 기존 이름과 중복일 수 있으니, 필요하면 고유 이름으로 변경 (15자 이내)
$domainLeafNameForPublicIp_02 = "pip-" + $vmName_02 # 애져 상 기존 이름과 중복일 수 있으니, 필요하면 고유 이름으로 변경 (15자 이내)
$domainLeafNameForPublicIp_03 = "pip-" + $vmName_03 # 애져 상 기존 이름과 중복일 수 있으니, 필요하면 고유 이름으로 변경 (15자 이내)
$domainLeafNameForPublicIp_04 = "pip-" + $vmName_04 # 애져 상 기존 이름과 중복일 수 있으니, 필요하면 고유 이름으로 변경 (15자 이내)

#######################################################
### 각 VM 설치후 실행되는 포스트 스크립의 저장소 
### 1. 스토리지 계정 및 BLOB CONTAINER 생성
### 2. 생성된 container로 dc 및 vm 구성 스크립트 카피
### 3. 각 VM에서 접근할 수 있도록 아래 변수 수정
#######################################################
$containerName = "vmconfigs"
$configStorageAccountEndPointSuffix = "core.windows.net"
$dcconfigFileName = "dc_configuration.ps1"
$vmconfigFileName = "vm_configuration.ps1"

#######################################################
### WARNING : RG이름이 같을 경우 기존의 RG를 모두 지워 버림
#######################################################

Get-AzResourceGroup -Name $resourceGroupName -ErrorVariable doesNotExist -ErrorAction SilentlyContinue

if (!$doesNotExist) 
{
    Write-Host "Resource Group already exists.  Deleting and re-creating..."
    Remove-AzResourceGroup -Name $resourceGroupName -Force
    Write-Host "Deleting Resource Group succeeded..."
}

Write-Host "Creating Resource Group..."
New-AzResourceGroup `
    -Name $resourceGroupName `
    -Location $location
   
Write-Host "Creating Storage Account..."
New-AzStorageAccount `
    -Name $storageAccountName `
    -Location $location `
    -SkuName $storageAccountSku `
    -ResourceGroupName $resourceGroupName `

Write-Host "Creating Storage Account for Witness..."
New-AzStorageAccount `
    -Name $witnessStorageAccountName `
    -Location $location `
    -SkuName $storageAccountSku `
    -ResourceGroupName $resourceGroupName `

Write-Host "Creating Proximity Placement Group..."
$ppg = New-AzProximityPlacementGroup `
    -ResourceGroupName $resourceGroupName `
    -Name "mscs_asd_ppg" `
    -Location $location `
    -ProximityPlacementGroupType Standard `

##### subnet-1 (External)
$subnet_config_01 = New-AzVirtualNetworkSubnetConfig `
    -Name $subNetName_01 `
    -AddressPrefix $subNetAddressPrefix_01

##### subnet-2 (Internal)
$subnet_config_02 = New-AzVirtualNetworkSubnetConfig `
    -Name $subNetName_02 `
    -AddressPrefix $subNetAddressPrefix_02

##### vnet
Write-Host "Creating Virtual Network..."
$vnet = New-AzVirtualNetwork `
    -Name $vntName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -AddressPrefix $vNetAddressPrefix `
    -subnet $subnet_config_01, $subnet_config_02 `
    -DnsServer '192.168.1.11', '8.8.8.8'

###################################################################
##### NSG Rules
###################################################################

$nsgRuleRPC = New-azNetworkSecurityRuleConfig `
    -Name RPC `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 997 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 135 `
    -Access Allow

$nsgRuleSmb = New-azNetworkSecurityRuleConfig `
    -Name SMB `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 998 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 445 `
    -Access Allow

$nsgRuleNetBIOS = New-azNetworkSecurityRuleConfig `
    -Name NetBIOS `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 999 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 139 `
    -Access Allow

$nsgRuleRdp = New-azNetworkSecurityRuleConfig `
    -Name RDP `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1000 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 3389 `
    -Access Allow

$nsgRuleProbe_01 = New-azNetworkSecurityRuleConfig `
    -Name Probe_01 `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1001 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 59999 `
    -Access Allow

$nsgRuleProbe_02 = New-azNetworkSecurityRuleConfig `
    -Name Probe_02 `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1002 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 59998 `
    -Access Allow
    
$nsgRuleWinRmHttp= New-azNetworkSecurityRuleConfig `
    -Name WinRmHttp `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1003 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 5985 `
    -Access Allow

$nsgRuleWinRmHttps= New-azNetworkSecurityRuleConfig `
    -Name WinRmHttps `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1004 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 5986 `
    -Access Allow

$nsgRuleIcmpV4= New-azNetworkSecurityRuleConfig `
    -Name IcmpV4 `
    -Protocol Icmp `
    -Direction Inbound `
    -Priority 1005 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange * `
    -Access Allow

$nsgRuleISCSI= New-azNetworkSecurityRuleConfig `
    -Name iSCSI-Target-Server `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1006 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 3260 `
    -Access Allow

Write-Host "Creating Network Security Group..."
$nsg = New-AzNetworkSecurityGroup `
    -Name $nsgName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -SecurityRules $nsgRuleRdp, $nsgRuleProbe_01, $nsgRuleProbe_02, $nsgRuleWinRmHttp, $nsgRuleWinRmHttps, $nsgRuleIcmpV4, $nsgRuleISCSI, $nsgRuleNetBIOS, $nsgRuleSmb, $nsgRuleRPC `

##### avs
Write-Host "Creating Availability Set 1..."
$avs = New-AzAvailabilitySet `
    -ResourceGroupName $resourceGroupName `
    -Name $avsName `
    -Location $location `
    -Sku Aligned `
    -PlatformFaultDomainCount 2 `
    -PlatformUpdateDomainCount 5

######################################################################
#### Azure Load Balancers 1
######################################################################

$frontend_config_01_01 = New-AzLoadBalancerFrontEndIpConfig `
    -Name "frontend_01_01" `
    -PrivateIpAddress $ilbIpAddress_01_01 `
    -SubnetId $vnet.Subnets[0].Id

$frontend_config_01_02 = New-AzLoadBalancerFrontEndIpConfig `
    -Name "frontend_01_02" `
    -PrivateIpAddress $ilbIpAddress_01_02 `
    -SubnetId $vnet.Subnets[0].Id

$backend_config_01_01 = New-AzLoadBalancerBackendAddressPoolConfig `
    -Name "backend_01_01" 

$backend_config_01_02 = New-AzLoadBalancerBackendAddressPoolConfig `
    -Name "backend_01_02" 

$probe_config_01_01 = New-AzLoadBalancerProbeConfig `
    -Name "probe_01_01" `
    -Protocol Tcp `
    -Port $healthProbe_01_01 `
    -IntervalInSeconds 5 `
    -ProbeCount 2

$probe_config_01_02 = New-AzLoadBalancerProbeConfig `
    -Name "probe_01_02" `
    -Protocol Tcp `
    -Port $healthProbe_01_02 `
    -IntervalInSeconds 5 `
    -ProbeCount 2

$rule_config_01_01 = New-AzLoadBalancerRuleConfig `
    -Name "rule_01_01" `
    -EnableFloatingIP:$true `
    -LoadDistribution Default `
    -Protocol All `
    -FrontendPort 0 `
    -BackendPort 0 `
    -BackendAddressPoolId $backend_config_01_01.Id `
    -FrontendIpConfigurationId $frontend_config_01_01.Id `
    -ProbeId $probe_config_01_01.Id
    
$rule_config_01_02 = New-AzLoadBalancerRuleConfig `
    -Name "rule_01_02" `
    -EnableFloatingIP:$true `
    -LoadDistribution Default `
    -Protocol All `
    -FrontendPort 0 `
    -BackendPort 0 `
    -BackendAddressPoolId $backend_config_01_01.Id `
    -FrontendIpConfigurationId $frontend_config_01_02.Id `
    -ProbeId $probe_config_01_02.Id

$ilb_01 = New-AzLoadBalancer `
    -ResourceGroupName $resourceGroupName `
    -Name "mscs_ilb_01" `
    -Location $location `
    -Sku Standard `
    -FrontendIpConfiguration $frontend_config_01_01, $frontend_config_01_02 `
    -BackendAddressPool $backend_config_01_01, $backend_config_01_02 `
    -LoadBalancingRule $rule_config_01_01, $rule_config_01_02 `
    -Probe $probe_config_01_01, $probe_config_01_02 `
    -Force:$true

######################################################################
##### public IP Configurations
######################################################################

Write-Host "Creating Public IP 01..."
$pip_01 = New-AzPublicIpAddress `
    -Name "pip_01" `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -AllocationMethod Static `
    -IdleTimeoutInMinute 4 `
    -Sku Standard `
    -IpAddressVersion IPv4 `
    -DomainNameLabel $domainLeafNameForPublicIp_01
    
Write-Host "Creating Public IP 02..."
$pip_02 = New-AzPublicIpAddress `
    -Name "pip_02" `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -AllocationMethod Static `
    -IdleTimeoutInMinute 4 `
    -Sku Standard `
    -IpAddressVersion IPv4 `
    -DomainNameLabel $domainLeafNameForPublicIp_02

Write-Host "Creating Public IP 03..."
$pip_03 = New-AzPublicIpAddress `
    -Name "pip_03" `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -AllocationMethod Static `
    -IdleTimeoutInMinute 4 `
    -Sku Standard `
    -IpAddressVersion IPv4 `
    -DomainNameLabel $domainLeafNameForPublicIp_03

Write-Host "Creating Public IP 04..."
$pip_04 = New-AzPublicIpAddress `
    -Name "pip_04" `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -AllocationMethod Static `
    -IdleTimeoutInMinute 4 `
    -Sku Standard `
    -IpAddressVersion IPv4 `
    -DomainNameLabel $domainLeafNameForPublicIp_04

########################################################################
##### NIC-01 (Domain Controller) 
########################################################################

Write-Host "Creating Network Interface 01-01..."
$nic_01_01 = New-AzNetworkInterface `
  -Name nic_01_01 `
  -ResourceGroupName $resourceGroupName `
  -Location $location `
  -SubnetId $vnet.Subnets[0].Id `
  -PublicIpAddressId $pip_01.Id `
  -PrivateIpAddress "192.168.1.11" `
  -DnsServer "192.168.1.11", "8.8.8.8" `
  -EnableAcceleratedNetworking `
  -NetworkSecurityGroupId $nsg.Id 

########################################################################
##### NIC-02 (MSCS - ASD Node 01) 
########################################################################

Write-Host "Creating Network Interface 02-01..."    
$nic_02_01 = New-AzNetworkInterface `
  -Name nic_02_01 `
  -ResourceGroupName $resourceGroupName `
  -Location $location `
  -SubnetId $vnet.Subnets[0].Id `
  -PublicIpAddressId $pip_02.Id `
  -PrivateIpAddress "192.168.1.12" `
  -DnsServer "192.168.1.11", "8.8.8.8" `
  -NetworkSecurityGroupId $nsg.Id `
  -EnableAcceleratedNetworking `
  -LoadBalancerBackendAddressPoolId $backend_config_01_01.Id ##### LB POOL 1

Write-Host "Creating Network Interface 02-02..."    
$nic_02_02 = New-AzNetworkInterface `
  -Name nic_02_02 `
  -ResourceGroupName $resourceGroupName `
  -Location $location `
  -SubnetId $vnet.Subnets[1].Id `
  -PrivateIpAddress "192.168.2.12" `
  -EnableAcceleratedNetworking `
  -NetworkSecurityGroupId $nsg.Id

########################################################################
##### NIC-03 (MSCS - ASD Node 02) 
########################################################################

Write-Host "Creating Network Interface 03-01..."
$nic_03_01 = New-AzNetworkInterface `
  -Name nic_03_01 `
  -ResourceGroupName $resourceGroupName `
  -Location $location `
  -SubnetId $vnet.Subnets[0].Id `
  -PublicIpAddressId $pip_03.Id `
  -PrivateIpAddress "192.168.1.13" `
  -DnsServer "192.168.1.11", "8.8.8.8" `
  -EnableAcceleratedNetworking `
  -NetworkSecurityGroupId $nsg.Id `
  -LoadBalancerBackendAddressPoolId $backend_config_01_01.id ##### LB POOL 2

  Write-Host "Creating Network Interface 03-02..."
$nic_03_02 = New-AzNetworkInterface `
  -Name nic_03_02 `
  -ResourceGroupName $resourceGroupName `
  -Location $location `
  -SubnetId $vnet.Subnets[1].Id `
  -PrivateIpAddress "192.168.2.13" `
  -EnableAcceleratedNetworking `
  -NetworkSecurityGroupId $nsg.Id

########################################################################
##### NIC-04 (TEST Node ) 
########################################################################

Write-Host "Creating Network Interface 04-01..."
$nic_04_01 = New-AzNetworkInterface `
  -Name nic_04_01 `
  -ResourceGroupName $resourceGroupName `
  -Location $location `
  -SubnetId $vnet.Subnets[0].Id `
  -PublicIpAddressId $pip_04.Id `
  -PrivateIpAddress "192.168.1.14" `
  -DnsServer "192.168.1.11", "8.8.8.8" `
  -EnableAcceleratedNetworking `
  -NetworkSecurityGroupId $nsg.Id

Write-Host "Creating Network Interface 04-02..."
$nic_04_02 = New-AzNetworkInterface `
  -Name nic_04_02 `
  -ResourceGroupName $resourceGroupName `
  -Location $location `
  -SubnetId $vnet.Subnets[1].Id `
  -PrivateIpAddress "192.168.2.14" `
  -EnableAcceleratedNetworking `
  -NetworkSecurityGroupId $nsg.Id

#######################################################################
##### Create a virtual machine configuration
#######################################################################

Write-Host "Creating VM-01... (Domain Controller)"
$vm_01_config = New-AzVMConfig -VMName $vmName_01 -VMSize $vmSku_DC -AvailabilitySetId $avs.Id | `
    Set-AzVMOperatingSystem -Windows -ComputerName $vmName_01 -Credential $credential | `
    Set-AzVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus $windowsSku -Version latest | `
    Add-AzVMNetworkInterface -Id $nic_01_01.Id -Primary 
    New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm_01_config -AsJob

Write-Host "Creating VM-02..."
$vm_02_config = New-AzVMConfig -VMName $vmName_02 -VMSize $VMSKU -AvailabilitySetId $avs.Id | `
    Set-AzVMOperatingSystem -Windows -ComputerName $vmName_02 -Credential $credential | `
    Set-AzVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus $windowsSku -Version latest | `
    Add-AzVMNetworkInterface -Id $nic_02_01.Id -Primary | `
    Add-AzVMNetworkInterface -Id $nic_02_02.Id 
    New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm_02_config -AsJob

Write-Host "Creating VM-03..."
$vm_03_config = New-AzVMConfig -VMName $vmName_03 -VMSize $VMSKU -AvailabilitySetId $avs.Id | `
    Set-AzVMOperatingSystem -Windows -ComputerName $vmName_03 -Credential $credential | `
    Set-AzVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus $windowsSku -Version latest | `
    Add-AzVMNetworkInterface -Id $nic_03_01.Id -Primary | `
    Add-AzVMNetworkInterface -Id $nic_03_02.Id
    New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm_03_config -AsJob

Write-Host "Creating VM-04..."
$vm_04_config = New-AzVMConfig -VMName $vmName_04 -VMSize $VMSKU -AvailabilitySetId $avs.Id| `
    Set-AzVMOperatingSystem -Windows -ComputerName $vmName_04 -Credential $credential | `
    Set-AzVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus $windowsSku -Version latest | `
    Add-AzVMNetworkInterface -Id $nic_04_01.Id -Primary | `
    Add-AzVMNetworkInterface -Id $nic_04_02.Id
    New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm_04_config -AsJob

Get-Job | Wait-Job 

#########################################################################
##### Azure Disk DISK config 
#########################################################################

$disk_config_01 = New-AzDiskConfig `
    -Location $location `
    -DiskSizeGB $disksize `
    -AccountType Premium_LRS `
    -CreateOption Empty `
    -MaxSharesCount 2
        
$disk = New-AzDisk -ResourceGroupName $resourceGroupName -DiskName 'disk_01' -Disk $disk_config_01

#########################################################################
##### Attach Shared Disk to both VMs
#########################################################################

$nodeVM_01 = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName_02
$nodeVM_01 = Add-AzVMDataDisk -VM $nodeVM_01 -Name "disk_01" -CreateOption Attach -ManagedDiskId $disk.Id -Lun 0
$nodeVM_02 = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName_03
$nodeVM_02 = Add-AzVMDataDisk -VM $nodeVM_02 -Name "disk_01" -CreateOption Attach -ManagedDiskId $disk.Id -Lun 0

Update-AzVM -VM $nodeVM_01 -ResourceGroupName $resourceGroupName
Update-AzVM -VM $nodeVM_02 -ResourceGroupName $resourceGroupName

#########################################################################
##### Custom Script Extension (post-installation of features on each VMs)
#########################################################################

Write-Host "custom script extension on VM-01"
Set-AzVMCustomScriptExtension `
    -VMName $vmName_01 `
    -Name CustomScriptExtension `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -ContainerName $containerName `
    -FileName $dcconfigFileName `
    -StorageAccountName $vmConfigurationStorageAccountName `
    -StorageEndpointSuffix $configStorageAccountEndPointSuffix `
    -StorageAccountKey $vmConfigurationStorageAccountKey `
    -Run $dcconfigFileName 
   
Write-Host "custom script extension on VM-02"
Set-AzVMCustomScriptExtension `
    -VMName $vmName_02 `
    -Name CustomScriptExtension `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -ContainerName $containerName `
    -FileName $vmconfigFileName `
    -StorageAccountName $vmConfigurationStorageAccountName `
    -StorageEndpointSuffix $configStorageAccountEndPointSuffix `
    -StorageAccountKey $vmConfigurationStorageAccountKey `
    -Run $vmconfigFileName

Write-Host "custom script extension on VM-03"
Set-AzVMCustomScriptExtension `
    -VMName $vmName_03 `
    -Name CustomScriptExtension `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -ContainerName $containerName `
    -FileName $vmconfigFileName `
    -StorageAccountName $vmConfigurationStorageAccountName `
    -StorageEndpointSuffix $configStorageAccountEndPointSuffix `
    -StorageAccountKey $vmConfigurationStorageAccountKey `
    -Run $vmconfigFileName

Write-Host "custom script extension on VM-04"
Set-AzVMCustomScriptExtension `
    -VMName $vmName_04 `
    -Name CustomScriptExtension `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -ContainerName $containerName `
    -FileName $vmconfigFileName `
    -StorageAccountName $vmConfigurationStorageAccountName `
    -StorageEndpointSuffix $configStorageAccountEndPointSuffix `
    -StorageAccountKey $vmConfigurationStorageAccountKey `
    -Run $vmconfigFileName

##########################################################################
##### remote commands to install DC, Az modules, and to join domain
##########################################################################

# vm-01
Write-Host "Running remote script vm-01..."
$session = New-PSSession -ComputerName ($domainLeafNameForPublicIp_01 + "." + $location + "." + "cloudapp.azure.com") -Credential $credential
$scriptBlock = {
    param($domainPassword, $domainName, $domainNamNetBios)
    $securedPwd = ConvertTo-SecureString $domainPassword -AsPlainText -Force
    Install-ADDSForest `
        -CreateDnsDelegation:$false `
        -SafeModeAdministratorPassword $securedPwd `
        -DatabasePath “C:\Windows\NTDS” `
        -DomainMode “Win2012R2” `
        -DomainName $domainName `
        -DomainNetbiosName $domainNamNetBios `
        -ForestMode “Win2012R2” `
        -InstallDns:$true `
        -LogPath “C:\Windows\NTDS” `
        -NoRebootOnCompletion:$false `
        -SysvolPath “C:\Windows\SYSVOL” `
        -Force:$true
}
Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $domainPassword, $domainName ,$domainNamNetBios

Start-Sleep 300 # give it 10 minutes for Domain Controller to get online functional

##########################################################################
##### remote commands to install DC, Az modules, and to isntall Az Modules
##########################################################################

# install az for powershell on all VMs
$session = New-PSSession -Credential $credential -ComputerName `
    ($domainLeafNameForPublicIp_01 + "." + $location + "." + "cloudapp.azure.com"), `
    ($domainLeafNameForPublicIp_02 + "." + $location + "." + "cloudapp.azure.com"), `
    ($domainLeafNameForPublicIp_03 + "." + $location + "." + "cloudapp.azure.com"), `
    ($domainLeafNameForPublicIp_04 + "." + $location + "." + "cloudapp.azure.com")
$scriptBlock = {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name Nuget -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
}
Invoke-Command -Session $session -ScriptBlock $scriptBlock

# copy mscs config flie from blob to one of node VMs.  
$session = New-PSSession -Credential $credential -ComputerName `
    ($domainLeafNameForPublicIp_02 + "." + $location + "." + "cloudapp.azure.com")
$scriptBlock = {
    azcopy.exe copy 'https://csustorageaccountstdv2.blob.core.windows.net/vmconfigs/mscs_configuration.ps1?sv=2019-12-12&ss=bf&srt=sco&sp=rwdlacx&se=2025-08-09T12:50:23Z&st=2020-08-09T04:50:23Z&spr=https&sig=HY7DCp%2FsqVx9ea5Kth3BTH88nBWlEDq22GZNhqK%2B13g%3D' 'C:\Users\Public\Documents\'
}
Invoke-Command -Session $session -ScriptBlock $scriptBlock

##########################################################################
##### remote commands to install DC, Az modules, and to isntall Az Modules
##########################################################################

### DNS entries for file server, cluster
$session = New-PSSession -Credential $credential -ComputerName `
    ($domainLeafNameForPublicIp_01 + "." + $location + "." + "cloudapp.azure.com")
$scriptBlock = {
    param($domainName, $fileservername)
    Add-DnsServerResourceRecordA -Name "mscs-asd-cluster"  -ZoneName $domainName -AllowUpdateAny -IPv4Address "192.168.1.10" -TimeToLive 01:00:00
    Add-DnsServerResourceRecordA -Name $fileservername  -ZoneName $domainName -AllowUpdateAny -IPv4Address "192.168.1.101" -TimeToLive 01:00:00
}
Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $domainName, $fileservername

### VM joins domain and reboot
$session = New-PSSession -Credential $credential -ComputerName `
    ($domainLeafNameForPublicIp_02 + "." + $location + "." + "cloudapp.azure.com"), `
    ($domainLeafNameForPublicIp_03 + "." + $location + "." + "cloudapp.azure.com"), `
    ($domainLeafNameForPublicIp_04 + "." + $location + "." + "cloudapp.azure.com")

    $scriptBlock = {
    param($domainName, $domainCredential)
    Add-Computer -DomainName $domainName -Credential $domainCredential -Restart -Force
}
Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $domainName, $domainCredential

##########################################################################
##### Storage Key for Cloud Witness Bob 
##### 이것을 복사해다가 MSCS 구성 시 변수값에 대입
##########################################################################

$key = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $witnessStorageAccountName | Where-Object {$_.KeyName -eq "key1"}).Value
Write-Output "Storage Account Name for Cloud Witness: $witnessStorageAccountName"
Write-Output "Storage Account Key for Cloud Witness: $key"