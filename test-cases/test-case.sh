#!/bin/bash
# --------------------------------------------------------------------------------------------
# Docker Security TestCases
#
# Checks for dozens of common best-practices around deploying Docker containers in production.
# --------------------------------------------------------------------------------------------

version='1.0'

##################### Variables #####################
images_regx="csvs"


##################### Functions #####################

function device_details(){

    UNAME_MACHINE="$(/usr/bin/uname -m)"

    echo -e "Bash version: $(bash --version | head -n 1) \n"

    if [[ "${UNAME_MACHINE}" == "arm64" ]]
    then
        system_profiler SPHardwareDataType  |egrep -E "Model Name|Model Identifier|Chip|Total Number of Cores|Memory|Hardware" | grep -v UUID
    else
    echo -e "Not a Apple Silicon macOS \n "
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

function pre_requisite(){
    #the packages from brew and other things will go here.
    echo "TO DO the function"
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
        echo "## Size ##"
    printf "%-30s | %-30s\n" "Image" "Size"
    echo "--------------------------------+--------------------------------"
    docker images --format "{{.Repository}}:{{.Tag}} | {{.Size}}" | grep -i "$regex"
    echo ""
    
    echo "## Digest ##"
    printf "%-30s | %-70s\n" "Image" "Digest"
    echo "--------------------------------+------------------------------------------------------------------------"
    docker image ls --digests --format '{{.Repository}}:{{.Tag}} | {{.Digest}}' | egrep "rockylinux|mariadb|$regex"
}

function lint_dockerfiles() {
    local search_dir="../"

    # Find all Dockerfiles in the specified directory and subdirectories
    dockerfiles=$(find "$search_dir" -type f -name Dockerfile)

    # Check if any Dockerfiles were found
    if [ -z "$dockerfiles" ]; then
        echo "No Dockerfiles found in $search_dir or its subdirectories."
        return
    fi

    # Loop through each Dockerfile and lint it using hadolint
    for dockerfile in $dockerfiles; do
        echo "Linting Dockerfile: $dockerfile"
        hadolint "$dockerfile"
        echo "---"
    done
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
    echo "Container ID     | Seccomp Enabled | no-new-privileges Enabled | CgroupnsMode"
    echo "------------------------------------------------------------------"
    # Iterate over Docker images and filter them based on regex
    for container_id in $(docker ps --format "{{.Names}}"); do
        if [[ "$container_id" =~ $images_regx ]]; then
            local seccomp_enabled=$(docker inspect --format '{{ .HostConfig.SecurityOpt }}' "$container_id" | grep -c 'seccomp=')
            local no_new_privileges_enabled=$(docker inspect --format '{{ .HostConfig.SecurityOpt }}' "$container_id" | grep -c 'no-new-privileges=')
            local cgroup_ns_mode=$(docker inspect --format='{{.HostConfig.CgroupnsMode}}'  "$container_id")
            printf "%-16s | %-15s | %-15s | %-15s \n" "$container_id" "$(if [ "$seccomp_enabled" -gt 0 ]; then echo "Yes"; else echo "No"; fi)" "$(if [ "$no_new_privileges_enabled" -gt 0 ]; then echo "Yes"; else echo "No"; fi)" "$cgroup_ns_mode"
        fi
    done
}

function print_capability_details() {
    for container_id in $(docker ps --format "{{.Names}}"); do
        echo -e "\n##> Printing Docker capability add and drop details for container ID: $container_id"
        # Get the list of capabilities for the container
        cap_add=$(docker inspect --format='{{.HostConfig.CapAdd}}' "$container_id")
        cap_drop=$(docker inspect --format='{{.HostConfig.CapDrop}}' "$container_id")

        # Print capability details in table format
        echo "Capability Add Details:"
        printf "%-30s | %-30s\n" "Container ID" "Capability"
        echo "--------------------------------+--------------------------------"
        for cap in ${cap_add//[\"[\]]}; do
            printf "%-30s | %-30s\n" "$container_id" "$cap"
        done

        echo ""
        echo "Capability Drop Details:"
        printf "%-30s | %-30s\n" "Container ID" "Capability"
        echo "--------------------------------+--------------------------------"
        for cap in ${cap_drop//[\"[\]]}; do
            printf "%-30s | %-30s\n" "$container_id" "$cap"
        done
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

function check_docker_container_logs() {
    local num_lines="${2:-10}"          
    # Iterate over Docker images and filter them based on regex
    for container_name in $(docker ps --format "{{.Names}}"); do
        echo -e "\n########################################################### "
        echo "Checking Docker container logs for : $container_name"
        docker logs --tail "$num_lines" "$container_name"
    done
}

function validate_compose_config() {
    local compose_file="$1"

    # Check if the Docker Compose file exists
    if [ ! -f "$compose_file" ]; then
        echo "Error: Docker Compose file $compose_file not found."
        return 1
    fi

    echo "Docker-compose configuration linting: "
    docker-compose -f $compose_file config --quiet && printf "OK\n" || printf "ERROR\n"

    echo -e "\n Validating container configuration from Docker Compose file: $compose_file"

    # Print table headers
    printf "%-20s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s\n" "Service" "Health Check" "Logging" "Resource Limits" "CPU Limits (%)" "Memory Limits (MB)" "PID Limits"
    echo "-----------------------------------------------+-----------------+-----------------+-----------------+-----------------+-----------------"

    # Parse the Docker Compose file and validate each service
    services=$(docker-compose -f "$compose_file" config --services)
    for service in $services; do
        # Check for health check
        healthcheck=$(docker-compose -f "$compose_file" config "$service" | grep -c "healthcheck:")
        # Check for logging configuration
        logging=$(docker-compose -f "$compose_file" config "$service" | grep -c "logging:")
        # Check for resource limits
        resources=$(docker-compose -f "$compose_file" config "$service" | grep -c "resources:")
        # Check for Sub resource limits 
        cpu_limits=$(docker-compose -f "$compose_file" config "$service" | grep "cpus:"| tail -n 1 | awk '{print $NF}')
        memory_limits=$(docker-compose -f "$compose_file" config "$service" | grep "memory:"| tail -n 1 | awk '{print $NF}')
        pid_limits=$(docker-compose -f "$compose_file" config "$service" | grep "pids:"| tail -n 1 | awk '{print $NF}')

        # Print service information in table format
       printf "%-20s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s\n" "$service" "$(if [ "$healthcheck" -gt 0 ]; then echo "Defined"; else echo "Not Defined"; fi)" "$(if [ "$logging" -gt 0 ]; then echo "Defined"; else echo "Not Defined"; fi)" "$(if [ "$resources" -gt 0 ]; then echo "Defined"; else echo "Not Defined"; fi)" "$(if [[ -v cpu_limits ]]; then echo "${cpu_limits//\"/}"; else echo "Not Defined"; fi)" "$(if [[ -v memory_limits ]]; then echo "${memory_limits//\"/} / 1048576" | bc; else echo "Not Defined"; fi)" "$(if [[ -v pid_limits ]]; then echo "$pid_limits"; else echo "Not Defined"; fi)"
    done
}


########################################################### 
##################### Main Function #######################
###########################################################

main(){
    echo -e "\n ## Print Device Details ######################################################### "
    device_details 
    
    echo -e "\n ## Dockerd status check ######################################################### "
    check_docker_daemon
    echo "Docker daemon is running. Continuing with the script..."

    echo -e " \n ########################################################### "
    echo -e " #################### Docker-compose #######################"
    echo -e " ###########################################################\n "
    echo -e "Checking docker-compose configuration details \n"
    validate_compose_config "../docker-compose.yml" # location of the docker-compose file 

    echo -e " \n \n ########################################################### "
    echo -e " #################### Static ###############################"
    echo -e " ###########################################################\n "
    
    echo -e "\n ## Trusted Repo Pull ######################################################### "
    echo -e "Checking if the DOCKER_CONTENT_TRUST variable is set in the environment \n"
    check_variable DOCKER_CONTENT_TRUST 

    echo -e " \n ## Image Stat check #########################################################"
    echo -e " \n Checking the size and digest of the web and database images \n"
    search_docker_images $images_regx # Variable declared in the top section

    echo -e " \n ## Dockerfile lint check #########################################################"
    lint_dockerfiles

    echo -e " \n ## Image Scan #########################################################\n "
    run_trivy_scan

    echo -e " \n ########################################################### "
    echo -e " #################### Runtime ##############################"
    echo -e " ###########################################################\n "

    echo -e " \n ## Checking SecurityOpt #########################################################\n "
    check_secopt

    echo -e " \n ## Checking Capabilities #########################################################\n "
    print_capability_details

    echo -e " \n ## Checking Container Resource #########################################################\n "
    check_docker_stats_resources

    echo -e " \n ## Checking Container Logs #########################################################\n "
    check_docker_container_logs
}

########################################################### 
################## Main Function Call #####################
###########################################################

main "$@"