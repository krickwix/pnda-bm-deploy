# bare-metal pnda
## principles
The PNDA bare-metal deployment technics is close to the OpenStack deployment’s one. To deploy PNDA on top of bare-metal nodes, OpenStack platform services are used. The two main services involved in this process are ironic and heat.
By default, bare-metal nodes on top of which PNDA is to be deployed shall implement an IPMI interface for power management and shall be able to boot using PXE to boot and deploy an operating system. By default we will make use of the pxe_ipmitool ironic driver which is generic enough to manage power management and pxe boot on a vast majority of servers.
The high level deployment steps are (assuming the deployment environment is available and the hardware has been set-up, including its networks):

 - gathering bare-metal nodes specifications (ipmi ip address, ipmi credentials, mac address)
 - populating the ironic database with nodes specifications
 - introspecting the nodes
 - tagging the nodes with profiles
 - start the heat stack deployment
## undercloud installation
The deployment host operating system will preferably be either a Centos 7 or Redhat Enterprise Linux 7.
Once the operating system is installed we first create a dedicated user, replacing password with your chosen one.
```
useradd stack
echo "<password>" | passwd stack --stdin
echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack
chmod 0440 /etc/sudoers.d/stack
```
Set the hostname properly
```
hostnamectl –set-hostname undercloud.example.com
hostnamectl –set-hostname --transient undercloud.example.com
```
ensure the /etc/hosts file is correct
```
cat /etc/hosts
127.0.0.1 undercloud.example.com localhost
```
install the tools required to manage the deployment
```
sudo curl -o /etc/yum.repos.d/delorean-mitaka.repo \
  https://trunk.rdoproject.org/centos7-mitaka/current/delorean.repo
sudo curl -o /etc/yum.repos.d/delorean-deps-mitaka.repo \
  http://trunk.rdoproject.org/centos7-mitaka/delorean-deps.repo
sudo yum -y install yum-plugin-priorities
sudo yum install -y python-tripleoclient openstack-utils
```
switch to stack user
```
sudo -i -u stack
```
create the configuration file to deploy the environment
```
cat > ~/undercloud.conf <<EOF
[DEFAULT]
undercloud_hostname = undercloud.example.com
local_ip = 192.0.3.1/24
network_gateway = 192.0.3.1
undercloud_public_vip = 192.0.3.2
undercloud_admin_vip = 192.0.3.3
local_interface = enp6s0
network_cidr = 192.0.3.0/24
masquerade_network = 192.0.3.0/24
dhcp_start = 192.0.3.5
dhcp_end = 192.0.3.24
inspection_interface = br-ctlplane
inspection_iprange = 192.0.3.100,192.0.3.120
inspection_runbench = false
undercloud_debug = true
enable_mistral = false
enable_zaqar = false
ipxe_deploy = false
enable_monitoring = false
store_events = false
[auth]
EOF
```
install the client
```
export DIB_YUM_REPO_CONF="/etc/yum.repos.d/delorean-deps-mitaka.repo /etc/yum.repos.d/delorean-mitaka.repo"
export NODE_DIST=centos7
export DELOREAN_TRUNK_REPO="http://trunk.rdoproject.org/centos7-mitaka/current/"
openstack undercloud install

[…]

#############################################################################
Undercloud install complete.

The file containing this installation's passwords is at
/home/stack/undercloud-passwords.conf.

There is also a stackrc file at /home/stack/stackrc.

These files are needed to interact with the OpenStack services, and should be
secured.

#############################################################################
```
test the client authentication
```
. stackrc
openstack service list
+----------------------------------+------------+---------------+
| ID                               | Name       | Type          |
+----------------------------------+------------+---------------+
| 0216b22ec85b437d9cc80b3a34ff2da6 | ceilometer | metering      |
| 16b7cfa2f8f64484902c8d7c7c832597 | neutron    | network       |
| 228290231a9d48f09b6f801641a773c8 | glance     | image         |
| 3493e5ad8f3e4e14a9f91dc10849540d | novav3     | computev3     |
| 56cce03fd1b74a8c833650f8fe83639a | heat       | orchestration |
| 8a8be34a81e74aa5ad522c20c447d647 | nova       | compute       |
| a97775a728344d3db3fa655ba39bd16d | keystone   | identity      |
| a9f7e037e49b4e068015263e99d0ae21 | ironic     | baremetal     |
| bc0aaf1a1de941018eff9637c879a2ca | swift      | object-store  |
+----------------------------------+------------+---------------+
```
## images build
There are two types of images:

 - deployment and discovery images
 - the pnda image itself

