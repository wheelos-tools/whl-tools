# Simple HTTP File Server

A simple, containerized HTTP server for sharing files on a local network, powered by Nginx and Docker Compose.

This setup provides a quick and reliable way to expose a local directory over HTTP. The shared directory is mounted in read-only mode for security.

## Prerequisites

Before you begin, ensure you have the following installed on your Ubuntu system:
*   [Docker](https://docs.docker.com/engine/install/ubuntu/)
*   [Docker Compose](https://docs.docker.com/compose/install/)

You can install them with the following commands:
```bash
# Update package list
sudo apt update

# Install Docker and Docker Compose
sudo apt install docker.io docker-compose -y

# Start and enable Docker service
sudo systemctl start docker
sudo systemctl enable docker
```

## Setup

1.  **Create the Shared Directory**: This is the folder where you will place the files you want to share. The server is configured to use a directory named `share` in the same location as this `README.md` file.

    ```bash
    mkdir -p ./share
    ```

## Usage

All commands should be run from the directory containing the `docker-compose.yml` file.

#### Start the Server
To start the server in the background (detached mode):
```bash
docker-compose up -d
```

#### Check Server Status
To see the running container, its status, and mapped ports:
```bash
docker-compose ps
```

#### View Logs
To view the real-time logs from the Nginx server (useful for debugging):
```bash
# Use -f to follow the log output. Press Ctrl+C to exit.
docker-compose logs -f
```

#### Stop the Server
To stop the running container without removing it:
```bash
docker-compose stop
```

#### Restart the Server
To restart a stopped container:
```bash
docker-compose start
```

#### Stop and Remove the Server
To stop the server and remove the container, network, and volumes defined in the `docker-compose.yml`:
```bash
docker-compose down
```

## Accessing the Files

1.  **Find Your Server's IP Address**:
    ```bash
    hostname -I | awk '{print $1}'
    ```
    Let's assume the IP address is `192.168.1.100`.

2.  **Access via Browser**: Open a web browser on any device in the same network and navigate to:
    `http://192.168.1.100:8080`

3.  **Access via `wget`**: You can download files from another machine on the network using `wget`:
    ```bash
    wget http://192.168.1.100:8080/test.txt
    ```
```
