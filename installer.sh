#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
UI_SCRIPT="$SCRIPT_DIR/ui.sh"
UTILS_SCRIPT="$SCRIPT_DIR/utils.sh"
FUNCTIONS_DIR="$SCRIPT_DIR/functions"
CONFIGS_DIR="$SCRIPT_DIR/configs"
LOGS_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOGS_DIR/installer.log"
USER_DATA_DIR="$SCRIPT_DIR/.mcinstaller"
SERVERS_BASE_DIR="$SCRIPT_DIR/minecraft_servers"
LANG_DIR="$USER_DATA_DIR/lang"
SERVERS_CONFIG_FILE="$USER_DATA_DIR/servers.json"
INSTALLER_CONFIG_FILE="$USER_DATA_DIR/installer_config.json"
source "$UI_SCRIPT"
source "$UTILS_SCRIPT"
CURRENT_LANG="ru"
DEFAULT_RAM_SUGGESTION="2G"
initialize_application() {
    mkdir -p "$FUNCTIONS_DIR" "$CONFIGS_DIR/profiles" "$LOGS_DIR" "$USER_DATA_DIR" "$SERVERS_BASE_DIR" "$LANG_DIR"
    touch "$LOG_FILE"
    if [ ! -f "$INSTALLER_CONFIG_FILE" ]; then
        echo -e "\033[0;33m[WARN] Файл конфигурации установщика $INSTALLER_CONFIG_FILE не найден. Создание нового...\033[0m"
        echo "{\"language\": \"ru\", \"default_ram\": \"2G\"}" | jq . > "$INSTALLER_CONFIG_FILE"
        _log_message "INFO" "Created new installer config file at $INSTALLER_CONFIG_FILE"
    fi
    if jq -e . "$INSTALLER_CONFIG_FILE" > /dev/null 2>&1; then
        CURRENT_LANG=$(jq -r '.language // "ru"' "$INSTALLER_CONFIG_FILE")
        DEFAULT_RAM_SUGGESTION=$(jq -r '.default_ram // "2G"' "$INSTALLER_CONFIG_FILE")
    else
        _log_message "ERROR" "Installer config file $INSTALLER_CONFIG_FILE is corrupted. Recreating with defaults."
        echo "{\"language\": \"ru\", \"default_ram\": \"2G\"}" | jq . > "$INSTALLER_CONFIG_FILE"
        CURRENT_LANG="ru"
        DEFAULT_RAM_SUGGESTION="2G"
    fi
    if [ ! -f "$SERVERS_CONFIG_FILE" ] || ! jq -e . "$SERVERS_CONFIG_FILE" > /dev/null 2>&1; then
        _log_message "WARN" "Servers config file $SERVERS_CONFIG_FILE not found or corrupted. Creating new."
        echo "[]" > "$SERVERS_CONFIG_FILE"
    fi
    if [ -f "$LANG_DIR/$CURRENT_LANG.lang" ]; then
        source "$LANG_DIR/$CURRENT_LANG.lang"
        _log_message "INFO" "Loaded language file: $LANG_DIR/$CURRENT_LANG.lang"
    else
        _log_message "WARN" "Language file $LANG_DIR/$CURRENT_LANG.lang not found. Using fallback strings."
        menu_title='======== MINECRAFT SERVER INSTALLER (fallback) ========'
    fi
    display_info "$(printf "${log_info_logging_to:-Логирование также ведется в файл: %s}" "$LOG_FILE")"
}
settings_menu() {
    while true; do
        clear
        display_header "${settings_title:-НАСТРОЙКИ УСТАНОВЩИКА}"
        display_info "$(printf "${settings_current_language:-Текущий язык: %s}" "$CURRENT_LANG")"
        display_info "$(printf "${settings_current_default_ram:-RAM по умолчанию: %s}" "$DEFAULT_RAM_SUGGESTION")"
        echo ""
        display_info "$(printf "${settings_info_edit_config:-Для изменения отредактируйте: %s}" "$INSTALLER_CONFIG_FILE")"
        echo ""
        echo "1) ${settings_option_change_lang:-Изменить язык}"
        echo "2) ${settings_option_change_ram:-Изменить RAM по умолчанию}"
        echo "3) ${settings_option_back_to_main:-Вернуться в главное меню}"
        read_input "${prompt_choice:- > }" choice_settings
        case $choice_settings in
            1)
                clear
                display_header "${settings_option_change_lang:-Изменить язык}"
                echo "${settings_prompt_select_language:-Выберите язык:}"
                echo "${settings_lang_option_ru:-1) Русский (ru)}"
                echo "${settings_lang_option_en:-2) English (en)}"
                echo "3) ${manage_option_back_to_main:-Отмена}"
                read_input "${prompt_choice:- > }" lang_choice
                local new_lang="$CURRENT_LANG"
                case $lang_choice in
                    1) new_lang="ru" ;;
                    2) new_lang="en" ;;
                    3) display_info "${settings_lang_no_change:-Язык не изменен.}";;
                    *) display_error "${error_invalid_choice:-Неверный выбор.}";;
                esac
                if [[ "$new_lang" != "$CURRENT_LANG" && ("$lang_choice" == "1" || "$lang_choice" == "2") ]]; then
                    if [ ! -f "$LANG_DIR/$new_lang.lang" ]; then
                        display_error "Языковой файл для '$new_lang' ($LANG_DIR/$new_lang.lang) не найден. Язык не изменен."
                    else
                        jq ".language = \"$new_lang\"" "$INSTALLER_CONFIG_FILE" > "$INSTALLER_CONFIG_FILE.tmp" && \
                        mv "$INSTALLER_CONFIG_FILE.tmp" "$INSTALLER_CONFIG_FILE"
                        if [ $? -eq 0 ]; then
                            CURRENT_LANG="$new_lang"
                            display_info "$(printf "${settings_lang_changed_info:-Язык изменен на %s. Перезапустите установщик.}" "$new_lang")"
                        else
                            display_error "Не удалось сохранить изменения языка в $INSTALLER_CONFIG_FILE."
                        fi
                    fi
                elif [[ "$lang_choice" != "3" ]]; then
                    display_info "${settings_lang_no_change:-Язык не изменен.}";
                fi
                ;;
            2)
                read_input "$(printf "${settings_prompt_new_default_ram:-Новое значение RAM по умолчанию (%s): }" "$DEFAULT_RAM_SUGGESTION")" new_ram_val
                if [[ -n "$new_ram_val" && "$new_ram_val" =~ ^[0-9]+[GgMm]$ ]]; then
                    jq ".default_ram = \"$new_ram_val\"" "$INSTALLER_CONFIG_FILE" > "$INSTALLER_CONFIG_FILE.tmp" && \
                    mv "$INSTALLER_CONFIG_FILE.tmp" "$INSTALLER_CONFIG_FILE"
                    if [ $? -eq 0 ]; then
                        DEFAULT_RAM_SUGGESTION="$new_ram_val"
                        display_info "$(printf "${settings_default_ram_updated:-RAM по умолчанию обновлен на %s.}" "$new_ram_val")"
                    else
                        display_error "Не удалось сохранить изменения RAM в $INSTALLER_CONFIG_FILE."
                    fi
                else
                    display_error "${settings_default_ram_invalid_input:-Некорректный ввод. RAM не изменен.}"
                fi
                ;;
            3) return ;;
            *) display_error "${error_invalid_choice:-Неверный выбор.}";;
        esac
        read -n 1 -s -r -p "${press_any_key:-Нажмите любую клавишу...}"
    done
}
manage_servers_menu() {
    while true; do
        clear; display_header "${manage_servers_title:-УПРАВЛЕНИЕ СЕРВЕРАМИ}"
        local num_servers; num_servers=$(jq '. | length' "$SERVERS_CONFIG_FILE" 2>/dev/null)
        if [[ "$num_servers" -eq 0 ]] || [ -z "$num_servers" ]; then
            display_info "${manage_servers_no_servers:-Установленных серверов не найдено.}"; echo; echo "1) ${manage_option_back_to_main_menu:-Вернуться в главное меню}"
            read_input "${prompt_choice:- > }" mgmt_choice; if [[ "$mgmt_choice" == "1" ]]; then return; else display_error "${error_invalid_choice:-Неверный выбор.}"; sleep 1; continue; fi
        fi
        display_info "${manage_servers_list_installed:-Установленные серверы:}"; local i=1; local server_data=()
        while IFS= read -r server_json_line; do
            server_data[i]="$server_json_line"; local name type version path
            name=$(echo "$server_json_line"|jq -r '.name'); type=$(echo "$server_json_line"|jq -r '.type'); version=$(echo "$server_json_line"|jq -r '.version'); path=$(echo "$server_json_line"|jq -r '.path')
            echo "$i) $name ($type $version) - $path"; i=$((i+1))
        done < <(jq -c '.[]' "$SERVERS_CONFIG_FILE")
        echo; local back_option_num="$i"; echo "${back_option_num}) ${manage_option_back_to_main_menu:-Вернуться в главное меню}"
        read_input "$(printf "${manage_servers_prompt_select_server:-Введите номер сервера (0 для возврата): }" )" server_idx
        if ! [[ "$server_idx" =~ ^[0-9]+$ ]]; then display_error "${error_invalid_choice:-Неверный выбор. Введите число.}"; sleep 1; continue; fi
        if [[ "$server_idx" -ge 1 && "$server_idx" -lt "$back_option_num" ]]; then
            local selected_server_json="${server_data[$server_idx]}"
            local selected_server_name=$(echo "$selected_server_json" | jq -r '.name')
            local selected_server_path=$(echo "$selected_server_json" | jq -r '.path')
            local screen_session_name="mc_${selected_server_name//[^a-zA-Z0-9_]/_}"
            clear; display_header "$(printf "${manage_servers_select_action:-Действие для '%s'}" "$selected_server_name")"
            local server_status_msg; local port_status_msg=""
            if is_server_running "$screen_session_name"; then
                server_status_msg="$(printf "${manage_server_is_running:-Сервер %s (сессия %s) ЗАПУЩЕН.}" "$selected_server_name" "$screen_session_name")"
                local server_props_file="$selected_server_path/server.properties"
                if [ -f "$server_props_file" ]; then
                    local server_port; server_port=$(grep -E '^server-port=' "$server_props_file" | cut -d= -f2)
                    if [ -n "$server_port" ]; then
                        if ss -tulnp | grep -q ":${server_port}\s" || netstat -tulnp | grep -q ":${server_port}\s.*LISTEN"; then
                           port_status_msg="$(printf "${manage_server_port_listening:-Порт %s: СЛУШАЕТ}" "$server_port")"
                        else
                           port_status_msg="$(printf "${manage_server_port_not_listening:-Порт %s: НЕ СЛУШАЕТ}" "$server_port")"
                        fi
                    else
                        port_status_msg="${manage_server_port_not_configured:-Порт не настроен в server.properties}"
                    fi
                else
                    port_status_msg="${manage_server_port_unknown:-Порт: Статус неизвестен (нет server.properties)}"
                fi
            else
                server_status_msg="$(printf "${manage_server_is_not_running:-Сервер %s (сессия %s) НЕ ЗАПУЩЕН.}" "$selected_server_name" "$screen_session_name")"
            fi
            display_info "$server_status_msg"
            if [ -n "$port_status_msg" ]; then display_info "$port_status_msg"; fi; echo
            echo "1) ${manage_option_start_server:-Запустить сервер}"
            echo "2) ${manage_option_stop_server:-Остановить сервер}"
            echo "3) ${manage_option_send_command:-Отправить команду в консоль}"
            echo "4) ${manage_option_view_latest_log:-Посмотреть latest.log}"
            echo "5) ${manage_option_backup_server:-Создать резервную копию}"
            echo "6) ${manage_option_delete_server:-Удалить сервер}"
            echo "7) ${manage_option_back_to_server_list:-Назад к списку серверов}"
            read_input "${prompt_choice:- > }" action_choice
            case $action_choice in
                1) if ! command -v screen &>/dev/null; then display_error "${manage_error_no_screen:-Утилита 'screen' не найдена.}"; elif [ ! -f "$selected_server_path/start.sh" ]; then display_error "start.sh не найден в: $selected_server_path"; elif is_server_running "$screen_session_name"; then display_warning "$(printf "${manage_server_is_running:-Сервер %s уже запущен.}" "$selected_server_name" "$screen_session_name")"; else display_info "$(printf "${manage_server_start_attempt:-Попытка запуска '%s'}..." "$selected_server_name")"; (cd "$selected_server_path" && screen -L -Logfile "$selected_server_path/screen.log" -dmS "$screen_session_name" ./start.sh); sleep 1; if is_server_running "$screen_session_name"; then display_info "$(printf "${manage_server_started_successfully:-Сервер '%s' запущен в screen '%s'.}" "$selected_server_name" "$screen_session_name")"; else display_error "$(printf "${manage_server_start_failed:-Не удалось запустить '%s'.}" "$selected_server_name")"; fi; fi ;;
                2) stop_minecraft_server "$selected_server_name" "$screen_session_name" ;;
                3)
                    if is_server_running "$screen_session_name"; then
                        local user_command
                        read_input "$(printf "${manage_server_send_command_prompt:-Введите команду для '%s': }" "$selected_server_name")" user_command
                        screen -S "$screen_session_name" -X stuff "$user_command\n"
                        display_info "$(printf "${manage_server_command_sent:-Команда '%s' отправлена на '%s'.}" "$user_command" "$selected_server_name")"
                    else
                        display_error "$(printf "${manage_server_not_running_for_command:-Сервер '%s' не запущен.}" "$selected_server_name")"
                    fi
                    ;;
                4)
                    local latest_log_file="$selected_server_path/logs/latest.log"
                    if [ -f "$latest_log_file" ]; then
                        display_info "$(printf "${manage_server_viewing_log:-Просмотр logs/latest.log для '%s'...}" "$selected_server_name")"
                        if command -v less &>/dev/null; then
                            less "$latest_log_file"
                        elif command -v tail &>/dev/null; then
                             display_warning "${manage_server_less_not_found:-'less' не найден, исп. 'tail'.}"
                             tail -n 100 "$latest_log_file"
                             echo; display_info "(Конец вывода tail)"
                        else
                            cat "$latest_log_file"
                            echo; display_info "(Конец вывода cat)"
                        fi
                    else
                        display_error "$(printf "${manage_server_log_not_found:-logs/latest.log не найден для '%s'.}" "$selected_server_name")"
                    fi
                    ;;
                5) backup_minecraft_server "$selected_server_name" "$selected_server_path" "$screen_session_name" ;;
                6) delete_minecraft_server "$selected_server_name" "$selected_server_path" "$screen_session_name"; if [ $? -eq 0 ]; then continue; fi ;;
                7) ;;
                *) display_error "${error_invalid_choice:-Неверный выбор.}";;
            esac
        elif [[ "$server_idx" == "$back_option_num" || "$server_idx" == "0" ]]; then return;
        else display_error "${error_invalid_choice:-Неверный выбор.}"; fi
        if [[ "$action_choice" != "7" && ("$server_idx" -ge 1 && "$server_idx" -lt "$back_option_num") ]]; then read -n 1 -s -r -p "${press_any_key:-Нажмите любую клавишу...}"; fi
    done
}
main_menu() {
    while true; do
        clear; display_header "${menu_title:-Minecraft Server Installer}"
        echo "${menu_select_server_type:-Выберите действие или тип сервера:}"
        echo "--- Установка ---"
        echo "1) ${menu_option_paper:-Paper}"
        echo "2) ${menu_option_vanilla:-Vanilla}"
        echo "3) ${menu_option_fabric:-Fabric}"
        echo "4) ${menu_option_forge:-Forge}"
        echo "4.1) ${menu_option_neoforge:-NeoForge}
        echo "5 ${menu_option_purpur:-Purpur}"
        echo "--- Управление ---"
        echo "6) ${menu_option_manage_servers:-Управление серверами}"
        echo "7) ${menu_option_settings:-Настройки}"
        echo "--- Прочее ---"; echo "9) ${menu_option_exit:-Выход}"
        read_input "${prompt_choice:- > }" CHOICE
        case $CHOICE in
            1) source "$FUNCTIONS_DIR/install_paper.sh"; install_paper_server ;;
            2) source "$FUNCTIONS_DIR/install_vanilla.sh"; install_vanilla_server ;;
            3) source "$FUNCTIONS_DIR/install_fabric.sh"; install_fabric_server ;;
            4) source "$FUNCTIONS_DIR/install_forge.sh"; install_forge_server ;;
            5 source "$FUNCTIONS_DIR/install_purpur.sh"; install_purpur_server ;;
            4.1) source "$FUNCTIONS_DIR/install_neoforge.sh"; install_neoforge_server ;;
            6) manage_servers_menu ;;
            7) settings_menu ;;
            9) display_info "Выход из установщика."; exit 0 ;;
            *) display_error "${error_invalid_choice:-Неверный выбор. Пожалуйста, попробуйте снова.}" ;;
        esac
        if [[ "$CHOICE" != "9" && "$CHOICE" != "6" && "$CHOICE" != "7" ]]; then
            read -n 1 -s -r -p "${press_any_key:-Нажмите любую клавишу...}"
        fi
    done
}
initialize_application
check_dependencies
main_menu
