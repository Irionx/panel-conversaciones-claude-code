using System;
using System.IO;
using System.Linq;
using Avalonia;
using Conversaciones.Nucleo;

namespace Conversaciones;

internal static class Programa
{
    [STAThread]
    public static void Main(string[] args)
    {
        switch (args.Length > 0 ? args[0] : "")
        {
            case "--verificar": Verificar(); return;
            case "--sesiones": Sesiones(args.Length > 1 ? int.Parse(args[1]) : 10); return;
            case "--lista": Lista(); return;
            case "--esquema": Esquema(); return;
            case "--terminal": TerminalElegida(); return;
            case "--ver": Ver(args.Length > 1 ? args[1] : ""); return;
            // Sin guiones: es un comando, no una opcion del panel.
            case "guardar":
                Console.WriteLine();
                Console.WriteLine("  " + Guardado.Guardar(
                    Environment.CurrentDirectory,
                    args.Length > 1 && !args[1].StartsWith("--") ? args[1] : null,
                    Opcion(args, "--recap"), Opcion(args, "--notas")).Replace("\n", "\n  "));
                return;
            case "--abrir":
                Console.WriteLine(Terminal.Abrir(args[1], args[2]) ? "lanzado" : "no pude lanzar la terminal");
                return;
            // El escritorio invoca el binario con la URL como unico argumento:
            // ese es el handler de claudeconv://, no una forma de abrir el panel.
            case var u when u.StartsWith("claudeconv://", StringComparison.OrdinalIgnoreCase):
                Enlace(u);
                return;
            default: ConstruirApp().StartWithClassicDesktopLifetime(args); return;
        }
    }

    // Una conversacion entera, notas incluidas. El panel no las muestra a
    // proposito, pero desde la terminal se tienen que poder leer.
    private static void Ver(string id)
    {
        var c = Datos.PorId(id);
        if (c is null) { Console.WriteLine($"no hay ninguna conversacion con id '{id}'"); return; }
        var ctx = Transcripts.DeSesion(c.Cwd, c.Sesion, c.ContextoMax);
        Console.WriteLine($"  {c.Titulo}");
        Console.WriteLine($"    id       : {c.Id}");
        Console.WriteLine($"    proyecto : {c.Proyecto}{(c.Rama is null ? "" : $"  ({c.Rama})")}");
        Console.WriteLine($"    carpeta  : {c.Cwd}");
        Console.WriteLine($"    sesion   : {c.Sesion}");
        Console.WriteLine($"    fecha    : {c.Fecha}");
        if (ctx.Hay)
            Console.WriteLine($"    contexto : {Transcripts.FormatoTokens(ctx.Tokens)} de " +
                              $"{Transcripts.FormatoTokens(ctx.Limite)}  ({ctx.Porcentaje:0.#}%)");
        if (c.Recap is { Length: > 0 }) Console.WriteLine($"    recap    : {c.Recap}");
        if (Datos.Notas(c.Id) is { Length: > 0 } n) Console.WriteLine($"    notas    : {n}");
    }

    // El valor de una opcion --algo, o null si no vino.
    private static string? Opcion(string[] args, string nombre)
    {
        var i = Array.IndexOf(args, nombre);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }

    // UsePlatformDetect elige el backend solo: X11 en Linux (tambien bajo
    // XWayland en una sesion Wayland), Win32 en Windows.
    public static AppBuilder ConstruirApp() =>
        AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace();

    // Arma la ventana SIN mostrarla y dice como quedo. Un error de XAML no se ve
    // al compilar, solo al correr: esto lo saca a la luz desde una terminal.
    private static void Verificar()
    {
        ConstruirApp().SetupWithoutStarting();
        var v = new VentanaPanel();
        Console.WriteLine($"ventana ok  {v.Width}x{v.Height}  topmost={v.Topmost}  " +
                          $"decoraciones={v.WindowDecorations}  enBarra={v.ShowInTaskbar}  " +
                          $"transparencia={v.ActualTransparencyLevel}");
    }

