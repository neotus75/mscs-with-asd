# THIS CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF
# ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
# PARTICULAR PURPOSE.
# Author: Patrick Shim (pashim@microsoft.com)
# Copyright (c) Microsoft Corporation. All rights reserved

$driveLetter = Read-Host -Prompt "Enter drive letter for cluster volume (example: x)"
$stroageAccountName = Read-Host -Prompt "Enter stroage account name for cloud witness"
$stroageAccountKey = Read-Host -Prompt "Enter storage account key for cloud witness"

$diskNumber = (Get-Disk | Where-Object FriendlyName -eq 'Msft Virtual Disk' | Select-Object 'Number').Number
Initialize-Disk -Number $diskNumber -PartitionStyle GPT
New-Partition -UseMaximumSize -DiskNumber $diskNumber -DriveLetter $driveLetter
Format-Volume -DriveLetter $driveLetter -FileSystem ReFS -NewFileSystemLabel "Data Drive" -Force

######################################################################################
# 
# MSCS 노드 1 또는 2에서 실행
#
# The following script needs to run on ONE of the nodes in the cluster LOCALLY, 
# and it is not a part of the batch script above. Also note that there are two 
# clusters (one for MSCSI iSCSI target server and the other for application).  
#######################################################################################

# 1. create cluster service using static IP address
New-Cluster -Name mscs-asd-cluster -Node ("mscs-asd-02", "mscs-asd-03") -StaticAddress "192.168.1.10" -NoStorage 

# 2. set cloud witness quorum (번거롭지만... 메인 스크립트 실행 후 리턴되는 키값을 복제해다가 여기에 삽입"
Set-ClusterQuorum -CloudWitness -AccountName $stroageAccountName -AccessKey $stroageAccountKey

# 3. 클러스터 디스크 추가
$clusterDiskName = (Get-ClusterAvailableDisk | Add-ClusterDisk).Name

# 4. 클러스터 역할 설정 
Add-ClusterFileServerRole -Name "asd-files-smb" -Storage $clusterDiskName  -StaticAddress "192.168.1.101"

# 5. SMB 파일 서비스 추가 (노드에서 수동으로 구성)

# 6. define resource network / probe domain from LB
$ClusterNetworkName = "Cluster Network 1" # 랜카드가 여러장일때, 가끔 Cluster Network 2 또는 다른 번호로 잡히는 경우가 있음.
$ClusterIp = "192.168.1.101"
$ClusterIpResourceName = "IP Address $clusterIp" 
$Probe = 59998

Import-Module FailoverClusters

Get-ClusterResource $ClusterIpResourceName | Set-ClusterParameter -Multiple @{
    "Address"="$ClusterIp";
    "ProbePort"="$Probe";
    "SubnetMask"="255.255.255.255";
    "Network"="$ClusterNetworkName";
    "EnableDhcp"=0
}
