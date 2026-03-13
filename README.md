# Quick Start

Build:
```sh
sudo docker build -t gin-builder .
```

Run:
```sh
sudo docker run -it -p 8888:8888 gin-builder
```

Run and mount config.ini:
```sh
sudo docker run -it -p 8888:8888 -v /path_to_folder/config.ini:/opt/config.ini gin-builder
```

Jupyter will be available at http://localhost:8888

To start ollama:
```
docker exec -it be9a3c1e27c6 ollama serve # be9a3c1e27c6 is the current container
```

To access the docker:
```
docker exec -it be9a3c1e27c6 /bin/bash
```

and then 
```
source /opt/venv/bin/activate
```
