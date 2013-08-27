#!/bin/bash

display_welcomemsg() {

  cat <<'EOINFO'
Installation-Helper for Automatic Bootstrap and Configuration Daemon (abcd)

The installer will install abcd and tf2httpd. It may futher install a web, dns and a dhcp-server.

EOINFO
}

display_finished_installation() {
  cat <<'EOFINISHED'
Installation complete.

Please check out the files in /etc/abcd and /var/lib/abcd and change them as needed. (Especially ROOTPASSWORD-String)
EOFINISHED
}

ask_domainname() {
  echo -n "Enter Domainname: "
  read DOMAINNAME
}

ask_bootserver() {
  echo -n "Enter FQDN of the bootserver: "
  read BOOTSERVER
}

ask_install_bind9() {
  echo -n "Install bind9 DNS-Server (y/n): "
  read INSTALL_BIND9
}

ask_install_dhcpd() {
  echo -n "Install ISC DHCP-Server (y/n): "
  read INSTALL_DHCPD
}

ask_install_lighttpd() {
  echo -n "Install Lighttpd Web-Server (y/n): "
  read INSTALL_LIGHTTPD
}

ask_install_ipxe() {
  echo -n "Compile iPXE-Bootloader (y/n): "
  read INSTALL_IPXE
}

ask_install_atftpd() {
  echo -n "Install aTFTP-Server (y/n): "
  read INSTALL_ATFTPD
}

ask_install_abcd_downloader() {
  echo -n "Install and run ABCD-Downloader (y/n): "
  read INSTALL_ABCDDOWNLOADER
}

install_packages() {
  apt-get update -q
  apt-get install -y -q bind9-host
}

install_bind9() {
  apt-get install -y -q bind9
}

install_dhcpd() {
  apt-get install -y -q isc-dhcp-server 
}

install_lighttpd() {
  apt-get install -y -q lighttpd
  cat <<'EOF_LIGHTTPD_CONF' >/etc/lighttpd/conf-available/60-abcd.conf
$HTTP["host"] =~ "^@($|.@@)" {
  alias.url = ( "" => "/usr/lib/abcd/server" )
  $HTTP["url"] =~ "^/" {
    cgi.assign = ( "" => "" )
  }
}
EOF_LIGHTTPD_CONF
  BOOTSERVERNAME=$(echo $BOOTSERVER | sed -e "s#\.$DOMAINNAME##")
  sed -i -e "s#@@#$DOMAINNAME#" \
         -e "s#@#$BOOTSERVERNAME#" \
    /etc/lighttpd/conf-available/60-abcd.conf
  lighttpd-enable-mod accesslog
  lighttpd-enable-mod alias
  lighttpd-enable-mod cgi
  lighttpd-enable-mod abcd
  
  /etc/init.d/lighttpd restart
}


install_atftpd() {
  apt-get install -y atftpd
}

install_lhtfs() {
  
  apt-get install fuse python-fuse -y
  git clone git://github.com/steigr/lhtfs.git /tmp/lhtfs
  cp /tmp/lhtfs/lhtfs /usr/sbin/lhtfs
  chmod 0700 /usr/sbin/lhtfs
  adduser nobody fuse
  echo 'lhtfs#http://bootserver /srv/tftp fuse  defaults,allow_other 0 0' >> /etc/fstab
  umount /srv/tftp
  mount /srv/tftp
  
}

install_abcd() {
  test -e /etc/abcd && rm -rf /etc/abcd
  mkdir /etc/abcd
  test -e /usr/lib/abcd && rm -rf /usr/lib/abcd
  mkdir /usr/lib/abcd
  test -e /var/lib/abcd && rm -rf /var/lib/abcd
  mkdir /var/lib/abcd
  
  cp -r lib/* /usr/lib/abcd
  cp -r etc/* /etc/abcd
  cp -r var/* /var/lib/abcd
  
  chown root:www-data /etc/abcd/clients
  chmod 660 /etc/abcd/clients
  
  chown root:www-data /usr/lib/abcd/server
  chmod 750 /usr/lib/abcd/server
  
}

install_ipxe() {
  apt-get install -q -y make gcc binutils zlib1g-dev syslinux
  IPXETMP=/tmp/ipxe.$$
  git clone git://git.ipxe.org/ipxe.git $IPXETMP
  cat << 'IPXE_BOOT_SCRIPT' >$IPXETMP/default-script
#!ipxe
prompt --key 0x02 --timeout 2000 Press Ctrl-B for the iPXE command line... && shell ||
dhcp
imgload tftp://${next-server}/${filename}
boot
IPXE_BOOT_SCRIPT
  OLDPWD=$(pwd)
  cd $IPXETMP/src
  cp config/*.h config/local
  make EMBED=$IPXETMP/default-script bin/undionly.kpxe
  mkdir -p /var/lib/abcd/boot/ipxe
  cp bin/undionly.kpxe /var/lib/abcd/boot/ipxe/binary
  cd $OLDPWD
  rm -rf $IPXETMP
}

install_abcd_downloader() {
  rm -rf /etc/abcd/download.d
  git clone git://github.com/steigr/abcd-downloader.git /etc/abcd/download.d
  ln -s /etc/abcd/download.d/abcd-downloader /usr/sbin/abcd-downloader
  chmod 0700 /etc/abcd/download.d/abcd-downloader
  abcd-downloader
}


case "$1" in
  -d)
    DOMAINNAME=$(dnsdomainname)
    BOOTSERVER=bootserver.$DOMAINNAME
    INSTALL_BIND9=y
    INSTALL_DHCPD=y
    INSTALL_ATFTPD=y
    INSTALL_LIGHTTPD=y
    INSTALL_IPXE=y
    INSTALL_ABCDDOWNLOADER=y
  ;;
  *)
    display_welcomemsg
    ask_domainname
    ask_bootserver
    ask_domainname
    ask_bootserver
    ask_install_bind9
    ask_install_dhcpd
    ask_install_lighttpd
    ask_install_atftpd
    ask_install_ipxe
    ask_install_abcd_downloader
  ;;
esac

install_packages
install_lhtfs
[[ "x${INSTALL_BIND9}" = "xy" ]] && install_bind9
[[ "x${INSTALL_DHCPD}" = "xy" ]] && install_dhcpd
[[ "x${INSTALL_LIGHTTPD}" = "xy" ]] && install_lighttpd
[[ "x${INSTALL_ATFTPD}" = "xy" ]] && install_atftpd
install_abcd
[[ "x${INSTALL_IPXE}" = "xy" ]] && install_ipxe
[[ "x${INSTALL_ABCDDOWNLOADER}" = "xy" ]] && install_abcd_downloader

display_finished_installation
