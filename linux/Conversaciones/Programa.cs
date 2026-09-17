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

    // Lista lo que el panel va a mostrar, en texto. Sirve para comparar numero
    // por numero contra la version de Windows sin abrir ninguna ventana.
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
}
