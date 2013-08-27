#!/bin/sh

display_welcomemsg() {

  cat <<'EOINFO'
Installation-Helper for Automatic Bootstrap and Configuration Daemon (abcd)

The installer will install abcd and tf2httpd. It may futher install a web, dns and a dhcp-server.

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
  echo -n "Enter Domainname: "
  read DOMAINNAME
}

get_bootserver() {
  echo -n "Enter FQDN of the bootserver: "
  read BOOTSERVER
}


install_packages() {
  apt-get update -q
  apt-get install -y -q bind9 isc-dhcp-server lighttpd bind9-host
}

configure_lighttpd() {
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
  echo -n "Install ipxe from git (y/n): "
  read ANSWER
  case "$ANSWER" in
    y)
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
    ;;
    *)
      echo 'Not installing. Please use ipxe (or gpxe) into /var/lib/abcd/boot/$PXE_FLAVOUR/binary. Netboot-Scripts will be named netboot.$PXE_FLAVOUR'
    ;;
  esac
}

install_abcd_downloader() {
	rm -rf /etc/abcd/download.d
	git clone git://github.com/steigr/abcd-downloader.git /etc/abcd/download.d
	ln -s /etc/abcd/download.d/abcd-downloader /usr/sbin/abcd-downloader
	chmod 0700 /etc/abcd/download.d/abcd-downloader
}

install_installers() {
  echo -n "Download netboot-intallers for Debian/Ubuntu/OpenSUSE/CentOS/Fedora/Archlinux/Gentoo (recent versions) (y/n): "
  read ANSWER
  case "$ANSWER" in
    y)
      install_abcd_downloader
      abcd-downloader
    ;;
    *)
      echo 'You may run abcd-downloader to get these files later, abcd will not work without them. Please look at /etc/abcd/download.d for more distros or other mirros'
    ;;
  esac
}

display_welcomemsg
get_domainname
get_bootserver
install_packages
configure_lighttpd
install_atftpd
install_lhtfs
install_abcd
install_ipxe

