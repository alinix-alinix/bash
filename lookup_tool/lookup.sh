#!/bin/bash

# Файл со списком FQDN
HOSTS_FILE=$(cat hosts.txt)
# Файл для вывода результата
OUTPUT_FILE="hosts_info.csv"
# Пользователь для подключения по SSH
SSH_USER="s.stepanov"

# Заголовок таблицы
echo "fqdn;server_type;crontab;ip_addresses;cpu_cores;ram_size_GB;disk_count;disk_sizes_gb" > "$OUTPUT_FILE"

# Функция для перевода байтов в гигабайты
convert_to_gb() {
    echo "scale=2; $1 / 1024 / 1024 / 1024" | bc
}

# Функция для определения типа сервера (физический или виртуальный)
get_server_type() {
    fqdn=$1
    server_type=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$fqdn" "sudo dmidecode -s system-manufacturer" 2>/dev/null)
    if [[ $? -ne 0 || -z "$server_type" ]]; then
        echo "N/A"
    elif [[ "$server_type" =~ "VMware"|"QEMU"|"VirtualBox"|"Microsoft"|"KVM"|"Xen" ]]; then
        echo "$server_type"
    else
        echo "Physical"
    fi
}

# Функция для получения информации с удаленного хоста
get_host_info() {
    fqdn=$1
    echo "Обработка хоста: $fqdn"

    # Определяем тип сервера
    server_type=$(get_server_type "$fqdn")

    # Получаем содержимое crontab
    crontab_content=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$fqdn" 'sudo crontab -l' 2>/dev/null)
    if [[ $? -ne 0 || -z "$crontab_content" ]]; then
        crontab_content="N/A"
    else
        crontab_content=$(echo "$crontab_content" | tr '\n' ' ')
    fi

    # Получаем IP-адреса
    ip_addresses=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$fqdn" "hostname -I" 2>/dev/null)
    if [[ $? -ne 0 || -z "$ip_addresses" ]]; then
        ip_addresses="N/A"
    else
        ip_addresses=$(echo "$ip_addresses" | tr ' ' ',')
    fi

    # Получаем число ядер процессора
    cpu_cores=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$fqdn" "sudo nproc" 2>/dev/null)
    if [[ $? -ne 0 || -z "$cpu_cores" ]]; then
        cpu_cores="N/A"
    fi

    # Получаем объем ОЗУ (в ГБ)
    ram_size_bytes=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$fqdn" "sudo free -b | awk '/Mem:/ {print \$2}'" 2>/dev/null)
    if [[ $? -ne 0 || -z "$ram_size_bytes" ]]; then
        ram_size_gb="N/A"
    else
        ram_size_gb=$(convert_to_gb "$ram_size_bytes")
    fi

    # Получаем информацию о физических дисках типа sda, sdb и nvme
    disk_info=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$fqdn" "sudo lsblk -b -o SIZE,NAME,TYPE -d | grep -E 'sd|nvme'" 2>/dev/null)
    if [[ $? -ne 0 || -z "$disk_info" ]]; then
        disk_count="N/A"
        disk_sizes_gb="N/A"
    else
        disk_count=$(echo "$disk_info" | wc -l)
        disk_sizes_gb=$(echo "$disk_info" | awk '{print $1}' | while read -r size; do convert_to_gb "$size"; done | tr '\n' ',' | sed 's/,$//')
    fi

    # Записываем информацию в файл
    echo "$fqdn;$server_type;$crontab_content;$ip_addresses;$cpu_cores;$ram_size_gb;$disk_count;$disk_sizes_gb" >> "$OUTPUT_FILE"
}

# Чтение списка хостов и обработка каждого
for host in $HOSTS_FILE; do
    get_host_info "$host"
done

echo "Информация о хостах сохранена в $OUTPUT_FILE"
