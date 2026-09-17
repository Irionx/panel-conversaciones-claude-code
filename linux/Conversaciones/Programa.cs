using System;
using Avalonia;

namespace Conversaciones;

internal static class Programa
{
    [STAThread]
    public static void Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--verificar") { Verificar(); return; }
        ConstruirApp().StartWithClassicDesktopLifetime(args);
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
}
