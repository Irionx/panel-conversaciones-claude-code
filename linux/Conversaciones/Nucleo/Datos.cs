using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Data.Sqlite;

namespace Conversaciones.Nucleo;

public sealed record Etiqueta(long Id, string Nombre, string Color);

public sealed record Conversacion(
    string Id, string Titulo, string? Proyecto, string? Rama, string Cwd, string Sesion,
    string? Fecha, string? Recap, int ContextoMax, bool Archivada, int Orden,
    IReadOnlyList<Etiqueta> Etiquetas);

/// <summary>
/// La capa de datos. Misma base y MISMO esquema que la version de Windows: las
/// migraciones son las mismas cinco, en el mismo orden, asi una base creada aca
/// y una creada alla son el mismo archivo.
/// </summary>
public static class Datos
{
    // Las migraciones NUNCA se editan una vez publicadas: se agrega otra al
    // final. Si no, la base de alguien que ya migro queda distinta de la tuya.
    private static readonly string[][] Migraciones =
    {
        new[]
        {
            """
            CREATE TABLE conversacion (
                id          TEXT PRIMARY KEY,
                titulo      TEXT NOT NULL,
                proyecto    TEXT,
                rama        TEXT,
                cwd         TEXT NOT NULL,
                sesion      TEXT NOT NULL,
                fecha       TEXT,
                notas       TEXT,
                contextoMax INTEGER
            )
            """,
            """
            CREATE TABLE tag (
                conversacion_id TEXT NOT NULL,
                tag             TEXT NOT NULL,
                PRIMARY KEY (conversacion_id, tag)
            )
            """,
            "CREATE INDEX ix_conversacion_sesion ON conversacion (sesion)"
        },
        new[]
        {
            "ALTER TABLE conversacion ADD COLUMN orden INTEGER",
            "UPDATE conversacion SET orden = rowid"
        },
        new[] { "ALTER TABLE conversacion ADD COLUMN archivada INTEGER NOT NULL DEFAULT 0" },
        new[] { "ALTER TABLE conversacion ADD COLUMN recap TEXT" },
        new[]
        {
            """
            CREATE TABLE etiqueta (
                id     INTEGER PRIMARY KEY,
                nombre TEXT NOT NULL UNIQUE COLLATE NOCASE,
                color  TEXT NOT NULL
            )
            """,
            """
            CREATE TABLE conversacion_etiqueta (
                conversacion_id TEXT    NOT NULL,
                etiqueta_id     INTEGER NOT NULL,
                PRIMARY KEY (conversacion_id, etiqueta_id)
            )
            """
        }
    };

