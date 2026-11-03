#!/usr/bin/env python3
"""Let Wine 11.16's shell32 unzip through SHBindToObject and IFileOperation.

SOLIDWORKS.msi's InstallSpatialIOP custom action binds an IShellFolder to a .zip, then
copies its items with IFileOperation. Wine failed the bind and stubs CopyItem/CopyItems,
so the action fails and the MSI returns 1603.

Needs shell32-zipfolder.c (applied by apply-shell32-zipfolder.py).
Usage: shell32-fileop-copy.py <wine source dir>
"""
import pathlib
import sys

src = pathlib.Path(sys.argv[1]) / "dlls" / "shell32"


def replace(text, old, new):
    if text.count(old) != 1:
        sys.exit(f"expected exactly one match for: {old[:60]!r}")
    return text.replace(old, new)


pidl = (src / "pidl.c").read_text()
pidl = replace(pidl, """HRESULT WINAPI SHBindToObject(IShellFolder *psf, LPCITEMIDLIST pidl, IBindCtx *pbc, REFIID riid, void **ppv)
{
    IShellFolder *psfDesktop = NULL;
    HRESULT hr;
""", """extern HRESULT zipfolder_open(const WCHAR *zip_path, WCHAR *dir, DWORD dir_len);

/* Binds to the extracted contents when pidl is a .zip file and a folder was asked for. */
static HRESULT bind_zip_folder(IShellFolder *psf, LPCITEMIDLIST pidl, IBindCtx *pbc, REFIID riid, void **ppv)
{
    WCHAR path[MAX_PATH], dir[MAX_PATH];
    IShellFolder *desktop;
    LPITEMIDLIST dir_pidl;
    BOOL absolute;
    HRESULT hr;

    if (!IsEqualIID(riid, &IID_IShellFolder) && !IsEqualIID(riid, &IID_IShellFolder2))
        return S_FALSE;
    if (FAILED(SHGetDesktopFolder(&desktop)))
        return S_FALSE;
    absolute = !psf || psf == desktop;
    IShellFolder_Release(desktop);
    if (!absolute || !SHGetPathFromIDListW(pidl, path))
        return S_FALSE;
    if ((hr = zipfolder_open(path, dir, ARRAY_SIZE(dir))) != S_OK)
        return hr;
    if (FAILED(hr = SHParseDisplayName(dir, NULL, &dir_pidl, 0, NULL)))
        return hr;
    hr = SHBindToObject(NULL, dir_pidl, pbc, riid, ppv);
    ILFree(dir_pidl);
    return hr;
}

HRESULT WINAPI SHBindToObject(IShellFolder *psf, LPCITEMIDLIST pidl, IBindCtx *pbc, REFIID riid, void **ppv)
{
    IShellFolder *psfDesktop = NULL;
    HRESULT hr;
""")
pidl = replace(pidl, """    pdump(pidl);

    if (!ppv)
        return E_INVALIDARG;

    *ppv = NULL;

    if (!psf)
    {
        hr = SHGetDesktopFolder(&psfDesktop);
""", """    pdump(pidl);

    if (!ppv)
        return E_INVALIDARG;

    *ppv = NULL;

    if (pidl && (hr = bind_zip_folder(psf, pidl, pbc, riid, ppv)) != S_FALSE)
        return hr;

    if (!psf)
    {
        hr = SHGetDesktopFolder(&psfDesktop);
""")
(src / "pidl.c").write_text(pidl)

item = (src / "shellitem.c").read_text()
item = replace(item, """    FIXME("(%p, %p, %p, %s, %p)\\n", pidl_parent, psf, pidl, debugstr_guid(riid), ppv);

    return E_NOTIMPL;
}

HRESULT WINAPI SHCreateItemInKnownFolder""", """    IShellItem *item;
    HRESULT hr;

    TRACE("(%p, %p, %p, %s, %p)\\n", pidl_parent, psf, pidl, debugstr_guid(riid), ppv);

    *ppv = NULL;
    if (FAILED(hr = SHCreateShellItem(pidl_parent, psf, pidl, &item)))
        return hr;
    hr = IShellItem_QueryInterface(item, riid, ppv);
    IShellItem_Release(item);
    return hr;
}

HRESULT WINAPI SHCreateItemInKnownFolder""")
(src / "shellitem.c").write_text(item)

