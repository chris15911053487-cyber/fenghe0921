# server.json 里 HANA 密码的加密（Windows DPAPI，只用 Python 自带的 ctypes；2026-10-19）。
# 加密后写成 "password": "dpapi:<base64>"，只有这台服务器能解开（拷到别的电脑上解不开）。
#   machine 范围（默认）：这台机器上的任何账号都能解开——手工双击 run_server.bat（管理员）和开机任务（服务账号）都能用；
#   user 范围（--user-scope）：只有执行加密的那个 Windows 账号能解开，更严，但必须用服务账号执行加密。
# 用法：python console\dev_server.py --server --set-password [--user-scope]
import ctypes, base64
from ctypes import wintypes

PREFIX = 'dpapi:'
_ENTROPY = b'MTC_CA console'
_UI_FORBIDDEN, _LOCAL_MACHINE = 0x1, 0x4

class _Blob(ctypes.Structure):
    _fields_ = [('cbData', wintypes.DWORD), ('pbData', ctypes.POINTER(ctypes.c_char))]

def _blob(b):
    buf = ctypes.create_string_buffer(b, len(b))
    return _Blob(len(b), ctypes.cast(buf, ctypes.POINTER(ctypes.c_char))), buf

def _out(blob):
    try: return ctypes.string_at(blob.pbData, blob.cbData)
    finally: ctypes.windll.kernel32.LocalFree(blob.pbData)

def protect(text, machine=True):
    src, k1 = _blob(text.encode('utf-8')); ent, k2 = _blob(_ENTROPY); out = _Blob()
    flags = _UI_FORBIDDEN | (_LOCAL_MACHINE if machine else 0)
    if not ctypes.windll.crypt32.CryptProtectData(ctypes.byref(src), 'MTC_CA', ctypes.byref(ent), None, None, flags, ctypes.byref(out)):
        raise OSError('加密失败（Windows 错误 %d）' % ctypes.GetLastError())
    return PREFIX + base64.b64encode(_out(out)).decode('ascii')

def unprotect(value):
    src, k1 = _blob(base64.b64decode(value[len(PREFIX):])); ent, k2 = _blob(_ENTROPY); out = _Blob()
    if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(src), None, ctypes.byref(ent), None, None, _UI_FORBIDDEN, ctypes.byref(out)):
        raise OSError('server.json 里的密码解不开（Windows 错误 %d）：加密是在别的电脑上做的，或用 --user-scope 加密而当前不是同一个 Windows 账号。'
                      '请在这台服务器上重新执行 python console\\dev_server.py --server --set-password' % ctypes.GetLastError())
    return _out(out).decode('utf-8')

def is_protected(v): return isinstance(v, str) and v.startswith(PREFIX)
