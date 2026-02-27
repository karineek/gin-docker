"""
Ollama Test Script
  - Tests local Ollama server health
  - Auto-detects installed models and uses the smallest one
  - Optionally tests cloud models via ollama.com API

Config: config.ini (same directory or /opt/config.ini)
"""
import requests
import json
import sys
import os
import configparser
from pathlib import Path

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------
def load_config():
    """Load config.ini from script directory or /opt/."""
    cfg = configparser.ConfigParser()
    candidates = [
        Path(__file__).parent / "config.ini",
        Path("/opt/config.ini"),
    ]
    for p in candidates:
        if p.exists():
            cfg.read(p)
            print(f"[INFO] Config loaded from {p}")
            return cfg
    print("[INFO] No config.ini found, using defaults.")
    return cfg


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def get_local_url(cfg):
    return cfg.get("ollama", "local_url", fallback="http://localhost:11434")


def parse_size(size_val):
    """Parse a model size value — could be int (bytes) or string like '1.6 GB'."""
    if isinstance(size_val, (int, float)):
        return int(size_val)
    if isinstance(size_val, str):
        s = size_val.strip().upper()
        multipliers = {"B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}
        for suffix, mult in sorted(multipliers.items(), key=lambda x: -len(x[0])):
            if s.endswith(suffix):
                try:
                    return int(float(s[: -len(suffix)].strip()) * mult)
                except ValueError:
                    pass
    return float("inf")


def pick_smallest_model(models):
    """Return the model entry with the smallest size. Skips cloud models
    (size often '-' or 0) unless they are the only ones available."""
    local = []
    cloud = []
    for m in models:
        name = m.get("name", m.get("model", ""))
        raw_size = m.get("size", 0)
        size = parse_size(raw_size)
        entry = {"name": name, "size": size, "raw": m}
        if "cloud" in name.lower() or size == 0 or raw_size == "-":
            cloud.append(entry)
        else:
            local.append(entry)

    pool = local if local else cloud
    if not pool:
        return None
    pool.sort(key=lambda x: x["size"])
    return pool[0]


def fmt_size(b):
    """Format bytes to human-readable."""
    if b == 0 or b == float("inf"):
        return "cloud/unknown"
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if abs(b) < 1024:
            return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} PB"


# ---------------------------------------------------------------------------
# Test functions
# ---------------------------------------------------------------------------
def test_ollama_health(base_url):
    """Check if Ollama server is reachable."""
    try:
        resp = requests.get(f"{base_url}/", timeout=10)
        if resp.status_code == 200:
            print(f"[OK] Ollama server is running at {base_url}")
            return True
        else:
            print(f"[FAIL] Ollama returned status {resp.status_code}")
            return False
    except requests.ConnectionError:
        print(f"[FAIL] Cannot connect to Ollama server at {base_url}")
        return False


def test_list_models(base_url):
    """List available models and return them."""
    resp = requests.get(f"{base_url}/api/tags", timeout=10)
    data = resp.json()
    models = data.get("models", [])
    names = [m.get("name", m.get("model", "?")) for m in models]
    print(f"[OK] Available models ({len(models)}): {names}")
    return models


def test_generate_local(base_url, model_name, prompt, timeout_sec):
    """Send a prompt to a local model via the Ollama REST API."""
    payload = {
        "model": model_name,
        "prompt": prompt,
        "stream": False,
    }
    print(f"[...] Sending test prompt to {model_name} ...")
    resp = requests.post(
        f"{base_url}/api/generate", json=payload, timeout=timeout_sec
    )
    result = resp.json()
    text = result.get("response", "")
    print(f"[OK] Model response: {text.strip()}")
    return bool(text)


def test_cloud_model(cfg):
    """Test a cloud model via the ollama.com direct API (optional).

    This uses the direct Cloud API with an API key.
    Cloud models pulled via 'ollama signin' + 'ollama pull <model>:cloud'
    appear in the local model list and are tested automatically above.
    """
    api_key = cfg.get("ollama", "cloud_api_key", fallback="").strip()
    cloud_url = cfg.get("ollama", "cloud_url", fallback="").strip()
    cloud_model = cfg.get("ollama", "cloud_model", fallback="").strip()

    if not api_key or not cloud_model:
        print("[SKIP] Cloud API test — no cloud_api_key / cloud_model in config.ini")
        return None  # skipped, not failed

    prompt = cfg.get("test", "prompt", fallback="Say hello in one sentence.")
    timeout_sec = cfg.getint("test", "timeout", fallback=120)

    if not cloud_url:
        cloud_url = "https://ollama.com"

    print(f"[...] Testing cloud model {cloud_model} via {cloud_url} ...")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": cloud_model,
        "prompt": prompt,
        "stream": False,
    }
    try:
        resp = requests.post(
            f"{cloud_url}/api/generate",
            json=payload,
            headers=headers,
            timeout=timeout_sec,
        )
        if resp.status_code == 401:
            print("[FAIL] Cloud API: authentication failed (401). Check your API key.")
            return False
        resp.raise_for_status()
        result = resp.json()
        text = result.get("response", "")
        print(f"[OK] Cloud model response: {text.strip()}")
        return bool(text)
    except requests.exceptions.RequestException as e:
        print(f"[FAIL] Cloud API error: {e}")
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    cfg = load_config()
    base_url = get_local_url(cfg)
    prompt = cfg.get("test", "prompt", fallback="What is 2+2? Answer in one short sentence.")
    timeout_sec = cfg.getint("test", "timeout", fallback=120)

    print("=" * 60)
    print("  OLLAMA TEST SCRIPT")
    print("=" * 60)

    passed = 0
    total = 0

    # --- Test 1: Health ---
    total += 1
    if test_ollama_health(base_url):
        passed += 1
    else:
        print("Ollama server not reachable. Aborting.")
        sys.exit(1)

    # --- Test 2: List models ---
    models = test_list_models(base_url)

    # --- Test 3: Generate with smallest local model (only if models exist) ---
    if models:
        total += 1
        smallest = pick_smallest_model(models)
        if smallest:
            print(f"[INFO] Smallest model: {smallest['name']} ({fmt_size(smallest['size'])})")
            if test_generate_local(base_url, smallest["name"], prompt, timeout_sec):
                passed += 1
        else:
            print("[FAIL] Could not determine a model to test.")
    else:
        print("[SKIP] No local models installed — skipping local generation test.")

    # --- Test 4 (optional): Cloud model via direct API ---
    cloud_result = test_cloud_model(cfg)
    if cloud_result is not None:
        total += 1
        if cloud_result:
            passed += 1

    # --- Summary ---
    print("=" * 60)
    print(f"  RESULT: {passed}/{total} tests passed")
    print("=" * 60)
    sys.exit(0 if passed == total else 1)
