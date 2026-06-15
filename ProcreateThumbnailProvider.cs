/*
 * ProcreateThumbnailProvider.cs
 * ================================
 * Windows Shell Thumbnail Provider for .procreate files.
 * 
 * .procreate files are ZIP archives containing QuickLook/Thumbnail.png.
 * This COM DLL extracts that PNG and provides it to Windows Explorer
 * so that thumbnails appear in folder views.
 *
 * Compile with:
 *   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
 *     /target:library /out:ProcreateThumbnailProvider.dll
 *     /reference:System.Drawing.dll
 *     /reference:System.IO.Compression.dll
 *     ProcreateThumbnailProvider.cs
 *
 * Register with (Admin):
 *   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe
 *     /codebase ProcreateThumbnailProvider.dll
 */

using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace ProcreateThumbnailProvider
{
    #region COM Interfaces

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("0000000C-0000-0000-C000-000000000046")]
    public interface IStream
    {
        void Read([Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] byte[] pv, int cb, IntPtr pcbRead);
        void Write([In, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] byte[] pv, int cb, IntPtr pcbWritten);
        void Seek(long dlibMove, int dwOrigin, IntPtr plibNewPosition);
        void SetSize(long libNewSize);
        void CopyTo(IStream pstm, long cb, IntPtr pcbRead, IntPtr pcbWritten);
        void Commit(int grfCommitFlags);
        void Revert();
        void LockRegion(long libOffset, long cb, int dwLockType);
        void UnlockRegion(long libOffset, long cb, int dwLockType);
        void Stat(out System.Runtime.InteropServices.ComTypes.STATSTG pstatstg, int grfStatFlag);
        void Clone(out IStream ppstm);
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("e357fccd-a995-4576-b01f-234630154e96")]
    public interface IThumbnailProvider
    {
        void GetThumbnail(uint cx, out IntPtr phbmp, out uint pdwAlpha);
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("b824b49d-22ac-4161-ac8a-9916e8fa3f7f")]
    public interface IInitializeWithStream
    {
        void Initialize(IStream pstream, uint grfMode);
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("b7d14566-0509-4cce-a71f-0a554233bd9b")]
    public interface IInitializeWithFile
    {
        void Initialize([MarshalAs(UnmanagedType.LPWStr)] string pszFilePath, uint grfMode);
    }

    #endregion

    #region Thumbnail Provider

    [ComVisible(true)]
    [Guid("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")]
    [ClassInterface(ClassInterfaceType.None)]
    public class ProcreateThumbnailProvider : IThumbnailProvider, IInitializeWithStream, IInitializeWithFile
    {
        /// <summary>
        /// Wraps COM IStream as System.IO.Stream for ZipArchive streaming.
        /// ZipArchive only uses Read/Seek/Length/Position — no full file load.
        /// </summary>
        private class IStreamWrapper : Stream
        {
        private IStream _istream;
        private long _length;
        private long _position;

        public IStreamWrapper(IStream stream)
        {
            _istream = stream;
            System.Runtime.InteropServices.ComTypes.STATSTG stat;
            stream.Stat(out stat, 1);
            _length = stat.cbSize;
        }

        public override bool CanRead { get { return true; } }
        public override bool CanSeek { get { return true; } }
        public override bool CanWrite { get { return false; } }
        public override long Length { get { return _length; } }
        public override long Position
        {
            get { return _position; }
            set { Seek(value, SeekOrigin.Begin); }
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            if (offset != 0)
            {
                // ZipArchive always reads with offset=0, but handle just in case
                byte[] tmp = new byte[count];
                IntPtr readPtr = Marshal.AllocCoTaskMem(sizeof(int));
                try { _istream.Read(tmp, count, readPtr); }
                finally { Marshal.FreeCoTaskMem(readPtr); }
                Array.Copy(tmp, 0, buffer, offset, count);
                int read = Marshal.ReadInt32(readPtr);
                _position += read;
                return read;
            }
            IntPtr bytesReadPtr = Marshal.AllocCoTaskMem(sizeof(int));
            try
            {
                _istream.Read(buffer, count, bytesReadPtr);
                int read = Marshal.ReadInt32(bytesReadPtr);
                _position += read;
                return read;
            }
            finally { Marshal.FreeCoTaskMem(bytesReadPtr); }
        }

        public override long Seek(long offset, SeekOrigin origin)
        {
            int dwOrigin = origin == SeekOrigin.Begin ? 0 :
                           origin == SeekOrigin.Current ? 1 : 2;
            IntPtr newPosPtr = Marshal.AllocCoTaskMem(8);
            try
            {
                _istream.Seek(offset, dwOrigin, newPosPtr);
                _position = Marshal.ReadInt64(newPosPtr);
                return _position;
            }
            finally { Marshal.FreeCoTaskMem(newPosPtr); }
        }

        public override void Flush() { }
        public override void SetLength(long value) { throw new NotSupportedException(); }
        public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }

        protected override void Dispose(bool disposing)
        {
            if (disposing) { _istream = null; }
            base.Dispose(disposing);
        }
    }

        private IStream _stream;
        private string _filePath;

        public void Initialize(IStream pstream, uint grfMode) { _stream = pstream; }
        public void Initialize(string pszFilePath, uint grfMode) { _filePath = pszFilePath; }

        public void GetThumbnail(uint cx, out IntPtr phbmp, out uint pdwAlpha)
        {
            phbmp = IntPtr.Zero;
            pdwAlpha = 0;

            try
            {
                byte[] pngData = null;

                // Explorer calls IInitializeWithStream, so try stream first
                if (_stream != null)
                {
                    using (var wrapper = new IStreamWrapper(_stream))
                    using (var archive = new ZipArchive(wrapper, ZipArchiveMode.Read))
                    {
                        foreach (var entry in archive.Entries)
                        {
                            if (IsThumbnailEntry(entry))
                            {
                                using (var es = entry.Open())
                                using (var rs = new MemoryStream())
                                { es.CopyTo(rs); pngData = rs.ToArray(); }
                                break;
                            }
                        }
                    }
                }

                // Fallback: file path
                if (pngData == null && !string.IsNullOrEmpty(_filePath) && File.Exists(_filePath))
                    pngData = ExtractThumbnailFromFile(_filePath);

                if (pngData == null || pngData.Length == 0) return;

                using (MemoryStream ms = new MemoryStream(pngData))
                using (Bitmap original = new Bitmap(ms))
                {
                    int targetSize = (int)cx;
                    if (targetSize < 1) targetSize = 256;

                    float scale = Math.Min((float)targetSize / original.Width,
                                           (float)targetSize / original.Height);
                    int newW = Math.Max(1, (int)(original.Width * scale));
                    int newH = Math.Max(1, (int)(original.Height * scale));

                    using (Bitmap thumb = new Bitmap(newW, newH, PixelFormat.Format32bppArgb))
                    {
                        using (Graphics g = Graphics.FromImage(thumb))
                        {
                            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                            g.SmoothingMode = SmoothingMode.HighQuality;
                            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                            g.CompositingQuality = CompositingQuality.HighQuality;
                            g.DrawImage(original, 0, 0, newW, newH);
                        }
                        phbmp = thumb.GetHbitmap(Color.Transparent);
                        pdwAlpha = 2; // WTSAT_ARGB
                    }
                }
            }
            catch { }
        }

        // ── Extract from file path (FileStream, no full read) ────
        private static byte[] ExtractThumbnailFromFile(string filePath)
        {
            try
            {
                // Stream directly from disk - ZipArchive only reads
                // the central directory + the target entry, not the whole file
                using (var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var archive = new ZipArchive(fs, ZipArchiveMode.Read))
                {
                    foreach (var entry in archive.Entries)
                    {
                        if (IsThumbnailEntry(entry))
                        {
                            using (var es = entry.Open())
                            using (var rs = new MemoryStream())
                            { es.CopyTo(rs); return rs.ToArray(); }
                        }
                    }
                }
            }
            catch { return null; }
            return null;
        }

        // ── Match QuickLook/Thumbnail.png (case-insensitive) ────────
        private static bool IsThumbnailEntry(ZipArchiveEntry entry)
        {
            string name = entry.FullName;
            return (name.Equals("QuickLook/Thumbnail.png", StringComparison.OrdinalIgnoreCase) ||
                    name.Equals("QuickLook/thumbnail.png", StringComparison.OrdinalIgnoreCase) ||
                    name.Equals("Thumbnail.png", StringComparison.OrdinalIgnoreCase) ||
                    (name.StartsWith("QuickLook/", StringComparison.OrdinalIgnoreCase) &&
                     name.EndsWith(".png", StringComparison.OrdinalIgnoreCase)));
        }

        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr hObject);

        // ── COM Self-Registration ───────────────────────────────
        private const string CLSID_REG = "{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}";
        private const string EXT_REG = ".procreate";
        private const string HANDLER_NAME = "Procreate Thumbnail Provider";
        private const string THUMB_GUID = "{e357fccd-a995-4576-b01f-234630154e96}";

        [ComRegisterFunction]
        private static void Register(Type type)
        {
            try
            {
                string codeBase = "file:///" + type.Assembly.CodeBase
                    .Replace('\\', '/').Replace("file:///", "file:///");

                using (var k = Registry.ClassesRoot.CreateSubKey(
                    @"CLSID\" + CLSID_REG + @"\InprocServer32"))
                {
                    k.SetValue(null, "mscoree.dll");
                    k.SetValue("Assembly", "ProcreateThumbnailProvider, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null");
                    k.SetValue("Class", "ProcreateThumbnailProvider.ProcreateThumbnailProvider");
                    k.SetValue("CodeBase", codeBase);
                    k.SetValue("RuntimeVersion", "v4.0.30319");
                    k.SetValue("ThreadingModel", "Both");
                }

                using (var k = Registry.LocalMachine.CreateSubKey(
                    @"Software\Classes\CLSID\" + CLSID_REG + @"\InprocServer32"))
                {
                    k.SetValue(null, "mscoree.dll");
                    k.SetValue("Class", "ProcreateThumbnailProvider.ProcreateThumbnailProvider");
                    k.SetValue("CodeBase", codeBase);
                    k.SetValue("RuntimeVersion", "v4.0.30319");
                    k.SetValue("ThreadingModel", "Both");
                }

                using (var k = Registry.ClassesRoot.CreateSubKey(@"CLSID\" + CLSID_REG))
                {
                    k.SetValue(null, HANDLER_NAME);
                    k.SetValue("DisableProcessIsolation", 1, RegistryValueKind.DWord);
                }

                Registry.ClassesRoot.CreateSubKey(
                    @"CLSID\" + CLSID_REG + @"\Implemented Categories\{62C8FE65-4EBB-45e7-B440-6E39B2CDBF29}");

                using (var k = Registry.ClassesRoot.CreateSubKey(
                    EXT_REG + @"\ShellEx\" + THUMB_GUID))
                { if (k != null) k.SetValue(null, CLSID_REG); }

                using (var k = Registry.LocalMachine.CreateSubKey(
                    @"Software\Classes\" + EXT_REG + @"\ShellEx\" + THUMB_GUID))
                { if (k != null) k.SetValue(null, CLSID_REG); }

                using (var k = Registry.ClassesRoot.CreateSubKey(EXT_REG))
                {
                    k.SetValue("Content Type", "application/x-procreate");
                    k.SetValue("PerceivedType", "image");
                }

                using (var k = Registry.LocalMachine.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved", true))
                { if (k != null) k.SetValue(CLSID_REG, HANDLER_NAME); }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.WriteLine("Register error: " + ex.Message);
            }
        }

        [ComUnregisterFunction]
        private static void Unregister(Type type)
        {
            try
            {
                string sk = EXT_REG + @"\ShellEx\" + THUMB_GUID;
                try { Registry.ClassesRoot.DeleteSubKeyTree(sk, false); } catch { }
                try { Registry.LocalMachine.DeleteSubKeyTree(@"Software\Classes\" + sk, false); } catch { }
                try { Registry.ClassesRoot.DeleteSubKeyTree(@"CLSID\" + CLSID_REG, false); } catch { }
                try { Registry.LocalMachine.DeleteSubKeyTree(@"Software\Classes\CLSID\" + CLSID_REG, false); } catch { }

                using (var k = Registry.LocalMachine.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved", true))
                { try { if (k != null) k.DeleteValue(CLSID_REG, false); } catch { } }
            }
            catch { }
        }
    }

    #endregion
}
