#!/bin/bash

###Interaction Utilisateur

##Network
while [[ -z $network || ($network != 'w' && $network != 'e') ]]; do
	read -p '(w)ifi ou (e)thernet ? : ' network
done

##Partitions
fdisk -l

while [[ -z $root && $root != [a-z][1-9] ]]; do
	read -p 'Entrez le chemin de la partition Root (/): /dev/sd' root
done

while [[ -z $home && $home != [a-z][1-9] ]]; do
	read -p 'Entrez le chemin de la partition Home (/home): /dev/sd' home
done

while [[ -z $boot && $boot != [a-z][1-9] ]]; do
	read -p 'Entrez le chemin de la partition Boot (/boot): /dev/sd' boot
done

while [[ -z $efi && $efi != [a-z][1-9] ]]; do
	read -p 'Entrez le chemin de la partition Efi (/boot/efi): /dev/sd' efi
done

while [[ -z $tempefi && $tempefi != [a-z] ]]; do
	read -p 'Entrez le chemin du disque Efi : /dev/sd' tempefi
done

root="/dev/sd$root"
home="/dev/sd$home"
boot="/dev/sd$boot"
efi="/dev/sd$efi"
tempefi="/dev/sd$tempefi"

while [[ -z $hostname ]]; do
	read -p 'Entrez le hostname du système : ' hostname
done


###Commandes d'install

#Clavier
loadkeys fr-pc

##Partitionnement

echo "Partitionnement To Fix"

#To Fix

echo "Formatage des Partitions"

mkfs.vfat -F32 /dev/dev/sdx1 #Format EFI Partition
mkfs.ext2 $boot
mkfs.ext4 $root
mkfs.ext4 $home

echo "Montage des Partitions"

mount $root /mnt
mkdir /mnt/boot
mkdir /mnt/home
mount $boot /mnt/boot
mount $home /mnt/home
mkdir /mnt/boot/efi
mount $efi /mnt/boot/efi
mkdir /mnt/boot/efi/EFI
mkdir /mnt/boot/efi/EFI/arch

echo "Réseau"

if [[ $network = "w" ]]; then
	while [[ -z "$(ping -c1 google.fr)" ]]; do
		systemctl stop dhcpcd.service
		wifi-menu
		sleep 10
	done
	echo Connexion Etablished
else
	while [[ -z "$(ping -c1 google.fr)" ]]; do
		systemctl restart dhcpcd.service
	done
	echo Connexion Etablished
fi

echo "Installation de Base"

pacstrap /mnt base base-devel efibootmgr sudo #etc.

echo "Gen fstab"

genfstab -U -p /mnt >> /mnt/etc/fstab

#modprobe efivars

echo "Chroot et Config"

arch_chroot() {
	arch-chroot /mnt /bin/bash -c "${1}"
}

echo "$hostname" > /mnt/etc/hostname
echo "fr_FR.UTF-8 UTF-8" >> /mnt/etc/locale.gen

echo "test arch-chroot"
arch_chroot "locale-gen"

echo 'LANG="fr_FR.UTF-8"' > /mnt/etc/locale.conf
arch_chroot "export LANG=fr_FR.UTF-8"

echo "KEYMAP=fr-pc" > /mnt/etc/vconsole.conf

ln -s /mnt/usr/share/zoneinfo/Europe/Paris /mnt/etc/localtime

echo "Prepare Kernel"

arch_chroot "mkinitcpio -p linux"

arch_chroot "passwd"

echo "EFI Boot Stub"

cp /mnt/boot/vmlinuz-linux /mnt/boot/efi/EFI/arch/vmlinuz-arch.efi
cp /mnt/boot/initramfs-linux.img /mnt/boot/efi/EFI/arch/initramfs-arch.img
cp /mnt/boot/initramfs-linux-fallback.img /mnt/boot/efi/EFI/arch/initramfs-arch-fallback.img

cp ./efistub-update.path /mnt/etc/systemd/system/efistub-update.path
cp ./efistub-update.service /mnt/etc/systemd/system/efistub-update.service
arch_chroot "systemctl enable efistub-update.path"

arch_chroot "modprobe efivars"

echo "Récupération UUID de /"

uuid=`blkid $root | cut -d '"' -f 2`

arch_chroot `echo "root=UUID=$uuid rw acpi_osi= rootfstype=ext4 add_efi_memmap initrd=\EFI\arch\initramfs-arch.img" | iconv -f ascii -t ucs2 | efibootmgr -c -g -d $tempefi -p 1 -L "Arch Linux Test" -l '\EFI\arch\vmlinuz-arch.efi' -@ -`

echo "Umount Partitions"

Umount /mnt/boot/efi
umount /mnt/boot
umount /mnt/home
umount /mnt
