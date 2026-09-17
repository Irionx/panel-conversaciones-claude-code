using System;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Threading;
using Conversaciones.Nucleo;

namespace Conversaciones;

public partial class VentanaPanel : Window
{
    private readonly StackPanel _lista;
    private readonly TextBlock _pie;
    private readonly DispatcherTimer _reloj = new() { Interval = TimeSpan.FromSeconds(30) };

    public VentanaPanel()
    {
        AvaloniaXamlLoader.Load(this);
        _lista = this.FindControl<StackPanel>("lista")!;
        _pie = this.FindControl<TextBlock>("pie")!;

        // Sin barra de titulo del sistema, el asa para mover la ventana es
        // nuestra: BeginMoveDrag se la pide al gestor de ventanas.
        this.FindControl<Grid>("barraTitulo")!.PointerPressed += (_, e) => BeginMoveDrag(e);
        this.FindControl<Button>("btnCerrar")!.Click += (_, _) => Close();
        this.FindControl<Button>("btnRefrescar")!.Click += (_, _) => Cargar();

        _reloj.Tick += (_, _) => Cargar();
        _reloj.Start();
        Cargar();
    }

    private void Cargar()
    {
        _lista.Children.Clear();
        try
        {
            Datos.Inicializar();
            var todas = Datos.Conversaciones();
            if (todas.Count == 0)
            {
                _lista.Children.Add(Texto(
                    "Todavia no hay conversaciones guardadas.\n\n" +
                    "Desde la carpeta de un proyecto, con Claude Code abierto ahi:\n\n" +
                    "    conversaciones guardar\n\n" +
                    "y la charla en curso aparece en esta lista.",
                    11.5, "#6B7385", true));
                _pie.Text = Datos.Ruta;
                return;
            }

            foreach (var c in todas) _lista.Children.Add(Tarjeta(c));

            var term = Terminal.Cual();
            _pie.Text = term is null
                ? "No encuentro ninguna terminal instalada: el click no va a poder abrir nada."
                : $"{todas.Count} conversaciones · se actualiza solo cada 30 s";
        }
        catch (Exception ex)
        {
            _lista.Children.Add(Texto("No pude leer las conversaciones:\n" + ex.Message, 11.5, "#F85149", true));
        }
    }

    private Control Tarjeta(Conversacion c)
    {
        var ctx = Transcripts.DeSesion(c.Cwd, c.Sesion, c.ContextoMax);

        var cuerpo = new StackPanel { Spacing = 5 };
        cuerpo.Children.Add(Texto(c.Titulo, 12.5, "#F2F5F9", true, FontWeight.SemiBold));

        var meta = string.IsNullOrWhiteSpace(c.Proyecto) ? "" : c.Proyecto!;
        if (ctx.Hay) meta += (meta.Length > 0 ? "  ·  " : "") +
                             $"{ctx.Porcentaje:0.#}%  ({Transcripts.FormatoTokens(ctx.Tokens)} de {Transcripts.FormatoTokens(ctx.Limite)})";
        if (meta.Length > 0) cuerpo.Children.Add(Texto(meta, 10.5, "#6B7385", false));

        if (ctx.Hay) cuerpo.Children.Add(Barra(ctx.Porcentaje));

        // El recap guardado manda sobre el del transcript: lo escribio una
        // persona (o el /save) pensando en que se lea en la tarjeta.
        if ((c.Recap ?? ctx.Recap) is { Length: > 0 } recap)
            cuerpo.Children.Add(Texto(recap, 10.5, "#8A93A5", true));

        if (c.Etiquetas.Count > 0)
        {
            var chips = new WrapPanel { Margin = new Thickness(0, 2, 0, 0) };
            foreach (var e in c.Etiquetas) chips.Children.Add(Chip(e));
            cuerpo.Children.Add(chips);
        }

        var tarjeta = new Border
        {
            Background = Pincel("#1C222B"),
            BorderBrush = Pincel("#232A34"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(11, 9),
            Cursor = new Cursor(StandardCursorType.Hand),
            Child = cuerpo
        };
        ToolTip.SetTip(tarjeta, $"Abrir en una terminal:\nclaude --resume {c.Sesion}\nen {c.Cwd}");
        tarjeta.PointerPressed += (_, e) =>
        {
            if (!e.GetCurrentPoint(tarjeta).Properties.IsLeftButtonPressed) return;
            if (!Terminal.Abrir(c.Cwd, c.Sesion))
                _pie.Text = "No pude abrir una terminal. Instalada tiene que haber alguna de: " +
                            string.Join(", ", Terminal.Soportadas().Take(4)) + "...";
        };
        return tarjeta;
    }

    // La barra de contexto: verde mientras sobra, amarilla cuando aprieta y roja
    // cuando esta por quedarse sin lugar.
    private static Control Barra(double porcentaje)
    {
        var color = porcentaje < 60 ? "#3FB950" : porcentaje < 85 ? "#D29922" : "#F85149";
        var relleno = new Rectangle
        {
            Fill = Pincel(color),
            RadiusX = 2, RadiusY = 2,
            HorizontalAlignment = HorizontalAlignment.Left,
            Height = 4
        };
        var canal = new Border
        {
            Background = Pincel("#2A313C"),
            CornerRadius = new CornerRadius(2),
            Height = 4,
            Child = relleno
        };
        // El ancho se sabe recien cuando el layout midio la fila.
        canal.SizeChanged += (_, e) => relleno.Width = Math.Max(2, e.NewSize.Width * Math.Min(porcentaje, 100) / 100.0);
        return canal;
    }

    private static Control Chip(Etiqueta e) => new Border
    {
        Background = Pincel(ColorEtiqueta(e.Color)),
        CornerRadius = new CornerRadius(4),
        Padding = new Thickness(5, 1),
        Margin = new Thickness(0, 0, 4, 0),
        Child = new TextBlock { Text = e.Nombre, FontSize = 8.5, Foreground = Pincel("#0D1117") }
    };

    // Los colores son claves ("verde", "azul"...), no hex: la paleta vive en el
    // panel, no en la base. Si aparece una clave desconocida, gris y seguimos.
    private static string ColorEtiqueta(string clave) => clave.ToLowerInvariant() switch
    {
        "verde" => "#3FB950",
        "azul" => "#58A6FF",
        "violeta" => "#BC8CFF",
        "rosa" => "#F778BA",
        "rojo" => "#F85149",
        "naranja" => "#DB8E3C",
        "amarillo" => "#D29922",
        "gris" => "#8A93A5",
        _ => clave.StartsWith('#') ? clave : "#8A93A5"
    };

    private static TextBlock Texto(string t, double tam, string color, bool envolver,
                                   FontWeight peso = FontWeight.Normal) => new()
    {
        Text = t,
        FontSize = tam,
        FontWeight = peso,
        Foreground = Pincel(color),
        TextWrapping = envolver ? TextWrapping.Wrap : TextWrapping.NoWrap,
        TextTrimming = envolver ? TextTrimming.None : TextTrimming.CharacterEllipsis
    };

    private static IBrush Pincel(string hex) => new SolidColorBrush(Color.Parse(hex));
}
