# 用本机已装的 HANA ODBC 驱动（HDBODBC）连库的最小 DB-API 适配，只用 Python 自带的 ctypes，不需要 pip 安装任何包。
# 只在 Windows 上用（odbc32.dll）；dev_server.py 在没有 hdbcli 时自动改用它（2026-10-19，服务器上没有 hdbcli、有 HANA Client）。
# 只实现 dev_server.py 用到的部分：connect / cursor / execute(sql, [字符串参数]) / description / fetchone / fetchmany / fetchall /
# commit / rollback / setautocommit / isconnected / close。参数一律按 NVARCHAR 绑定（与 cost_console.ps1 相同）。
# Python 和驱动的位数要一致：64 位 Python 用 HDBODBC，32 位 Python 用 HDBODBC32（自动选择）。
import ctypes, struct, decimal, datetime, threading
from ctypes import c_void_p, c_short, c_ushort, c_int, c_ssize_t, c_size_t, byref, POINTER

SQL_HANDLE_ENV, SQL_HANDLE_DBC, SQL_HANDLE_STMT = 1, 2, 3
SQL_SUCCESS, SQL_SUCCESS_WITH_INFO, SQL_NO_DATA, SQL_NTS, SQL_NULL_DATA, SQL_NO_TOTAL = 0, 1, 100, -3, -1, -4
SQL_C_WCHAR, SQL_C_BINARY, SQL_WVARCHAR = -8, -2, -9
SQL_ATTR_ODBC_VERSION, SQL_ATTR_AUTOCOMMIT, SQL_ATTR_CONNECTION_DEAD = 200, 102, 1209
SQL_CLOSE, SQL_RESET_PARAMS = 0, 3
INT_TYPES = {4, 5, -6, -5, -7}            # INTEGER SMALLINT TINYINT BIGINT BIT
DEC_TYPES = {2, 3}                        # NUMERIC DECIMAL
FLT_TYPES = {6, 7, 8}                     # FLOAT REAL DOUBLE
DATE_TYPES, TS_TYPES = {9, 91}, {11, 93}
BIN_TYPES = {-2, -3, -4}

DRIVER = 'HDBODBC' if struct.calcsize('P') == 8 else 'HDBODBC32'
DEAD_STATES = ('08S01', '08003', '08007', '08001')

class Error(Exception): pass

_lib = None; _env = None; _lock = threading.Lock()

def _api():
    global _lib, _env
    with _lock:
        if _lib: return _lib
        L = ctypes.windll.odbc32
        H, R = c_void_p, c_short
        sig = {
            'SQLAllocHandle': [c_short, H, POINTER(H)],
            'SQLFreeHandle': [c_short, H],
            'SQLSetEnvAttr': [H, c_int, c_void_p, c_int],
            'SQLDriverConnectW': [H, c_void_p, ctypes.c_wchar_p, c_short, ctypes.c_wchar_p, c_short, POINTER(c_short), c_ushort],
            'SQLDisconnect': [H],
            'SQLSetConnectAttrW': [H, c_int, c_void_p, c_int],
            'SQLGetConnectAttrW': [H, c_int, c_void_p, c_int, POINTER(c_int)],
            'SQLEndTran': [c_short, H, c_short],
            'SQLGetDiagRecW': [c_short, H, c_short, ctypes.c_wchar_p, POINTER(c_int), ctypes.c_wchar_p, c_short, POINTER(c_short)],
            'SQLExecDirectW': [H, ctypes.c_wchar_p, c_int],
            'SQLFreeStmt': [H, c_ushort],
            'SQLBindParameter': [H, c_ushort, c_short, c_short, c_short, c_size_t, c_short, c_void_p, c_ssize_t, POINTER(c_ssize_t)],
            'SQLNumResultCols': [H, POINTER(c_short)],
            'SQLDescribeColW': [H, c_ushort, ctypes.c_wchar_p, c_short, POINTER(c_short), POINTER(c_short), POINTER(c_size_t), POINTER(c_short), POINTER(c_short)],
            'SQLFetch': [H],
            'SQLGetData': [H, c_ushort, c_short, c_void_p, c_ssize_t, POINTER(c_ssize_t)],
        }
        for n, a in sig.items():
            f = getattr(L, n); f.argtypes = a; f.restype = R
        env = c_void_p()
        _chk(L.SQLAllocHandle(SQL_HANDLE_ENV, None, byref(env)), None, None, L)
        L.SQLSetEnvAttr(env, SQL_ATTR_ODBC_VERSION, c_void_p(3), 0)
        _lib, _env = L, env
        return L

