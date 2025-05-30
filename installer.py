import os
import requests
import subprocess

def clear():
    os.system("cls" if os.name == "nt" else "clear")

def download_file(url, filename):
    response = requests.get(url)
    with open(filename, 'wb') as f:
        f.write(response.content)

def install_paper(version):
    url = f"https://api.papermc.io/v2/projects/paper/versions/{version}/builds"
    builds = requests.get(url).json()["builds"]
    build = builds[-1]["build"]
    jar_name = builds[-1]["downloads"]["application"]["name"]
    download_url = f"https://api.papermc.io/v2/projects/paper/versions/{version}/builds/{build}/downloads/{jar_name}"
    os.makedirs(f"servers/Paper-{version}", exist_ok=True)
    download_file(download_url, f"servers/Paper-{version}/server.jar")

def install_folia(version):
    url = f"https://api.papermc.io/v2/projects/folia/versions/{version}/builds"
    builds = requests.get(url).json()["builds"]
    build = builds[-1]["build"]
    jar_name = builds[-1]["downloads"]["application"]["name"]
    download_url = f"https://api.papermc.io/v2/projects/folia/versions/{version}/builds/{build}/downloads/{jar_name}"
    os.makedirs(f"servers/Folia-{version}", exist_ok=True)
    download_file(download_url, f"servers/Folia-{version}/server.jar")

def install_purpur(version):
    r = requests.get("https://api.purpurmc.org/v2/purpur")
    if version not in r.json()["versions"]:
        print("Version not supported by Purpur.")
        return
    latest_build = requests.get(f"https://api.purpurmc.org/v2/purpur/{version}").json()["builds"][-1]
    jar_url = f"https://api.purpurmc.org/v2/purpur/{version}/{latest_build}/download"
    os.makedirs(f"servers/Purpur-{version}", exist_ok=True)
    download_file(jar_url, f"servers/Purpur-{version}/server.jar")

def install_fabric(version):
    installer_meta = requests.get("https://meta.fabricmc.net/v2/versions/installer").json()[0]
    installer_version = installer_meta["version"]
    installer_url = f"https://maven.fabricmc.net/net/fabricmc/fabric-installer/{installer_version}/fabric-installer-{installer_version}.jar"
    installer_jar = "fabric-installer.jar"
    download_file(installer_url, installer_jar)
    target = f"servers/Fabric-{version}"
    os.makedirs(target, exist_ok=True)
    subprocess.run(["java", "-jar", installer_jar, "server", "-downloadMinecraft", "-mcversion", version, "-dir", target, "-noprofile"])
    os.remove(installer_jar)

def install_neoforge(version):  # Only NeoForge version, not MC version
    base_url = "https://maven.neoforged.net/releases/net/neoforged/neoforge"
    jar_name = f"neoforge-{version}-installer.jar"
    jar_url = f"{base_url}/{version}/{jar_name}"
    download_file(jar_url, jar_name)
    target = f"servers/NeoForge-{version}"
    os.makedirs(target, exist_ok=True)
    subprocess.run(["java", "-jar", jar_name, "--installServer", target])
    os.remove(jar_name)

def install_forge(version):  # Only Forge version, not MC version
    base_url = "https://maven.minecraftforge.net/net/minecraftforge/forge"
    jar_name = f"forge-{version}-installer.jar"
    jar_url = f"{base_url}/{version}/{jar_name}"
    download_file(jar_url, jar_name)
    target = f"servers/Forge-{version}"
    os.makedirs(target, exist_ok=True)
    subprocess.run(["java", "-jar", jar_name, "--installServer"], cwd=target)
    os.remove(jar_name)

def main_menu():
    while True:
        clear()
        print("PY-VERSION by WaterBucket | Original by VinTeRuS")
        print("\nMain Menu:")
        print("1. Install Minecraft Server")
        print("2. Manage Installed Servers")
        print("0. Exit")

        choice = input("\nChoose an option: ")

        if choice == "1":
            install_menu()
        elif choice == "2":
            manage_menu()
        elif choice == "0":
            break
        else:
            input("Invalid input. Press Enter to continue...")

def install_menu():
    while True:
        clear()
        print("Server Installation")
        print("1. Paper")
        print("2. Folia")
        print("3. Purpur")
        print("4. NeoForge")
        print("5. Fabric")
        print("6. Forge")
        print("0. Back")

        choice = input("\nSelect server type: ")

        if choice == "1":
            version = input("Enter Minecraft version (e.g. 1.20.4): ")
            install_paper(version)
        elif choice == "2":
            version = input("Enter Minecraft version (e.g. 1.20.4): ")
            install_folia(version)
        elif choice == "3":
            version = input("Enter Minecraft version (e.g. 1.20.4): ")
            install_purpur(version)
        elif choice == "4":
            version = input("Enter NeoForge version only (e.g. 21.1.172): ")
            install_neoforge(version)
        elif choice == "5":
            version = input("Enter Minecraft version (e.g. 1.20.4): ")
            install_fabric(version)
        elif choice == "6":
            version = input("Enter Forge version only (e.g. 1.20.4-47.2.0): ")
            install_forge(version)
        elif choice == "0":
            break
        else:
            input("Invalid input. Press Enter to continue...")

        input("Installation complete. Press Enter to return...")

def manage_menu():
    clear()
    if not os.path.exists("servers"):
        print("No servers installed yet.")
        input("Press Enter to return...")
        return

    servers = os.listdir("servers")
    if not servers:
        print("No servers found.")
        input("Press Enter to return...")
        return

    print("Installed Servers:")
    for i, s in enumerate(servers):
        print(f"{i + 1}. {s}")
    print("0. Back")

    choice = input("Select server to run: ")
    if choice == "0":
        return
    try:
        index = int(choice) - 1
        selected = servers[index]
        jar_path = os.path.join("servers", selected)
        files = os.listdir(jar_path)
        jar_file = next((f for f in files if f.endswith(".jar") and "installer" not in f), None)
        if not jar_file:
            print("No valid server jar found.")
        else:
            subprocess.run(["java", "-jar", jar_file, "nogui"], cwd=jar_path)
    except Exception as e:
        print("Error:", e)
        input("Press Enter to continue...")

if __name__ == "__main__":
    main_menu()
