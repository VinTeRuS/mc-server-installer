#!/bin/bash
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
_log_message() {
    local type="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    if [ -n "$LOG_FILE" ] && [ -w "$(dirname "$LOG_FILE")" ] ; then
        echo "[$timestamp] [$type] $message" >> "$LOG_FILE"
    fi
}
display_header() {
    echo -e "${COLOR_CYAN}"
    echo "============================================"
    local text_to_display="${1:-Missing Header}"
    local text_width=${#text_to_display}
    local term_width=$(tput cols 2>/dev/null || echo 44)
    local padding=$(( (term_width - text_width) / 2 ))
    [[ $padding -lt 0 ]] && padding=0
    printf "%*s%s\n" $padding "" "$text_to_display"
    echo "============================================"
    echo -e "${COLOR_RESET}"
}
display_info() {
    local message="$1"
    echo -e "${COLOR_GREEN}[INFO] $message${COLOR_RESET}"
    _log_message "INFO" "$message"
}
display_warning() {
    local message="$1"
    echo -e "${COLOR_YELLOW}[WARN] $message${COLOR_RESET}"
    _log_message "WARN" "$message"
}
display_error() {
    local message="$1"
    echo -e "${COLOR_RED}[ERROR] $message${COLOR_RESET}"
    _log_message "ERROR" "$message"
}
read_input() {
    local prompt="$1"
    local var_name="$2"
    echo -n -e "${COLOR_BLUE}${prompt}${COLOR_RESET}"
    read -r "$var_name"
}
