#!/usr/bin/env python3
"""Opt-in GDI presentation of GL for Wine 11.16's Mac driver.
Adapted from GeanyBezna/winemac-offscreen-children v0.2.0 (LGPL-2.1+).
Unlike that patch, this includes overlapping siblings at each ancestor, and is
only enabled with SW_OPENGL_GDI=1. Keeps CAD window geometry unchanged.
"""
from pathlib import Path
import sys
root = Path(sys.argv[1]) / 'dlls/winemac.drv'
changes = {}
def replace(code, old, new):
    if code.count(old) != 1:
        raise SystemExit('Expected one match: ' + old[:100])
    return code.replace(old, new)
if 'SW_OPENGL_GDI' in (root/'opengl.c').read_text():
    print('OpenGL GDI patch already applied'); sys.exit(0)
s = (root/'macdrv.h').read_text()
s = replace(s, '    macdrv_metal_swapchain  metal_swapchain;\n', '''    macdrv_metal_swapchain  metal_swapchain;
    BOOL                    gdi_present;
    BOOL                    view_hidden;
    BOOL                    offscreen_valid;
    void                   *offscreen_bits;
    size_t                  offscreen_size;
    int                     offscreen_width, offscreen_height;
''')
changes['macdrv.h'] = s
s = (root/'window.c').read_text()
s = replace(s, '    if (surface->metal_swapchain) macdrv_destroy_swapchain(surface->metal_swapchain);', '    free(surface->offscreen_bits);\n    if (surface->metal_swapchain) macdrv_destroy_swapchain(surface->metal_swapchain);')
helper = '''/* Preserve GDI children and all higher sibling windows, including those of
   ancestors (the FeatureManager is a sibling of the viewport's frame). */
static void clip_gdi_overlays(HWND hwnd, HDC hdc)
{
    UINT dpi = NtUserGetWinMonitorDpi(hwnd, MDT_RAW_DPI);
    HWND child, current, sibling;
    RECT rect;
    for (child = NtUserGetWindowRelative(hwnd, GW_CHILD); child;
         child = NtUserGetWindowRelative(child, GW_HWNDNEXT))
    {
        if (!NtUserIsWindowVisible(child) || !NtUserGetWindowRect(child, &rect, dpi)) continue;
        NtUserMapWindowPoints(0, hwnd, (POINT *)&rect, 2, dpi);
        NtGdiExcludeClipRect(hdc, rect.left, rect.top, rect.right, rect.bottom);
    }
    for (current = hwnd; current && current != NtUserGetAncestor(hwnd, GA_ROOT);
         current = NtUserGetAncestor(current, GA_PARENT))
    {
        for (sibling = NtUserGetWindowRelative(current, GW_HWNDPREV); sibling;
             sibling = NtUserGetWindowRelative(sibling, GW_HWNDPREV))
        {
            if (!NtUserIsWindowVisible(sibling) || !NtUserGetWindowRect(sibling, &rect, dpi)) continue;
            NtUserMapWindowPoints(0, hwnd, (POINT *)&rect, 2, dpi);
            NtGdiExcludeClipRect(hdc, rect.left, rect.top, rect.right, rect.bottom);
        }
    }
}

static void present_gdi_frame(struct macdrv_client_surface *surface, HDC hdc)
{
    BITMAPINFO info = {0};
    NtGdiSaveDC(hdc);
    clip_gdi_overlays(surface->client.hwnd, hdc);
    info.bmiHeader.biSize = sizeof(info.bmiHeader);
    info.bmiHeader.biWidth = surface->offscreen_width;
    info.bmiHeader.biHeight = surface->offscreen_height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    NtGdiSetDIBitsToDeviceInternal(hdc, 0, 0, surface->offscreen_width, surface->offscreen_height, 0, 0, 0,
        surface->offscreen_height, surface->offscreen_bits, &info, DIB_RGB_COLORS,
        (size_t)surface->offscreen_width * surface->offscreen_height * 4, sizeof(info), FALSE, NULL);
    NtGdiRestoreDC(hdc, -1);
}

'''
s = replace(s, 'static void macdrv_client_surface_update(struct client_surface *client)', helper+'static void macdrv_client_surface_update(struct client_surface *client)')
s = replace(s, '    macdrv_set_view_frame(surface->cocoa_view, cgrect_from_rect(client->monitor_rect));', '''    if (surface->gdi_present) InterlockedExchange(&client->offscreen, TRUE);
    macdrv_set_view_frame(surface->cocoa_view, cgrect_from_rect(client->monitor_rect));''')
