<#
.SYNOPSIS
    Bootstraps the NetMark C# project from scratch, compiles as a single
    portable self-contained EXE (with embedded HTML + default INI), and runs it.
    v35 - Updated default configuration values (BannerShadow=False, BorderEnabled=True, etc).
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = "C:\Dev\NetMark",
    [string]$Configuration = "Release"
)

 $ErrorActionPreference = 'Stop'
 $VerbosePreference     = 'Continue'

function Dbg-Step { param([string]$m) Write-Host "[STEP ] $m" -ForegroundColor Cyan }
function Dbg-Info { param([string]$m) Write-Host "[INFO ] $m" -ForegroundColor Gray }
function Dbg-Ok   { param([string]$m) Write-Host "[ OK  ] $m" -ForegroundColor Green }
function Dbg-Warn { param([string]$m) Write-Host "[WARN ] $m" -ForegroundColor Yellow }
function Dbg-Err  { param([string]$m) Write-Host "[ERR  ] $m" -ForegroundColor Red }
function Dbg-File { param([string]$p) Write-Host "        -> wrote: $p" -ForegroundColor DarkGray }

 $srcDir       = Join-Path $ProjectRoot 'src'
 $sharedDir    = Join-Path $srcDir 'Shared'
 $bannerDir    = Join-Path $srcDir 'NetMark'
 $objDir       = Join-Path $ProjectRoot 'obj'
 $binDir       = Join-Path $ProjectRoot 'bin'
 $artifactsDir = Join-Path $binDir $Configuration
 $publishDir   = Join-Path $artifactsDir 'publish'

Dbg-Step "Project root resolved to: $ProjectRoot"
Dbg-Step "Portable EXE will land in: $publishDir"

# ---------------------------------------------------------------------------
# Phase 1: Clean slate
# ---------------------------------------------------------------------------
Dbg-Step "Phase 1: Clean Slate"
if (Test-Path -LiteralPath $ProjectRoot) {
    Dbg-Info "Existing project detected. Removing: $ProjectRoot"
    try {
        Remove-Item -LiteralPath $ProjectRoot -Recurse -Force -ErrorAction Stop
        Dbg-Ok "Removed existing tree."
    } catch {
        Dbg-Err "Failed to delete existing project: $($_.Exception.Message)"
        throw
    }
} else {
    Dbg-Info "No existing project; nothing to delete."
}

# ---------------------------------------------------------------------------
# Phase 2: Recreate directory structure
# ---------------------------------------------------------------------------
Dbg-Step "Phase 2: Create directory structure"
foreach ($d in @($ProjectRoot, $srcDir, $sharedDir, $bannerDir, $objDir, $binDir, $artifactsDir, $publishDir)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    Dbg-Info "Ensured directory: $d"
}

# ---------------------------------------------------------------------------
# Phase 3: Emit project files
# ---------------------------------------------------------------------------
Dbg-Step "Phase 3: Emit source files"

# ---- Shared\NativeMethods.cs ----------------------------------------------
 $nativePath = Join-Path $sharedDir 'NativeMethods.cs'
 $nativeContent = @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;

namespace NetMark
{
    internal static class NativeMethods
    {
        public const uint ABM_NEW             = 0x00000000;
        public const uint ABM_REMOVE          = 0x00000001;
        public const uint ABM_QUERYPOS        = 0x00000002;
        public const uint ABM_SETPOS          = 0x00000003;
        
        public const uint ABN_POSCHANGED      = 0x00000001;
        public const uint ABN_FULLSCREENAPP   = 0x00000002;

        public const uint ABE_LEFT   = 0;
        public const uint ABE_TOP    = 1;
        public const uint ABE_RIGHT  = 2;
        public const uint ABE_BOTTOM = 3;

        [StructLayout(LayoutKind.Sequential)]
        public struct APPBARDATA
        {
            public int    cbSize;
            public IntPtr hWnd;
            public uint   uCallbackMessage;
            public uint   uEdge;
            public RECT   rc;
            public IntPtr lParam;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left, Top, Right, Bottom;
            public int Width  => Right - Left;
            public int Height => Bottom - Top;
            
            public Rectangle ToRectangle() => new Rectangle(Left, Top, Width, Height);
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public struct MONITORINFOEX
        {
            public int cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string szDevice;
        }

        public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

        [DllImport("shell32.dll", CallingConvention = CallingConvention.StdCall)]
        public static extern uint SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);

        [DllImport("user32.dll")]
        public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        public static readonly IntPtr HWND_TOPMOST   = new IntPtr(-1);

        public const uint SWP_NOSIZE          = 0x0001;
        public const uint SWP_NOMOVE          = 0x0002;
        public const uint SWP_NOACTIVATE      = 0x0010;
        public const uint SWP_SHOWWINDOW      = 0x0040;
        public const uint SWP_ASYNCWINDOWPOS  = 0x4000;

        [DllImport("user32.dll")]
        public static extern IntPtr GetTopWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetDesktopWindow();

        [DllImport("user32.dll")]
        public static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
            WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

        public delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
            int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

        public const uint EVENT_SYSTEM_FOREGROUND     = 0x0003;
        public const uint EVENT_OBJECT_LOCATIONCHANGE = 0x800B;
        public const uint WINEVENT_OUTOFCONTEXT       = 0x0000;
        public const uint WINEVENT_SKIPOWNPROCESS     = 0x0002;

        [DllImport("user32.dll")]
        public static extern bool UnhookWinEvent(IntPtr hWinEventHook);

        [DllImport("user32.dll")]
        public static extern int RegisterWindowMessage(string lpString);

        public const int  HTTRANSPARENT = -1;
        public const int  SC_CLOSE = 0xF060;
        public const int  SC_MOVE  = 0xF010;
        public const int  SC_SIZE  = 0xF000;

        public const int WM_NCHITTEST       = 0x0084;
        public const int WM_SYSCOMMAND      = 0x0112;
        public const int WM_DPICHANGED      = 0x02E0;
        public const int WM_CLOSE           = 0x0010;
        public const int WM_DISPLAYCHANGE   = 0x007E;

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern IntPtr MonitorFromRect(ref RECT lprc, uint dwFlags);

        public const uint MONITOR_DEFAULTTONEAREST = 0x00000002;

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, uint processId);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool QueryFullProcessImageName(IntPtr hProcess, uint dwFlags, StringBuilder lpExeName, ref uint lpdwSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hObject);

        public const uint PROCESS_QUERY_INFORMATION = 0x0400;
        public const uint PROCESS_VM_READ = 0x0010;

        // RDP Server Session Detection APIs and Constants
        public const int SM_REMOTESESSION = 0x1000;

        [DllImport("user32.dll")]
        public static extern int GetSystemMetrics(int nIndex);

        public static bool IsRemoteSession() => GetSystemMetrics(SM_REMOTESESSION) != 0;

        public const int WM_WTSSESSION_CHANGE = 0x02B1;
        public const int NOTIFY_FOR_THIS_SESSION = 0;

        public const int WTS_CONSOLE_CONNECT    = 0x1;
        public const int WTS_CONSOLE_DISCONNECT = 0x2;
        public const int WTS_REMOTE_CONNECT     = 0x3;
        public const int WTS_REMOTE_DISCONNECT  = 0x4;
        public const int WTS_SESSION_LOGON      = 0x5;
        public const int WTS_SESSION_LOGOFF     = 0x6;

        [DllImport("wtsapi32.dll", SetLastError = true)]
        public static extern bool WTSRegisterSessionNotification(IntPtr hWnd, int dwFlags);

        [DllImport("wtsapi32.dll", SetLastError = true)]
        public static extern bool WTSUnRegisterSessionNotification(IntPtr hWnd);
    }
}
'@
Set-Content -LiteralPath $nativePath -Value $nativeContent -Encoding UTF8
Dbg-File $nativePath

# ---- Shared\BannerSettings.cs ---------------------------------------------
 $settingsPath = Join-Path $sharedDir 'BannerSettings.cs'
 $settingsContent = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;

namespace NetMark
{
    internal sealed class BannerSettings
    {
        public string TextLeft    = "%IP_ADDRESS%";
        public string TextCenter  = "%COMPUTERNAME%";
        public string TextRight   = "%USERNAME%";
        public Color   BgColor    = Color.Green;
        public Color   FgColor    = Color.Black;
        public string  FontName   = "Segoe UI";
        public float   FontSize   = 10f;
        public bool    FontBold   = true;
        public bool    FontItalic = false;
        public bool    FontUnderline = false;
        public int     HeightPx   = 24;

        public bool    TextShadow       = false;
        public Color   TextShadowColor  = Color.FromArgb(64, 64, 64);
        public int     TextShadowOffset = 2;

        public bool    BannerShadow     = true;
        public bool    BorderEnabled    = false;
        public int     BorderSize       = 4;

        public int     MarginLeft       = 25;
        public int     MarginRight      = 25;

        // RAINBOW MODE REMOVED:
        // public bool    RainbowMode      = false;

        public Dictionary<string, string> CustomEnvVars = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        
        private Dictionary<string, string> _expandedVars = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        private readonly object _varLock = new object();

        // --- Native IP address cache (replaces PowerShell subprocess) ---
        private static string _cachedIpAddress;
        private static DateTime _cachedIpTimestamp;
        private static readonly object _ipLock = new object();

        public static string GetIniPath() => Path.Combine(AppContext.BaseDirectory, "NetMark.ini");

        /// <summary>
        /// Retrieves the primary IPv4 address natively via System.Net.NetworkInformation.
        /// Replaces the former powershell.exe subprocess approach that caused CPU spikes
        /// and process-creation traces in system event logs every 30 seconds.
        /// Results are cached for 5 seconds; call InvalidateIpCache() to force refresh.
        /// </summary>
        public static string GetNativeIpAddress()
        {
            lock (_ipLock)
            {
                if (_cachedIpAddress != null && (DateTime.UtcNow - _cachedIpTimestamp).TotalSeconds < 5)
                    return _cachedIpAddress;
            }

            string result = "";
            try
            {
                var candidates = NetworkInterface.GetAllNetworkInterfaces()
                    .Where(ni => ni.OperationalStatus == OperationalStatus.Up
                              && ni.NetworkInterfaceType != NetworkInterfaceType.Loopback
                              && ni.NetworkInterfaceType != NetworkInterfaceType.Tunnel
                              && ni.NetworkInterfaceType != NetworkInterfaceType.Unknown);

                foreach (var ni in candidates)
                {
                    string name = ni.Name ?? "";
                    if (name.IndexOf("vEthernet", StringComparison.OrdinalIgnoreCase) >= 0
                        || name.IndexOf("VMware",    StringComparison.OrdinalIgnoreCase) >= 0
                        || name.IndexOf("Virtual",   StringComparison.OrdinalIgnoreCase) >= 0
                        || name.IndexOf("QEMU",      StringComparison.OrdinalIgnoreCase) >= 0
                        || name.IndexOf("Loopback",  StringComparison.OrdinalIgnoreCase) >= 0)
                        continue;

                    var ipProps = ni.GetIPProperties();
                    foreach (var addr in ipProps.UnicastAddresses)
                    {
                        if (addr.Address.AddressFamily != AddressFamily.InterNetwork)
                            continue;
                        string ip = addr.Address.ToString();
                        if (ip.StartsWith("127.") || ip.StartsWith("169.254."))
                            continue;
                        result = ip;
                        break;
                    }
                    if (!string.IsNullOrEmpty(result)) break;
                }
            }
            catch { }

            lock (_ipLock)
            {
                _cachedIpAddress = result;
                _cachedIpTimestamp = DateTime.UtcNow;
            }
            return result;
        }

        /// <summary>
        /// Forces the next GetNativeIpAddress() call to query live network state
        /// instead of returning the cached value. Called on network-change events.
        /// </summary>
        public static void InvalidateIpCache()
        {
            lock (_ipLock)
            {
                _cachedIpAddress = null;
            }
        }

        public static BannerSettings Load()
        {
            string path = GetIniPath();
            if (File.Exists(path))
            {
                try { return LoadFromString(File.ReadAllText(path)); } catch { }
            }
            return new BannerSettings();
        }

