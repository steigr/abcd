#!/bin/sh

display_welcomemsg() {

  cat <<'EOINFO'
Installation-Helper for Automatic Bootstrap and Configuration Daemon (abcd)

The installer will install abcd and tf2httpd. It many futher install a web, dns and a dhcp-server.

EOINFO
}

display_needsrvrr() {

  cat <<EODNSSRV

Your local DNS-Domain must be extended by one DNS-Service-Record (DNS-SRV):

_netboot._autoprovision IN SRV 10 10 80 $(hostname -f).

This record is needed for tf2httpd, which forward tftp-requests as HTTP-GET-request to this server.

EODNSSRV
}

get_domainname() {
  echo -n "Please give your domain-name: "
  read DOMAINNAME
}


install_packages() {
  apt-get update >~/abcd-installer-$$.log 2>~/abcd-installer-$$.err
  apt-get install bind9 isc-dhcp-server lighttpd bind9-host python-dnspython python-daemon >~/abcd-installer-$$.log 2>~/abcd-installer-$$.err
}

configure_lighttpd() {
  cat doc/examples/lighttpd.conf.example | sed -e "s/example\.com/${DOMAINNAME}/" > /etc/lighttpd/conf-availabe/60-abcd.conf
  lighttpd-enable-mod accesslog
  lighttpd-enable-mod alias
  lighttpd-enable-mod cgi
  lighttpd-enable-mod abcd
  
  /etc/init.d/lighttpd restart
}


install_tf2httpd() {
  
  git clone git://github.com/steigr/tf2httpd.git /tmp/tf2httpd
  
  cp /tmp/tf2httpd/tf2httpd /usr/sbin/tf2httpd
  cp /tmp/tf2httpd/tf2httpd.init /etc/init.d/tf2httpd
  update-rc.d tf2httpd defaults
  
  rm -rf /tmp/tf2httpd
  
  host -t SRV _netboot._autoprovision || display_needsrvrr
  
}

install_abcd() {
  
  mkdir /etc/abcd
  mkdir /usr/lib/abcd
  mkdir /var/lib/abcd
  
  cp sbin/abcd-downloader /usr/sbin/abcd-downloader
  chown root:root /usr/sbin/abcd-downloader
  chmod 744 /usr/sbin/abcd-downloader
  
  cp -r lib/* /usr/lib/abcd
  cp -r etc/* /etc/abcd
  
  chown root:www-data /etc/abcd/clients
  chmod 660 /etc/abcd/clients
  
  chown root:www-data /usr/lib/abcd/server
  chmod 750 /usr/lib/abcd-server
  
}

install_ipxe() {
  echo -n "Install ipxe from git (y/n): "
  read ANSWER
  case "$ANSWER" in
    y)
      apt-get install -y make gcc
      git clone git://git.ipxe.org/ipxe.git /tmp/ipxe
      CAT << 'IPXE_BOOT_SCRIPT' >/tmp/ipxe/default-script
#!ipxe
prompt --key 0x02 --timeout 2000 Press Ctrl-B for the iPXE command line... && shell ||
dhcp
imgload tftp://${next-server}/${filename}
boot
IPXE_BOOT_SCRIPT
      cd /tmp/ipxe/src
      cp config/*.h config/local
      make EMBED=/tmp/ipxe/default-script bin/undionly.kpxe
      mkdir -p /var/lib/abcd/boot/ipxe
      cp bin/undionly.kpxe /var/lib/abcd/boot/ipxe/binary
    ;;
    *)
      echo 'Not installing. Please use ipxe (or gpxe) into /var/lib/abcd/boot/$PXE_FLAVOUR/binary. Netboot-Scripts will be named netboot.$PXE_FLAVOUR'
    ;;
  esac
}

install_installers() {
  echo -n "Download netboot-intallers for Debian/Ubuntu/OpenSUSE/CentOS/Fedora/Archlinux/Gentoo (recent versions) (y/n): "
  read ANSWER
  case "$ANSWER" in
    y)
      abcd-downloader
    ;;
    *)
      echo 'You may run abcd-downloader to get these files later, abcd will not work without them. Please look at /etc/abcd/download.d for more distros or other mirros'
    ;;
}

display_welcomemsg
get_domainname
install_packages
configure_lighttpd
install_tf2httpd
install_abcd
install_ipxe
install_installers
