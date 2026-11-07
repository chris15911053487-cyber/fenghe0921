-- =====================================================================
-- 新成本框架 第 2 期：计算结果表（设计稿 3.5）
-- 四项成本要素贯穿全流程：Mat 材料、Mfg 制造费用、Lab 人工、Sub 委外加工费；金额 = 四项之和。
-- 迭代过程中原地更新，收敛后在 P50 定稿；未收敛 / 失败时由 MTC_CA_P_RUN_CLEAN 删除本次结果。
-- =====================================================================
CREATE COLUMN TABLE "MTC_CA_R_LINE" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "LineId"     BIGINT         NOT NULL,       -- = S_LINE.LineId
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "TransCode"  NVARCHAR(10),
    "Qty"        DECIMAL(19,6)  NOT NULL,
    "Cat"        NVARCHAR(10)   NOT NULL,       -- 定价类别，见 MTC_CA_P30_INIT
    "InVal"      NVARCHAR(1)    NOT NULL DEFAULT 'N',  -- Y = 计入物料加权单价的入库
    "OrderType"  NVARCHAR(20),
    "OrderEntry" INTEGER,
    "PoolCode"   NVARCHAR(20),                  -- 公摊材料行归入的费用池
    "IsShared"   NVARCHAR(1)    NOT NULL DEFAULT 'N',
    "MatAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "MfgAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "LabAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "SubAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "Amount"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "Price"      DECIMAL(19,6),
    "PriceSrc"   NVARCHAR(200),
    "RuleId"     NVARCHAR(20),
    "Iter"       INT,
    PRIMARY KEY ("RunId", "LineId")
)
@@
COMMENT ON TABLE "MTC_CA_R_LINE" IS '单据行成本：一行 = 一条库存变动（对应 S_LINE），含四项金额、价格来源、规则编号'
@@
CREATE INDEX "MTC_CA_R_LINE_IX1" ON "MTC_CA_R_LINE" ("RunId", "ItemCode")
@@
CREATE INDEX "MTC_CA_R_LINE_IX2" ON "MTC_CA_R_LINE" ("RunId", "OrderType", "OrderEntry")
@@
CREATE COLUMN TABLE "MTC_CA_R_ITEM" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "iLevel"     INT            NOT NULL,       -- 计算用层级（-1 的物料放在最高层之后）
    "OpenQty"    DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "OpenMat"    DECIMAL(19,6)  NOT NULL DEFAULT 0, "OpenMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "OpenLab"    DECIMAL(19,6)  NOT NULL DEFAULT 0, "OpenSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "PMat"       DECIMAL(19,6)  NOT NULL DEFAULT 0, "PMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,   -- 当前单价（四项）
    "PLab"       DECIMAL(19,6)  NOT NULL DEFAULT 0, "PSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "LastPMat"   DECIMAL(19,6)  NOT NULL DEFAULT 0, "LastPMfg" DECIMAL(19,6) NOT NULL DEFAULT 0, -- 上一轮单价
    "LastPLab"   DECIMAL(19,6)  NOT NULL DEFAULT 0, "LastPSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "PriceSrc"   NVARCHAR(20),                  -- WAVG 本期加权 / QCPRICE 维护价兜底 / OPEN 期初单价 / ZERO 无价
    "InQty"      DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "InMat"      DECIMAL(19,6)  NOT NULL DEFAULT 0, "InMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "InLab"      DECIMAL(19,6)  NOT NULL DEFAULT 0, "InSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "OutQty"     DECIMAL(19,6)  NOT NULL DEFAULT 0,   -- 出库为负
    "OutMat"     DECIMAL(19,6)  NOT NULL DEFAULT 0, "OutMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "OutLab"     DECIMAL(19,6)  NOT NULL DEFAULT 0, "OutSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "EndQty"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "EndMat"     DECIMAL(19,6)  NOT NULL DEFAULT 0, "EndMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "EndLab"     DECIMAL(19,6)  NOT NULL DEFAULT 0, "EndSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "EndAmount"  DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "Flags"      NVARCHAR(200),                 -- 负库存 / 兜底价 / 无价 / 尾差无处挤
    "TailAmt"    DECIMAL(19,6)  NOT NULL DEFAULT 0,   -- 零库存尾差结转（TAIL-01，Q32）：已计入 Out 四项，凭证 JZ04；负数 = 转出
    "RtOpenMat"   DECIMAL(19,4),                 -- 期初料工费占比·材料（%）= 期初材料 ÷ 期初四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtOpenLab"   DECIMAL(19,4),                 -- 期初料工费占比·人工（%）= 期初人工 ÷ 期初四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtOpenMfg"   DECIMAL(19,4),                 -- 期初料工费占比·制造费用（%）= 期初制造费用 ÷ 期初四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtOpenSub"   DECIMAL(19,4),                 -- 期初料工费占比·委外加工费（%）= 期初委外加工费 ÷ 期初四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtInMat"     DECIMAL(19,4),                 -- 入库料工费占比·材料（%）= 入库材料 ÷ 入库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtInLab"     DECIMAL(19,4),                 -- 入库料工费占比·人工（%）= 入库人工 ÷ 入库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtInMfg"     DECIMAL(19,4),                 -- 入库料工费占比·制造费用（%）= 入库制造费用 ÷ 入库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtInSub"     DECIMAL(19,4),                 -- 入库料工费占比·委外加工费（%）= 入库委外加工费 ÷ 入库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtOutMat"    DECIMAL(19,4),                 -- 出库料工费占比·材料（%）= 出库材料 ÷ 出库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtOutLab"    DECIMAL(19,4),                 -- 出库料工费占比·人工（%）= 出库人工 ÷ 出库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtOutMfg"    DECIMAL(19,4),                 -- 出库料工费占比·制造费用（%）= 出库制造费用 ÷ 出库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtOutSub"    DECIMAL(19,4),                 -- 出库料工费占比·委外加工费（%）= 出库委外加工费 ÷ 出库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtEndMat"    DECIMAL(19,4),                 -- 期末料工费占比·材料（%）= 期末材料 ÷ 期末四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtEndLab"    DECIMAL(19,4),                 -- 期末料工费占比·人工（%）= 期末人工 ÷ 期末四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtEndMfg"    DECIMAL(19,4),                 -- 期末料工费占比·制造费用（%）= 期末制造费用 ÷ 期末四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    "RtEndSub"    DECIMAL(19,4),                 -- 期末料工费占比·委外加工费（%）= 期末委外加工费 ÷ 期末四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）
    PRIMARY KEY ("RunId", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_R_ITEM" IS '物料进销存与单价：一行 = 一个物料；入、出、期末四项金额；单价四项（成本还原不用另算）'
@@
CREATE COLUMN TABLE "MTC_CA_R_ORDER" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "OrderType"   NVARCHAR(20)   NOT NULL,
    "OrderEntry"  INTEGER        NOT NULL,
    "WorType"     NVARCHAR(10),
    "ItemCode"    NVARCHAR(50),
    "iLevel"      INT            NOT NULL,
    "PlannedQty"  DECIMAL(19,6),
    "PrevRecvQty" DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "RecvQty"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "Ratio"       DECIMAL(19,10),               -- min(累计入库 ÷ 计划, 1)；本期无入库为空
    "ClosedInFc"  NVARCHAR(1)    NOT NULL DEFAULT 'N',  -- Y = 按关单处理：本期关闭，或截至期初已关闭、本期仍有单据挂上来（Q35）
    "AllocMfg"    DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "AllocLab"    DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "CostMat"     DECIMAL(19,6)  NOT NULL DEFAULT 0, "CostMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,  -- 本期完工成本四项
    "CostLab"     DECIMAL(19,6)  NOT NULL DEFAULT 0, "CostSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "CostAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "UnitCost"    DECIMAL(19,6),
    "WipAmt"      DECIMAL(19,6)  NOT NULL DEFAULT 0,   -- 期末在产品（四项合计）
    "CloseDifAmt" DECIMAL(19,6)  NOT NULL DEFAULT 0,   -- 本期关单差异（四项合计，进 CLOSE_DIF_POOL）
    PRIMARY KEY ("RunId", "OrderType", "OrderEntry")
)
@@
COMMENT ON TABLE "MTC_CA_R_ORDER" IS '订单成本：一行 = 一张订单；本期结转比例、分摊费用、完工成本四项、在产品、关单差异'
@@
CREATE COLUMN TABLE "MTC_CA_R_ORDER_MAT" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "OrderType"   NVARCHAR(20)   NOT NULL,
    "OrderEntry"  INTEGER        NOT NULL,
    "ItemCode"    NVARCHAR(50)   NOT NULL,      -- 材料；'#SUBFEE' = 委外加工费
    "OpenIssQty"  DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "OpenIssMat"  DECIMAL(19,6)  NOT NULL DEFAULT 0, "OpenIssMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "OpenIssLab"  DECIMAL(19,6)  NOT NULL DEFAULT 0, "OpenIssSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "OpenCarMat"  DECIMAL(19,6)  NOT NULL DEFAULT 0, "OpenCarMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "OpenCarLab"  DECIMAL(19,6)  NOT NULL DEFAULT 0, "OpenCarSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "IssQty"      DECIMAL(19,6)  NOT NULL DEFAULT 0,   -- 本期领料（正数；生产退料为负）
    "IssMat"      DECIMAL(19,6)  NOT NULL DEFAULT 0, "IssMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "IssLab"      DECIMAL(19,6)  NOT NULL DEFAULT 0, "IssSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "Ratio"       DECIMAL(19,10),                      -- 本行结转比例（2026-10-30）：max(订单比例, 累计入库 × 单位计划用量 ÷ 净领料数量)，最高 1；本期无入库为空
    "CarMat"      DECIMAL(19,6)  NOT NULL DEFAULT 0, "CarMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,   -- 本期结转
    "CarLab"      DECIMAL(19,6)  NOT NULL DEFAULT 0, "CarSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "WipMat"      DECIMAL(19,6)  NOT NULL DEFAULT 0, "WipMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,   -- 期末在产品
    "WipLab"      DECIMAL(19,6)  NOT NULL DEFAULT 0, "WipSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    "ClsMat"      DECIMAL(19,6)  NOT NULL DEFAULT 0, "ClsMfg" DECIMAL(19,6) NOT NULL DEFAULT 0,   -- 本期关单差异
    "ClsLab"      DECIMAL(19,6)  NOT NULL DEFAULT 0, "ClsSub" DECIMAL(19,6) NOT NULL DEFAULT 0,
    PRIMARY KEY ("RunId", "OrderType", "OrderEntry", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_R_ORDER_MAT" IS '订单 × 材料：期初累计、本期领料、本期结转、期末在产品、关单差异（S5 公式，规则 WIP-01 / WW-01 / CLS-01）'
@@
CREATE COLUMN TABLE "MTC_CA_R_POOL" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "PoolCode"  NVARCHAR(20)   NOT NULL,
    "Elem"      NVARCHAR(3)    NOT NULL,        -- MFG / LAB
    "Src"       NVARCHAR(10)   NOT NULL,        -- JDT / MRV / PROWW / SHARED 公摊材料 / CLOSEDIF 关单差异
    "Amount"    DECIMAL(19,6)  NOT NULL DEFAULT 0,
    PRIMARY KEY ("RunId", "PoolCode", "Elem", "Src")
)
@@
COMMENT ON TABLE "MTC_CA_R_POOL" IS '费用池：一行 = 池 × 要素 × 来源的金额（设计稿 4.4）'
@@
CREATE COLUMN TABLE "MTC_CA_R_ALLOC" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "PoolCode"   NVARCHAR(20)   NOT NULL,
    "Elem"       NVARCHAR(3)    NOT NULL,
    "OrderType"  NVARCHAR(20)   NOT NULL,
    "OrderEntry" INTEGER        NOT NULL,
    "Hours"      DECIMAL(19,6),
    "RecvQty"    DECIMAL(19,6),
    "Weight"     DECIMAL(19,6),                 -- 单位工时 × 本期入库数
    "Ratio"      DECIMAL(19,10),
    "Amount"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    PRIMARY KEY ("RunId", "PoolCode", "Elem", "OrderType", "OrderEntry")
)
@@
COMMENT ON TABLE "MTC_CA_R_ALLOC" IS '费用分摊：一行 = 一个池的一项费用分给一张订单（规则 EXP-01）'
@@
CREATE COLUMN TABLE "MTC_CA_R_PAIR" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "LineId"     BIGINT         NOT NULL,       -- 取价的行
    "PairType"   NVARCHAR(10)   NOT NULL,       -- TRF 形态转换 / SRT 销售退货 / CNL 取消单
    "SrcLineId"  BIGINT,                        -- 本次运行中的来源行
    "SrcFc"      NVARCHAR(10),                  -- 来源在以前账期时的账期
    "SrcTable"   NVARCHAR(50),                  -- MTC_CA_R_LINE / MTC_COST_0302_INVNTDETAIL1
    "UMat"       DECIMAL(19,6), "UMfg" DECIMAL(19,6), "ULab" DECIMAL(19,6), "USub" DECIMAL(19,6),  -- 来源单位成本
    "Note"       NVARCHAR(200),
    PRIMARY KEY ("RunId", "LineId")
)
@@
COMMENT ON TABLE "MTC_CA_R_PAIR" IS '配对：一行 = 一条按另一行取价的单据行（形态转换、销售退货、取消单）'
@@
CREATE COLUMN TABLE "MTC_CA_R_CMP" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "Kind"      NVARCHAR(20)   NOT NULL,        -- ITEM_END 物料期末金额 / ITEM_PRICE 单价 / ORDER_COST 订单完工成本 / WIP 在产品
    "KeyCode"   NVARCHAR(100)  NOT NULL,
    "NewVal"    DECIMAL(19,6),
    "OldVal"    DECIMAL(19,6),
    "Diff"      DECIMAL(19,6),
    "Reason"    NVARCHAR(20)   NOT NULL DEFAULT 'UNEXPLAINED',  -- OLD_BUG 旧缺陷 / RULE 口径变化 / UNEXPLAINED 未解释
    "Note"      NVARCHAR(500),
    PRIMARY KEY ("RunId", "Kind", "KeyCode")
)
@@
COMMENT ON TABLE "MTC_CA_R_CMP" IS '新旧比对：一行 = 一个有差异的物料 / 订单；差异原因先记 UNEXPLAINED，逐项归因'
@@
-- 物料 × 交易类型的进销存（替代旧 0303 进销存列表），由 R_LINE 汇总
CREATE OR REPLACE VIEW "MTC_CA_V_ITEM_FLOW" AS
SELECT "FcCode", "RunType", "Scenario", "RunId", "ItemCode", "TransCode",
       SUM("Qty") AS "Qty", SUM("MatAmt") AS "MatAmt", SUM("MfgAmt") AS "MfgAmt",
       SUM("LabAmt") AS "LabAmt", SUM("SubAmt") AS "SubAmt", SUM("Amount") AS "Amount"
  FROM "MTC_CA_R_LINE"
 GROUP BY "FcCode", "RunType", "Scenario", "RunId", "ItemCode", "TransCode"
