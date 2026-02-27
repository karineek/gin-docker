# ---------------------------------------------------------------
# Base Image
# ---------------------------------------------------------------
FROM ubuntu:24.04

# ---------------------------------------------------------------
# Install system dependencies (including GPU detection tools)
# ---------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    zip \
    unzip \
    curl \
    git \
    ca-certificates \
    python3 \
    python3-venv \
    python3-dev \
    build-essential \
    pciutils \
    lshw \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------
# Install SDKMAN for Java, Maven, Gradle
# ---------------------------------------------------------------
RUN curl -s "https://get.sdkman.io" | bash

# Use bash login shell to enable SDKMAN in subsequent RUN commands
SHELL ["/bin/bash", "-lc"]

# Install Java, Gradle, Maven
RUN source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    sdk install java 21.0.9-oracle && \
    sdk install gradle 8.7 && \
    sdk install maven 3.9.11

# Set environment variables globally
ENV SDKMAN_DIR="/root/.sdkman"
ENV JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
ENV PATH="$JAVA_HOME/bin:$SDKMAN_DIR/candidates/maven/current/bin:$SDKMAN_DIR/candidates/gradle/current/bin:$PATH"

# ---------------------------------------------------------------
# Create logs directory
# ---------------------------------------------------------------
RUN mkdir -p /opt/logs

# ---------------------------------------------------------------
# Install Ollama (log output)
# ---------------------------------------------------------------
RUN curl -fsSL https://ollama.com/install.sh | tee /opt/logs/ollama_install.log | bash

# ---------------------------------------------------------------
# Clone gin-docker repo (for scripts, profiling data, notebook)
# ---------------------------------------------------------------
RUN git clone https://github.com/domsob/gin-docker.git /opt/gin-docker

# ---------------------------------------------------------------
# Copy config (local), pull script and test script (from git)
# ---------------------------------------------------------------
COPY config.ini /opt/config.ini
RUN cp /opt/gin-docker/pull_models.sh /opt/pull_models.sh && \
    chmod +x /opt/pull_models.sh && \
    cp /opt/gin-docker/test_ollama.py /opt/test_ollama.py

# ---------------------------------------------------------------
# Pull local models defined in config.ini during build
# ---------------------------------------------------------------
RUN bash /opt/pull_models.sh --build /opt/config.ini

# ---------------------------------------------------------------
# Clone repositories: GIN and JCodec
# ---------------------------------------------------------------
RUN git clone https://github.com/gintool/gin.git /opt/gin && \
    cd /opt/gin && git checkout llm

RUN git clone https://github.com/jcodec/jcodec.git /opt/jcodec && \
    cd /opt/jcodec && git checkout 7e52834
    
RUN git clone https://github.com/google/gson.git /opt/gson && \
    cd /opt/gson && git checkout gson-parent-2.13.2
    
RUN git clone https://github.com/junit-team/junit4.git /opt/junit4 && \
    cd /opt/junit4 && git checkout 71c33ce

RUN git clone https://github.com/apache/commons-net.git /opt/commons-net && \
    cd /opt/commons-net && git checkout rel/commons-net-3.10.0

RUN git clone https://github.com/karatelabs/karate.git /opt/karate && \
    cd /opt/karate && git checkout v1.4.1

# ---------------------------------------------------------------
# Replace settings in pom.xml's
# ---------------------------------------------------------------

# Change Java source/target version in pom.xml to 21 for Jcodec
RUN find /opt/jcodec -name pom.xml -exec \
      sed -i 's|<source>[ ]*1\.6[ ]*</source>|<source>21</source>|g' {} \; && \
    find /opt/jcodec -name pom.xml -exec \
      sed -i 's|<target>[ ]*1\.6[ ]*</target>|<target>21</target>|g' {} \;

# Remove line in Gson's pom.xml
RUN sed -i '/<argLine>--illegal-access=deny<\/argLine>/d' /opt/gson/pom.xml

# Commons Net: disable apache-rat-plugin
RUN sed -i '140a\
<plugin>\n\
  <groupId>org.apache.rat</groupId>\n\
  <artifactId>apache-rat-plugin</artifactId>\n\
  <configuration>\n\
    <skip>true</skip>\n\
  </configuration>\n\
</plugin>' /opt/commons-net/pom.xml

# ---------------------------------------------------------------
# Copy profiling data and notebook from gin-docker, then clean up
# ---------------------------------------------------------------
RUN cp /opt/gin-docker/profiling_data/jcodec.Profiler_output.csv /opt/jcodec/ && \
    cp /opt/gin-docker/profiling_data/commons-net.Profiler_output.csv /opt/commons-net/ && \
    cp /opt/gin-docker/profiling_data/gson.Profiler_output.csv /opt/gson/ && \
    cp /opt/gin-docker/profiling_data/junit4.Profiler_output.csv /opt/junit4/ && \
    cp /opt/gin-docker/profiling_data/karate-core.Profiler_output.csv /opt/karate/ && \
    cp /opt/gin-docker/gin_workflow.ipynb /opt/ && \
    rm -rf /opt/gin-docker

# ---------------------------------------------------------------
# Build GIN with log output
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/gin && ./gradlew clean build 2>&1 | tee /opt/logs/gin_build_output.txt"

# ---------------------------------------------------------------
# Build JCodec (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/jcodec && mvn clean compile 2>&1 | tee /opt/logs/jcodec_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/jcodec && mvn clean test 2>&1 | tee /opt/logs/jcodec_test.log"
    
# ---------------------------------------------------------------
# Build Gson (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/gson && mvn clean compile 2>&1 | tee /opt/logs/gson_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/gson && mvn clean test 2>&1 | tee /opt/logs/gson_test.log"

# ---------------------------------------------------------------
# Build JUnit4 (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/junit4 && mvn clean compile 2>&1 | tee /opt/logs/junit4_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/junit4 && mvn clean test 2>&1 | tee /opt/logs/junit4_test.log"

# ---------------------------------------------------------------
# Build Commons-Net (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/commons-net && mvn clean compile 2>&1 | tee /opt/logs/commons-net_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/commons-net && mvn clean test 2>&1 | tee /opt/logs/commons-net_test.log"

# ---------------------------------------------------------------
# Build Karate (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/karate/karate-core && mvn clean compile 2>&1 | tee /opt/logs/karate_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/karate/karate-core && mvn clean test 2>&1 | tee /opt/logs/karate_test.log"

# ---------------------------------------------------------------
# Create Python virtual environment and install Jupyter
# ---------------------------------------------------------------
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --upgrade pip setuptools wheel && \
    pip install notebook requests

# ---------------------------------------------------------------
# Expose Jupyter port
# ---------------------------------------------------------------
EXPOSE 8888
WORKDIR /opt

# ---------------------------------------------------------------
# Start Ollama, pull new models, run test, then start Jupyter
# ---------------------------------------------------------------
CMD bash -lc "\
    mkdir -p /opt/logs && \
    echo 'Starting Ollama server...' && \
    ollama serve > /opt/logs/ollama_serve.log 2>&1 & \
    sleep 5 && \
    echo 'Checking for new models to pull...' && \
    bash /opt/pull_models.sh --runtime /opt/config.ini 2>&1 | tee /opt/logs/model_pull.log && \
    echo 'Running Ollama test...' && \
    python3 /opt/test_ollama.py 2>&1 | tee /opt/logs/ollama_test.log && \
    echo 'Starting Jupyter Notebook...' && \
    jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.disable_check_xsrf=True --notebook-dir=/opt"
