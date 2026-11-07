-- 2026-10-14 补丁：费用池 / 归集参数改在 B1 维护（P05 同步）、PRE-18 增加校验、数据字典增加 B1 自定义表和“来源”。
-- 已部署的库依次执行：本文件；03_run_procs.sql；07_snapshot_procs.sql；08_precheck.sql；最后 CALL "MTC_CA_P_META_SYNC"()
DO BEGIN
    DECLARE n INT;
    SELECT COUNT(*) INTO n FROM SYS.TABLE_COLUMNS
     WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = 'MTC_CA_M_TABLE' AND COLUMN_NAME = 'Source';
    IF :n = 0 THEN
        EXEC 'ALTER TABLE "MTC_CA_M_TABLE" ADD ("Source" NVARCHAR(1000))';
    END IF;
END
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-18', 'PRE', 180, '费用池配置有效', '正好一个默认池；CLOSE_DIF_POOL 和 C_POOL_SRC / C_POOL_TGT 引用的池都存在；同一产品只属于一个池（Q22）；MatchBy 只能是 GRP / GRPTYPE（Q17）；B1 @MTC_CA_POOL / @MTC_CA_EXPSET 同步没有出错，成本中心在 OPRC 中存在且本期只有一条，匹配的物料组 / 车间类别在 OITB 中存在（2026-10-14）', 'Y', 'S6') WITH PRIMARY KEY
@@
-- 数据字典：快照表（S 层）和配置表的数据来源（用户 2026-10-14，执行台“说明书 → 表与字段”显示、可搜索）
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_ITEM', 'S', 'P20_ITEM：OITM 物料、OITB 物料组（U_ItemGrpType 车间类别）、OITT / ITT1 当前 BOM（算层级），MTC_CA_C_LEVEL_OVR 层级覆盖') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_LINE', 'S', 'P20_LINE：OIVL 库存记录（计价仓库 OWHS.U_IsCost=Y），交易类型取 MTC_VIEW_Document + @U_CIOTRN（59/60 的 U_TrsName）+ @MTC_COST_IOTYPE；采购收货 / 退货 / 发票 OPDN·PDN1、ORPD·RPD1、OPCH·PCH1、ORPC·RPC1；销售退货 RDN1；库存重估 @MTC_OMRV / @MTC_OMRV1；P20_AP 用 S_AP_MOVE 覆盖材料暂估金额') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_ORDER', 'S', 'P20_ORDER：OWOR 生产 / 委外订单（U_OrdType 工单类型）、@MTC_OWOR 返工单（U_OrdType、U_ItemCode、U_PlannedQty）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_ORDER_LINE', 'S', 'P20_ORDER：WOR1 生产订单行、@MTC_WOR1 返工单行（计划用料）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_EXP', 'S', 'P20_EXP：OJDT / JDT1 已过账凭证（人工科目 LAB_EXP、制造费用科目 MFG_EXP_PREFIX 开头，凭证代码在 EXP_JDT_TRANSCODES；取值见 B1 @MTC_CA_EXPSET），@MTC_OMRV / @MTC_OMRV1 库存重估，OWOR / @MTC_OWOR 找订单') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_SUBFEE', 'S', 'P20_SUBFEE：委外加工费收货 OPDN / PDN1（U_BaseType / U_BaseEntry 指向生产收货 IGN1，U_OWORNum 找 OWOR，U_OWORType=MTC_OWOR 时 U_MTCOWORNum 找返工单）、退货 ORPD / RPD1，@MTC_OMRV / @MTC_OMRV1 中 U_BaseType=ProWW 的重估行，@MTC_OWOR 返工单') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_AP_MOVE', 'S', 'P20_AP：采购收货 OPDN / PDN1、采购退货 ORPD / RPD1、应付发票 OPCH / PCH1、应付贷项 ORPC / RPC1（暂估价 U_InitPrice / U_IsPrice / Price），OITM 判断库存物料，@MTC_COST_IOTYPE') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_HOURS', 'S', 'P20_MISC：B1 生产工时 @MTC_COST_TIME（表头 U_FcCode 账期、Canceled）+ @MTC_COST_TIME1（行 U_ItemCode 物料、U_Time 单位工时）；同一物料多行取最大值（PRE-13 报出）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_QCPRICE', 'S', 'P20_MISC：B1 期初单价维护 @MTC_COST_QCPRICE（表头 U_FcCode）+ @MTC_COST_QCPRICE1（行 U_ItemCode、U_Price）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_OPEN', 'S', 'P20_OPEN：上期是承接账期时取 MTC_CA_BOOT_ITEM（旧框架 0301 期末，P_BOOTSTRAP 写入）；上期是新框架账期时读上期结果（待实现）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_ORDER_OPEN', 'S', 'P20_OPEN：上期是承接账期时取 MTC_CA_BOOT_ORDER_MAT（旧框架 CO4011 / ZCP1）；上期是新框架账期时读上期结果（待实现）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_POOL', 'C', 'P05：B1 @MTC_CA_POOL（Code、Name、U_IsDefault、U_Descr）有数据时每次运行前整表覆盖；没有时用种子值') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_POOL_SRC', 'C', 'P05：B1 @MTC_CA_POOL1（U_OcrCode、U_FromFc、U_ToFc）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_POOL_TGT', 'C', 'P05：B1 @MTC_CA_POOL2（U_MatchBy、U_MatchVal、U_WorTypes、U_FromFc、U_ToFc）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_ACCT', 'C', 'MFG_EXP_PREFIX / LAB_EXP 两行由 P05 从 B1 @MTC_CA_EXPSET1 同步（有数据时）；其余科目用种子值') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_PARAM', 'C', 'EXP_JDT_TRANSCODES 由 P05 从 B1 @MTC_CA_EXPSET1 同步，CLOSE_DIF_POOL 取 @MTC_CA_POOL.U_IsCloseDif=Y 的池（有数据时）；其余参数用种子值') WITH PRIMARY KEY
