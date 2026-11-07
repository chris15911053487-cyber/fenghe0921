-- =====================================================================
-- 2026-11-04 历史委外差异转出（用户 2026-11-04，设计稿 8.9）
-- ① 新表 MTC_CA_WW_HIST；② 科目 WW_HIST_EXP、参数 WW_HIST_OCR：参数目录里的参数 B1 没有时 PRE-28 阻断，部署后先补 B1（sl_import_costcfg.py --param）；
-- ③ B1 @MTC_CA_PARAM 的 COST_TRANSCODES 要加 JZ05，B1 要建凭证代码 JZ05（OTRC），两项由 PRE-30 检查。
-- 已部署的库：执行本文件，再执行 07、08、16、19_jv、19_ww_hist、21_reports、18_meta_comments，CALL "MTC_CA_P_META_SYNC"()；更新服务器版执行台。
-- 未编译。改前备份 _backup/*_20261104_before_wwhist.*
-- =====================================================================
CREATE COLUMN TABLE "MTC_CA_WW_HIST" (
    "OrderType"  NVARCHAR(20)   NOT NULL,
    "OrderEntry" INTEGER        NOT NULL,
    "DocNum"     INTEGER,
    "ItemCode"   NVARCHAR(50),
    "B1Status"   NVARCHAR(1),
    "CloseDate"  DATE,
    "LastFc"     NVARCHAR(10),
    "Amount"     DECIMAL(19,2)  NOT NULL,
    "LoadFc"     NVARCHAR(10),
    "LoadTime"   TIMESTAMP,
    "PlanFc"     NVARCHAR(10),
    "PlanUser"   NVARCHAR(50),
    "PlanTime"   TIMESTAMP,
    "PlanNote"   NVARCHAR(500),
    PRIMARY KEY ("OrderType", "OrderEntry")
)
@@
COMMENT ON TABLE "MTC_CA_WW_HIST" IS '历史委外差异转出清单：承接前已关闭、在产品留在 140801 的委外订单，用户按整张订单选择转出账期（用户 2026-11-04）'
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('WW_HIST_EXP', '0000-00', '9999-99', '510109', '历史委外差异转出（JZ05 借方，用户 2026-11-04）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-30', 'PRE', 300, '历史委外差异转出配置', '本期有计划转出的历史委外订单时：OTRC 有 JZ05、COST_TRANSCODES 含 JZ05、EXP_JDT_TRANSCODES 不含 JZ05、转出科目可记账、成本中心存在（用户 2026-11-04）', 'Y', 'S4') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('COST_TRANSCODES', '0000-00', '9999-99', ',MR01,MR02,YF01,PP01,WW01,IO01,IO02,PP04,PP05,WW03,DN01,DN02,DN03,DN04,AR03,AR04,JZ01,JZ03,JZ04,JZ05,PUR1,PUR2,PUR3,PUR4,PUR5,', 'LIST', '由成本模块生成的凭证代码：PP04 汇总 5101 时不再从总账取这些凭证（新框架自己生成），避免重复') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('WW_HIST_OCR', '0000-00', '9999-99', 'P016', 'STR', '历史委外差异转出（JZ05）借方的成本中心，按它归费用池（用户 2026-11-04）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('WW_HIST_OCR', 'PARAM', '凭证与对账', 445, '历史委外转出成本中心', 'STR', NULL, '成本中心代码，如 P016') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('WW_HIST_EXP', 'ACCT', '凭证与对账', 446, '历史委外转出科目', 'STR', NULL, '科目代码，如 510109') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('WWH-01', 'S4', '历史委外差异转出', '承接前已关闭、在产品留在 140801 的委外订单，由用户按整张订单选择转出账期。金额进费用池分摊给当月完工产品，P70 生成 JZ05：借 WW_HIST_EXP（510109，成本中心 WW_HIST_OCR），140801 记借方红字。本期不计入 140801 差额，下期起进期初。', '用户 2026-11-04') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_M_TABLE" ("TableName", "Layer", "Source") VALUES ('MTC_CA_WW_HIST', 'C', 'MTC_CA_P_WW_HIST_LOAD 从 MTC_COST_0322_OWOR_ZCP 载入；用户在执行台“历史委外差异”页选择转出账期') WITH PRIMARY KEY
@@
