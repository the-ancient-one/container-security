#!/bin/bash
# --------------------------------------------------------------------------------------------
# Docker Security TestCases
#
# Checks for dozens of common best-practices around deploying Docker containers in production.
# --------------------------------------------------------------------------------------------

version='1.0'

##################### Global Variables #####################

# Regular expression pattern for the images and containers to look for
images_regx="csvs"  

# List of pre-requisite packages to check and install
# List of tools used in in making the script work. This will check and install only using brew else will error out.
packages=("hadolint" "trivy") 


##################### Functions #####################

# Function to print the device details and package version
function device_details(){

    # Get the OS details
    UNAME_MACHINE="$(/usr/bin/uname -m)"

    # Print Bash, Docker and docker-compose version
    echo -e "\n##> Bash version: $(bash --version | head -n 1) \n"

    echo -e "##> Docker version: $(docker version) \n"

    echo -e "##> docker-compose version: $(bash --version | head -n 1) \n"

    # Print the machine details
    if [[ "${UNAME_MACHINE}" == "arm64" ]]
    then
        echo "##> Hardware Details"
        system_profiler SPHardwareDataType  |egrep -E "Model Name|Model Identifier|Chip|Total Number of Cores|Memory|Hardware" | grep -v UUID
    else
    echo -e "Not a Apple Silicon macOS \n "
    fi
   
}

# Function to check if the Docker daemon is running
function check_docker_daemon() {
    if ! docker info >/dev/null 2>&1; then
        echo "Docker daemon is not running. Exiting..."
        exit 1
    fi
}

# Function to check and install pre-requisite packages
function pre_requisite_packages(){
    local packages=("$@")
    local installed_packages=()

    echo -e "\nChecking and installing packages from Brew...\n "

    # Iterate over the list of packages
    for package in "${packages[@]}"; do
        # Check if the package is installed
        if brew list --versions "$package" >/dev/null 2>&1; then
            echo "$package is already installed."
            installed_packages+=("$package")
        else
            # Install the package
            echo "Installing $package..."
            brew install "$package"
            installed_packages+=("$package")
        fi
    done

    # Print the list of installed packages
    echo -e "\nInstalled packages:"
    printf "%s\n" "${installed_packages[@]}"
}

# Function to check if DOCKER_CONTENT_TRUST variable is set for pulling trusted images
function check_variable() {
    if [[ -v $1 ]]; then
        echo "$1 is set."
    else
        echo "$1 is not set and recommend checking https://docs.docker.com/engine/security/trust/."
    fi
}

# Function to search for Docker images and their sizes
function search_docker_images() {
    # Check if a regex pattern is provided
    local regex="$1"
        echo "## Size ##"
    printf "%-30s | %-7s | %-70s \n" "Image" "Size" "Id/Digest(sha256)"
    echo "-------------------------------+---------+------------------------------------------------------------------------"
    docker images --no-trunc --format "{{.Repository}}:{{.Tag}} | {{.Size}} | {{.ID}}" | grep -i "$regex"
    echo ""
    
    echo "## Digest ##"
    printf "%-30s | %-70s\n" "Image" "Digest"
    echo "--------------------------------+------------------------------------------------------------------------"
    docker image ls --digests --format '{{.Repository}}:{{.Tag}} | {{.Digest}}' | egrep "rockylinux|mariadb|$regex"
}

# Function to lint Dockerfiles using hadolint
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

# Function to run Trivy scan on Docker images
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

