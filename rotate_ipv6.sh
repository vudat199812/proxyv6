#!/bin/sh

# Hàm kiểm tra và cài đặt iptables nếu chưa có
check_iptables_install() {
    if ! iptables -V &> /dev/null; then
        echo "iptables chưa được cài đặt. Đang tiến hành cài đặt..."
        sudo yum install -y iptables-services
        sudo systemctl enable iptables
        sudo systemctl start iptables
    else
        echo "iptables đã được cài đặt."
    fi
}

# Hàm xóa IPv6 và các tệp cấu hình cũ
clear_proxy_and_file() {
    if ip -6 addr show dev eth0 | grep "inet6" | grep -v "::1/64" | grep -v "fe80::" | awk '{print $2}' | xargs -I {} sudo ip -6 addr del {} dev eth0; then
        echo "Đã xóa các địa chỉ IPv6 không mong muốn thành công."
    else
        echo "Lỗi khi xóa địa chỉ IPv6, tiếp tục chạy lệnh tiếp theo."
    fi
    systemctl restart NetworkManager
    rm -rf /home/proxy-installer
    rm -rf /usr/local/etc/3proxy/bin/3proxy
}

# Hàm tạo chuỗi ngẫu nhiên
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Mảng để tạo địa chỉ IPv6
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Hàm tạo địa chỉ IPv6 ngẫu nhiên
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Hàm cài đặt 3proxy
install_3proxy() {
    echo "Đang cài đặt 3proxy..."
    URL="https://raw.githubusercontent.com/3proxy/3proxy/master/3proxy-0.9.4.tar.gz"
    wget -qO- $URL | tar -xzf-
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
}

# Hàm tạo file cấu hình 3proxy
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

# Hàm tạo file chứa proxy cho người dùng
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Hàm tạo dữ liệu proxy
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "user$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

# Hàm tạo script iptables
gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

# Hàm tạo script thêm IPv6
gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

# Bắt đầu cài đặt
echo "Đang cài đặt các gói cần thiết..."
yum -y install gcc net-tools wget tar >/dev/null
chmod +x /etc/rc.d/rc.local
systemctl enable rc-local
systemctl start rc-local

check_iptables_install
clear_proxy_and_file
install_3proxy

echo "Thư mục làm việc: /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Địa chỉ IP nội bộ: ${IP4}. Dải IPv6 bên ngoài: ${IP6}"

# Số lượng proxy cố định là 100
COUNT=100

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

echo "Quá trình hoàn tất. Proxy đã được tạo và cấu hình thành công."
