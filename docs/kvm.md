# kvm virtual machine info

# build initial vm via virtualbox
- vm requirements
    - [qemu-guest-agent](https://pve.proxmox.com/wiki/Qemu-guest-agent)
    - [enable tty for console acces](https://ravada.readthedocs.io/en/latest/docs/config_console.html)


- conver from vdi to qcow2
    - ```qemu-img convert -f vdi diskfile.vdi -O qcow2 vm.qcow2```
- [vm management with virsh](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/chap-managing_guest_virtual_machines_with_virsh)   
- [install vm](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-guest_virtual_machine_installation_overview-creating_guests_with_virt_install#sect-Guest_virtual_machine_installation_overview-Creating_guests_with_virt_install) 
- [start vm](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-starting_suspending_resuming_saving_and_restoring_a_guest_virtual_machine-starting_a_defined_domain)
- [stop vm](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-managing_guest_virtual_machines_with_virsh-shutting_down_rebooting_and_force_shutdown_of_a_guest_virtual_machine#sect-Shutting_down_rebooting_and_force_shutdown_of_a_guest_virtual_machine-Shut_down_a_guest_virtual_machine)
- [uninstall vm](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-virsh-delete) 
- [console to vm](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-domain_commands-connecting_the_serial_console_for_the_guest_virtual_machine)

## install from iso
- kvm is finicky and needs to have a separate iso containing the cloud init scripts
    - build cidata iso
    - ```sudo genisoimage -output cidata.iso -volid cidata -rational-rock -joliet -joliet-long user-data.yml meta-data.yml```
- example command line
    - 
    ```bash 
    sudo virt-install \
  --noautoconsole \
  --name desktop-24-vm \
  --ram 8192 \
  --vcpus 2 \
  --disk path=/mnt/raid/libvirt/images/desktop-24-vm.qcow2,size=32,format=qcow2,bus=virtio \
  --os-variant ubuntu-lts-latest \
  --network bridge=kvmbr0 \
  --console pty,target_type=serial \
  --location /mnt/raid/ubuntu-24-vm.iso,kernel=casper/vmlinuz,initrd=casper/initrd \
  --disk path=/mnt/raid/cidata.iso,device=cdrom \
  --extra-args 'autoinstall console=ttyS0,115200n8 serial'```

## FAQ
- remmina connection failures
    -[xrdp xrdp_iso_send: trans_write_copy_s failed](https://unix.stackexchange.com/questions/648252/xrdp-iso-send-trans-write-copy-s-failed-issues-rdp-from-raspios-to-arch-x86-w)