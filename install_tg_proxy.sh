#!/usr/bin/env bash

# Telegram MTProto WS Proxy - Proxmox LXC Installer
# Source: https://github.com/solohaims/proxmox-tg-proxy
# Version: 2.1 (Russian localization & Arrow-keys)

set -eE
trap 'error_handler $LINENO' ERR

# --- Цвета и UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

header_info() {
  clear
  printf "${BLUE}############################################################${NC}\n"
  printf "${BLUE}#${NC}  ${YELLOW}Установщик Telegram MTProto WS Proxy v2.1${NC}           ${BLUE}#${NC}\n"
  printf "${BLUE}############################################################${NC}\n"
}

error_handler() {
  printf "\n${RED}Ошибка на строке $1. Установка прервана.${NC}\n"
  exit 1
}

# --- Компонент меню (Стрелки) ---
# Использование: select_option "Подсказка" "Опция1" "Опция2" ...
select_option() {
  local prompt="$1"
  shift
  local options=("$@")
  local cur=0
  local count=${#options[@]}
  local key=""

  printf "${YELLOW}$prompt (Стрелки для выбора, Enter для подтверждения):${NC}\n"

  # Скрыть курсор
  tput civis
  while true; do
    for i in "${!options[@]}"; do
      if [ "$i" -eq "$cur" ]; then
        printf "  ${GREEN}> ${options[$i]}${NC}\n"
      else
        printf "    ${options[$i]}\n"
      fi
    done

    # Чтение клавиши с /dev/tty для поддержки pipe (curl | bash)
    read -rsn3 key < /dev/tty
    if [[ "$key" == $'\x1b[A' ]]; then # Вверх
      cur=$(( (cur - 1 + count) % count ))
    elif [[ "$key" == $'\x1b[B' ]]; then # Вниз
      cur=$(( (cur + 1) % count ))
    elif [[ "$key" == "" ]]; then # Enter
      break
    fi
    # Вернуть курсор вверх
    printf "\033[${count}A"
  done
  # Показать курсор
  tput cnorm
  MENU_INDEX=$cur
}

# --- Проверка окружения ---
if [ ! -d /etc/pve ]; then
    printf "${RED}Ошибка: Этот скрипт должен быть запущен на хосте Proxmox VE!${NC}\n"
    exit 1
fi

header_info

# --- Конфигурация ---
NEXTID=$(pvesh get /cluster/nextid)
printf "${YELLOW}Введите ID контейнера [По умолчанию: $NEXTID] (Enter для пропуска): ${NC}"
read -r CTID < /dev/tty
CTID=${CTID:-$NEXTID}

printf "${YELLOW}Введите имя хоста [По умолчанию: tg-proxy] (Enter для пропуска): ${NC}"
read -r HOSTNAME < /dev/tty
HOSTNAME=${HOSTNAME:-tg-proxy}

# Выбор хранилища
STORES=($(pvesm status -content rootdir | awk 'NR>1 {print $1}'))
select_option "Выберите хранилище для LXC" "${STORES[@]}"
STORAGE=${STORES[$MENU_INDEX]}

# Подтверждение ресурсов
select_option "Выберите ресурсы" "Стандарт (1 CPU, 512MB RAM)" "Эконом (1 CPU, 256MB RAM)" "Производительный (2 CPU, 1GB RAM)"
case $MENU_INDEX in
  0) CORES=1; MEM=512 ;;
  1) CORES=1; MEM=256 ;;
  2) CORES=2; MEM=1024 ;;
esac

GEN_SECRET=$(openssl rand -hex 16)
printf "${YELLOW}Секрет прокси [По умолчанию: $GEN_SECRET] (Enter для пропуска): ${NC}"
read -r SECRET < /dev/tty
SECRET=${SECRET:-$GEN_SECRET}

printf "${YELLOW}Домен Cloudflare Worker (опционально, например proxy.me.workers.dev): ${NC}"
read -r WORKER < /dev/tty

# --- Выполнение ---
ROOT_PASS=$(openssl rand -base64 12)
TEMPLATE_NAME="debian-12-standard_12.2-1_amd64.tar.zst"

