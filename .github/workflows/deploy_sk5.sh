#!/bin/bash
# 版本：v2.1.0
# 最后更新：2025-03-26
# 功能：全自动Dante SOCKS5服务部署

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 异常处理
set -eo pipefail
trap 'echo -e "${RED}✖ 错误发生在第${LINENO}行，退出码：$?${RESET}" >&2; exit 1' ERR

# 依赖检查
check_dependencies() {
    local deps=("curl" "wget" "gcc" "make")
    for dep in "${deps[@]}"; do
        if ! command -v $dep &>/dev/null; then
            echo -e "${BLUE}▶ 安装依赖：$dep...${RESET}"
            apt-get install -y $dep || yum install -y $dep
        fi
    done
}

# 编译安装Dante
install_dante() {
    local temp_dir=$(mktemp -d)
    cd $temp_dir
    
    echo -e "${BLUE}▶ 下载Dante源码...${RESET}"
    wget -q --show-progress https://github.com/Lozy/danted/archive/master.zip
    unzip -q master.zip
    
    echo -e "${BLUE}▶ 编译安装中...${RESET}"
    cd danted-master
    ./configure --prefix=/usr/local \
                --sysconfdir=/etc \
                --localstatedir=/var \
                --with-sockd-conf=/etc/danted/sockd.conf
    make -j$(nproc)
    make install
}

# 服务配置
configure_service() {
    # 生成随机凭证
    local PORT=${1:-1080}
    local USERNAME="proxy$(date +%s | tail -c 4)"
    local PASSWORD=$(openssl rand -base64 16)

    # 配置文件
    mkdir -p /etc/danted
    cat > /etc/danted/sockd.conf <<EOF
logoutput: syslog
internal: 0.0.0.0 port = $PORT
external: $(curl -s ifconfig.me)
socksmethod: username
clientmethod: none
user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
    method: username
}
EOF

    # 认证文件
    echo "$USERNAME:$PASSWORD" > /etc/danted/sockd.passwd
    chmod 600 /etc/danted/sockd.passwd
}

# 主流程
main() {
    # 权限检查
    [[ $EUID -ne 0 ]] && { echo -e "${RED}✖ 请使用root权限执行${RESET}"; exit 1; }
    
    check_dependencies
    install_dante
    configure_service 1080
    
    # 系统服务配置
    cat > /etc/systemd/system/sockd.service <<EOF
[Unit]
Description=Dante SOCKS Proxy
After=network.target

[Service]
Type=forking
PIDFile=/run/sockd.pid
ExecStart=/usr/local/sbin/sockd -D -f /etc/danted/sockd.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable --now sockd
    
    # 输出结果
    echo -e "${GREEN}✔ 部署成功！${RESET}"
    echo -e "代理地址：$(curl -s ifconfig.me):1080"
    echo -e "认证信息：${YELLOW}${USERNAME}:${PASSWORD}${RESET}"
}

main "$@"
