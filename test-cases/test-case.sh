#!/bin/bash
# --------------------------------------------------------------------------------------------
# Docker Security TestCases
#
# Checks for dozens of common best-practices around deploying Docker containers in production.
# --------------------------------------------------------------------------------------------

version='1.0'

images_regx="csvs"

function device_details(){

    UNAME_MACHINE="$(/usr/bin/uname -m)"

    if [[ "${UNAME_MACHINE}" == "arm64" ]]
    then
        system_profiler SPHardwareDataType  |egrep -E "Model Name|Model Identifier|Chip|Total Number of Cores|Memory|Hardware" | grep -v UUID
    else
    echo -e "Not a macOS \n "
    fi
   
}

function check_docker_daemon() {
    if ! docker info >/dev/null 2>&1; then
        echo "Docker daemon is not running. Exiting..."
        exit 1
    fi
}

function check_package() {
    echo "Checking if the $1 package is installed "
    if which "$1" >/dev/null 2>&1; then
        echo -e "$1 package is installed. \n"
        return 1
    else
        echo -e "$1 package is not installed. \n"
        return 0
    fi
}

function check_variable() {
    if [[ -v $1 ]]; then
        echo "$1 is set."
    else
        echo "$1 is not set and recommend checking https://docs.docker.com/engine/security/trust/."
    fi
}

function search_docker_images() {
    local regex="$1"
    echo -e "## Size ####### "
    docker images --format "{{.Repository}}:{{.Tag}} - {{.Size}}" |grep -i "$regex"
    echo -e "## Digest ####### "
    docker image ls --digests --format '{{.Repository}}:{{.Tag}} - {{.Digest}}' | egrep "rockylinux|mariadb|$regex"
}

function run_trivy_scan() {
        echo -e "Scanning Docker images vulnerabilities, misconfiguration and secrets \n"

        # Iterate over Docker images and filter them based on regex
        for image in $(docker images --format "{{.Repository}}:{{.Tag}}"); do
            if [[ "$image" =~ $images_regx ]]; then
                echo -e "\n Scanning Docker images secrets and vulnerabilities(only HIGH,CRITICAL): $image \n"
                trivy image --ignore-unfixed --severity HIGH,CRITICAL "$image"
                echo -e "\n Scanning Docker images  misconfiguration: $image \n"
                trivy image --scanners misconfig "$image"

            fi
        done
}

function check_secopt() {
    echo -e "Scanning Docker conatiner for SecurityOpt options \n"
    echo "Container ID     | Seccomp Enabled | no-new-privileges Enabled"
    echo "------------------------------------------------------------------"
    # Iterate over Docker images and filter them based on regex
    for container_id in $(docker ps --format "{{.Names}}"); do
        if [[ "$container_id" =~ $images_regx ]]; then
            local seccomp_enabled=$(docker inspect --format '{{ .HostConfig.SecurityOpt }}' "$container_id" | grep -c 'seccomp=')
            local no_new_privileges_enabled=$(docker inspect --format '{{ .HostConfig.SecurityOpt }}' "$container_id" | grep -c 'no-new-privileges=')
            printf "%-16s | %-15s | %-24s\n" "$container_id" "$(if [ "$seccomp_enabled" -gt 0 ]; then echo "Yes"; else echo "No"; fi)" "$(if [ "$no_new_privileges_enabled" -gt 0 ]; then echo "Yes"; else echo "No"; fi)"
        fi
    done
}


function check_docker_stats_resources() {
    echo "Checking Docker container resource limits..."
    printf "%-15s | %-25s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s\n" "Container ID" "Name" "CPU Usage" "Memory Usage" "Memory Percentage" "Network I/O" "Block I/O" "PIDs"

    # Get container IDs of running containers
    container_ids=$(docker ps -q)

    # Loop through each container
    for container_id in $container_ids; do
        # Extract resource limits using docker stats
        stats_output=$(docker stats --no-stream --format "{{.ID}},{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}},{{.PIDs}}" "$container_id")
        
        # Parse the stats output
        IFS=',' read -r id name cpu mem_usage mem_perc net_io block_io pids <<< "$stats_output"
        
        # Print container resource limits
        printf "%-15s | %-25s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s\n" "$id" "$name" "$cpu" "$mem_usage" "$mem_perc" "$net_io" "$block_io" "$pids"
    done
}

main(){
    echo -e "\n ## Print Device Details ######################################################### "
    device_details 
    
    echo -e "\n ## Dockerd status check ######################################################### "
    check_docker_daemon
    echo "Docker daemon is running. Continuing with the script..."
    
    echo -e "\n ## Trusted Repo Pull ######################################################### "

    echo -e "Checking if the DOCKER_CONTENT_TRUST variable is set in the environment \n"
    check_variable DOCKER_CONTENT_TRUST

    echo -e " \n ## Image Stat check #########################################################"
    echo -e " \n Checking the size and digest of the web and database images \n"
    search_docker_images $images_regx

    echo -e " \n ## Image Scan #########################################################\n "
    run_trivy_scan

    echo -e " \n ########################################################### "
    echo -e " #################### Runtime ##############################"
    echo -e " ###########################################################\n "

    echo -e " \n ## Checking SecurityOpt #########################################################\n "
    check_secopt

    echo -e " \n ## Checking Resource Limits #########################################################\n "
    check_docker_stats_resources
}

main "$@"