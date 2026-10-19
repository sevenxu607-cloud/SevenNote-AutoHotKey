<#
    rebake-backdrop.ps1 -- rebuild a SevenWork image-theme backdrop from a hi-res source.

    Two jobs, and both matter:

    1. FRAMING. cropX / cropW / cropY pick the keep-window out of the source, and
       outRatio matches it to the editor area (measured 0.917 = 443x483 at 100%).
       Cropping tighter is how a portrait is made to fill the pane instead of
       floating in the middle of it with letterbox bars.

    2. TONE. The default here is "leave the source alone": lift 0 disables the
       shadow lift, knee 255 disables the highlight roll-off. A dark source wants
       NO lifting -- it already satisfies the "light text" WCAG line (background
       luma <= 118 for near-white text), and lifting it is exactly what makes a
       picture read as "veiled grey". The roll-off only earns its keep when the
       art has large highlights sitting under the text (Jinx: the face, the hand
       and the white haze, ~20% of pixels above 118):

           V' = V                                            (V <= knee)
           V' = knee + (V - knee) * (hiMax - knee) / (255 - knee)      (V > knee)

       Every channel is then scaled by V' / V -- NOT mixed towards a colour.
       HSV saturation (1 - min/max) is invariant under proportional scaling, so
       the bake brightens or darkens WITHOUT washing out. Mixing towards white
       (the obvious way, and what the first Jinx bake did) cuts saturation about
       in half -- measured 9.6% -> 5.0% -- and that is the "veiled grey" complaint.

    NOTE: keep this file pure ASCII. powershell.exe 5.1 reads .ps1 as system ANSI
    (GBK here); non-ASCII would corrupt it and can swallow the following quote.

    Usage (the house default: full-width crop + gentle highlight roll-off):
        powershell -NoProfile -ExecutionPolicy Bypass -File tools\rebake-backdrop.ps1 `
            -Src "D:\pics\hi-res.png" -Dst "D:\pics\baked.png" `
            -CropX 0.00 -CropW 1.00 -CropY 0.00 -Knee 138 -HiMax 200

    cropW is the ONLY lever on subject size: 0.72 renders the subject at 1.39x
    (a face close-up), 1.00 keeps it at source size with the whole subject in
    frame. Prefer 1.00; never go below 0.90.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Src,
    [Parameter(Mandatory = $true)][string]$Dst,
    [double]$CropX      = 0.0,      # left edge of the keep-window, fraction of source width
    [double]$CropW      = 1.0,      # width of the keep-window, fraction of source width
    [double]$CropY      = 0.0,      # top edge of the keep-window, fraction of source height
    [double]$OutRatio   = 0.917,    # editor-area aspect (width / height), measured 443x483
    [int]$OutWidth      = 2400,
    [double]$Lift       = 0.0,      # shadow lift; 0 = leave the shadows alone (default)
    [double]$Knee       = 255.0,    # highlights above this roll off; 255 = disabled
    [double]$HiMax      = 255.0,    # where 255 lands after the roll-off
    [double]$SatBoost   = 1.0,      # extra saturation on top; 1.0 = keep the source
    [double]$Sharpen    = 0.9,      # unsharp amount
    [int]$SharpenRadius = 4
)

if (-not (Test-Path -LiteralPath $Src)) {
    Write-Error ("source not found: " + $Src)
    exit 1
}

