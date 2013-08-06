#!/bin/bash

DEBUG=false

pre_chroot() {
echo "Running">/dev/tty1
[[ -x "$(which wget)" ]] && DOWNLOADER="$(which wget) -q -O " || DOWNLOADER="$(which curl) -s -o "
$DOWNLOADER - @BASEURL@/ping >/dev/null || true

echo "Partitioing Harddrive" >/dev/tty1
for i in $(cat /proc/swaps | grep -v "^Filename" | awk '{print $1}'); do
	swapoff $i
done
while true; do umount /mnt/gentoo//proc; [[ $? > 0 ]] && break; done
while true; do umount /mnt/gentoo//sys;  [[ $? > 0 ]] && break; done
while true; do umount /mnt/gentoo//dev;  [[ $? > 0 ]] && break; done
while true; do umount /mnt/gentoo/;      [[ $? > 0 ]] && break; done

set -e

dd if=/dev/zero of=/dev/sda bs=512 count=1
cat <<EOF | fdisk /dev/sda
n
p
1

+256M
a
1
n
p
2

+512M
n
e



t
2
82
n
l


w
EOF
partprobe
echo "Formatting Harddrive" >/dev/tty1
mkfs.ext2 -m0 /dev/sda1
mkfs.ext4 /dev/sda5
mkswap /dev/sda2
swapon /dev/sda2

mkdir -p /mnt/gentoo || true
mount /dev/sda5 /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount /dev/sda1 /mnt/gentoo/boot
cd /mnt/gentoo
echo "Downloading Stage3" >/dev/tty1
wget -O stage3-amd64.tar.bz2 "ftp://ftp.wh2.tu-dresden.de/pub/mirrors/gentoo//releases/amd64/autobuilds/20130711/stage3-amd64-20130711.tar.bz2"
tar vxjpf stage3-*.tar.bz2
echo "Configuring Portage (Make-Jobs, Mirrors)" >/dev/tty1
MAKEPARALLEL=$((( $(cat /proc/cpuinfo  | grep -e "^processor\s\s*:\s" | wc -l ) + 1 )))
echo "MAKEOPTS=\"-j${MAKEPARALLEL}\"" >> /mnt/gentoo/etc/portage/make.conf
MIRRORS="$(wget -q -O- http://www.gentoo.org/main/en/mirrors3.xml | sed '/country="DE"/, /\/mirrorgroup/!d' | grep 'ipv4="y"' | grep 'protocol="http"' | cut -f2 -d\> | cut -f1 -d\<)"
MIRRORS="$(echo $MIRRORS | xargs -n1 netselect -t 2 -m 50  | sort -n | head -n5 | awk '{print $2}')"
if [ "x$MIRRORS" = "x" ]; then
	echo 'GENTOO_MIRRORS="http://de-mirror.org/gentoo/ ftp://ftp.wh2.tu-dresden.de/pub/mirrors/gentoo"' >> /mnt/gentoo/etc/portage/make.conf
else
	echo "GENTOO_MIRRORS=\"$(echo $MIRRORS)\"" >> /mnt/gentoo/etc/portage/make.conf
fi
echo "Configuring Network" >/dev/tty1
cp -L /etc/resolv.conf /mnt/gentoo/etc
mount -t proc none /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
cp $0 /mnt/gentoo/root/autoinstall.sh
echo "Changeroot into System" >/dev/tty1
if [ "x${DEBUG}" = "xtrue" ]; then
	chroot /mnt/gentoo /bin/bash -x /root/autoinstall.sh CHROOT
else
	chroot /mnt/gentoo /bin/bash /root/autoinstall.sh CHROOT
fi
echo "Cleanup" >/dev/tty1
rm /mnt/gentoo/root/autoinstall.sh
}

