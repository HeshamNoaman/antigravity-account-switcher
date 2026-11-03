# Antigravity Multi-Account Switcher (Windows 10/11)

A lightweight, zero-dependency account switcher designed for **Google Antigravity** on Windows. It enables instant 1-click swapping between multiple Google accounts across **both** the **Antigravity Desktop Application** and the **VS Code Extension** without having to re-authenticate in the browser each time.

---

## ⚡ Why This Exists

Google Antigravity synchronizes its active session across two layers on Windows:
1. **Windows Credential Manager:** Generic credential entry `gemini:antigravity` managed by Windows `Advapi32.dll`.
2. **Local Session Files:** Stored in `~/.gemini/` (`google_accounts.json`, `oauth_creds.json`, and `jetski-standalone-oauth-token`).

Standard file-copy scripts or in-editor extensions fail to switch accounts globally because they don't synchronize both layers. This tool uses native Win32 P/Invoke APIs (`CredReadW` and `CredWriteW`) to swap both stores atomically.

---

## 🚀 Quick Start

### 1. Interactive Mode (Easiest)
Run the script or double-click `switch.bat`:
```powershell
.\antigravity-switch.ps1
```
or from CMD / File Explorer:
```cmd
switch.bat
```

### 2. Command Line Interface (CLI)

| Command | Action |
| :--- | :--- |
| `.\antigravity-switch.ps1 list` | List all saved accounts and show which is currently active |
| `.\antigravity-switch.ps1 save <profile_name>` | Snapshot the currently logged-in account |
| `.\antigravity-switch.ps1 use <profile_name>` | Switch immediately to the specified account |
| `.\antigravity-switch.ps1 delete <profile_name>` | Delete a saved profile |

---

## 📖 Step-by-Step Multi-Account Setup

### Step 1: Save Account 1
1. Make sure you are signed into your primary Google account in Antigravity.
2. Run:
   ```powershell
   .\antigravity-switch.ps1 save acc1
   ```

### Step 2: Save Account 2
1. In the Antigravity Desktop App or VS Code, click your account avatar $\rightarrow$ **Sign Out**.
2. Sign in with your second Google account.
3. Run:
   ```powershell
   .\antigravity-switch.ps1 save acc2
   ```

### Step 3: Switch Seamlessly Anytime
```powershell
# Switch to Account 1:
.\antigravity-switch.ps1 use acc1

# Switch to Account 2:
.\antigravity-switch.ps1 use acc2
```

Both VS Code and the Antigravity Desktop app immediately pick up the restored session without prompting for browser login.

---

## 🔒 Security & Privacy Notice

* All profile credentials and OAuth tokens are stored locally in the `profiles/` directory.
* The included `.gitignore` strictly ignores the `profiles/` folder and any credential tokens to ensure sensitive secrets are **never** accidentally committed or pushed to remote git repositories.
* Zero telemetry and zero third-party network requests. Everything executes locally on your machine.

---

## 🛠 Global CLI Shortcut (Optional)

To use `agy-switch` from any terminal prompt across Windows:
Add this repository to your user `PATH`, or copy `agy-switch.cmd` into `~/.gemini/antigravity/bin/`.