# Function to check SecurityOpt options for Docker containers
function check_secopt() {
    echo -e "Scanning Docker conatiner for SecurityOpt options \n"
    echo "Container ID     | Seccomp Enabled | no-new-privileges Enabled | CgroupnsMode | Privileged"
    echo "------------------------------------------------------------------"
    # Iterate over Docker images and filter them based on regex
    for container_id in $(docker ps --format "{{.Names}}"); do
        if [[ "$container_id" =~ $images_regx ]]; then
            # Get the list of security options for the container
            local seccomp_enabled=$(docker inspect --format '{{ .HostConfig.SecurityOpt }}' "$container_id" | grep -c 'seccomp=')
            local no_new_privileges_enabled=$(docker inspect --format '{{ .HostConfig.SecurityOpt }}' "$container_id" | grep -c 'no-new-privileges=')
            local cgroup_ns_mode=$(docker inspect --format='{{.HostConfig.CgroupnsMode}}'  "$container_id")
            local privileged_flag=$(docker inspect --format='{{.HostConfig.Privileged}}'  "$container_id")

            # Print security options in table format
            printf "%-16s | %-15s | %-15s | %-15s | %-15s \n" "$container_id" "$(if [ "$seccomp_enabled" -gt 0 ]; then echo "Yes"; else echo "No"; fi)" "$(if [ "$no_new_privileges_enabled" -gt 0 ]; then echo "Yes"; else echo "No"; fi)" "$cgroup_ns_mode" "$privileged_flag"
        fi
    done
}

