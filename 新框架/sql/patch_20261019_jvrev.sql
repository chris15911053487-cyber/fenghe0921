-- 2026-10-19 补丁：生成凭单时 AR03 / AR04 下月初自动冲销（参考用户插件代码：OBTF.AutoStorno / StornoDate、OBTD.Remarks）
-- 已部署的库依次执行：本文件（参数），19_jv.sql（F_JV_PLAN 增加冲销列）。
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('JV_REV_TRANSCODES', '0000-00', '9999-99', ',AR03,AR04,', 'LIST', '生成 SAP 凭单时下月初自动冲销的凭证代码：凭单勾选冲销（OBTF.AutoStorno），冲销日期 = 下一账期第一天；同旧 COJZ_01/03 的 U_IsRev（用户 2026-10-19）') WITH PRIMARY KEY