    /// <summary>Donde vive la base. En Linux manda la convencion XDG, no el
    /// layout de Windows: los datos del usuario no van al lado del binario.</summary>
    public static string Ruta
    {
        get
        {
            var propia = Environment.GetEnvironmentVariable("CONVERSACIONES_DATOS");
            if (!string.IsNullOrWhiteSpace(propia)) return propia;
            var datos = Environment.GetEnvironmentVariable("XDG_DATA_HOME");
            if (string.IsNullOrWhiteSpace(datos))
                datos = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                                     ".local", "share");
            return Path.Combine(datos, "conversaciones", "conversaciones.db");
        }
    }

    private static SqliteConnection Abrir(bool soloLectura = false)
    {
        var dir = Path.GetDirectoryName(Ruta);
        if (!soloLectura && !string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var cs = new SqliteConnectionStringBuilder
        {
            DataSource = Ruta,
            Mode = soloLectura ? SqliteOpenMode.ReadOnly : SqliteOpenMode.ReadWriteCreate
        }.ToString();
        var db = new SqliteConnection(cs);
        db.Open();
        // Igual que en Windows: WAL y un timeout, porque el panel y los comandos
        // pueden estar escribiendo al mismo tiempo.
        Ejecutar(db, "PRAGMA journal_mode = WAL");
        Ejecutar(db, "PRAGMA busy_timeout = 5000");
        return db;
    }

    /// <summary>Crea la base si no existe y la migra hasta la ultima version.</summary>
    public static void Inicializar()
    {
        using var db = Abrir();
        var version = Convert.ToInt32(Escalar(db, "PRAGMA user_version") ?? 0);
        for (var v = version; v < Migraciones.Length; v++)
        {
            using var tx = db.BeginTransaction();
            foreach (var sql in Migraciones[v]) Ejecutar(db, sql, tx);
            Ejecutar(db, $"PRAGMA user_version = {v + 1}", tx);
            tx.Commit();
        }
    }

    public static List<Conversacion> Conversaciones(bool archivadas = false)
    {
        var lista = new List<Conversacion>();
        if (!File.Exists(Ruta)) return lista;

        using var db = Abrir();
        var etiquetas = EtiquetasPorConversacion(db);

        using var cmd = db.CreateCommand();
        cmd.CommandText = """
            SELECT id, titulo, proyecto, rama, cwd, sesion, fecha, recap,
                   COALESCE(contextoMax, 0), COALESCE(archivada, 0), COALESCE(orden, rowid)
            FROM conversacion
            WHERE archivada = $arch
            ORDER BY COALESCE(orden, rowid)
            """;
        cmd.Parameters.AddWithValue("$arch", archivadas ? 1 : 0);
        using var r = cmd.ExecuteReader();
        while (r.Read())
        {
            var id = r.GetString(0);
            lista.Add(new Conversacion(
                id, r.GetString(1),
                r.IsDBNull(2) ? null : r.GetString(2),
                r.IsDBNull(3) ? null : r.GetString(3),
                r.GetString(4), r.GetString(5),
                r.IsDBNull(6) ? null : r.GetString(6),
                r.IsDBNull(7) ? null : r.GetString(7),
                r.GetInt32(8), r.GetInt32(9) != 0, r.GetInt32(10),
                etiquetas.TryGetValue(id, out var e) ? e : Array.Empty<Etiqueta>()));
        }
        return lista;
    }

    private static Dictionary<string, List<Etiqueta>> EtiquetasPorConversacion(SqliteConnection db)
    {
        var mapa = new Dictionary<string, List<Etiqueta>>();
        using var cmd = db.CreateCommand();
        cmd.CommandText = """
            SELECT ce.conversacion_id, e.id, e.nombre, e.color
            FROM conversacion_etiqueta ce
            JOIN etiqueta e ON e.id = ce.etiqueta_id
            ORDER BY e.nombre
            """;
        using var r = cmd.ExecuteReader();
        while (r.Read())
        {
            var id = r.GetString(0);
            if (!mapa.TryGetValue(id, out var l)) mapa[id] = l = new List<Etiqueta>();
            l.Add(new Etiqueta(r.GetInt64(1), r.GetString(2), r.GetString(3)));
        }
        return mapa;
    }

    /// <summary>El esquema tal como quedo en disco: la version y cada CREATE.
    /// Es lo que se compara contra la base de Windows para saber si son la
    /// misma; si no lo son, los datos dejan de ser intercambiables.</summary>
    public static List<string> Esquema()
    {
        var lineas = new List<string>();
        using var db = Abrir();
        lineas.Add("user_version = " + Convert.ToInt32(Escalar(db, "PRAGMA user_version") ?? 0));
        using var cmd = db.CreateCommand();
        cmd.CommandText = "SELECT type, name, COALESCE(sql, '') FROM sqlite_master ORDER BY type, name";
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lineas.Add($"{r.GetString(0),-6} {r.GetString(1),-24} {System.Text.RegularExpressions.Regex.Replace(r.GetString(2), @"\s+", " ").Trim()}");
        return lineas;
    }

    private static void Ejecutar(SqliteConnection db, string sql, SqliteTransaction? tx = null)
    {
        using var cmd = db.CreateCommand();
        cmd.CommandText = sql;
        if (tx is not null) cmd.Transaction = tx;
        cmd.ExecuteNonQuery();
    }

    private static object? Escalar(SqliteConnection db, string sql)
    {
        using var cmd = db.CreateCommand();
        cmd.CommandText = sql;
        return cmd.ExecuteScalar();
    }
}