# Function to print Docker capability add and drop details for containers
function print_capability_details() {
    # Iterate over Docker images and filter them based on regex
    for container_id in $(docker ps --format "{{.Names}}"); do
        echo -e "\n##> Printing Docker capability add and drop details for container ID: $container_id"

        # Get the list of capabilities for the container
        cap_add=$(docker inspect --format='{{.HostConfig.CapAdd}}' "$container_id")
        cap_drop=$(docker inspect --format='{{.HostConfig.CapDrop}}' "$container_id")

        # Print capability details in table format
        echo ""
        echo "Capability Drop Details:"
        printf "%-30s | %-30s\n" "Container ID" "Capability"
        echo "--------------------------------+--------------------------------"
        for cap in ${cap_drop//[\"[\]]}; do
            printf "%-30s | %-30s\n" "$container_id" "$cap"
        done

        echo "Capability Add Details:"
        printf "%-30s | %-30s\n" "Container ID" "Capability"
        echo "--------------------------------+--------------------------------"
        for cap in ${cap_add//[\"[\]]}; do
            printf "%-30s | %-30s\n" "$container_id" "$cap"
        done
    done
}

# Function to check Docker container resource limits
function check_docker_stats_resources() {

    # Print table headers
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

# Function to check Docker container logs
function check_docker_container_logs() {
    local num_lines="${2:-10}"          
    # Iterate over Docker images and filter them based on regex
    for container_name in $(docker ps --format "{{.Names}}"); do
        echo -e "\n########################################################### "
        echo "Checking Docker container logs for : $container_name"
        docker logs --tail "$num_lines" "$container_name"
    done
}

# Function to validate Docker Compose configuration
function validate_compose_config() {
    local compose_file="$1"

    # Check if the Docker Compose file exists
    if [ ! -f "$compose_file" ]; then
        echo "Error: Docker Compose file $compose_file not found."
        return 1
    fi

    # Lint the Docker Compose file
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

# Function to check Docker volume binds
function check_volume_binds() {
    for container_id in $(docker ps --format "{{.Names}}"); do

        echo -e "\n##> Checking Docker Volume details for : $container_id \n"

        # Get the volume host binds in the specified format
        volume_binds=$(docker inspect --format='{{range .Mounts}}{{.Type}} | {{.Destination}} | {{.Mode}} | {{.RW}} | {{"\n"}}{{end}}' "$container_id")

        # Print volume host binds with space as the heading
        echo "Volume Host Binds:"
        printf "%-10s %-30s %-10s %-10s\n" "Type" "Destination" "Mode" "Read/Write"
        echo "------+--------------------------------+------------+------------"
        echo "$volume_binds"
    done
}

# Function to check Docker container healthcheck details
function health_check(){   

    # Print table headers
    printf "%-10s %-8s %-8s %-8s %-10s\n" "Conatiner" "Interval" "Timeout" "Retries" "Test CMD"
    echo "----------+--------+--------+--------+----------------------------------------"
    for container_id in $(docker ps --format "{{.Names}}"); do
        # Get the healthcheck details for the container
        healthcheck=$(docker inspect --format=' {{.Config.Healthcheck.Interval}} | {{.Config.Healthcheck.Timeout}} | {{.Config.Healthcheck.Retries}} | {{if .State.Health}} "{{range .Config.Healthcheck.Test}} {{.}}{{end}}"  {{"\n"}}{{end}}' "$container_id")
        # Print healthcheck details in table format
        echo "$container_id" "|" "$healthcheck"
    done
}

# Function to check Dockerfile for Linux user or password-related commands
function check_dockerfile_users_passwords() {
    local compose_file="$1"

    # Check if docker-compose.yml is provided
    if [ -z "$compose_file" ]; then
        echo "Error: docker-compose.yml not provided."
        return 1
    fi

    # Check if docker-compose.yml exists
    if [ ! -f "$compose_file" ]; then
        echo "Error: docker-compose.yml $compose_file not found."
        return 1
    fi

    # Extract Dockerfile paths from docker-compose.yml
    dockerfile_paths=$(docker-compose -f  "$compose_file" config | awk '/context:/ { print $2 }')

    # Check if any Dockerfile paths are found
    if [ -z "$dockerfile_paths" ]; then
        echo "Error: No Dockerfile paths found in docker-compose.yml."
        return 1
    fi

    # Iterate over Dockerfile paths and check for Linux user or password-related commands
    for path in $dockerfile_paths; do
        grep -Ei 'user|passwd|password|chpasswd' "$path/Dockerfile" >/dev/null
        if [ $? -eq 0 ]; then
            echo -e "\nLinux user or password-related commands found in Dockerfile: $(basename "$path")/Dockerfile\n"
        else
            echo -e "\nNo Linux user or password-related commands found in Dockerfile:$(basename "$path")/Dockerfile\n"
        fi
    done
}


########################################################### 
##################### Main Function #######################
###########################################################

# Main function to call all the functions
main(){
    local action="$1"

    case "$action" in
        "device" | "all" )
            echo -e " \n ########################################################### "
            echo -e " ############## Device and Package Version #################"
            echo -e " ###########################################################\n "
            echo -e "\n ## Print Device Details ######################################################### "
            device_details 

            echo -e "\n ## Dependent Tool Check Details (Please note this will check only for Brew) ######################################################### "
            pre_requisite_packages "${packages[@]}"
                           
            echo -e "\n ## Dockerd status check ######################################################### "
            check_docker_daemon
            echo "Docker daemon is running. Continuing with the script..."
            ;;  
        
        "compose" | "static" | "all")   
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

            echo -e " \n ## Dockerfile User/Password check #########################################################"
            check_dockerfile_users_passwords "../docker-compose.yml" # location of the docker-compose file          
            
            echo -e " \n ## Image Scan #########################################################\n "
            run_trivy_scan
             ;;

        "runtime" | "all")
            echo -e " \n ########################################################### "
            echo -e " #################### Runtime ##############################"
            echo -e " ###########################################################\n "

            echo -e " \n ## Checking SecurityOpt #########################################################\n "
            check_secopt

            echo -e " \n ## Checking Capabilities #########################################################\n "
            print_capability_details

            echo -e " \n ## Checking Container Resource #########################################################\n "
            check_docker_stats_resources

            echo -e " \n ## Checking Volume Permissions #########################################################\n "
            check_volume_binds

            echo -e " \n ## Checking Container Healthcheck Details #########################################################\n "
            health_check

            echo -e " \n ## Checking Container Logs #########################################################\n "
            check_docker_container_logs
            ;;
        *)
            echo "Invalid action: $action"
            echo "Usage: $0 [device | static | compose | runtime | all]"
            exit 1
            ;;
        
    esac
}

########################################################### 
################## Main Function Call #####################
###########################################################
# Call the main function with all the arguments
main "$@"