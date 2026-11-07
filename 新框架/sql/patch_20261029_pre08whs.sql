-- 2026-10-29 补丁：PRE-08（不计价仓库中的生产和采购）可按参数排除仓库（用户：警告太多）
--   新参数 PRE08_EXCL_WHS（列表，仓库代码，默认为空 = 不排除）；B1 @MTC_CA_PARAM 加一行即可，如 Code = PRE08_EXCL_WHS、取值 S300,WX01。
--   只影响 PRE-08 的警告明细，不影响计算。
-- 已部署的库依次执行：本文件，08_precheck.sql（P10），再 CALL "MTC_CA_P_META_SYNC"()。离线改的，还没编译。
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('PRE08_EXCL_WHS', '0000-00', '9999-99', ',', 'LIST', 'PRE-08：不计价仓库中这些仓库（OWHS.WhsCode，逗号分隔）的采购、订单领料和完工不报；只影响警告，不影响计算（用户 2026-10-29）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PRE08_EXCL_WHS', 'PARAM', '尾差与校验', 370, 'PRE-08 不报的不计价仓库', 'LIST', NULL, '仓库代码逗号分隔，可以为空，如 S300,WX01') WITH PRIMARY KEY
@@
UPDATE "MTC_CA_C_CHECK" SET "Purpose" = 'U_IsCost 不是 Y 的仓库中有订单领料、完工或采购入库，提示核对仓库设置；参数 PRE08_EXCL_WHS 列出的仓库不报（用户 2026-10-29）' WHERE "CheckId" = 'PRE-08'
@@
