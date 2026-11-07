-- 2026-10-30 补丁：运行出错后能排查（起因 FH100_COST_TEST #14：迭代 49 轮单价越算越大，第 50 轮 P45 金额溢出 SQL 314，
--   出错处理把快照和中间结果全删了，导出里什么都没有）
--   1. P40 每轮末尾提交（13_p40_iter.sql）：出错时只回滚出错那一轮，R_* 停在最后一轮完成时，MTC_CA_RUN_ITER_ITEM 也保留。
--   2. P_RUN 进入 P40 后出错（10_run_entry.sql）：参数 KEEP_NOCONV = Y（默认）时和未收敛一样用 P_RUN_CLEAN 'NCV' 保留本次快照和中间结果，
--      运行状态仍是 FAIL，报错末尾注明“已保留供排查”；N 时删除。P_RUN_CLEAN 'NCV' 同时删掉同运行键下以前保留的失败运行（03_run_procs.sql）。
--   3. P20_MISC 工时全为空的物料取 0（07_snapshot_procs.sql）：原来 MAX(U_Time) 为 NULL 写 MTC_CA_S_HOURS 报 SQL 287（#9–#12），
--      现在由 PRE-14 当作没有工时报出。
--   排查语句：diag_iter_diverge.sql（只读，不进部署包）。
-- 前提：已执行 patch_20261029_noconv.sql（MTC_CA_RUN_ITER_ITEM、P_RUN_CLEAN 'NCV'、KEEP_NOCONV）。
-- 已部署的库依次执行：patch_20261029_noconv.sql（还没执行的话），本文件，03_run_procs.sql，07_snapshot_procs.sql，13_p40_iter.sql，
--   10_run_entry.sql，再 CALL "MTC_CA_P_META_SYNC"()。离线改的，还没编译。
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('KEEP_NOCONV', '0000-00', '9999-99', 'Y', 'STR', '未收敛或迭代及以后出错时保留本次快照和最后一轮中间结果供排查（Y），N = 删除（2026-10-29；出错 2026-10-30）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('KEEP_NOCONV', 'PARAM', '计算控制', 254, '未收敛 / 出错时保留中间结果', 'STR', 'Y,N', 'Y = 未收敛或迭代及以后出错时，保留本次快照和最后一轮中间结果（可在执行台查看、导出排查），下次成功运行时自动删除；N = 删除') WITH PRIMARY KEY
@@
