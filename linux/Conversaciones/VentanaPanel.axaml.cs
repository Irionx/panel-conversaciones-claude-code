using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Markup.Xaml;

namespace Conversaciones;

public partial class VentanaPanel : Window
{
    public VentanaPanel()
    {
        AvaloniaXamlLoader.Load(this);
        // Sin barra de titulo del sistema, el asa para mover la ventana es
        // nuestra: BeginMoveDrag se la pide al gestor de ventanas.
        this.FindControl<Grid>("barraTitulo")!.PointerPressed += (_, e) => BeginMoveDrag(e);
        this.FindControl<Button>("btnCerrar")!.Click += (_, _) => Close();
    }
}
