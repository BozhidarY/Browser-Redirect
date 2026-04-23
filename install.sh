#!/bin/bash
set -e

HOST_NAME="com.browser.redirect"
EXTENSION_ID="${1}"
INSTALL_DIR="${2:-$HOME/.browser-redirect}"
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

if [ -z "$EXTENSION_ID" ]; then
    echo "Usage: curl -sL <url> | bash -s <extension-id>"
    exit 1
fi

# Reject macOS TCC-protected directories (Chrome can't execute from them)
if [ "$(uname -s)" = "Darwin" ]; then
    RESOLVED_DIR="$(cd "$(dirname "$INSTALL_DIR")" 2>/dev/null && pwd)/$(basename "$INSTALL_DIR")" 2>/dev/null || RESOLVED_DIR="$INSTALL_DIR"
    case "$RESOLVED_DIR" in
        "$HOME/Downloads"*|"$HOME/Documents"*|"$HOME/Desktop"*)
            echo "Error: Cannot install in Downloads, Documents, or Desktop."
            echo "macOS blocks Chrome from running scripts in these folders."
            echo "Use the default path or another location (e.g. \$HOME/.browser-redirect)."
            exit 1
            ;;
    esac
fi

mkdir -p "$INSTALL_DIR"

# ---- Write native host script inline ----
cat > "$INSTALL_DIR/host.py" << 'PYEOF'
#!/usr/bin/env python3
import json
import os
import platform
import struct
import subprocess
import sys

BROWSER_MAP = {
    "Darwin": {
        "brave": "Brave Browser",
        "firefox": "Firefox",
        "safari": "Safari",
        "edge": "Microsoft Edge",
        "chrome": "Google Chrome",
    },
    "Linux": {
        "brave": "brave-browser",
        "firefox": "firefox",
        "edge": "microsoft-edge",
        "chrome": "google-chrome",
    },
    "Windows": {
        "brave": "brave.exe",
        "firefox": "firefox.exe",
        "edge": "msedge.exe",
        "chrome": "chrome.exe",
    },
}


def read_message():
    raw = sys.stdin.buffer.read(4)
    if len(raw) < 4:
        return None
    length = struct.unpack("=I", raw)[0]
    data = sys.stdin.buffer.read(length)
    return json.loads(data)


def send_message(msg):
    encoded = json.dumps(msg).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("=I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def resolve_app_name(browser_key):
    system = platform.system()
    browsers = BROWSER_MAP.get(system, {})
    if browser_key.startswith("custom:"):
        return browser_key[7:]
    return browsers.get(browser_key, browser_key)


def find_browser_path_windows(app_name):
    """Find browser exe path on Windows via the App Paths registry."""
    try:
        import winreg
        exe = app_name if app_name.endswith(".exe") else app_name + ".exe"
        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            rf"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{exe}",
        )
        path, _ = winreg.QueryValueEx(key, "")
        winreg.CloseKey(key)
        if os.path.isfile(path):
            return path
    except Exception:
        pass
    return None


def check_browser_installed(browser_key):
    app_name = resolve_app_name(browser_key)
    system = platform.system()

    try:
        if system == "Darwin":
            result = subprocess.run(
                ["osascript", "-e", f'id of application "{app_name}"'],
                capture_output=True, text=True,
            )
            return result.returncode == 0
        elif system == "Linux":
            result = subprocess.run(
                ["which", app_name],
                capture_output=True,
            )
            return result.returncode == 0
        elif system == "Windows":
            return find_browser_path_windows(app_name) is not None
    except Exception:
        pass

    return False


def open_in_browser(browser_key, url):
    app_name = resolve_app_name(browser_key)
    system = platform.system()

    if system == "Darwin":
        subprocess.Popen(["open", "-a", app_name, url])
    elif system == "Linux":
        subprocess.Popen([app_name, url])
    elif system == "Windows":
        path = find_browser_path_windows(app_name)
        subprocess.Popen([path or app_name, url])


message = read_message()
if not message:
    sys.exit(0)

if message.get("ping"):
    send_message({"status": "ok"})
elif message.get("check_browser"):
    installed = check_browser_installed(message["check_browser"])
    send_message({"status": "ok", "installed": installed})
elif "url" in message and "browser" in message:
    try:
        open_in_browser(message["browser"], message["url"])
        send_message({"status": "ok"})
    except Exception as e:
        send_message({"status": "error", "message": str(e)})
else:
    send_message({"status": "error", "message": "Invalid message"})
PYEOF

chmod +x "$INSTALL_DIR/host.py"

# ---- Determine native messaging directories for all Chromium browsers ----
OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
    BROWSER_DIRS=(
        "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
        "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
        "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
        "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
        "$HOME/Library/Application Support/Vivaldi/NativeMessagingHosts"
        "$HOME/Library/Application Support/com.operasoftware.Opera/NativeMessagingHosts"
    )
elif [ "$OS" = "Linux" ]; then
    BROWSER_DIRS=(
        "$HOME/.config/google-chrome/NativeMessagingHosts"
        "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
        "$HOME/.config/microsoft-edge/NativeMessagingHosts"
        "$HOME/.config/chromium/NativeMessagingHosts"
        "$HOME/.config/vivaldi/NativeMessagingHosts"
        "$HOME/.config/opera/NativeMessagingHosts"
    )
else
    echo "Unsupported OS: $OS"
    exit 1
fi

# ---- Write native messaging manifest to each browser ----
INSTALLED=0
for DIR in "${BROWSER_DIRS[@]}"; do
    # Only install if the browser's parent config dir exists
    PARENT="$(dirname "$DIR")"
    if [ -d "$PARENT" ]; then
        mkdir -p "$DIR"
        cat > "$DIR/$HOST_NAME.json" << EOF
{
    "name": "$HOST_NAME",
    "description": "Browser Redirect native messaging host",
    "path": "$INSTALL_DIR/host.py",
    "type": "stdio",
    "allowed_origins": [
        "chrome-extension://$EXTENSION_ID/"
    ]
}
EOF
        echo "  Installed for: $(basename "$PARENT")"
        INSTALLED=$((INSTALLED + 1))
    fi
done

if [ "$INSTALLED" -eq 0 ]; then
    echo "No supported Chromium browsers found. Installing for Chrome by default."
    if [ "$OS" = "Darwin" ]; then
        DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    else
        DIR="$HOME/.config/google-chrome/NativeMessagingHosts"
    fi
    mkdir -p "$DIR"
    cat > "$DIR/$HOST_NAME.json" << EOF
{
    "name": "$HOST_NAME",
    "description": "Browser Redirect native messaging host",
    "path": "$INSTALL_DIR/host.py",
    "type": "stdio",
    "allowed_origins": [
        "chrome-extension://$EXTENSION_ID/"
    ]
}
EOF
fi

echo ""
echo "Browser Redirect installed successfully."
echo "Restart your browser for it to take effect."