op = (src / "shlfileop.c").read_text()
op = replace(op, """    COPY_ENGINE_MOVE,
    COPY_ENGINE_REMOVE_DIRECTORY_SILENT,
""", """    COPY_ENGINE_MOVE,
    COPY_ENGINE_REMOVE_DIRECTORY_SILENT,
    COPY_ENGINE_COPY,
""")
op = replace(op, """static HRESULT perform_file_operations(struct file_operation *operation)
{""", """/* Copies one queued item, recursively, into its destination folder. */
static HRESULT copy_engine_copy(struct copy_engine_operation *op)
{
    SHFILEOPSTRUCTW req = {0};
    WCHAR *src = NULL, *folder = NULL, *from = NULL, *to = NULL;
    SIZE_T src_len, to_len;
    HRESULT hr;

    if (FAILED(hr = SHGetNameFromIDList(op->item_pidl, SIGDN_FILESYSPATH, &src)))
        goto done;
    if (FAILED(hr = IShellItem_GetDisplayName(op->folder, SIGDN_FILESYSPATH, &folder)))
        goto done;

    src_len = lstrlenW(src);
    to_len = lstrlenW(folder) + (op->name ? lstrlenW(op->name) + 1 : 0);
    from = calloc(src_len + 2, sizeof(WCHAR));
    to = calloc(to_len + 2, sizeof(WCHAR));
    if (!from || !to)
    {
        hr = E_OUTOFMEMORY;
        goto done;
    }
    lstrcpyW(from, src);
    lstrcpyW(to, folder);
    if (op->name)
    {
        lstrcatW(to, L"\\\\");
        lstrcatW(to, op->name);
    }

    req.wFunc = FO_COPY;
    req.pFrom = from;
    req.pTo = to;
    req.fFlags = FOF_SILENT | FOF_NOCONFIRMATION | FOF_NOCONFIRMMKDIR | FOF_NOERRORUI;
    hr = SHFileOperationW(&req) ? E_FAIL : S_OK;

done:
    CoTaskMemFree(src);
    CoTaskMemFree(folder);
    free(from);
    free(to);
    return hr;
}

static HRESULT perform_file_operations(struct file_operation *operation)
{""")
op = replace(op, """            case COPY_ENGINE_MOVE:
            {
                struct notify_move_item_param p;
""", """            case COPY_ENGINE_COPY:
                hr = copy_engine_copy(op);
                break;

            case COPY_ENGINE_MOVE:
            {
                struct notify_move_item_param p;
""")
op = replace(op, """    FIXME("(%p, %p, %p, %s, %p): stub.\\n", iface, item, folder, debugstr_w(name), sink);

    return E_NOTIMPL;
}

static HRESULT WINAPI file_operation_CopyItems(IFileOperation *iface, IUnknown *items, IShellItem *folder)
{
    FIXME("(%p, %p, %p): stub.\\n", iface, items, folder);

    return E_NOTIMPL;
}
""", """    TRACE("(%p, %p, %p, %s, %p).\\n", iface, item, folder, debugstr_w(name), sink);

    if (!folder || !item)
        return E_INVALIDARG;

    return add_operation(impl_from_IFileOperation(iface), COPY_ENGINE_COPY, item, folder, name, sink, 0, NULL);
}

static HRESULT WINAPI file_operation_CopyItems(IFileOperation *iface, IUnknown *items, IShellItem *folder)
{
    struct file_operation *operation = impl_from_IFileOperation(iface);
    IShellItemArray *array;
    IEnumShellItems *enumerator;
    IShellItem *item;
    HRESULT hr = S_OK;

    TRACE("(%p, %p, %p).\\n", iface, items, folder);

    if (!folder || !items)
        return E_INVALIDARG;

    if (SUCCEEDED(IUnknown_QueryInterface(items, &IID_IShellItemArray, (void **)&array)))
    {
        DWORD count = 0, i;

        IShellItemArray_GetCount(array, &count);
        for (i = 0; SUCCEEDED(hr) && i < count; i++)
        {
            if (FAILED(hr = IShellItemArray_GetItemAt(array, i, &item)))
                break;
            hr = add_operation(operation, COPY_ENGINE_COPY, item, folder, NULL, NULL, 0, NULL);
            IShellItem_Release(item);
        }
        IShellItemArray_Release(array);
        return hr;
    }
    if (SUCCEEDED(IUnknown_QueryInterface(items, &IID_IEnumShellItems, (void **)&enumerator)))
    {
        while (SUCCEEDED(hr) && IEnumShellItems_Next(enumerator, 1, &item, NULL) == S_OK)
        {
            hr = add_operation(operation, COPY_ENGINE_COPY, item, folder, NULL, NULL, 0, NULL);
            IShellItem_Release(item);
        }
        IEnumShellItems_Release(enumerator);
        return hr;
    }
    if (SUCCEEDED(IUnknown_QueryInterface(items, &IID_IShellItem, (void **)&item)))
    {
        hr = add_operation(operation, COPY_ENGINE_COPY, item, folder, NULL, NULL, 0, NULL);
        IShellItem_Release(item);
        return hr;
    }

    FIXME("Unsupported items object %p.\\n", items);
    return E_NOTIMPL;
}
""")
(src / "shlfileop.c").write_text(op)
print("patched", src)
