// =============================================================================
//  lanzador.cs - Conversaciones.exe: abre Hilos de Claudio sin ninguna consola a la vista
// -----------------------------------------------------------------------------
//  powershell.exe es de consola: desde un acceso directo Windows le crea una
//  antes de correr el script, y en Windows 11 esa consola es Windows Terminal.
//  Este .exe es de ventanas y lanza PowerShell con CREATE_NO_WINDOW. Lo compila
//  lib-setup.ps1 (Build-Lanzador) con el compilador de C# que ya trae Windows.
// =============================================================================
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

static class Lanzador
{
    [STAThread]
    static int Main(string[] args)
    {
        string app = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);

        // Dos usos fijos y nada mas: que no sea un "corre cualquier .ps1 oculto"
        // que otro programa pueda aprovechar.
        string script;
        string extra = "";
        if (args.Length == 0)
        {
            script = "gadget.ps1";
        }
        else if (args.Length == 2 && args[0] == "--abrir")
        {
            script = "abrir-conversacion.ps1";
            extra = " -Url " + Comillas(args[1]);
        }
        else
        {
            return Fallar("Uso:  Conversaciones.exe   o   Conversaciones.exe --abrir <url>");
        }

        string ruta = Path.Combine(app, script);
        if (!File.Exists(ruta)) return Fallar("No encuentro " + ruta);

        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
        // La misma linea que usaba el acceso directo: gadget.ps1 y cerrar-gadget.ps1
        // reconocen al gadget vivo por ese -File "...\app\gadget.ps1".
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + Comillas(ruta) + extra;
        psi.WorkingDirectory = Path.GetDirectoryName(app);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        try
        {
            Process.Start(psi).Dispose();
        }
        catch (Exception e)
        {
            return Fallar("No pude arrancar PowerShell:\n\n" + e.Message);
        }
        return 0;
    }

    // Reglas de CommandLineToArgvW: las barras pegadas a una comilla se
    // duplican, o se comen la comilla de cierre y el argumento se corre.
    static string Comillas(string s)
    {
        StringBuilder sb = new StringBuilder("\"");
        int barras = 0;
        foreach (char c in s)
        {
            if (c == '\\') { barras++; continue; }
            sb.Append('\\', c == '"' ? barras * 2 + 1 : barras);
            sb.Append(c);
            barras = 0;
        }
        sb.Append('\\', barras * 2);
        return sb.Append('"').ToString();
    }

    static int Fallar(string texto)
    {
        MessageBox.Show(texto, "Conversaciones", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        return 1;
    }
}
