-- 2026-10-30 补丁：期初价维护清单写明原因和来源单据（用户：清单和生成到 B1 的期初单价维护单行备注里要看得出这个物料为什么要维护）
--   MTC_CA_R_QCP_NEED 加 Reason（原因）、NeedDocs（按交易类型列单号）；新表 MTC_CA_R_QCP_LINE 存逐行来源单据（结果层，阻断时也保留）。
--   执行台“期初价维护”页显示这两列，点行看来源单据；“生成 B1 单据”把原因、建议价来源和单号写进 U_LineMemo。
-- 已部署的库依次执行：本文件，12_p30_init.sql（P10_QCP），18_meta_comments.sql，再 CALL "MTC_CA_P_META_SYNC"()。离线改的，还没编译。
-- 同日追加（用户）：MTC_CA_R_HOURS_NEED 加 PoolNames（费用池代码 + 名称）、NeedOrders（本期有入库的订单），P10_HOURS 写入，
--   生成 B1 工时单时行备注 U_Memo 保留“参考哪个账期的工时单”，再加费用池和订单。
-- 补丁前的运行没有这些列的值，重新“只做检查”一次即可。
ALTER TABLE "MTC_CA_R_QCP_NEED" ADD ("Reason" NVARCHAR(500), "NeedDocs" NVARCHAR(1000))
@@
-- PRE-23 的来源单据行（用户 2026-10-30）：哪些单据行要按单价计价而没有价格。写在结果层，阻断时快照删掉也还在
CREATE COLUMN TABLE "MTC_CA_R_QCP_LINE" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "LineId"     BIGINT         NOT NULL,       -- MTC_CA_S_LINE.LineId
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "ObjType"    NVARCHAR(20),
    "DocEntry"   INTEGER,
    "DocNum"     NVARCHAR(50),
    "LineNum"    INTEGER,
    "DocDate"    DATE,
    "TransCode"  NVARCHAR(10),
    "BusiType"   NVARCHAR(20),
    "WhsCode"    NVARCHAR(8),
    "Qty"        DECIMAL(19,6),
    PRIMARY KEY ("RunId", "LineId")
)
@@
COMMENT ON TABLE "MTC_CA_R_QCP_LINE" IS 'PRE-23 来源单据行：需要维护期初成本价的物料，本期哪些单据行要按单价计价'
@@
ALTER TABLE "MTC_CA_R_HOURS_NEED" ADD ("PoolNames" NVARCHAR(500), "NeedOrders" NVARCHAR(1000))
@@
