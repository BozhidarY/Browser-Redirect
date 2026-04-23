const HOST_NAME = "com.browser.redirect";

const BROWSER_LABELS = {
  brave: "Brave",
  firefox: "Firefox",
  safari: "Safari",
  edge: "Microsoft Edge",
  chrome: "Google Chrome",
};

const INSTALL_URL_UNIX =
  "https://raw.githubusercontent.com/BozhidarY/browser-redirect/main/install.sh";
const INSTALL_URL_WIN =
  "https://raw.githubusercontent.com/BozhidarY/browser-redirect/main/install_windows.ps1";

let rules = [];
let editingIndex = -1;

document.addEventListener("DOMContentLoaded", () => {
  checkNativeHost();
});

// --- Connection check ---

function checkNativeHost() {
  chrome.runtime.sendNativeMessage(HOST_NAME, { ping: true }, (response) => {
    if (chrome.runtime.lastError || !response) {
      showSetupScreen();
    } else {
      showMainScreen();
    }
  });
}

// --- Setup screen ---

function showSetupScreen() {
  document.getElementById("setup-screen").style.display = "block";
  document.getElementById("main-screen").style.display = "none";

  const extId = chrome.runtime.id;
  const isWindows = navigator.userAgent.includes("Windows");

  const defaultPath = isWindows
    ? "%LOCALAPPDATA%\\BrowserRedirect"
    : "$HOME/.browser-redirect";

  const pathInput = document.getElementById("install-path");
  pathInput.value = defaultPath;

  const restrictedDirs = ["Downloads", "Documents", "Desktop"];

  function isRestrictedPath(path) {
    if (isWindows) return false;
    const normalized = path.replace(/^(\$HOME|~)\//, "");
    return restrictedDirs.some((dir) => normalized === dir || normalized.startsWith(dir + "/"));
  }

  function buildCommand() {
    const installPath = pathInput.value.trim();
    const isDefault = !installPath || installPath === defaultPath;

    if (isWindows) {
      const pathArg = isDefault ? "" : ` '${installPath}'`;
      return `powershell -Command "irm '${INSTALL_URL_WIN}' -OutFile $env:TEMP\\br.ps1; powershell -ExecutionPolicy Bypass $env:TEMP\\br.ps1 '${extId}'${pathArg}"`;
    }

    if (isDefault) {
      return `curl -sL '${INSTALL_URL_UNIX}' | bash -s '${extId}'`;
    }
    const path = installPath.replace(/^~/, "$HOME");
    return `curl -sL '${INSTALL_URL_UNIX}' | bash -s '${extId}' "${path}"`;
  }

  function updateCommand() {
    const installPath = pathInput.value.trim();
    const pathWarning = document.getElementById("path-warning");
    const copyBtn = document.getElementById("copy-btn");

    if (isRestrictedPath(installPath)) {
      pathWarning.textContent = "Downloads, Documents, and Desktop are not supported. macOS blocks Chrome from running scripts in these folders.";
      pathWarning.style.display = "block";
      copyBtn.disabled = true;
    } else {
      pathWarning.style.display = "none";
      copyBtn.disabled = false;
    }

    document.getElementById("install-command").textContent = buildCommand();
  }

  document.getElementById("setup-instruction").innerHTML = isWindows
    ? 'Paste this command in <strong>PowerShell</strong>:'
    : 'Paste this command in <strong>Terminal</strong>:';

  updateCommand();
  pathInput.addEventListener("input", updateCommand);

  document.getElementById("copy-btn").addEventListener("click", () => {
    navigator.clipboard.writeText(buildCommand()).then(() => {
      document.getElementById("copy-btn").textContent = "Copied!";
      setTimeout(() => {
        document.getElementById("copy-btn").textContent = "Copy";
      }, 1500);
    });
  });

  document.getElementById("retry-btn").addEventListener("click", () => {
    checkNativeHost();
  });
}

// --- Main screen ---

function showMainScreen() {
  document.getElementById("setup-screen").style.display = "none";
  document.getElementById("main-screen").style.display = "block";
  loadRules();
  setupEventListeners();
}

function loadRules() {
  chrome.storage.sync.get({ rules: [] }, (data) => {
    rules = data.rules;
    renderRules();
  });
}

function saveRules() {
  chrome.storage.sync.set({ rules });
}

function renderRules() {
  const list = document.getElementById("rules-list");

  if (rules.length === 0) {
    list.innerHTML = '<div class="empty-state">No redirect rules yet</div>';
    return;
  }

  list.innerHTML = rules
    .map(
      (rule, i) => `
    <div class="rule">
      <span class="rule-url">${esc(rule.urlPattern)}</span>
      <span class="rule-arrow">&rarr;</span>
      <span class="rule-browser">${esc(rule.browserLabel)}</span>
      <span class="rule-actions">
        <button class="edit-btn" data-index="${i}" title="Edit">&#9998;</button>
        <button class="delete-btn" data-index="${i}" title="Remove">&times;</button>
      </span>
    </div>`
    )
    .join("");

  list.querySelectorAll(".edit-btn").forEach((btn) => {
    btn.addEventListener("click", () => startEditing(parseInt(btn.dataset.index)));
  });

  list.querySelectorAll(".delete-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      rules.splice(parseInt(btn.dataset.index), 1);
      saveRules();
      renderRules();
      if (editingIndex >= 0) cancelEditing();
    });
  });

  list.querySelectorAll(".rule-url").forEach((el) => {
    el.addEventListener("click", () => {
      navigator.clipboard.writeText(el.textContent).then(() => {
        showStatus("Copied to clipboard", "success");
      });
    });
  });

  list.querySelectorAll(".rule-url").forEach((el, i) => {
    el.addEventListener("mouseenter", (e) => {
      if (el.scrollWidth <= el.clientWidth) return;
      const tip = document.createElement("div");
      tip.className = "tooltip";
      tip.textContent = rules[i].urlPattern;
      document.body.appendChild(tip);
      const rect = el.getBoundingClientRect();
      const tipRect = tip.getBoundingClientRect();
      const popupWidth = document.documentElement.clientWidth;
      let left = rect.left;
      if (left + tipRect.width > popupWidth - 8) {
        left = popupWidth - tipRect.width - 8;
      }
      tip.style.left = Math.max(8, left) + "px";
      tip.style.top = rect.bottom + 4 + "px";
      el._tip = tip;
    });
    el.addEventListener("mouseleave", () => {
      if (el._tip) {
        el._tip.remove();
        el._tip = null;
      }
    });
  });
}

