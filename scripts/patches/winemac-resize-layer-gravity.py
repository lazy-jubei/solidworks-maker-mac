#!/usr/bin/env python3
"""Stop Core Animation stretching the previous frame over the band a live resize exposes.

A Win32 window's frame changes before the application paints the area that the change exposed, so
every layer that tracks the window is momentarily larger than its contents. Core Animation's default
contentsGravity (kCAGravityResize) scales whatever the layer already holds into that band. Measured
against SolidWorks in a Windows guest, that is the opposite of what Windows does: there the newly
exposed strip is either already app content or the window background, never a scaled copy. Over a
sizing drag the repeated scaled copies feed back into each other and read as the staircase ghost
next to the task pane and the doubled status row.

So present each layer's contents at their own size, anchored at the top-left of the layer, and let
the strip the app has not painted yet read as the window background (the colour Wine already
prefills a fresh surface with) instead of the layers' black.

Layers that lag the window by a frame:
  * the CALayerHost mirroring a cross-process GL window's layer;
  * the in-process GL view's CAMetalLayer;
  * the CAMetalLayer a cross-process GL window exports through a CAContext;
  * the GDI surface layer, whose updateLayer crops its image to the layer bounds and then assigns
    it, so the default gravity stretches it the moment the view grew before the surface did.

Set SW_MAC_RESIZE_GRAVITY=0 to get the old stretching behaviour back for comparison.
"""
from pathlib import Path
import sys

path = Path(sys.argv[1]) / 'dlls/winemac.drv/cocoa_window.m'
code = path.read_text()
if 'macdrv_resize_band_background' in code:
    print('Resize layer gravity already applied')
    sys.exit(0)

def replace(text, old, new):
    if text.count(old) != 1:
        raise SystemExit('Expected one match: ' + old[:100])
    return text.replace(old, new)

helpers = '''/* Colour of the strip a resized layer has no contents for yet. Cached because the colour behind it
 * is a dispatch_once constant and this runs on the main thread while layers are being set up. */
static CGColorRef macdrv_resize_band_background(void)
{
    static CGColorRef color;
    if (!color)
    {
        uint32_t bg = macdrv_window_background_color();
        const CGFloat components[4] = { ((bg >> 16) & 0xff) / 255.0, ((bg >> 8) & 0xff) / 255.0,
                                        (bg & 0xff) / 255.0, 1 };
        color = CGColorCreate( CGColorSpaceCreateWithName(kCGColorSpaceSRGB), components );
    }
    return color;
}

/* Draw a layer's contents at their own size instead of scaling them over its bounds. Off with
 * SW_MAC_RESIZE_GRAVITY=0, which restores Core Animation's default kCAGravityResize. */
static BOOL resize_gravity_top_left(void)
{
    static int enabled = -1;
    if (enabled < 0)
    {
        const char *env = getenv( "SW_MAC_RESIZE_GRAVITY" );
        enabled = !env || env[0] != '0';
    }
    return enabled;
}

'''

anchor = '@implementation WineContentView'
code = replace(code, anchor, helpers + anchor)

sites = [
    ('        host.magnificationFilter = kCAFilterNearest;\n'
     '        host.contentsScale = retina_on ? 2.0 : 1.0;\n', '        ', 'host'),
    ('        layer.magnificationFilter = kCAFilterNearest;\n'
     '        layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);\n'
     '        layer.contentsScale = retina_on ? 2.0 : 1.0;\n', '        ', 'layer'),
    ('    offscreen_layer.magnificationFilter = kCAFilterNearest;\n'
     '    offscreen_layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);\n'
     '    offscreen_layer.contentsScale = retina_on ? 2.0 : 1.0;\n', '    ', 'offscreen_layer'),
]
for marker, indent, name in sites:
    code = replace(code, marker, marker + (
        '%(i)sif (resize_gravity_top_left())\n'
        '%(i)s{\n'
        '%(i)s    %(n)s.contentsGravity = kCAGravityTopLeft;\n'
        '%(i)s    %(n)s.backgroundColor = macdrv_resize_band_background();\n'
        '%(i)s}\n') % {'i': indent, 'n': name})

code = replace(code, '''        if (image)
        {
            layer.position = surfaceRect.origin;
            layer.contents = (id)image;
''', '''        if (image)
        {
            layer.position = surfaceRect.origin;
            if (resize_gravity_top_left()) layer.contentsGravity = kCAGravityTopLeft;
            layer.contents = (id)image;
''')

code = replace(code, '#include <dlfcn.h>', '#include <dlfcn.h>\n#include <stdlib.h>')
path.write_text(code)
print('Applied the resize layer gravity fix to cocoa_window.m')
