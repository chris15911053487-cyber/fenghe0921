-- =====================================================================
-- 新成本框架 第 1 期：输入快照层、校验结果、期初承接（设计稿 3.4、6、7）
-- 快照表（MTC_CA_S_*）和结果表（MTC_CA_R_*）都带运行键 FcCode/RunType/Scenario/RunId，
-- 由 MTC_CA_P_RUN_CLEAN 按运行键清理（只留最后一次成功运行）。
-- 符号约定：数量、金额入库为正、出库为负（与旧 0302 相同）；费用、加工费为正数表示发生额。
-- =====================================================================

-- 计价仓库范围：OWHS.U_IsCost='Y'（设计稿 Q1），MTC_CA_C_WHS 中登记的例外优先
CREATE OR REPLACE VIEW "MTC_CA_V_WHS" AS
SELECT W."WhsCode", W."WhsName",
       COALESCE(C."IsCost", CASE WHEN W."U_IsCost" = 'Y' THEN 'Y' ELSE 'N' END) AS "IsCost",
       CASE WHEN C."WhsCode" IS NOT NULL THEN 'C_WHS' ELSE 'OWHS' END AS "Source"
  FROM "OWHS" W
  LEFT JOIN "MTC_CA_C_WHS" C ON C."WhsCode" = W."WhsCode"
