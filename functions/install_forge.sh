#!/bin/bash
install_forge_server() {
    display_header "${forge_installer_title:-Установка Forge сервера}"
    local server_name
    while true; do
        read_input "${forge_prompt_server_name:-Имя Forge сервера: }" server_name
        if [[ -z "$server_name" ]]; then display_error "Имя не м.б. пустым."; continue; fi
        server_name=$(echo "$server_name"|sed 's/[^a-zA-Z0-9_-]/_/g'); if [[ -z "$server_name" ]]; then display_error "Имя стало пустым после очистки."; continue; fi
        if [[ -d "$SERVERS_BASE_DIR/$server_name" ]]; then display_error "$(printf "${server_dir_exists:-Директория %s уже есть.}" "$SERVERS_BASE_DIR/$server_name")"; else break; fi
    done
    if [ -z "$SERVERS_BASE_DIR" ]; then display_error "КРИТ: SERVERS_BASE_DIR не определена."; return 1; fi
    local SERVER_DIR="$SERVERS_BASE_DIR/$server_name"
    display_info "${forge_fetching_versions:-Получение списка версий Minecraft для Forge...}"
    local forge_maven_metadata_url="https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml"
    local mc_versions_forge
    mc_versions_forge=$(curl -sSL "$forge_maven_metadata_url" | grep -oP '(?<=<version>)[0-9]+\.[0-9]+(\.[0-9]+)?(?=-)' | sort -Vru | uniq)
    if [ -z "$mc_versions_forge" ]; then
        display_error "Не удалось получить список версий Minecraft для Forge."
        return 1
    fi
    display_info "Доступные версии Minecraft для Forge (могут быть и другие):"
    echo "$mc_versions_forge"
    local mc_version
    read_input "${forge_prompt_mc_version:-Введите версию Minecraft для Forge: }" mc_version
    if ! echo "$mc_versions_forge" | grep -q -w "$mc_version"; then
        display_warning "Введенная версия Minecraft ($mc_version) не найдена в автоматически определенном списке. Попытка продолжить..."
    fi
    display_info "$(printf "${forge_fetching_forge_versions:-Получение версий Forge для Minecraft %s...}" "$mc_version")"
    local latest_forge_full_version
    latest_forge_full_version=$(curl -sSL "$forge_maven_metadata_url" | grep "<version>${mc_version}-" | sed "s/.*<version>\(${mc_version}-[^<]*\)<\/version>.*/\1/" | sort -Vr | head -n1)
    if [ -z "$latest_forge_full_version" ]; then
        display_error "$(printf "${forge_error_forge_version_not_found:-Не удалось найти версию Forge для Minecraft %s.}" "$mc_version")"
        return 1
    fi
    display_info "$(printf "${forge_latest_version:-Последняя версия Forge для MC %s: %s}" "$mc_version" "$latest_forge_full_version")"
    local forge_version_input
    read_input "$(printf "${forge_prompt_forge_version:-Введите полную версию Forge (по умолч. %s) или 'latest': }" "$latest_forge_full_version")" forge_version_input
    local selected_forge_full_version
    if [[ -z "$forge_version_input" || "$forge_version_input" == "latest" ]]; then
        selected_forge_full_version="$latest_forge_full_version"
    else
        selected_forge_full_version="$forge_version_input"
    fi
    display_info "Выбрана версия Forge: $selected_forge_full_version"
    local forge_installer_jar_name="forge-${selected_forge_full_version}-installer.jar"
    local forge_installer_download_url="https://maven.minecraftforge.net/net/minecraftforge/forge/${selected_forge_full_version}/${forge_installer_jar_name}"
    local ram_alloc_prompt ram_alloc; ram_alloc_prompt=$(printf "${paper_prompt_ram:-RAM (по умолчанию %s): }" "$DEFAULT_RAM_SUGGESTION"); read_input "$ram_alloc_prompt" ram_alloc; [[ -z "$ram_alloc" ]] && ram_alloc="$DEFAULT_RAM_SUGGESTION"; display_info "RAM: $ram_alloc."
    if ! mkdir -p "$SERVER_DIR"; then display_error "Не удалось создать директорию $SERVER_DIR."; return 1; fi
    if [ ! -d "$SERVER_DIR" ]; then display_error "КРИТ: Директория $SERVER_DIR не создана."; return 1; fi
    display_info "$(printf "${forge_downloading_installer:-Загрузка установщика Forge %s...}" "$selected_forge_full_version")"
    if ! download_file "$forge_installer_download_url" "$SERVER_DIR/$forge_installer_jar_name"; then
        display_error "Загрузка установщика Forge не удалась. Проверьте URL: $forge_installer_download_url"
        rm -rf "$SERVER_DIR"
        return 1
    fi
    display_info "${forge_running_installer:-Запуск установщика Forge...}"
    (cd "$SERVER_DIR" && java -jar "$forge_installer_jar_name" --installServer .)
    if [ $? -ne 0 ]; then
        display_error "${forge_installer_failed:-Установщик Forge завершился с ошибкой.}"
        return 1
    fi
    generate_server_properties "$SERVER_DIR"
    display_info "${paper_creating_eula:-Создание eula.txt...}"; echo "eula=true" > "$SERVER_DIR/eula.txt"
    local forge_server_jar_name_pattern="forge-${mc_version}-*-server.jar" 
    local forge_server_jar_name="forge-${selected_forge_full_version}.jar" 
    local unix_args_path="libraries/net/minecraftforge/forge/${selected_forge_full_version}/unix_args.txt"
    local final_jar_or_args_path
    if [ -f "$SERVER_DIR/$unix_args_path" ]; then
        final_jar_or_args_path="$unix_args_path"
        display_info "Будет использован $unix_args_path для запуска."
    else
        local found_forge_jar
        found_forge_jar=$(find "$SERVER_DIR" -maxdepth 1 -name "$forge_server_jar_name_pattern" -print -quit)
        if [ -n "$found_forge_jar" ]; then
            forge_server_jar_name=$(basename "$found_forge_jar")
            final_jar_or_args_path="$forge_server_jar_name"
            display_info "Найден основной JAR сервера Forge: $forge_server_jar_name. Будет использован прямой запуск JAR."
        elif [ -f "$SERVER_DIR/run.sh" ] || [ -f "$SERVER_DIR/run.bat" ] ; then
             display_warning "Не найден unix_args.txt или конкретный server.jar. Найден run.sh/run.bat. Настройте start.sh вручную при необходимости."
             final_jar_or_args_path="NEEDS_MANUAL_SETUP_FOR_JAR" # Placeholder
        else
            display_error "Не удалось определить основной JAR файл сервера Forge или unix_args.txt. Установка может быть неполной."
            final_jar_or_args_path="UNKNOWN_FORGE_JAR"
        fi
    fi
    display_info "${paper_creating_start_script:-Создание start.sh...}"
    cat > "$SERVER_DIR/start.sh" <<EOL
#!/bin/bash
cd "\$(dirname "\$0")"
XMS_RAM="${ram_alloc}"
XMX_RAM="${ram_alloc}"
ADDITIONAL_JVM_ARGS=""
if [ -f .env ]; then
  source .env
fi
if [ -f "${unix_args_path}" ]; then
  echo "-Xms\${XMS_RAM}" > user_jvm_args.txt
  echo "-Xmx\${XMX_RAM}" >> user_jvm_args.txt
  if [ -n "\$ADDITIONAL_JVM_ARGS" ]; then
    echo "\$ADDITIONAL_JVM_ARGS" >> user_jvm_args.txt
  fi
  java @user_jvm_args.txt @"${unix_args_path}" nogui "\$@"
elif [ -f "${forge_server_jar_name}" ]; then
  java "-Xms\${XMS_RAM}" "-Xmx\${XMX_RAM}" \${ADDITIONAL_JVM_ARGS} -jar "${forge_server_jar_name}" nogui
else
  echo "Ошибка: Не удалось найти unix_args.txt или подходящий Forge JAR для запуска."
  echo "Проверьте ${unix_args_path} или ${forge_server_jar_name}"
fi
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
    display_info "${fabric_cleaning_up:-Очистка (удаление установщика Forge)...}"
    rm -f "$SERVER_DIR/$forge_installer_jar_name"
    local server_dir_abs_path; if [ -d "$SERVER_DIR" ]; then server_dir_abs_path=$(cd "$SERVER_DIR" && pwd); else display_error "$SERVER_DIR не найдена для abs пути."; return 1; fi
    if [ -z "$server_dir_abs_path" ]; then display_error "Не удалось получить abs путь для $SERVER_DIR."; return 1; fi
    local display_version_forge="$selected_forge_full_version"
    if save_server_config "$server_name" "forge" "$display_version_forge" "$ram_alloc" "$server_dir_abs_path" "$final_jar_or_args_path"; then
        display_info "$(printf "${forge_install_success:-Сервер Forge %s успешно установлен в %s.}" "$display_version_forge" "$SERVER_DIR")"
        display_info "${forge_start_script_info:-Для запуска используется Forge run.sh или сгенерированный start.sh.}"
    else
        display_warning "Сервер Forge установлен, но не удалось сохранить его конфигурацию."
    fi
    return 0
}
