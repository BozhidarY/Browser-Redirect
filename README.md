# Browser Redirect

A Chrome extension that automatically redirects specific websites to a browser of your choice. For example, you can have YouTube always open in Brave, or GitHub always open in Firefox.

## Features

- Redirect any domain to any browser (Brave, Firefox, Safari, Edge, Chrome, or custom)
- Add, edit, and delete redirect rules from a simple popup UI
- Detects whether the target browser is installed before saving a rule
- Works on macOS, Linux, and Windows
- Supports all Chromium-based browsers (Chrome, Brave, Edge, Vivaldi, Opera, Chromium)
- No data is sent to any server — everything runs locally

## How It Works

The extension uses Chrome's [Native Messaging API](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) to communicate with a small local helper script. When you navigate to a matched domain, the extension sends the URL to the helper script, which opens it in your chosen browser and closes the original tab.

## Installation

### 1. Install the Extension

Install from the [Chrome Web Store](https://chrome.google.com/webstore) or load it manually:

1. Go to `chrome://extensions`
2. Enable **Developer mode** (top-right toggle)
3. Click **Load unpacked** and select the extension folder

### 2. Install the Native Host

Open the extension popup — it will show a setup screen with a command to copy and paste into your terminal.

**macOS / Linux:**
```sh
curl -sL 'https://raw.githubusercontent.com/BozhidarY/browser-redirect/main/install.sh' | bash -s '<your-extension-id>'
```

**Windows (PowerShell):**
```powershell
powershell -Command "irm 'https://raw.githubusercontent.com/BozhidarY/browser-redirect/main/install_windows.ps1' -OutFile $env:TEMP\br.ps1; powershell -ExecutionPolicy Bypass $env:TEMP\br.ps1 '<your-extension-id>'"
```

The extension popup will fill in the correct extension ID and install path for you.

After running the command, restart your browser and reopen the popup.

### 3. Add Rules

Click the extension icon to open the popup, enter a domain (e.g. `youtube.com`), select a target browser, and click **+ Add Rule**.

## Files

| File | Description |
|------|-------------|
| `manifest.json` | Extension manifest (Manifest V3) |
| `background.js` | Service worker that intercepts navigations and redirects |
| `popup.html/js/css` | Extension popup UI |
| `host.py` | Native messaging host for macOS/Linux (Python) |
| `install.sh` | Installer for macOS/Linux |
| `install_windows.ps1` | Installer for Windows (PowerShell) |

## Privacy

No data is collected or transmitted. See [PRIVACY.md](PRIVACY.md) for the full privacy policy.

## License

MIT
