#!/bin/bash
install_vanilla_server() {
    display_info "Запуск установки Vanilla сервера (Mojang)..."
    local server_name; while true; do read_input "${vanilla_prompt_server_name:-Имя Vanilla сервера: }" server_name; if [[ -z "$server_name" ]]; then display_error "Имя не м.б. пустым."; continue; fi; server_name=$(echo "$server_name"|sed 's/[^a-zA-Z0-9_-]/_/g'); if [[ -z "$server_name" ]]; then display_error "Имя стало пустым после очистки."; continue; fi; if [[ -d "$SERVERS_BASE_DIR/$server_name" ]]; then display_error "$(printf "${server_dir_exists:-Директория %s уже есть.}" "$SERVERS_BASE_DIR/$server_name")"; else break; fi; done
    if [ -z "$SERVERS_BASE_DIR" ]; then display_error "КРИТ: SERVERS_BASE_DIR не определена."; return 1; fi
    local SERVER_DIR="$SERVERS_BASE_DIR/$server_name"
    display_info "${vanilla_fetching_versions:-Получение версий Vanilla...}"; local version_manifest_json; version_manifest_json=$(curl -sSL "https://launchermeta.mojang.com/mc/game/version_manifest.json"); if [ $? -ne 0 ]||! echo "$version_manifest_json"|jq -e . >/dev/null 2>&1; then display_error "Не удалось получить/обработать манифест Mojang."; return 1; fi
    local latest_release_version; latest_release_version=$(echo "$version_manifest_json"|jq -r '.latest.release'); if [ -z "$latest_release_version" ]||[ "$latest_release_version" == "null" ]; then display_error "Не удалось извлечь последнюю релизную версию Vanilla."; return 1; fi; display_info "${vanilla_latest_version:-Последняя версия Vanilla: } $latest_release_version"
    local mc_version; local version_type_filter=".versions[]"; echo "${vanilla_select_version_type:-Тип версии Vanilla:}"; echo "1) ${vanilla_option_release:-Стабильные релизы}"; echo "2) ${vanilla_option_snapshot:-Релизы и снапшоты}"; read_input "${prompt_choice:- > }" version_choice; if [[ "$version_choice" == "1" ]]; then version_type_filter='.versions[]|select(.type=="release")'; fi
    local use_latest_prompt_formatted=$(printf "${vanilla_use_latest_prompt:-Исп. последнюю %s? (y/N, по умолчанию y): }" "$latest_release_version"); read_input "$use_latest_prompt_formatted" use_latest
    if [[ "$use_latest" =~ ^[Nn]$ ]]; then local available_versions_list=$(echo "$version_manifest_json"|jq -r "$version_type_filter|.id"|tr '\n' ' '); display_info "Доступные: $available_versions_list"; read_input "${vanilla_prompt_specific_version:-Введите версию Vanilla (напр. 1.21): }" mc_version; if [ -z "$mc_version" ]; then display_error "Версия не введена."; return 1; fi; if ! echo "$version_manifest_json"|jq -e --arg ver "$mc_version" "$version_type_filter|select(.id==\$ver)">/dev/null; then display_error "Версия '$mc_version' не найдена/не соотв. фильтру."; return 1; fi; else mc_version="$latest_release_version"; fi; display_info "Выбрана: $mc_version"
    local version_specific_url; version_specific_url=$(echo "$version_manifest_json"|jq -r --arg ver "$mc_version" '.versions[]|select(.id==$ver)|.url'); if [ -z "$version_specific_url" ]||[ "$version_specific_url" == "null" ]; then display_error "Не найден URL для манифеста $mc_version."; return 1; fi
    display_info "$(printf "${vanilla_fetching_manifest:-Получение манифеста для Vanilla %s...}" "$mc_version")"; local specific_manifest_json; specific_manifest_json=$(curl -sSL "$version_specific_url"); if [ $? -ne 0 ]||! echo "$specific_manifest_json"|jq -e . >/dev/null 2>&1; then display_error "Не удалось получить/обработать манифест для $mc_version."; return 1; fi
    local server_download_url; server_download_url=$(echo "$specific_manifest_json"|jq -r '.downloads.server.url'); if [ -z "$server_download_url" ]||[ "$server_download_url" == "null" ]; then display_error "$(printf "${vanilla_error_no_manifest:-Не найден URL server.jar для Vanilla %s.}" "$mc_version")"; return 1; fi; display_info "${vanilla_download_url:-URL: } $server_download_url"
    local ram_alloc_prompt ram_alloc; ram_alloc_prompt=$(printf "${vanilla_prompt_ram:-RAM (по умолчанию %s): }" "$DEFAULT_RAM_SUGGESTION"); read_input "$ram_alloc_prompt" ram_alloc; [[ -z "$ram_alloc" ]] && ram_alloc="$DEFAULT_RAM_SUGGESTION"; display_info "RAM: $ram_alloc."
    display_info "$(printf "${vanilla_creating_dir:-Создание директории %s...}" "$SERVER_DIR")"; if ! mkdir -p "$SERVER_DIR"; then display_error "Не удалось создать $SERVER_DIR."; return 1; fi; if [ ! -d "$SERVER_DIR" ]; then display_error "КРИТ: Директория $SERVER_DIR не создана."; return 1; fi
    local jar_filename="server.jar"; display_info "$(printf "${vanilla_downloading_jar:-Загрузка %s (версия %s)...}" "$jar_filename" "$mc_version")"; if ! download_file "$server_download_url" "$SERVER_DIR/$jar_filename"; then display_error "Загрузка Vanilla JAR не удалась."; rm -rf "$SERVER_DIR"; return 1; fi
    generate_server_properties "$SERVER_DIR"
    display_info "${vanilla_creating_eula:-Создание eula.txt...}"; echo "eula=true" > "$SERVER_DIR/eula.txt"
    display_info "${vanilla_creating_start_script:-Создание start.sh...}"
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
    if save_server_config "$server_name" "vanilla" "$mc_version" "$ram_alloc" "$server_dir_abs_path" "$jar_filename"; then
        display_info "$(printf "${vanilla_install_success:-Vanilla %s успешно установлен в %s.}" "$mc_version" "$SERVER_DIR")"
        display_info "Для запуска: cd '$SERVER_DIR' && ./start.sh или через меню управления."
    else display_warning "Сервер установлен, но не удалось сохранить его конфигурацию."; fi
    return 0
}
