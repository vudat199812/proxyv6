#!/bin/sh
check_iptables_install() {
    if ! iptables -V &> /dev/null
    then
        echo "iptables chưa được cài đặt. Đang tiến hành cài đặt..."
        sudo yum install -y iptables-services
        systemctl enable iptables
        systemctl start iptables
    else
        echo "iptables đã được cài đặt."
    fi
}

random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c5
	echo
}


array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}
install_3proxy() {
    echo "installing 3proxy"
    URL="https://raw.githubusercontent.com/vudat199812/proxyv6/main/3proxy-3proxy-0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    cp root/3proxy-0.9.4/scripts/3proxy.service /etc/systemd/system/3proxy.service
    systemctl daemon-reload
    cd $WORKDIR
}


gen_3proxy() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong
users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})
$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

upload_proxy() {
    echo "upload"

}
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}
echo "installing apps"
yum -y install gcc net-tools bsdtar zip >/dev/null
check_iptables_install
install_3proxy

echo "working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. Exteranl sub for ip6 = ${IP6}"

echo "How many proxy do you want to create? Example 500"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh /etc/rc.d/rc.local
>/root/3proxy-0.9.4/scripts/3proxy.cfg
gen_3proxy >/root/3proxy-0.9.4/scripts/3proxy.cfg
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
systemctl start 3proxy

gen_proxy_file_for_user

upload_proxy
