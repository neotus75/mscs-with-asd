##########################################################################################
### WORK IN PROGRESS!!!!!! RHEL 7.4
##########################################################################################
# THIS CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF
# ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
# PARTICULAR PURPOSE.
# Author: Patrick Shim (pashim@microsoft.com)
# Copyright (c) Microsoft Corporation. All rights reserved
##########################################################################################
### THIS IS NOT A PROPER SHELL SCRIPT.  THIS IS ONLY A CHEAT_SHEET.  YOU NEED TO COPY and 
### PASTE LINE-BY-LINE TO FOLLOW
##########################################################################################
### run on each nodes
##########################################################################################

sudo -i

yum update -y
yum install pcs pacemaker fence-agents-azure-arm install nmap-ncat resource-agents -y

### add all nodes to /etc/hosts file
echo "192.168.1.11 smb-vm-pcmk-01" >> /etc/hosts
echo "192.168.1.12 smb-vm-pcmk-02" >> /etc/hosts
echo "192.168.1.13 smb-vm-pcmk-03" >> /etc/hosts
echo "192.168.1.14 smb-vm-pcmk-04" >> /etc/hosts
echo "192.168.1.15 smb-vm-pcmk-05" >> /etc/hosts

### set password for hacluster
echo 'hacluster' | passwd --stdin hacluster

### add firewall entry for pacemaker
firewall-cmd --permanent --add-service=high-availability
firewall-cmd --reload

### disable firewall just to make sure all nodes are communicating (not recommended)
systemctl disable firewalld

### start pacemaker service - and ensure it is running
systemctl start pcsd.service
systemctl enable pcsd.service
systemctl status pcsd.service

##########################################################################################
### run on only one node!!!
##########################################################################################

pcs cluster auth smb-vm-pcmk-01 smb-vm-pcmk-02 smb-vm-pcmk-03
pcs cluster setup --name smb-pcmk-cluster smb-vm-pcmk-01 smb-vm-pcmk-02 smb-vm-pcmk-03

### start pacemaker on all nodes
pcs cluster enable --all
pcs cluster start --all

##########################################################################################
### azure-cli installation only works on RHEL 7.7 and above.  
### rpm --import https://packages.microsoft.com/keys/microsoft.asc
### sh -c 'echo -e "[azure-cli] name=Azure CLI baseurl=https://packages.microsoft.com/yumrepos/azure-cli enabled=1 gpgcheck=1 gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
### yum install azure-cli
##########################################################################################

### this assumes you have azure cli on your linux box.   
# az login
# az ad sp create-for-rbac -n "rhel-pmkr-cluster" --role owner --scopes /subscriptions/a370ff12-d748-4091-8749-a21c085d368f/resourceGroups/asd-pcmk-resources
# {
#   "appId": "714a1fd2-0d8f-4260-a979-xxxxxxxxxx",
#   "displayName": "rhel-pmkr-cluster",
#   "name": "http://rhel-pmkr-cluster",
#   "password": "<APP_PASSWORD>",
#   "tenant": "72f988bf-86f1-41af-91ab-xxxxxxxxxx"
# }

### copy and paste your app information and replace the value below to create cluster fencing
fence_azure_arm -l 714a1fd2-0d8f-4260-a979-xxxxxxxxxx -p <APP_PASSWORD> --resourceGroup asd-pcmk-resources --tenantId 72f988bf-86f1-41af-91ab-xxxxxxxxxx --subscriptionId <SUB_ID> -o list
pcs stonith create smb_pcmk_stonith fence_azure_arm login=714a1fd2-0d8f-4260-a979-xxxxxxxxxx passwd=<APP_PASSWORD> resourceGroup=asd-pcmk-resources tenantId=72f988bf-86f1-41af-91ab-xxxxxxxxxx subscriptionId=<SUB_ID> pcmk_reboot_retries=3

### test to make sure fencing works
pcs stonith fence smb-vm-pcmk-02
pcs status
pcs cluster start smb-vm-pcmk-02


yum install lvm2-cluster gfs2-utils -y

pcs property set no-quorum-policy=freeze
pcs resource create smb-pcmk-dlm ocf:pacemaker:controld op monitor interval=30s on-fail=fence clone interleave=true ordered=true
pcs resource create smb-pcmk-clvmd ocf:heartbeat:clvm op monitor interval=30s on-fail=fence clone interleave=true ordered=true

vim /etc/lvm/lvm.conf # LINE 777 locking_type = 3

cp /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.$(date +%m-%d-%H%M%S).bak
dracut -f -v

systemctl stop lvm2-lvmetad
systemctl disable lvm2-lvmetad
systemctl stop lvm2-lvmetad.socket
systemctl disable lvm2-lvmetad.socket

pcs constraint order start smb-pcmk-dlm-clone then smb-pcmk-clvmd-clone
pcs constraint colocation add smb-pcmk-clvmd-clone with smb-pcmk-dlm-clone

pvcreate /dev/sdc
vgcreate -Ay -cy smb_pcmk_vg /dev/vdb
lvcreate -L4G -n smb_pcmk_lv smb_pcmk_vg

systemctl stop lvm2-lvmetad
systemctl disable lvm2-lvmetad
systemctl stop lvm2-lvmetad.socket
systemctl disable lvm2-lvmetad.socket

##########################################################################################
### WORK IN PROGRESS
##########################################################################################