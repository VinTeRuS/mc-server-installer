#!/bin/bash
install_purpur_server() {
    display_header "${purpur_installer_title:-Установка Purpur сервера}"
    local server_name
    while true; do
        read_input "${purpur_prompt_server_name:-Имя Purpur сервера: }" server_name
        if [[ -z "$server_name" ]]; then display_error "Имя не м.б. пустым."; continue; fi
        server_name=$(echo "$server_name"|sed 's/[^a-zA-Z0-9_-]/_/g'); if [[ -z "$server_name" ]]; then display_error "Имя стало пустым после очистки."; continue; fi
        if [[ -d "$SERVERS_BASE_DIR/$server_name" ]]; then display_error "$(printf "${server_dir_exists:-Директория %s уже есть.}" "$SERVERS_BASE_DIR/$server_name")"; else break; fi
    done
    if [ -z "$SERVERS_BASE_DIR" ]; then display_error "КРИТ: SERVERS_BASE_DIR не определена."; return 1; fi
    local SERVER_DIR="$SERVERS_BASE_DIR/$server_name"
    display_info "${purpur_fetching_versions:-Получение версий Purpur...}"
    local versions_json; versions_json=$(curl -sSL "https://api.purpurmc.org/v2/purpur")
    if [ $? -ne 0 ]||! echo "$versions_json"|jq -e . >/dev/null 2>&1; then display_error "Не удалось получить/обработать версии Purpur."; return 1; fi
    local latest_purpur_mc_version; latest_purpur_mc_version=$(echo "$versions_json"|jq -r '.versions[-1]')
    if [ -z "$latest_purpur_mc_version" ]||[ "$latest_purpur_mc_version" == "null" ]; then display_error "Не удалось извлечь последнюю версию MC для Purpur."; return 1; fi
    display_info "$(printf "${purpur_latest_version:-Последняя версия MC для Purpur: %s}" "$latest_purpur_mc_version")"
    local mc_version; local use_latest_prompt_formatted=$(printf "${purpur_use_latest_prompt:-Исп. MC %s для Purpur? (y/N): }" "$latest_purpur_mc_version")
    read_input "$use_latest_prompt_formatted" use_latest
    if [[ "$use_latest" =~ ^[Nn]$ ]]; then
        local purpur_versions_list=$(echo "$versions_json"|jq -r '.versions[]'|tr '\n' ' ')
        display_info "Доступные MC версии: ${purpur_versions_list}"
        read_input "${purpur_prompt_mc_version:-Введите версию MC для Purpur: }" mc_version
        if [ -z "$mc_version" ]; then display_error "Версия не введена."; return 1; fi
        if ! echo "$versions_json"|jq -e --arg ver "$mc_version" '.versions[]|select(.==$ver)'>/dev/null; then display_error "$(printf "${purpur_error_mc_version_not_found:-Версия MC '%s' не найдена для Purpur.}" "$mc_version")"; return 1; fi
    else
        mc_version="$latest_purpur_mc_version"
    fi
    display_info "Выбрана MC версия: $mc_version"
    local fetch_builds_msg=$(printf "${purpur_fetching_builds:-Получение билдов Purpur для MC %s...}" "$mc_version")
    display_info "$fetch_builds_msg"; local build_info_json; build_info_json=$(curl -sSL "https://api.purpurmc.org/v2/purpur/${mc_version}/latest")
    if [ $? -ne 0 ]||! echo "$build_info_json"|jq -e . >/dev/null 2>&1; then display_error "Не удалось получить/обработать инфо о билде Purpur для $mc_version."; return 1; fi
    local latest_build_id; latest_build_id=$(echo "$build_info_json"|jq -r '.build')
    local jar_filename; jar_filename=$(echo "$build_info_json"|jq -r '.jar')
    if [ -z "$latest_build_id" ] || [ "$latest_build_id" == "null" ] || [ -z "$jar_filename" ] || [ "$jar_filename" == "null" ]; then
        display_error "$(printf "${purpur_error_no_builds:-Не найден билд Purpur для MC %s.}" "$mc_version")"; return 1;
    fi
    display_info "$(printf "${purpur_latest_build:-Последний билд Purpur для %s: %s (%s)}" "$mc_version" "$latest_build_id" "$jar_filename")"
    local download_url="https://api.purpurmc.org/v2/purpur/${mc_version}/${latest_build_id}/download"
    display_info "${paper_download_url:-URL: } $download_url"
    local ram_alloc_prompt ram_alloc; ram_alloc_prompt=$(printf "${purpur_prompt_ram:-RAM (по умолчанию %s): }" "$DEFAULT_RAM_SUGGESTION"); read_input "$ram_alloc_prompt" ram_alloc; [[ -z "$ram_alloc" ]] && ram_alloc="$DEFAULT_RAM_SUGGESTION"; display_info "RAM: $ram_alloc."
    display_info "$(printf "${paper_creating_dir:-Создание директории %s...}" "$SERVER_DIR")"; if ! mkdir -p "$SERVER_DIR"; then display_error "Не удалось создать $SERVER_DIR."; return 1; fi
    if [ ! -d "$SERVER_DIR" ]; then display_error "КРИТ: Директория $SERVER_DIR не создана."; return 1; fi
    display_info "$(printf "${purpur_downloading_jar:-Загрузка %s...}" "$jar_filename")"
    if ! download_file "$download_url" "$SERVER_DIR/$jar_filename"; then display_error "Загрузка Purpur JAR не удалась."; rm -rf "$SERVER_DIR"; return 1; fi
    generate_server_properties "$SERVER_DIR"
    display_info "${paper_creating_eula:-Создание eula.txt...}"; echo "eula=true" > "$SERVER_DIR/eula.txt"
    display_info "${paper_creating_start_script:-Создание start.sh...}"
    cat > "$SERVER_DIR/start.sh" <<EOL
#!/bin/bash
cd "\$(dirname "\$0")"
XMS_RAM="${ram_alloc}"
XMX_RAM="${ram_alloc}"
SERVER_JAR="${jar_filename}"
ADDITIONAL_JVM_ARGS=""
if [ -f .env ]; then
  source .env
fi
java "-Xms\${XMS_RAM}" "-Xmx\${XMX_RAM}" \${ADDITIONAL_JVM_ARGS} -jar "\${SERVER_JAR}" nogui
EOL
    if [ ! -f "$SERVER_DIR/start.sh" ]; then display_error "Не создан start.sh в $SERVER_DIR"; return 1; fi
    chmod +x "$SERVER_DIR/start.sh"
    read_input "${prompt_create_env_file:-Создать .env для кастомных JVM аргументов? (y/N): }" create_env
    if [[ "$create_env" =~ ^[YyДд]$ ]]; then
        cat > "$SERVER_DIR/.env" <<EOL
ADDITIONAL_JVM_ARGS=""
EOL
        display_info "${env_file_created_message:-.env файл создан.}"
    else
        display_info "${env_file_not_created_message:-.env файл не будет создан.}"
    fi
    local server_dir_abs_path; if [ -d "$SERVER_DIR" ]; then server_dir_abs_path=$(cd "$SERVER_DIR" && pwd); else display_error "$SERVER_DIR не найдена для abs пути."; return 1; fi
    if [ -z "$server_dir_abs_path" ]; then display_error "Не удалось получить abs путь для $SERVER_DIR."; return 1; fi
    if save_server_config "$server_name" "purpur" "$mc_version" "$ram_alloc" "$server_dir_abs_path" "$jar_filename"; then
        display_info "$(printf "${purpur_install_success:-Purpur %s (билд %s) успешно установлен в %s.}" "$mc_version" "$latest_build_id" "$SERVER_DIR")"
        display_info "Для запуска: cd '$SERVER_DIR' && ./start.sh или через меню управления."
    else
        display_warning "Сервер Purpur установлен, но не удалось сохранить его конфигурацию."
    fi
    return 0
}
