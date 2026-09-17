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
            case "--abrir":
                Console.WriteLine(Terminal.Abrir(args[1], args[2]) ? "lanzado" : "no pude lanzar la terminal");
                return;
            default: ConstruirApp().StartWithClassicDesktopLifetime(args); return;
        }
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
        Console.WriteLine($"\n{todas.Count} conversaciones");
    }
}
