-- 2026-10-15 补丁：发出商品（用户 2026-10-15）
--   ① 分次开票的尾差：新表 MTC_CA_R_GOODS_MOVE（本期开票 / 贷项 / 退货消耗和全部消耗完时的尾差 ADJ），新函数 MTC_CA_F_GOODS_MOVE；
--      DN03 = INV + RIN + ADJ，发出商品余额 = 行金额 − 已消耗金额，与 DN01 − DN03 逐行相等
--   ② PRE-26 应收发票 / 贷项不基于交货 / 退货（阻断）；PRE-27 销售单据没有客户类型（阻断）
-- 已部署的库依次执行：本文件（建表 + 种子），08_precheck.sql（F_GOODS_OPEN / F_GOODS_MOVE 移到这里，重建 P10_PRECHECK），
-- 16_p70_jdt.sql（重建 P71、P70），18_meta_comments.sql，再 CALL "MTC_CA_P_META_SYNC"()
CREATE COLUMN TABLE "MTC_CA_R_GOODS_MOVE" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "SrcObj"     NVARCHAR(20)   NOT NULL,       -- 被消耗的行：15 交货 / 16 不基于交货的销售退货
    "SrcEntry"   INTEGER        NOT NULL,
    "SrcLine"    INTEGER        NOT NULL,
    "K"          NVARCHAR(10)   NOT NULL,       -- INV 应收发票 / RIN 应收贷项 / RET 基于交货的退货 / ADJ 全部消耗完的尾差
    "DocEntry"   INTEGER        NOT NULL,       -- 消耗单据（含取消单）；ADJ 为原行
    "LineNum"    INTEGER        NOT NULL,
    "DocDate"    DATE,                          -- ADJ 为期末日
    "CustType"   NVARCHAR(20),                  -- 消耗单据的客户类型；ADJ 取原行的
    "IsSample"   NVARCHAR(1)    NOT NULL DEFAULT 'N',  -- 原行或消耗单据是样品销售：不做 DN03
    "Qty"        DECIMAL(19,6),                 -- 与原行 DocQty 同号；取消单反号
    "UnitCost"   DECIMAL(19,6),                 -- INV / RIN 取原行单位成本，RET 取退货行自己的
    "Amount"     DECIMAL(19,2),                 -- ROUND(Qty × UnitCost, 2)；ADJ = 行金额 − 已消耗金额（本期新出现的部分）
    PRIMARY KEY ("RunId", "SrcObj", "SrcEntry", "SrcLine", "K", "DocEntry", "LineNum")
)
@@
COMMENT ON TABLE "MTC_CA_R_GOODS_MOVE" IS '发出商品本期消耗：一行 = 一条交货 / 独立退货行被本期一张开票、贷项或退货（含取消单）消耗的部分，或该行全部消耗完时的尾差（ADJ）；DN03 = INV + RIN + ADJ（非样品），RET 由 DN01 冲回（用户 2026-10-15）'
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-26', 'PRE', 260, '应收发票 / 贷项不基于交货 / 退货', '本期应收发票的库存物料行不基于交货（直接开票出库、预留发票），或应收贷项的库存物料行不基于退货：发出商品和 DN03 只认基于交货 / 退货的开票，这类行的销售成本结转不了（用户 2026-10-15：不会出现，出现就阻断）', 'Y', 'S10') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-27', 'PRE', 270, '销售单据没有客户类型', '本期交货 / 退货 / 应收发票 / 贷项，以及截至期末仍未开票的交货 / 独立退货，销售订单类型（U_SalOrdType）在 @MTC_SALORDTYPE 中没有或客户类型不是国内客户 / 国外客户：DN03 取不到 6401 科目，AR03/AR04 不计提，样品 DN02/DN04 不生成（用户 2026-10-15 阻断）', 'Y', 'S12') WITH PRIMARY KEY
