#!/bin/bash -v

#set -xe


openstack flavor delete pnda-micro
openstack flavor delete pico-kafka
openstack flavor delete pico-edge
openstack flavor delete pico-dn
openstack flavor delete pico-mgr

openstack flavor create --id auto --ram 2048 --disk 3 --vcpus 1 pnda-micro
openstack flavor create --id auto --ram 2048 --disk 3 --vcpus 1 pico-kafka
openstack flavor create --id auto --ram 8192 --disk 19 --vcpus 4 pico-edge
openstack flavor create --id auto --ram 8192 --disk 29 --vcpus 4 pico-dn
openstack flavor create --id auto --ram 8192 --disk 19 --vcpus 4 pico-mgr

openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="master" pnda-micro
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="kafka" pico-kafka
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="cm" pico-edge
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="dn" pico-dn
openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="mgr" pico-mgr
