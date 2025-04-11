# kvm virtual machine info

# build initial vm via virtualbox
- vm requirements
    - [qemu-guest-agent](https://pve.proxmox.com/wiki/Qemu-guest-agent)
    - [enable tty for console acces](https://ravada.readthedocs.io/en/latest/docs/config_console.html)


- conver from vdi to qcow2
    - ```qemu-img convert -f vdi diskfile.vdi -O qcow2 vm.qcow2```
- [install vm](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-guest_virtual_machine_installation_overview-creating_guests_with_virt_install#sect-Guest_virtual_machine_installation_overview-Creating_guests_with_virt_install) 
- [start vm](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-starting_suspending_resuming_saving_and_restoring_a_guest_virtual_machine-starting_a_defined_domain)
- [stop vm](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-managing_guest_virtual_machines_with_virsh-shutting_down_rebooting_and_force_shutdown_of_a_guest_virtual_machine#sect-Shutting_down_rebooting_and_force_shutdown_of_a_guest_virtual_machine-Shut_down_a_guest_virtual_machine)
- [uninstall vm](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-virsh-delete) 


## FAQ
- remmina connection failures
    -[xrdp xrdp_iso_send: trans_write_copy_s failed](https://unix.stackexchange.com/questions/648252/xrdp-iso-send-trans-write-copy-s-failed-issues-rdp-from-raspios-to-arch-x86-w)