// --- Editing ---

function startEditing(index) {
  const rule = rules[index];
  editingIndex = index;

  document.getElementById("url-input").value = rule.urlPattern;

  const browserSelect = document.getElementById("browser-select");
  const customInput = document.getElementById("custom-browser-input");

  if (rule.browser.startsWith("custom:")) {
    browserSelect.value = "custom";
    customInput.value = rule.browser.slice(7);
    customInput.classList.add("visible");
  } else {
    browserSelect.value = rule.browser;
    customInput.value = "";
    customInput.classList.remove("visible");
  }

  document.getElementById("add-btn").textContent = "Save Rule";
  document.getElementById("cancel-btn").style.display = "block";
}

function cancelEditing() {
  editingIndex = -1;
  document.getElementById("url-input").value = "";
  document.getElementById("browser-select").value = "";
  document.getElementById("custom-browser-input").value = "";
  document.getElementById("custom-browser-input").classList.remove("visible");
  document.getElementById("add-btn").textContent = "+ Add Rule";
  document.getElementById("cancel-btn").style.display = "none";
}

// --- Event listeners ---

function setupEventListeners() {
  document.getElementById("browser-select").addEventListener("change", (e) => {
    const custom = document.getElementById("custom-browser-input");
    custom.classList.toggle("visible", e.target.value === "custom");
  });

  document.getElementById("add-btn").addEventListener("click", submitRule);
  document.getElementById("cancel-btn").addEventListener("click", cancelEditing);
  document.getElementById("url-input").addEventListener("keydown", (e) => {
    if (e.key === "Enter") submitRule();
    if (e.key === "Escape" && editingIndex >= 0) cancelEditing();
  });
}

// --- Add / Save rule ---

function submitRule() {
  const urlInput = document.getElementById("url-input");
  const browserSelect = document.getElementById("browser-select");
  const customInput = document.getElementById("custom-browser-input");

  const urlPattern = urlInput.value
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, "")
    .replace(/\/.*$/, "")
    .replace(/^www\./, "");

  if (!urlPattern) return showStatus("Enter a domain", "error");
  if (!/^[a-z0-9]([a-z0-9-]*\.)+[a-z]{2,}$/.test(urlPattern))
    return showStatus("Enter a valid domain (e.g. youtube.com)", "error");
  if (!browserSelect.value) return showStatus("Select a browser", "error");

  let browserKey, browserLabel;

  if (browserSelect.value === "custom") {
    const name = customInput.value.trim();
    if (!name) return showStatus("Enter the browser name", "error");
    browserKey = "custom:" + name;
    browserLabel = name;
  } else {
    browserKey = browserSelect.value;
    browserLabel = BROWSER_LABELS[browserKey] || browserKey;
  }

  // Check for duplicates (skip the rule being edited)
  const duplicate = rules.find(
    (r, i) =>
      i !== editingIndex &&
      r.urlPattern === urlPattern &&
      r.browser === browserKey
  );
  if (duplicate) return showStatus("Rule already exists", "error");

  // Check if browser is installed before saving
  chrome.runtime.sendNativeMessage(
    HOST_NAME,
    { check_browser: browserKey },
    (response) => {
      if (response && response.installed === false) {
        showStatus(
          `"${browserLabel}" was not found on this system`,
          "error"
        );
        return;
      }

      const rule = { urlPattern, browser: browserKey, browserLabel };

      if (editingIndex >= 0) {
        rules[editingIndex] = rule;
        showStatus("Rule updated", "success");
      } else {
        rules.push(rule);
        showStatus("Rule added", "success");
      }

      saveRules();
      renderRules();
      cancelEditing();
    }
  );
}

// --- Helpers ---

function showStatus(message, type) {
  const bar = document.getElementById("status-bar");
  bar.textContent = message;
  bar.className = "status-bar " + type;
  setTimeout(() => {
    bar.textContent = "";
    bar.className = "status-bar";
  }, 3000);
}

function esc(str) {
  const el = document.createElement("span");
  el.textContent = str;
  return el.innerHTML;
}
