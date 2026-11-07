-- =====================================================================
-- 新成本框架 第 3 期：凭证、发出商品、应付暂估的结果表与配置（设计稿 3.5、4.5、4.6，清单 S12、S15）
-- 凭证先逐条来源写 R_JDT_SRC（金额带符号：正 = 借，负 = 贷），再按 凭证代码 × 科目 × 成本中心 × 项目 汇总成 R_JDT。
-- 新框架只生成凭证，不过账；过账仍在库外完成（与旧 0801 相同）。
-- =====================================================================
CREATE COLUMN TABLE "MTC_CA_R_JDT_SRC" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "SrcId"      BIGINT         NOT NULL,
    "TransCode"  NVARCHAR(10)   NOT NULL,       -- OTRC.TrnsCode
    "AcctCode"   NVARCHAR(15),                  -- 空 = 取不到科目（POST-08 报出）
    "OcrCode"    NVARCHAR(20),
    "Project"    NVARCHAR(20),
    "Amount"     DECIMAL(19,2)  NOT NULL,       -- 正 = 借方，负 = 贷方
    "SrcType"    NVARCHAR(10)   NOT NULL,       -- LINE 单据行（R_LINE.LineId）/ ORDER 订单 / DOC B1 单据行 / GL 总账 / OMRV 重估行
    "SrcKey"     NVARCHAR(100),
    "Note"       NVARCHAR(200),
    "VendorCode" NVARCHAR(50),                  -- 220202 应付暂估行的供应商（写入 JDT1.U_VendorCode，PUR1–PUR5）
    PRIMARY KEY ("RunId", "SrcId")
)
@@
COMMENT ON TABLE "MTC_CA_R_JDT_SRC" IS '凭证来源明细：一行 = 一笔来源对一个科目的借贷（替代旧 0802_OJDTBASEDETAIL），可追溯到单据行、订单'
@@
CREATE COLUMN TABLE "MTC_CA_R_JDT" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "TransCode"  NVARCHAR(10)   NOT NULL,
    "LineNo"     INT            NOT NULL,
    "TransName"  NVARCHAR(100),
    "RefDate"    DATE           NOT NULL,
    "AcctCode"   NVARCHAR(15),
    "Debit"      DECIMAL(19,2)  NOT NULL DEFAULT 0,
    "Credit"     DECIMAL(19,2)  NOT NULL DEFAULT 0,
    "OcrCode"    NVARCHAR(20),
    "Project"    NVARCHAR(20),
    "VendorCode" NVARCHAR(50),                  -- 供应商（JDT1.U_VendorCode）
    PRIMARY KEY ("RunId", "TransCode", "LineNo")
)
@@
-- 已部署的库补列（2026-10-13 PUR1–PUR5 需要按供应商）
DO BEGIN
    DECLARE n INT;
    SELECT COUNT(*) INTO n FROM SYS.TABLE_COLUMNS
     WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = 'MTC_CA_R_JDT_SRC' AND COLUMN_NAME = 'VendorCode';
    IF :n = 0 THEN
        EXEC 'ALTER TABLE "MTC_CA_R_JDT_SRC" ADD ("VendorCode" NVARCHAR(50))';
    END IF;
    SELECT COUNT(*) INTO n FROM SYS.TABLE_COLUMNS
     WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = 'MTC_CA_R_JDT' AND COLUMN_NAME = 'VendorCode';
    IF :n = 0 THEN
        EXEC 'ALTER TABLE "MTC_CA_R_JDT" ADD ("VendorCode" NVARCHAR(50))';
    END IF;
