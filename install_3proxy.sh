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
install_3proxy() {
    echo "installing 3proxy"
    URL="https://raw.githubusercontent.com/vudat199812/proxyv6/main/3proxy-3proxy-0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    make -f Makefile.unix-install
    cd $WORKDIR
    echo "install done"
}
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_
yum -y install gcc net-tools bsdtar zip >/dev/null
check_iptables_install
install_3proxy