    // Las sesiones que hay en disco, esten guardadas o no. Sirve para comparar
    // numero por numero contra la version de Windows sin abrir ninguna ventana.
    private static void Sesiones(int cuantas)
    {
        Console.WriteLine($"raiz: {Transcripts.RaizProyectos}");
        if (!Directory.Exists(Transcripts.RaizProyectos))
        {
            Console.WriteLine("no existe: no hay transcripts de Claude Code en esta cuenta");
            return;
        }

        foreach (var f in Transcripts.Todos().Take(cuantas))
        {
            var c = Transcripts.DeTranscript(f.FullName);
            var uso = c.Hay
                ? $"{c.Porcentaje,5:0.0}%  {Transcripts.FormatoTokens(c.Tokens),6} / {Transcripts.FormatoTokens(c.Limite),-6} [{c.Fuente}]"
                : "  sin datos de contexto";
            Console.WriteLine($"{f.Name[..8]}  {f.LastWriteTime:dd/MM HH:mm}  {uso}");
            if (c.Recap is { Length: > 0 } r)
                Console.WriteLine($"          {(r.Length > 90 ? r[..90] : r)}");
        }
    }

    // claudeconv://abrir?id=<slug>[&remoto=1]
    //
    // SEGURIDAD: de la URL solo se acepta un id contra lista blanca y el flag
    // remoto comparado contra el literal "1". La carpeta y el uuid salen de la
    // base local, que es de confianza, y el comando esta fijo en Terminal.
    private static void Enlace(string url)
    {
        var m = System.Text.RegularExpressions.Regex.Match(url, "id=([^&/]+)");
        var id = m.Success ? Uri.UnescapeDataString(m.Groups[1].Value) : "";
        if (!System.Text.RegularExpressions.Regex.IsMatch(id, "^[A-Za-z0-9._-]{1,64}$"))
        {
            Console.Error.WriteLine($"URL sin un id valido: {url}");
            Environment.ExitCode = 1;
            return;
        }

        var c = Datos.PorId(id);
        if (c is null)
        {
            Console.Error.WriteLine($"No hay ninguna conversacion con id '{id}' en el panel");
            Environment.ExitCode = 1;
            return;
        }

        var remoto = System.Text.RegularExpressions.Regex.IsMatch(url, "[?&]remoto=1(&|$)");
        if (!Terminal.Abrir(c.Cwd, c.Sesion, remoto))
        {
            Console.Error.WriteLine("No encontre ninguna terminal para abrirla: " +
                                    string.Join(", ", Terminal.Soportadas()));
            Environment.ExitCode = 1;
        }
    }

    // Que terminal se va a usar y con que argumentos, SIN abrirla. En Linux no
    // hay una sola terminal, asi que conviene poder ver cual gano.
    private static void TerminalElegida()
    {
        var exe = Terminal.Cual();
        if (exe is null)
        {
            Console.WriteLine("no hay ninguna terminal instalada de las que conozco:");
            Console.WriteLine("  " + string.Join(", ", Terminal.Soportadas()));
            return;
        }
        Console.WriteLine("terminal: " + exe);
        var plan = Terminal.Preparar("/home/ana/mi proyecto", "11111111-2222-3333-4444-555555555555");
        if (plan is { } p)
            Console.WriteLine("lanzaria: " + p.Exe + " " + string.Join(" ", p.Args.Select(a => a.Contains(' ') ? "\"" + a + "\"" : a)));
    }

    // El esquema tal como quedo en disco. Comparable contra el de Windows:
    // si las dos bases no son iguales, los datos dejan de ser intercambiables.
    private static void Esquema()
    {
        Datos.Inicializar();
        foreach (var linea in Datos.Esquema()) Console.WriteLine(linea);
    }

    // Lo que va a mostrar el panel: las conversaciones GUARDADAS, con su
    // contexto al dia. Es la misma lectura que hara la ventana.
    private static void Lista()
    {
        Console.WriteLine($"base: {Datos.Ruta}");
        Datos.Inicializar();
        var todas = Datos.Conversaciones();
        if (todas.Count == 0)
        {
            Console.WriteLine("la base esta vacia: todavia no hay conversaciones guardadas");
            return;
        }

        foreach (var c in todas)
        {
            var ctx = Transcripts.DeSesion(c.Cwd, c.Sesion, c.ContextoMax);
            var uso = ctx.Hay ? $"{ctx.Porcentaje,5:0.0}%" : "    -";
            var etiquetas = c.Etiquetas.Count > 0
                ? "  [" + string.Join(" ", c.Etiquetas.Select(e => e.Nombre)) + "]"
                : "";
            Console.WriteLine($"{uso}  {c.Titulo}{etiquetas}");
            Console.WriteLine($"        {c.Proyecto ?? "-"}  ·  {c.Id}");
            if ((c.Recap ?? ctx.Recap) is { Length: > 0 } r)
                Console.WriteLine($"        {(r.Length > 88 ? r[..88] : r)}");
        }
        Console.WriteLine($"\n{todas.Count} conversacion{(todas.Count == 1 ? "" : "es")}");
    }
}