@@
COMMENT ON VIEW "MTC_CA_V_WHS" IS '计价仓库范围：IsCost=Y 的仓库参与成本计算'
@@
CREATE COLUMN TABLE "MTC_CA_S_ITEM" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ItemCode"    NVARCHAR(50)   NOT NULL,
    "ItemName"    NVARCHAR(200),
    "ItmsGrpCod"  NVARCHAR(20),
    "GrpType"     NVARCHAR(20),                 -- OITB.U_ItemGrpType（车间类别，费用池范围和 PP05 车间用，Q17）
    "CalType"     NVARCHAR(30),                 -- OITM.U_ItemProp
    "InvntItem"   NVARCHAR(1),
    "IsBomFather" NVARCHAR(1)    NOT NULL DEFAULT 'N',
    "iLevel"      INT            NOT NULL DEFAULT -1,
    "LevelSrc"    NVARCHAR(10),                 -- NOBOM / BOM / OVR
    "LevelNote"   NVARCHAR(500),                -- -1 的原因
    PRIMARY KEY ("RunId", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_S_ITEM" IS '物料快照：一行 = 一个物料；含本期层级（按当前 BOM，替代 U_COILV）'
@@
-- 已部署的库补列（2026-10-13 Q17 新增 GrpType）
DO BEGIN
    DECLARE n INT;
    SELECT COUNT(*) INTO n FROM SYS.TABLE_COLUMNS
     WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = 'MTC_CA_S_ITEM' AND COLUMN_NAME = 'GrpType';
    IF :n = 0 THEN
        EXEC 'ALTER TABLE "MTC_CA_S_ITEM" ADD ("GrpType" NVARCHAR(20))';
    END IF;
END
@@
-- 产品 → 费用池（池的分摊范围按 C_POOL_TGT.MatchBy 匹配物料组或 U_ItemGrpType）；P43、PRE-14/17/18 共用
CREATE OR REPLACE VIEW "MTC_CA_V_ITEM_POOL" AS
SELECT I."RunId", I."ItemCode", T."PoolCode", T."WorTypes", T."MatchBy", T."ItmsGrpCod" AS "MatchKey"
  FROM "MTC_CA_S_ITEM" I
  JOIN "MTC_CA_C_POOL_TGT" T ON I."FcCode" BETWEEN T."FromFc" AND T."ToFc"
                            AND ((T."MatchBy" = 'GRP' AND T."ItmsGrpCod" = I."ItmsGrpCod")
                              OR (T."MatchBy" = 'GRPTYPE' AND T."ItmsGrpCod" = I."GrpType"))
@@
COMMENT ON VIEW "MTC_CA_V_ITEM_POOL" IS '产品属于哪个费用池、可分摊哪些订单类型（一行 = 运行 × 产品 × 池）'
@@
CREATE COLUMN TABLE "MTC_CA_S_LINE" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "LineId"      BIGINT         NOT NULL,      -- 运行内序号
    "Src"         NVARCHAR(10)   NOT NULL,      -- OIVL / OMRV
    "SrcKey"      NVARCHAR(50)   NOT NULL,      -- OIVL.TransSeq；OMRV 为 DocEntry-LineId
    "ObjType"     NVARCHAR(20)   NOT NULL,
    "DocEntry"    INTEGER        NOT NULL,
    "DocNum"      NVARCHAR(50),
    "LineNum"     INTEGER,
    "Canceled"    NVARCHAR(1),                  -- N 正常 / Y 被取消的原单 / C 取消单
    "DocDate"     DATE           NOT NULL,
    "ItemCode"    NVARCHAR(50)   NOT NULL,
    "WhsCode"     NVARCHAR(8),
    "Qty"         DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "B1Amt"       DECIMAL(19,6),                -- OIVL.SumStock（B1 移动平均下的金额，仅供对照）
    "SrcAmt"      DECIMAL(19,6),                -- 有固定来源金额的行：采购收货 / 退货、发票差异、重估；其余为空，由计算定价
    "TransCode"   NVARCHAR(10),                 -- @MTC_COST_IOTYPE.Code；空 = 识别不了（PRE-05）
    "Dir"         NVARCHAR(1),                  -- @MTC_COST_IOTYPE.U_IOType：I / O
    "BusiType"    NVARCHAR(20),                 -- 59/60 的业务类型 @U_CIOTRN.Code
    "BusiClass"   NVARCHAR(20),                 -- @U_CIOTRN.U_TransType：B01 订单产出 / B03 订单投入 / K01 / K02
    "CardCode"    NVARCHAR(50),
    "BaseType"    NVARCHAR(20),                 -- MTC_VIEW_Document 改写后的来源（退货 → 原交货；取消单 → 原单）
    "BaseEntry"   NVARCHAR(50),
    "BaseLine"    NVARCHAR(50),
    "OrderType"   NVARCHAR(20),                 -- 202 / MTC_OWOR（59/60 订单领料、入库）
    "OrderEntry"  INTEGER,
    "OrderLine"   INTEGER,                      -- 订单行；完工入库为空
    "PairKey"     NVARCHAR(100),                -- 形态转换配对键（204/205）
    "AcctCode"    NVARCHAR(15),
    "OcrCode"     NVARCHAR(20),
    "SharedExp"   NVARCHAR(1)    NOT NULL DEFAULT 'N',  -- Y = 记 5101 的其他出入库 / 盘点，金额进费用池（公摊材料）
    "NoCost"      NVARCHAR(1)    NOT NULL DEFAULT 'N',
    "NoCostNote"  NVARCHAR(200),
    PRIMARY KEY ("RunId", "LineId")
)
@@
COMMENT ON TABLE "MTC_CA_S_LINE" IS '库存变动快照：一行 = 计价仓库的一条 OIVL 记录或一条库存重估行（替代 0303 / 0302 取数）'
@@
CREATE INDEX "MTC_CA_S_LINE_IX1" ON "MTC_CA_S_LINE" ("RunId", "ItemCode")
@@
CREATE INDEX "MTC_CA_S_LINE_IX2" ON "MTC_CA_S_LINE" ("RunId", "OrderType", "OrderEntry")
@@
CREATE COLUMN TABLE "MTC_CA_S_ORDER" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "OrderType"    NVARCHAR(20)   NOT NULL,     -- 202 / MTC_OWOR
    "OrderEntry"   INTEGER        NOT NULL,
    "OrderNum"     NVARCHAR(50),
    "WorType"      NVARCHAR(10),
    "ItemCode"     NVARCHAR(50),
    "PlannedQty"   DECIMAL(19,6),
    "PostDate"     DATE,
    "B1Status"     NVARCHAR(1),                 -- 当前状态（P/R/L/C）
    "CloseDate"    DATE,
    "StatusAtEnd"  NVARCHAR(10)   NOT NULL,     -- OPEN / CLOSED（截至期末，设计稿 Q4）
    "ClosedInFc"   NVARCHAR(1)    NOT NULL DEFAULT 'N',
    "InScope"      NVARCHAR(1)    NOT NULL DEFAULT 'Y',  -- N = 期初前已关闭或已取消，仅因本期有单据引用而列入
    "CardCode"     NVARCHAR(50),
    "RecvQty"      DECIMAL(19,6)  NOT NULL DEFAULT 0,   -- 本期完工入库数（S_LINE 中 B01、订单行为空）
    "PrevRecvQty"  DECIMAL(19,6)  NOT NULL DEFAULT 0,   -- 截至上期累计入库数（来自期初）
    PRIMARY KEY ("RunId", "OrderType", "OrderEntry")
)
@@
COMMENT ON TABLE "MTC_CA_S_ORDER" IS '订单快照：一行 = 一张生产 / 委外 / 返工订单（OWOR + @MTC_OWOR）'
@@
CREATE COLUMN TABLE "MTC_CA_S_ORDER_LINE" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "OrderType"   NVARCHAR(20)   NOT NULL,
    "OrderEntry"  INTEGER        NOT NULL,
    "OrderLine"   INTEGER        NOT NULL,
    "ItemCode"    NVARCHAR(50),
    "BaseQty"     DECIMAL(19,6),
    "PlannedQty"  DECIMAL(19,6),
    PRIMARY KEY ("RunId", "OrderType", "OrderEntry", "OrderLine")
)
@@
COMMENT ON TABLE "MTC_CA_S_ORDER_LINE" IS '订单计划用料：只用于提示（不领、订单外领料），不参与结转公式'
@@
CREATE COLUMN TABLE "MTC_CA_S_EXP" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ExpId"      BIGINT         NOT NULL,
    "Src"        NVARCHAR(10)   NOT NULL,       -- JDT / MRV / PROWW
    "SrcKey"     NVARCHAR(50)   NOT NULL,       -- TransId-Line_ID / DocEntry-LineId
    "SrcTrans"   NVARCHAR(20),                  -- 凭证代码 OJDT.TransCode，或重估单类型
    "SrcObj"     NVARCHAR(20),                  -- 凭证的来源单据类型 OJDT.TransType（排查重复计入用）
    "SrcDoc"     INTEGER,                       -- 凭证的来源单据 OJDT.CreatedBy
    "DocDate"    DATE           NOT NULL,
    "AcctCode"   NVARCHAR(15),
    "OcrCode"    NVARCHAR(20),
    "Elem"       NVARCHAR(3)    NOT NULL,       -- MFG 制造 / LAB 人工
    "Amount"     DECIMAL(19,6)  NOT NULL,       -- 正数 = 费用增加
    "Note"       NVARCHAR(200),
    PRIMARY KEY ("RunId", "ExpId")
)
@@
COMMENT ON TABLE "MTC_CA_S_EXP" IS '费用来源快照：一行 = 一条凭证行或重估行（替代 0311 前三段；公摊材料来自 S_LINE.SharedExp，关单差异在迭代中产生）'
@@
CREATE COLUMN TABLE "MTC_CA_S_SUBFEE" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "FeeId"       BIGINT         NOT NULL,
    "Src"         NVARCHAR(10)   NOT NULL,      -- PDN 加工费收货 / RPD 加工费退货 / PROWW 重估
    "SrcKey"      NVARCHAR(50)   NOT NULL,
    "DocDate"     DATE           NOT NULL,
    "ItemCode"    NVARCHAR(50),                 -- 加工费物料
    "Qty"         DECIMAL(19,6),
    "Amount"      DECIMAL(19,6)  NOT NULL,      -- 正数 = 加工费增加
    "RcptEntry"   INTEGER,                      -- 关联的生产收货 OIGN.DocEntry
    "OrderType"   NVARCHAR(20),                 -- 空 = 找不到订单（PRE-12）
    "OrderEntry"  INTEGER,
    "MatchNote"   NVARCHAR(200),
    PRIMARY KEY ("RunId", "FeeId")
)
@@
COMMENT ON TABLE "MTC_CA_S_SUBFEE" IS '委外加工费来源快照：一行 = 一条加工费收货 / 退货 / ProWW 重估行，按订单归集（替代 0306，覆盖 MTC_OWOR）'
@@
CREATE COLUMN TABLE "MTC_CA_S_AP_MOVE" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "MoveId"     BIGINT         NOT NULL,
    "BaseObj"    NVARCHAR(2)    NOT NULL,       -- 暂估行：20 收货 / 21 不基于收货的退货
    "BaseEntry"  INTEGER        NOT NULL,
    "BaseLine"   INTEGER        NOT NULL,
    "BaseDate"   DATE,
    "BaseSign"   INT            NOT NULL,       -- 收货 1 / 退货 -1
    "BaseQty"    DECIMAL(19,6),
    "UnitPrice"  DECIMAL(19,6),                 -- 暂估单价：U_InitPrice ≠ 0 → U_InitPrice；U_IsPrice='Y' → Price；否则 LineTotal ÷ 数量；材料、委外加工费相同
    "FullAmt"    DECIMAL(19,2),                 -- 整行暂估金额（正数）
    "CardCode"   NVARCHAR(50),
    "ItemCode"   NVARCHAR(50),
    "AccrType"   NVARCHAR(10)   NOT NULL,       -- MAT 材料（PUR1 / PUR2）/ SUBFEE 委外加工费（PUR4 / PUR3）
    "MoveType"   NVARCHAR(10)   NOT NULL,       -- ACCR 暂估行本身 / RET 基于暂估行的退货、换货 / INV 基于暂估行的发票、贷项
    "IsCancel"   NVARCHAR(1)    NOT NULL DEFAULT 'N',  -- Y = 取消单（金额、数量取原单的相反数，Q26）
    "ObjType"    NVARCHAR(2)    NOT NULL,       -- 产生这笔变动的单据
    "DocEntry"   INTEGER        NOT NULL,
    "LineNum"    INTEGER        NOT NULL,
    "DocDate"    DATE           NOT NULL,
    "Qty"        DECIMAL(19,6)  NOT NULL DEFAULT 0,   -- 对暂估行未清数量的影响（按暂估行方向，正 = 增加未清）
    "AccrAmt"    DECIMAL(19,2)  NOT NULL DEFAULT 0,   -- 对 220202 贷方余额的影响（正 = 增加暂估）
    "DocAmt"     DECIMAL(19,2),                       -- INV：发票行金额（发票为正、贷项为负，取消单反向）
    "ProdItem"   NVARCHAR(50),                        -- 委外加工费发票行 U_ItemCode（发票差异计入的产品）
    "AmtRule"    NVARCHAR(10),                        -- ROUND 数量 × 暂估单价 / LAST 最后一次清余数（Q27）/ FULL 整行 / CANCEL 取消
    PRIMARY KEY ("RunId", "MoveId")
)
@@
COMMENT ON TABLE "MTC_CA_S_AP_MOVE" IS '应付暂估变动：一行 = 一条收货 / 退货暂估行的一笔变动（暂估、退货、开票及其取消）；PUR1–PUR5 凭证、期末应付暂估余额、委外发票差异共用（设计稿 4.6）'
@@
CREATE INDEX "MTC_CA_S_AP_MOVE_IX1" ON "MTC_CA_S_AP_MOVE" ("RunId", "BaseObj", "BaseEntry", "BaseLine")
@@
CREATE COLUMN TABLE "MTC_CA_S_HOURS" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "Hours"      DECIMAL(19,6)  NOT NULL,       -- 单位工时（多个值时取最大，同时由 PRE-13 报出）
    "MinHours"   DECIMAL(19,6),
    "LineCnt"    INT,
    PRIMARY KEY ("RunId", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_S_HOURS" IS '本期单位工时快照：一行 = 一个产品（@MTC_COST_TIME(1)）'
@@
CREATE COLUMN TABLE "MTC_CA_S_QCPRICE" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "Price"      DECIMAL(19,6)  NOT NULL,
    "MinPrice"   DECIMAL(19,6),
    "LineCnt"    INT,
    PRIMARY KEY ("RunId", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_S_QCPRICE" IS '本期期初维护价快照：一行 = 一个物料（@MTC_COST_QCPRICE(1)，迭代初值 / 兜底价 / 无原单退货价）'
@@
CREATE COLUMN TABLE "MTC_CA_S_OPEN" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "Qty"        DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "MatAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "MfgAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "LabAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "SubAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "Amount"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "Src"        NVARCHAR(10)   NOT NULL,       -- BOOT 期初承接 / PREV 上期新框架结果
    PRIMARY KEY ("RunId", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_S_OPEN" IS '物料期初快照：一行 = 一个物料的期初数量和四项金额'
@@
CREATE COLUMN TABLE "MTC_CA_S_ORDER_OPEN" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "OrderType"     NVARCHAR(20)   NOT NULL,
    "OrderEntry"    INTEGER        NOT NULL,
    "ItemCode"      NVARCHAR(50)   NOT NULL,    -- 材料；'#SUBFEE' 行 = 未结转的委外加工费
    "CumIssueQty"   DECIMAL(19,6)  NOT NULL DEFAULT 0,  -- 截至上期累计领料（正数）
    "CumIssueMat"   DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "CumIssueMfg"   DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "CumIssueLab"   DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "CumIssueSub"   DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "CumCarriedMat" DECIMAL(19,6)  NOT NULL DEFAULT 0,  -- 截至上期累计已结转
    "CumCarriedMfg" DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "CumCarriedLab" DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "CumCarriedSub" DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "Src"           NVARCHAR(10)   NOT NULL,
    PRIMARY KEY ("RunId", "OrderType", "OrderEntry", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_S_ORDER_OPEN" IS '订单 × 材料期初快照：截至上期的累计领料和累计结转（设计稿 4.2、7）'
@@
CREATE COLUMN TABLE "MTC_CA_R_CHECK" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "CheckId"    NVARCHAR(20)   NOT NULL,
    "Stage"      NVARCHAR(4)    NOT NULL,
    "Result"     NVARCHAR(4)    NOT NULL,       -- PASS / FAIL（阻断）/ WARN / SKIP
    "IssueCnt"   BIGINT         NOT NULL DEFAULT 0,
    "IsBlock"    NVARCHAR(1)    NOT NULL,
    "Msg"        NVARCHAR(1000),
    "CheckTime"  TIMESTAMP      NOT NULL,
    PRIMARY KEY ("RunId", "CheckId")
)
@@
COMMENT ON TABLE "MTC_CA_R_CHECK" IS '校验结果：一行 = 一次运行的一项校验'
@@
CREATE COLUMN TABLE "MTC_CA_R_CHECK_DTL" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "CheckId"    NVARCHAR(20)   NOT NULL,
    "SeqNo"      INT            NOT NULL,
    "KeyCode"    NVARCHAR(200),                 -- 单据 / 物料 / 订单键，可回查 B1
    "Info"       NVARCHAR(1000),
    PRIMARY KEY ("RunId", "CheckId", "SeqNo")
)
@@
COMMENT ON TABLE "MTC_CA_R_CHECK_DTL" IS '校验问题明细：每项最多保留 MTC_CA_C_PARAM.CHECK_DTL_MAX 行（只在本地显示）'
@@
-- 期初承接（一次性，设计稿第 7 节）：不按运行键清理，代表“旧框架 2026-08 的期末”
CREATE COLUMN TABLE "MTC_CA_BOOT_ITEM" (
    "FcCode"     NVARCHAR(10)   NOT NULL,
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "Qty"        DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "MatAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "MfgAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "LabAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "SubAmt"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "Amount"     DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "Src"        NVARCHAR(100),
    "LoadTime"   TIMESTAMP,
    PRIMARY KEY ("FcCode", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_BOOT_ITEM" IS '期初承接：旧框架该期物料期末（MTC_COST_0301_INVNT.QM_*），料工费按 MTC_CA_BOOT_RATIO 拆分，没有比例的全部记材料'
@@
CREATE COLUMN TABLE "MTC_CA_BOOT_ORDER" (
    "FcCode"      NVARCHAR(10)   NOT NULL,
    "OrderType"   NVARCHAR(20)   NOT NULL,
    "OrderEntry"  INTEGER        NOT NULL,
    "CumRecvQty"  DECIMAL(19,6)  NOT NULL DEFAULT 0,  -- 旧 0321_OWOR 截至该期 IgnQty 合计
    "ZcpWip"      DECIMAL(19,6),                      -- 旧 0322_OWOR_ZCP."在产品新"
    "Zcp1Wip"     DECIMAL(19,6),                      -- 旧 0322_OWOR_ZCP1.Amount 合计
    "LoadTime"    TIMESTAMP,
    PRIMARY KEY ("FcCode", "OrderType", "OrderEntry")
)
@@
COMMENT ON TABLE "MTC_CA_BOOT_ORDER" IS '期初承接：截至该期仍未关闭的订单；ZcpWip ≠ Zcp1Wip 的由 BOOT-01 列出（设计稿 Q8）'
@@
CREATE COLUMN TABLE "MTC_CA_BOOT_ORDER_MAT" (
    "FcCode"        NVARCHAR(10)   NOT NULL,
    "OrderType"     NVARCHAR(20)   NOT NULL,
    "OrderEntry"    INTEGER        NOT NULL,
    "ItemCode"      NVARCHAR(50)   NOT NULL,
    "CumIssueQty"   DECIMAL(19,6)  NOT NULL DEFAULT 0,  -- 旧 0321_OWOR1 截至该期合计，取反为正数
    "CumIssueAmt"   DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "WipQty"        DECIMAL(19,6)  NOT NULL DEFAULT 0,  -- 旧 0322_OWOR_ZCP1.Quantity / Amount
    "WipAmt"        DECIMAL(19,6)  NOT NULL DEFAULT 0,
    "CumCarriedAmt" DECIMAL(19,6)  NOT NULL DEFAULT 0,  -- = CumIssueAmt − WipAmt
    "LoadTime"      TIMESTAMP,
    PRIMARY KEY ("FcCode", "OrderType", "OrderEntry", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_BOOT_ORDER_MAT" IS '期初承接：订单 × 材料累计领料、在产品（ZCP1，设计稿 Q8）、累计已结转'
@@
CREATE COLUMN TABLE "MTC_CA_BOOT_RATIO" (
    "FcCode"     NVARCHAR(10)   NOT NULL,       -- 承接账期
    "ItemCode"   NVARCHAR(50)   NOT NULL,
    "RatioFc"    NVARCHAR(10)   NOT NULL,       -- 取比例的旧框架账期（截至承接账期最近一个有完工的账期）
    "RMat"       DECIMAL(19,10) NOT NULL DEFAULT 1,
    "RMfg"       DECIMAL(19,10) NOT NULL DEFAULT 0,
    "RLab"       DECIMAL(19,10) NOT NULL DEFAULT 0,
    "RSub"       DECIMAL(19,10) NOT NULL DEFAULT 0,
    "Basis"      NVARCHAR(200),
    "LoadTime"   TIMESTAMP,
    PRIMARY KEY ("FcCode", "ItemCode")
)
@@
COMMENT ON TABLE "MTC_CA_BOOT_RATIO" IS '期初承接：物料料工费比例（旧 0321_OWOR_SUM 最近有完工账期的完工成本四项，材料按领料逐级展开；用户 2026-10-18），拆分 BOOT_ITEM 期末和订单领料'
