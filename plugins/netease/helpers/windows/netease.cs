using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace TernNetease
{
    public static class Win
    {
        private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr lParam);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int cmd);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);

        // The CloudMusic shell window. Its title carries "<song> - <artist>".
        private const string MainClass = "OrpheusBrowserHost";

        public static bool Running()
        {
            return Process.GetProcessesByName("cloudmusic").Length > 0;
        }

        public static IntPtr FindMain()
        {
            var pids = new HashSet<uint>();
            foreach (var process in Process.GetProcessesByName("cloudmusic")) pids.Add((uint)process.Id);
            if (pids.Count == 0) return IntPtr.Zero;
            IntPtr found = IntPtr.Zero;
            EnumWindows((hWnd, lParam) =>
            {
                uint pid;
                GetWindowThreadProcessId(hWnd, out pid);
                if (!pids.Contains(pid)) return true;
                var name = new StringBuilder(128);
                GetClassName(hWnd, name, name.Capacity);
                if (name.ToString() != MainClass) return true;
                found = hWnd;
                return false;
            }, IntPtr.Zero);
            return found;
        }

        public static bool Alive(IntPtr hWnd)
        {
            return hWnd != IntPtr.Zero && IsWindow(hWnd);
        }

        public static string Title(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return "";
            var text = new StringBuilder(512);
            GetWindowText(hWnd, text, text.Capacity);
            return text.ToString();
        }

        // CloudMusic's global hotkeys are the only way to drive playback from outside.
        public static void Hotkey(params byte[] keys)
        {
            for (int i = 0; i < keys.Length; i++) keybd_event(keys[i], 0, 0, IntPtr.Zero);
            System.Threading.Thread.Sleep(60);
            for (int i = keys.Length - 1; i >= 0; i--) keybd_event(keys[i], 0, 2, IntPtr.Zero);
        }

        public static void Show(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return;
            ShowWindow(hWnd, 9); // SW_RESTORE
            SetForegroundWindow(hWnd);
        }
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
    }

    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int Item(int index, out IMMDevice device);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }

    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionManager2
    {
        [PreserveSig] int GetAudioSessionControl(IntPtr groupingParam, int flags, out IntPtr control);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr groupingParam, int flags, out IntPtr volume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
    }

    [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionEnumerator
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetSession(int index, out IAudioSessionControl2 session);
    }

    [Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionControl2
    {
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName(out IntPtr name);
        [PreserveSig] int SetDisplayName(IntPtr name, ref Guid context);
        [PreserveSig] int GetIconPath(out IntPtr path);
        [PreserveSig] int SetIconPath(IntPtr path, ref Guid context);
        [PreserveSig] int GetGroupingParam(out Guid param);
        [PreserveSig] int SetGroupingParam(ref Guid param, ref Guid context);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int GetSessionIdentifier(out IntPtr id);
        [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
        [PreserveSig] int GetProcessId(out uint pid);
    }

    [Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface ISimpleAudioVolume
    {
        [PreserveSig] int SetMasterVolume(float level, ref Guid context);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute(bool mute, ref Guid context);
        [PreserveSig] int GetMute(out bool mute);
    }

    [Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioMeterInformation
    {
        [PreserveSig] int GetPeakValue(out float peak);
    }

    // The app's own volume: CloudMusic keeps no readable volume, its mixer sessions do.
    public static class AppVolume
    {
        private const int RenderFlow = 0;
        private const int DeviceStateActive = 1;
        private const int ClsCtxAll = 23;

        private static List<IAudioSessionControl2> Sessions()
        {
            var found = new List<IAudioSessionControl2>();
            var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
            IMMDeviceCollection devices;
            if (enumerator.EnumAudioEndpoints(RenderFlow, DeviceStateActive, out devices) != 0) return found;
            int deviceCount;
            devices.GetCount(out deviceCount);
            var managerId = typeof(IAudioSessionManager2).GUID;
            for (int d = 0; d < deviceCount; d++)
            {
                IMMDevice device;
                if (devices.Item(d, out device) != 0) continue;
                object managerObject;
                if (device.Activate(ref managerId, ClsCtxAll, IntPtr.Zero, out managerObject) != 0) continue;
                IAudioSessionEnumerator sessions;
                if (((IAudioSessionManager2)managerObject).GetSessionEnumerator(out sessions) != 0) continue;
                int sessionCount;
                sessions.GetCount(out sessionCount);
                for (int s = 0; s < sessionCount; s++)
                {
                    IAudioSessionControl2 control;
                    if (sessions.GetSession(s, out control) != 0) continue;
                    uint pid;
                    if (control.GetProcessId(out pid) != 0 || pid == 0) continue;
                    string name;
                    try { name = Process.GetProcessById((int)pid).ProcessName; } catch { continue; }
                    if (string.Equals(name, "cloudmusic", StringComparison.OrdinalIgnoreCase)) found.Add(control);
                }
            }
            return found;
        }

        // The loudest of the app's streams. The meter reads 0 while the client is paused, even
        // though it keeps its mixer session alive, so this is the real play/pause signal.
        public static float Peak()
        {
            float peak = 0f;
            foreach (var control in Sessions())
            {
                var meter = control as IAudioMeterInformation;
                if (meter == null) continue;
                float value;
                if (meter.GetPeakValue(out value) == 0 && value > peak) peak = value;
            }
            return peak;
        }

        // 1 while any of the app's streams is active, 2 when they only exist silent, 0 when there are none.
        public static int State()
        {
            int state = 0;
            foreach (var control in Sessions())
            {
                int value;
                if (control.GetState(out value) != 0) continue;
                if (value == 1) return 1;
                if (value == 2) state = 2;
            }
            return state;
        }

        public static float[] Get()
        {
            foreach (var control in Sessions())
            {
                var volume = (ISimpleAudioVolume)control;
                float level;
                bool muted;
                if (volume.GetMasterVolume(out level) == 0 && volume.GetMute(out muted) == 0)
                {
                    return new float[] { level, muted ? 1f : 0f };
                }
            }
            return null;
        }

        public static int Set(float level, int mute)
        {
            var context = Guid.Empty;
            int changed = 0;
            foreach (var control in Sessions())
            {
                var volume = (ISimpleAudioVolume)control;
                bool ok = true;
                if (level >= 0) ok &= volume.SetMasterVolume(Math.Min(1f, Math.Max(0f, level)), ref context) == 0;
                if (mute >= 0) ok &= volume.SetMute(mute == 1, ref context) == 0;
                if (ok) changed++;
            }
            return changed;
        }
    }
}