        public static BannerSettings LoadFromString(string content)
        {
            var s = new BannerSettings();
            string currentSection = "";
            
            foreach (var rawLine in content.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
            {
                string trimmed = rawLine.Trim();
                if (string.IsNullOrEmpty(trimmed)) continue;
                
                if (trimmed.StartsWith("[") && trimmed.EndsWith("]"))
                {
                    currentSection = trimmed.Substring(1, trimmed.Length - 2);
                    continue;
                }
                
                int eqIdx = rawLine.IndexOf('=');
                if (eqIdx < 0) continue;
                
                string key = rawLine.Substring(0, eqIdx).Trim();
                string val = rawLine.Substring(eqIdx + 1).Trim();
                
                if (currentSection.Equals("EnvVars", StringComparison.OrdinalIgnoreCase))
                {
                    val = val.Replace("\\n", "\n");
                    s.CustomEnvVars[key] = val;
                }
                else
                {
                    switch (key)
                    {
                        case "TextLeft":          s.TextLeft = val; break;
                        case "TextCenter":        s.TextCenter = val; break;
                        case "TextRight":         s.TextRight = val; break;
                        case "BgColor":           try { s.BgColor = Color.FromArgb(int.Parse(val)); } catch { } break;
                        case "FgColor":           try { s.FgColor = Color.FromArgb(int.Parse(val)); } catch { } break;
                        case "FontName":          s.FontName = val; break;
                        case "FontSize":          try { s.FontSize = float.Parse(val); } catch { } break;
                        case "FontBold":          try { s.FontBold = bool.Parse(val); } catch { } break;
                        case "FontItalic":        try { s.FontItalic = bool.Parse(val); } catch { } break;
                        case "FontUnderline":     try { s.FontUnderline = bool.Parse(val); } catch { } break;
                        case "Height":            try { s.HeightPx = int.Parse(val); } catch { } break;
                        case "TextShadow":        try { s.TextShadow = bool.Parse(val); } catch { } break;
                        case "TextShadowColor":   try { s.TextShadowColor = Color.FromArgb(int.Parse(val)); } catch { } break;
                        case "TextShadowOffset":  try { s.TextShadowOffset = int.Parse(val); } catch { } break;
                        case "BannerShadow":      try { s.BannerShadow = bool.Parse(val); } catch { } break;
                        case "BorderEnabled":     try { s.BorderEnabled = bool.Parse(val); } catch { } break;
                        case "BorderSize":        try { s.BorderSize = int.Parse(val); } catch { } break;
                        case "MarginLeft":        try { s.MarginLeft = int.Parse(val); } catch { } break;
                        case "MarginRight":       try { s.MarginRight = int.Parse(val); } catch { } break;
                        // RAINBOW MODE REMOVED:
                        // case "RainbowMode":       try { s.RainbowMode = bool.Parse(val); } catch { } break;
                    }
                }
            }
            return s;
        }

        public void Save()
        {
            try { File.WriteAllText(GetIniPath(), ToIniString()); } catch { }
        }

        public string ToIniString()
        {
            var sb = new StringBuilder();
            sb.AppendLine("[Settings]");
            sb.AppendLine($"TextLeft={TextLeft ?? ""}");
            sb.AppendLine($"TextCenter={TextCenter ?? ""}");
            sb.AppendLine($"TextRight={TextRight ?? ""}");
            sb.AppendLine($"BgColor={BgColor.ToArgb()}");
            sb.AppendLine($"FgColor={FgColor.ToArgb()}");
            sb.AppendLine($"FontName={FontName ?? "Segoe UI"}");
            sb.AppendLine($"FontSize={FontSize}");
            sb.AppendLine($"FontBold={FontBold}");
            sb.AppendLine($"FontItalic={FontItalic}");
            sb.AppendLine($"FontUnderline={FontUnderline}");
            sb.AppendLine($"Height={HeightPx}");
            sb.AppendLine($"TextShadow={TextShadow}");
            sb.AppendLine($"TextShadowColor={TextShadowColor.ToArgb()}");
            sb.AppendLine($"TextShadowOffset={TextShadowOffset}");
            sb.AppendLine($"BannerShadow={BannerShadow}");
            sb.AppendLine($"BorderEnabled={BorderEnabled}");
            sb.AppendLine($"BorderSize={BorderSize}");
            sb.AppendLine($"MarginLeft={MarginLeft}");
            sb.AppendLine($"MarginRight={MarginRight}");
            
            // RAINBOW MODE REMOVED:
            // if (RainbowMode)
            // {
            //     sb.AppendLine($"RainbowMode={RainbowMode}");
            // }
            
            if (CustomEnvVars != null && CustomEnvVars.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("[EnvVars]");
                foreach (var kvp in CustomEnvVars)
                {
                    string val = kvp.Value ?? "";
                    string escaped = val.Replace("\r\n", "\\n").Replace("\n", "\\n").Replace("\r", "");
                    sb.AppendLine($"{kvp.Key}={escaped}");
                }
            }
            return sb.ToString();
        }

        public void EvaluateCustomEnvVars()
        {
            var expanded = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (CustomEnvVars != null)
            {
                foreach (var kvp in CustomEnvVars)
                {
                    if (string.IsNullOrEmpty(kvp.Key)) continue;
                    
                    // POWERSHELL EVALUATION REMOVED:
                    // Previously, values starting with '$' were sent to a hidden powershell.exe
                    // subprocess via Base64-encoded -EncodedCommand every 30 seconds and on
                    // every network adapter event. This caused unnecessary CPU spikes and
                    // aggressive process creation traces in system event logs.
                    // IP_ADDRESS is now resolved natively in ExpandText() via GetNativeIpAddress().
                    //
                    // if (IsPowerShellExpression(kvp.Value))
                    // {
                    //     string result = EvaluatePowerShell(kvp.Value);
                    //     expanded[kvp.Key] = result ?? "";
                    // }
                    // else
                    // {
                    //     expanded[kvp.Key] = kvp.Value ?? "";
                    // }
                    
                    expanded[kvp.Key] = kvp.Value ?? "";
                }
            }
            lock (_varLock) { _expandedVars = expanded; }
        }

        public string ExpandText(string text)
        {
            if (string.IsNullOrEmpty(text)) return text ?? "";
            string result = text;
            
            // Native IP address resolution — replaces the former PowerShell subprocess.
            // %IP_ADDRESS% is now a built-in variable resolved via System.Net.NetworkInformation.
            result = result.Replace("%IP_ADDRESS%", GetNativeIpAddress(), StringComparison.OrdinalIgnoreCase);
            
            lock (_varLock)
            {
                if (_expandedVars != null)
                {
                    foreach (var kvp in _expandedVars)
                    {
                        if (kvp.Value != null)
                            result = result.Replace($"%{kvp.Key}%", kvp.Value, StringComparison.OrdinalIgnoreCase);
                    }
                }
            }
            try { result = Environment.ExpandEnvironmentVariables(result); } catch { }
            return result ?? "";
        }

        // POWERSHELL EVALUATION REMOVED:
        // private static bool IsPowerShellExpression(string value)
        // {
        //     if (string.IsNullOrEmpty(value)) return false;
        //     return value.TrimStart().StartsWith("$");
        // }
        //
        // private static string EvaluatePowerShell(string script)
        // {
        //     try
        //     {
        //         string encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        //         var psi = new ProcessStartInfo
        //         {
        //             FileName = "powershell.exe",
        //             Arguments = $"-NoProfile -NonInteractive -EncodedCommand {encoded}",
        //             UseShellExecute = false,
        //             RedirectStandardOutput = true,
        //             RedirectStandardError = true,
        //             CreateNoWindow = true
        //         };
        //         using (var p = Process.Start(psi))
        //         {
        //             if (p == null) return "";
        //             string output = p.StandardOutput.ReadToEnd().Trim();
        //             p.WaitForExit(15000);
        //             if (!p.HasExited) try { p.Kill(); } catch { }
        //             var lines = output.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
        //             return lines.Length > 0 ? lines[0].Trim() : output;
        //         }
        //     }
        //     catch { return ""; }
        // }
    }
}
'@
Set-Content -LiteralPath $settingsPath -Value $settingsContent -Encoding UTF8
Dbg-File $settingsPath

# ---- Shared\BannerWindow.cs  (CHANGED: Log + WndProc + rcMonitor fix + SetVisibilityState) -------
 $bannerPath = Join-Path $sharedDir 'BannerWindow.cs'
 $bannerContent = @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace NetMark
{
    internal sealed class BannerWindow : Form
    {
        private readonly IntPtr _hMonitor;
        private NativeMethods.MONITORINFOEX _currentMonitorInfo;
        private BannerSettings _settings;
        private readonly int _callbackMsg;
        private bool _registered;

        // RAINBOW MODE REMOVED:
        // private int _hue = 0;
        // private System.Windows.Forms.Timer _rainbowTimer;

        [System.Diagnostics.Conditional("DEBUG")]
        private void Log(string msg)
        {
            System.Diagnostics.Debug.WriteLine($"[Banner] {msg}");
        }

        public BannerWindow(IntPtr hMonitor, BannerSettings settings)
        {
            _hMonitor = hMonitor;
            _settings = settings ?? new BannerSettings();
            _callbackMsg = NativeMethods.RegisterWindowMessage("NetMarkAppBarCallback");

            this.ShowInTaskbar = false;
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.Manual;
            this.DoubleBuffered = true;
            this.AutoScaleMode = AutoScaleMode.None;
            
            UpdateMonitorInfo();
            this.Bounds = ComputeVisibleWindowRect();
            Log("BannerWindow created for monitor: " + _hMonitor);
            
            // RAINBOW MODE REMOVED:
            // if (_settings.RainbowMode) StartRainbowTimer();
        }

        private void UpdateMonitorInfo()
        {
            _currentMonitorInfo = new NativeMethods.MONITORINFOEX { cbSize = Marshal.SizeOf(typeof(NativeMethods.MONITORINFOEX)) };
            NativeMethods.GetMonitorInfo(_hMonitor, ref _currentMonitorInfo);
        }

        public BannerSettings CurrentSettings => _settings;

        public void UpdateSettings(BannerSettings newSettings)
        {
            if (newSettings == null) newSettings = new BannerSettings();
            
            bool recreate = newSettings.BannerShadow != _settings.BannerShadow;
            _settings = newSettings;
            
            if (recreate)
            {
                Log("Recreating handle for shadow change.");
                UnregisterAppBar();
                this.RecreateHandle();
            }
            else
            {
                ReassertAppBar();
            }

            // RAINBOW MODE REMOVED:
            // if (_settings.RainbowMode) StartRainbowTimer();
            // else StopRainbowTimer();

            this.Invalidate();
        }

        // RAINBOW MODE REMOVED:
        // private void StartRainbowTimer()
        // {
        //     if (_rainbowTimer == null)
        //     {
        //         _rainbowTimer = new System.Windows.Forms.Timer();
        //         _rainbowTimer.Interval = 150; 
        //         _rainbowTimer.Tick += (s, e) => 
        //         {
        //             _hue = (_hue + 2) % 360;
        //             this.Invalidate();
        //             this.Update(); 
        //         };
        //     }
        //     if (!_rainbowTimer.Enabled) _rainbowTimer.Start();
        // }
        //
        // private void StopRainbowTimer()
        // {
        //     _rainbowTimer?.Stop();
        // }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00000080 | 0x00000008 | 0x08000000;
                if (_settings != null && _settings.BannerShadow)
                    cp.ClassStyle |= 0x00020000;
                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            try { RegisterAppBar(); }
            catch (Exception ex) { Log("RegisterAppBar failed: " + ex.Message); }
        }

        protected override void WndProc(ref Message m)
        {
            try
            {
                long wParam = m.WParam.ToInt64();
                if (m.Msg == _callbackMsg)
                {
                    int notify = (int)(wParam & 0xFFFFFFFF);
                    switch (notify)
                    {
                        case (int)NativeMethods.ABN_POSCHANGED: ReassertAppBar(); break;
                        case (int)NativeMethods.ABN_FULLSCREENAPP:
                            if (m.LParam.ToInt64() == 0) ReassertTopmost();
                            break;
                    }
                    return;
                }

                switch (m.Msg)
                {
                    case NativeMethods.WM_NCHITTEST:
                        m.Result = new IntPtr(NativeMethods.HTTRANSPARENT);
                        return;
                    case NativeMethods.WM_SYSCOMMAND:
                        int cmd = (int)(wParam & 0xFFF0);
                        if (cmd == NativeMethods.SC_CLOSE || cmd == NativeMethods.SC_MOVE || cmd == NativeMethods.SC_SIZE)
                            return;
                        break;
                    case NativeMethods.WM_DPICHANGED:
                    case NativeMethods.WM_DISPLAYCHANGE:
                        UpdateMonitorInfo();
                        ReassertAppBar();
                        this.Invalidate();
                        return;
                }
                base.WndProc(ref m);
            }
            catch (Exception ex)
            {
                Log("WndProc exception: " + ex.Message);
            }
        }

        private NativeMethods.RECT ComputeAppBarRect()
        {
            var rcMon = _currentMonitorInfo.rcMonitor;
            var rcWork = _currentMonitorInfo.rcWork;
            int h = (_settings != null && _settings.HeightPx > 0) ? _settings.HeightPx : 24;
            // Use rcWork.Top to ensure placement below any existing top taskbar if AppBar fails.
            // Use rcMon.Left/Right to span the full width.
            return new NativeMethods.RECT { Left = rcMon.Left, Top = rcWork.Top, Right = rcMon.Right, Bottom = rcWork.Top + h };
        }

        private Rectangle ComputeVisibleWindowRect()
        {
            var r = ComputeAppBarRect();
            return new Rectangle(r.Left, r.Top, r.Width, r.Height);
        }

        private void RegisterAppBar()
        {
            NativeMethods.APPBARDATA abd = new NativeMethods.APPBARDATA
            {
                cbSize = Marshal.SizeOf(typeof(NativeMethods.APPBARDATA)),
                hWnd = this.Handle,
                uCallbackMessage = (uint)_callbackMsg,
                uEdge = NativeMethods.ABE_TOP
            };
            abd.rc = ComputeAppBarRect();
            uint r = NativeMethods.SHAppBarMessage(NativeMethods.ABM_NEW, ref abd);
            
            if (r != 0)
            {
                _registered = true;
                ReassertAppBar();
                Log("AppBar registered successfully.");
            }
            else
            {
                Log("AppBar registration failed (returned 0).");
            }
        }

        public void ReassertTopmost()
        {
            NativeMethods.SetWindowPos(this.Handle, NativeMethods.HWND_TOPMOST, 0, 0, 0, 0,
                NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_ASYNCWINDOWPOS);
        }

        private void ReassertAppBar()
        {
            if (!_registered) return;
            try
            {
                NativeMethods.APPBARDATA abd = new NativeMethods.APPBARDATA
                {
                    cbSize = Marshal.SizeOf(typeof(NativeMethods.APPBARDATA)),
                    hWnd = this.Handle,
                    uCallbackMessage = (uint)_callbackMsg,
                    uEdge = NativeMethods.ABE_TOP,
                    rc = ComputeAppBarRect()
                };
                NativeMethods.SHAppBarMessage(NativeMethods.ABM_QUERYPOS, ref abd);
                
                abd.rc.Left = _currentMonitorInfo.rcMonitor.Left;
                abd.rc.Right = _currentMonitorInfo.rcMonitor.Right;

                NativeMethods.SHAppBarMessage(NativeMethods.ABM_SETPOS, ref abd);
                this.Bounds = abd.rc.ToRectangle();
            }
            catch { }
        }

        public void SetVisibilityState(bool visible)
        {
            if (visible)
            {
                if (!_registered)
                {
                    this.Visible = true;
                    if (this.IsHandleCreated) RegisterAppBar();
                }
                ReassertTopmost();
            }
            else
            {
                if (_registered)
                {
                    UnregisterAppBar();
                    this.Visible = false;
                }
            }
        }

        protected override void OnPaintBackground(PaintEventArgs e) { }

        protected override void OnPaint(PaintEventArgs e)
        {
            try
            {
                if (_settings == null) _settings = new BannerSettings();
                
                Color bg = _settings.BgColor;
                // RAINBOW MODE REMOVED:
                // if (_settings.RainbowMode)
                // {
                //     bg = ColorFromHSV(_hue, 1.0, 0.85);
                // }
                e.Graphics.Clear(bg);

                string fontName = string.IsNullOrWhiteSpace(_settings.FontName) ? "Segoe UI" : _settings.FontName;
                float fontSize = _settings.FontSize <= 0 ? 10f : _settings.FontSize;

                FontStyle style = FontStyle.Regular;
                if (_settings.FontBold)      style |= FontStyle.Bold;
                if (_settings.FontItalic)    style |= FontStyle.Italic;
                if (_settings.FontUnderline) style |= FontStyle.Underline;

                using (Font font = new Font(fontName, fontSize, style))
                {
                    int mLeft = _settings.MarginLeft > 0 ? _settings.MarginLeft : 0;
                    int mRight = _settings.MarginRight > 0 ? _settings.MarginRight : 0;
                    int slotWidth = this.Width / 3;

                    Rectangle leftRect   = new Rectangle(mLeft, 0, slotWidth - mLeft, this.Height);
                    Rectangle centerRect = new Rectangle(slotWidth, 0, slotWidth, this.Height);
                    Rectangle rightRect  = new Rectangle(slotWidth * 2, 0, slotWidth - mRight, this.Height);

                    string leftText   = _settings.ExpandText(_settings.TextLeft);
                    string centerText = _settings.ExpandText(_settings.TextCenter);
                    string rightText  = _settings.ExpandText(_settings.TextRight);

                    TextFormatFlags flags = TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding;

                    if (_settings.TextShadow)
                    {
                        int dx = _settings.TextShadowOffset;
                        int dy = _settings.TextShadowOffset;
                        Rectangle leftShadow   = new Rectangle(leftRect.X + dx,   leftRect.Y + dy,   leftRect.Width,   leftRect.Height);
                        Rectangle centerShadow = new Rectangle(centerRect.X + dx, centerRect.Y + dy, centerRect.Width, centerRect.Height);
                        Rectangle rightShadow  = new Rectangle(rightRect.X + dx,  rightRect.Y + dy,  rightRect.Width,  rightRect.Height);

                        if (!string.IsNullOrEmpty(leftText))
                            TextRenderer.DrawText(e.Graphics, leftText, font, leftShadow,   _settings.TextShadowColor, flags | TextFormatFlags.Left);
                        if (!string.IsNullOrEmpty(centerText))
                            TextRenderer.DrawText(e.Graphics, centerText, font, centerShadow, _settings.TextShadowColor, flags | TextFormatFlags.HorizontalCenter);
                        if (!string.IsNullOrEmpty(rightText))
                            TextRenderer.DrawText(e.Graphics, rightText, font, rightShadow,  _settings.TextShadowColor, flags | TextFormatFlags.Right);
                    }

                    if (!string.IsNullOrEmpty(leftText))
                        TextRenderer.DrawText(e.Graphics, leftText, font, leftRect,   _settings.FgColor, flags | TextFormatFlags.Left);
                    if (!string.IsNullOrEmpty(centerText))
                        TextRenderer.DrawText(e.Graphics, centerText, font, centerRect, _settings.FgColor, flags | TextFormatFlags.HorizontalCenter);
                    if (!string.IsNullOrEmpty(rightText))
                        TextRenderer.DrawText(e.Graphics, rightText, font, rightRect,  _settings.FgColor, flags | TextFormatFlags.Right);
                }
            }
            catch (Exception ex) { Log("OnPaint failed: " + ex.Message); }
            base.OnPaint(e);
        }

        // RAINBOW MODE REMOVED:
        // private static Color ColorFromHSV(double hue, double saturation, double value)
        // {
        //     int hi = Convert.ToInt32(Math.Floor(hue / 60)) % 6;
        //     double f = hue / 60 - Math.Floor(hue / 60);
        //     value = value * 255;
        //     int v = Convert.ToInt32(value);
        //     int p = Convert.ToInt32(value * (1 - saturation));
        //     int q = Convert.ToInt32(value * (1 - f * saturation));
        //     int t = Convert.ToInt32(value * (1 - (1 - f) * saturation));
        //     if (hi == 0) return Color.FromArgb(255, v, t, p);
        //     else if (hi == 1) return Color.FromArgb(255, q, v, p);
        //     else if (hi == 2) return Color.FromArgb(255, p, v, t);
        //     else if (hi == 3) return Color.FromArgb(255, p, q, v);
        //     else if (hi == 4) return Color.FromArgb(255, t, p, v);
        //     else return Color.FromArgb(255, v, p, q);
        // }

        private void UnregisterAppBar()
        {
            if (!_registered) return;
            try
            {
                NativeMethods.APPBARDATA abd = new NativeMethods.APPBARDATA
                {
                    cbSize = Marshal.SizeOf(typeof(NativeMethods.APPBARDATA)),
                    hWnd = this.Handle
                };
                NativeMethods.SHAppBarMessage(NativeMethods.ABM_REMOVE, ref abd);
            }
            catch { }
            _registered = false;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) 
            {
                // RAINBOW MODE REMOVED:
                // StopRainbowTimer();
                UnregisterAppBar();
            }
            base.Dispose(disposing);
        }
    }
}
'@
Set-Content -LiteralPath $bannerPath -Value $bannerContent -Encoding UTF8
Dbg-File $bannerPath

