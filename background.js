const HOST_NAME = "com.browser.redirect";

let rules = [];

chrome.storage.sync.get({ rules: [] }, (data) => {
  rules = data.rules;
});

chrome.storage.onChanged.addListener((changes) => {
  if (changes.rules) {
    rules = changes.rules.newValue || [];
  }
});

chrome.webNavigation.onBeforeNavigate.addListener((details) => {
  if (details.frameId !== 0) return;

  let url;
  try {
    url = new URL(details.url);
  } catch {
    return;
  }

  const hostname = url.hostname.replace(/^www\./, "");

  const match = rules.find((rule) => {
    const pattern = rule.urlPattern.replace(/^www\./, "");
    return hostname === pattern || hostname.endsWith("." + pattern);
  });

  if (!match) return;

  chrome.runtime.sendNativeMessage(HOST_NAME, {
    url: details.url,
    browser: match.browser,
  });

  chrome.tabs.remove(details.tabId);
});
