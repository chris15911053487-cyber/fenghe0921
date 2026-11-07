# 打包成本执行台服务器版：生成 部署包/执行台服务器/（+ 同名 .zip），拷到 Windows 服务器上解压即用。
# 只带运行需要的文件；不带 server.json、logs/、audit/、_backup/、连接文件和脱敏密钥。
# 用法：python3 tools/console/pack_server.py
import os, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(ROOT, '部署包', '执行台服务器')
if os.path.exists(OUT): shutil.rmtree(OUT)
os.makedirs(os.path.join(OUT, 'console'))
for f in ('dev_server.py', 'hana_odbc.py', 'dpapi.py', 'index.html', 'login.html', 'actions.json', 'server.example.json'):
    shutil.copy2(os.path.join(HERE, f), os.path.join(OUT, 'console', f))
for f in ('run_server.bat', 'install_service.bat', 'install_service.ps1'):
    shutil.copy2(os.path.join(HERE, 'server', f), os.path.join(OUT, f))
src = open(os.path.join(ROOT, 'tools', 'README.md'), encoding='utf-8').read()
a = src.index('## 服务器部署'); b = src.find('\n## ', a + 5)
open(os.path.join(OUT, 'README.md'), 'w', encoding='utf-8').write('# 成本执行台 · 服务器版\n\n' + src[a:b if b > 0 else None].replace('## 服务器部署', '', 1).strip() + '\n')
shutil.make_archive(OUT, 'zip', os.path.dirname(OUT), os.path.basename(OUT))
print('已生成 %s 和 %s.zip' % (OUT, OUT))
