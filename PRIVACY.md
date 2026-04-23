# Privacy Policy — Browser Redirect

**Last updated:** April 23, 2026

## Data Collection

Browser Redirect does **not** collect, store, or transmit any personal data.

## How It Works

- Redirect rules (domain + browser pairs) are stored **locally** in your browser using Chrome's built-in storage API.
- The native messaging host runs **locally** on your machine to launch the target browser. It does not communicate with any external servers.
- No analytics, tracking, or telemetry of any kind is included.

## Permissions

| Permission | Why it's needed |
|---|---|
| `webNavigation` | Detect when you navigate to a URL that matches one of your rules |
| `nativeMessaging` | Communicate with the local helper script that opens the target browser |
| `storage` | Save your redirect rules locally |
| `tabs` | Close the Chrome tab after redirecting to the target browser |

## Third Parties

This extension does not share any data with third parties.

## Contact

If you have questions about this policy, open an issue on the [GitHub repository](https://github.com/BozhidarY/browser-redirect/issues).
