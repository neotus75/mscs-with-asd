# THIS CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF
# ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
# PARTICULAR PURPOSE.
# Author: Patrick Shim (pashim@microsoft.com)
# Copyright (c) Microsoft Corporation. All rights reserved

# disable IE Enhanced Security
function Disable-InternetExplorerESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -Force
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -Force
    Stop-Process -Name Explorer -Force
    Write-Host "IE Enhanced Security Configuration (ESC) has been disabled." -ForegroundColor Green
}
function Enable-InternetExplorerESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 1 -Force
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 1 -Force
    Stop-Process -Name Explorer
    Write-Host "IE Enhanced Security Configuration (ESC) has been enabled." -ForegroundColor Green
}
function Disable-UserAccessControl {
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 00000000 -Force
    Write-Host "User Access Control (UAC) has been disabled." -ForegroundColor Green    
}
Disable-UserAccessControl
Disable-InternetExplorerESC

# WinRM 
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force
Get-Item WSMan:\localhost\Client\TrustedHosts

# 각각의 노드에서 윈도우즈 방화벽 설정
Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True 
Set-NetFirewallRule -DisplayGroup 'Windows Remote Management' -Enabled True
Set-NetFirewallRule -Group "@firewallapi.dll,-36751" -Profile Domain -Enabled true
New-NetFirewallRule -Name 'Status Probe_01' -DisplayName 'Status Probe' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 59998
New-NetFirewallRule -Name 'Status Probe_02' -DisplayName 'Status Probe' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 59999
New-NetFirewallRule -Name 'Chat Server' -DisplayName 'Chat Server Status Probe' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 56675
New-NetFirewallRule -Name 'MSDTC' -DisplayName 'MSDTC' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3372
New-NetFirewallRule -Name 'SQL' -DisplayName 'SQL' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 1433
New-NetFirewallRule -Name 'SQL-M' -DisplayName 'SQL-M' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 1434
New-NetFirewallRule -Name 'WinRmHttp' -DisplayName 'WinRmHttp' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985
New-NetFirewallRule -Name 'WinRmHttps' -DisplayName 'WinRmHttps' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5986
New-NetFirewallRule -Name 'Ping' -DisplayName 'ICMPv4'-Direction Inbound -Action Allow -Protocol ICMPv4 -LocalPort Any
New-NetFirewallRule -Name 'iSCSI' -DisplayName 'iSCSI-Portal'-Direction Inbound -Action Allow -Protocol Tcp -LocalPort 3260
New-NetFirewallRule -Name 'SMB' -DisplayName 'SMB' -Direction Inbound -Action Allow -Protocol Tcp -LocalPort 445
New-NetFirewallRule -Name 'RPC' -DisplayName 'RPC' -Direction Inbound -Action Allow -Protocol Tcp -LocalPort 135
New-NetFirewallRule -Name 'NetBIOS' -DisplayName 'NetBIOS' -Direction Inbound -Action Allow -Protocol Tcp -LocalPort 139
New-NetFirewallRule -Name 'NFS-PortMapper' -DisplayName 'NFS-PortMapper'-Direction Inbound -Action Allow -Protocol Tcp -LocalPort 111
New-NetFirewallRule -Name 'NFS' -DisplayName 'NFS'-Direction Inbound -Action Allow -Protocol Tcp -LocalPort 2049


# 필수 기능 설치
Install-WindowsFeature AD-Domain-Services, ADLDS, Telnet-Client -IncludeAllSubFeature -IncludeManagementTools
Import-Module -Name ADDSDeployment


