using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace Conversaciones.Nucleo;

/// <summary>
/// Guardar la conversacion en curso, que es lo que en Windows hace guardar.ps1.
/// Deduce todo lo que puede: la sesion, el proyecto, la rama y el titulo.
/// </summary>
public static class Guardado
{
    /// <summary>
    /// Cual es la sesion en curso para esta carpeta. Claude Code publica la suya
    /// en el entorno; sin eso se cae al transcript mas reciente del proyecto, que
    /// con dos sesiones abiertas a la vez puede ser la otra.
    /// </summary>
    public static string? SesionActual(string cwd)
    {
        var dir = Path.Combine(Transcripts.RaizProyectos, Transcripts.CarpetaProyecto(cwd));
        if (!Directory.Exists(dir)) return null;

        var delEntorno = Environment.GetEnvironmentVariable("CLAUDE_CODE_SESSION_ID");
        if (!string.IsNullOrWhiteSpace(delEntorno) &&
            File.Exists(Path.Combine(dir, delEntorno + ".jsonl"))) return delEntorno;

        return new DirectoryInfo(dir).EnumerateFiles("*.jsonl")
            .OrderByDescending(f => f.LastWriteTimeUtc)
            .FirstOrDefault()?.Name.Replace(".jsonl", "");
    }

    /// <summary>
    /// El nombre real de la sesion: el que se puso con /rename si sobrevive en
    /// disco, y si no el titulo automatico que Claude Code escribe en el
    /// transcript, que es el mismo que muestra la pestaña de la terminal.
    /// </summary>
    public static string? NombreSesion(string cwd, string sesion)
    {
        var dirUuid = Path.Combine(Transcripts.RaizProyectos, Transcripts.CarpetaProyecto(cwd), sesion);
        var custom = Path.Combine(dirUuid, "custom-title.json");
        if (File.Exists(custom))
        {
            try
            {
                var j = JsonDocument.Parse(File.ReadAllText(custom)).RootElement;
                if (j.TryGetProperty("customTitle", out var t) && t.GetString() is { Length: > 0 } s) return s;
            }
            catch { }
        }

        var transcript = Transcripts.RutaTranscript(cwd, sesion);
        if (transcript is null) return null;

        // El ai-title se escribe cerca del arranque de la conversacion, asi que
        // se busca desde el principio y no desde la cola.
        try
        {
            foreach (var linea in File.ReadLines(transcript).Take(400))
            {
                if (!linea.Contains("\"type\":\"ai-title\"")) continue;
                var j = JsonDocument.Parse(linea).RootElement;
                if (j.TryGetProperty("aiTitle", out var t) && t.GetString() is { Length: > 0 } s) return s;
            }
        }
        catch { }
        return null;
    }

    public static string? Rama(string cwd)
    {
        try
        {
            var psi = new ProcessStartInfo("git", "rev-parse --abbrev-ref HEAD")
            {
                WorkingDirectory = cwd,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };
            using var p = Process.Start(psi);
            if (p is null) return null;
            var salida = p.StandardOutput.ReadToEnd().Trim();
            p.WaitForExit(4000);
            return p.ExitCode == 0 && salida.Length > 0 ? salida : null;
        }
        catch { return null; }
    }

    /// <summary>Guarda la conversacion en curso. Devuelve el texto a mostrar.</summary>
    public static string Guardar(string cwd, string? titulo, string? recap)
    {
        var sesion = SesionActual(cwd);
        if (sesion is null)
            return $"No encuentro ninguna sesion de Claude Code para esta carpeta.\nBuscaba en: " +
                   Path.Combine(Transcripts.RaizProyectos, Transcripts.CarpetaProyecto(cwd));

        var proyecto = new DirectoryInfo(cwd).Name;
        titulo = string.IsNullOrWhiteSpace(titulo)
            ? NombreSesion(cwd, sesion) ?? $"{proyecto} - {DateTime.Now:dd/MM/yyyy HH:mm}"
            : titulo;

        var ctx = Transcripts.DeSesion(cwd, sesion);
        var rama = Rama(cwd);
        var (id, nueva, antes) = Datos.Guardar(titulo, cwd, sesion, proyecto, rama, recap, 0);

        var texto = $"Conversacion {(nueva ? "agregada" : "actualizada")}\n" +
                    $"    id       : {id}\n" +
                    $"    titulo   : {titulo}\n" +
                    $"    proyecto : {proyecto}{(rama is null ? "" : $"  ({rama})")}\n" +
                    $"    sesion   : {sesion}\n";
        if (ctx.Hay)
            texto += $"    contexto : {Transcripts.FormatoTokens(ctx.Tokens)} de " +
                     $"{Transcripts.FormatoTokens(ctx.Limite)}  ({ctx.Porcentaje:0.#}%)\n";
        if (antes is not null) texto += $"\n    Antes se llamaba: {antes}\n";
        return texto;
    }
}
