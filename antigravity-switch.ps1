<#
.SYNOPSIS
    Antigravity Multi-Account Switcher for Windows 10/11
    Synchronizes both ~/.gemini token files and Windows Credential Manager (gemini:antigravity).
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action = "interactive",

    [Parameter(Position = 1)]
    [string]$ProfileName,

    [Alias("h", "?")]
    [switch]$Help
)

# Win32 Advapi32 Credential Manager definition
$WinCredCode = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WinCredManager {
    [DllImport("Advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("Advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredWrite([In] ref CREDENTIAL userCredential, [In] uint flags);

    [DllImport("Advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
    public static extern void CredFree(IntPtr cred);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    public static string Read(string target) {
        IntPtr credPtr;
        if (CredRead(target, 1, 0, out credPtr)) {
            CREDENTIAL cred = (CREDENTIAL)Marshal.PtrToStructure(credPtr, typeof(CREDENTIAL));
            byte[] bytes = new byte[cred.CredentialBlobSize];
            Marshal.Copy(cred.CredentialBlob, bytes, 0, cred.CredentialBlobSize);
            CredFree(credPtr);
            return Encoding.UTF8.GetString(bytes);
        }
        return null;
    }

    public static bool Write(string target, string userName, string secret) {
        byte[] bytes = Encoding.UTF8.GetBytes(secret);
        IntPtr blobPtr = Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes, 0, blobPtr, bytes.Length);

        CREDENTIAL cred = new CREDENTIAL();
        cred.Type = 1; // Generic
        cred.TargetName = target;
        cred.UserName = userName;
        cred.CredentialBlobSize = bytes.Length;
        cred.CredentialBlob = blobPtr;
        cred.Persist = 2; // CRED_PERSIST_LOCAL_MACHINE

        bool success = CredWrite(ref cred, 0);
        Marshal.FreeHGlobal(blobPtr);
        return success;
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'WinCredManager').Type) {
    Add-Type -TypeDefinition $WinCredCode
}

# Store profiles in the project directory
$ProfilesDir = Join-Path $PSScriptRoot "profiles"
$GeminiDir = Join-Path $HOME ".gemini"
$CredTarget = "gemini:antigravity"

if (-not (Test-Path $ProfilesDir)) {
    New-Item -ItemType Directory -Path $ProfilesDir -Force | Out-Null
}

function Get-ActiveEmail {
    $credSecret = [WinCredManager]::Read($CredTarget)
    if ($credSecret) {
        try {
            $json = $credSecret | ConvertFrom-Json
            if ($json.id_token_email) { return $json.id_token_email }
        } catch {}
    }
    $accountsFile = Join-Path $GeminiDir "google_accounts.json"
    if (Test-Path $accountsFile) {
        try {
            $acc = Get-Content $accountsFile -Raw | ConvertFrom-Json
            if ($acc.active) { return $acc.active }
        } catch {}
    }
    return "Unknown"
}

function Save-Profile([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $defaultName = (Get-ActiveEmail) -replace '[@.]', '_'
        $Name = Read-Host "Enter profile name (default: $defaultName)"
        if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $defaultName }
    }

    $targetDir = Join-Path $ProfilesDir $Name
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    # 1. Capture disk files
    $filesToCopy = @("oauth_creds.json", "google_accounts.json", "jetski-standalone-oauth-token")
    foreach ($file in $filesToCopy) {
        $source = Join-Path $GeminiDir $file
        if (Test-Path $source) {
            Copy-Item -Path $source -Destination $targetDir -Force
        }
    }

    # 2. Capture Windows Credential Manager
    $credSecret = [WinCredManager]::Read($CredTarget)
    if ($credSecret) {
        $credPath = Join-Path $targetDir "win_cred.json"
        [System.IO.File]::WriteAllText($credPath, $credSecret, [System.Text.Encoding]::UTF8)
    }

    $activeEmail = Get-ActiveEmail
    $meta = @{
        ProfileName = $Name
        Email = $activeEmail
        SavedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $meta | ConvertTo-Json | Set-Content (Join-Path $targetDir "meta.json")

    Write-Host "`n[SUCCESS] Profile '$Name' saved successfully!" -ForegroundColor Green
    Write-Host "Associated Account: $activeEmail" -ForegroundColor Cyan
    Write-Host "Location: $targetDir" -ForegroundColor Gray
}

function Use-Profile([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Host "Please specify a profile name to switch to." -ForegroundColor Red
        return
    }

    $targetDir = Join-Path $ProfilesDir $Name
    if (-not (Test-Path $targetDir)) {
        Write-Host "Profile '$Name' not found in $ProfilesDir" -ForegroundColor Red
        return
    }

    # 1. Restore disk files
    $filesToRestore = @("oauth_creds.json", "google_accounts.json", "jetski-standalone-oauth-token")
    foreach ($file in $filesToRestore) {
        $src = Join-Path $targetDir $file
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination $GeminiDir -Force
        }
    }

    # 2. Restore Windows Credential Manager
    $credPath = Join-Path $targetDir "win_cred.json"
    if (Test-Path $credPath) {
        $secret = [System.IO.File]::ReadAllText($credPath, [System.Text.Encoding]::UTF8)
        $ok = [WinCredManager]::Write($CredTarget, "antigravity", $secret)
        if (-not $ok) {
            Write-Warning "Could not write to Windows Credential Manager ($CredTarget)."
        }
    }

    $metaFile = Join-Path $targetDir "meta.json"
    $email = "Unknown"
    if (Test-Path $metaFile) {
        try {
            $email = (Get-Content $metaFile -Raw | ConvertFrom-Json).Email
        } catch {}
    }

    Write-Host "`n[SUCCESS] Switched to profile '$Name' ($email)!" -ForegroundColor Green
    Write-Host "Windows Credential Manager & ~/.gemini files synchronized." -ForegroundColor Cyan
    Write-Host "Both VS Code and Antigravity Desktop are now connected to: $email" -ForegroundColor Yellow
}

function Delete-Profile([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Host "Please specify a profile name to delete." -ForegroundColor Red
        return
    }
    $targetDir = Join-Path $ProfilesDir $Name
    if (Test-Path $targetDir) {
        Remove-Item -Path $targetDir -Recurse -Force
        Write-Host "[SUCCESS] Profile '$Name' deleted." -ForegroundColor Green
    } else {
        Write-Host "Profile '$Name' does not exist." -ForegroundColor Yellow
    }
}

function List-Profiles {
    $activeEmail = Get-ActiveEmail
    Write-Host "`n=== Antigravity Account Profiles ===" -ForegroundColor Cyan
    Write-Host "Storage Directory: $ProfilesDir" -ForegroundColor Gray
    Write-Host "Currently Active: $activeEmail" -ForegroundColor Green
    Write-Host "-------------------------------------"

    $profiles = Get-ChildItem -Path $ProfilesDir -Directory
    if ($profiles.Count -eq 0) {
        Write-Host "No profiles saved yet. Run with -Action save to snapshot your current account." -ForegroundColor Gray
        return
    }

    foreach ($p in $profiles) {
        $metaFile = Join-Path $p.FullName "meta.json"
        $email = "Unknown"
        $savedAt = ""
        if (Test-Path $metaFile) {
            try {
                $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
                $email = $meta.Email
                $savedAt = " (Saved: $($meta.SavedAt))"
            } catch {}
        }
        $mark = if ($email -eq $activeEmail -and $activeEmail -ne "Unknown") { " [ACTIVE]" } else { "" }
        $color = if ($mark) { "Green" } else { "White" }
        Write-Host " * $($p.Name) -> $email$savedAt$mark" -ForegroundColor $color
    }
    Write-Host ""
}

function Show-Help {
    Write-Host "`n=== Antigravity Multi-Account Switcher ===" -ForegroundColor Cyan
    Write-Host "Synchronizes Windows Credential Manager (gemini:antigravity) & ~/.gemini tokens.`n" -ForegroundColor Gray

    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  agy-switch                                 Launch interactive menu"
    Write-Host "  agy-switch list                            List saved accounts and show active session"
    Write-Host "  agy-switch save <profile_name>             Snapshot currently logged-in account"
    Write-Host "  agy-switch use <profile_name>              Switch to a saved profile immediately"
    Write-Host "  agy-switch delete <profile_name>           Delete a saved profile"
    Write-Host "  agy-switch help                            Show this help message`n"

    Write-Host "HELP ALIASES:" -ForegroundColor Yellow
    Write-Host "  agy-switch -h | --help | -? | /?`n"

    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  agy-switch save work                       Save active account as 'work'"
    Write-Host "  agy-switch save personal                   Save active account as 'personal'"
    Write-Host "  agy-switch use work                        Switch to 'work' profile"
    Write-Host "  agy-switch delete old_acc                  Remove 'old_acc' profile`n"

    Write-Host "STORAGE LOCATION:" -ForegroundColor Yellow
    Write-Host "  $ProfilesDir`n"
}

if ($Help -or $Action.ToLower() -in @("help", "-help", "--help", "-h", "-?", "/?", "?")) {
    Show-Help
    return
}

switch ($Action.ToLower()) {
    "list" { List-Profiles }
    "save" { Save-Profile $ProfileName }
    "use"  { Use-Profile $ProfileName }
    "delete" { Delete-Profile $ProfileName }
    "interactive" {
        while ($true) {
            Clear-Host
            List-Profiles
            Write-Host "1) Switch account"
            Write-Host "2) Save current account as new profile"
            Write-Host "3) Delete a saved profile"
            Write-Host "4) View help & usage guide"
            Write-Host "5) Exit"
            $choice = Read-Host "`nChoose an option [1-5]"
            switch ($choice) {
                "1" {
                    $name = Read-Host "Enter profile name to switch to"
                    if (-not [string]::IsNullOrWhiteSpace($name)) {
                        Use-Profile $name
                        Read-Host "`nPress Enter to continue..."
                    }
                }
                "2" {
                    $name = Read-Host "Enter new profile name"
                    Save-Profile $name
                    Read-Host "`nPress Enter to continue..."
                }
                "3" {
                    $name = Read-Host "Enter profile name to delete"
                    Delete-Profile $name
                    Read-Host "`nPress Enter to continue..."
                }
                "4" {
                    Show-Help
                    Read-Host "`nPress Enter to continue..."
                }
                "5" { return }
                default { }
            }
        }
    }
    default {
        Write-Host "`n[ERROR] Unknown command: '$Action'" -ForegroundColor Red
        Write-Host "Run 'agy-switch help' to see all available commands.`n" -ForegroundColor Yellow
    }
}