# Поиск хранилища для шаблонов
TEMP_STORE=$(pvesm status -content vztmpl | awk 'NR>1 {print $1}' | head -n 1)
if [ -z "$TEMP_STORE" ]; then
    printf "${RED}Хранилище с типом 'Container template' не найдено!${NC}\n"
    exit 1
fi

TEMPLATE_PATH=$(pvesm path "$TEMP_STORE:vztmpl/$TEMPLATE_NAME" 2>/dev/null || echo "")

if [ ! -f "$TEMPLATE_PATH" ]; then
    printf "${BLUE}Загрузка шаблона Debian 12 в хранилище '$TEMP_STORE'...${NC}\n"
    pveam update
    pveam download "$TEMP_STORE" "$TEMPLATE_NAME"
fi

printf "\n${GREEN}Создание непривилегированного LXC контейнера $CTID...${NC}\n"
pct create "$CTID" "$TEMP_STORE:vztmpl/$TEMPLATE_NAME" \
    --hostname "$HOSTNAME" \
    --storage "$STORAGE" \
    --password "$ROOT_PASS" \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --cores "$CORES" \
    --memory "$MEM" \
    --swap 512 \
    --unprivileged 1 \
    --features nesting=1 \
    --start 1

# --- Ожидание готовности ---
printf "${BLUE}Ожидание сети в контейнере...${NC}"
until pct exec "$CTID" -- ping -c 1 -W 1 google.com &>/dev/null; do
    printf "."
    sleep 2
done
printf " OK\n"

# --- Внутренняя настройка ---
printf "${GREEN}Установка зависимостей и tg-ws-proxy...${NC}\n"
pct exec "$CTID" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-venv python3-pip git build-essential libffi-dev libssl-dev tini curl
    useradd -r -m -s /bin/bash tgproxy || true
    rm -rf /opt/tg-ws-proxy
    git clone https://github.com/Flowseal/tg-ws-proxy.git /opt/tg-ws-proxy
    cd /opt/tg-ws-proxy
    python3 -m venv venv
    ./venv/bin/pip install --upgrade pip
    ./venv/bin/pip install cryptography==46.0.5
    chown -R tgproxy:tgproxy /opt/tg-ws-proxy
"

# Создание сервиса
CF_ARG=""
if [ -n "$WORKER" ]; then
    CF_ARG="--cfproxy-worker-domain $WORKER"
fi

pct exec "$CTID" -- bash -c "cat <<EOF > /etc/systemd/system/tg-proxy.service
[Unit]
Description=Telegram MTProto WS Proxy
After=network.target

[Service]
Type=simple
User=tgproxy
WorkingDirectory=/opt/tg-ws-proxy
ExecStart=/opt/tg-ws-proxy/venv/bin/python3 -u proxy/tg_ws_proxy.py --host 0.0.0.0 --port 1443 --secret $SECRET $CF_ARG --dc-ip 2:149.154.167.220 --dc-ip 4:149.154.167.220
Restart=always
# Защита системы
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
"

pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl enable tg-proxy
pct exec "$CTID" -- systemctl start tg-proxy

# Получение IP
IP=$(pct exec "$CTID" -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)

# --- Итоги ---
header_info
printf "${GREEN}УСПЕХ! Telegram прокси запущен.${NC}\n"
printf "------------------------------------------------------------\n"
printf "ID контейнера: $CTID | Пароль root: $ROOT_PASS\n"
printf "IP: $IP | Секрет: dd$SECRET\n"
printf "------------------------------------------------------------\n"
printf "${YELLOW}Ссылка для Telegram (Прямая):${NC}\n"
printf "tg://proxy?server=$IP&port=1443&secret=dd$SECRET\n"
printf "------------------------------------------------------------\n"

if [ -n "$WORKER" ]; then
    printf "${BLUE}Ссылка Stealth (через Cloudflare):${NC}\n"
    printf "tg://proxy?server=$WORKER&port=443&secret=dd$SECRET\n"
    printf "------------------------------------------------------------\n"
fi
printf "${BLUE}Подсказка: используйте 'pct enter $CTID' для управления контейнером.${NC}\n"
