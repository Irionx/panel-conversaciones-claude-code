using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Conversaciones.Nucleo;

/// <summary>Lo que se sabe del uso de contexto de una sesion.</summary>
public sealed record Contexto(int Tokens, int Limite, double Porcentaje, bool Hay,
                              string Fuente, DateTime? Fecha, string? Recap)
{
    public static readonly Contexto Vacio = new(0, 0, 0, false, "ninguna", null, null);
}

/// <summary>
/// Lee los transcripts de Claude Code. Es el puerto del mismo algoritmo que usa
/// la version de Windows: si los dos paneles no dan el mismo numero, uno miente.
/// </summary>
public static class Transcripts
{
    // Claude Code respeta CLAUDE_CONFIG_DIR; respetarla tambien deja probar esto
    // contra otra carpeta sin tocar la de verdad.
    public static string DirClaude =>
        Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR") is { Length: > 0 } d
            ? d
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");

    public static string RaizProyectos => Path.Combine(DirClaude, "projects");

    private static string CacheHud => Path.Combine(DirClaude, "plugins", "claude-hud", "context-cache");

    private static readonly string[] Campos =
        { "input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens" };

    private static readonly Dictionary<string, (string Sello, Contexto Valor)> Cache = new();
    private static int _ventanaHabitual = -1;

    /// <summary>"/home/ana/mi proyecto" a "-home-ana-mi-proyecto". Todo lo que no
    /// es alfanumerico pasa a guion: es la regla de Claude Code.</summary>
    public static string CarpetaProyecto(string cwd) =>
        Regex.Replace(cwd.TrimEnd('/'), "[^A-Za-z0-9]", "-");

    public static string? RutaTranscript(string cwd, string sesion)
    {
        var f = Path.Combine(RaizProyectos, CarpetaProyecto(cwd), sesion + ".jsonl");
        return File.Exists(f) ? f : null;
    }

