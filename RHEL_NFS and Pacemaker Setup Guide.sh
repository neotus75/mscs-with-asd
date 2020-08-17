##########################################################################################
### tested on RHEL 7.6
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
### run on only one node!!!
##########################################################################################

pcs cluster auth vm-pcmk-01 vm-pcmk-02 vm-pcmk-03
pcs cluster setup --name vm-pcmk-cluster vm-pcmk-01 vm-pcmk-02 vm-pcmk-03

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
# az ad sp create-for-rbac -n "rhel-pmkr-cluster" --role owner --scopes /subscriptions/<SUBSCRIPTION-ID>/resourceGroups/asd-pcmk-resources
# {
#   "appId": "714a1fd2-0d8f-4260-a979-xxxxxxxxxx",
#   "displayName": "rhel-pmkr-cluster",
#   "name": "http://rhel-pmkr-cluster",
#   "password": "<APP_PASSWORD>",
#   "tenant": "72f988bf-86f1-41af-91ab-xxxxxxxxxx"
# }

### copy and paste your app information and replace the value below to create cluster fencing
fence_azure_arm -l 714a1fd2-0d8f-4260-a979-xxxxxxxxxx -p <APP_PASSWORD> --resourceGroup asd-pcmk-resources --tenantId 72f988bf-86f1-41af-91ab-xxxxxxxxxx --subscriptionId <SUB_ID> -o list
pcs stonith create nfs_pcmk_stonith fence_azure_arm login=714a1fd2-0d8f-4260-a979-xxxxxxxxxx passwd=<APP_PASSWORD> resourceGroup=asd-pcmk-resources tenantId=72f988bf-86f1-41af-91ab-xxxxxxxxxx subscriptionId=<SUB_ID> pcmk_reboot_retries=3

### test to make sure fencing works
pcs stonith fence vm-pcmk-02
pcs status
pcs cluster start vm-pcmk-02

### create partition on Azure Shared Disk (/dev/sdc) 
fdisk /dev/sdc

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
touch /nfsshare/exports/export/clientdatafile

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

### tag volume group to pacemaker (repeated on all nodes just to make sure)
vgchange --addtag pacemaker /dev/pcmkvg
vgs -o vg_tags /dev/pcmkvg

### add volume exclusion in lvm.conf file
vim /etc/lvm/lvm.conf # ---> LINE 1240: volume_list = []


##########################################################################################
### There is a problem with the following command.  Do not run it,
### and consult Red Hat Support
### dracut -H -f /boot/initramfs-$(uname -r).img $(uname -r)
##########################################################################################

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
