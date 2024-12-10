#!/bin/bash

set -e  # Dừng script nếu gặp lỗi

### Hàm kiểm tra và cài đặt các gói cần thiết ###
check_dependencies() {
    echo "Đang kiểm tra các gói cần thiết..."
    yum -y install gcc net-tools zip curl iproute wget >/dev/null
    yum -y install iptables-services >/dev/null
    systemctl enable iptables
    systemctl start iptables
    echo "Hoàn tất kiểm tra và cài đặt gói."
}

### Hàm làm sạch địa chỉ IPv6 và cấu hình cũ ###
clear_old_config() {
    echo "Xóa địa chỉ IPv6 và cấu hình cũ..."
    ip -6 addr flush dev eth0 || echo "Không có địa chỉ IPv6 nào để xóa."
    systemctl restart NetworkManager

    pkill -f 3proxy || echo "3proxy không chạy, không cần dừng."
    rm -rf /usr/local/etc/3proxy /home/proxy-installer
    echo "Hoàn tất xóa cấu hình cũ."
}

### Hàm tạo chuỗi ngẫu nhiên ###
random_string() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
}

### Hàm tạo địa chỉ IPv6 ngẫu nhiên ###
generate_ipv6() {
    local subnet=$1
    local hex=$(printf "%04x:%04x:%04x:%04x" $((RANDOM % 65536)) $((RANDOM % 65536)) $((RANDOM % 65536)) $((RANDOM % 65536)))
    echo "${subnet}:${hex}"
}

### Hàm cài đặt 3proxy ###
install_3proxy() {
    echo "Cài đặt 3proxy..."
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    wget -qO- https://raw.githubusercontent.com/vudat199812/proxyv6/main/3proxy-3proxy-0.9.4.tar.gz | tar -xz
    cd 3proxy-3proxy-0.9.4
    make -f Makefile.Linux
    cp bin/3proxy /usr/local/etc/3proxy/bin/
    echo "Hoàn tất cài đặt 3proxy."
}

### Hàm tạo file cấu hình cho 3proxy ###
generate_3proxy_config() {
    cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
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
    echo "Hoàn tất tạo cấu hình cho 3proxy."
}

### Hàm tạo dữ liệu proxy ###
generate_proxy_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random_string)/pass$(random_string)/$IP4/$port/$(generate_ipv6 $IP6)"
    done >$WORKDATA
}

### Hàm thêm địa chỉ IPv6 ###
apply_ipv6_addresses() {
    awk -F "/" '{print "ip -6 addr add " $5 "/64 dev eth0"}' ${WORKDATA} | bash
    echo "Đã thêm các địa chỉ IPv6."
}

### Hàm thêm quy tắc iptables ###
apply_iptables_rules() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -j ACCEPT"}' ${WORKDATA} | bash
    echo "Đã thêm quy tắc iptables."
}

### Hàm tạo file proxy cho người dùng ###
generate_proxy_file() {
    awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2}' ${WORKDATA} >proxy.txt
    echo "Thông tin proxy được lưu trong proxy.txt."
}

### Khởi động ###
main() {
    clear_old_config
    check_dependencies
    install_3proxy

    echo "Nhập số lượng proxy muốn tạo (vd: 500):"
    read COUNT

    WORKDIR="/home/proxy-installer"
    WORKDATA="${WORKDIR}/data.txt"
    mkdir -p $WORKDIR

    IP4=$(curl -4 -s icanhazip.com)
    IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
    FIRST_PORT=10000
    LAST_PORT=$((FIRST_PORT + COUNT - 1))

    echo "Địa chỉ IPv4: $IP4"
    echo "Subnet IPv6: $IP6"

    generate_proxy_data
    apply_ipv6_addresses
    apply_iptables_rules
    generate_3proxy_config
    generate_proxy_file

    cat <<EOF >/etc/rc.d/rc.local
#!/bin/bash
bash $WORKDIR/boot_iptables.sh
bash $WORKDIR/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

    chmod +x /etc/rc.d/rc.local
    bash /etc/rc.d/rc.local

    echo "Proxy đã sẵn sàng. Xem file proxy.txt để biết thông tin chi tiết."
}

main
