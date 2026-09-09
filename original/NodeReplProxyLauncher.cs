// Environment-only wrapper. MCP stdio is inherited without parsing or rewriting.
// The original node_repl.exe remains responsible for all sandboxing and tool behavior.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

internal static class NodeReplProxyLauncher {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo {
        public int cb; public string reserved, desktop, title;
        public int x, y, width, height, xChars, yChars, fill, flags;
        public short show, reservedSize; public IntPtr reservedPtr, stdin, stdout, stderr;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInfo { public IntPtr process, thread; public int pid, tid; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CreateProcess(string app, StringBuilder command, IntPtr pa, IntPtr ta,
        bool inherit, uint flags, IntPtr env, string cwd, ref StartupInfo si, out ProcessInfo pi);
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int info, IntPtr data, uint length);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle, uint timeout);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

    static string Quote(string value) {
        StringBuilder b = new StringBuilder("\""); int slashes = 0;
        foreach (char ch in value) {
            if (ch == '\\') { slashes++; continue; }
            if (ch == '"') { b.Append('\\', slashes * 2 + 1); b.Append(ch); }
            else { b.Append('\\', slashes); b.Append(ch); }
            slashes = 0;
        }
        b.Append('\\', slashes * 2); return b.Append('"').ToString();
    }
    static int Main(string[] args) {
        IntPtr job = IntPtr.Zero; ProcessInfo child = new ProcessInfo();
        try {
            if (!Environment.Is64BitProcess) throw new InvalidOperationException("64-bit Windows is required.");
            string node = Environment.GetEnvironmentVariable("NODE_REPL_NODE_PATH");
            if (String.IsNullOrEmpty(node)) throw new InvalidOperationException("NODE_REPL_NODE_PATH is missing.");
            string real = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(node), "node_repl.exe"));
            string expected = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenAI", "Codex", "runtimes", "cua_node") + Path.DirectorySeparatorChar;
            if (!real.StartsWith(expected, StringComparison.OrdinalIgnoreCase) || !File.Exists(real))
                throw new InvalidOperationException("Original bundled node_repl.exe was not found in the expected runtime.");
            Environment.SetEnvironmentVariable("HTTP_PROXY", "http://127.0.0.1:56666");
            Environment.SetEnvironmentVariable("HTTPS_PROXY", "http://127.0.0.1:56666");
            StartupInfo si = new StartupInfo(); si.cb = Marshal.SizeOf(si); si.flags = 0x100;
            si.stdin = GetStdHandle(-10); si.stdout = GetStdHandle(-11); si.stderr = GetStdHandle(-12);
            foreach (IntPtr handle in new IntPtr[] { si.stdin, si.stdout, si.stderr })
                if (handle != IntPtr.Zero && handle != new IntPtr(-1) && !SetHandleInformation(handle, 1, 1)) throw new Win32Exception();
            // Kill only this wrapper's child tree when the MCP client closes the wrapper.
            job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new Win32Exception();
            IntPtr limits = Marshal.AllocHGlobal(144);
            try {
                Marshal.Copy(new byte[144], 0, limits, 144); Marshal.WriteInt32(limits, 16, 0x2000);
                if (!SetInformationJobObject(job, 9, limits, 144)) throw new Win32Exception();
            } finally { Marshal.FreeHGlobal(limits); }
            StringBuilder command = new StringBuilder(Quote(real));
            foreach (string arg in args) command.Append(' ').Append(Quote(arg));
            if (!CreateProcess(real, command, IntPtr.Zero, IntPtr.Zero, true, 0x08000004, IntPtr.Zero,
                Environment.CurrentDirectory, ref si, out child)) throw new Win32Exception();
            if (!AssignProcessToJobObject(job, child.process)) { TerminateProcess(child.process, 1); throw new Win32Exception(); }
            if (ResumeThread(child.thread) == UInt32.MaxValue) throw new Win32Exception();
            string log = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "proxy-runtime-" + Process.GetCurrentProcess().Id + ".txt");
            File.WriteAllText(log, "utc=" + DateTime.UtcNow.ToString("o") + "\nchildPid=" + child.pid +
                "\nrealExecutable=" + real + "\nproxy=http://127.0.0.1:56666\n");
            WaitForSingleObject(child.process, UInt32.MaxValue);
            uint exitCode; if (!GetExitCodeProcess(child.process, out exitCode)) throw new Win32Exception();
            return unchecked((int)exitCode);
        } catch (Exception e) { Console.Error.WriteLine("Codex proxy launcher: " + e.Message); return 1; }
        finally {
            if (job != IntPtr.Zero) CloseHandle(job);
            if (child.thread != IntPtr.Zero) CloseHandle(child.thread);
            if (child.process != IntPtr.Zero) CloseHandle(child.process);
        }
    }
}
