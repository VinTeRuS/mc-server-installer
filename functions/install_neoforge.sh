#!/bin/bash

install_neoforge() {
    echo "Установка NeoForge"
    echo "------------------"

    read -rp "Введите версию Minecraft: " mc_version
    read -rp "Введите версию NeoForge (например, 20.4.152): " neoforge_version

    echo "➤ Создание папки сервера..."
    mkdir -p "${mc_version}-neoforge"
    cd "${mc_version}-neoforge" || exit 1

    echo "➤ Скачивание установщика NeoForge..."
    curl -LO "https://maven.neoforged.net/releases/net/neoforged/neoforge/${neoforge_version}/neoforge-${neoforge_version}-installer.jar"
    if [ ! -f "neoforge-${neoforge_version}-installer.jar" ]; then
        echo "❌ Не удалось скачать установщик NeoForge!"
        exit 1
    fi

    echo "➤ Установка сервера..."
    java -jar "neoforge-${neoforge_version}-installer.jar" --installServer

    echo "✅ Установка завершена."
}