    /// <summary>La cola del archivo, por seek. Leer entero un .jsonl de megas en
    /// cada refresco no es opcion; la primera linea sale partida y se descarta.</summary>
    public static List<string> Cola(string ruta, int bytes = 524288)
    {
        try
        {
            using var fs = new FileStream(ruta, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var desde = Math.Max(0, fs.Length - bytes);
            fs.Seek(desde, SeekOrigin.Begin);
            var buf = new byte[fs.Length - desde];
            var leidos = fs.Read(buf, 0, buf.Length);
            if (leidos <= 0) return new List<string>();
            var lineas = Encoding.UTF8.GetString(buf, 0, leidos).Split('\n').ToList();
            if (desde > 0 && lineas.Count > 1) lineas.RemoveAt(0);
            return lineas.Where(l => !string.IsNullOrWhiteSpace(l)).ToList();
        }
        catch { return new List<string>(); }
    }

    /// <summary>El cache de claude-hud, indexado por el sha256 de la ruta del
    /// transcript. Es la unica fuente que sabe el tamaño REAL de la ventana.</summary>
    private static JsonElement? CacheContexto(string rutaTranscript)
    {
        try
        {
            if (!Directory.Exists(CacheHud)) return null;
            var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(rutaTranscript))).ToLowerInvariant();
            var f = Path.Combine(CacheHud, hash + ".json");
            if (!File.Exists(f)) return null;
            return JsonDocument.Parse(File.ReadAllText(f)).RootElement.Clone();
        }
        catch { return null; }
    }

    /// <summary>La ventana mas frecuente entre las sesiones conocidas, para las
    /// que no tienen cache propio.</summary>
    private static int VentanaHabitual()
    {
        if (_ventanaHabitual >= 0) return _ventanaHabitual;
        _ventanaHabitual = 0;
        try
        {
            var tam = new List<int>();
            foreach (var f in Directory.EnumerateFiles(CacheHud, "*.json"))
            {
                try
                {
                    var r = JsonDocument.Parse(File.ReadAllText(f)).RootElement;
                    if (r.TryGetProperty("context_window_size", out var v) && v.TryGetInt32(out var n) && n > 0)
                        tam.Add(n);
                }
                catch { }
            }
            if (tam.Count > 0)
                _ventanaHabitual = tam.GroupBy(x => x).OrderByDescending(g => g.Count()).First().Key;
        }
        catch { }
        return _ventanaHabitual;
    }

    public static Contexto DeSesion(string cwd, string sesion, int limite = 0)
    {
        var f = RutaTranscript(cwd, sesion);
        return f is null ? Contexto.Vacio : DeTranscript(f, limite);
    }

    public static Contexto DeTranscript(string f, int limite = 0)
    {
        var fi = new FileInfo(f);
        // Mientras el archivo no cambie, el contexto tampoco: de N conversaciones
        // normalmente solo una esta trabajando.
        var sello = fi.LastWriteTimeUtc.Ticks + "|" + fi.Length;
        if (Cache.TryGetValue(f, out var guardado) && guardado.Sello == sello) return guardado.Valor;

        var cola = Cola(f);
        if (cola.Count == 0) return Contexto.Vacio;

        // El recap sale de la cola COMPLETA: en una charla con mucha herramienta,
        // las ultimas lineas pueden ser puros resultados y ningun last-prompt.
        string? recap = null;
        for (var i = cola.Count - 1; i >= 0; i--)
        {
            if (!cola[i].Contains("\"type\":\"last-prompt\"")) continue;
            try
            {
                var texto = JsonDocument.Parse(cola[i]).RootElement.GetProperty("lastPrompt").GetString();
                if (!string.IsNullOrWhiteSpace(texto))
                {
                    recap = Regex.Replace(texto, @"\s+", " ").Trim();
                    if (recap.Length > 200) recap = recap.Substring(0, 200);
                }
            }
            catch { }
            break;
        }

        var lineas = cola.Count > 60 ? cola.GetRange(cola.Count - 60, 60) : cola;

        JsonElement? usage = null;
        for (var i = lineas.Count - 1; i >= 0; i--)
        {
            var l = lineas[i];
            if (!l.Contains("\"type\":\"assistant\"") || !l.Contains("\"usage\"")) continue;
            // Los subagentes tienen su propio contexto chico: no es el de la charla.
            if (l.Contains("\"isSidechain\":true")) continue;
            try
            {
                var raiz = JsonDocument.Parse(l).RootElement;
                if (!raiz.TryGetProperty("message", out var m) || !m.TryGetProperty("usage", out var u)) continue;
                // Un turno interrumpido deja los cuatro campos en cero: existe, pero
                // aceptarlo mostraba 0% con el transcript lleno.
                if (Sumar(u) <= 0) continue;
                usage = u.Clone();
                break;
            }
            catch { }
        }

        var fuenteUso = "transcript";
        if (usage is null)
        {
            var c = CacheContexto(f);
            if (c is { } cc && cc.TryGetProperty("current_usage", out var cu))
            {
                usage = cu.Clone();
                fuenteUso = "claude-hud";
            }
        }

        if (usage is null)
        {
            // Sin usage no hay barra, pero el recap igual sirve para la tarjeta.
            var sinUso = Contexto.Vacio with { Recap = recap };
            Cache[f] = (sello, sinUso);
            return sinUso;
        }

        var tokens = Sumar(usage.Value);

        // El limite, por orden de confianza: lo fijado, el real que cachea
        // claude-hud, la ventana mas habitual, y recien ahi una estimacion.
        var fuente = "fijado";
        if (limite <= 0 && CacheContexto(f) is { } cache2 &&
            cache2.TryGetProperty("context_window_size", out var cw) && cw.TryGetInt32(out var n) && n > 0)
        {
            limite = n;
            fuente = "claude-hud";
        }
        if (limite <= 0 && VentanaHabitual() > 0) { limite = VentanaHabitual(); fuente = "habitual"; }
        if (limite <= 0) { limite = tokens > 200000 ? 1000000 : 200000; fuente = "estimado"; }

        var resultado = new Contexto(tokens, limite, Math.Round(100.0 * tokens / limite, 1), true,
                                     fuente + (fuenteUso == "claude-hud" ? " (uso del hud)" : ""),
                                     fi.LastWriteTime, recap);
        Cache[f] = (sello, resultado);
        return resultado;

        static int Sumar(JsonElement u)
        {
            var s = 0;
            foreach (var campo in Campos)
                if (u.TryGetProperty(campo, out var v) && v.TryGetInt32(out var n)) s += n;
            return s;
        }
    }

    /// <summary>Todos los transcripts que hay, del mas recien tocado al mas viejo.</summary>
    public static IEnumerable<FileInfo> Todos()
    {
        if (!Directory.Exists(RaizProyectos)) yield break;
        var archivos = new DirectoryInfo(RaizProyectos)
            .EnumerateDirectories()
            .SelectMany(d => d.EnumerateFiles("*.jsonl"))
            .OrderByDescending(f => f.LastWriteTimeUtc);
        foreach (var f in archivos) yield return f;
    }

    public static string FormatoTokens(int n) => n >= 1000
        ? (n / 1000.0).ToString("0.#", CultureInfo.InvariantCulture) + "k"
        : n.ToString(CultureInfo.InvariantCulture);
}