def _diag(L, htype, h):
    out = []
    for i in range(1, 6):
        st = ctypes.create_unicode_buffer(6); nat = c_int(); msg = ctypes.create_unicode_buffer(2048); ln = c_short()
        if L.SQLGetDiagRecW(htype, h, i, st, byref(nat), msg, 2048, byref(ln)) not in (SQL_SUCCESS, SQL_SUCCESS_WITH_INFO): break
        out.append((st.value, msg.value))
    return out

def _chk(rc, htype, h, L=None):
    if rc in (SQL_SUCCESS, SQL_SUCCESS_WITH_INFO, SQL_NO_DATA): return rc
    d = _diag(L or _lib, htype, h) if h else []
    e = Error('; '.join('[%s] %s' % x for x in d) or 'ODBC 调用失败（返回码 %s）' % rc)
    e.sqlstate = d[0][0] if d else ''
    raise e

def conn_str(conf, schema=None):
    # conf 与 server.json 的 hana 段相同：odbc（整串）/ dsn / key（hdbuserstore）/ address+port+databaseName+user+password，可选 driver
    if conf.get('odbc'): s = conf['odbc']
    else:
        q = lambda v: '{' + str(v).replace('}', '}}') + '}'
        if conf.get('dsn'): s = 'DSN=%s' % q(conf['dsn'])
        else:
            s = 'DRIVER={%s};SERVERNODE=%s' % (conf.get('driver') or DRIVER, '@' + conf['key'] if conf.get('key') else '%s:%s' % (conf['address'], conf['port']))
            if conf.get('databaseName') and not conf.get('key'): s += ';DATABASENAME=' + q(conf['databaseName'])
        if conf.get('user') and not conf.get('key'): s += ';UID=' + q(conf['user'])
        if conf.get('password') and not conf.get('key'): s += ';PWD=' + q(conf['password'])
    if schema: s += ';CURRENTSCHEMA=' + schema
    return s

def connect(cs):
    L = _api()
    h = c_void_p()
    _chk(L.SQLAllocHandle(SQL_HANDLE_DBC, _env, byref(h)), SQL_HANDLE_ENV, _env)
    out = ctypes.create_unicode_buffer(2048); ln = c_short()
    try:
        _chk(L.SQLDriverConnectW(h, None, cs, SQL_NTS, out, 2048, byref(ln), 0), SQL_HANDLE_DBC, h)
    except Error as e:
        L.SQLFreeHandle(SQL_HANDLE_DBC, h)
        if e.sqlstate == 'IM002':
            raise Error('%s。找不到 HANA ODBC 驱动：Python 是 %d 位，需要同样位数的 HANA Client（驱动名 %s）；'
                        '只有 32 位 HANA Client 时请用 32 位 Python，或在 server.json 的 hana 段写 "driver" 指定驱动名。'
                        % (e, struct.calcsize('P') * 8, DRIVER))
        raise
    return Connection(h)

class Connection:
    def __init__(self, h): self.h = h; self.dead = False
    def cursor(self): return Cursor(self)
    def setautocommit(self, on):
        _chk(_lib.SQLSetConnectAttrW(self.h, SQL_ATTR_AUTOCOMMIT, c_void_p(1 if on else 0), -5), SQL_HANDLE_DBC, self.h)
    def commit(self): _chk(_lib.SQLEndTran(SQL_HANDLE_DBC, self.h, 0), SQL_HANDLE_DBC, self.h)
    def rollback(self): _chk(_lib.SQLEndTran(SQL_HANDLE_DBC, self.h, 1), SQL_HANDLE_DBC, self.h)
    def isconnected(self):
        if self.dead or not self.h: return False
        v = c_int(0)
        if _lib.SQLGetConnectAttrW(self.h, SQL_ATTR_CONNECTION_DEAD, byref(v), 4, None) in (SQL_SUCCESS, SQL_SUCCESS_WITH_INFO):
            return v.value != 1
        return True
    def close(self):
        if self.h:
            _lib.SQLDisconnect(self.h); _lib.SQLFreeHandle(SQL_HANDLE_DBC, self.h); self.h = None

