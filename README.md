# Minecraft Server Installer Script

A Bash script to easily install and manage Minecraft servers (PaperMC, Vanilla, Fabric, Forge, Purpur) on Linux or Termux.

## Features

- Install multiple server types with version selection  
- Auto-download server JARs and installers  
- Interactive setup for server.properties and JVM RAM settings  
- Manage servers: start/stop, send commands, view logs, backup, delete  
- Runs servers in detached `screen` sessions  
- Supports `.env` files for custom JVM args per server  
- Language support (English/Russian) and configurable defaults  

## Prerequisites

`bash`, `curl`, `jq`, `java (OpenJDK 21+)`, `screen`, `tar`, `ss` or `netstat`, `less` or `tail`

## Usage

1. Make script executable: `chmod +x installer.sh`  
2. Run: `./installer.sh`  
3. Follow menu prompts to install or manage servers
