sudo apt-get update
 
# Fix the users
sudo groupadd docker
newgrp docker
sudo usermod -aG docker $(whoami)
 
# Install docker
sudo apt install apt-transport-https curl gnupg-agent ca-certificates software-properties-common -y
sudo apt install docker.io
sudo systemctl stop docker
sudo systemctl stop docker.socket
sudo systemctl stop containerd
sudo systemctl start docker
 
docker --version
groups $(whoami)
sudo chmod 666 /var/run/docker.sock
docker run hello-world
 
echo ">> To build image run: docker build -t dockerfuzzer ."
sudo docker build --no-cache -t gin-builder .
echo ">> Starting Ollama Server."
sudo docker rm -f gin-builder 2>/dev/null || true
sudo docker run -d --name gin-builder -p 8888:8888 gin-builder:latest 
echo ">> Entering Docker container"
sudo docker exec -it gin-builder bash
