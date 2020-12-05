##########################################################################################
### tested on RHEL 7.7
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

##########################################################################################
### run on each nodes
##########################################################################################
sudo -i
yum update -y
yum install pcs pacemaker fence-agents-azure-arm install nmap-ncat resource-agents -y

### add all nodes to /etc/hosts file
echo "192.168.1.11 vm-pcmk-01" >> /etc/hosts
echo "192.168.1.12 vm-pcmk-02" >> /etc/hosts
echo "192.168.1.13 vm-pcmk-03" >> /etc/hosts
echo "192.168.1.14 vm-pcmk-04" >> /etc/hosts
echo "192.168.1.15 vm-pcmk-05" >> /etc/hosts

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
### run on node 1
##########################################################################################

pcs cluster auth vm-pcmk-01 vm-pcmk-02 vm-pcmk-03
pcs cluster setup --name pcmk-nfs-cluster vm-pcmk-01 vm-pcmk-02 vm-pcmk-03

### start pacemaker on all nodes
pcs cluster enable --all
pcs cluster start --all

### install azure-cli for fence agent creation on azure AD
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/azure-cli.repo
sudo yum install azure-cli -y

az login
az ad sp create-for-rbac -n "pcmk-nfs-cluster" --role owner --scopes /subscriptions/<subId>/resourceGroups/<Resource Group> # your sub ID and resource group

### this assumes you have azure cli on your linux box.   
{
  "appId": "<appId>",
  "displayName": "pcmk-nfs-cluster",
  "name": "http://pcmk-nfs-cluster",
  "password": "<pass>",
  "tenant": "<tenantId>"
}

### copy and paste your app information and replace the value below to create cluster fencing
fence_azure_arm -l <appId> -p <passwd> --resourceGroup nfs-pcmk-asd-resources --tenantId <tenantId> --subscriptionId <subscriptionId> -o list
pcs stonith create nfs_pcmk_stonith fence_azure_arm login=<appId> passwd=<passwd> resourceGroup=nfs-pcmk-asd-resources tenantId=<tenantId> subscriptionId=<subId> pcmk_reboot_retries=3

### create partition on Azure Shared Disk (/dev/sdc) 
fdisk /dev/sdc # n -> p -> w -> default sizes

### create volume group, logical volume, and format it to ext4
pvcreate /dev/sdc1
vgcreate pcmkvg /dev/sdc1
lvcreate -l 100%FREE -n pcmklv pcmkvg 
lvs
mkfs.ext4 /dev/pcmkvg/pcmklv

### prep to create share directory for NFS service
mkdir /nfsshare
mount /dev/pcmkvg/pcmklv /nfsshare

### test create a file
mkdir -p /nfsshare/exports
mkdir -p /nfsshare/exports/export
touch /nfsshare/exports/export/test.txt

### tag volume group to pacemaker
vgchange --addtag pacemaker /dev/pcmkvg
vgs -o vg_tags /dev/pcmkvg

### unmount the volume and set activation flag
umount /dev/pcmkvg/pcmklv
vgchange -an pcmkvg

##########################################################################################
### run on each nodes !!!
##########################################################################################
lvmconf --enable-halvm --services --startstopservices

##########################################################################################
### run on node 1
##########################################################################################

### add volume exclusion in lvm.conf file (you can use sed command)
vim /etc/lvm/lvm.conf # ---> LINE 1240: volume_list = ["rootvg"]

### rebuild initramfs once lvm.conf is modified
cp /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.$(date +%m-%d-%H%M%S).bak
dracut -f -H -v /boot/initramfs-$(uname -r).img $(uname -r)

# create probing port from Internal Load Balancer
pcs resource create nfs-pcmk-ilb azure-lb port=59998 --group nfs-pcmk-resources

# create virtual IP for NFS server
pcs resource create nfs-pcmk-vip IPaddr2 ip="192.168.1.10" --group nfs-pcmk-resources

# create logical volume manager for pcmk volume group
pcs resource create nfs-pcmk-lvm LVM volgrpname=pcmkvg exclusive=true --group nfs-pcmk-resources

# create file system on logical volume 
pcs resource create nfs-share Filesystem device=/dev/pcmkvg/pcmklv directory=/nfsshare fstype=ext4 --group nfs-pcmk-resources

# create nfs-daemon 
pcs resource create nfs-daemon nfsserver nfs_shared_infodir=/nfsshare/nfsinfo nfs_no_notify=true --group nfs-pcmk-resources

# create root export to to allow sharing to the network
pcs resource create nfs-pcmk-root exportfs clientspec=192.168.1.0/255.255.255.0 options=rw,sync,no_root_squash directory=/nfsshare/exports fsid=0 --group nfs-pcmk-resources

# create client export to to allow sharing to the network
pcs resource create nfs-pcmk-export exportfs clientspec=192.168.1.0/255.255.255.0 options=rw,sync,no_root_squash directory=/nfsshare/exports/export fsid=1 --group nfs-pcmk-resources

# create nfs notification
pcs resource create nfs-pcmk-notify nfsnotify source_host=192.168.1.10 --group nfs-pcmk-resources