post_chroot() {
echo "Setup Environment" >/dev/tty1
source /etc/profile
export PS1="(chroot) $PS1"
set -e
mkdir /usr/portage
echo "First Portage Sync" >/dev/tty1
emerge-webrsync
emerge --sync
eselect profile set 1
echo "Configure Location" >/dev/tty1
cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime
echo "Europe/Berlin" > /etc/timezone

## Stage1 Installation
#echo "Bootstrap Stage 1" >/dev/tty1
#cd /usr/portage/scripts
#./bootstrap.sh
#cd /root
#emerge -e system

echo "Compiling Kernel" >/dev/tty1
emerge gentoo-sources
cd /usr/src/linux
make localmodconfig
echo $?
MAKEPARALLEL=$((( $(cat /proc/cpuinfo  | grep -e "^processor\s\s*:\s" | wc -l ) + 1 )))
make -j$MAKEPARALLEL && make modules_install
export KVER=$(echo $(head Makefile | grep -e "^VERSION" -e "^PATCHLEVEL" -e "^SUBLEVEL" | rev | cut -f1 -d" " | rev) | sed -e "s# #.#g")
cp arch/x86/boot/bzImage /boot/kernel-$KVER-gentoo

echo "Creating InitRD" >/dev/tty1
emerge genkernel
genkernel --install initramfs
ls /boot/{kernel,initramfs}*

echo "Creating fstab" >/dev/tty1
cat /etc/fstab | grep -v -e "^/dev/BOOT" -e "^/dev/ROOT" -e "^/dev/SWAP" > /tmp/fstab && mv /tmp/fstab /etc/fstab

echo "/dev/sda5 / ext4 defaults 0 1" >> /etc/fstab
echo "/dev/sda2 none swap sw 0 0" >> /etc/fstab
echo "/dev/sda1 /boot ext2 defaults 0 2" >> /etc/fstab

echo "Configure Network-Environment" >/dev/tty1
emerge bind-tools
emerge iproute2

IFACE=$(ip addr show | grep -v "^ " | grep -v "lo: " | cut -f2 -d":" | rev | cut -f1 -d" " | rev )
MYFIRSTIP=$(ip addr show $IFACE | grep "inet " | awk '{print $2}' | cut -f1 -d"/")
MYFIRSTMAC=$(ip link show $IFACE  | grep "link/" | awk '{print $2}')
NODENAME=$(host $MYFIRSTIP | rev | cut -f1 -d" " | rev | cut -f1 -d".")
DOMAIN=$(host $MYFIRSTIP | rev | cut -f1 -d" " | cut -b2- | rev | cut -f2- -d".")

echo "hostname=\"$NODENAME\"" > /etc/conf.d/hostname

echo "dns_domain_lo=\"localdomain\"" > /etc/conf.d/net
echo 'config_eth0="dhcp"' >> /etc/conf.d/net

echo '127.0.0.1	localhost.localdomain localhost' > /etc/hosts
echo '::1 localhost.localdomain localhost' >> /etc/hosts
echo "$MYFIRSTIP	$NODENAME.$DOMAIN $NODENAME" >> /etc/hosts

cd /etc/init.d
ln -s net.lo net.eth0
rc-update add net.eth0 default

echo "Setting Root-Password" >/dev/tty1
set -e
echo 'root:@ROOTPASSWORD@' | chpasswd
echo 'de_DE.UTF-8 UTF-8' > /etc/locale.gen
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
echo 'LANG="en_US.UTF-8"' > /etc/env.d/02locale
echo 'LC_COLLATE="C"' >> /etc/env.d/02locale
env-update && source /etc/profile
echo "Installing System-Software" >/dev/tty1
emerge syslog-ng
rc-update add syslog-ng default
emerge vixie-cron
rc-update add vixie-cron default
emerge mlocate
rc-update add sshd default
emerge dhcpcd

echo "Disabling udev-iface-rename" >/dev/tty1
ln -s /dev/null /etc/udev/rules.d/80-net-name-slot.rules

echo "Installing Bootloader" >/dev/tty1
emerge grub
cat <<EOGRUBCFG >/boot/grub/grub.conf
default 0
timeout 2
title Gentoo Linux $KVER
root (hd0,0)
kernel (hd0,0)/kernel-$KVER-gentoo root=/dev/sda5
initrd (hd0,0)/initramfs-genkernel-x86_64-$KVER-gentoo
EOGRUBCFG
grep -v rootfs /proc/mounts > /etc/mtab
grub-install --no-floppy /dev/sda
echo "Running Postinstallation Script" >/dev/tty1
set +e
@POSTINSTALL@
set -e
}

CHROOT=$1

case "$CHROOT" in
	CHROOT)
		if [ "x$DEBUG" = "xfalse" ]; then
			set -x
		fi
		post_chroot
	;;
	*)
		LOGFILE=autoinstall-$(date +%s)
		ERRFILE=autoinstall-$(date +%s)
		if [ "x$DEBUG" = "xfalse" ]; then
			exec >/tmp/$LOGFILE.log 2>/tmp/$LOGFILE.err
		fi
		set -x
		setterm -powersave off -blank 0
		pre_chroot
		echo "Backup Logfiles" >/dev/tty1
		mv /tmp/${LOGFILE}* /mnt/gentoo/root || true # Only present if DEBUG is false
		echo "Unmounting all System-Partitions" >/dev/tty1
		set +e
		while true; do umount /mnt/gentoo/proc; [[ $? > 0 ]] && break; done
		while true; do umount /mnt/gentoo/sys;  [[ $? > 0 ]] && break; done
		while true; do umount /mnt/gentoo/dev/shm;  [[ $? > 0 ]] && break; done
		while true; do umount /mnt/gentoo/dev/pts;  [[ $? > 0 ]] && break; done
		while true; do umount /mnt/gentoo/dev;		[[ $? > 0 ]] && break; done
		while true; do umount /mnt/gentoo/boot;  [[ $? > 0 ]] && break; done
		while true; do umount /mnt/gentoo/;      [[ $? > 0 ]] && break; done
		echo "Reboot" >/dev/tty1
		reboot
	;;
esac

