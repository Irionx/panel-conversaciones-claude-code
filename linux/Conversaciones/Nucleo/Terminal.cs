using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace Conversaciones.Nucleo;

/// <summary>
/// Abre una conversacion en la terminal del escritorio. En Windows esto era
/// Windows Terminal y listo; en Linux no hay una sola, asi que se prueba una
/// lista en orden y gana la primera que este instalada.
/// </summary>
public static class Terminal
{
    // El orden no es alfabetico: primero lo que el usuario eligio ($TERMINAL),
    // despues el alias de Debian, y recien ahi las conocidas por popularidad.
    // Cada una recibe los argumentos a su manera, no hay estandar.
    private static readonly (string Exe, Func<string, string, string[]> Args)[] Conocidas =
    {
        ("x-terminal-emulator", (cwd, cmd) => new[] { "-e", "bash", "-c", Cd(cwd, cmd) }),
        ("konsole",             (cwd, cmd) => new[] { "--workdir", cwd, "-e", "bash", "-c", cmd }),
        ("gnome-terminal",      (cwd, cmd) => new[] { "--working-directory=" + cwd, "--", "bash", "-c", cmd }),
        ("xfce4-terminal",      (cwd, cmd) => new[] { "--working-directory=" + cwd, "-e", "bash -c " + Comillas(cmd) }),
        ("kitty",               (cwd, cmd) => new[] { "--directory", cwd, "bash", "-c", cmd }),
        ("alacritty",           (cwd, cmd) => new[] { "--working-directory", cwd, "-e", "bash", "-c", cmd }),
        ("wezterm",             (cwd, cmd) => new[] { "start", "--cwd", cwd, "--", "bash", "-c", cmd }),
        ("foot",                (cwd, cmd) => new[] { "--working-directory=" + cwd, "bash", "-c", cmd }),
        ("xterm",               (cwd, cmd) => new[] { "-e", "bash", "-c", Cd(cwd, cmd) })
    };

    private static string Cd(string cwd, string cmd) => $"cd {Comillas(cwd)} && {cmd}";

    private static string Comillas(string s) => "'" + s.Replace("'", "'\\''") + "'";

    /// <summary>Que se va a ejecutar adentro de la terminal. El `exec bash` del
    /// final deja la ventana abierta cuando Claude Code termina, igual que el
    /// `cmd /k` de la version de Windows.</summary>
    public static string Comando(string sesion, bool remoto = false) =>
        $"claude --resume {sesion}{(remoto ? " --remote-control" : "")}; exec bash";

    /// <summary>La primera terminal instalada, o null si no hay ninguna.</summary>
    public static string? Cual()
    {
        var propia = Environment.GetEnvironmentVariable("TERMINAL");
        if (!string.IsNullOrWhiteSpace(propia) && EnPath(propia) is { } p) return p;
        return Conocidas.Select(t => EnPath(t.Exe)).FirstOrDefault(p => p is not null);
    }

    private static string? EnPath(string exe)
    {
        if (exe.Contains('/')) return File.Exists(exe) ? exe : null;
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in path.Split(':', StringSplitOptions.RemoveEmptyEntries))
        {
            var f = Path.Combine(dir, exe);
            if (File.Exists(f)) return f;
        }
        return null;
    }

    /// <summary>Arma el lanzamiento sin ejecutarlo. Separado a proposito: asi se
    /// puede ver que se iba a correr sin abrir ninguna ventana.</summary>
    public static (string Exe, string[] Args)? Preparar(string cwd, string sesion, bool remoto = false)
    {
        var exe = Cual();
        if (exe is null) return null;
        var nombre = Path.GetFileName(exe);
        var receta = Conocidas.FirstOrDefault(t => t.Exe == nombre).Args
                     ?? ((c, cmd) => new[] { "-e", "bash", "-c", Cd(c, cmd) });
        return (exe, receta(cwd, Comando(sesion, remoto)));
    }

    public static bool Abrir(string cwd, string sesion, bool remoto = false)
    {
        var plan = Preparar(cwd, sesion, remoto);
        if (plan is null) return false;
        var psi = new ProcessStartInfo(plan.Value.Exe) { UseShellExecute = false, WorkingDirectory = Existe(cwd) ? cwd : "/" };
        foreach (var a in plan.Value.Args) psi.ArgumentList.Add(a);
        try { Process.Start(psi); return true; }
        catch { return false; }
    }

    private static bool Existe(string dir)
    {
        try { return Directory.Exists(dir); } catch { return false; }
    }

    /// <summary>Todas las que se conocen, para poder decirle a alguien que no
    /// tiene ninguna cual instalar.</summary>
    public static IEnumerable<string> Soportadas() => Conocidas.Select(t => t.Exe);
}