# Guard: the shell is persistent, so a second run in the same session would
# hit "type name already exists" from Add-Type.
#
# !! IMPORTANT !! whenever the C# logic below changes, BUMP THE CLASS NAME
# (RebakeBackdrop -> RebakeBackdrop2 -> ...). Otherwise the persistent shell
# silently keeps the previously compiled type and your edit never runs --
# measured the hard way: a rewritten curve produced byte-identical output that
# matched the OLD formula at every sampled pixel.
if (-not ("RebakeBackdrop2" -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class RebakeBackdrop2 {
    public static string Run(string src, string dst,
                             double cropX, double cropW, double cropY,
                             double outRatio, int outWidth,
                             double lift, double knee, double hiMax,
                             double satBoost, double sharpen, int sharpenRadius) {
        using (var img = Image.FromFile(src)) {
            int sw = img.Width, sh = img.Height;

            // Keep-window: the width decides, the height follows from the editor
            // aspect. Clamped so the window always stays inside the source.
            int cw = (int)Math.Round(sw * cropW);
            int ch = (int)Math.Round(cw / outRatio);
            if (ch > sh) { ch = sh; cw = (int)Math.Round(ch * outRatio); }
            int cx = (int)Math.Round(sw * cropX);
            if (cx + cw > sw) cx = sw - cw;
            if (cx < 0) cx = 0;
            int cy = (int)Math.Round(sh * cropY);
            if (cy + ch > sh) cy = sh - ch;
            if (cy < 0) cy = 0;

            int ow = outWidth, oh = (int)Math.Round(outWidth / outRatio);

            var bmp = new Bitmap(ow, oh, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp)) {
                g.InterpolationMode   = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode     = PixelOffsetMode.HighQuality;
                g.CompositingQuality  = CompositingQuality.HighQuality;
                g.DrawImage(img, new Rectangle(0, 0, ow, oh),
                            new Rectangle(cx, cy, cw, ch), GraphicsUnit.Pixel);
            }

            var rect = new Rectangle(0, 0, ow, oh);
            var data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            int stride = data.Stride, bytes = stride * oh;
            byte[] buf = new byte[bytes];
            Marshal.Copy(data.Scan0, buf, 0, bytes);

            // Tone map in VALUE space -- never by mixing towards a colour.
            //   lift > 0  : V = lift + (255 - lift) * sqrt(V / 255)   (shadow lift)
            //   knee<255 : V = knee + (V - knee) * (hiMax - knee) / (255 - knee)
            //                       (highlight roll-off, for V > knee)
            // Every channel is then scaled by V' / V. HSV saturation (1 - min/max)
            // is invariant under proportional scaling, so the picture is brightened
            // or darkened WITHOUT washing out -- mixing towards white is what makes
            // a bake read as "veiled grey". Default is a no-op: lift 0, knee 255.
            // satBoost is an optional extra push on top (1.0 = keep the source).
            int[] vOut = new int[256];
            for (int i = 0; i < 256; i++) {
                double v = i;
                if (lift > 0)
                    v = lift + (255.0 - lift) * Math.Sqrt(v / 255.0);
                if (knee < 255)
                    v = (v <= knee) ? v : knee + (v - knee) * (hiMax - knee) / (255.0 - knee);
                if (v > 255) v = 255;
                if (v < 0)   v = 0;
                vOut[i] = (int)Math.Round(v);
            }

            for (int y = 0; y < oh; y++) {
                int row = y * stride;
                for (int x = 0; x < ow; x++) {
                    int i = row + x * 4;
                    int b = buf[i], g2 = buf[i + 1], r = buf[i + 2];
                    int V = r; if (g2 > V) V = g2; if (b > V) V = b;
                    if (V == 0) {                       // pure black stays neutral
                        byte nv = (byte)vOut[0];
                        buf[i] = nv; buf[i + 1] = nv; buf[i + 2] = nv;
                        continue;
                    }
                    double s = (double)vOut[V] / V;
                    double bb = b * s, gg = g2 * s, rr = r * s;
                    if (satBoost != 1.0) {
                        double gy = 0.299 * rr + 0.587 * gg + 0.114 * bb;
                        rr = gy + (rr - gy) * satBoost;
                        gg = gy + (gg - gy) * satBoost;
                        bb = gy + (bb - gy) * satBoost;
                    }
                    buf[i] = Clamp(bb); buf[i + 1] = Clamp(gg); buf[i + 2] = Clamp(rr);
                }
            }
            Marshal.Copy(buf, 0, data.Scan0, bytes);
            bmp.UnlockBits(data);

            if (sharpen > 0) Unsharp(bmp, sharpen, sharpenRadius);

            bmp.Save(dst, ImageFormat.Png);
            bmp.Dispose();
            return ow + "x" + oh + "  crop=" + cw + "x" + ch + "@" + cx + "," + cy;
        }
    }

    static byte Clamp(double v) {
        if (v > 255) return 255;
        if (v < 0)   return 0;
        return (byte)Math.Round(v);
    }

    // Separable gaussian blur, then out = in + amount * (in - blur).
    // Only ONE float scratch buffer: pass 2 folds the difference back on the fly
    // (a full second float buffer would cost another 100 MB on a 2400x2775 stage).
    static void Unsharp(Bitmap bmp, double amount, int radius) {
        int w = bmp.Width, h = bmp.Height;
        var rect = new Rectangle(0, 0, w, h);
        var data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int stride = data.Stride, bytes = stride * h;
        byte[] src = new byte[bytes];
        Marshal.Copy(data.Scan0, src, 0, bytes);

        float[] k = GaussKernel(radius);
        int kr = k.Length / 2;
        float[] tmp = new float[bytes];

        for (int y = 0; y < h; y++) {
            int row = y * stride;
            for (int x = 0; x < w; x++) {
                float b = 0, g = 0, r = 0;
                for (int t = -kr; t <= kr; t++) {
                    int sx = x + t; if (sx < 0) sx = 0; if (sx >= w) sx = w - 1;
                    int i = row + sx * 4; float wt = k[t + kr];
                    b += src[i] * wt; g += src[i + 1] * wt; r += src[i + 2] * wt;
                }
                int o = row + x * 4;
                tmp[o] = b; tmp[o + 1] = g; tmp[o + 2] = r;
            }
        }

        for (int y = 0; y < h; y++) {
            int row = y * stride;
            for (int x = 0; x < w; x++) {
                int i = row + x * 4;
                float b = 0, g = 0, r = 0;
                for (int t = -kr; t <= kr; t++) {
                    int sy = y + t; if (sy < 0) sy = 0; if (sy >= h) sy = h - 1;
                    int j = sy * stride + x * 4; float wt = k[t + kr];
                    b += tmp[j] * wt; g += tmp[j + 1] * wt; r += tmp[j + 2] * wt;
                }
                src[i]     = Clamp(src[i]     + amount * (src[i]     - b));
                src[i + 1] = Clamp(src[i + 1] + amount * (src[i + 1] - g));
                src[i + 2] = Clamp(src[i + 2] + amount * (src[i + 2] - r));
            }
        }
        Marshal.Copy(src, 0, data.Scan0, bytes);
        bmp.UnlockBits(data);
    }

    static float[] GaussKernel(int radius) {
        double sigma = radius / 2.0;
        int size = radius * 2 + 1;
        float[] k = new float[size];
        double sum = 0;
        for (int i = 0; i < size; i++) {
            int d = i - radius;
            k[i] = (float)Math.Exp(-(d * d) / (2 * sigma * sigma));
            sum += k[i];
        }
        for (int i = 0; i < size; i++) k[i] = (float)(k[i] / sum);
        return k;
    }
}
'@
}

$info = [RebakeBackdrop2]::Run($Src, $Dst, $CropX, $CropW, $CropY, $OutRatio, $OutWidth, $Lift, $Knee, $HiMax, $SatBoost, $Sharpen, $SharpenRadius)
Write-Host ("baked -> " + $Dst + "   " + $info)