class Cursor:
    def __init__(self, conn):
        self.conn = conn; self.h = c_void_p(); self.description = None; self._types = []
        _chk(_lib.SQLAllocHandle(SQL_HANDLE_STMT, conn.h, byref(self.h)), SQL_HANDLE_DBC, conn.h)

    def _call(self, rc):
        try: return _chk(rc, SQL_HANDLE_STMT, self.h)
        except Error as e:
            if e.sqlstate in DEAD_STATES: self.conn.dead = True
            raise

    def execute(self, sql, params=()):
        L = _lib
        L.SQLFreeStmt(self.h, SQL_CLOSE); L.SQLFreeStmt(self.h, SQL_RESET_PARAMS)
        keep = []   # 参数缓冲区在执行完之前不能被回收
        for i, p in enumerate(params or (), 1):
            s = '' if p is None else str(p)
            n = max(len(s.encode('utf-16-le')) // 2, 1)
            buf = ctypes.create_unicode_buffer(s, n + 1); ind = c_ssize_t(SQL_NULL_DATA if p is None else SQL_NTS)
            keep.append((buf, ind))
            self._call(L.SQLBindParameter(self.h, i, 1, SQL_C_WCHAR, SQL_WVARCHAR, n, 0, buf, ctypes.sizeof(buf), byref(ind)))
        self._call(L.SQLExecDirectW(self.h, sql, SQL_NTS))
        nc = c_short(); self._call(L.SQLNumResultCols(self.h, byref(nc)))
        if nc.value <= 0:
            self.description = None; self._types = []; return self
        desc = []; types = []
        for i in range(1, nc.value + 1):
            nm = ctypes.create_unicode_buffer(512); nl = c_short(); ty = c_short(); sz = c_size_t(); dd = c_short(); nu = c_short()
            self._call(L.SQLDescribeColW(self.h, i, nm, 512, byref(nl), byref(ty), byref(sz), byref(dd), byref(nu)))
            desc.append((nm.value, ty.value, None, sz.value, sz.value, dd.value, bool(nu.value))); types.append(ty.value)
        self.description = desc; self._types = types
        return self

    def _get(self, i, ty):
        L = _lib; ind = c_ssize_t()
        if ty in BIN_TYPES:
            buf = ctypes.create_string_buffer(8192); parts = []
            while True:
                rc = self._call(L.SQLGetData(self.h, i, SQL_C_BINARY, buf, 8192, byref(ind)))
                if rc == SQL_NO_DATA: break
                if ind.value == SQL_NULL_DATA: return None
                parts.append(buf.raw[:8192 if ind.value in (SQL_NO_TOTAL,) or ind.value > 8192 else ind.value])
                if rc == SQL_SUCCESS: break
            return b''.join(parts)
        buf = ctypes.create_unicode_buffer(4096); parts = []
        while True:
            rc = self._call(L.SQLGetData(self.h, i, SQL_C_WCHAR, buf, ctypes.sizeof(buf), byref(ind)))
            if rc == SQL_NO_DATA: break
            if ind.value == SQL_NULL_DATA: return None
            parts.append(buf.value)
            if rc == SQL_SUCCESS: break
        s = ''.join(parts)
        try:
            if ty in INT_TYPES: return int(s)
            if ty in DEC_TYPES: return decimal.Decimal(s)
            if ty in FLT_TYPES: return float(s)
            if ty in DATE_TYPES: return datetime.datetime.strptime(s[:10], '%Y-%m-%d').date()
            if ty in TS_TYPES: return datetime.datetime.strptime(s[:19], '%Y-%m-%d %H:%M:%S')
        except ValueError: pass
        return s

    def fetchone(self):
        if not self.description: return None
        rc = self._call(_lib.SQLFetch(self.h))
        if rc == SQL_NO_DATA: return None
        return tuple(self._get(i, t) for i, t in enumerate(self._types, 1))

    def fetchmany(self, n):
        out = []
        while len(out) < n:
            r = self.fetchone()
            if r is None: break
            out.append(r)
        return out

    def fetchall(self):
        out = []
        while True:
            r = self.fetchone()
            if r is None: return out
            out.append(r)

    def close(self):
        if self.h:
            _lib.SQLFreeHandle(SQL_HANDLE_STMT, self.h); self.h = None
