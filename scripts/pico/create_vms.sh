#!/bin/bash -v

set -xe

for i in $(virsh list --all | awk ' /pnda/ {print $2} '); do virsh undefine $i;done

qemu-img create -f qcow2 -o preallocation=metadata pnda-master.qcow2 4G
virt-install --accelerate --name=pnda-master --file=pnda-master.qcow2 --graphics vnc,listen=0.0.0.0 --vcpus=1 --ram=2048 --network bridge=br-ctlplane,virtualport_type=openvswitch,model=virtio --network network=default,model=virtio --os-type=linux --boot hd --dry-run --print-xml > pnda-master.xml
virsh define pnda-master.xml

qemu-img create -f qcow2 -o preallocation=metadata pnda-kafka-0.qcow2 4G
virt-install --accelerate --name=pnda-kafka-0 --file=pnda-kafka-0.qcow2 --graphics vnc,listen=0.0.0.0 --vcpus=1 --ram=2048 --network bridge=br-ctlplane,virtualport_type=openvswitch,model=virtio  --network network=default,model=virtio --os-type=linux --boot hd --dry-run --print-xml > pnda-kafka-0.xml
virsh define pnda-kafka-0.xml

qemu-img create -f qcow2 -o preallocation=metadata pnda-cdh-edge.qcow2 20G
virt-install --accelerate --name=pnda-cdh-edge --file=pnda-cdh-edge.qcow2 --graphics vnc,listen=0.0.0.0 --vcpus=4 --ram=8192 --network bridge=br-ctlplane,virtualport_type=openvswitch,model=virtio  --network network=default,model=virtio --os-type=linux --boot hd --dry-run --print-xml > pnda-cdh-cm.xml
virsh define pnda-cdh-edge.xml

qemu-img create -f qcow2 -o preallocation=metadata pnda-cdh-dn0.qcow2 30G;
virt-install --accelerate --name=pnda-cdh-dn0 --file=pnda-cdh-dn0.qcow2 --graphics vnc,listen=0.0.0.0 --vcpus=4 --ram=8192 --network bridge=br-ctlplane,virtualport_type=openvswitch,model=virtio  --network network=default,model=virtio --os-type=linux --boot hd --dry-run --print-xml > pnda-cdh-dn0.xml; \
virsh define pnda-cdh-dn0.xml; \

qemu-img create -f qcow2 -o preallocation=metadata pnda-cdh-mgr1.qcow2 20G;
virt-install --accelerate --name=pnda-cdh-mgr1 --file=pnda-cdh-mgr1.qcow2 --graphics vnc,listen=0.0.0.0 --vcpus=4 --ram=8192 --network bridge=br-ctlplane,virtualport_type=openvswitch,model=virtio  --network network=default,model=virtio --os-type=linux --boot hd --dry-run --print-xml > pnda-cdh-mgr1.xml; \
virsh define pnda-cdh-mgr1.xml; \

rm -f /tmp/nodes.txt && for i in $(virsh list --all | awk ' /pnda/ {print $2} ');do mac=$(virsh domiflist $i | awk ' /br-ctlplane/ {print $5} '); echo -e "$mac" >>/tmp/nodes.txt;done && cat /tmp/nodes.txt
rm -f /tmp/names.txt && for i in $(virsh list --all | awk ' /pnda/ {print $2} ');do echo -e "$i" >>/tmp/names.txt;done && cat /tmp/names.txt

virsh list --all
