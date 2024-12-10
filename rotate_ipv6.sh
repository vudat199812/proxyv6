#!/bin/sh

check_iptables_install() {
    if ! iptables -V &> /dev/null
    then
        echo "iptables chưa được cài đặt. Đang tiến hành cài đặt..."
        sudo yum install -y iptables-services
        sudo systemctl enable iptables
        sudo systemctl start iptables
    else
        echo "iptables đã được cài đặt."
    fi
}

clear_proxy_and_file() {
    # Xóa tất cả các địa chỉ IPv6 trên giao diện eth0
    echo "Đang xóa tất cả các địa chỉ IPv6 trên eth0..."
    sudo ip link set dev eth0 down
    sudo ip -6 addr flush dev eth0
    sudo ip link set dev eth0 up

    if [ $? -eq 0 ]; then
        echo "Đã xóa tất cả các địa chỉ IPv6 thành công."
    else
        echo "Lỗi khi xóa các địa chỉ IPv6."
    fi

    # Khởi động lại dịch vụ mạng
    echo "Khởi động lại dịch vụ mạng..."
    sudo systemctl restart NetworkManager

    # Xóa thư mục và tệp không cần thiết
    if [ -d "/home/proxy-installer" ]; then
        echo "Đang xóa thư mục /home/proxy-installer..."
        sudo rm -rf /home/proxy-installer
    else
        echo "/home/proxy-installer không tồn tại."
    fi

    if [ -f "/usr/local/etc/3proxy/bin/3proxy" ]; then
        echo "Đang xóa tệp /usr/local/etc/3proxy/bin/3proxy..."
        sudo rm -rf /usr/local/etc/3proxy/bin/3proxy
    else
        echo "/usr/local/etc/3proxy/bin/3proxy không tồn tại."
    fi

    echo "Chờ 3 giây để đảm bảo các thao tác hoàn tất..."
    sleep 3
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
    echo "Installing 3proxy..."
    URL="https://raw.githubusercontent.com/vudat199812/proxyv6/main/3proxy-3proxy-0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp bin/3proxy /usr/local/etc/3proxy/bin/
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
    echo "Uploading proxy..."
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF
#!/bin/bash
for port in {${FIRST_PORT}..${LAST_PORT}}; do
    if ! sudo iptables -C INPUT -p tcp --dport \$port -m state --state NEW -j ACCEPT 2>/dev/null; then
        sudo iptables -I INPUT -p tcp --dport \$port -m state --state NEW -j ACCEPT
        echo "Đã thêm cổng \$port vào iptables."
    else
        echo "Cổng \$port đã tồn tại trong iptables, bỏ qua."
    fi
done
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

echo "Installing required apps..."
yum -y install gcc net-tools bsdtar zip >/dev/null
chmod +x /etc/rc.d/rc.local
systemctl enable rc-local
systemctl start rc-local
check_iptables_install
clear_proxy_and_file
install_3proxy

echo "Working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. External subnet for IP6 = ${IP6}"

echo "How many proxies do you want to create? Example: 500"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh /etc/rc.d/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.d/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

bash /etc/rc.d/rc.local
gen_proxy_file_for_user
