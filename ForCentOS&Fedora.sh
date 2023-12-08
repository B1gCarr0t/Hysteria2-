#!/bin/bash

bold=$(tput bold)
green=$(tput setaf 2)
reset=$(tput sgr0)

echo "${bold}${green}欢迎使用由BigCarr0t大胡萝卜提供的Hysteria2一键安装脚本！${reset}"
echo "${bold}${green}特别感谢由Asahi 一米六五大帅哥提供的测试环境${reset}"
echo "${bold}${green}特别感谢由 河滨 岩石 提供的URI模版${reset}"
read -p "按 Enter 键继续..."

# 应要求添加URI再显示功能

read -p "重新部署Hysteria2请输入1；显示配置URI请输入2: " USER_PURPOSE

# 移除dpkg锁，虽然这不是必要的，但有时候又是必要的

sudo rm -f /var/run/yum.pid

# 更新软件源
if [ "$USER_PURPOSE" == "1" ]; then
  echo "正在更新软件源..."
  if yum update; then
    echo "软件源更新成功！"
  else
    echo "软件源更新失败，请检查网络连接或手动执行 'yum update'。"
    exit 1
  fi
  # 安装curl组件
  echo "正在安装curl..."
  if yum install -y curl; then
    echo "curl安装成功！"
  else
    echo "curl安装失败，请检查网络连接或手动执行 'yum install curl'。"
    exit 1
  fi
  # 安装Hysteria2
  echo "正在安装Hysteria2..."
  if bash <(curl -fsSL https://get.hy2.sh/); then
    echo "Hysteria2安装成功！"
  else
    echo "Hysteria2安装失败，请检查网络连接或手动执行 'bash <(curl -fsSL https://get.hy2.sh/)'。"
    exit 1
  fi
  # 编写Hysteria2配置文件
  echo "配置Hysteria2监听端口..."

  read -p "请输入希望Hysteria2监听的端口（默认为443）: " LISTEN_PORT
  LISTEN_PORT=${LISTEN_PORT:-"443"}

  read -p "是否开启端口跳跃？输入 1（默认关闭）或 2（开启）: " PORT_HOPPING
  PORT_HOPPING=${PORT_HOPPING:-"1"}

  DEFAULT_INTERFACE=$(ip route | awk '/^default/ {print $5}')
  echo "检测到默认网卡为: $DEFAULT_INTERFACE"

  if [ "$PORT_HOPPING" == "2" ]; then
    if ! command -v iptables &> /dev/null || ! command -v ip6tables &> /dev/null; then
      echo "正在安装iptables和ip6tables..."
      if yum install -y iptables ip6tables; then
        echo "iptables和ip6tables安装成功！"
      else
        echo "iptables和ip6tables安装失败，请检查网络连接或手动执行 'yum install iptables ip6tables'。"
        exit 1
      fi
    fi
    read -p "请输入希望开启的端口段（默认为5000-6000）: " PORT_HOPPING_RANGE
    PORT_HOPPING_RANGE=${PORT_HOPPING_RANGE:-"5000-6000"}

    PORT_RANGE_FORMATTED=$(echo "$PORT_HOPPING_RANGE" | sed 's/-/:/')

    sudo iptables -t nat -F && iptables -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p udp --dport $PORT_RANGE_FORMATTED -j DNAT --to-destination :$LISTEN_PORT

    ip6tables -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p udp --dport $PORT_RANGE_FORMATTED -j DNAT --to-destination :$LISTEN_PORT

    echo "已为用户配置iptables和ip6tables的DNAT端口转发规则，将端口段 $PORT_HOPPING_RANGE 转发到 $LISTEN_PORT "
  fi

  read -p "请选择证书类型：输入 1（自签证书，默认）或 2（CA证书）: " CERT_TYPE
  CERT_TYPE=${CERT_TYPE:-"1"}

  if [ "$CERT_TYPE" == "1" ]; then
    read -p "请输入自签证书域名（将成为伪装站点，默认为bing.com）: " SELF_SIGNED_DOMAIN
    SELF_SIGNED_DOMAIN=${SELF_SIGNED_DOMAIN:-"bing.com"}  # 默认域名为bing.com
    CERT_PATH="/etc/hysteria/$SELF_SIGNED_DOMAIN.crt"
    KEY_PATH="/etc/hysteria/$SELF_SIGNED_DOMAIN.key"

    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout $KEY_PATH -out $CERT_PATH -subj "/CN=$SELF_SIGNED_DOMAIN" -days 36500
    chown hysteria:hysteria $KEY_PATH $CERT_PATH

    echo "已生成自签证书：$CERT_PATH 和私钥：$KEY_PATH"
  fi

  if [ "$CERT_TYPE" == "2" ]; then
    read -p "请输入自有域名（已正确解析，并开放了80、443端口）: " OWN_DOMAIN
    read -p "请输入email（用于Let's Encrypt证书申请）: " EMAIL

    echo "Hysteria2将在运行时自动申请Let's Encrypt证书。"
  fi

  read -p "请选择如何设置Hysteria2的密码：输入 1（手动设置）或 2（自动设置，默认）: " PASSWORD_OPTION
  PASSWORD_OPTION=${PASSWORD_OPTION:-"2"}

  if [ "$PASSWORD_OPTION" == "1" ]; then
    read -s -p "请设置Hysteria2的密码: " HYSTERIA_PASSWORD
    echo
  else
    HYSTERIA_PASSWORD=$(openssl rand -hex 32)
    echo "已生成一个64位的随机密码。"
  fi

  CONFIG_FILE="/etc/hysteria/config.yaml"

  echo "listen: :$LISTEN_PORT" > $CONFIG_FILE

  if [ "$CERT_TYPE" == "1" ]; then
    echo "tls:" >> $CONFIG_FILE
    echo "  cert: /etc/hysteria/$SELF_SIGNED_DOMAIN.crt" >> $CONFIG_FILE
    echo "  key: /etc/hysteria/$SELF_SIGNED_DOMAIN.key" >> $CONFIG_FILE
  fi

  if [ "$CERT_TYPE" == "2" ]; then
    echo "acme:" >> $CONFIG_FILE
    echo "  domains:" >> $CONFIG_FILE
    echo "    - $OWN_DOMAIN" >> $CONFIG_FILE
    echo "  email: $EMAIL" >> $CONFIG_FILE
  fi

  echo "quic:" >> $CONFIG_FILE
  echo "  initStreamReceiveWindow: 8388608" >> $CONFIG_FILE
  echo "  maxStreamReceiveWindow: 8388608" >> $CONFIG_FILE
  echo "  initConnReceiveWindow: 20971520" >> $CONFIG_FILE
  echo "  maxConnReceiveWindow: 20971520" >> $CONFIG_FILE
  echo "  maxIdleTimeout: 30s" >> $CONFIG_FILE
  echo "  maxIncomingStreams: 1024" >> $CONFIG_FILE
  echo "  disablePathMTUDiscovery: false" >> $CONFIG_FILE
  echo "ignoreClientBandwidth: false" >> $CONFIG_FILE
  echo "disableUDP: false" >> $CONFIG_FILE
  echo "udpIdleTimeout: 600s" >> $CONFIG_FILE
  echo "auth:" >> $CONFIG_FILE
  echo "  type: password" >> $CONFIG_FILE

  if [ "$PASSWORD_OPTION" == "1" ]; then
    read -s -p "请设置Hysteria2的密码: " HYSTERIA_PASSWORD
    echo
  else
    HYSTERIA_PASSWORD=$(openssl rand -hex 32)
    echo "已生成一个64位的随机密码。"
  fi

  echo "  password: $HYSTERIA_PASSWORD" >> $CONFIG_FILE
  echo "masquerade:" >> $CONFIG_FILE
  echo "  type: proxy" >> $CONFIG_FILE
  echo "  proxy:" >> $CONFIG_FILE

  if [ "$CERT_TYPE" == "1" ]; then
    echo "    url: https://$SELF_SIGNED_DOMAIN" >> $CONFIG_FILE
  else
    echo "    url: https://$OWN_DOMAIN" >> $CONFIG_FILE
  fi

  echo "    rewriteHost: true" >> $CONFIG_FILE

  echo "正在重启Hysteria2服务..."
  if systemctl restart hysteria-server; then
    echo "Hysteria2服务重启成功！"
  else
    echo "Hysteria2服务重启失败，请手动执行 'systemctl restart hysteria-server'。"
  fi
  echo "正在将Hysteria2设置为开启启动..."
  if systemctl enable hysteria-server; then
    echo "已成功将 Hysteria2 设置为开机启动！"
  else
    echo "Hysteria2设置开机启动失败，请手动执行 'systemctl enable hysteria-server'。"
  fi
  echo "正在检查Hysteria2服务的运行状态..."
  if systemctl is-active --quiet hysteria-server && journalctl -u hysteria-server | grep -q "server up and running"; then
    echo "Hysteria2服务正在运行。"
  else
    echo "Hysteria2服务未能正常运行，正在尝试重启服务..."

    if systemctl restart hysteria-server && systemctl is-active --quiet hysteria-server && journalctl -u hysteria-server | grep -q "server up and running"; then
      echo "Hysteria2服务重启成功！"
    else
      echo "Hysteria2服务重启失败，请手动执行 'systemctl restart hysteria-server' 并检查日志以获取详细信息。"
    fi
  fi
  HYSTERIA_STATUS=$(systemctl is-active hysteria-server)

  if [ "$HYSTERIA_STATUS" != "active" ]; then
    echo "Hysteria2服务未运行正常，请先确保服务正常运行。"
    exit 1
  fi
  # 生成URI
  if ! command -v jq &> /dev/null; then
    echo "正在安装jq工具..."
    if yum install -y jq; then
      echo "jq工具安装成功！"
    else
      echo "jq工具安装失败，请检查网络连接或手动执行 'yum install jq'。"
      exit 1
    fi
  fi

  PUBLIC_IP=$(curl -s https://api64.ipify.org?format=json | jq -r '.ip')
  IP_VERSION=""
  if [[ $PUBLIC_IP =~ .*:.* ]]; then
    IP_VERSION="IPv6"
  elif [[ $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IP_VERSION="IPv4"
  fi

  HYSTERIA_CONFIG_FILE="/etc/hysteria/config.yaml"
  if [ -f "$HYSTERIA_CONFIG_FILE" ]; then
    LISTEN_PORT=$(grep -E '^listen: :' $HYSTERIA_CONFIG_FILE | awk '{print $2}')
    TLS_CERT_FILE=$(grep -E '^  cert:' $HYSTERIA_CONFIG_FILE | awk '{print $2}')
    TLS_KEY_FILE=$(grep -E '^  key:' $HYSTERIA_CONFIG_FILE | awk '{print $2}')
    PASSWORD=$(grep -E '^  password:' $HYSTERIA_CONFIG_FILE | awk '{print $2}')
    MASQUERADE_URL=$(grep -E '^    url:' $HYSTERIA_CONFIG_FILE | awk '{print $2}')

    URI_FILE="/etc/hysteria/uri.txt"
    if [ "$IP_VERSION" == "IPv4" ]; then
      CONFIG_URI="hy2://$PASSWORD@$PUBLIC_IP$LISTEN_PORT/?insecure=1&sni=$(echo "$MASQUERADE_URL" | sed 's|https://||')#hy2"

      if [ "$PORT_HOPPING" == "2" ]; then
        CONFIG_URI="hy2://$PASSWORD@$PUBLIC_IP$LISTEN_PORT/?insecure=1&mport=$(echo "$LISTEN_PORT" | sed 's|:||')%2C$PORT_HOPPING_RANGE&sni=$(echo "$MASQUERADE_URL" | sed 's|https://||')#hy2"
      fi

      echo "IPv4配置URI生成完成: ${bold}${green}$CONFIG_URI${reset}"
      echo "$CONFIG_URI" > $URI_FILE
    elif [ "$IP_VERSION" == "IPv6" ]; then
      CONFIG_URI="hy2://$PASSWORD@[$PUBLIC_IP]$LISTEN_PORT/?insecure=1&sni=$(echo "$MASQUERADE_URL" | sed 's|https://||')#hy2"

    if [ "$PORT_HOPPING" == "2" ]; then
      CONFIG_URI="hy2://$PASSWORD@$PUBLIC_IP$LISTEN_PORT/?insecure=1&mport=$(echo "$LISTEN_PORT" | sed 's|:||')%2C$PORT_HOPPING_RANGE&sni=$(echo "$MASQUERADE_URL" | sed 's|https://||')#hy2"
    fi
  
    echo "IPv4配置URI生成完成: ${bold}${green}$CONFIG_URI${reset}"
    echo "$CONFIG_URI" > $URI_FILE
  elif [ "$IP_VERSION" == "IPv6" ]; then
    CONFIG_URI="hy2://$PASSWORD@[$PUBLIC_IP]$LISTEN_PORT/?insecure=1&sni=$(echo "$MASQUERADE_URL" | sed 's|https://||')#hy2"
  
    if [ "$PORT_HOPPING" == "2" ]; then
      CONFIG_URI="hy2://$PASSWORD@[$PUBLIC_IP]$LISTEN_PORT/?insecure=1&mport=$(echo "$LISTEN_PORT" | sed 's|:||')%2C$PORT_HOPPING_RANGE&sni=$(echo "$MASQUERADE_URL" | sed 's|https://||')#hy2"
    fi
  
    echo "IPv6配置URI生成完成: ${bold}${green}$CONFIG_URI${reset}"
    echo "$CONFIG_URI" > $URI_FILE
  elif [ "$IP_VERSION" == "IPv4/IPv6" ]; then
    CONFIG_URI_IPV4="hy2://$PASSWORD@$PUBLIC_IP$LISTEN_PORT/?insecure=1&sni=$(echo "$MASQUERADE_URL" | sed 's|https://||')#hy2"
    CONFIG_URI_IPV6="hy2://$PASSWORD@[$PUBLIC_IP]$LISTEN_PORT/?insecure=1&sni=$(echo "$MASQUERADE_URL" | sed 's|https://||')#hy2"

    if [ "$PORT_HOPPING" == "2" ]; then
      CONFIG_URI_IPV4="hy2://$PASSWORD@$PUBLIC_IP$LISTEN_PORT/?insecure=1&mport=$(echo "$LISTEN_PORT" | sed 's|:||')%2C$PORT_HOPPING_RANGE&sni=$(echo "$MASQUERADE_URL" | sed 's|https://||')#hy2"
      CONFIG_URI_IPV6="hy2://$PASSWORD@[$PUBLIC_IP]$LISTEN_PORT/?insecure=1&mport=$(echo "$LISTEN_PORT" | sed 's|:||')%2C$PORT_HOPPING_RANGE&sni=$(echo "$MASQUERADE_URL" | sed 's|https://||')#hy2"
    fi
  
    echo "IPv4配置URI生成完成: ${bold}${green}$CONFIG_URI_IPV4${reset}"
    echo "IPv6配置URI生成完成: ${bold}${green}$CONFIG_URI_IPV6${reset}"
    echo "$CONFIG_URI_IPV4" > $URI_FILE
    echo "$CONFIG_URI_IPV6" >> $URI_FILE
  fi
  
  
  else
    echo "未找到Hysteria配置文件：$HYSTERIA_CONFIG_FILE"
    echo "请检查文件路径是否正确，并确保Hysteria服务已安装和配置。"
  fi
  echo "${bold}${green}如您遇到使用问题，请加入t.me/hysteria_github电报群，在中文技术交流中@B1gCarr0t${reset}"
  echo "${bold}${green}本脚本开源在https://github.com/B1gCarr0t/Hysteria2-库中欢迎审计${reset}"

elif [ "$USER_PURPOSE" == "2" ]; then

  URI_FILE="/etc/hysteria/uri.txt"
  cat "$URI_FILE"
else
  echo "无效的选择。请重新运行脚本并输入有效的选项。"
  exit 1
fi