# ---- Shared\BorderWindow.cs  (CHANGED: Log + WndProc + rcMonitor fix + SetVisibilityState) ------
 $borderPath = Join-Path $sharedDir 'BorderWindow.cs'
 $borderContent = @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace NetMark
{
    internal sealed class BorderWindow : Form
    {
        private readonly IntPtr _hMonitor;
        private NativeMethods.MONITORINFOEX _currentMonitorInfo;
        private readonly uint _edge;
        private BannerSettings _settings;
        private readonly int _callbackMsg;
        private bool _registered;

        // RAINBOW MODE REMOVED:
        // private int _hue = 0;
        // private System.Windows.Forms.Timer _rainbowTimer;

        [System.Diagnostics.Conditional("DEBUG")]
        private void Log(string msg)
        {
            System.Diagnostics.Debug.WriteLine($"[Border:{_edge}] {msg}");
        }

        public BannerSettings CurrentSettings => _settings;

        public BorderWindow(IntPtr hMonitor, BannerSettings settings, uint edge)
        {
            _hMonitor = hMonitor;
            _settings = settings ?? new BannerSettings();
            _edge = edge;
            _callbackMsg = NativeMethods.RegisterWindowMessage("NetMarkBorderAppBarCallback");

            this.ShowInTaskbar = false;
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.Manual;
            this.DoubleBuffered = true;
            this.AutoScaleMode = AutoScaleMode.None;
            
            UpdateMonitorInfo();
            this.Bounds = ComputeVisibleWindowRect();
            Log($"BorderWindow created edge={edge} monitor={hMonitor}");

            // RAINBOW MODE REMOVED:
            // if (_settings.RainbowMode) StartRainbowTimer();
        }

        private void UpdateMonitorInfo()
        {
            _currentMonitorInfo = new NativeMethods.MONITORINFOEX { cbSize = Marshal.SizeOf(typeof(NativeMethods.MONITORINFOEX)) };
            NativeMethods.GetMonitorInfo(_hMonitor, ref _currentMonitorInfo);
        }

        public void UpdateSettings(BannerSettings newSettings)
        {
            if (newSettings == null) newSettings = new BannerSettings();
            _settings = newSettings;
            ReassertAppBar();

            // RAINBOW MODE REMOVED:
            // if (_settings.RainbowMode) StartRainbowTimer();
            // else StopRainbowTimer();

            this.Invalidate();
        }

        // RAINBOW MODE REMOVED:
        // private void StartRainbowTimer()
        // {
        //     if (_rainbowTimer == null)
        //     {
        //         _rainbowTimer = new System.Windows.Forms.Timer();
        //         _rainbowTimer.Interval = 150; 
        //         _rainbowTimer.Tick += (s, e) => 
        //         {
        //             _hue = (_hue + 2) % 360;
        //             this.Invalidate();
        //             this.Update(); 
        //         };
        //     }
        //     if (!_rainbowTimer.Enabled) _rainbowTimer.Start();
        // }
        //
        // private void StopRainbowTimer()
        // {
        //     _rainbowTimer?.Stop();
        // }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00000080 | 0x08000000 | 0x00000008;
                if (_settings != null && _settings.BannerShadow)
                    cp.ClassStyle |= 0x00020000; 
                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            try { RegisterAppBar(); }
            catch (Exception ex) { Log("RegisterAppBar failed: " + ex.Message); }
        }

        protected override void WndProc(ref Message m)
        {
            try
            {
                long wParam = m.WParam.ToInt64();
                if (m.Msg == _callbackMsg)
                {
                    int notify = (int)(wParam & 0xFFFFFFFF);
                    switch (notify)
                    {
                        case (int)NativeMethods.ABN_POSCHANGED: ReassertAppBar(); break;
                        case (int)NativeMethods.ABN_FULLSCREENAPP:
                            if (m.LParam.ToInt64() == 0) ReassertTopmost();
                            break;
                    }
                    return;
                }
                switch (m.Msg)
                {
                    case NativeMethods.WM_NCHITTEST:
                        m.Result = new IntPtr(NativeMethods.HTTRANSPARENT);
                        return;
                    case NativeMethods.WM_SYSCOMMAND:
                        int cmd = (int)(wParam & 0xFFF0);
                        if (cmd == NativeMethods.SC_CLOSE || cmd == NativeMethods.SC_MOVE || cmd == NativeMethods.SC_SIZE)
                            return;
                        break;
                    case NativeMethods.WM_DPICHANGED:
                    case NativeMethods.WM_DISPLAYCHANGE:
                        UpdateMonitorInfo();
                        ReassertAppBar();
                        this.Invalidate();
                        return;
                }
                base.WndProc(ref m);
            }
            catch (Exception ex)
            {
                Log("WndProc exception: " + ex.Message);
            }
        }

        private NativeMethods.RECT ComputeAppBarRect()
        {
            int size = (_settings != null && _settings.BorderSize > 0) ? _settings.BorderSize : 4;
            var rcMon = _currentMonitorInfo.rcMonitor;
            var rcWork = _currentMonitorInfo.rcWork;

            switch (_edge)
            {
                case NativeMethods.ABE_LEFT:
                    // Use rcWork.Left to avoid being placed under a left taskbar.
                    return new NativeMethods.RECT { Left = rcWork.Left, Top = rcMon.Top, Right = rcWork.Left + size, Bottom = rcMon.Bottom };
                case NativeMethods.ABE_RIGHT:
                    // Use rcWork.Right to avoid being placed under a right taskbar.
                    return new NativeMethods.RECT { Left = rcWork.Right - size, Top = rcMon.Top, Right = rcWork.Right, Bottom = rcMon.Bottom };
                case NativeMethods.ABE_BOTTOM:
                    // Use rcWork.Bottom to avoid being placed under a bottom taskbar.
                    return new NativeMethods.RECT { Left = rcMon.Left, Top = rcWork.Bottom - size, Right = rcMon.Right, Bottom = rcWork.Bottom };
                default:
                    return new NativeMethods.RECT();
            }
        }

        private Rectangle ComputeVisibleWindowRect()
        {
            var r = ComputeAppBarRect();
            return new Rectangle(r.Left, r.Top, r.Width, r.Height);
        }

        private void RegisterAppBar()
        {
            NativeMethods.APPBARDATA abd = new NativeMethods.APPBARDATA
            {
                cbSize = Marshal.SizeOf(typeof(NativeMethods.APPBARDATA)),
                hWnd = this.Handle,
                uCallbackMessage = (uint)_callbackMsg,
                uEdge = _edge
            };
            abd.rc = ComputeAppBarRect();
            uint r = NativeMethods.SHAppBarMessage(NativeMethods.ABM_NEW, ref abd);
            if (r != 0)
            {
                _registered = true;
                ReassertAppBar();
                Log($"AppBar registered edge={_edge}");
            }
            else
            {
                Log($"AppBar registration failed edge={_edge} (returned 0).");
            }
        }

        public void ReassertTopmost()
        {
            NativeMethods.SetWindowPos(this.Handle, NativeMethods.HWND_TOPMOST, 0, 0, 0, 0,
                NativeMethods.SWP_NOMOVE | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_ASYNCWINDOWPOS);
        }

        private void ReassertAppBar()
        {
            if (!_registered) return;
            try
            {
                NativeMethods.APPBARDATA abd = new NativeMethods.APPBARDATA
                {
                    cbSize = Marshal.SizeOf(typeof(NativeMethods.APPBARDATA)),
                    hWnd = this.Handle,
                    uCallbackMessage = (uint)_callbackMsg,
                    uEdge = _edge,
                    rc = ComputeAppBarRect()
                };
                NativeMethods.SHAppBarMessage(NativeMethods.ABM_QUERYPOS, ref abd);
                
                if (_edge == NativeMethods.ABE_BOTTOM)
                {
                    abd.rc.Left = _currentMonitorInfo.rcMonitor.Left;
                    abd.rc.Right = _currentMonitorInfo.rcMonitor.Right;
                }
                else if (_edge == NativeMethods.ABE_LEFT || _edge == NativeMethods.ABE_RIGHT)
                {
                    abd.rc.Top = _currentMonitorInfo.rcMonitor.Top;
                    abd.rc.Bottom = _currentMonitorInfo.rcMonitor.Bottom;
                }

                NativeMethods.SHAppBarMessage(NativeMethods.ABM_SETPOS, ref abd);
                this.Bounds = abd.rc.ToRectangle();
            }
            catch { }
        }

        public void SetVisibilityState(bool visible)
        {
            if (visible)
            {
                if (!_registered)
                {
                    this.Visible = true;
                    if (this.IsHandleCreated) RegisterAppBar();
                }
                ReassertTopmost();
            }
            else
            {
                if (_registered)
                {
                    UnregisterAppBar();
                    this.Visible = false;
                }
            }
        }

        protected override void OnPaintBackground(PaintEventArgs e) { }

        protected override void OnPaint(PaintEventArgs e)
        {
            try
            {
                if (_settings == null) _settings = new BannerSettings();
                
                Color bg = _settings.BgColor;
                // RAINBOW MODE REMOVED:
                // if (_settings.RainbowMode)
                // {
                //     bg = ColorFromHSV(_hue, 1.0, 0.85);
                // }
                e.Graphics.Clear(bg);
            }
            catch (Exception ex) { Log("OnPaint failed: " + ex.Message); }
            base.OnPaint(e);
        }

        // RAINBOW MODE REMOVED:
        // private static Color ColorFromHSV(double hue, double saturation, double value)
        // {
        //     int hi = Convert.ToInt32(Math.Floor(hue / 60)) % 6;
        //     double f = hue / 60 - Math.Floor(hue / 60);
        //     value = value * 255;
        //     int v = Convert.ToInt32(value);
        //     int p = Convert.ToInt32(value * (1 - saturation));
        //     int q = Convert.ToInt32(value * (1 - f * saturation));
        //     int t = Convert.ToInt32(value * (1 - (1 - f) * saturation));
        //     if (hi == 0) return Color.FromArgb(255, v, t, p);
        //     else if (hi == 1) return Color.FromArgb(255, q, v, p);
        //     else if (hi == 2) return Color.FromArgb(255, p, v, t);
        //     else if (hi == 3) return Color.FromArgb(255, p, q, v);
        //     else if (hi == 4) return Color.FromArgb(255, t, p, v);
        //     else return Color.FromArgb(255, v, p, q);
        // }

        private void UnregisterAppBar()
        {
            if (!_registered) return;
            try
            {
                NativeMethods.APPBARDATA abd = new NativeMethods.APPBARDATA
                {
                    cbSize = Marshal.SizeOf(typeof(NativeMethods.APPBARDATA)),
                    hWnd = this.Handle
                };
                NativeMethods.SHAppBarMessage(NativeMethods.ABM_REMOVE, ref abd);
            }
            catch { }
            _registered = false;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) 
            {
                // RAINBOW MODE REMOVED:
                // StopRainbowTimer();
                UnregisterAppBar();
            }
            base.Dispose(disposing);
        }
    }
}
'@
Set-Content -LiteralPath $borderPath -Value $borderContent -Encoding UTF8
Dbg-File $borderPath

# ---- NetMark\NetMark.csproj -----------------------------------------------
 $bannerCsprojPath = Join-Path $bannerDir 'NetMark.csproj'
 $bannerCsprojContent = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <UseWindowsForms>true</UseWindowsForms>
    <Nullable>disable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <AssemblyName>NetMark</AssemblyName>
    <RootNamespace>NetMark</RootNamespace>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <ApplicationHighDpiMode>PerMonitorV2</ApplicationHighDpiMode>
    <PublishSingleFile>true</PublishSingleFile>
    <SelfContained>true</SelfContained>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
    <EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>
    <DebugType>embedded</DebugType>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="..\Shared\**\*.cs" />
    <EmbeddedResource Include="Configurator.html" />
    <EmbeddedResource Include="NetMark.default.ini" />
  </ItemGroup>
</Project>
'@
Set-Content -LiteralPath $bannerCsprojPath -Value $bannerCsprojContent -Encoding UTF8
Dbg-File $bannerCsprojPath

# ---- NetMark\app.manifest -----------------------------------------------
 $bannerManifestPath = Join-Path $bannerDir 'app.manifest'
 $bannerManifestContent = @'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="NetMark.app" />
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="asInvoker" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
'@
Set-Content -LiteralPath $bannerManifestPath -Value $bannerManifestContent -Encoding UTF8
Dbg-File $bannerManifestPath

