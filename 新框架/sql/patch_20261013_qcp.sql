-- 2026-10-13 补丁：PRE-23 需要维护期初成本价的物料。已部署的库依次执行：本文件（建表 + 种子），
-- 然后 12_p30_init.sql（新过程 MTC_CA_P10_QCP）、17_p90_tools.sql、10_run_entry.sql；最后 CALL "MTC_CA_P_META_SYNC"()
CREATE COLUMN TABLE "MTC_CA_R_QCP_NEED" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "ItemName"   NVARCHAR(200),
    "ItmsGrpCod" NVARCHAR(20),
    "iLevel"     INT,
    "FirstSeen"  NVARCHAR(1)    NOT NULL,       -- Y = 首次出现：以前各期的新框架结果、期初承接、旧 0301、本期期初都没有这个物料
    "LastFc"     NVARCHAR(10),                  -- 以前最近一次出现的账期
    "NeedTrans"  NVARCHAR(500),                 -- 本期需要按单价计价的交易类型
    "NeedQty"    DECIMAL(19,6),                 -- 这些行的数量绝对值合计
    "SuggPrice"  DECIMAL(19,6),                 -- 建议价（只供参考，不写 B1）
    "SuggSrc"    NVARCHAR(20),                  -- NEW 新框架期末单价 / OLD 旧 0301 单价 / BOOT 期初承接 / LASTPUR 物料主数据最近采购价
    "SuggFc"     NVARCHAR(10),
    PRIMARY KEY ("RunId", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_R_QCP_NEED" IS '需要维护期初成本价的物料（PRE-23）：本期有要按单价计价的变动，计算前却没有任何价格来源；只读清单，不写 @MTC_COST_QCPRICE'
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-23', 'PRE', 230, '需要维护期初成本价的物料', '本期有要按单价计价的变动（出库、其他入库、盘点、无原单退货等），计算前却没有任何价格来源（无期初结存金额、无采购 / 完工 / 形态转换入库、无维护价）；区分首次出现和以前出现过，给出建议价（以前最近一期单价，或最近采购价）。只列清单，不写 @MTC_COST_QCPRICE，在 B1 维护后重新检查（用户 2026-10-13）', 'N', 'S1') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('QCP_PRICED_IN', '0000-00', '9999-99', ',I01,I03,I05,I07,I08,I09,I90,', 'LIST', 'PRE-23：数量为正时算作价格来源的入库交易类型（采购、生产 / 返工 / 委外完工、形态转换入库、期初生产入库）；这些行本身也不需要维护价') WITH PRIMARY KEY
