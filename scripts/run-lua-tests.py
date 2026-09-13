#!/usr/bin/env python3
"""Run local Lua 5.1 tests without installing a router runtime on the host."""
import ctypes
import ctypes.util
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(source):
    executable = shutil.which("lua5.1") or shutil.which("luajit")
    if executable:
        subprocess.run([executable, "-e", source], cwd=ROOT, check=True)
        return
    library = ctypes.util.find_library("luajit-5.1") or ctypes.util.find_library("lua5.1")
    if not library:
        raise SystemExit("Lua 5.1 or LuaJIT is required for behavioral tests")
    lua = ctypes.CDLL(library)
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lua.luaL_loadstring.restype = ctypes.c_int
    lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    lua.lua_pcall.restype = ctypes.c_int
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    if not state:
        raise SystemExit("Cannot allocate Lua state")
    try:
        lua.luaL_openlibs(state)
        status = lua.luaL_loadstring(state, source.encode())
        if status == 0:
            status = lua.lua_pcall(state, 0, 0, 0)
        if status:
            raise SystemExit(lua.lua_tolstring(state, -1, None).decode())
    finally:
        lua.lua_close(state)


if __name__ == "__main__":
    import os
    os.chdir(ROOT)
    if len(sys.argv) > 1:
        for name in sys.argv[1:]:
            path = pathlib.Path(name).resolve()
            if not path.is_relative_to(ROOT) or not path.is_file():
                raise SystemExit("Test must be a file in this checkout")
            run("arg = {}; dofile(" + repr(str(path)) + ")")
    else:
        files = [ROOT / "files/usr/libexec/ddk-console", ROOT / "files/usr/libexec/ddk-v3-worker"]
        files += sorted((ROOT / "files/usr/share/ddk-field-console").glob("*.lua"))
        run("\n".join("assert(loadfile(" + repr(str(path)) + "))" for path in files))
        for path in sorted((ROOT / "scripts").glob("test-*.lua")):
            run("arg = {}; dofile(" + repr(str(path)) + ")")
        print("Lua syntax and behavioral tests passed", flush=True)
