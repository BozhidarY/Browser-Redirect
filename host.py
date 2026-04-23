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
