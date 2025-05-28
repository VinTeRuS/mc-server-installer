#!/bin/bash
install_fabric_server() {
    display_header "${fabric_installer_title:-Установка Fabric сервера}"
    local server_name; while true; do read_input "${fabric_prompt_server_name:-Имя Fabric сервера: }" server_name; if [[ -z "$server_name" ]]; then display_error "Имя не м.б. пустым."; continue; fi; server_name=$(echo "$server_name"|sed 's/[^a-zA-Z0-9_-]/_/g'); if [[ -z "$server_name" ]]; then display_error "Имя стало пустым после очистки."; continue; fi; if [[ -d "$SERVERS_BASE_DIR/$server_name" ]]; then display_error "$(printf "${server_dir_exists:-Директория %s уже есть.}" "$SERVERS_BASE_DIR/$server_name")"; else break; fi; done
    if [ -z "$SERVERS_BASE_DIR" ]; then display_error "КРИТ: SERVERS_BASE_DIR не определена."; return 1; fi
    local SERVER_DIR="$SERVERS_BASE_DIR/$server_name"
    display_info "${fabric_fetching_meta:-Получение метаданных Fabric...}"
    local fabric_installer_url fabric_installer_version; fabric_installer_version_json=$(curl -sSL "https://meta.fabricmc.net/v2/versions/installer"); if [ $? -ne 0 ] || ! echo "$fabric_installer_version_json" | jq -e . >/dev/null 2>&1; then display_error "Не удалось получить версии установщика Fabric."; return 1; fi
    fabric_installer_url=$(echo "$fabric_installer_version_json" | jq -r 'map(select(.stable==true)) | .[0].url'); fabric_installer_version=$(echo "$fabric_installer_version_json" | jq -r 'map(select(.stable==true)) | .[0].version')
    if [ -z "$fabric_installer_url" ] || [ "$fabric_installer_url" == "null" ] || [ -z "$fabric_installer_version" ]; then display_error "Не удалось определить URL/версию установщика Fabric."; return 1; fi
    display_info "$(printf "${fabric_latest_installer_version:-Исп. установщик Fabric v%s}" "$fabric_installer_version")"
    local fabric_mc_versions_json mc_version latest_stable_mc_version; fabric_mc_versions_json=$(curl -sSL "https://meta.fabricmc.net/v2/versions/game"); if [ $? -ne 0 ] || ! echo "$fabric_mc_versions_json" | jq -e . >/dev/null 2>&1; then display_error "Не удалось получить версии Minecraft для Fabric."; return 1; fi
    latest_stable_mc_version=$(echo "$fabric_mc_versions_json" | jq -r 'map(select(.stable==true)) | .[0].version'); display_info "$(printf "${fabric_latest_stable_mc_version:-Последняя стабильная MC для Fabric: %s}" "$latest_stable_mc_version")"
    read_input "$(printf "${fabric_prompt_mc_version:-Версия Minecraft (по умолч. %s): }" "$latest_stable_mc_version")" mc_version; [[ -z "$mc_version" ]] && mc_version="$latest_stable_mc_version"
    if ! echo "$fabric_mc_versions_json" | jq -e --arg mc "$mc_version" '.[] | select(.version==$mc)' > /dev/null; then display_error "$(printf "${fabric_error_mc_version_not_found:-Версия MC '%s' не найдена в Fabric.}", "$mc_version")"; return 1; fi
    local fabric_loader_version_json fabric_loader_version; fabric_loader_version_json=$(curl -sSL "https://meta.fabricmc.net/v2/versions/loader"); if [ $? -ne 0 ] || ! echo "$fabric_loader_version_json" | jq -e . >/dev/null 2>&1; then display_error "Не удалось получить версии загрузчика Fabric."; fabric_loader_version=""; else fabric_loader_version=$(echo "$fabric_loader_version_json" | jq -r 'map(select(.stable==true)) | .[0].version'); fi
    if [ -z "$fabric_loader_version" ]; then display_warning "Не удалось определить loader Fabric, установщик выберет подходящую."; else display_info "$(printf "${fabric_latest_loader_version:-Исп. Fabric Loader v%s}" "$fabric_loader_version")"; fi
    local ram_alloc_prompt ram_alloc; ram_alloc_prompt=$(printf "${fabric_prompt_ram:-RAM (по умолчанию %s): }" "$DEFAULT_RAM_SUGGESTION"); read_input "$ram_alloc_prompt" ram_alloc; [[ -z "$ram_alloc" ]] && ram_alloc="$DEFAULT_RAM_SUGGESTION"; display_info "RAM: $ram_alloc."
    if ! mkdir -p "$SERVER_DIR"; then display_error "Не удалось создать директорию $SERVER_DIR."; return 1; fi; if [ ! -d "$SERVER_DIR" ]; then display_error "КРИТ: Директория $SERVER_DIR не создана."; return 1; fi
    local fabric_installer_jar="fabric-installer.jar"; display_info "$(printf "${fabric_downloading_installer:-Загрузка установщика Fabric (%s)...}" "$fabric_installer_version")"
    if ! download_file "$fabric_installer_url" "$SERVER_DIR/$fabric_installer_jar"; then display_error "Загрузка установщика Fabric не удалась."; rm -rf "$SERVER_DIR"; return 1; fi
    display_info "$(printf "${fabric_running_installer:-Запуск установщика Fabric для MC %s...}" "$mc_version")"; local fabric_install_cmd="java -jar \"$fabric_installer_jar\" server -mcversion \"$mc_version\" -downloadMinecraft"; if [ -n "$fabric_loader_version" ]; then fabric_install_cmd="$fabric_install_cmd -loader \"$fabric_loader_version\""; fi
    (cd "$SERVER_DIR" && eval "$fabric_install_cmd"); if [ $? -ne 0 ]; then display_error "${fabric_installer_failed:-Установщик Fabric завершился с ошибкой.}"; return 1; fi
    local server_jar_filename="fabric-server-launch.jar"; if [ ! -f "$SERVER_DIR/$server_jar_filename" ]; then display_error "$(printf "${fabric_server_jar_not_found:-Не найден %s в %s}" "$server_jar_filename" "$SERVER_DIR")"; return 1; fi
    generate_server_properties "$SERVER_DIR"
    local install_fabric_api_prompt; install_fabric_api_prompt=$(printf "${fabric_prompt_install_fabric_api:-Хотите установить Fabric API? (y/N): }"); read_input "$install_fabric_api_prompt" confirm_fabric_api
    if [[ "$confirm_fabric_api" =~ ^[YyДд]$ ]]; then
        display_info "$(printf "${fabric_fetching_fabric_api:-Поиск Fabric API для MC %s...}" "$mc_version")"
        local fabric_api_project_id="P7dR8mSH"; local mc_version_escaped=$(jq -nr --arg str "$mc_version" '$str|@uri')
        local fabric_api_versions_url="https://api.modrinth.com/v2/project/${fabric_api_project_id}/version?game_versions=\[\"${mc_version_escaped}\"\]&loaders=\[\"fabric\"\]"
        local fabric_api_data fabric_api_dl_url fabric_api_dl_filename fabric_api_version_number
        fabric_api_data=$(curl -sSL "$fabric_api_versions_url" | jq -r '.[0]')
        if [ -z "$fabric_api_data" ] || [ "$fabric_api_data" == "null" ]; then display_warning "$(printf "${fabric_api_not_found:-Не удалось найти Fabric API для MC %s.}" "$mc_version")"; else
            fabric_api_dl_url=$(echo "$fabric_api_data" | jq -r '.files[]? | select(.primary == true) | .url // .files[0].url')
            fabric_api_dl_filename=$(echo "$fabric_api_data" | jq -r '.files[]? | select(.primary == true) | .filename // .files[0].filename')
            fabric_api_version_number=$(echo "$fabric_api_data" | jq -r '.version_number')
            if [ -z "$fabric_api_dl_url" ] || [ "$fabric_api_dl_url" == "null" ] || [ -z "$fabric_api_dl_filename" ]; then display_warning "$(printf "${fabric_api_not_found:-Не удалось найти URL загрузки Fabric API для MC %s.}" "$mc_version")"; else
                display_info "$(printf "${fabric_api_version_found:-Найдена версия Fabric API: %s}" "$fabric_api_version_number")"
                local mods_dir="$SERVER_DIR/mods"; if [ ! -d "$mods_dir" ]; then display_info "$(printf "${fabric_creating_mods_folder:-Создание папки mods в %s...}" "$SERVER_DIR")"; mkdir -p "$mods_dir"; fi
                display_info "$(printf "${fabric_api_downloading:-Загрузка %s (%s)...}" "$fabric_api_dl_filename" "$fabric_api_version_number")"
                if download_file "$fabric_api_dl_url" "$mods_dir/$fabric_api_dl_filename"; then display_info "$(printf "${fabric_api_install_success:-Fabric API (%s) успешно установлен.}" "$fabric_api_dl_filename")";
                else display_error "${fabric_api_download_failed:-Не удалось загрузить Fabric API.}"; fi
            fi
        fi
    fi
    display_info "${paper_creating_eula:-Создание eula.txt...}"; echo "eula=true" > "$SERVER_DIR/eula.txt"
    display_info "${paper_creating_start_script:-Создание start.sh...}"
    cat > "$SERVER_DIR/start.sh" <<EOL
#!/bin/bash
cd "\$(dirname "\$0")"
XMS_RAM="${ram_alloc}"
XMX_RAM="${ram_alloc}"
SERVER_JAR="${server_jar_filename}"
ADDITIONAL_JVM_ARGS=""
if [ -f .env ]; then
  source .env
fi
java "-Xms\${XMS_RAM}" "-Xmx\${XMX_RAM}" \${ADDITIONAL_JVM_ARGS} -jar "\${SERVER_JAR}" nogui
EOL
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
    display_info "${fabric_cleaning_up:-Очистка (удаление установщика Fabric)...}"; rm -f "$SERVER_DIR/$fabric_installer_jar"
    local server_dir_abs_path; if [ -d "$SERVER_DIR" ]; then server_dir_abs_path=$(cd "$SERVER_DIR" && pwd); else display_error "$SERVER_DIR не найдена для abs пути."; return 1; fi
    if [ -z "$server_dir_abs_path" ]; then display_error "Не удалось получить abs путь для $SERVER_DIR."; return 1; fi
    local display_version="$mc_version (Fabric Loader: ${fabric_loader_version:-auto})"
    if save_server_config "$server_name" "fabric" "$display_version" "$ram_alloc" "$server_dir_abs_path" "$server_jar_filename"; then
        display_info "$(printf "${fabric_install_success:-Сервер Fabric для MC %s успешно установлен в %s.}" "$display_version" "$SERVER_DIR")"
        display_info "Для запуска: cd '$SERVER_DIR' && ./start.sh или через меню управления."
    else display_warning "Сервер Fabric установлен, но не удалось сохранить его конфигурацию."; fi
    return 0
}