# ---- NetMark\Program.cs  (CHANGED: Fixed debounce logic & native process query) ----
 $bannerProgramPath = Join-Path $bannerDir 'Program.cs'
 $bannerProgramContent = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing; 
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using NetMark;

namespace NetMark
{
    internal static class Program
    {
        private static readonly List<BannerWindow>  _windows       = new List<BannerWindow>();
        private static readonly List<BorderWindow>  _borderWindows = new List<BorderWindow>();
        private static List<IntPtr> _monitors = new List<IntPtr>();

        private static System.Threading.Timer _watchdog;
        private static System.Threading.Timer _envVarRefreshTimer;
        private static System.Threading.Timer _envVarDebounce;
        private static System.Threading.Timer _monitorCheckTimer;
        private static IntPtr _winEventHook;
        private static NativeMethods.WinEventDelegate _winEventProc;
        private static FileSystemWatcher _iniWatcher;
        private static Mutex _mutex;

        // >>> CHANGED: RDP state tracking + Fixed Debounce logic
        private static bool _isHiddenForRdpServer = false;
        private static bool _isHiddenForRdpClient = false;
        private static bool _pendingHideState = false;
        private static System.Windows.Forms.Timer _rdpHideDebounceTimer;
        private static MessageWindow _sessionListener;

        [System.Diagnostics.Conditional("DEBUG")]
        private static void Log(string msg)
        {
            System.Diagnostics.Debug.WriteLine($"[NetMark] {msg}");
        }

        [STAThread]
        private static int Main(string[] args)
        {
            Log("NetMark starting (v35 - Default Settings Updated)...");
            
            bool createdNew;
            _mutex = new Mutex(true, "Global\\NetMarkSingleInstance", out createdNew);
            if (!createdNew)
            {
                Log("Another instance is already running. Exiting.");
                return 0;
            }

            try
            {
                Log("Initializing application...");
                Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                AppDomain.CurrentDomain.ProcessExit += (s, e) => Cleanup();

                if (!File.Exists(BannerSettings.GetIniPath()))
                {
                    Log("INI file missing. Extracting embedded default INI...");
                    try
                    {
                        ExtractEmbeddedResource("NetMark.default.ini", BannerSettings.GetIniPath());
                        Log("Extracted default INI to: " + BannerSettings.GetIniPath());
                    }
                    catch (Exception ex)
                    {
                        Log("Failed to extract default INI: " + ex.Message + ". Using runtime defaults.");
                        new BannerSettings().Save();
                    }

                    string htmlPath = Path.Combine(AppContext.BaseDirectory, "Configurator.html");
                    try
                    {
                        if (!File.Exists(htmlPath))
                        {
                            ExtractEmbeddedResource("Configurator.html", htmlPath);
                            Log("Extracted HTML configurator to: " + htmlPath);
                        }
                        if (File.Exists(htmlPath))
                        {
                            Process.Start(new ProcessStartInfo(htmlPath) { UseShellExecute = true });
                        }
                    }
                    catch (Exception ex) { Log("Failed to extract/launch HTML: " + ex.Message); }
                }

                Log("Enumerating monitors...");
                _monitors = new List<IntPtr>();
                NativeMethods.MonitorEnumProc callback = (IntPtr hMon, IntPtr hdc, ref NativeMethods.RECT rc, IntPtr data) =>
                {
                    _monitors.Add(hMon);
                    return true;
                };
                NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);
                Log($"Found {_monitors.Count} monitor(s).");

                Log("Loading settings...");
                BannerSettings settings = BannerSettings.Load() ?? new BannerSettings();

                Log("Evaluating custom env vars...");
                ThreadPool.QueueUserWorkItem(_ =>
                {
                    try
                    {
                        settings.EvaluateCustomEnvVars();
                        foreach (var w in _windows)
                        {
                            if (w != null && w.IsHandleCreated)
                                w.Invoke((Action)(() => w.Invalidate()));
                        }
                    }
                    catch (Exception ex) { Log("Env var eval failed: " + ex.Message); }
                });

                Log("Creating banner windows...");
                foreach (var hMon in _monitors)
                {
                    var w = new BannerWindow(hMon, settings);
                    w.Show();
                    _windows.Add(w);
                }

                Log("Creating border windows (if enabled)...");
                ApplyBorderSettings(settings);

                Log("Setting up RDP session listener...");
                _sessionListener = new MessageWindow();
                
                // Force handle creation so WTSRegisterSessionNotification is called in OnHandleCreated.
                // The Handle property accessor safely invokes CreateHandle() on the UI thread.
                var dummyHandle = _sessionListener.Handle; 
                
                SetRdpServerState(hide: NativeMethods.IsRemoteSession());

                Log("Setting up watchdog, INI watcher, and live env-var refresh...");
                _iniWatcher = new FileSystemWatcher(AppContext.BaseDirectory, "NetMark.ini");
                _iniWatcher.NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size;
                _iniWatcher.Changed += OnIniChanged;
                _iniWatcher.Created += OnIniChanged;
                _iniWatcher.EnableRaisingEvents = true;

                _winEventProc = new NativeMethods.WinEventDelegate(OnWinEvent);
                _winEventHook = NativeMethods.SetWinEventHook(
                    NativeMethods.EVENT_SYSTEM_FOREGROUND, NativeMethods.EVENT_SYSTEM_FOREGROUND,
                    IntPtr.Zero, _winEventProc, 0, 0,
                    NativeMethods.WINEVENT_OUTOFCONTEXT | NativeMethods.WINEVENT_SKIPOWNPROCESS);

                _watchdog = new System.Threading.Timer(_ => EvaluateForegroundState(), null, 250, 250);

                _monitorCheckTimer = new System.Threading.Timer(_ =>
                {
                    try
                    {
                        var currentMonitors = new List<IntPtr>();
                        NativeMethods.MonitorEnumProc monCallback = (IntPtr hMon, IntPtr hdc, ref NativeMethods.RECT rc, IntPtr data) =>
                        {
                            currentMonitors.Add(hMon);
                            return true;
                        };
                        NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, monCallback, IntPtr.Zero);

                        if (currentMonitors.Count != _monitors.Count
                            && _windows.Count > 0
                            && _windows[0].IsHandleCreated)
                        {
                            _windows[0].BeginInvoke((Action)(() => RefreshMonitorsAndWindows()));
                        }
                    }
                    catch { }
                }, null, TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));

                try
                {
                    NetworkChange.NetworkAddressChanged += OnNetworkAddressChanged;
                    Log("Subscribed to NetworkChange.NetworkAddressChanged.");
                }
                catch (Exception ex) { Log("NetworkAddressChanged subscribe failed: " + ex.Message); }

                _envVarRefreshTimer = new System.Threading.Timer(_ => RefreshEnvVars(reason: "poll"),
                    null, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(30));

                Log("Starting application loop...");
                Application.Run();
                Log("Application loop exited.");
            }
            catch (Exception ex)
            {
                Log("FATAL ERROR: " + ex.ToString());
                MessageBox.Show("NetMark crashed:\n\n" + ex.ToString(), "NetMark Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                Cleanup();
            }

            return 0;
        }

        public static void RefreshMonitorsAndWindows()
        {
            _monitors.Clear();
            NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, 
                (IntPtr hMon, IntPtr hdc, ref NativeMethods.RECT rc, IntPtr data) =>
                {
                    _monitors.Add(hMon);
                    return true;
                }, IntPtr.Zero);

            var settings = BannerSettings.Load() ?? new BannerSettings();

            foreach (var w in _windows) w.Dispose();
            _windows.Clear();
            foreach (var w in _borderWindows) w.Dispose();
            _borderWindows.Clear();

            foreach (var hMon in _monitors)
            {
                var w = new BannerWindow(hMon, settings);
                w.Show();
                _windows.Add(w);
            }
            ApplyBorderSettings(settings);

            SetRdpServerState(hide: NativeMethods.IsRemoteSession());
        }

        private static void ApplyBorderSettings(BannerSettings settings)
        {
            bool currentEnabled = _borderWindows.Count > 0;
            bool newEnabled = settings != null && settings.BorderEnabled && settings.BorderSize > 0;
            bool sizeChanged = currentEnabled && newEnabled 
                && (_borderWindows[0].CurrentSettings.BorderSize != settings.BorderSize || _borderWindows[0].CurrentSettings.HeightPx != settings.HeightPx);

            if (currentEnabled != newEnabled || sizeChanged)
            {
                try
                {
                    foreach (var w in _borderWindows) w.Dispose();
                    _borderWindows.Clear();

                    if (newEnabled)
                    {
                        foreach (var hMon in _monitors)
                        {
                            var lw = new BorderWindow(hMon, settings, NativeMethods.ABE_LEFT);
                            lw.Show();
                            _borderWindows.Add(lw);

                            var rw = new BorderWindow(hMon, settings, NativeMethods.ABE_RIGHT);
                            rw.Show();
                            _borderWindows.Add(rw);

                            var bw = new BorderWindow(hMon, settings, NativeMethods.ABE_BOTTOM);
                            bw.Show();
                            _borderWindows.Add(bw);
                        }
                        Log($"Created {_borderWindows.Count} border window(s).");
                    }
                    else
                    {
                        Log("Borders disabled.");
                    }
                }
                catch (Exception ex) { Log("ApplyBorderSettings failed: " + ex.Message); }
            }
            else if (currentEnabled && newEnabled)
            {
                foreach (var w in _borderWindows)
                {
                    w.UpdateSettings(settings);
                }
            }
        }

        private static void ExtractEmbeddedResource(string resourceName, string destinationPath)
        {
            var asm = System.Reflection.Assembly.GetExecutingAssembly();
            System.IO.Stream stream = asm.GetManifestResourceStream(resourceName);
            if (stream == null)
            {
                string actualName = null;
                foreach (var n in asm.GetManifestResourceNames())
                {
                    if (n.EndsWith(resourceName, StringComparison.OrdinalIgnoreCase))
                    {
                        actualName = n;
                        break;
                    }
                }
                if (actualName != null)
                    stream = asm.GetManifestResourceStream(actualName);
            }
            if (stream == null)
                throw new FileNotFoundException($"Embedded resource not found: {resourceName}");

            string dir = Path.GetDirectoryName(destinationPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                Directory.CreateDirectory(dir);

            using (stream)
            using (var fs = new FileStream(destinationPath, FileMode.Create, FileAccess.Write))
            {
                stream.CopyTo(fs);
            }
        }

        private static void OnIniChanged(object sender, FileSystemEventArgs e)
        {
            try
            {
                Log("INI file changed. Reloading...");
                Thread.Sleep(200);
                var newSettings = BannerSettings.Load() ?? new BannerSettings();

                ThreadPool.QueueUserWorkItem(_ =>
                {
                    try
                    {
                        newSettings.EvaluateCustomEnvVars();
                        
                        if (_windows.Count > 0 && _windows[0].IsHandleCreated)
                        {
                            _windows[0].Invoke((Action)(() =>
                            {
                                foreach (var w in _windows)
                                {
                                    if (w != null && w.IsHandleCreated)
                                        w.UpdateSettings(newSettings);
                                }
                                ApplyBorderSettings(newSettings);
                            }));
                        }
                    }
                    catch (Exception ex) { Log("Failed to apply new settings: " + ex.Message); }
                });
            }
            catch { }
        }

        private static void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
        {
            EvaluateForegroundState();
        }

        private static void EvaluateForegroundState()
        {
            if (_windows.Count == 0 || !_windows[0].IsHandleCreated) return;

            _windows[0].BeginInvoke((Action)(() =>
            {
                bool isRemoteClient = false;
                bool isFullScreen = false;
                IntPtr fg = IntPtr.Zero;
                try
                {
                    fg = NativeMethods.GetForegroundWindow();
                    if (fg != IntPtr.Zero)
                    {
                        string name = GetProcessNameFromHwnd(fg);
                        isRemoteClient = name == "mstsc" || name == "msrdc" || name == "cdviewer" || name == "wfica32" || name == "vmware-view" || name == "rdpclient";
                        if (isRemoteClient)
                        {
                            isFullScreen = IsWindowFullScreen(fg);
                        }
                    }
                }
                catch { }

                SetRemoteClientState(isRemoteClient && isFullScreen);

                if (!_isHiddenForRdpClient && !_isHiddenForRdpServer)
                {
                    IntPtr top = NativeMethods.GetTopWindow(NativeMethods.GetDesktopWindow());
                    bool ours = false;
                    foreach (var w in _windows)       if (w.Handle == top) { ours = true; break; }
                    if (!ours) foreach (var w in _borderWindows) if (w.Handle == top) { ours = true; break; }
                    
                    if (!ours)
                    {
                        foreach (var w in _windows)       w.ReassertTopmost();
                        foreach (var w in _borderWindows) w.ReassertTopmost();
                    }
                }
            }));
        }

        private static string GetProcessNameFromHwnd(IntPtr hwnd)
        {
            uint pid;
            NativeMethods.GetWindowThreadProcessId(hwnd, out pid);
            if (pid == 0) return "";
            
            IntPtr hProcess = NativeMethods.OpenProcess(NativeMethods.PROCESS_QUERY_INFORMATION | NativeMethods.PROCESS_VM_READ, false, pid);
            if (hProcess == IntPtr.Zero) return "";
            
            StringBuilder sb = new StringBuilder(260);
            uint size = 260;
            bool success = NativeMethods.QueryFullProcessImageName(hProcess, 0, sb, ref size);
            NativeMethods.CloseHandle(hProcess);
            
            if (success)
            {
                return System.IO.Path.GetFileNameWithoutExtension(sb.ToString()).ToLowerInvariant();
            }
            return "";
        }

        private static bool IsWindowFullScreen(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero) return false;
            
            NativeMethods.RECT wndRect;
            if (!NativeMethods.GetWindowRect(hwnd, out wndRect)) return false;
            
            IntPtr monitor = NativeMethods.MonitorFromRect(ref wndRect, NativeMethods.MONITOR_DEFAULTTONEAREST);
            if (monitor == IntPtr.Zero) return false;

            NativeMethods.MONITORINFOEX mi = new NativeMethods.MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(typeof(NativeMethods.MONITORINFOEX));
            if (!NativeMethods.GetMonitorInfo(monitor, ref mi)) return false;

            return wndRect.Left <= mi.rcMonitor.Left + 5 &&
                   wndRect.Top <= mi.rcMonitor.Top + 5 &&
                   wndRect.Right >= mi.rcMonitor.Right - 5 &&
                   wndRect.Bottom >= mi.rcMonitor.Bottom - 5;
        }

        private static void RefreshEnvVars(string reason)
        {
            try
            {
                if (_windows.Count == 0) return;
                var s = _windows[0].CurrentSettings;
                if (s == null) return;

                Log($"Refreshing env vars ({reason})...");
                
                // Invalidate the native IP cache so the next ExpandText() call
                // queries live network state instead of returning the cached value.
                BannerSettings.InvalidateIpCache();
                
                s.EvaluateCustomEnvVars();
                foreach (var w in _windows)
                {
                    if (w != null && w.IsHandleCreated)
                        w.Invoke((Action)(() => w.Invalidate()));
                }
            }
            catch (Exception ex) { Log($"Env var refresh ({reason}) failed: " + ex.Message); }
        }

        private static void OnNetworkAddressChanged(object sender, EventArgs e)
        {
            try
            {
                Log("NetworkAddressChanged event received. Debouncing...");
                _envVarDebounce?.Dispose();
                _envVarDebounce = new System.Threading.Timer(_ => RefreshEnvVars(reason: "network-change"),
                    null, TimeSpan.FromSeconds(2), Timeout.InfiniteTimeSpan);
            }
            catch (Exception ex) { Log("OnNetworkAddressChanged failed: " + ex.Message); }
        }

        private sealed class MessageWindow : Form
        {
            public MessageWindow()
            {
                this.ShowInTaskbar = false;
                this.FormBorderStyle = FormBorderStyle.None;
                this.ClientSize = new System.Drawing.Size(0, 0); 
                this.Opacity = 0;
            }

            protected override void OnHandleCreated(EventArgs e)
            {
                base.OnHandleCreated(e);
                NativeMethods.WTSRegisterSessionNotification(this.Handle, NativeMethods.NOTIFY_FOR_THIS_SESSION);
            }

            protected override void WndProc(ref Message m)
            {
                if (m.Msg == NativeMethods.WM_WTSSESSION_CHANGE)
                {
                    int eventType = m.WParam.ToInt32();
                    Program.OnSessionChange(eventType);
                }
                base.WndProc(ref m);
            }

            protected override void Dispose(bool disposing)
            {
                if (disposing && this.IsHandleCreated)
                {
                    NativeMethods.WTSUnRegisterSessionNotification(this.Handle);
                }
                base.Dispose(disposing);
            }
        }

        public static void OnSessionChange(int eventType)
        {
            Log($"WTS Session Event: {eventType}");
            switch (eventType)
            {
                case NativeMethods.WTS_REMOTE_CONNECT:
                    SetRdpServerState(hide: true);
                    break;
                case NativeMethods.WTS_CONSOLE_CONNECT:
                case NativeMethods.WTS_REMOTE_DISCONNECT:
                    SetRdpServerState(hide: NativeMethods.IsRemoteSession());
                    break;
            }
        }

        private static void SetRemoteClientState(bool hide)
        {
            if (_pendingHideState == hide) return; // Only act if state is actually changing
            _pendingHideState = hide;

            if (hide)
            {
                if (_rdpHideDebounceTimer == null)
                {
                    _rdpHideDebounceTimer = new System.Windows.Forms.Timer();
                    _rdpHideDebounceTimer.Interval = 500;
                    _rdpHideDebounceTimer.Tick += (s, e) => 
                    {
                        _rdpHideDebounceTimer.Stop();
                        _isHiddenForRdpClient = true;
                        EvaluateVisibilityState();
                    };
                }
                if (!_rdpHideDebounceTimer.Enabled)
                {
                    _rdpHideDebounceTimer.Start();
                }
            }
            else
            {
                if (_rdpHideDebounceTimer != null) _rdpHideDebounceTimer.Stop();
                _isHiddenForRdpClient = false;
                EvaluateVisibilityState();
            }
        }

        private static void SetRdpServerState(bool hide)
        {
            if (_isHiddenForRdpServer == hide) return;
            _isHiddenForRdpServer = hide;
            EvaluateVisibilityState();
        }

        private static void EvaluateVisibilityState()
        {
            bool hide = _isHiddenForRdpServer || _isHiddenForRdpClient;
            
            Log(hide ? "Hiding NetMark (RDP session active)" : "Restoring NetMark (Console session active)");

            foreach (var w in _windows) w.SetVisibilityState(!hide);
            foreach (var w in _borderWindows) w.SetVisibilityState(!hide);
        }

        private static void Cleanup()
        {
            try
            {
                if (_winEventHook != IntPtr.Zero) NativeMethods.UnhookWinEvent(_winEventHook);
                _watchdog?.Dispose();
                _envVarRefreshTimer?.Dispose();
                _envVarDebounce?.Dispose();
                _monitorCheckTimer?.Dispose();
                _iniWatcher?.Dispose();
                
                _rdpHideDebounceTimer?.Dispose();
                _sessionListener?.Dispose(); 

                foreach (var w in _borderWindows) w.Dispose();
                _borderWindows.Clear();
                foreach (var w in _windows) w.Dispose();
                _windows.Clear();
            }
            catch { }
        }
    }
}
'@
Set-Content -LiteralPath $bannerProgramPath -Value $bannerProgramContent -Encoding UTF8
Dbg-File $bannerProgramPath