@@
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
    "Reason"     NVARCHAR(500),                 -- 为什么要维护（中文一句话，页面和 B1 行备注用，用户 2026-10-30）
    "NeedDocs"   NVARCHAR(1000),                -- 触发的单据：按交易类型列单号 Num（每类最多 10 张），完整的见 MTC_CA_R_QCP_LINE
    PRIMARY KEY ("RunId", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_R_QCP_NEED" IS '需要维护期初成本价的物料（PRE-23）：本期有要按单价计价的变动，计算前却没有任何价格来源；只读清单，不写 @MTC_COST_QCPRICE'
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
CREATE COLUMN TABLE "MTC_CA_R_HOURS_NEED" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ItemCode"   NVARCHAR(50)   NOT NULL,       -- 产品（订单主件）
    "ItemName"   NVARCHAR(200),
    "ItmsGrpCod" NVARCHAR(20),
    "Pools"      NVARCHAR(500),                 -- 应分摊的费用池（逗号分隔）
    "OrderCnt"   INT,                           -- 本期有入库、应分摊的订单数
    "RecvQty"    DECIMAL(19,6),                 -- 这些订单本期入库数量合计
    "CurHours"   DECIMAL(19,6),                 -- 本期工时单里的单位工时：空 = 没有录，0 = 录了 0
    "RefHours"   DECIMAL(19,6),                 -- 参考工时：以前最近一个账期工时单里不为 0 的单位工时（只供参考，不写 B1）
    "RefFc"      NVARCHAR(30),                  -- 参考工时的账期
    "PoolNames"  NVARCHAR(500),                 -- 费用池代码 + 名称（B1 行备注用，用户 2026-10-30）
    "NeedOrders" NVARCHAR(1000),                -- 本期有入库的订单：类型 + 单号 Num + 入库数量（最多 15 张）
    PRIMARY KEY ("RunId", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_R_HOURS_NEED" IS '需要维护工时的产品（PRE-14 按物料汇总）：本期有入库、在费用池分摊范围内的订单，产品在本期工时单里没有单位工时或为 0；只读清单，不写 @MTC_COST_TIME'
