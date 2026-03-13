#!/usr/bin/env bash
set -euo pipefail

# This was translated from the original workflow via OpenAI, 27/02/2026
# =========
# Settings
# =========
PROJECT_DIR="/opt/jcodec"
PROJECT_NAME="jcodec"
GIN_JAR="/opt/gin/build/gin.jar"
MAVEN_HOME="/root/.sdkman/candidates/maven/current"
RESULTS_DIR="${PROJECT_DIR}/results"
TINYLOG_LEVEL="trace"

# LLM / model tag used in filenames + Gin args
LLM="gemma2:2b"
MODEL="${LLM}"

GINOPTION="${1:-}"  # Which Option to run the script on, this is so we run the profiler only once

cd "${PROJECT_DIR}"

# =====================
# 1) Profile the project
# =====================
case $GINOPTION in
    profile | PROFILE | prof | profiling)
        java -Dtinylog.level="${TINYLOG_LEVEL}" \
          -cp "${GIN_JAR}" \
          gin.util.Profiler \
          -r 20 \
          -mavenHome "${MAVEN_HOME}" \
          -p "${PROJECT_NAME}" \
          -d . \
          -o "${PROJECT_NAME}.Profiler_output.csv"

# ==========================
# 2) Masking Random Search
# ==========================
    random | Random | rand | RANDOM)
        mkdir -p "${RESULTS_DIR}"
        
        java -Dtinylog.level="${TINYLOG_LEVEL}" \
          -cp "${GIN_JAR}" \
          gin.util.RandomSampler \
          -j \
          -p "${PROJECT_NAME}" \
          -d . \
          -m "${PROJECT_NAME}.Profiler_output.csv" \
          -o "${RESULTS_DIR}/${PROJECT_NAME}.RandomSampler_1000_output.${MODEL}.csv" \
          -mavenHome "${MAVEN_HOME}" \
          -timeoutMS 10000 \
          -et gin.edit.llm.LLMMaskedStatement \
          -mt "${MODEL}" \
          -pt MASKED \
          -pn 1000 \
          &> "${RESULTS_DIR}/${PROJECT_NAME}.RandomSampler_COMBINED_1000_stderrstdout.${MODEL}.txt"

# =========================
# 3) Masking Local Search
# =========================
    local | Local | LOCAL)
        mkdir -p "${RESULTS_DIR}"
        
        java -Dtinylog.level="${TINYLOG_LEVEL}" \
          -cp "${GIN_JAR}" \
          gin.util.LocalSearchRuntime \
          -j \
          -p "${PROJECT_NAME}" \
          -d . \
          -m "${PROJECT_NAME}.Profiler_output.csv" \
          -o "${RESULTS_DIR}/${PROJECT_NAME}.LocalSearchRuntime_COMBINED_50_output.${MODEL}.csv" \
          -mavenHome "${MAVEN_HOME}" \
          -timeoutMS 10000 \
          -et gin.edit.llm.LLMMaskedStatement \
          -mt "${LLM}" \
          -pt MASKED \
          -in 100 \
          &> "${RESULTS_DIR}/${PROJECT_NAME}.LocalSearchRuntime_LLM_MASKED_50_stderrstdout.${MODEL}.txt"

# =========================
# 4) Local Search with PatchCat
# =========================
    LocalPatchCat | lpc | LPC |localpatchcat | LOCALPATCHCAT)
        mkdir -p "${RESULTS_DIR}"
        
        java -Dtinylog.level="${TINYLOG_LEVEL}" \
          -cp "${GIN_JAR}" \
          gin.util.LocalSearchRuntime \
          -j \
          -p "${PROJECT_NAME}" \
          -d . \
          -m "${PROJECT_NAME}.Profiler_output.csv" \
          -o "${RESULTS_DIR}/${PROJECT_NAME}.LocalSearchRuntime_COMBINED_50_output.${MODEL}.csv" \
          -mavenHome "${MAVEN_HOME}" \
          -timeoutMS 10000 \
          -et gin.edit.llm.LLMMaskedStatement \
          -mt "${LLM}" \
          -pc \
          -pt MASKED \
          -in 100 \
          &> "${RESULTS_DIR}/${PROJECT_NAME}.LocalSearchRuntime_LLM_MASKED_50_stderrstdout.${MODEL}.txt"  
    *)
        echo "Option is unknown"
    ;;
esac