# ---- NetMark\Configurator.html -----------------------------------------
 $htmlPath = Join-Path $bannerDir 'Configurator.html'
 $htmlContent = @'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>NetMark Configurator</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-app: #f4f6fb;
      --bg-surface: #ffffff;
      --bg-surface-subtle: #f1f5f9;
      --bg-surface-hover: #e2e8f0;
      --border-subtle: #e2e8f0;
      --border-strong: #cbd5e1;
      --border-focus: #2563eb;
      --text-primary: #0f172a;
      --text-secondary: #475569;
      --text-tertiary: #94a3b8;
      --accent: #2563eb;
      --accent-hover: #1d4ed8;
      --accent-subtle: #eff6ff;
      --accent-text: #1d4ed8;
      --danger: #ef4444;
      --danger-hover: #dc2626;
      --danger-subtle: #fef2f2;
      --success: #10b981;
      --warning: #f59e0b;
      --radius-sm: 6px;
      --radius-md: 10px;
      --radius-lg: 14px;
      --radius-xl: 20px;
      --shadow-xs: 0 1px 2px rgba(0, 0, 0, 0.04);
      --shadow-sm: 0 2px 4px rgba(0, 0, 0, 0.05);
      --shadow-md: 0 6px 16px -2px rgba(0, 0, 0, 0.08), 0 2px 6px -1px rgba(0, 0, 0, 0.04);
      --shadow-lg: 0 12px 28px -4px rgba(0, 0, 0, 0.12), 0 4px 10px -2px rgba(0, 0, 0, 0.05);
      --transition-fast: 150ms cubic-bezier(0.4, 0, 0.2, 1);
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: var(--bg-app);
      font-family: 'Inter', system-ui, -apple-system, sans-serif;
      color: var(--text-primary);
      -webkit-font-smoothing: antialiased;
      line-height: 1.5;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }
    #screenSimulator {
      position: fixed; inset: 0; pointer-events: none; z-index: 9999; border: 0 solid transparent;
    }
    #bannerWrapper {
      position: sticky;
      top: 0;
      z-index: 100;
      background: var(--bg-app);
      padding-bottom: 15px; 
    }
    .live-appbar-strip {
      width: 100%;
      display: grid; grid-template-columns: 1fr 1fr 1fr;
      align-items: center; padding: 0 12px;
      white-space: nowrap; overflow: hidden;
      transition: background-color var(--transition-fast), color var(--transition-fast), height var(--transition-fast), box-shadow var(--transition-fast);
      box-sizing: border-box;
    }
    .banner-slot {
      display: flex;
      align-items: center;
      height: 100%;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      padding: 0 4px;
    }
    .slot-left { justify-content: flex-start; }
    .slot-center { justify-content: center; }
    .slot-right { justify-content: flex-end; }
    header.app-header {
      background: var(--bg-surface); border-bottom: 1px solid var(--border-subtle);
      padding: 12px 28px; display: flex; align-items: center; justify-content: space-between;
    }
    .brand-group { display: flex; align-items: center; gap: 12px; transition: opacity 0.3s ease, transform 0.3s ease; }
    .brand-group.hidden { opacity: 0; transform: translateX(-20px); pointer-events: none; }
    .brand-icon {
      width: 36px; height: 36px;
      background: linear-gradient(135deg, var(--accent) 0%, #1d4ed8 100%);
      color: #fff; border-radius: var(--radius-md);
      display: flex; align-items: center; justify-content: center;
      font-size: 18px; box-shadow: 0 2px 6px rgba(37, 99, 235, 0.3);
      cursor: pointer; user-select: none; transition: transform 0.3s ease;
    }
    .brand-icon.spin { transform: rotate(360deg); }
    .brand-text h1 { font-size: 16px; font-weight: 700; letter-spacing: -0.02em; }
    .brand-text p { font-size: 12px; color: var(--text-tertiary); }
    .app-main { flex: 1; max-width: 1100px; width: 100%; margin: 0 auto; padding: 24px 28px 120px 28px; display: flex; flex-direction: column; gap: 20px; }
    .card { background: var(--bg-surface); border: 1px solid var(--border-subtle); border-radius: var(--radius-lg); padding: 20px; box-shadow: var(--shadow-xs); transition: border-color var(--transition-fast); }
    .card:hover { border-color: var(--border-strong); }
    .card-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px; padding-bottom: 12px; border-bottom: 1px solid var(--border-subtle); }
    .card-title { font-size: 15px; font-weight: 700; color: var(--text-primary); display: flex; align-items: center; gap: 10px; }
    .step-number { width: 26px; height: 26px; border-radius: 50%; background: var(--accent); color: #fff; font-size: 13px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0; }
    .card-subtitle { font-size: 13px; color: var(--text-secondary); margin-top: 4px; line-height: 1.45; }
    .form-group { margin-bottom: 16px; }
    .form-group:last-child { margin-bottom: 0; }
    .field-label { display: flex; justify-content: space-between; align-items: center; font-size: 13px; font-weight: 600; color: var(--text-secondary); margin-bottom: 6px; }
    .field-hint { font-size: 11px; font-weight: 400; color: var(--text-tertiary); }
    .input-mono { font-family: 'JetBrains Mono', monospace; font-size: 13px; }
    .input-text { width: 100%; height: 40px; padding: 0 12px; background: var(--bg-surface); border: 1px solid var(--border-strong); border-radius: var(--radius-sm); color: var(--text-primary); outline: none; transition: all var(--transition-fast); }
    .input-text:focus { border-color: var(--border-focus); box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12); }
    .preset-chips { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
    .chip-btn { background: var(--bg-surface-subtle); border: 1px solid var(--border-subtle); border-radius: var(--radius-sm); padding: 4px 9px; font-size: 11.5px; font-weight: 600; color: var(--text-secondary); cursor: pointer; font-family: 'JetBrains Mono', monospace; transition: all var(--transition-fast); }
    .chip-btn:hover { background: var(--bg-surface-hover); color: var(--text-primary); border-color: var(--border-strong); }
    .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
    @media (max-width: 600px) { .grid-2 { grid-template-columns: 1fr; } }
    .color-picker-btn { display: flex; align-items: center; gap: 10px; padding: 6px 10px; background: var(--bg-surface); border: 1px solid var(--border-strong); border-radius: var(--radius-sm); cursor: pointer; width: 100%; height: 40px; transition: all var(--transition-fast); }
    .color-picker-btn:hover { background: var(--bg-surface-subtle); border-color: var(--border-focus); }
    .color-circle { width: 22px; height: 22px; border-radius: 50%; border: 1px solid rgba(0,0,0,0.12); flex-shrink: 0; box-shadow: inset 0 1px 2px rgba(0,0,0,0.1); }
    .color-label-val { font-family: 'JetBrains Mono', monospace; font-size: 12px; font-weight: 600; color: var(--text-primary); }
    .slider-container { display: flex; align-items: center; gap: 12px; }
    .slider-input { flex: 1; accent-color: var(--accent); cursor: pointer; }
    .slider-val-badge { font-family: 'JetBrains Mono', monospace; background: var(--bg-surface-subtle); border: 1px solid var(--border-subtle); padding: 4px 8px; border-radius: var(--radius-sm); font-size: 12px; font-weight: 600; min-width: 56px; text-align: center; }
    .toggle-row { display: flex; align-items: center; justify-content: space-between; padding: 10px 12px; background: var(--bg-surface-subtle); border-radius: var(--radius-sm); border: 1px solid var(--border-subtle); }
    .toggle-label { font-size: 13px; font-weight: 600; color: var(--text-secondary); }
    .toggle-hint { font-size: 11px; color: var(--text-tertiary); margin-top: 2px; }
    .switch { position: relative; display: inline-block; width: 42px; height: 24px; flex-shrink: 0; }
    .switch input { opacity: 0; width: 0; height: 0; }
    .slider-toggle { position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background: #cbd5e1; border-radius: 999px; transition: var(--transition-fast); }
    .slider-toggle:before { position: absolute; content: ""; height: 18px; width: 18px; left: 3px; bottom: 3px; background: #fff; border-radius: 50%; transition: var(--transition-fast); box-shadow: 0 1px 3px rgba(0,0,0,0.25); }
    .switch input:checked + .slider-toggle { background: var(--accent); }
    .switch input:checked + .slider-toggle:before { transform: translateX(18px); }
    .style-pills { display: flex; gap: 6px; flex-wrap: wrap; }
    .style-pill { display: inline-flex; align-items: center; gap: 6px; padding: 6px 12px; background: var(--bg-surface-subtle); border: 1px solid var(--border-subtle); border-radius: 999px; font-size: 12.5px; font-weight: 600; color: var(--text-secondary); cursor: pointer; transition: all var(--transition-fast); user-select: none; }
    .style-pill input { accent-color: var(--accent); cursor: pointer; }
    .style-pill:has(input:checked) { background: var(--accent-subtle); border-color: var(--accent); color: var(--accent-text); }
    details.card { padding: 0; overflow: hidden; }
    details.card > summary { list-style: none; cursor: pointer; padding: 20px; display: flex; align-items: center; justify-content: space-between; user-select: none; }
    details.card > summary::-webkit-details-marker { display: none; }
    details.card[open] > summary { border-bottom: 1px solid var(--border-subtle); }
    .summary-content { display: flex; flex-direction: column; gap: 2px; }
    .chevron { transition: transform 0.2s ease; font-size: 14px; color: var(--text-tertiary); }
    details.card[open] > summary .chevron { transform: rotate(180deg); }
    .preset-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px; }
    .preset-card { cursor: pointer; border: 2px solid var(--border-subtle); border-radius: var(--radius-md); overflow: hidden; transition: all var(--transition-fast); background: var(--bg-surface); }
    .preset-card:hover { border-color: var(--accent); transform: translateY(-1px); box-shadow: var(--shadow-md); }
    .preset-card.active { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.18); }
    .preset-preview { height: 36px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 700; padding: 0 8px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: 'JetBrains Mono', monospace; }
    .preset-meta { padding: 6px 10px; background: var(--bg-surface-subtle); font-size: 11px; color: var(--text-secondary); font-weight: 600; display: flex; align-items: center; justify-content: space-between; }
    .preset-meta-dot { width: 10px; height: 10px; border-radius: 50%; border: 1px solid rgba(0,0,0,0.15); }
    .env-list { display: flex; flex-direction: column; gap: 12px; padding: 20px; }
    .env-row { display: grid; grid-template-columns: 1fr 2fr auto; gap: 12px; align-items: end; padding: 12px; background: var(--bg-surface-subtle); border-radius: var(--radius-md); border: 1px solid var(--border-subtle); }
    .env-input-group { display: flex; flex-direction: column; gap: 4px; }
    .env-input-group label { font-size: 11px; font-weight: 600; color: var(--text-tertiary); text-transform: uppercase; letter-spacing: 0.5px; }
    .env-input-group input { width: 100%; height: 38px; padding: 0 12px; background: var(--bg-surface); border: 1px solid var(--border-strong); border-radius: var(--radius-sm); color: var(--text-primary); outline: none; font-family: 'JetBrains Mono', monospace; font-size: 13px; transition: all var(--transition-fast); }
    .env-input-group input:focus { border-color: var(--border-focus); box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12); }
    .btn-icon-danger { background: var(--bg-surface); border: 1px solid var(--border-strong); color: var(--danger); width: 38px; height: 38px; border-radius: var(--radius-sm); cursor: pointer; display: flex; align-items: center; justify-content: center; transition: all var(--transition-fast); }
    .btn-icon-danger:hover { background: var(--danger-subtle); border-color: var(--danger); }
    .btn { display: inline-flex; align-items: center; justify-content: center; gap: 8px; padding: 0 16px; height: 42px; width: 160px; border-radius: var(--radius-sm); font-size: 14px; font-weight: 600; cursor: pointer; border: 1px solid transparent; transition: all var(--transition-fast); user-select: none; }
    .btn-primary { background: var(--accent); color: #fff; box-shadow: 0 2px 4px rgba(37, 99, 235, 0.2); }
    .btn-primary:hover { background: var(--accent-hover); box-shadow: 0 4px 10px rgba(37, 99, 235, 0.3); }
    .btn-secondary { background: var(--bg-surface); border-color: var(--border-strong); color: var(--text-primary); }
    .btn-secondary:hover { background: var(--bg-surface-subtle); border-color: var(--border-focus); }
    .btn-sm { height: 32px; padding: 0 12px; font-size: 12px; width: auto; }
    .help-callout { background: #fffbeb; border: 1px solid #fde68a; border-radius: var(--radius-sm); padding: 8px 12px; font-size: 12px; color: #92400e; margin-top: 8px; line-height: 1.5; }
    .info-callout { background: var(--accent-subtle); border: 1px solid #bfdbfe; border-radius: var(--radius-sm); padding: 8px 12px; font-size: 12px; color: #1e40af; margin-top: 8px; line-height: 1.5; }
    .floating-actions {
      position: fixed; bottom: 24px; right: 24px; z-index: 2000;
      display: flex; flex-direction: column; gap: 10px; align-items: stretch; width: 160px;
    }
    /* RAINBOW MODE REMOVED:
    #rainbowEggCard {
      display: none; border: 2px dashed var(--accent); animation: dropIn 0.5s ease;
    }
    @keyframes dropIn { from { transform: translateY(-20px); opacity: 0; } to { transform: translateY(0); opacity: 1; } }
    */

    /* Custom Modal Dialog */
    .modal-overlay {
      position: fixed; top: 0; left: 0; right: 0; bottom: 0;
      background: rgba(15, 23, 42, 0.6); backdrop-filter: blur(4px);
      display: flex; align-items: center; justify-content: center; z-index: 3000;
      opacity: 0; pointer-events: none; transition: opacity 0.2s ease;
    }
    .modal-overlay.active { opacity: 1; pointer-events: auto; }
    .modal-box {
      background: var(--bg-surface); border-radius: var(--radius-lg);
      box-shadow: var(--shadow-lg); padding: 28px; max-width: 420px; width: 90%;
      transform: scale(0.95); transition: transform 0.2s ease; text-align: center;
    }
    .modal-overlay.active .modal-box { transform: scale(1); }
    .modal-icon { width: 48px; height: 48px; background: var(--accent-subtle); color: var(--accent); border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 24px; margin: 0 auto 16px; }
    .modal-box h3 { font-size: 18px; font-weight: 700; margin-bottom: 8px; }
    .modal-box p { font-size: 14px; color: var(--text-secondary); margin-bottom: 20px; line-height: 1.5; }
  </style>
</head>
<body>
  <div id="screenSimulator"></div>
  <div id="bannerWrapper">
    <div id="liveBanner" class="live-appbar-strip">
      <div id="slotLeft" class="banner-slot slot-left"></div>
      <div id="slotCenter" class="banner-slot slot-center"></div>
      <div id="slotRight" class="banner-slot slot-right"></div>
    </div>
  </div>
  <header class="app-header">
    <div class="brand-group" id="brandGroup">
      <div class="brand-icon" id="brandIcon">&#x2699;</div>
      <div class="brand-text">
        <h1>NetMark Configurator</h1>
        <p>Set up your desktop classification banner in three easy steps.</p>
      </div>
    </div>
  </header>
  <main class="app-main">
    <section class="card">
      <div class="card-header">
        <div>
          <h2 class="card-title"><span class="step-number">1</span> Banner Text</h2>
          <p class="card-subtitle">Type the words you want to see in the banner. Special words like <code>%COMPUTERNAME%</code> or <code>%USERNAME%</code> are replaced automatically with real values.</p>
        </div>
      </div>
      <div class="form-group">
        <div class="field-label"><span>Left side</span><span class="field-hint">Optional &mdash; usually left blank</span></div>
        <input type="text" id="txtLeft" class="input-text input-mono" placeholder="e.g. SYSTEM: %COMPUTERNAME%" value="%IP_ADDRESS%">
        <div class="preset-chips">
          <button class="chip-btn" onclick="insertMacro('txtLeft', '%COMPUTERNAME%')">+ Computer name</button>
          <button class="chip-btn" onclick="insertMacro('txtLeft', '%IP_ADDRESS%')">+ IP address</button>
        </div>
      </div>
      <div class="form-group">
        <div class="field-label"><span>Center (main message)</span><span class="field-hint">This is the big classification text</span></div>
        <input type="text" id="txtCenter" class="input-text input-mono" value="%COMPUTERNAME%">
        <div class="preset-chips">
          <button class="chip-btn" onclick="insertMacro('txtCenter', '%COMPUTERNAME%')">+ Computer name</button>
          <button class="chip-btn" onclick="insertMacro('txtCenter', '%USERNAME%')">+ Username</button>
        </div>
      </div>
      <div class="form-group">
        <div class="field-label"><span>Right side</span><span class="field-hint">Often shows who is logged in</span></div>
        <input type="text" id="txtRight" class="input-text input-mono" value="%USERNAME%">
        <div class="preset-chips">
          <button class="chip-btn" onclick="insertMacro('txtRight', '%USERNAME%')">+ Username</button>
          <button class="chip-btn" onclick="insertMacro('txtRight', '%USERDOMAIN%\\%USERNAME%')">+ Domain\Username</button>
          <button class="chip-btn" onclick="insertMacro('txtRight', '%IP_ADDRESS%')">+ IP address</button>
        </div>
      </div>
      <div class="help-callout"><strong>Tip:</strong> Click the small chips above to insert special values. <code>%COMPUTERNAME%</code> shows your PC name, <code>%USERNAME%</code> shows your login name, <code>%IP_ADDRESS%</code> shows your network IP (resolved natively by C# &mdash; no PowerShell needed).</div>
    </section>
    
    <section class="card">
      <div class="card-header">
        <div>
          <h2 class="card-title"><span class="step-number">2</span> USA Classification Levels</h2>
          <p class="card-subtitle">Click a level to apply standard text and colors. Showing common levels.</p>
        </div>
      </div>
      <div class="preset-grid" id="presetGridCommon"></div>
      <div id="presetExpandWrapper" style="display: none; padding-top: 20px;">
        <div class="preset-grid" id="presetGridAll"></div>
      </div>
      <div style="text-align: center; padding: 20px;">
        <button type="button" class="btn btn-secondary btn-sm" id="expandPresetsBtn" onclick="togglePresets()">Show All Levels</button>
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div>
          <h2 class="card-title"><span class="step-number">3</span> Customize Look</h2>
          <p class="card-subtitle">Change colors, fonts, size, add drop shadows, and wrap a border around the screen edges.</p>
        </div>
      </div>
      <div class="grid-2">
        <div class="form-group">
          <div class="field-label"><span>Background color</span><span class="field-hint">The bar color</span></div>
          <label class="color-picker-btn">
            <span class="color-circle" id="bgCircle" style="background-color: #007a33;"></span>
            <span class="color-label-val" id="bgHexLabel">#007A33</span>
            <input type="color" id="pickerBg" style="opacity: 0; width: 0; height: 0; position: absolute;" value="#007a33" oninput="syncColor('bg', this.value)">
          </label>
        </div>
        <div class="form-group">
          <div class="field-label"><span>Text color</span><span class="field-hint">Words color</span></div>
          <label class="color-picker-btn">
            <span class="color-circle" id="fgCircle" style="background-color: #ffffff;"></span>
            <span class="color-label-val" id="fgHexLabel">#FFFFFF</span>
            <input type="color" id="pickerFg" style="opacity: 0; width: 0; height: 0; position: absolute;" value="#ffffff" oninput="syncColor('fg', this.value)">
          </label>
        </div>
      </div>
      <div class="form-group">
        <div class="field-label"><span>Banner height</span><span class="field-hint">How tall the bar is on screen</span></div>
        <div class="slider-container">
          <input type="range" id="sliderHeight" class="slider-input" min="16" max="64" value="24" oninput="syncHeight(this.value)">
          <div class="slider-val-badge" id="heightBadge">24 px</div>
        </div>
      </div>
      <div class="grid-2">
        <div class="form-group">
          <div class="field-label"><span>Left margin</span><span class="field-hint">Padding from left edge</span></div>
          <div class="slider-container">
            <input type="range" id="sliderMarginLeft" class="slider-input" min="0" max="100" value="25" oninput="syncMarginLeft(this.value)">
            <div class="slider-val-badge" id="marginLeftBadge">25 px</div>
          </div>
        </div>
        <div class="form-group">
          <div class="field-label"><span>Right margin</span><span class="field-hint">Padding from right edge</span></div>
          <div class="slider-container">
            <input type="range" id="sliderMarginRight" class="slider-input" min="0" max="100" value="25" oninput="syncMarginRight(this.value)">
            <div class="slider-val-badge" id="marginRightBadge">25 px</div>
          </div>
        </div>
      </div>
      <div class="form-group">
        <div class="toggle-row">
          <div>
            <div class="toggle-label">Banner drop shadow</div>
            <div class="toggle-hint">Adds a soft shadow below and around the banner so it stands out from the desktop.</div>
          </div>
          <label class="switch"><input type="checkbox" id="chkBannerShadow" onchange="updateAll()"><span class="slider-toggle"></span></label>
        </div>
      </div>
      <div style="height: 1px; background: var(--border-subtle); margin: 18px 0;"></div>
      <div class="form-group">
        <div class="toggle-row">
          <div>
            <div class="toggle-label">Screen border (left, right, bottom)</div>
            <div class="toggle-hint">Wraps a colored border around the left, right, and bottom of every monitor. Same color as the banner. Reserves screen space so maximized windows avoid it &mdash; just like the top banner.</div>
          </div>
          <label class="switch"><input type="checkbox" id="chkBorderEnabled" checked onchange="updateAll()"><span class="slider-toggle"></span></label>
        </div>
      </div>
      <div class="form-group" id="borderSizeGroup" style="opacity: 1; pointer-events: auto;">
        <div class="field-label"><span>Border thickness</span><span class="field-hint">In pixels</span></div>
        <div class="slider-container">
          <input type="range" id="sliderBorderSize" class="slider-input" min="0" max="24" value="0" oninput="syncBorderSize(this.value)">
          <div class="slider-val-badge" id="borderSizeBadge">0 px</div>
        </div>
        <div class="info-callout">The border color automatically matches the banner background color. Change the background color above to change the border color.</div>
      </div>
      <div style="height: 1px; background: var(--border-subtle); margin: 18px 0;"></div>
      <div class="grid-2">
        <div class="form-group">
          <div class="field-label"><span>Font</span><span class="field-hint">Letter style</span></div>
          <select id="selFontFamily" class="input-text" onchange="updateAll()">
            <optgroup label="Sans-serif (clean, modern)">
              <option value="Segoe UI" selected>Segoe UI</option>
              <option value="Arial">Arial</option>
              <option value="Calibri">Calibri</option>
              <option value="Candara">Candara</option>
              <option value="Corbel">Corbel</option>
              <option value="Franklin Gothic Medium">Franklin Gothic Medium</option>
              <option value="Microsoft Sans Serif">Microsoft Sans Serif</option>
              <option value="Tahoma">Tahoma</option>
              <option value="Trebuchet MS">Trebuchet MS</option>
              <option value="Verdana">Verdana</option>
            </optgroup>
            <optgroup label="Serif (classic, formal)">
              <option value="Cambria">Cambria</option>
              <option value="Constantia">Constantia</option>
              <option value="Georgia">Georgia</option>
              <option value="Palatino Linotype">Palatino Linotype</option>
              <option value="Times New Roman">Times New Roman</option>
            </optgroup>
            <optgroup label="Monospace (technical)">
              <option value="Consolas">Consolas</option>
              <option value="Courier New">Courier New</option>
              <option value="Lucida Console">Lucida Console</option>
            </optgroup>
            <optgroup label="Decorative / Other">
              <option value="Comic Sans MS">Comic Sans MS</option>
              <option value="Gabriola">Gabriola</option>
              <option value="Impact">Impact</option>
            </optgroup>
          </select>
        </div>
        <div class="form-group">
          <div class="field-label"><span>Font size</span><span class="field-hint">In points</span></div>
          <div style="display: flex; gap: 8px; align-items: center;">
            <input type="number" id="numFontSize" class="input-text input-mono" style="width: 80px;" min="6" max="36" value="10" oninput="updateAll()">
            <span style="font-size: 12px; color: var(--text-tertiary);">pt</span>
          </div>
        </div>
      </div>
      <div class="form-group">
        <div class="field-label"><span>Text style</span><span class="field-hint">Mix and match</span></div>
        <div class="style-pills">
          <label class="style-pill"><input type="checkbox" id="chkFontBold" checked onchange="updateAll()"> <strong>Bold</strong></label>
          <label class="style-pill"><input type="checkbox" id="chkFontItalic" onchange="updateAll()"> <em>Italic</em></label>
          <label class="style-pill"><input type="checkbox" id="chkFontUnderline" onchange="updateAll()"> <u>Underline</u></label>
        </div>
      </div>
      <div style="height: 1px; background: var(--border-subtle); margin: 18px 0;"></div>
      
      <div class="form-group">
        <div class="toggle-row">
          <div>
            <div class="toggle-label">Text drop shadow</div>
            <div class="toggle-hint">Adds a shadow behind the letters. Great for low-contrast color combos (like orange on yellow).</div>
          </div>
          <label class="switch"><input type="checkbox" id="chkTextShadow" onchange="updateAll()"><span class="slider-toggle"></span></label>
        </div>
      </div>
      <div class="grid-2" id="textShadowControls" style="margin-top: 12px; opacity: 0.5; pointer-events: none;">
        <div class="form-group">
          <div class="field-label"><span>Shadow color</span></div>
          <label class="color-picker-btn">
            <span class="color-circle" id="tscCircle" style="background-color: #404040;"></span>
            <span class="color-label-val" id="tscHexLabel">#404040</span>
            <input type="color" id="pickerTextShadow" style="opacity: 0; width: 0; height: 0; position: absolute;" value="#404040" oninput="syncColor('tsc', this.value)">
          </label>
        </div>
        <div class="form-group">
          <div class="field-label"><span>Shadow offset</span><span class="field-hint">How far the shadow sticks out</span></div>
          <div class="slider-container">
            <input type="range" id="sliderTextShadowOffset" class="slider-input" min="1" max="6" value="2" oninput="syncTextShadowOffset(this.value)">
            <div class="slider-val-badge" id="tsOffsetBadge">2 px</div>
          </div>
        </div>
      </div>
    </section>

    <details class="card">
      <summary>
        <div class="summary-content">
          <h2 class="card-title">&#x2699;&#xFE0F; Custom Variables <span style="font-size: 11px; font-weight: 600; color: var(--text-tertiary); background: var(--bg-surface-subtle); padding: 2px 8px; border-radius: 999px; margin-left: 4px;">Advanced</span></h2>
          <p class="card-subtitle" style="margin-left: 36px;">Create custom static text values. Hidden by default to keep things clean.</p>
        </div>
        <span class="chevron">&#x25BC;</span>
      </summary>
      <div class="env-list" id="envList"></div>
      <div style="padding: 0 20px 20px 20px;">
        <button class="btn btn-secondary btn-sm" onclick="addEnvRow('', '')">+ Add Variable</button>
        <div class="help-callout"><strong>Note:</strong> <code>%IP_ADDRESS%</code> is now a built-in variable resolved natively via C# (<code>System.Net.NetworkInformation</code>) &mdash; no PowerShell subprocess needed. You can still create custom variables here with static text values. Use <code>%VAR_NAME%</code> in your banner text to reference them. The running banner refreshes the IP address within ~2 seconds of any network change.</div>
      </div>
    </details>

    <!-- RAINBOW MODE REMOVED:
    <section class="card" id="rainbowEggCard" style="text-align: center;">
      <div class="toggle-row" style="display: inline-flex; padding: 12px 24px; border: none; background: transparent;">
        <div style="margin-right: 12px;">
          <div class="toggle-label" style="font-size: 14px;">🌈 Enable Rainbow Mode</div>
          <div class="toggle-hint">You found the secret feature! Cycles the banner background through the rainbow.</div>
        </div>
        <label class="switch"><input type="checkbox" id="chkRainbowMode" onchange="updateAll()"><span class="slider-toggle"></span></label>
      </div>
    </section>
    -->
  </main>

  <div class="floating-actions">
    <button type="button" class="btn btn-primary" onclick="downloadIni()"><span>&#x1F4BE;</span> Save Settings</button>
    <button type="button" class="btn btn-secondary" onclick="resetToDefaults()"><span>&#x21BA;</span> Reset</button>
  </div>

  <div class="modal-overlay" id="customAlert">
    <div class="modal-box">
      <div class="modal-icon">&#x2714;</div>
      <h3>Saved Successfully</h3>
      <p id="modalMessage">Please ensure this NetMark.ini file is placed in the same directory as NetMark.exe for the changes to take effect. The running banner will update automatically. The IP address refreshes natively within ~2 seconds of any network change (no PowerShell subprocess).</p>
      <button class="btn btn-primary" onclick="closeModal()">OK</button>
    </div>
  </div>

  <script>
    const PRESETS = [
      { name: "UNCLASSIFIED",            text: "UNCLASSIFIED",                       bg: "#007a33", fg: "#ffffff", desc: "Standard" },
      { name: "UNCLASSIFIED // FOUO",    text: "UNCLASSIFIED // FOUO",                bg: "#007a33", fg: "#ffffff", desc: "For Official Use Only" },
      { name: "UNCLASSIFIED // CUI",     text: "UNCLASSIFIED // CUI",                bg: "#007a33", fg: "#ffffff", desc: "CUI Designation" },
      { name: "CUI",                     text: "CUI",                                bg: "#512888", fg: "#ffffff", desc: "Controlled Unclassified" },
      { name: "CUI // SP-SHI",           text: "CUI // SP-SHI",                      bg: "#512888", fg: "#ffffff", desc: "Sensitive Homeland Info" },
      { name: "CUI // SP-HC",            text: "CUI // SP-HC",                       bg: "#512888", fg: "#ffffff", desc: "Sensitive Health Care" },
      { name: "CUI // SP-PR",            text: "CUI // SP-PR",                       bg: "#512888", fg: "#ffffff", desc: "Sensitive Privacy" },
      { name: "CUI // FEDCON",           text: "CUI // FEDCON",                      bg: "#512888", fg: "#ffffff", desc: "Federal Contract" },
      { name: "CUI // NOFORN",           text: "CUI // NOFORN",                      bg: "#512888", fg: "#ffffff", desc: "No Foreign" },
      { name: "CONFIDENTIAL",            text: "CONFIDENTIAL",                       bg: "#003e7e", fg: "#ffffff", desc: "Confidential level" },
      { name: "CONFIDENTIAL // NOFORN",  text: "CONFIDENTIAL // NOFORN",             bg: "#003e7e", fg: "#ffffff", desc: "Conf No Foreign" },
      { name: "SECRET",                  text: "SECRET",                             bg: "#c00000", fg: "#ffffff", desc: "Secret level" },
      { name: "SECRET // NOFORN",        text: "SECRET // NOFORN",                   bg: "#c00000", fg: "#ffffff", desc: "Secret No Foreign" },
      { name: "SECRET // REL TO USA, FVEY", text: "SECRET // REL TO USA, FVEY",      bg: "#c00000", fg: "#ffffff", desc: "Rel FVEY" },
      { name: "TOP SECRET",              text: "TOP SECRET",                        bg: "#ff8c00", fg: "#000000", desc: "Top Secret level" },
      { name: "TOP SECRET // NOFORN",    text: "TOP SECRET // NOFORN",              bg: "#ff8c00", fg: "#000000", desc: "TS No Foreign" },
      { name: "TOP SECRET // SCI",       text: "TOP SECRET // SCI",                  bg: "#ff8c00", fg: "#000000", desc: "TS SCI" },
      { name: "TS // SCI // NOFORN",     text: "TS // SCI // NOFORN",                bg: "#ff8c00", fg: "#000000", desc: "TS SCI NF" },
      { name: "TS // SCI // REL TO USA, FVEY", text: "TS // SCI // REL TO USA, FVEY", bg: "#ff8c00", fg: "#000000", desc: "TS SCI FVEY" },
      { name: "SBU",                     text: "SENSITIVE BUT UNCLASSIFIED",         bg: "#003e7e", fg: "#ffffff", desc: "Sensitive but Unclass." },
      { name: "LES",                     text: "LAW ENFORCEMENT SENSITIVE",         bg: "#5c0a20", fg: "#ffffff", desc: "Law Enforcement" },
      { name: "LES // NOFORN",           text: "LES // NOFORN",                      bg: "#5c0a20", fg: "#ffffff", desc: "LES No Foreign" },
      { name: "DoD CPI",                 text: "DoD CRITICAL PROGRAM INFO",         bg: "#404040", fg: "#ffffff", desc: "Critical Prog Info" },
      { name: "ITAR",                    text: "ITAR CONTROLLED",                    bg: "#8b0000", fg: "#ffffff", desc: "Export controlled" },
      { name: "HIPAA",                   text: "HIPAA PROTECTED",                    bg: "#008080", fg: "#ffffff", desc: "Healthcare data" },
      { name: "A-C PRIV",                text: "ATTORNEY-CLIENT PRIVILEGED",         bg: "#5c4033", fg: "#ffffff", desc: "Legal privilege" },
      { name: "PA",                      text: "PUBLIC AFFAIRS USE ONLY",            bg: "#3b6db5", fg: "#ffffff", desc: "Public Affairs" },
      { name: "PROPRIETARY",             text: "CONTRACTOR PROPRIETARY",             bg: "#505050", fg: "#ffffff", desc: "Proprietary" }
    ];
    const appState = {
      textLeft: "%IP_ADDRESS%", textCenter: "%COMPUTERNAME%", textRight: "%USERNAME%",
      bgColor: "#007a33", fgColor: "#ffffff", fontName: "Segoe UI", fontSize: 10,
      fontBold: true, fontItalic: false, fontUnderline: false, heightPx: 24,
      textShadow: false, textShadowColor: "#404040", textShadowOffset: 2, 
      bannerShadow: false,
      borderEnabled: true, borderSize: 0,
      marginLeft: 25, marginRight: 25,
      // RAINBOW MODE REMOVED: rainbowMode: false,
      // IP_ADDRESS is now a built-in native variable — no PowerShell custom env var needed.
      customEnvVars: []
    };
    // Mock system env for preview simulation. IP_ADDRESS shows a generic placeholder
    // since the browser cannot query the actual machine's network interfaces.
    const mockSystemEnv = { "COMPUTERNAME": "WORKSTATION-01", "USERNAME": "AdminUser", "USERDOMAIN": "CORPNET", "IP_ADDRESS": "10.0.0.100" };
    // RAINBOW MODE REMOVED: let rainbowInterval = null;

    // RAINBOW MODE REMOVED — gear-click easter egg handler commented out:
    // let gearClicks = 0;
    // let gearTimer = null;
    // document.getElementById('brandIcon').addEventListener('click', () => {
    //     gearClicks++;
    //     if (gearTimer) clearTimeout(gearTimer);
    //     gearTimer = setTimeout(() => { gearClicks = 0; }, 3000); 
    // 
    //     if (gearClicks >= 5) {
    //         gearClicks = 0;
    //         const egg = document.getElementById('rainbowEggCard');
    //         const icon = document.getElementById('brandIcon');
    //         icon.classList.add('spin');
    //         setTimeout(() => icon.classList.remove('spin'), 500);
    //         
    //         if (egg.style.display === 'none' || egg.style.display === '') {
    //             egg.style.display = 'block';
    //             egg.scrollIntoView({ behavior: 'smooth', block: 'center' });
    //         }
    //     }
    // });

    function hexToSignedArgb(hex) {
      hex = hex.replace('#', '');
      const r = parseInt(hex.substring(0, 2), 16);
      const g = parseInt(hex.substring(2, 4), 16);
      const b = parseInt(hex.substring(4, 6), 16);
      const uint32 = ((255 << 24) | (r << 16) | (g << 8) | b) >>> 0;
      return (uint32 > 0x7FFFFFFF) ? uint32 - 0x100000000 : uint32;
    }
    function expandPreview(text) {
      if (!text) return "";
      let result = text;
      // Expand custom env vars generically — no hardcoded mock IP values.
      // Values starting with '$' (legacy PowerShell expressions) are shown as
      // a generic "<Dynamic Value>" placeholder rather than a fake IP address.
      appState.customEnvVars.forEach(item => {
        if (item.key.trim()) {
          const val = item.val.trim();
          const re = new RegExp(`%${item.key}%`, 'gi');
          let replacement = item.val;
          if (val.startsWith("$")) {
            replacement = "<Dynamic Value>";
          }
          result = result.replace(re, replacement);
        }
      });
      // Expand built-in system variables (including IP_ADDRESS which is now native)
      for (const [k, v] of Object.entries(mockSystemEnv)) {
        const re = new RegExp(`%${k}%`, 'gi');
        result = result.replace(re, v);
      }
      return result;
    }
    function updateAll() {
      appState.textLeft = document.getElementById('txtLeft').value;
      appState.textCenter = document.getElementById('txtCenter').value;
      appState.textRight = document.getElementById('txtRight').value;
      appState.fontName = document.getElementById('selFontFamily').value;
      appState.fontSize = parseFloat(document.getElementById('numFontSize').value) || 10;
      appState.fontBold = document.getElementById('chkFontBold').checked;
      appState.fontItalic = document.getElementById('chkFontItalic').checked;
      appState.fontUnderline = document.getElementById('chkFontUnderline').checked;
      appState.textShadow = document.getElementById('chkTextShadow').checked;
      appState.bannerShadow = document.getElementById('chkBannerShadow').checked;
      appState.borderEnabled = document.getElementById('chkBorderEnabled').checked;
      
      // RAINBOW MODE REMOVED:
      // const chkRainbow = document.getElementById('chkRainbowMode');
      // if (chkRainbow) appState.rainbowMode = chkRainbow.checked;

      const tsControls = document.getElementById('textShadowControls');
      if (appState.textShadow) { tsControls.style.opacity = '1'; tsControls.style.pointerEvents = 'auto'; }
      else { tsControls.style.opacity = '0.5'; tsControls.style.pointerEvents = 'none'; }

      const borderGroup = document.getElementById('borderSizeGroup');
      if (appState.borderEnabled) { borderGroup.style.opacity = '1'; borderGroup.style.pointerEvents = 'auto'; }
      else { borderGroup.style.opacity = '0.5'; borderGroup.style.pointerEvents = 'none'; }

      const banner = document.getElementById('liveBanner');
      banner.style.height = `${appState.heightPx}px`;
      banner.style.color = appState.fgColor;
      banner.style.fontFamily = `"${appState.fontName}", sans-serif`;
      banner.style.fontSize = `${appState.fontSize}pt`;
      banner.style.fontWeight = appState.fontBold ? '700' : '400';
      banner.style.fontStyle = appState.fontItalic ? 'italic' : 'normal';
      banner.style.textDecoration = appState.fontUnderline ? 'underline' : 'none';
      
      const slotL = document.getElementById('slotLeft');
      const slotR = document.getElementById('slotRight');
      slotL.style.marginLeft = `${appState.marginLeft}px`;
      slotR.style.marginRight = `${appState.marginRight}px`;

      if (appState.textShadow) {
          const off = `${appState.textShadowOffset}px`;
          banner.style.textShadow = `${off} ${off} 2px ${appState.textShadowColor}`;
      } else {
          banner.style.textShadow = 'none';
      }

      const sim = document.getElementById('screenSimulator');
      
      // RAINBOW MODE REMOVED:
      // if (appState.rainbowMode) {
      //     if (!rainbowInterval) {
      //         rainbowInterval = setInterval(() => {
      //             const hue = (Date.now() / 60) % 360; 
      //             const color = `hsl(${hue}, 100%, 50%)`;
      //             banner.style.backgroundColor = color;
      //             if (appState.borderEnabled) {
      //                 sim.style.borderLeftColor = color;
      //                 sim.style.borderRightColor = color;
      //                 sim.style.borderBottomColor = color;
      //             }
      //         }, 50);
      //     }
      // } else {
      //     if (rainbowInterval) {
      //         clearInterval(rainbowInterval);
      //         rainbowInterval = null;
      //     }
      //     banner.style.backgroundColor = appState.bgColor;
      // }
      banner.style.backgroundColor = appState.bgColor;

      if (appState.borderEnabled) {
          const s = `${appState.borderSize}px`;
          // RAINBOW MODE REMOVED: const c = appState.rainbowMode ? banner.style.backgroundColor : appState.bgColor;
          const c = appState.bgColor;
          sim.style.borderLeftWidth = s;
          sim.style.borderRightWidth = s;
          sim.style.borderBottomWidth = s;
          
          // RAINBOW MODE REMOVED: if (!appState.rainbowMode) {
          sim.style.borderLeftColor = c;
          sim.style.borderRightColor = c;
          sim.style.borderBottomColor = c;
          // }
      } else {
          sim.style.borderLeftWidth = '0';
          sim.style.borderRightWidth = '0';
          sim.style.borderBottomWidth = '0';
      }

      banner.style.boxShadow = appState.bannerShadow ? '0 4px 14px rgba(0,0,0,0.45)' : 'none';

      document.getElementById('slotLeft').textContent = expandPreview(appState.textLeft);
      document.getElementById('slotCenter').textContent = expandPreview(appState.textCenter);
      document.getElementById('slotRight').textContent = expandPreview(appState.textRight);
    }
    function syncHeight(val) { appState.heightPx = parseInt(val); document.getElementById('heightBadge').textContent = `${val} px`; updateAll(); }
    function syncMarginLeft(val) { appState.marginLeft = parseInt(val); document.getElementById('marginLeftBadge').textContent = `${val} px`; updateAll(); }
    function syncMarginRight(val) { appState.marginRight = parseInt(val); document.getElementById('marginRightBadge').textContent = `${val} px`; updateAll(); }
    function syncBorderSize(val) { appState.borderSize = parseInt(val); document.getElementById('borderSizeBadge').textContent = `${val} px`; updateAll(); }
    function syncTextShadowOffset(val) { appState.textShadowOffset = parseInt(val); document.getElementById('tsOffsetBadge').textContent = `${val} px`; updateAll(); }
    function syncColor(type, val) {
      if (type === 'bg') { appState.bgColor = val; document.getElementById('bgCircle').style.backgroundColor = val; document.getElementById('bgHexLabel').textContent = val.toUpperCase(); }
      else if (type === 'fg') { appState.fgColor = val; document.getElementById('fgCircle').style.backgroundColor = val; document.getElementById('fgHexLabel').textContent = val.toUpperCase(); }
      else if (type === 'tsc') { appState.textShadowColor = val; document.getElementById('tscCircle').style.backgroundColor = val; document.getElementById('tscHexLabel').textContent = val.toUpperCase(); }
      updateAll();
    }
    function applyPreset(p) {
      document.getElementById('txtCenter').value = p.text;
      document.getElementById('txtLeft').value = '';
      document.getElementById('txtRight').value = '';
      
      document.getElementById('pickerBg').value = p.bg;
      document.getElementById('pickerFg').value = p.fg;
      syncColor('bg', p.bg);
      syncColor('fg', p.fg);
      document.querySelectorAll('.preset-card').forEach(c => c.classList.remove('active'));
      const idx = PRESETS.indexOf(p);
      const cards = document.querySelectorAll('.preset-card');
      if (cards[idx]) cards[idx].classList.add('active');
      updateAll();
    }
    function createPresetCard(p) {
        const card = document.createElement('div');
        card.className = 'preset-card';
        card.onclick = () => applyPreset(p);
        card.innerHTML = `<div class="preset-preview" style="background-color: ${p.bg}; color: ${p.fg};">${p.name}</div><div class="preset-meta"><span>${p.desc}</span><span class="preset-meta-dot" style="background-color: ${p.bg};"></span></div>`;
        return card;
    }
    function renderPresetGrid() {
      const commonGrid = document.getElementById('presetGridCommon');
      const allGrid = document.getElementById('presetGridAll');
      commonGrid.innerHTML = '';
      allGrid.innerHTML = '';
      
      const commonNames = ["UNCLASSIFIED", "UNCLASSIFIED // FOUO", "CUI", "CONFIDENTIAL", "SECRET", "TOP SECRET"];
      const commonPresets = PRESETS.filter(p => commonNames.includes(p.name));
      const otherPresets = PRESETS.filter(p => !commonNames.includes(p.name));

      commonPresets.forEach(p => commonGrid.appendChild(createPresetCard(p)));
      otherPresets.forEach(p => allGrid.appendChild(createPresetCard(p)));
    }
    function togglePresets() {
      const wrapper = document.getElementById('presetExpandWrapper');
      const btn = document.getElementById('expandPresetsBtn');
      if (wrapper.style.display === 'none') {
        wrapper.style.display = 'block';
        btn.innerText = "Hide Advanced Levels";
      } else {
        wrapper.style.display = 'none';
        btn.innerText = "Show All Levels";
      }
    }
    function insertMacro(targetId, macro) {
      const input = document.getElementById(targetId);
      input.value += (input.value.length > 0 ? " " : "") + macro;
      updateAll();
      input.focus();
    }
    function renderEnvTable() {
      const list = document.getElementById('envList');
      list.innerHTML = '';
      appState.customEnvVars.forEach((item, index) => {
        const row = document.createElement('div');
        row.className = 'env-row';
        row.innerHTML = `<div class="env-input-group"><label>Variable Name</label><input type="text" value="${item.key.replace(/"/g, '&quot;')}" placeholder="VAR_NAME" oninput="updateEnvRow(${index}, 'key', this.value)"></div><div class="env-input-group"><label>Value (static text)</label><input type="text" value="${item.val.replace(/"/g, '&quot;')}" placeholder="Static text value" oninput="updateEnvRow(${index}, 'val', this.value)"></div><button class="btn-icon-danger" title="Delete" onclick="deleteEnvRow(${index})">&#x2715;</button>`;
        list.appendChild(row);
      });
    }
    function addEnvRow(key = '', val = '') { appState.customEnvVars.push({ key, val }); renderEnvTable(); updateAll(); const inputs = document.querySelectorAll('#envList .env-row:last-child input'); if (inputs.length > 0) inputs[0].focus(); }
    function updateEnvRow(index, field, value) { appState.customEnvVars[index][field] = value; updateAll(); }
    function deleteEnvRow(index) { appState.customEnvVars.splice(index, 1); renderEnvTable(); updateAll(); }
    function generateIniString() {
      let ini = `[Settings]\r\n`;
      ini += `TextLeft=${appState.textLeft}\r\n`;
      ini += `TextCenter=${appState.textCenter}\r\n`;
      ini += `TextRight=${appState.textRight}\r\n`;
      ini += `BgColor=${hexToSignedArgb(appState.bgColor)}\r\n`;
      ini += `FgColor=${hexToSignedArgb(appState.fgColor)}\r\n`;
      ini += `FontName=${appState.fontName}\r\n`;
      ini += `FontSize=${appState.fontSize}\r\n`;
      ini += `FontBold=${appState.fontBold ? "True" : "False"}\r\n`;
      ini += `FontItalic=${appState.fontItalic ? "True" : "False"}\r\n`;
      ini += `FontUnderline=${appState.fontUnderline ? "True" : "False"}\r\n`;
      ini += `Height=${appState.heightPx}\r\n`;
      ini += `TextShadow=${appState.textShadow ? "True" : "False"}\r\n`;
      ini += `TextShadowColor=${hexToSignedArgb(appState.textShadowColor)}\r\n`;
      ini += `TextShadowOffset=${appState.textShadowOffset}\r\n`;
      ini += `BannerShadow=${appState.bannerShadow ? "True" : "False"}\r\n`;
      ini += `BorderEnabled=${appState.borderEnabled ? "True" : "False"}\r\n`;
      ini += `BorderSize=${appState.borderSize}\r\n`;
      ini += `MarginLeft=${appState.marginLeft}\r\n`;
      ini += `MarginRight=${appState.marginRight}\r\n`;
      // RAINBOW MODE REMOVED:
      // if (appState.rainbowMode) {
      //     ini += `RainbowMode=True\r\n`;
      // }
      const validVars = appState.customEnvVars.filter(v => v.key.trim() !== "");
      if (validVars.length > 0) {
        ini += `\r\n[EnvVars]\r\n`;
        validVars.forEach(v => { const escaped = v.val.replace(/\r?\n/g, '\\n'); ini += `${v.key}=${escaped}\r\n`; });
      }
      return ini;
    }
    async function downloadIni() {
      const text = generateIniString();
      if (window.showSaveFilePicker) {
        try {
          const handle = await window.showSaveFilePicker({ suggestedName: 'NetMark.ini', types: [{ description: 'INI Configuration File', accept: { 'text/plain': ['.ini'] } }] });
          const writable = await handle.createWritable();
          await writable.write(text);
          await writable.close();
          showModal();
        } catch (err) { console.error("Save cancelled or failed:", err); }
      } else {
        const blob = new Blob([text], { type: 'text/plain;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url; a.download = 'NetMark.ini'; a.click();
        URL.revokeObjectURL(url);
        showModal();
      }
    }
    function showModal() {
        document.getElementById('customAlert').classList.add('active');
    }
    function closeModal() {
        document.getElementById('customAlert').classList.remove('active');
    }
    function resetToDefaults() {
      if (!confirm("Reset all settings back to defaults?")) return;
      document.getElementById('txtLeft').value = '%IP_ADDRESS%';
      document.getElementById('txtCenter').value = '%COMPUTERNAME%';
      document.getElementById('txtRight').value = '%USERNAME%';
      document.getElementById('sliderHeight').value = 24;
      document.getElementById('sliderMarginLeft').value = 25;
      document.getElementById('sliderMarginRight').value = 25;
      document.getElementById('selFontFamily').value = 'Segoe UI';
      document.getElementById('numFontSize').value = 10;
      document.getElementById('chkFontBold').checked = true;
      document.getElementById('chkFontItalic').checked = false;
      document.getElementById('chkFontUnderline').checked = false;
      document.getElementById('chkTextShadow').checked = false;
      document.getElementById('chkBannerShadow').checked = false;
      document.getElementById('chkBorderEnabled').checked = true;
      document.getElementById('sliderBorderSize').value = 0;
      document.getElementById('sliderTextShadowOffset').value = 2;
      document.getElementById('pickerTextShadow').value = '#404040';
      
      // RAINBOW MODE REMOVED:
      // const chkRainbow = document.getElementById('chkRainbowMode');
      // if (chkRainbow) chkRainbow.checked = false;

      syncColor('bg', '#007a33');
      syncColor('fg', '#ffffff');
      syncColor('tsc', '#404040');
      syncHeight(24);
      syncMarginLeft(25);
      syncMarginRight(25);
      syncBorderSize(0);
      syncTextShadowOffset(2);
      // IP_ADDRESS is now built-in — no PowerShell custom env var needed.
      appState.customEnvVars = [];
      document.querySelectorAll('.preset-card').forEach(c => c.classList.remove('active'));
      renderEnvTable();
      updateAll();
    }
    ['txtLeft', 'txtCenter', 'txtRight'].forEach(id => { document.getElementById(id).addEventListener('input', updateAll); });
    
    window.addEventListener('scroll', () => {
        const brand = document.getElementById('brandGroup');
        if (window.scrollY > 30) {
            brand.classList.add('hidden');
        } else {
            brand.classList.remove('hidden');
        }
    });

    renderPresetGrid();
    renderEnvTable();
    updateAll();
  </script>
</body>
</html>
'@
Set-Content -LiteralPath $htmlPath -Value $htmlContent -Encoding UTF8
Dbg-File $htmlPath

# ---- NetMark\NetMark.default.ini --------------------------------------
 $defaultIniPath = Join-Path $bannerDir 'NetMark.default.ini'
 $defaultIniContent = @'
[Settings]
TextLeft=%IP_ADDRESS%
TextCenter=%COMPUTERNAME%
TextRight=%USERNAME%
BgColor=-16745933
FgColor=-1
FontName=Segoe ui
FontSize=10
FontBold=True
FontItalic=False
FontUnderline=False
Height=24
TextShadow=False
TextShadowColor=-12566464
TextShadowOffset=2
BannerShadow=False
BorderEnabled=True
BorderSize=0
MarginLeft=25
MarginRight=25

; IP_ADDRESS is now a built-in variable resolved natively by C# via
; System.Net.NetworkInformation — no PowerShell subprocess required.
; The [EnvVars] section is intentionally omitted. Add your own custom
; static-text variables here if needed (e.g. MY_VAR=Some Value, then
; use %MY_VAR% in your banner text above).
'@
Set-Content -LiteralPath $defaultIniPath -Value $defaultIniContent -Encoding UTF8
Dbg-File $defaultIniPath

# ---------------------------------------------------------------------------
# Phase 4: Publish (single-file portable EXE)
# ---------------------------------------------------------------------------
Dbg-Step "Phase 4: Publish Single-File Portable EXE"
 $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) {
    Dbg-Err "dotnet SDK not found on PATH. Install .NET 8 SDK and re-run."
    throw "dotnet SDK required."
}

 $bannerCsproj = Join-Path $bannerDir 'NetMark.csproj'

 $origEAP = $ErrorActionPreference
 $ErrorActionPreference = 'Continue'

Dbg-Info "Running: dotnet publish -c $Configuration -r win-x64 -o `"$publishDir`""
Dbg-Info "(This produces a self-contained single-file EXE — may take 30-60s and output ~70 MB)"
 $publishOutput = & dotnet publish $bannerCsproj -c $Configuration -r win-x64 -o $publishDir --nologo 2>&1
 $publishOutput | ForEach-Object {
    $line = $_ -as [string]
    if ($line -match 'error') { Dbg-Err $line }
    elseif ($line -match 'warning') { Dbg-Warn $line }
    else { Dbg-Info $line }
}
 $publishExitCode = $LASTEXITCODE
 $ErrorActionPreference = $origEAP

if ($publishExitCode -ne 0) { throw "publish failed for NetMark" }

Get-ChildItem -Path $publishDir -Filter "*.pdb" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $publishDir -Filter "*.xml" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

Dbg-Ok "Publish succeeded."

 $exePath = Join-Path $publishDir 'NetMark.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "exe missing at $exePath" }

 $exeSizeMB = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
Dbg-Ok "Portable single-file EXE: $exePath ($exeSizeMB MB)"

# ---------------------------------------------------------------------------
# Phase 5: Run (Detached)
# ---------------------------------------------------------------------------
Dbg-Step "Phase 5: Run"

Dbg-Info "Killing any existing NetMark processes..."
Get-Process -Name "NetMark" -ErrorAction SilentlyContinue | Stop-Process -Force

Remove-Item -Path (Join-Path $publishDir 'NetMark.ini')          -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $publishDir 'Configurator.html')      -ErrorAction SilentlyContinue
Remove-Item -Path "C:\NetMark-startup.log"                       -ErrorAction SilentlyContinue

Dbg-Info "Launching NetMark (single-file portable exe)..."
Start-Process -FilePath $exePath

Start-Sleep -Seconds 3
 $running = Get-Process -Name "NetMark" -ErrorAction SilentlyContinue
if (-not $running) {
    Dbg-Warn "NetMark process is not running."
    Dbg-Warn "Note: v35 uses [Conditional('DEBUG')] logging — C:\NetMark-startup.log"
    Dbg-Warn "will NOT exist in Release builds. Check the on-screen MessageBox for errors."
    $logFile = "C:\NetMark-startup.log"
    if (Test-Path $logFile) {
        Write-Host "`n--- Crash Log ---" -ForegroundColor Red
        Get-Content $logFile -Tail 30
        Write-Host "-----------------`n" -ForegroundColor Red
    }
} else {
    Dbg-Ok "NetMark has been started successfully."
}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " NetMark (v35) is running in background."                             -ForegroundColor White
Write-Host " The HTML Configurator should now be open in your browser."           -ForegroundColor White
Write-Host ""
Write-Host " Save the NetMark.ini to this folder:"                               -ForegroundColor White
Write-Host "   $publishDir"                                                        -ForegroundColor Yellow
Write-Host " The banner updates instantly when you click Save."                   -ForegroundColor White
Write-Host ""
Write-Host " The portable EXE is at:"                                              -ForegroundColor White
Write-Host "   $exePath"                                                           -ForegroundColor Green
Write-Host " Size: $exeSizeMB MB (self-contained, no .NET runtime needed)"        -ForegroundColor DarkGray
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
Dbg-Ok "Done."