create the deployment and discovery images
```
export DIB_YUM_REPO_CONF="/etc/yum.repos.d/delorean-deps-mitaka.repo /etc/yum.repos.d/delorean-mitaka.repo"
export NODE_DIST=centos7
export DELOREAN_TRUNK_REPO="http://trunk.rdoproject.org/centos7-mitaka/current/"
mkdir ~/images && cd ~/images
openstack overcloud image build –-all
```
create the pnda image
```
cd
git clone https://github.com/pndaproject/pnda-dib-elements.git
export NODE_DIST=ubuntu
export ELEMENTS_PATH="/usr/share/tripleo-image-elements:/usr/share/openstack-heat-templates/:/usr/share/openstack-heat-templates/software-config/elements:/usr/share/instack-undercloud:/usr/share/tripleo-puppet-elements:/home/stack/images/pnda-dib-elements"
export PUPPET_COMMON_ELEMENTS="\
    sysctl \
    hosts \
    baremetal \
    dhcp-all-interfaces \
    os-collect-config \
    heat-config-puppet \
    heat-config-script \
    puppet-modules \
    hiera \
    os-net-config \
    stable-interface-names \
    grub2 \
    cloud-init-pnda"
cd image && disk-image-create -a amd64 -o pnda-image ubuntu $PUPPET_COMMON_ELEMENTS 2>&1 | tee dib-pnda-image.log
```
upload the images
```
openstack overcloud image upload
glance image-create  --name pnda-image-initrd --disk-format ari --container-format ari --file pnda-image.initrd --progress
glance image-create  --name pnda-image-vmlinuz --disk-format aki --container-format aki --file pnda-image.vmlinuz --progress
glance image-create  --name pnda-image --disk-format qcow2 --container-format bare --file pnda-image.qcow2 --progress
pnda_initrd_id=$(glance image-list|grep pnda-image-initrd|awk {'print $2'})
pnda_kernel_id=$(glance image-list|grep pnda-image-vmlinuz|awk {'print $2'})
glance image-update --property ramdisk_id=$pnda_initrd_id pnda-image
glance image-update --property kernel_id=$pnda_kernel_id panda-image
```

##  Registering nodes
Nodes can be either physical or virtual.
### physical systems
The bare-metal nodes will be provisioned and deployed using the ironic driver,  pxe_ipmitool, which interfaces with their IPMI interface for power management, and provides the PXE boot chain.
They shall first be registered against ironic.
The configuration parameters necessary are the MAC address of each node, the IPMI interface IP address, and optionally the IPMI authentication parameters. Optionally the node can be named.
The data to be collected for these nodes look like:
| MAC | IPMI IP | IPMI user | IPMI password |
|-
| xx:xx:xx:xx:xx:xx | xxx.xxx.xxx.xxx | user | pass |

After having collected the nodes parameters, we will create a json file to be imported into ironic. This json file will enclose a list of nodes. Each node is defined like:
```
{
      "name": "node_name",
      "pm_addr": "xxx.xxx.xxx.xxx",
      "pm_password": "impi_password",
      "pm_user": "ipmi_username",
      "pm_type": "pxe_impitool",
      "mac": [
        "xx:xx:xx:xx:xx:xx"
      ],
      "cpu": "1",
      "memory": "1024",
      "disk": "10",
      "arch": "x86_64"
    }
```

