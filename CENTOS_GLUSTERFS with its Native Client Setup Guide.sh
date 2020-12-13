# set up gluster environment
yum search centos-release-gluster
yum install centos-release-gluster -y 
yum install glusterfs gluster-cli glusterfs-libs glusterfs-server nfs-utils -y

# usual stuff
echo "192.168.1.11 vm-gfs-01" >> /etc/hosts
echo "192.168.1.12 vm-gfs-02" >> /etc/hosts
echo "192.168.1.13 vm-gfs-03" >> /etc/hosts
echo "192.168.1.14 vm-gfs-04" >> /etc/hosts
echo "192.168.1.15 vm-gfs-05" >> /etc/hosts

# create volume group to gluster
pvcreate /dev/sdc
vgcreate vg_gluster /dev/sdc
lvcreate -l 100%FREE -n brick vg_gluster

# prepares for XFS bricks 
mkfs.xfs /dev/vg_gluster/brick

mkdir -p /bricks
mount /dev/vg_gluster/brick /bricks
echo -e '/dev/vg_gluster/brick /bricks	xfs	defaults	0	0' >> /etc/fstab

# prepares for trusted pool
systemctl enable glusterd.service
systemctl start glusterd.service

systemctl enable firewalld
systemctl start firewalld
firewall-cmd --zone=public --add-port=24007-24008/tcp --permanent
firewall-cmd --reload

# probe gluster peer from vm-gfs-01.  you do not need to run this on other nodes.
gluster peer probe vm-gfs-02
gluster peer probe vm-gfs-03

# creates HA GlusterFS volumes
firewall-cmd --zone=public --add-port=24009/tcp --permanent
firewall-cmd --zone=public --add-service=nfs --add-service=samba --add-service=samba-client --permanent
firewall-cmd --zone=public --add-port=111/tcp --add-port=139/tcp --add-port=445/tcp --add-port=965/tcp --add-port=2049/tcp --add-port=38465-38469/tcp --add-port=631/tcp --add-port=111/udp --add-port=963/udp --add-port=49152-49251/tcp  --permanent
firewall-cmd --reload

# !!! RUN ON NODE-1 ONLY !!!
mkdir /bricks/data
gluster volume create glustervol replica 3 transport tcp vm-gfs-01:/bricks/data vm-gfs-02:/bricks/data vm-gfs-03:/bricks/data
gluster volume start glustervol
gluster volume set glustervol nfs.disable off
gluster volume set glustervol nfs.acl off

# GLUSTER CLIENT SETUP (192.168.1.14 only)
yum install glusterfs glusterfs-fuse attr -y
mount -t glusterfs vm-gfs-01:/glustervol /mnt/glusterfs/
mount -t glusterfs -o backup-volfile-servers=vm-gfs-02:vm-gfs-03,log-level=WARNING,log-file=/var/log/gluster.log vm-gfs-01:/glustervol /mnt/glusterfs
#fstab: vm-gfs-01:/glustervol       /mnt/glusterfs  glusterfs       defaults,_netdev,backup-volfile-servers=vm-gfs-02:vm-gfs-03     0 0


