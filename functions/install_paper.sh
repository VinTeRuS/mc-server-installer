#!/bin/bash
install_paper_server() {
    display_info "Запуск установки PaperMC сервера..."
    local server_name
    while true; do
        read_input "${paper_prompt_server_name:-Имя Paper сервера: }" server_name
        if [[ -z "$server_name" ]]; then display_error "Имя не м.б. пустым."; continue; fi
        server_name=$(echo "$server_name"|sed 's/[^a-zA-Z0-9_-]/_/g')
        if [[ -z "$server_name" ]]; then display_error "Имя стало пустым после очистки."; continue; fi
        if [[ -d "$SERVERS_BASE_DIR/$server_name" ]]; then display_error "$(printf "${server_dir_exists:-Директория %s уже есть.}" "$SERVERS_BASE_DIR/$server_name")"; else break; fi
    done
    if [ -z "$SERVERS_BASE_DIR" ]; then display_error "КРИТ: SERVERS_BASE_DIR не определена."; return 1; fi
    local SERVER_DIR="$SERVERS_BASE_DIR/$server_name"
    display_info "${paper_fetching_versions:-Получение версий PaperMC...}"; local versions_json; versions_json=$(curl -sSL "https://api.papermc.io/v2/projects/paper"); if [ $? -ne 0 ]||! echo "$versions_json"|jq -e . >/dev/null 2>&1; then display_error "Не удалось получить/обработать версии PaperMC."; return 1; fi
    local latest_paper_version; latest_paper_version=$(echo "$versions_json"|jq -r '.versions[-1]'); if [ -z "$latest_paper_version" ]||[ "$latest_paper_version" == "null" ]; then display_error "Не удалось извлечь последнюю версию Paper."; return 1; fi
    display_info "${paper_latest_version:-Последняя версия Paper: } $latest_paper_version"; local mc_version; local use_latest_prompt_formatted=$(printf "${paper_use_latest_prompt:-Исп. последнюю %s? (y/N, по умолчанию y): }" "$latest_paper_version"); read_input "$use_latest_prompt_formatted" use_latest
    if [[ "$use_latest" =~ ^[Nn]$ ]]; then local paper_versions_list=$(echo "$versions_json"|jq -r '.versions[]'|tr '\n' ' '); display_info "Доступные: ${paper_versions_list}"; read_input "${paper_prompt_specific_version:-Введите версию Paper (напр. 1.21): }" mc_version; if [ -z "$mc_version" ]; then display_error "Версия не введена."; return 1; fi; if ! echo "$versions_json"|jq -e --arg ver "$mc_version" '.versions[]|select(.==$ver)'>/dev/null; then display_error "Версия '$mc_version' не найдена."; return 1; fi; else mc_version="$latest_paper_version"; fi; display_info "Выбрана: $mc_version"
    local fetch_builds_msg=$(printf "${paper_fetching_builds:-Получение билдов для Paper %s...}" "$mc_version"); display_info "$fetch_builds_msg"; local builds_json; builds_json=$(curl -sSL "https://api.papermc.io/v2/projects/paper/versions/${mc_version}/builds"); if [ $? -ne 0 ]||! echo "$builds_json"|jq -e . >/dev/null 2>&1; then display_error "Не удалось получить/обработать билды для Paper $mc_version."; return 1; fi
    local latest_build_id; latest_build_id=$(echo "$builds_json"|jq -r '.builds|map(select(.channel=="default"))|.[-1].build // (.builds|.[-1].build)'); if [ -z "$latest_build_id" ]||[ "$latest_build_id" == "null" ]; then display_error "$(printf "${paper_error_no_builds:-Не найден билд для Paper %s.}" "$mc_version")"; return 1; fi; display_info "$(printf "${paper_latest_build:-Последний билд для %s: }" "$mc_version") $latest_build_id"
    local jar_filename="paper-${mc_version}-${latest_build_id}.jar"; local download_url="https://api.papermc.io/v2/projects/paper/versions/${mc_version}/builds/${latest_build_id}/downloads/${jar_filename}"; display_info "${paper_download_url:-URL: } $download_url"; if [[ "$download_url" == *"/versions//builds//downloads/-null-"* ]]||[ -z "$jar_filename" ]||[[ "$jar_filename" == *-null-* ]]; then display_error "Ошибка URL/имени JAR."; return 1; fi
    local ram_alloc_prompt ram_alloc; ram_alloc_prompt=$(printf "${paper_prompt_ram:-RAM (по умолчанию %s): }" "$DEFAULT_RAM_SUGGESTION"); read_input "$ram_alloc_prompt" ram_alloc; [[ -z "$ram_alloc" ]] && ram_alloc="$DEFAULT_RAM_SUGGESTION"; display_info "RAM: $ram_alloc."
    display_info "$(printf "${paper_creating_dir:-Создание директории %s...}" "$SERVER_DIR")"; if ! mkdir -p "$SERVER_DIR"; then display_error "Не удалось создать $SERVER_DIR."; return 1; fi; if [ ! -d "$SERVER_DIR" ]; then display_error "КРИТ: Директория $SERVER_DIR не создана."; return 1; fi
    display_info "$(printf "${paper_downloading_jar:-Загрузка %s...}" "$jar_filename")"; if ! download_file "$download_url" "$SERVER_DIR/$jar_filename"; then display_error "Загрузка Paper JAR не удалась."; rm -rf "$SERVER_DIR"; return 1; fi
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
        display_info "${env_file_created_message:-.env файл создан. Отредактируйте его для добавления аргументов.}"
    else
        display_info "${env_file_not_created_message:-.env файл не будет создан.}"
    fi
    local server_dir_abs_path; if [ -d "$SERVER_DIR" ]; then server_dir_abs_path=$(cd "$SERVER_DIR" && pwd); else display_error "$SERVER_DIR не найдена для abs пути."; return 1; fi
    if [ -z "$server_dir_abs_path" ]; then display_error "Не удалось получить abs путь для $SERVER_DIR."; return 1; fi
    if save_server_config "$server_name" "paper" "$mc_version" "$ram_alloc" "$server_dir_abs_path" "$jar_filename"; then
        display_info "$(printf "${paper_install_success:-Paper %s (%s) успешно установлен в %s.}" "$mc_version" "$latest_build_id" "$SERVER_DIR")"
        display_info "Для запуска: cd '$SERVER_DIR' && ./start.sh или через меню управления."
    else display_warning "Сервер установлен, но не удалось сохранить его конфигурацию."; fi
    return 0
}
