#!/bin/bash
# نام فایل: setup_hysteria_tunnel.sh
# این اسکریپت تونل Hysteria با حالت reality را بین سرور ایرانی و سرور خارجی راه‌اندازی می‌کند.
# قابلیت‌های این اسکریپت شامل:
#   - تولید خودکار کلیدهای خصوصی و عمومی با استفاده از wg (wireguard-tools)
#   - دانلود باینری hysteria مطابق با معماری سیستم (x86_64 یا arm64)
#   - دریافت پورت گوش شن (مثلاً 443) و همچنین دریافت پورت تونل (مثلاً 43070)
#     در حالت سرور؛ در صورت وارد کردن پورت تونل متفاوت، می‌توان به‌صورت خودکار قانون iptables برای هدایت ترافیک اضافه کرد.
#   - قابلیت uninstall جهت حذف باینری hysteria، فایل‌های پیکربندی و سرویس systemd (در صورت وجود)
#
# لطفاً اسکریپت را با دسترسی root اجرا کنید.

# بررسی اجرا با دسترسی root
if [ "$EUID" -ne 0 ]; then
    echo "لطفاً اسکریپت را با دسترسی ریشه (root) اجرا کنید."
    exit 1
fi

# بررسی ورودی کاربر (server, client یا uninstall)
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 {server|client|uninstall}"
    exit 1
fi

MODE="$1"

# تابع دانلود باینری hysteria با بررسی معماری سیستم
download_hysteria() {
    if command -v hysteria >/dev/null 2>&1; then
        echo "باینری hysteria قبلاً نصب شده است."
    else
        ARCH=$(uname -m)
        echo "شناسایی معماری سیستم: $ARCH"
        if [ "$ARCH" == "x86_64" ]; then
            BIN_URL="https://github.com/apernet/hysteria/releases/download/v2.0.0/hysteria-linux-amd64"
        elif [ "$ARCH" == "aarch64" ] || [ "$ARCH" == "arm64" ]; then
            BIN_URL="https://github.com/apernet/hysteria/releases/download/v2.0.0/hysteria-linux-arm64"
        else
            echo "معماری سیستم شما ($ARCH) پشتیبانی نمی‌شود."
            exit 1
        fi
        echo "دانلود باینری hysteria از $BIN_URL..."
        wget -O /usr/local/bin/hysteria "$BIN_URL"
        chmod +x /usr/local/bin/hysteria
    fi
}

# تابع تولید کلید با استفاده از wg (wireguard-tools)
generate_keys() {
    if ! command -v wg >/dev/null 2>&1; then
        echo "ابزار wg (wireguard-tools) نصب نشده است. لطفاً آن را نصب کنید."
        exit 1
    fi
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
}

if [ "$MODE" == "server" ]; then
    echo "تنظیم سرور Hysteria..."

    # دریافت پورت گوش شن
    read -rp "پورت گوش شن (مثلاً 443): " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-443}
    
    # دریافت پورت تونل (برای نمونه کارهایی مانند استفاده از x‑ui)
    read -rp "پورت تونل (مثلاً 43070، در صورت خالی گذاشتن از پورت گوش شن استفاده خواهد شد): " TUNNEL_PORT
    if [ -z "$TUNNEL_PORT" ]; then
        TUNNEL_PORT="$LISTEN_PORT"
    fi

    # دریافت سایر تنظیمات سرور
    read -rp "مقدار PSK برای fallback (یک رشته دلخواه): " FALLBACK_PSK
    read -rp "دامنه سرور برای حالت reality (مثلاً example.com): " REALITY_DOMAIN

    # تولید کلیدهای سرور
    echo "تولید کلیدهای سرور..."
    generate_keys
    SERVER_PRIVATE_KEY="$PRIVATE_KEY"
    SERVER_PUBLIC_KEY="$PUBLIC_KEY"

    # نمایش کلیدهای تولید شده به‌گونه‌ای که کاربر بتواند آن‌ها را کپی کند
    echo "================ کلیدهای تولید شده سرور ================"
    echo "کلید خصوصی سرور: $SERVER_PRIVATE_KEY"
    echo "کلید عمومی سرور: $SERVER_PUBLIC_KEY"
    echo "=========================================================="
    echo "لطفاً این کلیدها را با دقت ذخیره کنید؛ به آن‌ها برای تنظیم کلاینت نیاز خواهید داشت."

    # ایجاد فایل پیکربندی سرور (هیس‌تریا همیشه به پورت گوش شن در listen متصل است)
    CONFIG_FILE="/etc/hysteria_server.yml"
    cat <<EOF > "$CONFIG_FILE"
# تنظیمات سرور Hysteria با حالت reality
listen: "0.0.0.0:$LISTEN_PORT"
protocol: "reality"
fallback: "$FALLBACK_PSK"
reality:
  server_name: "$REALITY_DOMAIN"
  public_key: "$SERVER_PUBLIC_KEY"
  private_key: "$SERVER_PRIVATE_KEY"
