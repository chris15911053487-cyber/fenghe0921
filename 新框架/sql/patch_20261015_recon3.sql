-- 2026-10-15 补丁：财务对账分期初 / 本期 / 期末列示（用户 2026-10-15）。新表 MTC_CA_R_GOODS_OUT_BEG（期初发出商品），新函数 MTC_CA_F_GOODS_OPEN，
-- MTC_CA_F_RECON_LEDGER 加 Phase 列、MTC_CA_F_RECON 加期初 / 本期 / 期末列，P75 按参数 RECON_BLOCK_ON（默认 CUR 本期差额）判断。
-- 已部署的库依次执行：本文件（建表 + 种子），16_p70_jdt.sql（重建 F_GOODS_OPEN、P71、F_RECON*、P75），再重新计算；执行台更新 actions.json / index.html。
CREATE COLUMN TABLE "MTC_CA_R_GOODS_OUT_BEG" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ObjType"    NVARCHAR(20)   NOT NULL,       -- 15 交货 / 16 不基于交货的销售退货
    "DocEntry"   INTEGER        NOT NULL,
    "LineNum"    INTEGER        NOT NULL,
    "DocDate"    DATE,
    "CardCode"   NVARCHAR(50),
    "CustType"   NVARCHAR(20),
    "IsSample"   NVARCHAR(1)    NOT NULL DEFAULT 'N',
    "ItemCode"   NVARCHAR(50),
    "DocQty"     DECIMAL(19,6),
    "InvQty"     DECIMAL(19,6),                 -- 截至上期末已开票（贷项）数量
    "RetQty"     DECIMAL(19,6),                 -- 截至上期末已退货数量
    "OpenQty"    DECIMAL(19,6),                 -- 带符号：交货为正、独立退货为负
    "UnitCost"   DECIMAL(19,6),
    "CostAmt"    DECIMAL(19,2),
    "CostSrc"    NVARCHAR(50),
    PRIMARY KEY ("RunId", "ObjType", "DocEntry", "LineNum")
)
@@
COMMENT ON TABLE "MTC_CA_R_GOODS_OUT_BEG" IS '期初发出商品（截至上期末已交货未开票），结构同 R_GOODS_OUT，单位成本取同一来源（R_DNCOST）；财务对账的业务端期初（用户 2026-10-15）'
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-09', 'POST', 190, '库存科目总账 = 业务', '按存货科目比较与新框架期末金额（替代 JZ04 尾差凭证，Q15）。期初 / 本期 / 期末分开列示业务、财务和差额：业务期初取承接 / 上期结果，财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证（已过账或已在未清凭单的凭证代码不再加）；按参数 RECON_BLOCK_ON 判断（默认 CUR 本期差额，期初差额只列示；用户 2026-10-15；MTC_CA_F_RECON）', 'Y', 'S16') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-10', 'POST', 200, '发出商品对账', '140601（三个来源都不含 AR03/AR04）= 发出商品（非样品）合计（同 C20）。期初 / 本期 / 期末分开列示业务、财务和差额：业务期初取承接 / 上期结果，财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证（已过账或已在未清凭单的凭证代码不再加）；按参数 RECON_BLOCK_ON 判断（默认 CUR 本期差额，期初差额只列示；用户 2026-10-15；MTC_CA_F_RECON）', 'Y', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-11', 'POST', 210, '应付暂估对账', '220202（贷 − 借）按 U_VendorCode = 应付暂估（按供应商，同 C19）。期初 / 本期 / 期末分开列示业务、财务和差额：业务期初取承接 / 上期结果，财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证（已过账或已在未清凭单的凭证代码不再加）；按参数 RECON_BLOCK_ON 判断（默认 CUR 本期差额，期初差额只列示；用户 2026-10-15；MTC_CA_F_RECON）', 'Y', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-13', 'POST', 225, '生产在产品对账', '500101 的成本凭证 = 生产 / 包装 / 返工订单（WorType ≠ 50）在产品，不含加工费；本期的非成本凭证分录（手工凭证、单据自动凭证等）允许存在，单独列出、不算差异，期初按科目余额全额比较（参数 RECON_COSTONLY_AREAS）。期初 / 本期 / 期末分开列示业务、财务和差额：业务期初取承接 / 上期结果，财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证（已过账或已在未清凭单的凭证代码不再加）；按参数 RECON_BLOCK_ON 判断（默认 CUR 本期差额，期初差额只列示；用户 2026-10-15；MTC_CA_F_RECON）', 'Y', 'S5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('RECON_COSTONLY_AREAS', '0000-00', '9999-99', ',WIP_PROD,', 'LIST', '财务对账中只比较成本凭证（COST_TRANSCODES）的对账项：其他分录（手工凭证、单据自动凭证等）允许存在，单独列出、不算差异；可选 STOCK、WIP_PROD、WW_MAT、WW_FEE、GOODS、AP（用户 2026-10-13）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('RECON_BLOCK_ON', '0000-00', '9999-99', 'CUR', 'STR', '财务对账（POST-06/09/10/11/13）按哪一列差额判断：CUR 本期差额（期初差额只列示）/ END 期末差额（用户 2026-10-15）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-06', 'POST', 160, '委外对账', '140801 = 委外在产品（材料）；140802 = 订单上未结转加工费（正常为 0）；另列加工费留在订单上的订单。期初 / 本期 / 期末分开列示业务、财务和差额：业务期初取承接 / 上期结果，财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证（已过账或已在未清凭单的凭证代码不再加）；按参数 RECON_BLOCK_ON 判断（默认 CUR 本期差额，期初差额只列示；用户 2026-10-15；MTC_CA_F_RECON）', 'Y', 'S4') WITH PRIMARY KEY
