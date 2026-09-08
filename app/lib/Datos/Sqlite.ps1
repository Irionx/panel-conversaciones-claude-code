# =============================================================================
#  Sqlite.ps1 - acceso a SQLite sin instalar NADA
# -----------------------------------------------------------------------------
#  Windows 10/11 trae winsqlite3.dll en System32 (la usan componentes del propio
#  sistema). Se le entra por P/Invoke directo, asi que el proyecto no arrastra
#  System.Data.SQLite ni binarios nativos en el repo. Medido en esta maquina:
#  version 3.51.1.
#
#  LA TRAMPA: la API de SQLite habla UTF-8, no UTF-16 ni ANSI. Marshalear con
#  CharSet.Ansi pasaria los strings por cp1252 y "diseño" volveria roto. Por eso
#  todos los strings van y vienen como byte[] convertidos a mano.
#
#  Este archivo lo carga Datos.psm1 y no se usa desde ningun otro lado.
# =============================================================================

if (-not ('SqliteNativo' -as [type])) {
    Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class SqliteNativo {
    const string DLL = "winsqlite3.dll";
    const int OK = 0, ROW = 100, DONE = 101;
    const int OPEN_READWRITE = 0x2, OPEN_CREATE = 0x4;
    // Tipos de columna que devuelve sqlite3_column_type
    const int T_INTEGER = 1, T_NULL = 5;
    static readonly IntPtr TRANSIENT = new IntPtr(-1);

    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_close_v2(IntPtr db);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, IntPtr tail);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_step(IntPtr stmt);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_bind_text(IntPtr stmt, int i, byte[] val, int n, IntPtr destructor);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_bind_int64(IntPtr stmt, int i, long val);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_bind_null(IntPtr stmt, int i);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr sqlite3_column_text(IntPtr stmt, int i);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern long sqlite3_column_int64(IntPtr stmt, int i);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_column_bytes(IntPtr stmt, int i);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_column_type(IntPtr stmt, int i);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_column_count(IntPtr stmt);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr sqlite3_errmsg(IntPtr db);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr sqlite3_libversion();
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_busy_timeout(IntPtr db, int ms);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_changes(IntPtr db);

    static byte[] U8z(string s) {
        byte[] b = Encoding.UTF8.GetBytes(s ?? "");
        byte[] z = new byte[b.Length + 1];
        Buffer.BlockCopy(b, 0, z, 0, b.Length);
        return z;                       // terminado en 0, como espera la API
    }
    static string Cstr(IntPtr p) {
        if (p == IntPtr.Zero) return null;
        int n = 0; while (Marshal.ReadByte(p, n) != 0) n++;
        byte[] b = new byte[n];
        Marshal.Copy(p, b, 0, n);
        return Encoding.UTF8.GetString(b);
    }

    public static string Version() { return Cstr(sqlite3_libversion()); }

    public static IntPtr Abrir(string ruta) {
        IntPtr db;
        int rc = sqlite3_open_v2(U8z(ruta), out db, OPEN_READWRITE | OPEN_CREATE, IntPtr.Zero);
        if (rc != OK) throw new Exception("No pude abrir la base (rc=" + rc + "): " + ruta);
        // Si otro proceso esta escribiendo, esperar en vez de fallar al toque.
        sqlite3_busy_timeout(db, 5000);
        return db;
    }
    public static void Cerrar(IntPtr db) { if (db != IntPtr.Zero) sqlite3_close_v2(db); }
    public static int Cambios(IntPtr db) { return sqlite3_changes(db); }

    static void Ligar(IntPtr db, IntPtr st, object[] pars) {
        if (pars == null) return;
        for (int i = 0; i < pars.Length; i++) {
            object v = pars[i];
            int rc;
            if (v == null) {
                rc = sqlite3_bind_null(st, i + 1);
            } else if (v is int || v is long || v is short) {
                rc = sqlite3_bind_int64(st, i + 1, Convert.ToInt64(v));
            } else {
                byte[] b = Encoding.UTF8.GetBytes(Convert.ToString(v));
                rc = sqlite3_bind_text(st, i + 1, b, b.Length, TRANSIENT);
            }
            if (rc != OK) throw new Exception("bind " + (i + 1) + ": " + Cstr(sqlite3_errmsg(db)));
        }
    }

    /// Una sentencia sin resultados (INSERT/UPDATE/DELETE/CREATE/PRAGMA).
    public static void Ejecutar(IntPtr db, string sql, object[] pars) {
        IntPtr st;
        if (sqlite3_prepare_v2(db, U8z(sql), -1, out st, IntPtr.Zero) != OK)
            throw new Exception(Cstr(sqlite3_errmsg(db)) + "  [SQL: " + sql + "]");
        try {
            Ligar(db, st, pars);
            int rc = sqlite3_step(st);
            if (rc != DONE && rc != ROW)
                throw new Exception(Cstr(sqlite3_errmsg(db)) + "  [SQL: " + sql + "]");
        } finally { sqlite3_finalize(st); }
    }

    /// Filas como object[]: string para texto, long para enteros, null para NULL.
    /// Distinguir null de cadena vacia importa: un campo opcional ausente no es
    /// lo mismo que un campo puesto en "".
    public static object[][] Consultar(IntPtr db, string sql, object[] pars) {
        IntPtr st;
        if (sqlite3_prepare_v2(db, U8z(sql), -1, out st, IntPtr.Zero) != OK)
            throw new Exception(Cstr(sqlite3_errmsg(db)) + "  [SQL: " + sql + "]");
        var filas = new List<object[]>();
        try {
            Ligar(db, st, pars);
            int cols = sqlite3_column_count(st);
            while (sqlite3_step(st) == ROW) {
                var f = new object[cols];
                for (int c = 0; c < cols; c++) {
                    int t = sqlite3_column_type(st, c);
                    if (t == T_NULL) f[c] = null;
                    else if (t == T_INTEGER) f[c] = sqlite3_column_int64(st, c);
                    else {
                        IntPtr p = sqlite3_column_text(st, c);
                        int n = sqlite3_column_bytes(st, c);
                        byte[] b = new byte[n];
                        if (n > 0) Marshal.Copy(p, b, 0, n);
                        f[c] = Encoding.UTF8.GetString(b);
                    }
                }
                filas.Add(f);
            }
        } finally { sqlite3_finalize(st); }
        return filas.ToArray();
    }
}
'@
}
