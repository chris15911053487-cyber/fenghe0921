-- 2026-10-14 补丁：计算后校验（Stage = POST，含 BOOT-01）不通过一律阻断，没有警告（用户 2026-10-14）。
-- 已部署的库依次执行：08_precheck.sql（MTC_CA_P_CHECK_PUT：POST 阶段强制 IsBlock='Y'）、10_run_entry.sql（P60 / P75 步骤记 BLOCKED，
-- 运行说明写出阻断的校验项）、本文件（检查项登记同步，与 04_seed / 15_p70_tables 一致）。已有运行的结果不变，重新计算后生效。
UPDATE "MTC_CA_C_CHECK" SET "IsBlock" = 'Y' WHERE "Stage" = 'POST'
