-- 2026-10-28 补丁：计算参数改在 B1 平铺表格 @MTC_CA_PARAM 维护（用户 2026-10-28，表结构见 新框架/B1自定义表_费用配置.md 第 2 节）
--   新增参数目录 MTC_CA_C_PARAM_DEF（38 个可在 B1 维护的参数：分类、中文名、类型、可选值、填法）；
--   P05 优先读 @MTC_CA_PARAM，没有时仍读旧 @MTC_CA_EXPSET / 1；费用池补账期格式和起止顺序检查；列表参数“空”只替换单独一项。
-- 已部署的库依次执行：本文件，07_snapshot_procs.sql（P05），18_meta_comments.sql，再 CALL "MTC_CA_P_META_SYNC"()。
-- B1 里建好 @MTC_CA_PARAM 后再执行 20_b1cfg_check.sql（校验视图 + TN 校验过程），TN 片段见 20_b1cfg_tn_snippet.sql。
-- 离线写的，还没编译。
CREATE COLUMN TABLE "MTC_CA_C_PARAM_DEF" (
    "ParamCode"  NVARCHAR(50)   NOT NULL,               -- 参数代码 = B1 @MTC_CA_PARAM.Code（第二段起 代码@起始账期）
    "Target"     NVARCHAR(10)   NOT NULL DEFAULT 'PARAM', -- 同步到哪：PARAM = MTC_CA_C_PARAM，ACCT = MTC_CA_C_ACCT（Usage = 参数代码）
    "Category"   NVARCHAR(20)   NOT NULL,               -- 分类：费用归集 / 计算控制 / 尾差与校验 / 凭证与对账 / 业务口径
    "SortNo"     INT            NOT NULL DEFAULT 0,     -- 显示顺序
    "CnName"     NVARCHAR(100)  NOT NULL,               -- 中文名（B1 Name）
    "DataType"   NVARCHAR(10)   NOT NULL,               -- DEC 数字 / INT 整数 / STR 文字 / LIST 逗号列表 / FC 账期 YYYY-MM / DATE 日期 YYYY-MM-DD
    "Choices"    NVARCHAR(200),                         -- 只能取这些值（逗号分隔），空 = 不限
    "Hint"       NVARCHAR(254),                         -- 填法、可选值、单位（B1 U_Hint）
    PRIMARY KEY ("ParamCode")
)
@@
COMMENT ON TABLE "MTC_CA_C_PARAM_DEF" IS '参数目录：可在 B1 @MTC_CA_PARAM 维护的参数、类型、中文名和填法'
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-18', 'PRE', 180, '费用池配置有效', '正好一个默认池；CLOSE_DIF_POOL 和 C_POOL_SRC / C_POOL_TGT 引用的池都存在；同一产品只属于一个池（Q22）；MatchBy 只能是 GRP / GRPTYPE（Q17）；B1 @MTC_CA_POOL / @MTC_CA_PARAM（没有时旧 @MTC_CA_EXPSET）同步没有出错（2026-10-28 起含保存校验视图 MTC_CA_V_B1CFG_ISSUES 的全部问题：账期格式、起止顺序、账期段重叠、取值类型等），成本中心在 OPRC 中存在且本期只有一条，匹配的物料组 / 车间类别在 OITB 中存在（2026-10-14）', 'Y', 'S6') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_S_EXP', 'S', 'P20_EXP：OJDT / JDT1 已过账凭证（人工科目 LAB_EXP、制造费用科目 MFG_EXP_PREFIX 开头，凭证代码在 EXP_JDT_TRANSCODES；取值见 B1 @MTC_CA_PARAM），@MTC_OMRV / @MTC_OMRV1 库存重估，OWOR / @MTC_OWOR 找订单') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_ACCT', 'C', 'MFG_EXP_PREFIX / LAB_EXP 两行由 P05 从 B1 @MTC_CA_PARAM（没有时读旧 @MTC_CA_EXPSET1）同步（有数据时）；其余科目用种子值') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_PARAM', 'C', 'MTC_CA_C_PARAM_DEF 登记的参数由 P05 从 B1 @MTC_CA_PARAM（没有时读旧 @MTC_CA_EXPSET1）同步，B1 里出现的以 B1 为准；CLOSE_DIF_POOL 取 @MTC_CA_POOL.U_IsCloseDif=Y 的池（有数据时）；其余参数用种子值') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('MFG_EXP_PREFIX', 'ACCT', '费用归集', 110, '制造费用科目前缀', 'STR', NULL, '凭证里以它开头的科目计入制造费用，如 5101') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('LAB_EXP', 'ACCT', '费用归集', 120, '人工费用科目', 'STR', NULL, '科目代码，如 500102') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('EXP_JDT_TRANSCODES', 'PARAM', '费用归集', 130, '计入费用池的凭证代码', 'LIST', NULL, 'OJDT.TransCode，逗号分隔；“空”= 没有凭证代码的手工凭证。如 空,PP03,MR03,MR11,MR12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('SUBFEE_ITEM', 'PARAM', '费用归集', 140, '委外加工费物料', 'STR', NULL, '物料代码，如 X0510001') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('START_FC', 'PARAM', '计算控制', 210, '新框架起始账期', 'FC', NULL, 'YYYY-MM。上线后不要改，会打乱期初承接') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('BOOTSTRAP_FC', 'PARAM', '计算控制', 220, '期初承接账期', 'FC', NULL, 'YYYY-MM，从旧框架该期结果取期初。上线后不要改') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CONV_PRICE', 'PARAM', '计算控制', 230, '收敛标准：单价', 'DEC', NULL, '物料单价两轮之差的上限，如 0.000001；不清楚不要改') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CONV_AMT', 'PARAM', '计算控制', 240, '收敛标准：金额', 'DEC', NULL, '费用池、关单差异两轮之差的上限（元），如 0.01；不清楚不要改') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('MAX_ITER', 'PARAM', '计算控制', 250, '最大迭代轮数', 'INT', NULL, '整数，超过仍不收敛则不写结果，如 50') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('LEVEL_GUARD', 'PARAM', '计算控制', 260, '层级计算保护上限', 'INT', NULL, '整数，防循环引用，不是业务层数，如 30') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('QCP_PRICED_IN', 'PARAM', '计算控制', 270, 'PRE-23 价格来源入库类型', 'LIST', NULL, '交易类型逗号分隔，如 I01,I03,I05,I07,I08,I09,I90') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('LEGACY_INITPRICE_DATE', 'PARAM', '计算控制', 280, '按 U_InitPrice 取成本的截止日', 'DATE', NULL, 'YYYY-MM-DD，该日及以前的交货 / 退货按行上 U_InitPrice 取成本') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('TAIL_MAX', 'PARAM', '尾差与校验', 310, '零库存尾差结转上限', 'DEC', NULL, '元（含）：期末数量 0、金额在 ± 本值以内的结转 640101（JZ04），如 0.02') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('TAIL_WARN', 'PARAM', '尾差与校验', 320, '尾差报警下限', 'DEC', NULL, '元（含）：POST-14 挤进出库行的尾差绝对值达到本值才报，如 0.1') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PRICE_JUMP_PCT', 'PARAM', '尾差与校验', 330, '价格波动报警比例', 'DEC', NULL, '%：POST-14 价格波动 / 期末单价偏离，如 30') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PRICE_JUMP_AMT', 'PARAM', '尾差与校验', 340, '价格波动报警金额', 'DEC', NULL, '元：POST-14 价格波动的影响金额下限，如 100') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CHECK_DTL_MAX', 'PARAM', '尾差与校验', 350, '每项校验保留明细行数', 'INT', NULL, '整数，如 200') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('ACCT_CHECK_BUSITYPES', 'PARAM', '尾差与校验', 360, 'PRE-25 核对科目的业务类型', 'LIST', NULL, '@U_CIOTRN.Code 逗号分隔，如 210') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('COST_TRANSCODES', 'PARAM', '凭证与对账', 410, '成本模块生成的凭证代码', 'LIST', NULL, '凭证代码逗号分隔；要和代码实际生成的一致，不要随意增删') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('JV_REV_TRANSCODES', 'PARAM', '凭证与对账', 420, '凭单下月初自动冲销的凭证代码', 'LIST', NULL, '凭证代码逗号分隔，如 AR03,AR04') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('RECON_BLOCK_ON', 'PARAM', '凭证与对账', 430, '财务对账按哪列差额阻断', 'STR', 'CUR,END', 'CUR 本期差额（期初差额只列示）/ END 期末差额') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('RECON_COSTONLY_AREAS', 'PARAM', '凭证与对账', 440, '只比较成本凭证的对账项', 'LIST', NULL, '可选 STOCK、WIP_PROD、WW_MAT、WW_FEE、GOODS、AP，逗号分隔') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PUR2_REV_ACCTS', 'PARAM', '凭证与对账', 450, 'PUR2 冲回发票凭证的科目', 'LIST', NULL, '科目或前 4 位，逗号分隔，如 1403,1405,1409,220202') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PUR3_REV_ACCTS', 'PARAM', '凭证与对账', 460, 'PUR3 冲回发票凭证的科目', 'LIST', NULL, '科目或前 4 位，逗号分隔，如 140802') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('TB_EXTRA_ACCTS', 'PARAM', '凭证与对账', 470, '科目余额表额外列出的科目', 'LIST', NULL, '科目或科目前缀，逗号分隔，可以为空，如 6602,1122') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('SAMPLE_VAT_RATE', 'PARAM', '凭证与对账', 480, '样品视同销售税率', 'DEC', NULL, '小数，如 0.13') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('SAMPLE_VAT_DIV', 'PARAM', '凭证与对账', 490, '国内样品销项税除数', 'DEC', NULL, '销项税 = 数量 × 平台价 ÷ 本值 × 税率，如 1.13') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('SAMPLE_EXPORT_FACTOR', 'PARAM', '凭证与对账', 500, '国外样品销项税成本倍数', 'DEC', NULL, '销项税 = 成本 × 本值 × 税率，如 1.5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('WW_WORTYPES', 'PARAM', '业务口径', 510, '委外工单的订单类型', 'LIST', NULL, 'U_OrdType 逗号分隔，如 50；改了要同步改费用池分摊范围的订单类型') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('REWORK_WORTYPES', 'PARAM', '业务口径', 520, '返工单的订单类型', 'LIST', NULL, 'U_OrdType 逗号分隔，如 30') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('TRIAL_WORTYPES', 'PARAM', '业务口径', 530, '试打订单的订单类型', 'LIST', NULL, 'U_OrdType 逗号分隔，如 40') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('TRIAL_ISSUE_BUSITYPES', 'PARAM', '业务口径', 540, '试打允许的领料业务类型', 'LIST', NULL, '@U_CIOTRN.Code 逗号分隔，如 307,305') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CONV_IN_BUSITYPE', 'PARAM', '业务口径', 550, '形态转换转入业务类型', 'STR', NULL, '@U_CIOTRN.Code，如 204（I05）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CONV_OUT_BUSITYPE', 'PARAM', '业务口径', 560, '形态转换转出业务类型', 'STR', NULL, '@U_CIOTRN.Code，如 205（O05）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('RETURN_BUSITYPES', 'PARAM', '业务口径', 570, '生产退料业务类型', 'LIST', NULL, '@U_CIOTRN.Code 逗号分隔，如 304') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('SAMPLE_SALTYPES', 'PARAM', '业务口径', 580, '样品销售的业务类型', 'LIST', NULL, '@MTC_SALORDTYPE.U_BusiType 逗号分隔，如 样品销售') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CUST_DOM', 'PARAM', '业务口径', 590, '国内客户的客户类型', 'STR', NULL, '@MTC_SALORDTYPE.U_CustType，如 国内客户') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('CUST_EXP', 'PARAM', '业务口径', 600, '国外客户的客户类型', 'STR', NULL, '@MTC_SALORDTYPE.U_CustType，如 国外客户') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_C_PARAM_DEF', 'C', '种子数据（04_seed.sql）；B1 @MTC_CA_PARAM 的 Name / U_Category / U_DataType / U_Hint 由 sl_import_costcfg.py --param 按它写入') WITH PRIMARY KEY
@@
