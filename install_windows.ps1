param(
    [Parameter(Position=0)]
    [string]$ExtensionId,
    [Parameter(Position=1)]
    [string]$InstallPath
)

$hostName = "com.browser.redirect"

if (-not $ExtensionId) {
    Write-Host "Browser Redirect - Windows Installer"
    Write-Host ""
    Write-Host "Usage: powershell -ExecutionPolicy Bypass -File install_windows.ps1 <chrome-extension-id> [install-path]"
    Write-Host ""
    Write-Host "To find your extension ID:"
    Write-Host "  1. Open chrome://extensions"
    Write-Host "  2. Enable 'Developer mode' (top-right toggle)"
    Write-Host "  3. Click 'Load unpacked' and select the extension folder"
    Write-Host "  4. Copy the ID shown under the extension name"
    exit 1
}

$installDir = if ($InstallPath) { $InstallPath } else { Join-Path $env:LOCALAPPDATA "BrowserRedirect" }
New-Item -ItemType Directory -Path $installDir -Force | Out-Null

# ---- Write host.ps1 (the native messaging host) ----
$hostScript = @'
$stdin = [System.Console]::OpenStandardInput()
$stdout = [System.Console]::OpenStandardOutput()

# Read 4-byte length prefix
$lenBuf = New-Object byte[] 4
$read = $stdin.Read($lenBuf, 0, 4)
if ($read -lt 4) { exit }
$msgLen = [BitConverter]::ToUInt32($lenBuf, 0)

# Read message body
$msgBuf = New-Object byte[] $msgLen
$totalRead = 0
while ($totalRead -lt $msgLen) {
    $n = $stdin.Read($msgBuf, $totalRead, $msgLen - $totalRead)
    if ($n -eq 0) { exit }
    $totalRead += $n
}
$message = [System.Text.Encoding]::UTF8.GetString($msgBuf) | ConvertFrom-Json

function Send-Response($obj) {
    $json = $obj | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $lenBytes = [BitConverter]::GetBytes([uint32]$bytes.Length)
    $stdout.Write($lenBytes, 0, 4)
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
}

$browserMap = @{
    "brave"   = "brave.exe"
    "firefox" = "firefox.exe"
    "edge"    = "msedge.exe"
    "chrome"  = "chrome.exe"
}

function Get-BrowserPath($browserKey) {
    if ($browserKey.StartsWith("custom:")) {
        $appName = $browserKey.Substring(7)
    } else {
        $appName = $browserMap[$browserKey]
        if (-not $appName) { return $null }
    }
    $exe = if ($appName.EndsWith(".exe")) { $appName } else { "$appName.exe" }
    try {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe")
        if ($key) {
            $path = $key.GetValue("")
            $key.Close()
            if ($path -and (Test-Path $path)) { return $path }
        }
    } catch {}
    return $null
}

if ($message.ping) {
    Send-Response @{ status = "ok" }
}
elseif ($message.check_browser) {
    $path = Get-BrowserPath $message.check_browser
    Send-Response @{ status = "ok"; installed = ($null -ne $path) }
}
elseif ($message.url -and $message.browser) {
    try {
        $path = Get-BrowserPath $message.browser
        if ($path) {
            Start-Process -FilePath $path -ArgumentList $message.url
        }
        Send-Response @{ status = "ok" }
    } catch {
        Send-Response @{ status = "error"; message = $_.Exception.Message }
    }
}
else {
    Send-Response @{ status = "error"; message = "Invalid message" }
}
'@

$hostPs1Path = Join-Path $installDir "host.ps1"
Set-Content -Path $hostPs1Path -Value $hostScript -Encoding UTF8

# ---- Write host.bat wrapper (Chrome needs an exe or bat) ----
$hostBatPath = Join-Path $installDir "host.bat"
$batContent = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$hostPs1Path`""
Set-Content -Path $hostBatPath -Value $batContent -Encoding ASCII

# ---- Write native messaging manifest ----
$manifestPath = Join-Path $installDir "$hostName.json"
$manifest = @{
    name = $hostName
    description = "Browser Redirect native messaging host"
    path = $hostBatPath
    type = "stdio"
    allowed_origins = @("chrome-extension://$ExtensionId/")
} | ConvertTo-Json
Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8

# ---- Register in Windows Registry for all Chromium browsers ----
$browserRegPaths = @(
    "HKCU:\SOFTWARE\Google\Chrome\NativeMessagingHosts\$hostName"
    "HKCU:\SOFTWARE\BraveSoftware\Brave-Browser\NativeMessagingHosts\$hostName"
    "HKCU:\SOFTWARE\Microsoft\Edge\NativeMessagingHosts\$hostName"
    "HKCU:\SOFTWARE\Chromium\NativeMessagingHosts\$hostName"
    "HKCU:\SOFTWARE\Vivaldi\NativeMessagingHosts\$hostName"
    "HKCU:\SOFTWARE\Opera Software\Opera Stable\NativeMessagingHosts\$hostName"
)

foreach ($regPath in $browserRegPaths) {
    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "(default)" -Value $manifestPath
}

Write-Host ""
Write-Host "Browser Redirect installed successfully."
Write-Host "Registered for: Chrome, Brave, Edge, Chromium, Vivaldi, Opera"
Write-Host "Restart your browser for it to take effect."