END
@@
COMMENT ON TABLE "MTC_CA_R_JDT" IS '凭证行：一行 = 一张凭证（凭证代码）的一个科目 × 成本中心 × 项目（替代旧 0801_TOOJDT，每种凭证代码一张）'
@@
CREATE COLUMN TABLE "MTC_CA_R_GOODS_OUT" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ObjType"    NVARCHAR(20)   NOT NULL,       -- 15 交货 / 16 不基于交货的销售退货
    "DocEntry"   INTEGER        NOT NULL,
    "LineNum"    INTEGER        NOT NULL,
    "DocDate"    DATE,
    "CardCode"   NVARCHAR(50),
    "CustType"   NVARCHAR(20),                  -- @MTC_SALORDTYPE.U_CustType
    "IsSample"   NVARCHAR(1)    NOT NULL DEFAULT 'N',
    "ItemCode"   NVARCHAR(50),
    "DocQty"     DECIMAL(19,6),
    "InvQty"     DECIMAL(19,6),                 -- 截至期末已开票（贷项）数量
    "RetQty"     DECIMAL(19,6),                 -- 截至期末已退货数量（基于交货的退货）
    "OpenQty"    DECIMAL(19,6),                 -- 带符号：交货为正、独立退货为负
    "UnitCost"   DECIMAL(19,6),
    "CostAmt"    DECIMAL(19,2),
    "CostSrc"    NVARCHAR(50),
    PRIMARY KEY ("RunId", "ObjType", "DocEntry", "LineNum")
)
@@
COMMENT ON TABLE "MTC_CA_R_GOODS_OUT" IS '发出商品（截至期末已交货未开票），一行 = 一条未清交货 / 独立退货行；口径同 reports/MTC_RPT_CO6103，成本取新框架结果'
@@
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
CREATE COLUMN TABLE "MTC_CA_R_AP_ACCR" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ObjType"    NVARCHAR(20)   NOT NULL,       -- 20 收货 / 21 不基于收货的退货
    "DocEntry"   INTEGER        NOT NULL,
    "LineNum"    INTEGER        NOT NULL,
    "DocDate"    DATE,
    "CardCode"   NVARCHAR(50),
    "AccrType"   NVARCHAR(10),                  -- MAT 材料 / SUBFEE 委外费用
    "ItemCode"   NVARCHAR(50),
    "DocQty"     DECIMAL(19,6),
    "InvQty"     DECIMAL(19,6),
    "RetQty"     DECIMAL(19,6),
    "OpenQty"    DECIMAL(19,6),                 -- 带符号
    "UnitPrice"  DECIMAL(19,6),                 -- 暂估单价
    "OpenAmt"    DECIMAL(19,2),
    PRIMARY KEY ("RunId", "ObjType", "DocEntry", "LineNum")
)
@@
COMMENT ON TABLE "MTC_CA_R_AP_ACCR" IS '应付暂估（截至期末已收货未开票），一行 = 一条未清收货 / 独立退货行；口径同 reports/MTC_RPT_CO6102'
@@
CREATE COLUMN TABLE "MTC_CA_R_DNCOST" (
    "FcCode" NVARCHAR(10) NOT NULL, "RunType" NVARCHAR(1) NOT NULL, "Scenario" NVARCHAR(30) NOT NULL, "RunId" BIGINT NOT NULL,
    "ObjType"    NVARCHAR(20)   NOT NULL,       -- 15 交货 / 16 销售退货
    "DocEntry"   INTEGER        NOT NULL,
    "LineNum"    INTEGER        NOT NULL,
    "UnitCost"   DECIMAL(19,6),                 -- 空 = 找不到成本（POST-12）
    "CostSrc"    NVARCHAR(50),                  -- U_InitPrice / 本期 / 新框架 YYYY-MM / 旧0302
    PRIMARY KEY ("RunId", "ObjType", "DocEntry", "LineNum")
)
@@
COMMENT ON TABLE "MTC_CA_R_DNCOST" IS '交货 / 退货行单位成本：DN03 开票结转、AR03/AR04 与发出商品共用'
@@
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
CREATE COLUMN TABLE "MTC_CA_C_OCR_MAP" (
    "MapType"   NVARCHAR(20)   NOT NULL,        -- ITEMGRPTYPE：产品物料组的 OITB.U_ItemGrpType → 车间成本中心
    "MapKey"    NVARCHAR(50)   NOT NULL,
    "OcrCode"   NVARCHAR(20)   NOT NULL,
    "Descr"     NVARCHAR(200),
    PRIMARY KEY ("MapType", "MapKey")
)
@@
COMMENT ON TABLE "MTC_CA_C_OCR_MAP" IS '成本中心映射：PP05 生产入库结转贷 500101 时的车间成本中心（旧 0801 写死 A→P017、B→P016、C→P019）'
@@
UPSERT "MTC_CA_C_OCR_MAP" VALUES ('ITEMGRPTYPE', 'A', 'P017', '旧 0801 写死') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_OCR_MAP" VALUES ('ITEMGRPTYPE', 'B', 'P016', '旧 0801 写死') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_OCR_MAP" VALUES ('ITEMGRPTYPE', 'C', 'P019', '旧 0801 写死') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('WW_FEE_DIF', '0000-00', '9999-99', '140803', '委托加工物资-加工费暂估差异（PUR3 借、MR01 贷；旧 @MTC_MRVTYPE WW）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('PUR2_REV_ACCTS', '0000-00', '9999-99', ',1403,1405,1409,220202,', 'LIST', 'PUR2 冲回本期应付发票 / 贷项系统凭证中的这些科目（科目前 4 位或整个科目匹配；同旧 6101_1，Q23 先保留）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('PUR3_REV_ACCTS', '0000-00', '9999-99', ',140802,', 'LIST', 'PUR3 冲回本期应付发票 / 贷项系统凭证中的这些科目（同旧 6101_1）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('POST_WARN_IDS', '0000-00', '9999-99', ',POST-15,', 'LIST', '只警告、不阻断的计算后校验（其余 POST 一律阻断，用户 2026-10-14；POST-15 先只警告，用户 2026-10-30）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('INITPRICE_NEW_FROM', '0000-00', '9999-99', '2026-01-01', 'DATE', '这天及以后的收货 / 退货再用指定单价 U_InitPrice 时 POST-15 报出（期初和上线后系统 Price 有误才用，2026 年起应很少，用户 2026-10-30）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr") VALUES ('VAT_OUT', '0000-00', '9999-99', '22210106', '样品视同销售销项税（DN02 / DN04）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('SAMPLE_VAT_RATE', '0000-00', '9999-99', '0.13', 'DEC', '样品视同销售税率') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('SAMPLE_VAT_DIV', '0000-00', '9999-99', '1.13', 'DEC', '国内样品：销项税 = 数量 × 平台价 ÷ 本值 × 税率') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('SAMPLE_EXPORT_FACTOR', '0000-00', '9999-99', '1.5', 'DEC', '国外样品：销项税 = 成本 × 本值 × 税率') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('LEGACY_INITPRICE_DATE', '0000-00', '9999-99', '2024-12-31', 'STR', '该日期及以前的交货 / 退货按行上 U_InitPrice 取成本（旧 0801 写死）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('SUBFEE_ITEM', '0000-00', '9999-99', 'X0510001', 'STR', '委外加工费物料（应付暂估中单列为委外费用）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('COST_TRANSCODES', '0000-00', '9999-99', ',MR01,MR02,YF01,PP01,WW01,IO01,IO02,PP04,PP05,WW03,DN01,DN02,DN03,DN04,AR03,AR04,JZ01,JZ03,JZ04,PUR1,PUR2,PUR3,PUR4,PUR5,', 'LIST', '由成本模块生成的凭证代码：PP04 汇总 5101 时不再从总账取这些凭证（新框架自己生成），避免重复') WITH PRIMARY KEY
@@
-- Q14【建议，待确认】：YF01、MR02 是成本模块自己生成的凭证，新框架已从源单据取公摊材料和重估（SHARED / MRV），
-- 费用池再读已过账的 YF01、MR02 会重复计入，所以从默认值中去掉
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('EXP_JDT_TRANSCODES', '0000-00', '9999-99', ',,PP03,MR03,MR11,MR12,', 'LIST', '计入费用池的凭证代码，“,,” 表示空代码；旧 0311 还含 YF01、MR02，新框架从源单据取，去掉以免重复（Q14）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-08', 'POST', 180, '凭证借贷平衡、科目齐全', '每种凭证代码借贷相等；没有取不到科目的行', 'Y', 'S15') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-09', 'POST', 190, '库存科目总账 = 业务', '按存货科目比较与新框架期末金额（替代 JZ04 尾差凭证，Q15）。期初 / 本期 / 期末分开列示业务、财务和差额：业务期初取承接 / 上期结果，财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证（已过账或已在未清凭单的凭证代码不再加）；按参数 RECON_BLOCK_ON 判断（默认 CUR 本期差额，期初差额只列示；用户 2026-10-15；MTC_CA_F_RECON）', 'Y', 'S16') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-10', 'POST', 200, '发出商品对账', '140601 期末 = 期初 = 0（用户 2026-10-15）：月末 AR03 / AR04 把未开票部分全部计提，下月初 B1 自动冲销，所以业务端期初、期末都是 0，财务端含全部分录。本期构成：① 冲销上月计提（OJDT.StornoToTr 指向 AR03 / AR04）② 发货 DN01 ③ 样品转出 DN02 / DN04 ④ 发票 DN03 ⑤ 本月计提 AR03 / AR04，合计应为 0；另核对 ① = 上期末未开票（R_GOODS_OUT_BEG）、⑤ = 本期末未开票（R_GOODS_OUT），不一致单独列出（如旧框架按当前未清数量计提的上月金额）。差额 = 总账已过账 + 未清凭单 + 底稿中本期尚未过账的凭证 − 0；底稿分录按凭证代码 × 科目判断是否已过账，B1 自动冲销不算（2026-10-17）。手工调整（凭证代码不在 COST_TRANSCODES，参数 RECON_COSTONLY_AREAS 含 GOODS）单独列出、不算差异：期末差额扣除手工调整后应等于期初差额（用户 2026-10-17）。140601 差额不允许 0.01（用户 2026-11-01）：本期合计在 ±GOODS_TAIL_MAX（默认 1 元）以内的尾差由 P70 生成 JZ04 转入 TAIL_ADJ（640101 主营业务成本），本校验按差额 ≥ 0.005 报出', 'Y', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('GOODS_TAIL_MAX', '0000-00', '9999-99', '1', 'DEC', '发出商品尾差结转上限（元，含）：140601 本期参与对账的分录合计不为 0、在 ±本值以内的，P70 生成 JZ04 转入 TAIL_ADJ（640101），超过的由 POST-10 报出（用户 2026-11-01）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('GOODS_TAIL_MAX', 'PARAM', '尾差与校验', 315, '发出商品尾差结转上限', 'DEC', NULL, '元（含）：140601 本期合计在 ± 本值以内的转 640101（JZ04），如 1；超过的 POST-10 报出') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_RULE" ("RuleId", "Scene", "Title", "Descr", "Basis") VALUES ('TAIL-02', 'S12', '发出商品尾差结转', '140601 本期 = 冲销上月计提 + 发货 + 样品转出 + 发票 + 本月计提，应为 0；四舍五入留下的尾差（±GOODS_TAIL_MAX 以内）生成 JZ04：借 / 贷 TAIL_ADJ（640101），贷 / 借 140601，期末差额 = 期初差额；超过的不处理，POST-10 报出', '用户确认') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-11', 'POST', 210, '应付暂估对账', '220202（贷 − 借）按 U_VendorCode = 应付暂估（按供应商，同 C19）。期初 / 本期 / 期末分开列示业务、财务和差额：业务期初取承接 / 上期结果，财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证（已过账或已在未清凭单的凭证代码不再加）；按参数 RECON_BLOCK_ON 判断（默认 CUR 本期差额，期初差额只列示；用户 2026-10-15；MTC_CA_F_RECON）', 'Y', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-15', 'POST', 215, 'PUR1–PUR5 与业务端逐单据勾稽', 'PUR1–PUR5 把 B1 标准成本自动凭证（收货、退货、发票）在存货、应付暂估、加工费科目上的金额冲掉，按暂估口径（指定单价 U_InitPrice → 已确认价 → LineTotal）重记。逐张单据核对：系统凭证 + PUR 冲回 + PUR 重记（+ MR01）= 业务端（220202 = 暂估变动，存货 = 计入物料成本的金额，140802 = 加工费暂估，140803、价格差异科目、收货单其他科目 = 0）；另报没有系统凭证的单据、已全部开票但暂估没清零的行、PUR4 与订单加工费不一致、非库存收货行、本期新用指定单价的行、已过账 PUR 与底稿不一致（MTC_CA_F_PUR_DOC，用户 2026-10-30）。先只警告（参数 POST_WARN_IDS）', 'N', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-12', 'POST', 220, '销售成本取价', '本期开票 / 未开票交货找不到交货成本、或没有客户类型（取不到 6401 科目）的行', 'Y', 'S10') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-13', 'POST', 225, '生产在产品对账', '500101 的成本凭证 = 生产 / 包装 / 返工订单（WorType ≠ 50）在产品，不含加工费；本期的非成本凭证分录（手工凭证、单据自动凭证等）允许存在，单独列出、不算差异，期初按科目余额全额比较（参数 RECON_COSTONLY_AREAS）。期初 / 本期 / 期末分开列示业务、财务和差额：业务期初取承接 / 上期结果，财务期初 = 本期以前的总账 + 未清凭单；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证（已过账或已在未清凭单的凭证代码不再加）；按参数 RECON_BLOCK_ON 判断（默认 CUR 本期差额，期初差额只列示；用户 2026-10-15；MTC_CA_F_RECON）', 'Y', 'S5') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('RECON_COSTONLY_AREAS', '0000-00', '9999-99', ',WIP_PROD,GOODS,WW_MAT,', 'LIST', '财务对账中只比较成本凭证（COST_TRANSCODES）的对账项：其他分录（手工凭证、单据自动凭证等）允许存在，单独列出、不算差异；可选 STOCK、WIP_PROD、WW_MAT、WW_FEE、GOODS、AP（用户 2026-10-13；GOODS 发出商品手工调整不算差异，用户 2026-10-17）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('RECON_BLOCK_ON', '0000-00', '9999-99', 'CUR', 'STR', '财务对账（POST-06/09/10/11/13）按哪一列差额判断：CUR 本期差额（期初差额只列示）/ END 期末差额（用户 2026-10-15）') WITH PRIMARY KEY
