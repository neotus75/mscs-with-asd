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
az ad sp create-for-rbac -n "pcmk-nfs-cluster" --role owner --scopes /subscriptions/a370ff12-d748-4091-8749-a21c085d368f/resourceGroups/nfs-pcmk-asd-resources # your sub ID and resource group

### this assumes you have azure cli on your linux box.   
{
  "appId": "7e35bb0b-1fe4-4b5d-b759-5198065ac0d1",
  "displayName": "pcmk-nfs-cluster",
  "name": "http://pcmk-nfs-cluster",
  "password": "YilNOOqMDmEVbR.n8YUijg2XGHh_9gCsIO",
  "tenant": "72f988bf-86f1-41af-91ab-2d7cd011db47"
}

### copy and paste your app information and replace the value below to create cluster fencing
fence_azure_arm -l 7e35bb0b-1fe4-4b5d-b759-5198065ac0d1 -p YilNOOqMDmEVbR.n8YUijg2XGHh_9gCsIO --resourceGroup nfs-pcmk-asd-resources --tenantId 72f988bf-86f1-41af-91ab-2d7cd011db47 --subscriptionId a370ff12-d748-4091-8749-a21c085d368f -o list
pcs stonith create nfs_pcmk_stonith fence_azure_arm login=7e35bb0b-1fe4-4b5d-b759-5198065ac0d1 passwd=YilNOOqMDmEVbR.n8YUijg2XGHh_9gCsIO resourceGroup=nfs-pcmk-asd-resources tenantId=72f988bf-86f1-41af-91ab-2d7cd011db47 subscriptionId=a370ff12-d748-4091-8749-a21c085d368f pcmk_reboot_retries=3

### create partition on Azure Shared Disk (/dev/sdc) 
fdisk /dev/sdc # n -> p -> w -> default sizes

### create volume group, logical volume, and format it to ext4
pvcreate /dev/sdc1                      # creates a physical volume 
vgcreate pcmkvg /dev/sdc1               # creates a volume group
lvcreate -l 100%FREE -n pcmklv pcmkvg   # creates logical volume of 100% in size, named "n", in the volume group called pcmkvg 
lvs                                     # reports information about the logical volume
mkfs.ext4 /dev/pcmkvg/pcmklv            # creates filesystem (ext4) out of /dev/pcmkvg/pcmklv

### prep to create share directory for NFS service
mkdir /nfsshare                         # creates a folder to be shared
mount /dev/pcmkvg/pcmklv /nfsshare      # now mount volume to the shared folder

### test create a file
mkdir -p /nfsshare/exports
mkdir -p /nfsshare/exports/export
touch /nfsshare/exports/export/test.txt

### tag volume group to pacemaker
vgchange --addtag pacemaker /dev/pcmkvg # changes vg attrutes of /dev/pcmkvg (adds a tag)
vgs -o vg_tags /dev/pcmkvg              # displays informationi about the volume group under the tag (pacemaker, in this case)

### unmount the volume and set activation flag
umount /dev/pcmkvg/pcmklv               # vg is enabled at creation by default. this means, lv can be accessed in the vg. for clustering,
vgchange -an pcmkvg                     # it needs to unmount and disable the volume group so that kernal does not know of it exists.

##########################################################################################
### run on each nodes !!!
##########################################################################################
# The following procedure configures the volume group in a way that will ensure that only the cluster is capable of activating the volume 
# group, and that the volume group will not be activated outside of the cluster on startup. If the volume group is activated by a system 
# outside of the cluster, there is a risk of corrupting the volume group's metadata.

lvmconf --enable-halvm --services --startstopservices

##########################################################################################
### run on node 1
##########################################################################################

# add volume exclusion in lvm.conf file by adding volume_list = ["rootvg"] only. please note that you must NOT include your vg (pcmkvg) for 
# it to be controlled by cluster
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