The only mandatory parameters that need to be properly configured are pm_addr, pm_password, pm_user, pm_type and mac.
The cpu, memory, disk, arch parameters are initialized to any default values as these specifications will be discovered later on.
A final json file will look like:
```
cat ~/instackenv.json
{
  “nodes”: [
    {
      "name": "node_name",
      "pm_addr": "xxx.xxx.xxx.xxx",
      "pm_password": "impi_password",
      "pm_user": "ipmi_username",
      "pm_type": "pxe_impitool",
      "mac": [
        "xx:xx:xx:xx:xx:xx"
      ],
      "cpu": "1",
      "memory": "1024",
      "disk": "10",
      "arch": "x86_64"
    },
    {
      "name": "node_name",
      "pm_addr": "xxx.xxx.xxx.xxx",
      "pm_password": "impi_password",
      "pm_user": "ipmi_username",
      "pm_type": "pxe_impitool",
      "mac": [
        "xx:xx:xx:xx:xx:xx"
      ],
      "cpu": "1",
      "memory": "1024",
      "disk": "10",
      "arch": "x86_64"
    },
    {
      "name": "node_name",
      "pm_addr": "xxx.xxx.xxx.xxx",
      "pm_password": "impi_password",
      "pm_user": "ipmi_username",
      "pm_type": "pxe_impitool",
      "mac": [
        "xx:xx:xx:xx:xx:xx"
      ],
      "cpu": "1",
      "memory": "1024",
      "disk": "10",
      "arch": "x86_64"
    }
  ]
}
```
Import the bare-metal nodes definitions
```
openstack baremetal import --json ~/instackenv.json
openstack baremetal list -c UUID -c Power\ State -c Provisioning\ State
+--------------------------------------+-------------+--------------------+
| UUID                                 | Power State | Provisioning State |
+--------------------------------------+-------------+--------------------+
| 464b81cc-6dd7-48f2-9e86-30450e592009 | power off   | available          |
| fb88a389-6a73-47e7-ae8b-a4116cc36604 | power off   | available          |
| a34dad17-cdb7-40ea-a305-d2c7ceedb859 | power off   | available          |
| f9d4e1f5-dba5-412c-b4af-9fffedd86fb0 | power off   | available          |
+--------------------------------------+-------------+--------------------+
```
At this point the nodes power state shall be defined (i.e. different from None). If not,  then this reveals a connection issue between the bare-metal service driver and the nodes IPMI interfaces.
Examining one node
```
ironic node-show 464b81cc-6dd7-48f2-9e86-30450e592009 |grep -A1 properties
| properties             | {u'memory_mb': u'1024', u'cpu_arch': u'x86_64', u'local_gb': u'10',   |
|                        | u'cpus': u'1', u'capabilities': u''}  |
```
As expected the node is said to be 1 cpu, 10 GB disk, 1024MB ram.
### virtualized systems
It is possible to replace bare-metal nodes with virtual machines. In this case, except for the ironic driver used to interact with the machines, the process remains identical to what it is with physical machines.
install the required packages
```
sudo -i # Change as root user
yum -y install libvirt virt-install libguestfs-tools
systemctl enable libvirtd
systemctl start libvirtd
```
create a default network xml file
```
cat > default-net.xml <<EOF
<network>
  <name>default</name>
  <bridge name="virbr0" stp='on' delay='0'/>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <mac address='52:54:00:13:4f:ae'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
```
Define and start the network
```
virsh net-define default-net.xml
virsh net-autostart default
virsh net-start default
```
Verify the running network
```
virsh net-dumpxml default
<network>
  <name>default</name>
  <uuid>22bb630f-65d0-45c9-9b6e-1a2d24da48d1</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr100' stp='on' delay='0'/>
  <mac address='52:54:00:13:4f:ae'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
```
Create some virtual machines
```
mkdir /home/stack/vms && cd /home/stack/vms
/home/stack/ngena-heat-templates/helpers/create_vms.sh
```
List the created machines
```
virsh list --all
 Id    Name                           State
----------------------------------------------------
 -     pnda-cdh-cm                    shut off
 -     pnda-cdh-dn1                   shut off
 -     pnda-cdh-dn2                   shut off
 -     pnda-cdh-dn3                   shut off
 -     pnda-cdh-mgr1                  shut off
 -     pnda-cdh-mgr2                  shut off
 -     pnda-gateway                   shut off
 -     pnda-kafka-1                   shut off
 -     pnda-kafka-2                   shut off
 -     pnda-master                    shut off
 -     pnda-zookeeper-1               shut off
 -     pnda-zookeeper-2               shut off
 -     pnda-zookeeper-3               shut off
```
Check that a storage pool has been created
```
semanage fcontext -a -t virt_image_t '/home/stack/vms(/.*)?'
restorecon -R /home/stack/vms
virsh pool-list –all
virsh pool-info vms
```
Hypervisor connectivity
```
cat << EOF > /etc/polkit-1/localauthority/50-local.d/50-libvirt-user-stack.pkla
[libvirt Management Access]
Identity=unix-user:stack
Action=org.libvirt.unix.manage
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
ssh-copy-id -i ~/.ssh/id_rsa.pub root@192.168.122.1
ssh-copy-id -i ~/.ssh/id_rsa.pub stack@192.168.122.1
virsh --connect qemu+ssh://root@192.168.122.1/system list --all
```
Looking for the instances mac addresses and names
```
rm -f /tmp/nodes.txt && for i in $(virsh list --all | awk ' /pnda/ {print $2} ');do mac=$(virsh domiflist $i | awk ' /br-ctlplane/ {print $5} '); echo -e "$mac" >>/tmp/nodes.txt;done && cat /tmp/nodes.txt
rm -f /tmp/names.txt && for i in $(virsh list --all | awk ' /pnda/ {print $2} ');do echo -e "$i" >>/tmp/names.txt;done && cat /tmp/names.txt
```
Creating the instance list json file from the previously created instance list files.
```
/home/stack/ngena-heat-templates/helpers/create_json.sh
```
Import the nodes into ironic
```
openstack baremetal import --json ~/instackenv.json
```
Review the imported nodes
```
openstack baremetal list
+--------------------------------------+------------------+---------------+-------------+--------------------+-------------+
| UUID                                 | Name             | Instance UUID | Power State | Provisioning State | Maintenance |
+--------------------------------------+------------------+---------------+-------------+--------------------+-------------+
| 4cbe3b0d-8fbc-48e8-ba85-933f5e39a158 | pnda-cdh-cm      | None          | power off   | available          | False       |
| 82e88847-88ed-4558-8ec1-0b4523d70401 | pnda-cdh-dn1     | None          | power off   | available          | False       |
| 813f77ea-4982-40ec-8b09-2c2b431583b8 | pnda-cdh-dn2     | None          | power off   | available          | False       |
| 13824fb4-1a31-48ad-b065-82ebaa71eac4 | pnda-cdh-dn3     | None          | power off   | available          | False       |
| d2292b5e-e2e8-46cb-b644-b101a691661f | pnda-cdh-mgr1    | None          | power off   | available          | False       |
| a6d9e7ba-f893-416b-ab2d-83ec03272dec | pnda-cdh-mgr2    | None          | power off   | available          | False       |
| 67fea56b-3baf-4694-b175-c5b67970481a | pnda-gateway     | None          | power off   | available          | False       |
| 770ba417-1e29-47dc-b86a-598c8889768c | pnda-kafka-1     | None          | power off   | available          | False       |
| b8b26264-3c29-4e44-8fb0-9b90dbb04156 | pnda-kafka-2     | None          | power off   | available          | False       |
| e86c8ca7-7c9e-4378-adee-7317d495b6a8 | pnda-master      | None          | power off   | available          | False       |
| a69611b8-1a1a-40d2-a4bd-4c492e576256 | pnda-zookeeper-1 | None          | power off   | available          | False       |
| 3cecd513-5327-4805-a6ec-be38c5b1f430 | pnda-zookeeper-2 | None          | power off   | available          | False       |
| 98da9359-23df-4000-b18d-4c652a2ef59c | pnda-zookeeper-3 | None          | power off   | available          | False       |
+--------------------------------------+------------------+---------------+-------------+--------------------+-------------+
```
At this point, the power state of the nodes should be different from ‘None’ meaning that the baremetal service successfully retrieved the actual instances power states.

Creating the instances flavors
```
/home/stack/ngena-heat-templates/helpers/create_flavors.sh
```
Tag the baremetal nodes with a profile
```
/home/stack/ngena-heat-templates/helpers/tag_nodes.sh
```

## nodes introspection
Once a node has been registered, it is available for introspection (the node will execute a self inspection process, and return the result to ironic)
Configure the nodes
```
openstack baremetal configure boot
```
start the introspection process
```
openstack baremetal introspection bulk start
Setting nodes for introspection to manageable...
Starting introspection of node:  464b81cc-6dd7-48f2-9e86-30450e592009
Waiting for introspection to finish...
Introspection for UUID 464b81cc-6dd7-48f2-9e86-30450e592009 finished successfully.
Setting manageable nodes to available...
Node 464b81cc-6dd7-48f2-9e86-30450e592009 has been set to available.
Introspection completed.
```
Examine the introspected node
```
ironic node-show 464b81cc-6dd7-48f2-9e86-30450e592009 |grep -A1 properties
| properties             | {u'memory_mb': u'16384', u'cpu_arch': u'x86_64', u'local_gb': u'1000',   |
|                        | u'cpus': u'12', u'capabilities': u'boot_option:local'} |
```
The node is now registered with the right capabilities.


