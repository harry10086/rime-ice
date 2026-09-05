// others/script/rime_cursor.rs
// Native in-process cursor positioning helper for librime-lua on Windows
// Compiled as rime_cursor.dll (cdylib)

use std::thread;
use std::time::Duration;

type LuaState = *mut std::ffi::c_void;

#[link(name = "user32")]
extern "system" {
    fn keybd_event(b_vk: u8, b_scan: u8, dw_flags: u32, dw_extra_info: usize);
}

// Function pointer signatures for Lua 5.4 C API
type LuaToIntegerX = unsafe extern "C" fn(l: LuaState, idx: i32, isnum: *mut i32) -> i64;
type LuaPushCClosure = unsafe extern "C" fn(l: LuaState, fn_ptr: unsafe extern "C" fn(LuaState) -> i32, n: i32);
type LuaCreateTable = unsafe extern "C" fn(l: LuaState, narr: i32, nrec: i32);
type LuaSetField = unsafe extern "C" fn(l: LuaState, idx: i32, k: *const std::os::raw::c_char);
type LuaPushBoolean = unsafe extern "C" fn(l: LuaState, b: i32);

#[link(name = "kernel32")]
extern "system" {
    fn GetModuleHandleA(lp_module_name: *const u8) -> *mut std::ffi::c_void;
    fn GetProcAddress(h_module: *mut std::ffi::c_void, lp_proc_name: *const u8) -> *mut std::ffi::c_void;
}

unsafe fn get_lua_fn<T>(name: &[u8]) -> Option<T> {
    let rime_mod = GetModuleHandleA(b"rime.dll\0".as_ptr());
    if rime_mod.is_null() {
        return None;
    }
    let proc = GetProcAddress(rime_mod, name.as_ptr());
    if proc.is_null() {
        None
    } else {
        Some(std::mem::transmute_copy(&proc))
    }
}

pub unsafe extern "C" fn lua_move_left(l: LuaState) -> i32 {
    let to_int: Option<LuaToIntegerX> = get_lua_fn(b"lua_tointegerx\0");
    let push_bool: Option<LuaPushBoolean> = get_lua_fn(b"lua_pushboolean\0");

    let count = if let Some(f) = to_int {
        f(l, 1, std::ptr::null_mut())
    } else {
        0
    };

    if count > 0 {
        let count_u = count as u32;
        thread::spawn(move || {
            // Wait 100ms for editor/TSF commit & layout to complete before moving caret
            thread::sleep(Duration::from_millis(100));
            for _ in 0..count_u {
                // VK_LEFT = 0x25, scan code = 0x4B, KEYEVENTF_EXTENDEDKEY = 0x0001
                keybd_event(0x25, 0x4B, 0x0001, 0);
                keybd_event(0x25, 0x4B, 0x0001 | 0x0002, 0);
            }
        });
    }

    if let Some(f) = push_bool {
        f(l, 1);
    }
    1
}

#[no_mangle]
pub unsafe extern "C" fn luaopen_rime_cursor(l: LuaState) -> i32 {
    let create_table: Option<LuaCreateTable> = get_lua_fn(b"lua_createtable\0");
    let push_cclosure: Option<LuaPushCClosure> = get_lua_fn(b"lua_pushcclosure\0");
    let set_field: Option<LuaSetField> = get_lua_fn(b"lua_setfield\0");

    if let (Some(ct), Some(pc), Some(sf)) = (create_table, push_cclosure, set_field) {
        ct(l, 0, 1);
        pc(l, lua_move_left, 0);
        sf(l, -2, b"move_left\0".as_ptr() as *const std::os::raw::c_char);
        1
    } else {
        0
    }
}