a = s.index('static void macdrv_client_surface_present('); b = s.index('static const struct client_surface_funcs',a)
s = s[:a]+'''static void macdrv_client_surface_present(struct client_surface *client, HDC hdc)
{
    struct macdrv_client_surface *surface = impl_from_client_surface(client);
    struct macdrv_win_data *data;
    BOOL hidden = hdc && surface->offscreen_valid;
    if (hidden) present_gdi_frame(surface, hdc);
    surface->offscreen_valid = FALSE;
    if (!(data = get_win_data(client->hwnd))) return;
    if (data->client_view != surface->cocoa_view)
    {
        if (data->client_view) macdrv_set_view_hidden(data->client_view, TRUE);
        data->client_view = surface->cocoa_view;
        surface->view_hidden = !hidden;
    }
    if (surface->view_hidden != hidden)
    {
        macdrv_set_view_hidden(surface->cocoa_view, hidden);
        surface->view_hidden = hidden;
    }
    release_win_data(data);
}

''' + s[b:]
changes['window.c'] = s
s = (root/'opengl.c').read_text()
s = replace(s, 'static PFN_glGetIntegerv pglGetIntegerv;', '''static PFN_glGetIntegerv pglGetIntegerv;
static void (*pglBindBuffer)(GLenum, GLuint);
static void (*pglBindFramebuffer)(GLenum, GLuint);
static void (*pglPixelStorei)(GLenum, GLint);
static void (*pglReadBuffer)(GLenum);''')
s = replace(s, '    LOAD_FUNCPTR(glGetIntegerv);', '''    LOAD_FUNCPTR(glGetIntegerv);
    LOAD_FUNCPTR(glBindBuffer);
    LOAD_FUNCPTR(glBindFramebuffer);
    LOAD_FUNCPTR(glPixelStorei);
    LOAD_FUNCPTR(glReadBuffer);''')
s = s.replace('    *drawable = &gl->base;', '''    {
        const char *enabled = getenv("SW_OPENGL_GDI");
        struct macdrv_client_surface *surface = impl_from_client_surface(client);
        surface->gdi_present = enabled && !strcmp(enabled, "1");
    }
    *drawable = &gl->base;''', 1)
# Reuse the reviewed state-saving readback from the upstream patch.
patch = (Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).with_name('winemac-offscreen-upstream.patch')).read_text()
a = patch.index('+static void read_offscreen_frame('); b = patch.index('\n static BOOL macdrv_surface_swap', a)
lines = patch[a:b].splitlines()
readback = '\n'.join(line[1:] for line in lines if line.startswith('+')) + '}\n\n'
s = replace(s, 'static void macdrv_surface_flush(struct opengl_drawable *base, UINT flags)', readback+'static void macdrv_surface_flush(struct opengl_drawable *base, UINT flags)')
s = replace(s, '''        macdrv_flush_opengl_context(context->context);
        client_surface_present(base->client);''', '''        if (client->gdi_present) read_offscreen_frame(client, base->doublebuffer);
        macdrv_flush_opengl_context(context->context);
        client_surface_present(base->client);''')
s = replace(s, """        make_context_current(context, context->read_view == client->cocoa_view);
        macdrv_flush_opengl_context(context->context);""", """        make_context_current(context, context->read_view == client->cocoa_view);
        if (client->gdi_present) read_offscreen_frame(client, base->doublebuffer);
        macdrv_flush_opengl_context(context->context);""")
changes['opengl.c'] = s
for name, code in changes.items():
    p = root/name
    backup = p.with_suffix(p.suffix+'.before-gdi')
    if not backup.exists(): backup.write_bytes(p.read_bytes())
    p.write_text(code)
    print('Patched', name)
