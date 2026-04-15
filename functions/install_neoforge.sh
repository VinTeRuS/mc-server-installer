#!/bin/bash

install_neoforge_server() {
    display_header "${neoforge_installer_title:-Установка NeoForge сервера}"
    local server_name
    while true; do
        read_input "${neoforge_prompt_server_name:-Имя NeoForge сервера: }" server_name
        if [[ -z "$server_name" ]]; then display_error "Имя не м.б. пустым."; continue; fi
        server_name=$(echo "$server_name"|sed 's/[^a-zA-Z0-9_-]/_/g')
        if [[ -z "$server_name" ]]; then display_error "Имя стало пустым после очистки."; continue; fi
        if [[ -d "$SERVERS_BASE_DIR/$server_name" ]]; then display_error "$(printf "${server_dir_exists:-Директория %s уже есть.}" "$SERVERS_BASE_DIR/$server_name")"; else break; fi
    done

    if [ -z "$SERVERS_BASE_DIR" ]; then display_error "КРИТ: SERVERS_BASE_DIR не определена."; return 1; fi
    local SERVER_DIR="$SERVERS_BASE_DIR/$server_name"

    display_info "${neoforge_fetching_versions:-Получение списка версий NeoForge...}"
    local neoforge_maven_metadata_url="https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml"
    
    local all_versions
    all_versions=$(curl -sSL "$neoforge_maven_metadata_url" | grep -oP '(?<=<version>)[^<]+' | sort -Vru)
    if [ -z "$all_versions" ]; then
        display_error "Не удалось получить список версий NeoForge."
        return 1
    fi

    # Group versions by Minecraft version (e.g. 21.1.x -> 1.21.1)
    # Mapping logic: 20.1.x -> 1.20.1, 20.4.x -> 1.20.4, 21.0.x -> 1.21, 21.1.x -> 1.21.1
    display_info "Последние доступные версии NeoForge (сокращенно):"
    echo "$all_versions" | head -n 15

    local selected_version
    read_input "${neoforge_prompt_version:-Введите версию NeoForge (напр. 21.1.58) или 'latest': }" selected_version
    if [[ -z "$selected_version" || "$selected_version" == "latest" ]]; then
        selected_version=$(echo "$all_versions" | head -n 1)
    fi

    if ! echo "$all_versions" | grep -q -w "$selected_version"; then
        display_warning "Версия '$selected_version' не найдена в списке. Попытка продолжить..."
    fi

    local ram_alloc_prompt ram_alloc
    ram_alloc_prompt=$(printf "${paper_prompt_ram:-RAM (по умолчанию %s): }" "$DEFAULT_RAM_SUGGESTION")
    read_input "$ram_alloc_prompt" ram_alloc
    [[ -z "$ram_alloc" ]] && ram_alloc="$DEFAULT_RAM_SUGGESTION"

    if ! mkdir -p "$SERVER_DIR"; then display_error "Не удалось создать директорию $SERVER_DIR."; return 1; fi

    local neoforge_installer_jar="neoforge-${selected_version}-installer.jar"
    local neoforge_url="https://maven.neoforged.net/releases/net/neoforged/neoforge/${selected_version}/${neoforge_installer_jar}"

    display_info "Загрузка установщика NeoForge: $neoforge_installer_jar..."
    if ! download_file "$neoforge_url" "$SERVER_DIR/$neoforge_installer_jar"; then
        display_error "Загрузка не удалась. Проверьте версию: $selected_version"
        rm -rf "$SERVER_DIR"
        return 1
    fi

    display_info "Запуск установщика NeoForge (это может занять время)..."
    (cd "$SERVER_DIR" && java -jar "$neoforge_installer_jar" --installServer .)
    if [ $? -ne 0 ]; then
        display_error "Установщик NeoForge завершился с ошибкой."
        return 1
    fi

    display_info "Создание eula.txt и server.properties..."
    echo "eula=true" > "$SERVER_DIR/eula.txt"
    generate_server_properties "$SERVER_DIR"

    # Determine startup command
    # NeoForge usually provides unix_args.txt in libraries/net/neoforged/neoforge/<version>/
    local unix_args_path="libraries/net/neoforged/neoforge/${selected_version}/unix_args.txt"
    
    display_info "Создание start.sh..."
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
elif [ -f "run.sh" ]; then
  # Fallback to generated run.sh if it exists (some installations might have it)
  ./run.sh
else
  # Manual attempt if everything else fails
  java "-Xms\${XMS_RAM}" "-Xmx\${XMX_RAM}" \${ADDITIONAL_JVM_ARGS} -jar neoforge-server.jar nogui
fi
EOL
    chmod +x "$SERVER_DIR/start.sh"

    rm -f "$SERVER_DIR/$neoforge_installer_jar"

    local server_dir_abs_path
    server_dir_abs_path=$(cd "$SERVER_DIR" && pwd)
    
    if save_server_config "$server_name" "neoforge" "$selected_version" "$ram_alloc" "$server_dir_abs_path" "neoforge-server.jar"; then
        display_info "NeoForge сервер успешно установлен в $SERVER_DIR"
    else
        display_warning "Сервер установлен, но не удалось сохранить конфигурацию."
    fi
    return 0
}
