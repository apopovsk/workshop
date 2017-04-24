#!/bin/bash

kvm \
  -name openrg-node,process=openrg-node \
  -cpu host,level=9 -m 2048 \
  -parallel none \
  -display none -vga none \
  -monitor telnet::2001,server,nowait,nodelay \
  -serial stdio \
  -device virtio-9p-pci,fsdev=rootfs,mount_tag=rootfs -fsdev local,id=rootfs,path=/,security_model=none \
  -kernel /boot/vmlinuz-*-generic \
  -initrd /boot/initrd.img-*-generic \
  -append 'root=rootfs rootfstype=9p rootflags=trans=virtio rw 3 console=ttyS0 init=/sbin/init'

#  -device e1000,netdev=net0 -netdev tap,id=net0,ifname=vm0,script=no,downscript=no \
#   -kernel "bzImage" \
#  -append 'root=rootfs rw rootfstype=9p rootflags=trans=virtio console=ttyS0 init=/bin/bash'

#  -daemonize \
#  -kernel "bzImage" \
#  -append 'root=/dev/sda1 rw console=ttyS0 init=/bin/bash'
#  -hda debian-8.2.0-openstack-amd64.qcow2 \
