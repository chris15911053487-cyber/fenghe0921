-- 2026-11-01 补丁：PRE-28 B1 计算参数缺项（用户：参数目录里要维护的参数，B1 @MTC_CA_PARAM 本账期没有就先阻断，为保证准确）
--   原来 P05 对 B1 里没有的参数静默沿用新框架种子值；现在 P10 计算前检查按 B1 原样快照 MTC_CA_C_PARAM_B1 逐个核对参数目录
--   MTC_CA_C_PARAM_DEF，没有适用于本账期的行就阻断（只做检查也会报）。取值格式仍由 PRE-18 管。
-- 已部署的库依次执行：本文件，08_precheck.sql（P10），再 CALL "MTC_CA_P_META_SYNC"()。离线写的，还没编译。
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-28', 'PRE', 280, 'B1 计算参数缺项', '参数目录 MTC_CA_C_PARAM_DEF 中的参数，B1 @MTC_CA_PARAM 没有适用于本账期的行：不阻断时会静默沿用新框架种子值。按 B1 原样快照 MTC_CA_C_PARAM_B1（P05 同步时刷新）判断，只看有没有行，取值格式由 PRE-18 管（用户 2026-11-01 阻断，为保证准确）', 'Y', 'S6') WITH PRIMARY KEY
