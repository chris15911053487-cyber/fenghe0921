-- =====================================================================
-- 合进 B1 存储过程 SBO_SP_TransactionNotification 的一段（用户 2026-10-28：B1 保存成本参数 / 费用池时校验）
-- 本文件不能单独执行，也不在部署包里。用法：
--   1. 先执行 20_b1cfg_check.sql（建 MTC_CA_V_B1CFG_ISSUES、MTC_CA_P_B1CFG_TN）。
--   2. 备份现有的 SBO_SP_TransactionNotification 定义。
--   3. 把下面这段放在过程末尾、返回结果的 SELECT :error, :error_message FROM DUMMY 之前；不改动已有代码。
--      :error = 0 时才检查，不会覆盖前面已有的报错。变量名 error / error_message 与 B1 标准模板一致，
--      如果你们的 TN 里叫别的名字，按实际改。
--   4. 在 B1 里故意填错一行（如账期写 202611、数字参数填字母）保存，应弹出“[成本配置] …”的提示。
-- 只对新增 / 更新（A / U）生效；删除不检查，删掉默认池等由运行时 PRE-18 阻断。
-- 2026-10-29：计算参数的删除（D）也调用，只检查锁定（U_Locked = Y 的参数不能删）。2026-10-28 已合入旧版这一段的，
--   不改也能拦住锁定参数的修改，只是拦不住删除；要拦删除就把 IF 条件换成下面的新版。
-- 部署不会覆盖 TN：全部部署.sql、deploy.py、build_deploy.py、20_b1cfg_check.sql 都不碰 SBO_SP_TransactionNotification，
--   这一段只能人工合入；以后要去掉也是人工从 TN 里删。
-- 合入后 TN 依赖 MTC_CA_P_B1CFG_TN 和视图 MTC_CA_V_B1CFG_ISSUES：执行 99_drop_all.sql 删掉新框架对象、或重建库时没执行
--   20_b1cfg_check.sql，B1 里保存计算参数（MTC_CA_PARAM）或费用池（MTC_CA_POOL）会报找不到过程而存不进去（其他单据不受影响）。
--   处理：重新执行 20_b1cfg_check.sql；或先把 TN 里这一段注释掉。
-- =====================================================================

-- 成本计算参数 / 费用池保存校验（MTC_CA_，2026-10-28，2026-10-29 加参数锁定；校验口径见视图 MTC_CA_V_B1CFG_ISSUES）
IF :error = 0 AND ((:object_type IN ('MTC_CA_PARAM', 'MTC_CA_POOL') AND :transaction_type IN ('A', 'U'))
                OR (:object_type = 'MTC_CA_PARAM' AND :transaction_type = 'D')) THEN
    CALL "MTC_CA_P_B1CFG_TN"(:object_type, :list_of_cols_val_tab_del, error, error_message);
END IF;
