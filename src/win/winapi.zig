pub usingnamespace @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cDefine("VC_EXTRALEAN", "1");
    @cInclude("windows.h");
});
