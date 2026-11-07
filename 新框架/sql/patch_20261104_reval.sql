-- =====================================================================
-- 2026-11-04 库存重估清单（用户 2026-11-04，设计稿 8.8）
-- ① 新表 MTC_CA_R_REVAL_NEED、P55 MTC_CA_P55_REVAL（P50 之后写清单）。
-- ② 新参数 REVAL_DEV_PCT（默认 10）：参数目录里的参数 B1 没有时 PRE-28 阻断，部署后先补 B1（sl_import_costcfg.py --param）。
-- 已部署的库：执行本文件，再执行 14_p50_p60_p65.sql、10_run_entry.sql、18_meta_comments.sql，CALL "MTC_CA_P_META_SYNC"()；
--   更新服务器版执行台。未编译。改前备份 _backup/*_20261104_before_reval.*
-- =====================================================================
CREATE COLUMN TABLE "MTC_CA_R_REVAL_NEED" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "ItemName"   NVARCHAR(200),
    "ItmsGrpCod" NVARCHAR(20),
    "iLevel"     INT,
    "Kind"       NVARCHAR(10)   NOT NULL,       -- APDIF 发票 / 贷项差额造成单价异常 / ZERO 结存数量 > 0、金额 <= 0
    "EndQty"     DECIMAL(19,6),                 -- 期末结存数量
    "EndAmt"     DECIMAL(19,6),                 -- 期末结存金额
    "BaseQty"    DECIMAL(19,6),                 -- 加权数量 = 期初数量 + 本期计价入库数量；调整金额 =（目标单价 − 当前加权价）× 它
    "CurPrice"   DECIMAL(19,6),                 -- 当前加权价
    "ApDif"      DECIMAL(19,6),                 -- 本期应付发票 / 贷项差额（数量为 0 的 18 / 19 行）合计
    "RevalAmt"   DECIMAL(19,6),                 -- 本期已有的重估单（MRV1，计入成本）金额合计
    "DevPct"     DECIMAL(19,6),                 -- 当前加权价偏离剔除差异后单价的比例（%）
    "SuggPrice"  DECIMAL(19,6),                 -- 建议单价（用户可改）
    "SuggSrc"    NVARCHAR(20),                  -- EXDIF 剔除差异后的加权价 / NEW 新框架期末单价 / OLD 旧 0301 单价 / BOOT 期初承接 / LASTPUR 物料主数据最近采购价
    "SuggFc"     NVARCHAR(10),                  -- 建议单价取自哪个账期
    "AdjAmt"     DECIMAL(19,6),                 -- 按建议单价算出的调整金额
    "Reason"     NVARCHAR(500),                 -- 为什么列入清单（中文一句话，页面和 B1 行备注用）
    "NeedDocs"   NVARCHAR(1000),                -- 造成差额的发票 / 贷项单号 Num（每类最多 10 张）
    PRIMARY KEY ("RunId", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_R_REVAL_NEED" IS '库存重估清单（P55，用户 2026-11-04）：结存数量 > 0 且金额 <= 0，或发票 / 贷项差额使加权价偏离 ≥ REVAL_DEV_PCT 的物料；用户在执行台勾选后生成 @MTC_OMRV 重估单（MRV1 / ProCost），再重新计算'
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('REVAL_DEV_PCT', '0000-00', '9999-99', '10', 'DEC', '库存重估清单的偏离阈值（%，含）：本期发票 / 贷项差额使加权价偏离剔除差异后单价达到本值的物料列入“库存重估”页（2026-11-04）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('REVAL_DEV_PCT', 'PARAM', '尾差与校验', 316, '库存重估偏离阈值', 'DEC', NULL, '百分比（含），如 10：发票 / 贷项差额使加权价偏离达到本值的物料列入“库存重估”页') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('RVL-02', 'S13', '库存重估清单', '结存数量 > 0 且金额 <= 0，或本期发票 / 贷项差额使加权价偏离剔除差异后单价 ≥ REVAL_DEV_PCT 的物料列入清单。建议单价：有差额时取剔除差异后的加权价，否则取以前最近一期单价，再取最近采购价。调整金额 =（目标单价 − 当前加权价）×（期初数量 + 计价入库数量）。用户勾选后生成 MRV1 / ProCost 重估单，重新计算后进入加权价，本期出库和期末都按目标单价。', '用户 2026-11-04') WITH PRIMARY KEY
@@