EOF

    echo "فایل پیکربندی سرور در ${CONFIG_FILE} ایجاد شد."

    download_hysteria

    # در صورتی که پورت تونل متفاوت از پورت گوش شن باشد، از کاربر در مورد افزودن قانون iptables پرسیده می‌شود
    if [ "$TUNNEL_PORT" != "$LISTEN_PORT" ]; then
        echo "شما پورت تونل را ($TUNNEL_PORT) غیر از پورت گوش شن ($LISTEN_PORT) وارد کرده‌اید."
        read -rp "آیا می‌خواهید قانون iptables برای هدایت ترافیک از پورت $TUNNEL_PORT به $LISTEN_PORT اضافه شود؟ [y/n]: " iptables_conf
        if [ "$iptables_conf" == "y" ] || [ "$iptables_conf" == "Y" ]; then
            # اعمال قوانین برای TCP و UDP (اگر نیاز به پروتکل خاصی دارید، تنظیم کنید)
            iptables -t nat -A PREROUTING -p tcp --dport "$TUNNEL_PORT" -j REDIRECT --to-ports "$LISTEN_PORT"
            iptables -t nat -A PREROUTING -p udp --dport "$TUNNEL_PORT" -j REDIRECT --to-ports "$LISTEN_PORT"
            echo "قوانین iptables اعمال شدند. (برای بازیابی، در صورت نیاز، این قوانین را به صورت دستی حذف نمایید.)"
        else
            echo "قوانین iptables اعمال نخواهد شد. لازم است مطمئن شوید که پورت $TUNNEL_PORT به $LISTEN_PORT هدایت شود."
        fi
    fi

    echo "راه‌اندازی سرور hysteria..."
    hysteria -config "$CONFIG_FILE" server

elif [ "$MODE" == "client" ]; then
    echo "تنظیم کلاینت Hysteria..."

    # دریافت اطلاعات لازم از کاربر جهت تنظیم کلاینت
    read -rp "آدرس سرور خارجی (به فرم دامنه:پورت، مثلاً example.com:443 یا example.com:43070): " SERVER_ADDRESS
    read -rp "مقدار PSK برای fallback (یک رشته دلخواه): " FALLBACK_PSK
    read -rp "دامنه سرور برای حالت reality (همان دامنه تنظیم شده در سرور): " REALITY_DOMAIN
    read -rp "کلید عمومی (Public Key) سرور برای reality: " REALITY_PUBLIC_KEY

    # تولید کلید کلاینت
    echo "تولید کلید کلاینت..."
    generate_keys
    CLIENT_PRIVATE_KEY="$PRIVATE_KEY"
    CLIENT_PUBLIC_KEY="$PUBLIC_KEY"
    
    # نمایش کلیدهای تولید شده کلاینت
    echo "================ کلیدهای تولید شده کلاینت ================"
    echo "کلید خصوصی کلاینت: $CLIENT_PRIVATE_KEY"
    echo "کلید عمومی کلاینت: $CLIENT_PUBLIC_KEY"
    echo "=========================================================="
    echo "شما در صورت نیاز می‌توانید کلید عمومی را ثبت نمایید."

    # ایجاد فایل پیکربندی کلاینت
    CONFIG_FILE="/etc/hysteria_client.yml"
    cat <<EOF > "$CONFIG_FILE"
# تنظیمات کلاینت Hysteria با حالت reality
server: "$SERVER_ADDRESS"
protocol: "reality"
fallback: "$FALLBACK_PSK"
reality:
  server_name: "$REALITY_DOMAIN"
  public_key: "$REALITY_PUBLIC_KEY"
  private_key: "$CLIENT_PRIVATE_KEY"
EOF

    echo "فایل پیکربندی کلاینت در ${CONFIG_FILE} ایجاد شد."
    download_hysteria
    echo "راه‌اندازی کلاینت hysteria..."
    hysteria -config "$CONFIG_FILE" client

elif [ "$MODE" == "uninstall" ]; then
    echo "حذف کامل hysteria و فایل‌های مرتبط در حال انجام است..."
    
    # توقف اجرای فرآیندهای hysteria
    pkill hysteria && echo "روندهای hysteria متوقف شدند." || echo "هیچ فرآیند active یافت نشد."

    # حذف باینری hysteria
    if [ -f /usr/local/bin/hysteria ]; then
        rm /usr/local/bin/hysteria && echo "باینری hysteria حذف شد."
    else
        echo "باینری hysteria پیدا نشد."
    fi

    # حذف فایل‌های پیکربندی
    if [ -f /etc/hysteria_server.yml ]; then
        rm /etc/hysteria_server.yml && echo "فایل پیکربندی سرور حذف شد."
    fi
    if [ -f /etc/hysteria_client.yml ]; then
        rm /etc/hysteria_client.yml && echo "فایل پیکربندی کلاینت حذف شد."
    fi

    # حذف فایل سرویس systemd در صورت وجود
    if [ -f /etc/systemd/system/hysteria.service ]; then
        systemctl stop hysteria.service
        systemctl disable hysteria.service
        rm /etc/systemd/system/hysteria.service
        systemctl daemon-reload
        echo "سرویس systemd hysteria حذف شد."
    fi

    echo "حذف hysteria به پایان رسید."
    exit 0

else
    echo "مدل نامعتبر. لطفاً از گزینه‌های 'server', 'client' یا 'uninstall' استفاده کنید."
    exit 1
fi
