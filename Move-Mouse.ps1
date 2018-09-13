
3
01
Function Move-Mouse {
param (
    [uint16] $XY=1,
    [int32] $Secs = 5,
    [boolean] $LoopInfinite = $false,
    [boolean] $DisplayPosition = $false
)

begin {

    $typedef = @"
using System.Runtime.InteropServices;

namespace PoSh
{
    public static class Mouse
    {
        [DllImport("user32.dll")]
        static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);

        private const int MOUSEEVENTF_MOVE = 0x0001;

        public static void MoveTo(`int x, int y)
        {
            mouse_event(MOUSEEVENTF_MOVE, x, y, 0, 0);
        }
    }
}
"@

    Add-Type -TypeDefinition $typedef

}

process {

    if ($LoopInfinite) {
        
        $i = 1
        while ($true) {
            if ($DisplayPosition) { Write-Host "$([System.Windows.Forms.Cursor]::Position.X),$([System.Windows.Forms.Cursor]::Position.Y)" }
    
            if (($i % 2) -eq 0) {
                [PoSh.Mouse]::MoveTo($XY, $XY)
                $i++
            } else {
                [PoSh.Mouse]::MoveTo(-$XY, -$XY)
                $i--
            }

            Start-Sleep -Seconds $Secs
        }
    } else {
        if ($DisplayPosition) { Write-Host "$([System.Windows.Forms.Cursor]::Position.X),$([System.Windows.Forms.Cursor]::Position.Y)" }
    
        [PoSh.Mouse]::MoveTo($XY, $XY)
    }
}

}

Move-Mouse -XY 1 -Secs 5 -LoopInfinite $true -DisplayPosition $false