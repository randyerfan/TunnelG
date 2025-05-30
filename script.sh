#!/bin/bash

set -e

# رنگ‌ها برای خروجی زیباتر
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # بدون رنگ

# بررسی دسترسی ریشه
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}لطفاً اسکریپت را با دسترسی ریشه اجرا کنید.${NC}"
  exit 1
fi

# نصب پیش‌نیازها
install_dependencies() {
  echo -e "${GREEN}در حال نصب پیش‌نیازها...${NC}"
  apt update
  apt install -y curl jq tar
}

# دانلود و نصب Hysteria 2
install_hysteria() {
  echo -e "${GREEN}در حال دانلود Hysteria 2...${NC}"
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo -e "${RED}معماری پشتیبانی نمی‌شود: $ARCH${NC}"; exit 1 ;;
  esac

  LATEST_URL=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | \
    jq -r ".assets[] | select(.name | test(\"hysteria-linux-$ARCH.*.tar.gz\")) | .browser_download_url")

  if [ -z "$LATEST_URL" ]; then
    echo -e "${RED}عدم توانایی در دریافت لینک دانلود.${NC}"
    exit 1
  fi

  curl -L "$LATEST_URL" -o hysteria.tar.gz
  tar -xzf hysteria.tar.gz
  mv hysteria /usr/local/bin/hysteria
  chmod +x /usr/local/bin/hysteria
  rm -f hysteria.tar.gz
  echo -e "${GREEN}Hysteria 2 با موفقیت نصب شد.${NC}"
}

# دریافت ورودی‌ها از کاربر
get_user_input() {
  read -p "نام دامنه Reality را وارد کنید (مثال: example.com): " DOMAIN
  read -p "پورت Reality را وارد کنید (پیش‌فرض: 443): " REALITY_PORT
  REALITY_PORT=${REALITY_PORT:-443}
  read -p "رمز عبور برای احراز هویت را وارد کنید: " PASSWORD
  read -p "پورت مورد نظر برای Hysteria را وارد کنید (مثال: 5678): " HYSTERIA_PORT
}

# ایجاد فایل پیکربندی
create_config() {
  mkdir -p /etc/hysteria
  cat > /etc/hysteria/config.yaml <<EOF
listen: :$HYSTERIA_PORT
obfs:
  type: reality
  reality:
    server: $DOMAIN:$REALITY_PORT
    public_key: "کلید عمومی را اینجا وارد کنید"
auth:
  type: password
  password: "$PASSWORD"
EOF
  echo -e "${GREEN}فایل پیکربندی ایجاد شد در /etc/hysteria/config.yaml${NC}"
}

# ایجاد سرویس systemd
create_service() {
  cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable hysteria
  systemctl start hysteria
  echo -e "${GREEN}سرویس Hysteria فعال و راه‌اندازی شد.${NC}"
}

# منوی اصلی
main_menu() {
  echo -e "${GREEN}نصب سرور Hysteria 2 به سبک TAQ-BOSTAN${NC}"
  echo "1) نصب"
  echo "2) حذف"
  echo "3) خروج"
  read -p "انتخاب کنید [1-3]: " CHOICE
  case "$CHOICE" in
    1)
      install_dependencies
      install_hysteria
      get_user_input
      create_config
      create_service
      ;;
    2)
      systemctl stop hysteria
      systemctl disable hysteria
      rm -f /usr/local/bin/hysteria
      rm -rf /etc/hysteria
      rm -f /etc/systemd/system/hysteria.service
      systemctl daemon-reload
      echo -e "${GREEN}Hysteria با موفقیت حذف شد.${NC}"
      ;;
    3)
      echo "خروج..."
      exit 0
      ;;
    *)
      echo -e "${RED}انتخاب نامعتبر.${NC}"
      ;;
  esac
}

main_menu
