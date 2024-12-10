#!/bin/bash

WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

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
    if ! command -v 3proxy &>/dev/null; then
        echo "Cài đặt 3proxy..."
        URL="https://raw.githubusercontent.com/vudat199812/proxyv6/main/3proxy-3proxy-0.9.4.tar.gz"
        wget -qO- $URL | bsdtar -xvf-
        cd 3proxy-0.9.4
        make -f Makefile.Linux
        mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
        cp bin/3proxy /usr/local/etc/3proxy/bin/
        cd $WORKDIR
    else
        echo "3proxy đã được cài đặt."
    fi
    
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

rotate_proxy_info() {
    echo "Đang thay đổi thông tin proxy..."
    rm -f $WORKDIR/proxy.txt $WORKDATA
    seq $FIRST_PORT $LAST_PORT | while read port; do
        USER="usr$(random)"
        PASS="pass$(random)"
        IPV6=$(gen64 $IP6)
        echo "$USER/$PASS/$IP4/$port/$IPV6" >> $WORKDATA
    done
    gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg
    gen_proxy_file_for_user
    update_iptables
    update_ifconfig
    systemctl restart 3proxy
    echo "Thông tin proxy mới đã được cập nhật và lưu tại $WORKDIR/proxy.txt."
}

gen_proxy_file_for_user() {
    awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2}' ${WORKDATA} >$WORKDIR/proxy.txt
}

update_iptables() {
    echo "Cập nhật lại các quy tắc iptables..."
    iptables -F
    awk -F "/" '{print "iptables -A INPUT -p tcp --dport " $4 " -j ACCEPT"}' ${WORKDATA} | bash
    iptables-save > /etc/sysconfig/iptables
    echo "Quy tắc iptables đã được cập nhật."
}

update_ifconfig() {
    echo "Cập nhật địa chỉ IPv6..."
    ip -6 addr flush dev eth0
    awk -F "/" '{print "ip -6 addr add " $5 "/64 dev eth0"}' ${WORKDATA} | bash
    echo "Địa chỉ IPv6 đã được cập nhật."
}

main() {
    echo "Cài đặt proxy IPv6 với 3proxy"
    mkdir -p $WORKDIR && cd $WORKDIR
    install_3proxy

    echo "Nhập số lượng proxy bạn muốn tạo (ví dụ: 100):"
    read COUNT
    FIRST_PORT=10000
    LAST_PORT=$(($FIRST_PORT + $COUNT - 1))

    rotate_proxy_info
    echo "Hoàn tất! Proxy đã sẵn sàng và thông tin được lưu tại $WORKDIR/proxy.txt."
}

main
