# Cyber Security for Virtualisation Systems (UKFT CSVS 23 - PMA)
## University of Warwick 
### $${\color{red}(Read \space the \space following \space file \space carefully!)}$$ 

## Folder Structure

| File/Folder        | Description                                |
| ------------------ | ------------------------------------------ |
| `./`                | Root directory of the project.             |
| `.env`                | Environment file containing all the variables used in docker-compose.             |
| `./.git/`                | Directory containing git repo config and objects.             |
| `./.github/`                | Directory containing GitHub Actions and workflow realted to the repo.             |
| `./docker-compose.yml` | Docker Compose configuration file.         |
| `./webserver/`    | Directory containing application web artifactes(including Dockerfile).       |
| `./dbserver/`    | Directory containing application database artifactes(including Dockerfile).        |
| `./seccomp/`    | Directory containing seccomp profiles used by the containers.        |
| `./test-cases/`    | Directory conatining shell script for running test cases.        |
| `./kubectl_dashboard/`    | Directory conatining Kubernetes dashboard.        |
| `./kubectl_yml/`    | Directory conatining Kubernetes deployment yamls.        |

## Complete Folder Tree Structure

```
.
├── README.md
├── .env
├── .git/
├── .github
│   └── workflows
│       └── name: Docker_Compose.yml
├── VideoReadME.md
├── dbserver
│   ├── Dockerfile
│   ├── db_password.txt
│   ├── db_root_password.txt
│   ├── mysqld.cnf
│   └── sqlconfig
│       └── csvs23db.sql
├── docker-compose.yml
├── kubectl_dashboard
│   ├── cluster-rbac.yaml
│   └── service-acc.yaml
├── kubectl_yml
│   ├── csvs-dbserver-claim1-persistentvolumeclaim.yaml
│   ├── csvs-dbserver-deployment.yaml
│   ├── csvs-webserver-deployment.yaml
│   ├── csvs_dbserver-service.yaml
│   ├── csvs_webserver-service.yaml
│   ├── db-data-persistentvolumeclaim.yaml
│   └── db-password-secret.yaml
├── seccomp
│   ├── mariadb.json
│   └── webapp.json
├── test-cases
│   └── test-case.sh
└── webserver
    ├── Dockerfile
    ├── configfiles
    │   ├── docker-entrypoint.sh
    │   ├── nginx.conf
    │   ├── php-fpm.conf
    │   ├── php.ini
    │   └── www.conf
    └── webfiles
        ├── action.php
        ├── index.php
        └── style.css
```

> Important Note : The Image tag/version is controlled from .env file with respective app names. For Kubernetes this is hardcoded aganist images, as an improvment this should be converted to Helm charts with Templates, Charts and Values.

## Usage

1. Make sure you have Docker installed on your system.
2. Navigate to the project directory: `/`.
3. Run the following command to start the application using Docker Compose:

    ```bash
    docker-compose down # to build the images.
    docker-compose up --force-recreate  -d # to force-recreate the conatiners and services in detached mode.
    docker-compose down # teardown the containers and services.
    docker rmi -f $(docker images -a -q) # remove all the images for a fresh build.
    docker buildx prune -f # delete all cached layers from the machine.
    ```

    This will build and start the necessary containers and services defined in the `docker-compose.yml` file.
    > Note: it is recommeneded to run the commands in order.

4. To run the test cases, execute the following command:

    ```bash
    cd ./test-cases/
    bash test_case.sh # script written in Bash version: GNU bash, version 5.2.26(1)
    ```

    This will run the `test_case.sh` script and execute the predefined test cases.

## Github Action 

The GitHub Actions is a powerful automation tool integrated within GitHub, enabling to automate workflows directly within their repositories. It has been used for the creation of custom CI/CD pipelines, and build->pushing images to registry, streamlining development workflows and enhancing collaboration among development teams.

## Kubernetes

The Kubernetes is essential as it provides a scalable, flexible, and resilient platform for containerized applications. Kubernetes offers built-in features such as automated scaling, rolling updates, and service discovery, enabling seamless management of applications across hybrid and multi-cloud environments. However, this has only been added to demostrate future-proofing and cloud agnostic requriment of the application CI/CD ecosystem.

   ```bash
    cd ./kubectl_yml/
    #K8s Volumnes deployment     
    kubectl apply -f db-data-persistentvolumeclaim.yaml
    kubectl apply -f csvs-dbserver-claim1-persistentvolumeclaim.yaml
    #K8s Secret deployment  
    kubectl apply -f db-password-secret.yaml
    #K8s Service deployment  
    kubectl apply -f csvs_dbserver-service.yaml
    kubectl apply -f csvs_webserver-service.yaml
    #K8s Application deployment  
    kubectl apply -f csvs-webserver-deployment.yaml
    kubectl apply -f csvs-dbserver-deployment.yaml

    #K8s Dashboard deployment (for UI interface https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/,
    # alternative cli tool https://k9scli.io/) 
    kubectl apply -f service-acc.yaml
    kubectl apply -f cluster-rbac.yaml
   ```


Feel free to modify the folder structure and adapt the usage instructions according to your specific project needs.