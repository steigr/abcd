#!/bin/bash

DEBUG=false
set -e

pre_chroot() {
echo -e "\n\nBeginning Autoinstall" >/dev/tty1
echo "Setting Mirror" >/dev/tty1
echo 'Server = http://ftp-stud.hs-esslingen.de/pub/Mirrors/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist
echo "Updating Repository" >/dev/tty1
pacman --noconfirm -Syu || true
cd /tmp
echo "Loading Keymap" >/dev/tty1
loadkeys us
echo "Clearing Harddrive"
dd if=/dev/zero of=/dev/sda bs=512 count=1
echo "Partitioing Harddrive"
SELECTPART=$(fdisk -v | rev | cut -f1 -d" " | rev | sed -e "s#2\.2[012].*#a\n1#" -e "s#2.*#a#")

cat <<EOFDISK | fdisk /dev/sda
n
p
1


t
83
$SELECTPART
w
EOFDISK
partprobe

echo "Formatting Harddrive" >/dev/tty1
mkfs.ext4 /dev/sda1

echo "Mounting Harddrive" >/dev/tty1
mount /dev/sda1 /mnt

echo "Bootstrapping System" >/dev/tty1
pacstrap /mnt base

echo "Generating FStab" >/dev/tty1
genfstab -p /mnt >> /mnt/etc/fstab

echo "Setting Hostname" >/dev/tty1
MYFIRSTIP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -f1 -d"/")
MYFIRSTMAC=$(ip link show eth0 | grep "link/" | awk '{print $2}')
NODENAME=$(host $MYFIRSTIP | rev | cut -f1 -d" " | rev | cut -f1 -d".")
echo $NODENAME > /mnt/etc/hostname

echo "Mouting  chroot" >/dev/tty1
mount -o bind /proc /mnt/proc
mount -o bind /dev /mnt/dev
mount -o bind /sys /mnt/sys

echo "Preconfiguring Network" >/dev/tty1
cat /etc/resolv.conf

cp /etc/resolv.conf /mnt/etc/resolv.conf
cp $0 /mnt/tmp/startup_script
chroot /mnt /tmp/startup_script CHROOT

}
post_chroot() {

echo "Setting Timezone" >/dev/tty1
ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime

echo "Generating Locales" >/dev/tty1
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

echo "Configuring Console" >/dev/tty1
echo "KEYMAP=us" >> /etc/vconsole.conf
echo "FONT=lat9w-16">> /etc/vconsole.conf
echo "FONT_MAP=8859-1_to_uni" >> /etc/vconsole.conf 

echo "Generating InitRD" >/dev/tty1
mkinitcpio -p linux

echo "Setting Rootpassword" >/dev/tty1
echo "root:@ROOTPASSWORD@" | chpasswd

echo "Configuring udev" > /dev/tty1
ln -s /usr/lib/systemd/system/dhcpcd@.service /etc/systemd/system/multi-user.target.wants/dhcpcd@eth0.service
rm /etc/udev/rules.d/80-net-name-slot.rules || true
ln -s /dev/null /etc/udev/rules.d/80-net-name-slot.rules

echo "Installing Bootloader" >/dev/tty1
pacman -S --noconfirm grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

echo "Running Post-Configuration-Commands" >/dev/tty1
@POSTINSTALL@

}

CHROOT=$1

case "$CHROOT" in
	CHROOT)
		post_chroot
	;;
	*)
		LOGFILE="startup-script-$(date +%s).log"
		ERRFILE="startup-script-$(date +%s).err"
		if [ "x$DEBUG" = "xfalse" ]; then exec >/tmp/$LOGFILE 2>/tmp/$ERRFILE; fi
		set -x
		setterm -powersave off -blank 0
		pre_chroot
		set +e
		echo "Cleanup installation-Environment" >/dev/tty1
		mv /tmp/$LOGFILE /tmp/$ERRFILE /mnt/root
		while true; do umount /mnt/proc; [[ $? > 0 ]] && break; done
		while true; do umount /mnt/sys;  [[ $? > 0 ]] && break; done
		while true; do umount /mnt/dev;  [[ $? > 0 ]] && break; done
		while true; do umount /mnt;      [[ $? > 0 ]] && break; done
		echo "Installation finished" >/dev/tty1
		reboot
	;;
esac
