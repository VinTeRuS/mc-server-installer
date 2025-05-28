#!/bin/bash
check_dependencies() {
    local missing_deps=0
    local deps=("curl" "jq" "java" "screen" "tar" "grep" "sed" "awk" "cut")
    display_info "Проверка зависимостей..."
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            display_error "Команда '$cmd' не найдена. Пожалуйста, установите ее."
            if [ "$cmd" == "java" ]; then display_error "Например, для Termux: pkg install openjdk-21";
            elif [[ "$cmd" == "grep" || "$cmd" == "sed" || "$cmd" == "awk" || "$cmd" == "cut" ]]; then display_error "Это базовая утилита. Если она отсутствует, ваша система может быть неполной.";
            else display_error "Например, для Termux: pkg install $cmd"; fi
            missing_deps=1
        else
            display_info "'$cmd' найдена."
            if [ "$cmd" == "java" ]; then local java_version; java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}'); display_info "Установленная версия Java: $java_version (Рекомендуется Java 17+)"; fi
        fi
    done
    if ! command -v ss &>/dev/null && ! command -v netstat &>/dev/null; then
        display_error "Не найдена утилита 'ss' (iproute2) или 'netstat' (net-tools) для проверки портов."
        missing_deps=1
    else
        display_info "'ss' или 'netstat' найдена."
    fi
    if ! command -v less &>/dev/null && ! command -v tail &>/dev/null && ! command -v cat &>/dev/null; then
        display_error "Не найдены утилиты для просмотра логов ('less', 'tail', 'cat')."
        missing_deps=1
    else
        display_info "Утилиты для просмотра логов найдены."
    fi
    if [ $missing_deps -eq 1 ]; then display_error "Не все зависимости удовлетворены. Установите недостающие и попробуйте снова."; exit 1; fi
    display_info "Все основные зависимости на месте."
}
download_file() {
    local url="$1" output_path="$2" filename; filename=$(basename "$output_path")
    display_info "Загрузка $filename..."; if ! mkdir -p "$(dirname "$output_path")"; then display_error "Не удалось создать родительскую директорию для $output_path."; return 1; fi
    if curl --help 2>&1 | grep -q "progress-bar"; then curl --progress-bar -L -o "$output_path" "$url"; else curl -sSL -o "$output_path" "$url"; fi
    if [ $? -eq 0 ] && [ -s "$output_path" ]; then display_info "Файл $filename успешно загружен в $output_path."; return 0;
    else display_error "Ошибка при загрузке файла $filename."; rm -f "$output_path"; return 1; fi
}
save_server_config() {
    local name="$1" type="$2" version="$3" ram="$4" path="$5" jar="$6"
    display_info "${utils_saving_server_config:-Сохранение конфигурации сервера...}"
    if [ -z "$name" ]||[ -z "$type" ]||[ -z "$version" ]||[ -z "$path" ]||[ -z "$jar" ]; then display_error "Ошибка: Одно из значений для сохранения пустое."; return 1; fi
    local new_server_json; new_server_json=$(jq -n --arg name "$name" --arg type "$type" --arg version "$version" --arg ram "$ram" --arg path "$path" --arg jarFile "$jar" '{name: $name, type: $type, version: $version, ram: $ram, path: $path, jarFile: $jarFile, installed_at: (now | todate)}')
    if [ -z "$new_server_json" ]; then display_error "Ошибка: не удалось создать JSON-объект (jq)."; return 1; fi
    local temp_config_file="$SERVERS_CONFIG_FILE.tmp"
    if [ ! -f "$SERVERS_CONFIG_FILE" ]||! jq -e . "$SERVERS_CONFIG_FILE" >/dev/null 2>&1; then display_warning "Файл $SERVERS_CONFIG_FILE не найден/поврежден. Создание нового."; echo "[]" > "$SERVERS_CONFIG_FILE"; fi
    if jq ". += [$new_server_json]" "$SERVERS_CONFIG_FILE" > "$temp_config_file"; then
        if [ -s "$temp_config_file" ]&&jq -e . "$temp_config_file" >/dev/null 2>&1; then mv "$temp_config_file" "$SERVERS_CONFIG_FILE"; display_info "${utils_server_config_saved:-Конфигурация сохранена.}"; return 0;
        else display_error "Ошибка: Временный файл '$temp_config_file' пуст/невалиден."; rm -f "$temp_config_file"; return 1; fi
    else display_error "${utils_error_saving_config:-Ошибка записи в $SERVERS_CONFIG_FILE (jq).}"; rm -f "$temp_config_file"; return 1; fi
}
is_server_running() {
    local screen_session_name="$1"; if screen -list | grep -q -w "$screen_session_name"; then return 0; else return 1; fi
}
stop_minecraft_server() {
    local server_display_name="$1" screen_session_name="$2" skip_confirmation="${3:-false}"
    if [[ "$skip_confirmation" != "true" ]]; then
        local stop_confirm_msg=$(printf "${manage_server_stop_confirm:-Остановить %s? (y/N): }" "$server_display_name")
        read_input "$stop_confirm_msg" confirm_stop
        if [[ ! "$confirm_stop" =~ ^[YyДд]$ ]]; then display_info "$(printf "${manage_server_stop_cancelled:-Остановка %s отменена.}" "$server_display_name")"; return 1; fi
    fi
    display_info "$(printf "${manage_server_stopping_attempt:-Остановка %s (сессия %s)...}" "$server_display_name" "$screen_session_name")"
    if ! is_server_running "$screen_session_name"; then display_info "$(printf "${manage_server_stop_no_session:-Сессия %s не найдена/сервер остановлен.}" "$screen_session_name")"; return 0; fi
    if ! screen -S "$screen_session_name" -X stuff "stop\n"; then display_error "$(printf "${manage_server_stop_failed_to_send:-Не удалось отправить stop в %s.}" "$screen_session_name")"; return 1; fi
    local total_wait_time=30 check_interval=3 waited_time=0 stopped_successfully=false
    local polling_msg=$(printf "${manage_server_stop_polling:-Команда stop отправлена в %s. Ожидание до %d сек (проверка каждые %d сек):}" "$screen_session_name" "$total_wait_time" "$check_interval")
    display_info "$polling_msg"; display_info "$(printf "${manage_server_stopping_check_console:-Проверьте консоль (screen -r %s).}" "$screen_session_name")"; echo -n "Ожидание: "
    while [ $waited_time -lt $total_wait_time ]; do
        if ! is_server_running "$screen_session_name"; then stopped_successfully=true; break; fi
        sleep $check_interval; waited_time=$((waited_time + check_interval)); echo -n "."; done; echo
    if $stopped_successfully; then display_info "$(printf "${manage_server_stopped_successfully_polling:-Сервер (сессия %s) остановлен.}" "$screen_session_name")"; return 0;
    else display_warning "$(printf "${manage_server_stop_still_running_polling:-Сервер (сессия %s) еще запущен после %d сек. (screen -r %s).}" "$screen_session_name" "$total_wait_time" "$screen_session_name")"; return 1; fi
}
delete_minecraft_server() {
    local server_display_name="$1" server_path="$2" screen_session_name="$3"
    local delete_confirm_msg=$(printf "${manage_server_delete_confirm:-Удалить %s и все файлы? НЕОБРАТИМО. Введите ДА: }" "$server_display_name")
    read_input "$delete_confirm_msg" confirm_delete
    if [[ "$confirm_delete" != "ДА" && "$confirm_delete" != "YES" ]]; then display_info "$(printf "${manage_server_delete_cancelled:-Удаление %s отменено.}" "$server_display_name")"; return 1; fi
    display_info "$(printf "${manage_server_deleting:-Удаление %s...}" "$server_display_name")"
    if is_server_running "$screen_session_name"; then
        display_info "$(printf "${manage_server_stopping_before_delete:-Сервер '%s' запущен. Остановка перед удалением...}" "$server_display_name")"
        if ! stop_minecraft_server "$server_display_name" "$screen_session_name" "true"; then display_warning "Продолжение удаления, сервер мог не остановиться."; else display_info "Сервер остановлен перед удалением."; fi
    fi
    if [ -d "$server_path" ]; then if rm -rf "$server_path"; then display_info "Директория $server_path удалена."; else display_error "$(printf "${manage_server_delete_failed_rm:-Не удалось удалить %s.}" "$server_path")"; fi
    else display_warning "Директория $server_path не найдена."; fi
    local temp_config_file="$SERVERS_CONFIG_FILE.tmp"
    if jq --arg name_to_delete "$server_display_name" 'map(select(.name != $name_to_delete))' "$SERVERS_CONFIG_FILE" > "$temp_config_file"; then
        if [ -s "$temp_config_file" ]&&jq -e . "$temp_config_file" >/dev/null 2>&1; then mv "$temp_config_file" "$SERVERS_CONFIG_FILE"; display_info "$(printf "${manage_server_deleted_config_removed:-Запись о %s удалена из конфига.}" "$server_display_name")";
        else display_error "Ошибка: Временный файл '$temp_config_file' после удаления пуст/невалиден."; rm -f "$temp_config_file"; fi
    else display_error "$(printf "${manage_server_delete_failed_config:-Не удалось удалить %s из конфига (jq).}" "$server_display_name")"; rm -f "$temp_config_file"; return 1; fi
    display_info "$(printf "${manage_server_deleted_success:-Сервер %s полностью удален.}" "$server_display_name")"; return 0
}
generate_server_properties() {
    local SERVER_DIR="$1" properties_file="$SERVER_DIR/server.properties"
    display_info "${server_properties_customization_title:---- Настройка server.properties ---}"
    local default_motd="A Minecraft Server by Termux Installer" default_port="25565" default_pvp="true"
    local default_max_players="20" default_online_mode="true" default_gamemode="survival" default_difficulty="normal"
    local motd server_port pvp max_players online_mode gamemode difficulty
    read_input "$(printf "${prompt_motd:-MOTD (%s): }" "$default_motd")" motd; [[ -z "$motd" ]] && motd="$default_motd"
    read_input "$(printf "${prompt_server_port:-Порт (%s): }" "$default_port")" server_port; [[ -z "$server_port" ]] && server_port="$default_port"
    if ! [[ "$server_port" =~ ^[0-9]+$ ]]||[ "$server_port" -lt 1 ]||[ "$server_port" -gt 65535 ]; then display_warning "Некорр. порт. Исп. $default_port."; server_port="$default_port"; fi
    read_input "$(printf "${prompt_pvp:-PvP (true/false, %s): }" "$default_pvp")" pvp; [[ -z "$pvp" ]] && pvp="$default_pvp"; [[ ! "$pvp" =~ ^(true|false)$ ]] && pvp="$default_pvp"
    read_input "$(printf "${prompt_max_players:-Макс.игроков (%s): }" "$default_max_players")" max_players; [[ -z "$max_players" ]] && max_players="$default_max_players"; [[ ! "$max_players" =~ ^[0-9]+$ ]] && max_players="$default_max_players"
    read_input "$(printf "${prompt_online_mode:-Online-mode (true/false, %s): }" "$default_online_mode")" online_mode; [[ -z "$online_mode" ]] && online_mode="$default_online_mode"; [[ ! "$online_mode" =~ ^(true|false)$ ]] && online_mode="$default_online_mode"
    read_input "$(printf "${prompt_gamemode:-Режим (survival/creative/..., %s): }" "$default_gamemode")" gamemode; [[ -z "$gamemode" ]] && gamemode="$default_gamemode"
    case "$gamemode" in survival|creative|adventure|spectator) ;; *) display_warning "Некорр. режим. Исп. $default_gamemode."; gamemode="$default_gamemode" ;; esac
    read_input "$(printf "${prompt_difficulty:-Сложность (peaceful/easy/..., %s): }" "$default_difficulty")" difficulty; [[ -z "$difficulty" ]] && difficulty="$default_difficulty"
    case "$difficulty" in peaceful|easy|normal|hard) ;; *) display_warning "Некорр. сложность. Исп. $default_difficulty."; difficulty="$default_difficulty" ;; esac
    display_info "${server_properties_generating:-Генерация server.properties...}"; rm -f "$properties_file"
    { echo "enable-jmx-monitoring=false"; echo "rcon.port=25575"; echo "level-seed="; echo "gamemode=$gamemode"; echo "enable-command-block=false"; echo "enable-query=false"; echo "generator-settings={}"; echo "level-name=world"; echo "motd=$motd"; echo "query.port=$server_port"; echo "pvp=$pvp"; echo "generate-structures=true"; echo "difficulty=$difficulty"; echo "network-compression-threshold=256"; echo "max-tick-time=60000"; echo "require-resource-pack=false"; echo "use-native-transport=true"; echo "max-players=$max_players"; echo "online-mode=$online_mode"; echo "enable-status=true"; echo "allow-flight=false"; echo "broadcast-rcon-to-ops=true"; echo "view-distance=10"; echo "server-ip="; echo "resource-pack-prompt="; echo "allow-nether=true"; echo "server-port=$server_port"; echo "enable-rcon=false"; echo "sync-chunk-writes=true"; echo "op-permission-level=4"; echo "prevent-proxy-connections=false"; echo "resource-pack="; echo "entity-broadcast-range-percentage=100"; echo "rcon.password="; echo "player-idle-timeout=0"; echo "force-gamemode=false"; echo "rate-limit=0"; echo "hardcore=false"; echo "white-list=false"; echo "broadcast-console-to-ops=true"; echo "spawn-npcs=true"; echo "spawn-animals=true"; echo "function-permission-level=2"; echo "level-type=minecraft:normal"; echo "text-display-chat-sync=false"; echo "spawn-monsters=true"; echo "enforce-whitelist=false"; echo "resource-pack-sha1="; echo "spawn-protection=16"; echo "max-world-size=29999984"; } > "$properties_file"
    display_info "$(printf "${server_properties_saved:-server.properties сохранен в %s.}" "$properties_file")"
}
backup_minecraft_server() {
    local server_display_name="$1" server_path="$2" screen_session_name="$3"
    if ! command -v tar &>/dev/null; then display_error "${backup_tar_not_found:-'tar' не найден. Установите: pkg install tar}"; return 1; fi
    display_header "$(printf "${backup_server_title:-Резервное копирование %s}" "$server_display_name")"
    local server_was_running=false; if is_server_running "$screen_session_name"; then server_was_running=true; local confirm_stop_backup; read_input "$(printf "${backup_confirm_stop_server:-Остановить '%s' перед бэкапом? (y/N): }" "$server_display_name")" confirm_stop_backup
        if [[ "$confirm_stop_backup" =~ ^[YyДд]$ ]]; then if ! stop_minecraft_server "$server_display_name" "$screen_session_name" "true"; then display_warning "${backup_server_not_stopped_warn:-Сервер не остановлен. Бэкап м.б. неконсистентным.}"; else display_info "Сервер остановлен для бэкапа."; fi
        else display_warning "${backup_server_not_stopped_warn:-Сервер не остановлен. Бэкап м.б. неконсистентным.}"; if screen -S "$screen_session_name" -X stuff "save-all\nsay Мир сохранен перед бэкапом.\n"; then display_info "Команды 'save-all' и 'say' отправлены."; sleep 3; else display_warning "Не удалось отправить 'save-all'."; fi; fi; fi
    local backup_dir="$server_path/backups"; mkdir -p "$backup_dir"; local timestamp; timestamp=$(date +%Y-%m-%d_%H%M%S)
    local sane_server_name="${server_display_name//[^a-zA-Z0-9_-]/_}"; local backup_filename; backup_filename=$(printf "${backup_filename_template:-backup_%s_%s.tar.gz}" "$sane_server_name" "$timestamp")
    local backup_filepath="$backup_dir/$backup_filename"; display_info "$(printf "${backup_destination:-Бэкап будет сохранен в: %s}" "$backup_filepath")"; display_info "${backup_compressing:-Архивация...}"
    local files_to_backup=(); for world_folder in world world_nether world_the_end; do if [ -d "$server_path/$world_folder" ]; then files_to_backup+=("$world_folder"); fi; done
    if [ ${#files_to_backup[@]} -eq 0 ]; then display_warning "$(printf "${backup_world_folders_not_found:-Папки мира не найдены в %s.}" "$server_path")"; fi
    for config_file in server.properties ops.json whitelist.json banned-ips.json banned-players.json usercache.json; do if [ -f "$server_path/$config_file" ]; then files_to_backup+=("$config_file"); fi; done
    if [ -d "$server_path/playerdata" ]; then files_to_backup+=("playerdata"); fi; if [ -d "$server_path/advancements" ]; then files_to_backup+=("advancements"); fi; if [ -d "$server_path/stats" ]; then files_to_backup+=("stats"); fi
    if [ ${#files_to_backup[@]} -eq 0 ]; then display_warning "Нет файлов для бэкапа."; if $server_was_running && ! is_server_running "$screen_session_name"; then display_info "Перезапуск $server_display_name..."; (cd "$server_path" && screen -dmS "$screen_session_name" ./start.sh); fi; return 1; fi
    if tar -czvf "$backup_filepath" -C "$server_path" "${files_to_backup[@]}"; then display_info "$(printf "${backup_successful:-Бэкап %s создан.}" "$backup_filename")";
    else display_error "$(printf "${backup_failed:-Не удалось создать бэкап для %s.}" "$server_display_name")"; rm -f "$backup_filepath"; if $server_was_running && ! is_server_running "$screen_session_name"; then display_info "Перезапуск $server_display_name..."; (cd "$server_path" && screen -dmS "$screen_session_name" ./start.sh); fi; return 1; fi
    if $server_was_running && ! is_server_running "$screen_session_name"; then display_info "Завершение бэкапа. Перезапуск $server_display_name..."; (cd "$server_path" && screen -dmS "$screen_session_name" ./start.sh); sleep 1; if is_server_running "$screen_session_name"; then display_info "$server_display_name перезапущен."; else display_warning "Не удалось перезапустить $server_display_name."; fi; fi; return 0
}
