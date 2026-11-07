-- =====================================================================
-- 新成本框架 第 3 期：P71 发出商品与交货成本、P73 应付暂估、P74 应付暂估凭证、P70 凭证、P75 凭证与暂估校验（清单 S12、S15）
-- 替代：0801_TOOJDT 全部段、COJZ_01 / COJZ_03（JZ01 / JZ03 草稿）、6101_1（PUR1–PUR5，设计稿 4.6）、reports/CO6102、CO6103（未部署的草稿）。
-- 不替代：旧 JZ04（总账与业务的尾差）改为 POST-09 报出（Q15）；新 JZ04 只结转零库存物料 ±TAIL_MAX 以内的尾差（TAIL-01，Q32）。
-- 财务端与业务端对账：MTC_CA_F_RECON_LEDGER / MTC_CA_F_RECON / MTC_CA_F_RECON_STATUS，两个口径（用户 2026-10-13），P75 按口径写 POST-06/09/10/11/13。
-- 存货科目：OGAR 中物料组在该年度的 StockAct（同旧 0801）；订单在产品科目：WorType 50 → WW_MAT，其余 → WIP_PROD。
-- =====================================================================

-- 发出商品函数 MTC_CA_F_GOODS_OPEN / MTC_CA_F_GOODS_MOVE 在 08_precheck.sql（PRE-27 也用，08 先部署）
-- P71：发出商品（截至期末已交货未开票，口径同 CO6103）和交货 / 退货行单位成本（DN03、AR03/AR04 共用）
-- 单位成本优先级：LEGACY_INITPRICE_DATE 及以前的单据取 U_InitPrice → 本次运行 → 以前账期新框架结果 → 旧 0302
--   （旧 0302 只取 BOOTSTRAP_FC 及以前的账期，与 P30 SRT 一致；并行期旧框架算出的成本不用，2026-11-02）
-- 金额（用户 2026-10-15，尾差同应付暂估 Q27）：每条交货 / 独立退货行 行金额 = ROUND(DocQty × 单位成本, 2)；
--   每笔消耗（F_GOODS_MOVE）金额 = ROUND(Qty × 单位成本, 2)，退货用退货行自己的单位成本（与 DN01 冲回同额）；
--   行全部消耗完时，尾差 = 行金额 − 已消耗金额合计，本期新出现的尾差（期末 − 期初）作为 ADJ 由 DN03 转出；
--   发出商品余额 = 行金额 − 已消耗金额 − 尾差，与 DN01 − DN03 逐行相等。本期消耗和 ADJ 写 R_GOODS_MOVE，P70 的 DN03 从它取
CREATE OR REPLACE PROCEDURE "MTC_CA_P71_SALES" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE legacy DATE;
    DECLARE boot NVARCHAR(10);
    DECLARE smpSt NVARCHAR(500);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    boot := "MTC_CA_F_PARAM"('BOOTSTRAP_FC', :fc);   -- 旧框架成本只取承接账期及以前（2026-11-02）
    smpSt := IFNULL("MTC_CA_F_PARAM"('SAMPLE_SALTYPES', :fc), ',样品销售,');   -- 样品销售的销售订单类型（参数，2026-10-27）
    legacy := TO_DATE(IFNULL("MTC_CA_F_PARAM"('LEGACY_INITPRICE_DATE', :fc), '1900-01-01'));

    INSERT INTO "MTC_CA_R_GOODS_OUT" ("FcCode", "RunType", "Scenario", "RunId", "ObjType", "DocEntry", "LineNum", "DocDate", "CardCode",
                                      "CustType", "IsSample", "ItemCode", "DocQty", "InvQty", "RetQty", "OpenQty")
    SELECT :fc, :rt, :scen, :RunId, "ObjType", "DocEntry", "LineNum", "DocDate", "CardCode",
           "CustType", "IsSample", "ItemCode", "DocQty", "InvQty", "RetQty", "OpenQty"
      FROM "MTC_CA_F_GOODS_OPEN"(:d1);
    RowCnt := ::ROWCOUNT;

    -- 期初（上期末）发出商品：财务对账列示期初（用户 2026-10-15）
    INSERT INTO "MTC_CA_R_GOODS_OUT_BEG" ("FcCode", "RunType", "Scenario", "RunId", "ObjType", "DocEntry", "LineNum", "DocDate", "CardCode",
                                          "CustType", "IsSample", "ItemCode", "DocQty", "InvQty", "RetQty", "OpenQty")
    SELECT :fc, :rt, :scen, :RunId, "ObjType", "DocEntry", "LineNum", "DocDate", "CardCode",
           "CustType", "IsSample", "ItemCode", "DocQty", "InvQty", "RetQty", "OpenQty"
      FROM "MTC_CA_F_GOODS_OPEN"(ADD_DAYS(:d0, -1));

    -- 范围：期初、期末未清的行 + 本期有消耗（开票 / 贷项 / 退货，含取消单）的行；
    -- 需要单位成本的还有这些行截至期末的退货行本身（退货按自己的成本冲回 140601）
    mvAll = SELECT * FROM "MTC_CA_F_GOODS_MOVE"(:d1);
    scope = SELECT "ObjType", "DocEntry", "LineNum" FROM "MTC_CA_R_GOODS_OUT" WHERE "RunId" = :RunId
            UNION
            SELECT "ObjType", "DocEntry", "LineNum" FROM "MTC_CA_R_GOODS_OUT_BEG" WHERE "RunId" = :RunId
            UNION
            SELECT "SrcObj", "SrcEntry", "SrcLine" FROM :mvAll WHERE "DocDate" BETWEEN :d0 AND :d1;
    mv = SELECT M.* FROM :mvAll M
           JOIN :scope S ON S."ObjType" = M."SrcObj" AND S."DocEntry" = M."SrcEntry" AND S."LineNum" = M."SrcLine";
    keys = SELECT "ObjType", "DocEntry", "LineNum" FROM :scope
           UNION
           SELECT '16', "DocEntry", "LineNum" FROM :mv WHERE "K" = 'RET';
    hdr = SELECT '15' AS "ObjType", D."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate", D."U_InitPrice",
                 D."Quantity" AS "DocQty", M."U_SalOrdType"
            FROM "ODLN" M JOIN "DLN1" D ON M."DocEntry" = D."DocEntry"
          UNION ALL
          SELECT '16', D."DocEntry", D."LineNum", TO_DATE(M."DocDate"), D."U_InitPrice", -D."Quantity", M."U_SalOrdType"
            FROM "ORDN" M JOIN "RDN1" D ON M."DocEntry" = D."DocEntry";
    cur = SELECT S."ObjType", S."DocEntry", S."LineNum", SUM(L."Amount") / NULLIF(SUM(L."Qty"), 0) AS "UC"
            FROM "MTC_CA_S_LINE" S JOIN "MTC_CA_R_LINE" L ON L."RunId" = S."RunId" AND L."LineId" = S."LineId"
           WHERE S."RunId" = :RunId AND S."ObjType" IN ('15', '16')
           GROUP BY S."ObjType", S."DocEntry", S."LineNum";
    prv = SELECT "ObjType", "DocEntry", "LineNum", "UC", "FcCode" FROM (
            SELECT S."ObjType", S."DocEntry", S."LineNum", S."FcCode", SUM(L."Amount") / NULLIF(SUM(L."Qty"), 0) AS "UC",
                   ROW_NUMBER() OVER (PARTITION BY S."ObjType", S."DocEntry", S."LineNum" ORDER BY S."FcCode" DESC) AS "Rn"
              FROM "MTC_CA_S_LINE" S
              JOIN "MTC_CA_RUN" U ON U."RunId" = S."RunId" AND U."Status" = 'OK' AND U."RunType" = 'F'
              JOIN "MTC_CA_R_LINE" L ON L."RunId" = S."RunId" AND L."LineId" = S."LineId"
             WHERE S."ObjType" IN ('15', '16') AND S."FcCode" < :fc
             GROUP BY S."ObjType", S."DocEntry", S."LineNum", S."FcCode") WHERE "Rn" = 1;
    old = SELECT "ObjType", "DocEntry", "LineNum", SUM("Amount") / NULLIF(SUM("Quantity"), 0) AS "UC"
            FROM "MTC_COST_0302_INVNTDETAIL1"
           WHERE "CostCode" = '20' AND "ObjType" IN ('15', '16') AND "FcCode" <= :boot
           GROUP BY "ObjType", "DocEntry", "LineNum";

    INSERT INTO "MTC_CA_R_DNCOST" ("FcCode", "RunType", "Scenario", "RunId", "ObjType", "DocEntry", "LineNum", "UnitCost", "CostSrc")
    SELECT :fc, :rt, :scen, :RunId, K."ObjType", K."DocEntry", K."LineNum",
           CASE WHEN H."DocDate" <= :legacy THEN H."U_InitPrice" ELSE COALESCE(C."UC", P."UC", O."UC") END,
           CASE WHEN H."DocDate" <= :legacy THEN 'U_InitPrice'
                WHEN C."UC" IS NOT NULL THEN '本期' WHEN P."UC" IS NOT NULL THEN '新框架 ' || P."FcCode"
                WHEN O."UC" IS NOT NULL THEN '旧0302' END
      FROM :keys K
      LEFT JOIN :hdr H ON H."ObjType" = K."ObjType" AND H."DocEntry" = K."DocEntry" AND H."LineNum" = K."LineNum"
      LEFT JOIN :cur C ON C."ObjType" = K."ObjType" AND C."DocEntry" = K."DocEntry" AND C."LineNum" = K."LineNum"
      LEFT JOIN :prv P ON P."ObjType" = K."ObjType" AND P."DocEntry" = K."DocEntry" AND P."LineNum" = K."LineNum"
      LEFT JOIN :old O ON O."ObjType" = K."ObjType" AND O."DocEntry" = K."DocEntry" AND O."LineNum" = K."LineNum";

    -- 逐行：行金额、截至上期末 / 期末的消耗数量和金额、尾差
    salType = SELECT "Name", MAX("U_CustType") AS "CustType", MAX("U_BusiType") AS "BusiType"
                FROM "@MTC_SALORDTYPE" GROUP BY "Name";
    ln = SELECT S."ObjType", S."DocEntry", S."LineNum", H."DocQty", C."UnitCost",
                ROUND(H."DocQty" * C."UnitCost", 2) AS "LineAmt", T."CustType",
                CASE WHEN LOCATE(:smpSt, ',' || T."BusiType" || ',') > 0 THEN 'Y' ELSE 'N' END AS "IsSample"
           FROM :scope S
           JOIN :hdr H ON H."ObjType" = S."ObjType" AND H."DocEntry" = S."DocEntry" AND H."LineNum" = S."LineNum"
           LEFT JOIN "MTC_CA_R_DNCOST" C ON C."RunId" = :RunId AND C."ObjType" = S."ObjType" AND C."DocEntry" = S."DocEntry" AND C."LineNum" = S."LineNum"
           LEFT JOIN :salType T ON T."Name" = H."U_SalOrdType";
    ev = SELECT M."SrcObj", M."SrcEntry", M."SrcLine", M."K", M."DocEntry", M."LineNum", M."DocDate", M."Qty",
                CASE WHEN M."K" = 'RET' THEN COALESCE(RC."UnitCost", L."UnitCost") ELSE L."UnitCost" END AS "UnitCost",
                ROUND(M."Qty" * CASE WHEN M."K" = 'RET' THEN COALESCE(RC."UnitCost", L."UnitCost") ELSE L."UnitCost" END, 2) AS "Amount",
                T."CustType", CASE WHEN LOCATE(:smpSt, ',' || T."BusiType" || ',') > 0 OR L."IsSample" = 'Y' THEN 'Y' ELSE 'N' END AS "IsSample"
           FROM :mv M
           JOIN :ln L ON L."ObjType" = M."SrcObj" AND L."DocEntry" = M."SrcEntry" AND L."LineNum" = M."SrcLine"
           LEFT JOIN "MTC_CA_R_DNCOST" RC ON M."K" = 'RET' AND RC."RunId" = :RunId AND RC."ObjType" = '16'
                                         AND RC."DocEntry" = M."DocEntry" AND RC."LineNum" = M."LineNum"
           LEFT JOIN :salType T ON T."Name" = M."U_SalOrdType";
    bal = SELECT L."ObjType", L."DocEntry", L."LineNum", L."DocQty", L."LineAmt", L."CustType", L."IsSample",
                 IFNULL(SUM(E."Amount"), 0) AS "A1", IFNULL(SUM(CASE WHEN E."DocDate" < :d0 THEN E."Amount" END), 0) AS "A0",
                 IFNULL(SUM(E."Qty"), 0) AS "Q1", IFNULL(SUM(CASE WHEN E."DocDate" < :d0 THEN E."Qty" END), 0) AS "Q0"
            FROM :ln L
            LEFT JOIN :ev E ON E."SrcObj" = L."ObjType" AND E."SrcEntry" = L."DocEntry" AND E."SrcLine" = L."LineNum"
           GROUP BY L."ObjType", L."DocEntry", L."LineNum", L."DocQty", L."LineAmt", L."CustType", L."IsSample";
    bal2 = SELECT B.*,
                  CASE WHEN ABS(B."DocQty" - B."Q1") < 0.000001 THEN B."LineAmt" - B."A1" ELSE 0 END AS "R1",
                  CASE WHEN ABS(B."DocQty" - B."Q0") < 0.000001 THEN B."LineAmt" - B."A0" ELSE 0 END AS "R0"
             FROM :bal B;

    INSERT INTO "MTC_CA_R_GOODS_MOVE" ("FcCode", "RunType", "Scenario", "RunId", "SrcObj", "SrcEntry", "SrcLine", "K", "DocEntry", "LineNum",
                                       "DocDate", "CustType", "IsSample", "Qty", "UnitCost", "Amount")
    SELECT :fc, :rt, :scen, :RunId, "SrcObj", "SrcEntry", "SrcLine", "K", "DocEntry", "LineNum",
           "DocDate", "CustType", "IsSample", "Qty", "UnitCost", "Amount"
      FROM :ev WHERE "DocDate" BETWEEN :d0 AND :d1
    UNION ALL
    SELECT :fc, :rt, :scen, :RunId, "ObjType", "DocEntry", "LineNum", 'ADJ', "DocEntry", "LineNum",
           :d1, "CustType", "IsSample", 0, NULL, "R1" - "R0"
      FROM :bal2 WHERE "LineAmt" IS NOT NULL AND "R1" - "R0" <> 0;

    UPDATE T0 SET T0."UnitCost" = C."UnitCost", T0."CostSrc" = C."CostSrc", T0."CostAmt" = B."LineAmt" - B."A1" - B."R1"
      FROM "MTC_CA_R_GOODS_OUT" T0
      JOIN "MTC_CA_R_DNCOST" C ON C."RunId" = T0."RunId" AND C."ObjType" = T0."ObjType" AND C."DocEntry" = T0."DocEntry" AND C."LineNum" = T0."LineNum"
      JOIN :bal2 B ON B."ObjType" = T0."ObjType" AND B."DocEntry" = T0."DocEntry" AND B."LineNum" = T0."LineNum"
     WHERE T0."RunId" = :RunId;
    UPDATE T0 SET T0."UnitCost" = C."UnitCost", T0."CostSrc" = C."CostSrc", T0."CostAmt" = B."LineAmt" - B."A0" - B."R0"
      FROM "MTC_CA_R_GOODS_OUT_BEG" T0
      JOIN "MTC_CA_R_DNCOST" C ON C."RunId" = T0."RunId" AND C."ObjType" = T0."ObjType" AND C."DocEntry" = T0."DocEntry" AND C."LineNum" = T0."LineNum"
      JOIN :bal2 B ON B."ObjType" = T0."ObjType" AND B."DocEntry" = T0."DocEntry" AND B."LineNum" = T0."LineNum"
     WHERE T0."RunId" = :RunId;
END
@@
-- P73：应付暂估（截至期末已收货未开票，口径同 CO6102）。由 S_AP_MOVE 汇总，与 PUR1–PUR4 凭证同一口径，
-- 所以 220202 按供应商 = 本表合计（POST-11）
CREATE OR REPLACE PROCEDURE "MTC_CA_P73_AP_ACCR" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);

    INSERT INTO "MTC_CA_R_AP_ACCR" ("FcCode", "RunType", "Scenario", "RunId", "ObjType", "DocEntry", "LineNum", "DocDate", "CardCode",
                                    "AccrType", "ItemCode", "DocQty", "InvQty", "RetQty", "OpenQty", "UnitPrice", "OpenAmt")
    SELECT :fc, :rt, :scen, :RunId, "BaseObj", "BaseEntry", "BaseLine", MAX("BaseDate"), MAX("CardCode"),
           MAX("AccrType"), MAX("ItemCode"), MAX("BaseSign" * "BaseQty"),
           SUM(CASE WHEN "MoveType" = 'INV' THEN -"Qty" ELSE 0 END),
           SUM(CASE WHEN "MoveType" = 'RET' THEN -"Qty" ELSE 0 END),
           MAX("BaseSign") * SUM("Qty"), MAX("UnitPrice"), SUM("AccrAmt")
      FROM "MTC_CA_S_AP_MOVE"
     WHERE "RunId" = :RunId
     GROUP BY "BaseObj", "BaseEntry", "BaseLine"
    HAVING ABS(SUM("Qty")) > 0.000001 OR ABS(SUM("AccrAmt")) >= 0.005;
    RowCnt := ::ROWCOUNT;
END
@@
-- P74：应付暂估凭证 PUR1–PUR5（替代 6101_1，设计稿 4.6；Q16、Q23–Q28）。写 R_JDT_SRC，由 P70 一起汇总成 R_JDT。
--   PUR5 冲回本期收货 / 退货（20/21）系统凭证的全部科目（同旧）
--   PUR1 材料、PUR4 委外加工费：本期暂估、退货及其取消（S_AP_MOVE 的 ACCR / RET）：借存货 / 140802，贷 220202（按供应商）
--   PUR2 材料、PUR3 委外加工费：冲回本期应付发票 / 贷项系统凭证中参数 PUR2_REV_ACCTS / PUR3_REV_ACCTS 科目的行（Q23 先保留旧口径）；
--        本期开票及其取消（INV）：借 220202 = 冲回的暂估；借存货 / 140803 = 发票 − 暂估
--   不基于收货 / 退货的发票由 PRE-20 报出（Q24 用户说明不会出现）；非库存物料（加工费物料以外）不暂估，按发票的系统凭证处理（Q25）
CREATE OR REPLACE PROCEDURE "MTC_CA_P74_AP_JDT" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE apAcct NVARCHAR(15); DECLARE wwFee NVARCHAR(15); DECLARE wwDif NVARCHAR(15);
    DECLARE rev2 NVARCHAR(500); DECLARE rev3 NVARCHAR(500);
    DECLARE maxId BIGINT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    apAcct := "MTC_CA_F_ACCT"('AP_ACCRUAL', :fc);
    wwFee := "MTC_CA_F_ACCT"('WW_FEE', :fc);
    wwDif := "MTC_CA_F_ACCT"('WW_FEE_DIF', :fc);
    rev2 := IFNULL("MTC_CA_F_PARAM"('PUR2_REV_ACCTS', :fc), ',1403,1405,1409,220202,');
    rev3 := IFNULL("MTC_CA_F_PARAM"('PUR3_REV_ACCTS', :fc), ',140802,');

    stockAct = SELECT TO_NVARCHAR("ItmsGrpCod") AS "ItmsGrpCod", MAX("StockAct") AS "Acct"
                 FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4) GROUP BY "ItmsGrpCod";
    mv = SELECT A.*, SA."Acct" AS "StockAct", A."ObjType" || '-' || A."DocEntry" || '-' || A."LineNum" AS "Key"
           FROM "MTC_CA_S_AP_MOVE" A
           LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = A."RunId" AND I."ItemCode" = A."ItemCode"
           LEFT JOIN :stockAct SA ON SA."ItmsGrpCod" = I."ItmsGrpCod"
          WHERE A."RunId" = :RunId AND A."DocDate" BETWEEN :d0 AND :d1;
    gl = SELECT TO_NVARCHAR(H."TransType") AS "TransType", J."TransId", J."Line_ID", J."Account", J."Debit" - J."Credit" AS "Amt",
                J."U_VendorCode" AS "Vendor"
           FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
          WHERE H."RefDate" BETWEEN :d0 AND :d1 AND H."TransType" IN ('18', '19', '20', '21');

    src = -- PUR5：收货 / 退货系统凭证全部反向
          SELECT CAST('PUR5' AS NVARCHAR(10)) AS "TransCode", CAST("Account" AS NVARCHAR(15)) AS "AcctCode",
                 CAST("Vendor" AS NVARCHAR(50)) AS "VendorCode", CAST(-ROUND("Amt", 2) AS DECIMAL(19,2)) AS "Amount",
                 CAST('GL' AS NVARCHAR(10)) AS "SrcType", CAST("TransId" || '-' || "Line_ID" AS NVARCHAR(100)) AS "SrcKey"
            FROM :gl WHERE "TransType" IN ('20', '21')
          -- PUR1 / PUR4：暂估、退货
          UNION ALL
          SELECT CASE WHEN "AccrType" = 'MAT' THEN 'PUR1' ELSE 'PUR4' END, CASE WHEN "AccrType" = 'MAT' THEN "StockAct" ELSE :wwFee END,
                 NULL, "AccrAmt", 'DOC', "Key"
            FROM :mv WHERE "MoveType" IN ('ACCR', 'RET')
          UNION ALL
          SELECT CASE WHEN "AccrType" = 'MAT' THEN 'PUR1' ELSE 'PUR4' END, :apAcct, "CardCode", -"AccrAmt", 'DOC', "Key"
            FROM :mv WHERE "MoveType" IN ('ACCR', 'RET')
          -- PUR2 / PUR3：冲回发票系统凭证的指定科目
          UNION ALL
          SELECT 'PUR2', "Account", "Vendor", -ROUND("Amt", 2), 'GL', "TransId" || '-' || "Line_ID"
            FROM :gl WHERE "TransType" IN ('18', '19')
             AND (LOCATE(:rev2, ',' || LEFT("Account", 4) || ',') > 0 OR LOCATE(:rev2, ',' || "Account" || ',') > 0)
          UNION ALL
          SELECT 'PUR3', "Account", "Vendor", -ROUND("Amt", 2), 'GL', "TransId" || '-' || "Line_ID"
            FROM :gl WHERE "TransType" IN ('18', '19')
             AND (LOCATE(:rev3, ',' || LEFT("Account", 4) || ',') > 0 OR LOCATE(:rev3, ',' || "Account" || ',') > 0)
          -- PUR2 / PUR3：开票冲回暂估（借 220202）、发票差异（借存货 / 140803）
          UNION ALL
          SELECT CASE WHEN "AccrType" = 'MAT' THEN 'PUR2' ELSE 'PUR3' END, :apAcct, "CardCode", -"AccrAmt", 'DOC', "Key"
            FROM :mv WHERE "MoveType" = 'INV'
          UNION ALL
          SELECT CASE WHEN "AccrType" = 'MAT' THEN 'PUR2' ELSE 'PUR3' END, CASE WHEN "AccrType" = 'MAT' THEN "StockAct" ELSE :wwDif END,
                 NULL, IFNULL("DocAmt", 0) + "AccrAmt", 'DOC', "Key"
            FROM :mv WHERE "MoveType" = 'INV';

    SELECT IFNULL(MAX("SrcId"), 0) INTO maxId FROM "MTC_CA_R_JDT_SRC" WHERE "RunId" = :RunId;
    INSERT INTO "MTC_CA_R_JDT_SRC" ("FcCode", "RunType", "Scenario", "RunId", "SrcId", "TransCode", "AcctCode", "OcrCode", "Project",
                                    "Amount", "SrcType", "SrcKey", "VendorCode")
    SELECT :fc, :rt, :scen, :RunId, :maxId + ROW_NUMBER() OVER (ORDER BY "TransCode", "SrcType", "SrcKey", "AcctCode"),
           "TransCode", "AcctCode", NULL, NULL, "Amount", "SrcType", "SrcKey", "VendorCode"
      FROM :src WHERE "Amount" <> 0;
    RowCnt := ::ROWCOUNT;
END
@@
-- P70：凭证。各段规则见行内注释，沿用旧 0801；金额取 R_LINE / R_ORDER 等新框架结果
CREATE OR REPLACE PROCEDURE "MTC_CA_P70_JDT" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE wipProd NVARCHAR(15); DECLARE wwMat NVARCHAR(15); DECLARE wwFee NVARCHAR(15);
    DECLARE mfgAcct NVARCHAR(15); DECLARE labAcct NVARCHAR(15); DECLARE mfgp NVARCHAR(15);
    DECLARE clsProd NVARCHAR(15); DECLARE clsWw NVARCHAR(15); DECLARE goods NVARCHAR(15);
    DECLARE cogsDom NVARCHAR(15); DECLARE cogsExp NVARCHAR(15); DECLARE sample NVARCHAR(15); DECLARE vatOut NVARCHAR(15);
    DECLARE tailAcct NVARCHAR(15);
    DECLARE vatRate DECIMAL(19,6); DECLARE vatDiv DECIMAL(19,6); DECLARE expFactor DECIMAL(19,6);
    DECLARE costCodes NVARCHAR(500);
    DECLARE wwWt NVARCHAR(200); DECLARE smpSt NVARCHAR(500); DECLARE custDom NVARCHAR(50); DECLARE custExp NVARCHAR(50);
    DECLARE maxId BIGINT;
    DECLARE costOnly NVARCHAR(200); DECLARE gTailMax DECIMAL(19,2); DECLARE gRes DECIMAL(19,2); DECLARE gOk INT; DECLARE nJz4 INT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    -- 业务口径参数（2026-10-27 从代码中的固定值改为参数）
    wwWt := IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', :fc), ',50,');
    smpSt := IFNULL("MTC_CA_F_PARAM"('SAMPLE_SALTYPES', :fc), ',样品销售,');
    custDom := IFNULL("MTC_CA_F_PARAM"('CUST_DOM', :fc), '国内客户');
    custExp := IFNULL("MTC_CA_F_PARAM"('CUST_EXP', :fc), '国外客户');
    wipProd := "MTC_CA_F_ACCT"('WIP_PROD', :fc);      wwMat := "MTC_CA_F_ACCT"('WW_MAT', :fc);
    wwFee := "MTC_CA_F_ACCT"('WW_FEE', :fc);          mfgAcct := "MTC_CA_F_ACCT"('MFG_SHARED', :fc);
    labAcct := "MTC_CA_F_ACCT"('LAB_EXP', :fc);       mfgp := IFNULL("MTC_CA_F_ACCT"('MFG_EXP_PREFIX', :fc), '5101');
    clsProd := "MTC_CA_F_ACCT"('CLOSE_DIF_PROD', :fc); clsWw := "MTC_CA_F_ACCT"('CLOSE_DIF_WW', :fc);
    goods := "MTC_CA_F_ACCT"('GOODS_ISSUED', :fc);    cogsDom := "MTC_CA_F_ACCT"('COGS_DOM', :fc);
    cogsExp := "MTC_CA_F_ACCT"('COGS_EXP', :fc);      sample := "MTC_CA_F_ACCT"('SAMPLE', :fc);
    vatOut := "MTC_CA_F_ACCT"('VAT_OUT', :fc);
    tailAcct := IFNULL("MTC_CA_F_ACCT"('TAIL_ADJ', :fc), :cogsDom);
    vatRate := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('SAMPLE_VAT_RATE', :fc), '0.13'), 19, 6);
    vatDiv := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('SAMPLE_VAT_DIV', :fc), '1.13'), 19, 6);
    expFactor := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('SAMPLE_EXPORT_FACTOR', :fc), '1.5'), 19, 6);
    costCodes := IFNULL("MTC_CA_F_PARAM"('COST_TRANSCODES', :fc), ',');
    costOnly := IFNULL("MTC_CA_F_PARAM"('RECON_COSTONLY_AREAS', :fc), ',WIP_PROD,GOODS,WW_MAT,');
    gTailMax := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('GOODS_TAIL_MAX', :fc), '1'), 19, 2);

    stockAct =SELECT TO_NVARCHAR("ItmsGrpCod") AS "ItmsGrpCod", MAX("StockAct") AS "Acct"
                 FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4) GROUP BY "ItmsGrpCod";
    salType = SELECT "Name", MAX("U_CustType") AS "CustType", MAX("U_BusiType") AS "BusiType"
                FROM "@MTC_SALORDTYPE" GROUP BY "Name";
    ord = SELECT O."OrderType", O."OrderEntry", O."WorType", O."RecvQty", O."AllocMfg", O."AllocLab", O."CloseDifAmt",
                 CASE WHEN LOCATE(:wwWt, ',' || O."WorType" || ',') > 0 THEN 'Y' ELSE 'N' END AS "IsWw",   -- 委外工单（WW_WORTYPES）
                 CASE WHEN LOCATE(:wwWt, ',' || O."WorType" || ',') > 0 THEN :wwMat ELSE :wipProd END AS "WipAcct", M."OcrCode" AS "ShopOcr"
            FROM "MTC_CA_R_ORDER" O
            LEFT JOIN "OITM" I ON I."ItemCode" = O."ItemCode"
            LEFT JOIN "OITB" B ON B."ItmsGrpCod" = I."ItmsGrpCod"
            LEFT JOIN "MTC_CA_C_OCR_MAP" M ON M."MapType" = 'ITEMGRPTYPE' AND M."MapKey" = B."U_ItemGrpType"
           WHERE O."RunId" = :RunId;
    fee = SELECT "OrderType", "OrderEntry", ROUND("CarSub", 2) AS "Car", ROUND("ClsSub", 2) AS "Cls"
            FROM "MTC_CA_R_ORDER_MAT" WHERE "RunId" = :RunId AND "ItemCode" = '#SUBFEE';
    base = SELECT L."LineId", L."ItemCode", L."TransCode", L."Cat", L."Amount", L."Qty", L."OrderType", L."OrderEntry",
                  S."ObjType", S."DocEntry", S."LineNum", S."AcctCode", S."OcrCode", SA."Acct" AS "StockAct", S."Src"
             FROM "MTC_CA_R_LINE" L
             JOIN "MTC_CA_S_LINE" S ON S."RunId" = L."RunId" AND S."LineId" = L."LineId"
             LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = L."RunId" AND I."ItemCode" = L."ItemCode"
             LEFT JOIN :stockAct SA ON SA."ItmsGrpCod" = I."ItmsGrpCod"
            WHERE L."RunId" = :RunId AND L."Amount" <> 0;
    prj = SELECT '59' AS "ObjType", "DocEntry", "LineNum", "Project" FROM "IGN1"
          UNION ALL SELECT '60', "DocEntry", "LineNum", "Project" FROM "IGE1";
    smp = SELECT '15' AS "ObjType", M."DocEntry", T."CustType", M."U_OcrCode" FROM "ODLN" M JOIN :salType T ON T."Name" = M."U_SalOrdType" WHERE LOCATE(:smpSt, ',' || T."BusiType" || ',') > 0
          UNION ALL
          SELECT '16', M."DocEntry", T."CustType", M."U_OcrCode" FROM "ORDN" M JOIN :salType T ON T."Name" = M."U_SalOrdType" WHERE LOCATE(:smpSt, ',' || T."BusiType" || ',') > 0;
    ptp = SELECT T1."U_ItemCode", MAX(T1."U_Price") AS "Price"
            FROM "@MTC_PTPRICE" T0 JOIN "@MTC_PTPRICE1" T1 ON T0."DocEntry" = T1."DocEntry"
           WHERE T0."Canceled" = 'N' AND T0."U_FcCode" = :fc GROUP BY T1."U_ItemCode";

    -- 本期开票 / 贷项的销售成本（DN03）：P71 已按 数量 × 所基于交货 / 退货行的单位成本算好（取消单经原单找交货），
    -- 另有交货 / 退货行全部消耗完时的尾差 ADJ（用户 2026-10-15）；样品（交货或发票是样品销售）不结转
    -- 来源键：INV / RIN-单据-行；尾差记在交货 / 退货行上（15 / 16-DocEntry-LineNum），执行台“凭证”来源明细可直接打开
    invCost = SELECT CASE WHEN "K" = 'ADJ' THEN "SrcObj" ELSE "K" END AS "K", "DocEntry", "LineNum", "CustType", "Amount" AS "Cost"
                FROM "MTC_CA_R_GOODS_MOVE"
               WHERE "RunId" = :RunId AND "K" IN ('INV', 'RIN', 'ADJ') AND "IsSample" = 'N';

    src = -- MR01 委外加工费发票差异（P20_AP 从发票计算，替代 @MTC_OMRV WW 单）：借产品存货、贷 140803
          SELECT CAST('MR01' AS NVARCHAR(10)) AS "TransCode", CAST("StockAct" AS NVARCHAR(15)) AS "AcctCode",
                 CAST(NULL AS NVARCHAR(20)) AS "OcrCode", CAST(NULL AS NVARCHAR(20)) AS "Project",
                 CAST("Amount" AS DECIMAL(19,2)) AS "Amount", CAST('LINE' AS NVARCHAR(10)) AS "SrcType",
                 CAST("LineId" AS NVARCHAR(100)) AS "SrcKey"
            FROM :base WHERE "Src" = 'APDIF'
          UNION ALL
          SELECT 'MR01', "AcctCode", NULL, NULL, -"Amount", 'LINE', TO_NVARCHAR("LineId") FROM :base WHERE "Src" = 'APDIF'
          -- MR02 手工重估：借重估科目 −金额、贷存货 −金额。只取 MRV1：MRV2 是旧 0501 写的 0 数量尾差，新框架由 TAIL-01 / JZ04 处理，
          -- 业务端（P20_LINE）也只收 MRV1，再读 MRV2 会让存货科目总账与业务差一张 MRV2（POST-09，2026-10-17）
          UNION ALL
          SELECT 'MR02', T1."U_AcctCode", NULL, NULL, -ROUND(T1."U_Amount", 2), 'OMRV', T1."DocEntry" || '-' || T1."LineId"
            FROM "@MTC_OMRV" T0 JOIN "@MTC_OMRV1" T1 ON T0."DocEntry" = T1."DocEntry"
           WHERE T0."U_BaseType" = 'MRV1' AND IFNULL(T0."Canceled", 'N') = 'N' AND T0."U_DocDate" BETWEEN :d0 AND :d1
          UNION ALL
          SELECT 'MR02', T1."U_StockCode", NULL, NULL, ROUND(T1."U_Amount", 2), 'OMRV', T1."DocEntry" || '-' || T1."LineId"
            FROM "@MTC_OMRV" T0 JOIN "@MTC_OMRV1" T1 ON T0."DocEntry" = T1."DocEntry"
           WHERE T0."U_BaseType" = 'MRV1' AND IFNULL(T0."Canceled", 'N') = 'N' AND T0."U_DocDate" BETWEEN :d0 AND :d1
          -- YF01 其他出入库（I04 / O04）：借行上科目、贷存货
          UNION ALL
          SELECT 'YF01', B."AcctCode", B."OcrCode", P."Project", -B."Amount", 'LINE', TO_NVARCHAR(B."LineId")
            FROM :base B LEFT JOIN :prj P ON P."ObjType" = B."ObjType" AND P."DocEntry" = B."DocEntry" AND P."LineNum" = B."LineNum"
           WHERE B."TransCode" IN ('I04', 'O04')
          UNION ALL
          SELECT 'YF01', B."StockAct", NULL, NULL, B."Amount", 'LINE', TO_NVARCHAR(B."LineId") FROM :base B WHERE B."TransCode" IN ('I04', 'O04')
          -- PP01 生产领料（O03 / O07）、WW01 委外领料（O08 / O09）：借订单在产品科目、贷存货
          UNION ALL
          SELECT CASE WHEN B."TransCode" IN ('O08', 'O09') THEN 'WW01' ELSE 'PP01' END, O."WipAcct", NULL, NULL, -B."Amount", 'LINE', TO_NVARCHAR(B."LineId")
            FROM :base B JOIN :ord O ON O."OrderType" = B."OrderType" AND O."OrderEntry" = B."OrderEntry"
           WHERE B."Cat" IN ('ISSUE', 'RTN304') AND B."TransCode" IN ('O03', 'O07', 'O08', 'O09')
          UNION ALL
          SELECT CASE WHEN B."TransCode" IN ('O08', 'O09') THEN 'WW01' ELSE 'PP01' END, B."StockAct", NULL, NULL, B."Amount", 'LINE', TO_NVARCHAR(B."LineId")
            FROM :base B
           WHERE B."Cat" IN ('ISSUE', 'RTN304') AND B."TransCode" IN ('O03', 'O07', 'O08', 'O09')
          -- IO02 形态转换：借 A 存货、贷 B 存货
          UNION ALL
          SELECT 'IO02', B."StockAct", NULL, NULL, B."Amount", 'LINE', TO_NVARCHAR(B."LineId") FROM :base B WHERE B."TransCode" IN ('I05', 'O05')
          -- IO01 盘点：借行上科目、贷存货（盘盈相反）
          UNION ALL
          SELECT 'IO01', B."AcctCode", B."OcrCode", NULL, -B."Amount", 'LINE', TO_NVARCHAR(B."LineId") FROM :base B WHERE B."TransCode" IN ('I10', 'O10')
          UNION ALL
          SELECT 'IO01', B."StockAct", NULL, NULL, B."Amount", 'LINE', TO_NVARCHAR(B."LineId") FROM :base B WHERE B."TransCode" IN ('I10', 'O10')
          -- PP05 生产入库 / WW03 委外入库：借存货、贷订单在产品科目
          UNION ALL
          SELECT CASE WHEN O."IsWw" = 'Y' THEN 'WW03' ELSE 'PP05' END, B."StockAct", NULL, NULL, B."Amount", 'LINE', TO_NVARCHAR(B."LineId")
            FROM :base B JOIN :ord O ON O."OrderType" = B."OrderType" AND O."OrderEntry" = B."OrderEntry" WHERE B."Cat" = 'RCPT'
          UNION ALL
          SELECT CASE WHEN O."IsWw" = 'Y' THEN 'WW03' ELSE 'PP05' END, O."WipAcct", CASE WHEN O."IsWw" = 'Y' THEN NULL ELSE O."ShopOcr" END, NULL,
                 -B."Amount", 'LINE', TO_NVARCHAR(B."LineId")
            FROM :base B JOIN :ord O ON O."OrderType" = B."OrderType" AND O."OrderEntry" = B."OrderEntry" WHERE B."Cat" = 'RCPT'
          --   PP05 中分摊的制造、人工：改贷 500103 / 500102（按分摊额，未分摊部分留在费用科目，Q13）
          UNION ALL
          SELECT 'PP05', O."WipAcct", O."ShopOcr", NULL, O."AllocMfg" + O."AllocLab", 'ORDER', O."OrderType" || '-' || O."OrderEntry"
            FROM :ord O WHERE O."IsWw" = 'N' AND O."RecvQty" <> 0 AND (O."AllocMfg" <> 0 OR O."AllocLab" <> 0)
          UNION ALL
          SELECT 'PP05', :mfgAcct, NULL, NULL, -O."AllocMfg", 'ORDER', O."OrderType" || '-' || O."OrderEntry"
            FROM :ord O WHERE O."IsWw" = 'N' AND O."RecvQty" <> 0 AND O."AllocMfg" <> 0
          UNION ALL
          SELECT 'PP05', :labAcct, NULL, NULL, -O."AllocLab", 'ORDER', O."OrderType" || '-' || O."OrderEntry"
            FROM :ord O WHERE O."IsWw" = 'N' AND O."RecvQty" <> 0 AND O."AllocLab" <> 0
          --   WW03 中结转的加工费：改贷 140802（按订单归集额，S4 决定）
          UNION ALL
          SELECT 'WW03', :wwMat, NULL, NULL, F."Car", 'ORDER', O."OrderType" || '-' || O."OrderEntry"
            FROM :ord O JOIN :fee F ON F."OrderType" = O."OrderType" AND F."OrderEntry" = O."OrderEntry" WHERE O."IsWw" = 'Y' AND F."Car" <> 0
          UNION ALL
          SELECT 'WW03', :wwFee, NULL, NULL, -F."Car", 'ORDER', O."OrderType" || '-' || O."OrderEntry"
            FROM :ord O JOIN :fee F ON F."OrderType" = O."OrderType" AND F."OrderEntry" = O."OrderEntry" WHERE O."IsWw" = 'Y' AND F."Car" <> 0
          -- JZ01 / JZ03 关单差异：借 510199 / 510198，贷订单在产品科目（委外的加工费部分贷 140802）
          UNION ALL
          SELECT CASE WHEN O."IsWw" = 'Y' THEN 'JZ03' ELSE 'JZ01' END, CASE WHEN O."IsWw" = 'Y' THEN :clsWw ELSE :clsProd END,
                 NULL, NULL, ROUND(O."CloseDifAmt", 2), 'ORDER', O."OrderType" || '-' || O."OrderEntry"
            FROM :ord O WHERE ROUND(O."CloseDifAmt", 2) <> 0
          UNION ALL
          SELECT CASE WHEN O."IsWw" = 'Y' THEN 'JZ03' ELSE 'JZ01' END, O."WipAcct", NULL, NULL,
                 -(ROUND(O."CloseDifAmt", 2) - CASE WHEN O."IsWw" = 'Y' THEN IFNULL(F."Cls", 0) ELSE 0 END), 'ORDER', O."OrderType" || '-' || O."OrderEntry"
            FROM :ord O LEFT JOIN :fee F ON F."OrderType" = O."OrderType" AND F."OrderEntry" = O."OrderEntry"
           WHERE ROUND(O."CloseDifAmt", 2) <> 0
          UNION ALL
          SELECT 'JZ03', :wwFee, NULL, NULL, -F."Cls", 'ORDER', O."OrderType" || '-' || O."OrderEntry"
            FROM :ord O JOIN :fee F ON F."OrderType" = O."OrderType" AND F."OrderEntry" = O."OrderEntry"
           WHERE O."IsWw" = 'Y' AND ROUND(O."CloseDifAmt", 2) <> 0 AND F."Cls" <> 0
          -- JZ05 历史委外差异转出（用户 2026-11-04）：借 WW_HIST_EXP（510109，成本中心 WW_HIST_OCR），贷 140801；借方由下面的 PP04 结转
          UNION ALL
          SELECT 'JZ05', "AcctCode", "OcrCode", NULL, ROUND("Amount", 2), 'ORDER', "SrcKey"
            FROM "MTC_CA_S_EXP" WHERE "RunId" = :RunId AND "Src" = 'WWHIST'
          UNION ALL
          SELECT 'JZ05', :wwMat, NULL, NULL, -ROUND("Amount", 2), 'ORDER', "SrcKey"
            FROM "MTC_CA_S_EXP" WHERE "RunId" = :RunId AND "Src" = 'WWHIST'
          -- JZ04 零库存尾差结转（TAIL-01，Q31/Q32）：TailAmt 为负 = 期末多出的金额转出：借 TAIL_ADJ、贷存货；为正相反
          UNION ALL
          SELECT 'JZ04', SA."Acct", NULL, NULL, ROUND(R."TailAmt", 2), 'ITEM', R."ItemCode"
            FROM "MTC_CA_R_ITEM" R
            JOIN "MTC_CA_S_ITEM" I ON I."RunId" = R."RunId" AND I."ItemCode" = R."ItemCode"
            LEFT JOIN :stockAct SA ON SA."ItmsGrpCod" = I."ItmsGrpCod"
           WHERE R."RunId" = :RunId AND ROUND(R."TailAmt", 2) <> 0
          UNION ALL
          SELECT 'JZ04', :tailAcct, NULL, NULL, -ROUND("TailAmt", 2), 'ITEM', "ItemCode"
            FROM "MTC_CA_R_ITEM" WHERE "RunId" = :RunId AND ROUND("TailAmt", 2) <> 0
          -- DN01 销售交货 / 退货：借发出商品、贷存货
          UNION ALL
          SELECT 'DN01', :goods, NULL, NULL, -B."Amount", 'LINE', TO_NVARCHAR(B."LineId") FROM :base B WHERE B."TransCode" IN ('O01', 'O06')
          UNION ALL
          SELECT 'DN01', B."StockAct", NULL, NULL, B."Amount", 'LINE', TO_NVARCHAR(B."LineId") FROM :base B WHERE B."TransCode" IN ('O01', 'O06')
          -- DN02 / DN04 样品：发出商品转样品成本，含视同销售销项税（国内按平台价，国外按成本 × 系数）
          UNION ALL
          SELECT CASE WHEN M."CustType" = :custExp THEN 'DN04' ELSE 'DN02' END, :sample, M."U_OcrCode", NULL,
                 -(B."Amount" + CASE WHEN M."CustType" = :custExp THEN ROUND(B."Amount" * :expFactor * :vatRate, 2)
                                     ELSE ROUND(B."Qty" * IFNULL(P."Price", 0) / :vatDiv * :vatRate, 2) END), 'LINE', TO_NVARCHAR(B."LineId")
            FROM :base B JOIN :smp M ON M."ObjType" = B."ObjType" AND M."DocEntry" = B."DocEntry"
            LEFT JOIN :ptp P ON P."U_ItemCode" = B."ItemCode"
           WHERE B."TransCode" IN ('O01', 'O06') AND M."CustType" IN (:custDom, :custExp)
          UNION ALL
          SELECT CASE WHEN M."CustType" = :custExp THEN 'DN04' ELSE 'DN02' END, :goods, NULL, NULL, B."Amount", 'LINE', TO_NVARCHAR(B."LineId")
            FROM :base B JOIN :smp M ON M."ObjType" = B."ObjType" AND M."DocEntry" = B."DocEntry"
           WHERE B."TransCode" IN ('O01', 'O06') AND M."CustType" IN (:custDom, :custExp)
          UNION ALL
          SELECT CASE WHEN M."CustType" = :custExp THEN 'DN04' ELSE 'DN02' END, :vatOut, NULL, NULL,
                 CASE WHEN M."CustType" = :custExp THEN ROUND(B."Amount" * :expFactor * :vatRate, 2)
                      ELSE ROUND(B."Qty" * IFNULL(P."Price", 0) / :vatDiv * :vatRate, 2) END, 'LINE', TO_NVARCHAR(B."LineId")
            FROM :base B JOIN :smp M ON M."ObjType" = B."ObjType" AND M."DocEntry" = B."DocEntry"
            LEFT JOIN :ptp P ON P."U_ItemCode" = B."ItemCode"
           WHERE B."TransCode" IN ('O01', 'O06') AND M."CustType" IN (:custDom, :custExp)
          -- DN03 开票结转销售成本：借 6401（按客户类型），贷发出商品
          UNION ALL
          SELECT 'DN03', CASE WHEN "CustType" = :custDom THEN :cogsDom WHEN "CustType" = :custExp THEN :cogsExp END, NULL, NULL, "Cost", 'DOC', "K" || '-' || "DocEntry" || '-' || "LineNum"
            FROM :invCost WHERE IFNULL("Cost", 0) <> 0
          UNION ALL
          SELECT 'DN03', :goods, NULL, NULL, -"Cost", 'DOC', "K" || '-' || "DocEntry" || '-' || "LineNum"
            FROM :invCost WHERE IFNULL("Cost", 0) <> 0
          -- AR03 / AR04 未开票交货的销售成本暂估（截至期末未清数量，非样品）：借 6401、贷发出商品
          UNION ALL
          SELECT CASE WHEN "CustType" = :custDom THEN 'AR03' ELSE 'AR04' END, CASE WHEN "CustType" = :custDom THEN :cogsDom ELSE :cogsExp END,
                 NULL, NULL, "CostAmt", 'DOC', "ObjType" || '-' || "DocEntry" || '-' || "LineNum"
            FROM "MTC_CA_R_GOODS_OUT" WHERE "RunId" = :RunId AND "IsSample" = 'N' AND "CustType" IN (:custDom, :custExp) AND IFNULL("CostAmt", 0) <> 0
          UNION ALL
          SELECT CASE WHEN "CustType" = :custDom THEN 'AR03' ELSE 'AR04' END, :goods, NULL, NULL, -"CostAmt", 'DOC', "ObjType" || '-' || "DocEntry" || '-' || "LineNum"
            FROM "MTC_CA_R_GOODS_OUT" WHERE "RunId" = :RunId AND "IsSample" = 'N' AND "CustType" IN (:custDom, :custExp) AND IFNULL("CostAmt", 0) <> 0;

    -- PP04 制造费用结转：本次生成的凭证与总账（不含成本模块生成的凭证代码）在 5101 科目上的本期发生额，全部转入 500103
    pp4 = SELECT "AcctCode", SUM("Amount") AS "Amt" FROM (
              SELECT "AcctCode", "Amount" FROM :src WHERE "AcctCode" LIKE :mfgp || '%'
              UNION ALL
              SELECT J."Account", J."Debit" - J."Credit"
                FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
               WHERE H."RefDate" BETWEEN :d0 AND :d1 AND J."Account" LIKE :mfgp || '%'
                 AND LOCATE(:costCodes, ',' || IFNULL(H."TransCode", '') || ',') = 0)
           GROUP BY "AcctCode";

    -- JZ04 发出商品尾差（用户 2026-11-01：财务不允许 140601 留 0.01）：140601 本期应为 0（POST-10），
    -- 本期 = 总账 + 未清凭单中本期参与对账的分录（成本凭证、B1 自动冲销的成本凭证；GOODS 不在 RECON_COSTONLY_AREAS 时全部分录）
    --      + 本次底稿中本期尚未过账的 140601 分录（同 MTC_CA_F_RECON_LEDGER 的口径，手工调整不算）。
    -- 不为 0 且在 ±GOODS_TAIL_MAX（默认 1 元）以内的，借 / 贷 TAIL_ADJ（640101 主营业务成本），贷 / 借 140601，期末差额 = 期初差额。
    -- 超过上限的不处理，留给 POST-10 报出（不是尾差，要查原因）；JZ04 本期已在 140601 过账时也不处理。
    -- 按计算时的总账算：计算后上月 AR03 / AR04 的冲销或其他成本凭证才过账的，要重新计算。
    gpd = SELECT DISTINCT "TransCode" FROM (
              SELECT H."TransCode" FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
               WHERE H."RefDate" BETWEEN :d0 AND :d1 AND H."StornoToTr" IS NULL AND J."Account" = :goods
              UNION ALL
              SELECT T0."TransCode" FROM "OBTF" T0 JOIN "BTF1" T1 ON T1."TransId" = T0."TransId" AND T1."BatchNum" = T0."BatchNum"
               WHERE T0."BtfStatus" = 'O' AND T0."RefDate" BETWEEN :d0 AND :d1 AND T1."Account" = :goods)
           WHERE LOCATE(:costCodes, ',' || IFNULL("TransCode", '') || ',') > 0;
    SELECT ROUND(IFNULL(SUM("Amt"), 0), 2) INTO gRes FROM (
        SELECT J."Debit" - J."Credit" AS "Amt"
          FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
          LEFT JOIN "OJDT" R ON R."TransId" = H."StornoToTr"
         WHERE H."RefDate" BETWEEN :d0 AND :d1 AND J."Account" = :goods
           AND (LOCATE(:costOnly, ',GOODS,') = 0
                OR LOCATE(:costCodes, ',' || IFNULL(H."TransCode", '') || ',') > 0
                OR LOCATE(:costCodes, ',' || IFNULL(R."TransCode", '') || ',') > 0)
        UNION ALL
        SELECT T1."Debit" - T1."Credit"
          FROM "OBTF" T0 JOIN "BTF1" T1 ON T1."TransId" = T0."TransId" AND T1."BatchNum" = T0."BatchNum"
         WHERE T0."BtfStatus" = 'O' AND T0."RefDate" BETWEEN :d0 AND :d1 AND T1."Account" = :goods
           AND (LOCATE(:costOnly, ',GOODS,') = 0 OR LOCATE(:costCodes, ',' || IFNULL(T0."TransCode", '') || ',') > 0)
        UNION ALL
        SELECT "Amount" FROM :src WHERE "AcctCode" = :goods AND "TransCode" NOT IN (SELECT "TransCode" FROM :gpd));
    SELECT COUNT(*) INTO nJz4 FROM :gpd WHERE "TransCode" = 'JZ04';
    gOk := CASE WHEN :gRes <> 0 AND ABS(:gRes) <= :gTailMax AND :nJz4 = 0 AND IFNULL(:goods, '') <> '' AND IFNULL(:tailAcct, '') <> '' THEN 1 ELSE 0 END;
    gTail = SELECT CAST('JZ04' AS NVARCHAR(10)) AS "TransCode", CAST(:goods AS NVARCHAR(15)) AS "AcctCode",
                   CAST(NULL AS NVARCHAR(20)) AS "OcrCode", CAST(NULL AS NVARCHAR(20)) AS "Project",
                   CAST(-:gRes AS DECIMAL(19,2)) AS "Amount", CAST('GOODS' AS NVARCHAR(10)) AS "SrcType", CAST(:goods AS NVARCHAR(100)) AS "SrcKey"
              FROM DUMMY WHERE :gOk = 1
            UNION ALL
            SELECT 'JZ04', :tailAcct, NULL, NULL, :gRes, 'GOODS', :goods FROM DUMMY WHERE :gOk = 1;

    -- P74 已写入 PUR1–PUR5，接在其后编号
    SELECT IFNULL(MAX("SrcId"), 0) INTO maxId FROM "MTC_CA_R_JDT_SRC" WHERE "RunId" = :RunId;
    INSERT INTO "MTC_CA_R_JDT_SRC" ("FcCode", "RunType", "Scenario", "RunId", "SrcId", "TransCode", "AcctCode", "OcrCode", "Project",
                                    "Amount", "SrcType", "SrcKey")
    SELECT :fc, :rt, :scen, :RunId, :maxId + ROW_NUMBER() OVER (ORDER BY "TransCode", "SrcType", "SrcKey", "AcctCode"),
           "TransCode", "AcctCode", "OcrCode", "Project", "Amount", "SrcType", "SrcKey"
      FROM (SELECT * FROM :src
            UNION ALL
            SELECT * FROM :gTail
            UNION ALL
            SELECT 'PP04', :mfgAcct, NULL, NULL, ROUND("Amt", 2), 'GL', "AcctCode" FROM :pp4 WHERE ROUND("Amt", 2) <> 0
            UNION ALL
            SELECT 'PP04', "AcctCode", NULL, NULL, -ROUND("Amt", 2), 'GL', "AcctCode" FROM :pp4 WHERE ROUND("Amt", 2) <> 0)
     WHERE "Amount" <> 0;

    INSERT INTO "MTC_CA_R_JDT" ("FcCode", "RunType", "Scenario", "RunId", "TransCode", "LineNo", "TransName", "RefDate",
                                "AcctCode", "Debit", "Credit", "OcrCode", "Project", "VendorCode")
    SELECT :fc, :rt, :scen, :RunId, S."TransCode",
           ROW_NUMBER() OVER (PARTITION BY S."TransCode" ORDER BY CASE WHEN S."Amt" > 0 THEN 0 ELSE 1 END, S."AcctCode", S."OcrCode", S."Project", S."VendorCode"),
           C."TrnsCodDsc", :d1, S."AcctCode",
           CASE WHEN S."Amt" > 0 THEN S."Amt" ELSE 0 END, CASE WHEN S."Amt" < 0 THEN -S."Amt" ELSE 0 END, S."OcrCode", S."Project", S."VendorCode"
      FROM (SELECT "TransCode", "AcctCode", "OcrCode", "Project", "VendorCode", SUM("Amount") AS "Amt"
              FROM "MTC_CA_R_JDT_SRC" WHERE "RunId" = :RunId
             GROUP BY "TransCode", "AcctCode", "OcrCode", "Project", "VendorCode") S
      LEFT JOIN "OTRC" C ON C."TrnsCode" = S."TransCode"
     WHERE S."Amt" <> 0;
    RowCnt := ::ROWCOUNT;
END
@@
-- P75：凭证与暂估校验（POST-08 … POST-12）
-- 财务端与业务端对账（用户 2026-10-13）：两个口径
--   口径① 计算后、过账前：总账已过账分录 + 未清凭单（OBTF 未过账日记账凭单）+ 本次凭证底稿（R_JDT）= 业务端
--   口径② 过账后：      总账已过账分录 + 未清凭单 = 业务端
-- 校验按凭证代码合并两个口径（2026-10-14，2026-09 运行中 PUR1/PUR2/PUR5、MR02 已过账、其他成本凭证未过账，口径① 把已过账部分重复计入）：
--   差额 = 总账已过账 + 未清凭单 + 底稿中本期尚未过账的凭证 − 业务端
-- 底稿某个凭证代码（COST_TRANSCODES 中）本期已在总账过账、或本期未清凭单中已有时，这个代码的底稿分录 Dup='Y'，不再加。
-- 全部未过账时等于口径①，全部过账后等于口径②；Diff1 / Diff2 保留作参考。按凭证代码整体判断，同一代码只过账了一部分时仍会有差。
-- 函数只读，执行台每次打开都按当前总账重算。
-- 对账科目：存货科目（OGAR.StockAct）、WW_MAT、WW_FEE、WIP_PROD、GOODS_ISSUED（不含 AR03 / AR04）、AP_ACCRUAL（按 U_VendorCode）。
-- 金额方向：资产类为 借 − 贷；应付暂估为 贷 − 借。
-- 只对成本凭证的对账项（参数 RECON_COSTONLY_AREAS，默认 WIP_PROD）：总账、未清凭单中凭证代码不在 COST_TRANSCODES 的分录
-- （手工凭证、单据自动凭证等）允许存在，InRecon='N'，不参与比较，金额在 MTC_CA_F_RECON.OtherAmt 单独列出（用户 2026-10-13）。
-- 期初 / 本期 / 期末分开列示（用户 2026-10-15）：Phase = BEG（总账、未清凭单中 RefDate 早于本期）/ CUR（本期分录和底稿）。
-- 期初按科目余额全额比较（以前的非成本分录也构成期初余额），“只比成本凭证”只作用于本期分录，B1 自动冲销成本凭证不算非成本分录；
-- RECON_COSTONLY_AREAS 默认含 GOODS：140601 手工调整单独列出，期末差额扣除后应等于期初差额（用户 2026-10-17）；
-- 也含 WW_MAT：140801 本期凭证代码为空的手工调整（2026-09 −253,269.53）单独列出（用户 2026-10-17）。
CREATE OR REPLACE FUNCTION "MTC_CA_F_RECON_LEDGER" (IN RunId BIGINT)
RETURNS TABLE ("Area" NVARCHAR(20), "AcctCode" NVARCHAR(15), "KeyCode" NVARCHAR(50), "Src" NVARCHAR(10), "Phase" NVARCHAR(3),
               "TransCode" NVARCHAR(20), "InRecon" NVARCHAR(1), "Dup" NVARCHAR(1), "Amt" DECIMAL(19,2), "Part" NVARCHAR(10))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE costCodes NVARCHAR(500); DECLARE costOnly NVARCHAR(200);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    costCodes := IFNULL("MTC_CA_F_PARAM"('COST_TRANSCODES', :fc), ',');
    costOnly := IFNULL("MTC_CA_F_PARAM"('RECON_COSTONLY_AREAS', :fc), ',WIP_PROD,GOODS,WW_MAT,');

    acct = SELECT "Area", "AcctCode" FROM (
               SELECT DISTINCT 'STOCK' AS "Area", "StockAct" AS "AcctCode" FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4)
               UNION ALL SELECT 'WW_MAT', "MTC_CA_F_ACCT"('WW_MAT', :fc) FROM DUMMY
               UNION ALL SELECT 'WW_FEE', "MTC_CA_F_ACCT"('WW_FEE', :fc) FROM DUMMY
               UNION ALL SELECT 'WIP_PROD', "MTC_CA_F_ACCT"('WIP_PROD', :fc) FROM DUMMY
               UNION ALL SELECT 'GOODS', "MTC_CA_F_ACCT"('GOODS_ISSUED', :fc) FROM DUMMY
               UNION ALL SELECT 'AP', "MTC_CA_F_ACCT"('AP_ACCRUAL', :fc) FROM DUMMY)
            WHERE IFNULL("AcctCode", '') <> '';

    led = SELECT 'GL' AS "Src", CASE WHEN H."RefDate" < :d0 THEN 'BEG' ELSE 'CUR' END AS "Phase",
                 IFNULL(H."TransCode", '') AS "TransCode", J."Account" AS "AcctCode",
                 IFNULL(J."U_VendorCode", '') AS "Vendor", J."Debit" - J."Credit" AS "Amt", R."TransCode" AS "RevOf"
            FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
            LEFT JOIN "OJDT" R ON R."TransId" = H."StornoToTr"
           WHERE H."RefDate" <= :d1 AND J."Account" IN (SELECT "AcctCode" FROM :acct)
          UNION ALL
          SELECT 'VCH', CASE WHEN T0."RefDate" < :d0 THEN 'BEG' ELSE 'CUR' END, IFNULL(T0."TransCode", ''), T1."Account", IFNULL(T1."U_VendorCode", ''), T1."Debit" - T1."Credit", NULL
            FROM "OBTF" T0 JOIN "BTF1" T1 ON T1."TransId" = T0."TransId" AND T1."BatchNum" = T0."BatchNum"
           WHERE T0."BtfStatus" = 'O' AND T0."RefDate" <= :d1 AND T1."Account" IN (SELECT "AcctCode" FROM :acct)
          UNION ALL
          SELECT 'DRAFT', 'CUR', "TransCode", "AcctCode", IFNULL("VendorCode", ''), "Debit" - "Credit", NULL
            FROM "MTC_CA_R_JDT" WHERE "RunId" = :RunId AND "AcctCode" IN (SELECT "AcctCode" FROM :acct);

    -- 本期已过账或已在未清凭单中的成本凭证代码 × 科目：底稿中同一代码、同一科目的分录不再计入差额（Dup='Y'）。
    -- 2026-10-17 改为按科目判断、B1 自动冲销（StornoToTr 非空）不算：2026-09 运行中本期未清凭单有 AR03 / AR04 但没有 140601 分录，
    -- 按代码整体判断时底稿 AR03 / AR04 的 140601 计提被当成重复丢掉，POST-10 ⑤ 本月计提为 0、本期差额多出本期末未开票金额
    pdc = SELECT DISTINCT "TransCode", "AcctCode" FROM (
              SELECT H."TransCode", J."Account" AS "AcctCode" FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
               WHERE H."RefDate" BETWEEN :d0 AND :d1 AND H."StornoToTr" IS NULL
              UNION ALL
              SELECT T0."TransCode", T1."Account" FROM "OBTF" T0 JOIN "BTF1" T1 ON T1."TransId" = T0."TransId" AND T1."BatchNum" = T0."BatchNum"
               WHERE T0."BtfStatus" = 'O' AND T0."RefDate" BETWEEN :d0 AND :d1)
           WHERE LOCATE(:costCodes, ',' || IFNULL("TransCode", '') || ',') > 0;

    -- 先在子查询里算出 InRecon（HANA 不接受 GROUP BY 里带变量的表达式）
    led2 = SELECT A."Area", L."AcctCode", CASE WHEN A."Area" = 'AP' THEN L."Vendor" ELSE '' END AS "KeyCode", L."Src", L."Phase", L."TransCode",
                  -- JZ05 历史委外差异转出（用户 2026-11-04）：业务端本来就是 0，本期不算差额，单独列示；下期起进期初，期初差额随之减少
                  CASE WHEN A."Area" = 'WW_MAT' AND L."Phase" = 'CUR' AND L."TransCode" = 'JZ05' THEN 'N'
                       WHEN L."Src" <> 'DRAFT' AND L."Phase" = 'CUR' AND LOCATE(:costOnly, ',' || A."Area" || ',') > 0
                            AND LOCATE(:costCodes, ',' || L."TransCode" || ',') = 0
                            -- B1 自动冲销成本凭证（如上月 AR03 / AR04）不算手工分录（2026-10-17）
                            AND LOCATE(:costCodes, ',' || IFNULL(L."RevOf", '') || ',') = 0 THEN 'N'
                       ELSE 'Y' END AS "InRecon",
                  CASE WHEN L."Src" = 'DRAFT' AND P."TransCode" IS NOT NULL THEN 'Y' ELSE 'N' END AS "Dup",
                  CASE WHEN A."Area" = 'AP' THEN -L."Amt" ELSE L."Amt" END AS "Amt",
                  -- 发出商品构成（用户 2026-10-15）：REV 冲销上月计提（B1 自动冲销，StornoToTr 指向 AR03 / AR04）、DN01 发货、
                  -- SAMPLE 样品转出、DN03 发票、ACCR 本月计提、TAIL 尾差结转 JZ04（2026-11-01）、OTHER 其他
                  CASE WHEN A."Area" <> 'GOODS' THEN ''
                       WHEN L."RevOf" IN ('AR03', 'AR04') THEN 'REV'
                       WHEN L."TransCode" = 'DN01' THEN 'DN01'
                       WHEN L."TransCode" IN ('DN02', 'DN04') THEN 'SAMPLE'
                       WHEN L."TransCode" = 'DN03' THEN 'DN03'
                       WHEN L."TransCode" IN ('AR03', 'AR04') THEN 'ACCR'
                       WHEN L."TransCode" = 'JZ04' THEN 'TAIL'      -- 发出商品尾差（P70，用户 2026-11-01）
                       ELSE 'OTHER' END AS "Part"
             FROM :led L JOIN :acct A ON A."AcctCode" = L."AcctCode"
             LEFT JOIN :pdc P ON P."TransCode" = L."TransCode" AND P."AcctCode" = L."AcctCode";

    RETURN SELECT "Area", "AcctCode", "KeyCode", "Src", "Phase", "TransCode", "InRecon", "Dup", ROUND(SUM("Amt"), 2) AS "Amt", "Part"
             FROM :led2 GROUP BY "Area", "AcctCode", "KeyCode", "Src", "Phase", "TransCode", "InRecon", "Dup", "Part";
END
@@
-- 业务端：STOCK = 新框架期末金额（按物料组存货科目）；WW_MAT = 委外订单在产品（不含加工费）；WW_FEE = 委外订单未结转加工费；
-- WIP_PROD = 其他订单在产品（不含加工费）；GOODS = 0（140601 含 AR03 / AR04 计提和冲销，期初 = 期末 = 0，用户 2026-10-15）；AP = 应付暂估（按供应商）。
-- 期初 / 本期 / 期末分开列示（用户 2026-10-15）：
--   业务期初：STOCK = S_OPEN；在产品 = S_ORDER_OPEN 累计投入 − 累计结转；GOODS = 0；AP = S_AP_MOVE 中本期以前的变动；
--   业务本期 = 期末 − 期初；
--   财务期初 = 总账 + 未清凭单中本期以前的分录；财务本期 = 本期分录 + 底稿中本期尚未过账的凭证；财务期末 = 期初 + 本期。
--   BegDiff / CurDiff / Diff = 期初 / 本期 / 期末差额（Diff = BegDiff + CurDiff），P75 按参数 RECON_BLOCK_ON 选哪一列阻断。
-- GlAmt / VchAmt / DraftAmt / DupAmt 是期初 + 本期合计；Diff1 = 口径①（总账 + 未清凭单 + 底稿 − 业务），Diff2 = 口径②（总账 + 未清凭单 − 业务），只作参考；
-- 都只含 InRecon='Y' 的分录。OtherAmt = 不参与对账的分录（本期非成本凭证）；HistAmt = 其中 JZ05 历史委外差异转出（用户 2026-11-04）。
-- PendCodes / DupCodes = 未过账 / 已过账的底稿凭证代码和名称（OTRC），如“MR01 生产领料、PP01 …”。
CREATE OR REPLACE FUNCTION "MTC_CA_F_RECON" (IN RunId BIGINT)
RETURNS TABLE ("Area" NVARCHAR(20), "AcctCode" NVARCHAR(15), "KeyCode" NVARCHAR(50),
               "BegBiz" DECIMAL(19,2), "BegFin" DECIMAL(19,2), "BegDiff" DECIMAL(19,2),
               "CurBiz" DECIMAL(19,2), "CurFin" DECIMAL(19,2), "CurDiff" DECIMAL(19,2),
               "BizAmt" DECIMAL(19,2), "EndFin" DECIMAL(19,2), "Diff" DECIMAL(19,2),
               "GlAmt" DECIMAL(19,2), "VchAmt" DECIMAL(19,2), "DraftAmt" DECIMAL(19,2), "DupAmt" DECIMAL(19,2),
               "Diff1" DECIMAL(19,2), "Diff2" DECIMAL(19,2), "OtherAmt" DECIMAL(19,2),
               "PendCodes" NVARCHAR(1000), "DupCodes" NVARCHAR(1000), "HistAmt" DECIMAL(19,2))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE wwMat NVARCHAR(15); DECLARE wwFee NVARCHAR(15); DECLARE wipProd NVARCHAR(15); DECLARE goods NVARCHAR(15); DECLARE apAcct NVARCHAR(15);
    DECLARE wwWt NVARCHAR(200);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    wwWt := IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', :fc), ',50,');   -- 委外工单的订单类型（参数，2026-10-27）
    wwMat := "MTC_CA_F_ACCT"('WW_MAT', :fc);       wwFee := "MTC_CA_F_ACCT"('WW_FEE', :fc);
    wipProd := "MTC_CA_F_ACCT"('WIP_PROD', :fc);   goods := "MTC_CA_F_ACCT"('GOODS_ISSUED', :fc);
    apAcct := "MTC_CA_F_ACCT"('AP_ACCRUAL', :fc);

    stockAct = SELECT TO_NVARCHAR("ItmsGrpCod") AS "ItmsGrpCod", MAX("StockAct") AS "Acct"
                 FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4) GROUP BY "ItmsGrpCod";
    wip = SELECT SUM(CASE WHEN LOCATE(:wwWt, ',' || O."WorType" || ',') > 0 AND M."ItemCode" <> '#SUBFEE' THEN M."WipMat" + M."WipMfg" + M."WipLab" + M."WipSub" ELSE 0 END) AS "WwMat",
                 SUM(CASE WHEN LOCATE(:wwWt, ',' || O."WorType" || ',') > 0 AND M."ItemCode" = '#SUBFEE' THEN M."WipSub" ELSE 0 END) AS "WwFee",
                 SUM(CASE WHEN LOCATE(:wwWt, ',' || O."WorType" || ',') = 0 AND M."ItemCode" <> '#SUBFEE' THEN M."WipMat" + M."WipMfg" + M."WipLab" + M."WipSub" ELSE 0 END) AS "Prod"
            FROM "MTC_CA_R_ORDER_MAT" M
            JOIN "MTC_CA_R_ORDER" O ON O."RunId" = M."RunId" AND O."OrderType" = M."OrderType" AND O."OrderEntry" = M."OrderEntry"
           WHERE M."RunId" = :RunId;
    -- 期初在产品：累计投入 − 累计结转（同期末的口径：委外 #SUBFEE 只取加工费，其余四项要素合计）
    wip0 = SELECT SUM(CASE WHEN LOCATE(:wwWt, ',' || IFNULL(O."WorType", '') || ',') > 0 AND M."ItemCode" <> '#SUBFEE' THEN "Net" ELSE 0 END) AS "WwMat",
                  SUM(CASE WHEN LOCATE(:wwWt, ',' || IFNULL(O."WorType", '') || ',') > 0 AND M."ItemCode" = '#SUBFEE' THEN "NetSub" ELSE 0 END) AS "WwFee",
                  SUM(CASE WHEN LOCATE(:wwWt, ',' || IFNULL(O."WorType", '') || ',') = 0 AND M."ItemCode" <> '#SUBFEE' THEN "Net" ELSE 0 END) AS "Prod"
             FROM (SELECT "OrderType", "OrderEntry", "ItemCode",
                          IFNULL("CumIssueMat", 0) + IFNULL("CumIssueMfg", 0) + IFNULL("CumIssueLab", 0) + IFNULL("CumIssueSub", 0)
                          - IFNULL("CumCarriedMat", 0) - IFNULL("CumCarriedMfg", 0) - IFNULL("CumCarriedLab", 0) - IFNULL("CumCarriedSub", 0) AS "Net",
                          IFNULL("CumIssueSub", 0) - IFNULL("CumCarriedSub", 0) AS "NetSub"
                     FROM "MTC_CA_S_ORDER_OPEN" WHERE "RunId" = :RunId) M
             LEFT JOIN "MTC_CA_S_ORDER" O ON O."RunId" = :RunId AND O."OrderType" = M."OrderType" AND O."OrderEntry" = M."OrderEntry";
    biz = SELECT 'STOCK' AS "Area", X."Acct" AS "AcctCode", '' AS "KeyCode", 'END' AS "Phase", X."Amt"
            FROM (SELECT SA."Acct", SUM(R."EndAmount") AS "Amt"
                    FROM "MTC_CA_R_ITEM" R
                    JOIN "MTC_CA_S_ITEM" I ON I."RunId" = R."RunId" AND I."ItemCode" = R."ItemCode"
                    JOIN :stockAct SA ON SA."ItmsGrpCod" = I."ItmsGrpCod"
                   WHERE R."RunId" = :RunId GROUP BY SA."Acct") X
          UNION ALL
          SELECT 'STOCK', X."Acct", '', 'BEG', X."Amt"
            FROM (SELECT SA."Acct", SUM(O."Amount") AS "Amt"
                    FROM "MTC_CA_S_OPEN" O
                    JOIN "MTC_CA_S_ITEM" I ON I."RunId" = O."RunId" AND I."ItemCode" = O."ItemCode"
                    JOIN :stockAct SA ON SA."ItmsGrpCod" = I."ItmsGrpCod"
                   WHERE O."RunId" = :RunId GROUP BY SA."Acct") X
          UNION ALL SELECT 'WW_MAT', :wwMat, '', 'END', IFNULL("WwMat", 0) FROM :wip
          UNION ALL SELECT 'WW_FEE', :wwFee, '', 'END', IFNULL("WwFee", 0) FROM :wip
          UNION ALL SELECT 'WIP_PROD', :wipProd, '', 'END', IFNULL("Prod", 0) FROM :wip
          UNION ALL SELECT 'WW_MAT', :wwMat, '', 'BEG', IFNULL("WwMat", 0) FROM :wip0
          UNION ALL SELECT 'WW_FEE', :wwFee, '', 'BEG', IFNULL("WwFee", 0) FROM :wip0
          UNION ALL SELECT 'WIP_PROD', :wipProd, '', 'BEG', IFNULL("Prod", 0) FROM :wip0
          -- 发出商品 140601：月末 AR03 / AR04 把未开票部分全部计提、下月初 B1 自动冲销，所以业务端期初、期末都是 0（用户 2026-10-15）
          UNION ALL SELECT 'GOODS', :goods, '', 'END', 0 FROM DUMMY
          UNION ALL SELECT 'GOODS', :goods, '', 'BEG', 0 FROM DUMMY
          UNION ALL
          SELECT 'AP', :apAcct, X."CardCode", 'END', X."Amt"
            FROM (SELECT IFNULL("CardCode", '') AS "CardCode", SUM("OpenAmt") AS "Amt"
                    FROM "MTC_CA_R_AP_ACCR" WHERE "RunId" = :RunId GROUP BY IFNULL("CardCode", '')) X
          UNION ALL
          SELECT 'AP', :apAcct, X."CardCode", 'BEG', X."Amt"
            FROM (SELECT IFNULL("CardCode", '') AS "CardCode", SUM("AccrAmt") AS "Amt"
                    FROM "MTC_CA_S_AP_MOVE" WHERE "RunId" = :RunId AND "DocDate" < :d0 GROUP BY IFNULL("CardCode", '')) X;
    biz2 = SELECT "Area", "AcctCode", "KeyCode",
                  ROUND(SUM(CASE WHEN "Phase" = 'BEG' THEN "Amt" ELSE 0 END), 2) AS "Beg",
                  ROUND(SUM(CASE WHEN "Phase" = 'END' THEN "Amt" ELSE 0 END), 2) AS "Amt"
             FROM :biz
            WHERE IFNULL("AcctCode", '') <> '' GROUP BY "Area", "AcctCode", "KeyCode";
    lg = SELECT * FROM "MTC_CA_F_RECON_LEDGER"(:RunId);
    led = SELECT "Area", "AcctCode", "KeyCode",
                 SUM(CASE WHEN "Phase" = 'BEG' THEN "Amt" ELSE 0 END) AS "Beg",
                 SUM(CASE WHEN "Src" = 'GL' THEN "Amt" ELSE 0 END) AS "Gl",
                 SUM(CASE WHEN "Src" = 'VCH' THEN "Amt" ELSE 0 END) AS "Vch",
                 SUM(CASE WHEN "Src" = 'DRAFT' THEN "Amt" ELSE 0 END) AS "Draft",
                 SUM(CASE WHEN "Src" = 'DRAFT' AND "Dup" = 'Y' THEN "Amt" ELSE 0 END) AS "Dup"
            FROM :lg WHERE "InRecon" = 'Y'
           GROUP BY "Area", "AcctCode", "KeyCode";
    -- Dup='N'：JZ05 过账后底稿和总账各有一份，只算一次
    oth = SELECT "Area", "AcctCode", "KeyCode", SUM("Amt") AS "Amt",
                 SUM(CASE WHEN "TransCode" = 'JZ05' THEN "Amt" ELSE 0 END) AS "Hist"
            FROM :lg WHERE "InRecon" = 'N' AND "Dup" = 'N'
           GROUP BY "Area", "AcctCode", "KeyCode";
    -- 底稿凭证代码 + 中文名，分未过账 / 已过账两组
    dc = SELECT D."Area", D."AcctCode", D."KeyCode", D."Dup", D."TransCode" || IFNULL(' ' || C."TrnsCodDsc", '') AS "Name"
           FROM (SELECT "Area", "AcctCode", "KeyCode", "Dup", "TransCode" FROM :lg
                  WHERE "Src" = 'DRAFT' AND "InRecon" = 'Y' AND "Amt" <> 0
                  GROUP BY "Area", "AcctCode", "KeyCode", "Dup", "TransCode") D
           LEFT JOIN "OTRC" C ON C."TrnsCode" = D."TransCode";
    pend = SELECT "Area", "AcctCode", "KeyCode", LEFT(STRING_AGG("Name", '、' ORDER BY "Name"), 1000) AS "Codes"
             FROM :dc WHERE "Dup" = 'N' GROUP BY "Area", "AcctCode", "KeyCode";
    dupc = SELECT "Area", "AcctCode", "KeyCode", LEFT(STRING_AGG("Name", '、' ORDER BY "Name"), 1000) AS "Codes"
             FROM :dc WHERE "Dup" = 'Y' GROUP BY "Area", "AcctCode", "KeyCode";
    k = SELECT "Area", "AcctCode", "KeyCode" FROM :biz2 UNION SELECT "Area", "AcctCode", "KeyCode" FROM :led
        UNION SELECT "Area", "AcctCode", "KeyCode" FROM :oth;
    v = SELECT K."Area", K."AcctCode", K."KeyCode",
               IFNULL(B."Beg", 0) AS "BegBiz", IFNULL(B."Amt", 0) AS "BizAmt",
               IFNULL(L."Beg", 0) AS "BegFin",
               IFNULL(L."Gl", 0) + IFNULL(L."Vch", 0) + IFNULL(L."Draft", 0) - IFNULL(L."Dup", 0) AS "EndFin",
               IFNULL(L."Gl", 0) AS "Gl", IFNULL(L."Vch", 0) AS "Vch", IFNULL(L."Draft", 0) AS "Draft", IFNULL(L."Dup", 0) AS "Dup",
               IFNULL(X."Amt", 0) AS "Oth", IFNULL(X."Hist", 0) AS "Hist", P."Codes" AS "PendCodes", DC."Codes" AS "DupCodes"
          FROM :k K
          LEFT JOIN :biz2 B ON B."Area" = K."Area" AND B."AcctCode" = K."AcctCode" AND B."KeyCode" = K."KeyCode"
          LEFT JOIN :led L ON L."Area" = K."Area" AND L."AcctCode" = K."AcctCode" AND L."KeyCode" = K."KeyCode"
          LEFT JOIN :oth X ON X."Area" = K."Area" AND X."AcctCode" = K."AcctCode" AND X."KeyCode" = K."KeyCode"
          LEFT JOIN :pend P ON P."Area" = K."Area" AND P."AcctCode" = K."AcctCode" AND P."KeyCode" = K."KeyCode"
          LEFT JOIN :dupc DC ON DC."Area" = K."Area" AND DC."AcctCode" = K."AcctCode" AND DC."KeyCode" = K."KeyCode";

    RETURN SELECT "Area", "AcctCode", "KeyCode",
                  "BegBiz", "BegFin", "BegFin" - "BegBiz" AS "BegDiff",
                  "BizAmt" - "BegBiz" AS "CurBiz", "EndFin" - "BegFin" AS "CurFin",
                  ("EndFin" - "BegFin") - ("BizAmt" - "BegBiz") AS "CurDiff",
                  "BizAmt", "EndFin", "EndFin" - "BizAmt" AS "Diff",
                  "Gl" AS "GlAmt", "Vch" AS "VchAmt", "Draft" AS "DraftAmt", "Dup" AS "DupAmt",
                  "Gl" + "Vch" + "Draft" - "BizAmt" AS "Diff1", "Gl" + "Vch" - "BizAmt" AS "Diff2",
                  "Oth" AS "OtherAmt", "PendCodes", "DupCodes", "Hist" AS "HistAmt"
             FROM :v;
END
@@
-- 对账状态：本次底稿的凭证代码、其中本期已在总账过账的、未清凭单中的成本凭证代码（都带 OTRC 名称）；
-- Basis = DRAFT（都未过账，等于口径①）/ PART（部分过账，按凭证代码分开）/ POSTED（都已过账或在未清凭单，等于口径②）
CREATE OR REPLACE FUNCTION "MTC_CA_F_RECON_STATUS" (IN RunId BIGINT)
RETURNS TABLE ("Basis" NVARCHAR(10), "DraftCodes" NVARCHAR(1000), "PostedCodes" NVARCHAR(1000), "VchCodes" NVARCHAR(1000))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE costCodes NVARCHAR(500);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    costCodes := IFNULL("MTC_CA_F_PARAM"('COST_TRANSCODES', :fc), ',');

    dc = SELECT DISTINCT "TransCode" FROM "MTC_CA_R_JDT" WHERE "RunId" = :RunId;
    pc = SELECT DISTINCT H."TransCode" FROM "OJDT" H
          WHERE H."RefDate" BETWEEN :d0 AND :d1 AND H."StornoToTr" IS NULL AND H."TransCode" IN (SELECT "TransCode" FROM :dc);
    vc = SELECT DISTINCT T0."TransCode" FROM "OBTF" T0
          WHERE T0."BtfStatus" = 'O' AND T0."RefDate" <= :d1 AND LOCATE(:costCodes, ',' || IFNULL(T0."TransCode", '') || ',') > 0;
    -- 本期已过账或本期未清凭单中已有的凭证代码（只用于判断 Basis；MTC_CA_F_RECON_LEDGER 的 Dup 再按科目细分，2026-10-17）
    dup = SELECT "TransCode" FROM :pc
          UNION SELECT T0."TransCode" FROM "OBTF" T0
                 WHERE T0."BtfStatus" = 'O' AND T0."RefDate" BETWEEN :d0 AND :d1 AND T0."TransCode" IN (SELECT "TransCode" FROM :dc);
    nm = SELECT X."TransCode", X."TransCode" || IFNULL(' ' || C."TrnsCodDsc", '') AS "Name"
           FROM (SELECT "TransCode" FROM :dc UNION SELECT "TransCode" FROM :vc) X
           LEFT JOIN "OTRC" C ON C."TrnsCode" = X."TransCode";

    RETURN SELECT CASE WHEN U."Cnt" = 0 THEN 'DRAFT' WHEN U."Cnt" < D."Cnt" THEN 'PART' ELSE 'POSTED' END AS "Basis",
                  D."Codes" AS "DraftCodes", P."Codes" AS "PostedCodes", V."Codes" AS "VchCodes"
             FROM (SELECT COUNT(*) AS "Cnt", LEFT(STRING_AGG(N."Name", '、' ORDER BY N."Name"), 1000) AS "Codes"
                     FROM :dc T JOIN :nm N ON N."TransCode" = T."TransCode") D,
                  (SELECT LEFT(STRING_AGG(N."Name", '、' ORDER BY N."Name"), 1000) AS "Codes"
                     FROM :pc T JOIN :nm N ON N."TransCode" = T."TransCode") P,
                  (SELECT LEFT(STRING_AGG(N."Name", '、' ORDER BY N."Name"), 1000) AS "Codes"
                     FROM :vc T JOIN :nm N ON N."TransCode" = T."TransCode") V,
                  (SELECT COUNT(*) AS "Cnt" FROM :dup) U;
END
@@
-- 科目余额表（执行台“科目余额表”，用户 2026-10-15）：成本相关科目 = 物料组存货科目（OGAR.StockAct，当年）
-- + MTC_CA_C_ACCT 中本账期有效的全部用途科目（按前缀匹配 OACT 可过账科目，MFG_EXP_PREFIX 即 5101 制造费用）
-- + 参数 TB_EXTRA_ACCTS 列出的科目 / 前缀。Cat = 分类（同一科目多个用途时用“；”连接）
CREATE OR REPLACE FUNCTION "MTC_CA_F_TB_ACCT" (IN fc NVARCHAR(10))
RETURNS TABLE ("AcctCode" NVARCHAR(15), "AcctName" NVARCHAR(200), "Cat" NVARCHAR(500))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE extra NVARCHAR(1000);
    extra := IFNULL("MTC_CA_F_PARAM"('TB_EXTRA_ACCTS', :fc), '');
    pre = SELECT DISTINCT "StockAct" AS "Prefix", CAST('存货' AS NVARCHAR(200)) AS "Cat"
            FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4) AND IFNULL("StockAct", '') <> ''
          UNION
          SELECT "AcctCode", CASE WHEN "Usage" = 'MFG_EXP_PREFIX' THEN '制造费用'
                                  WHEN LOCATE("Descr", '（') > 1 THEN LEFT("Descr", LOCATE("Descr", '（') - 1)
                                  ELSE IFNULL("Descr", "Usage") END
            FROM "MTC_CA_C_ACCT" WHERE :fc BETWEEN "FromFc" AND "ToFc" AND IFNULL("AcctCode", '') <> ''
          UNION
          SELECT P, '参数 TB_EXTRA_ACCTS' FROM (
              SELECT SUBSTR_REGEXPR('[^,]+' IN :extra OCCURRENCE TO_INTEGER(G."GENERATED_PERIOD_START")) AS P
                FROM SERIES_GENERATE_INTEGER(1, 1, 51) G) WHERE P IS NOT NULL;
    m = SELECT DISTINCT A."AcctCode", A."AcctName", P."Cat"
          FROM "OACT" A JOIN :pre P ON A."AcctCode" LIKE P."Prefix" || '%'
         WHERE A."Postable" = 'Y';
    RETURN SELECT "AcctCode", MAX("AcctName") AS "AcctName", LEFT(STRING_AGG("Cat", '；' ORDER BY "Cat"), 500) AS "Cat"
             FROM :m GROUP BY "AcctCode";
END
@@
-- 科目余额表 / 明细账的分录行（Acct 为空串 = 全部成本相关科目）：
--   BEG   本期以前的总账已过账分录，按科目汇总成一行（期初余额）
--   GL    本期总账已过账分录（OJDT / JDT1）；RevOf = 冲销的原凭证的凭证代码（B1 自动冲销，OJDT.StornoToTr），如上月 AR03 / AR04 的冲销
--   VCH   截至期末的未清凭单（OBTF / BTF1，BtfStatus='O'，含本期以前的）
--   DRAFT 本次运行的凭证底稿（R_JDT）；凭证代码属于 COST_TRANSCODES 且本期已在总账过账或已在本期未清凭单中的，Dup='Y'，不计入余额（同财务对账）
CREATE OR REPLACE FUNCTION "MTC_CA_F_TB_LINE" (IN RunId BIGINT, IN Acct NVARCHAR(15))
RETURNS TABLE ("Src" NVARCHAR(10), "AcctCode" NVARCHAR(15), "RefDate" DATE, "TransId" INTEGER, "LineId" INTEGER, "DocNo" NVARCHAR(50),
               "TransCode" NVARCHAR(20), "ObjType" NVARCHAR(20), "BaseRef" NVARCHAR(50), "Memo" NVARCHAR(254),
               "OcrCode" NVARCHAR(20), "VendorCode" NVARCHAR(50), "Debit" DECIMAL(19,2), "Credit" DECIMAL(19,2), "Dup" NVARCHAR(1),
               "RevOf" NVARCHAR(20))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE costCodes NVARCHAR(500);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    costCodes := IFNULL("MTC_CA_F_PARAM"('COST_TRANSCODES', :fc), ',');
    tbAcct = SELECT "AcctCode" FROM "MTC_CA_F_TB_ACCT"(:fc) WHERE :Acct = '' OR "AcctCode" = :Acct;
    -- 同 MTC_CA_F_RECON_LEDGER：按凭证代码 × 科目判断，B1 自动冲销不算（2026-10-17）
    pdc = SELECT DISTINCT "TransCode", "AcctCode" FROM (
              SELECT H."TransCode", J."Account" AS "AcctCode" FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
               WHERE H."RefDate" BETWEEN :d0 AND :d1 AND H."StornoToTr" IS NULL
              UNION ALL
              SELECT T0."TransCode", T1."Account" FROM "OBTF" T0 JOIN "BTF1" T1 ON T1."TransId" = T0."TransId" AND T1."BatchNum" = T0."BatchNum"
               WHERE T0."BtfStatus" = 'O' AND T0."RefDate" BETWEEN :d0 AND :d1)
           WHERE LOCATE(:costCodes, ',' || IFNULL("TransCode", '') || ',') > 0;

    RETURN
    SELECT CAST('BEG' AS NVARCHAR(10)) AS "Src", J."Account" AS "AcctCode", ADD_DAYS(:d0, -1) AS "RefDate",
           CAST(NULL AS INTEGER) AS "TransId", CAST(NULL AS INTEGER) AS "LineId", CAST(NULL AS NVARCHAR(50)) AS "DocNo",
           CAST(NULL AS NVARCHAR(20)) AS "TransCode", CAST(NULL AS NVARCHAR(20)) AS "ObjType", CAST(NULL AS NVARCHAR(50)) AS "BaseRef",
           CAST('期初余额' AS NVARCHAR(254)) AS "Memo", CAST(NULL AS NVARCHAR(20)) AS "OcrCode", CAST(NULL AS NVARCHAR(50)) AS "VendorCode",
           CAST(SUM(J."Debit") AS DECIMAL(19,2)) AS "Debit", CAST(SUM(J."Credit") AS DECIMAL(19,2)) AS "Credit", CAST('N' AS NVARCHAR(1)) AS "Dup",
           CAST(NULL AS NVARCHAR(20)) AS "RevOf"
      FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
     WHERE H."RefDate" < :d0 AND J."Account" IN (SELECT "AcctCode" FROM :tbAcct)
     GROUP BY J."Account"
    UNION ALL
    SELECT 'GL', J."Account", TO_DATE(H."RefDate"), H."TransId", J."Line_ID", TO_NVARCHAR(H."Number"),
           H."TransCode", TO_NVARCHAR(H."TransType"), H."BaseRef", LEFT(COALESCE(NULLIF(J."LineMemo", ''), H."Memo"), 254),
           J."ProfitCode", J."U_VendorCode", J."Debit", J."Credit", 'N', IFNULL(R."TransCode", CASE WHEN H."StornoToTr" IS NOT NULL THEN '冲销' END)
      FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
      LEFT JOIN "OJDT" R ON R."TransId" = H."StornoToTr"
     WHERE H."RefDate" BETWEEN :d0 AND :d1 AND J."Account" IN (SELECT "AcctCode" FROM :tbAcct)
    UNION ALL
    SELECT 'VCH', T1."Account", TO_DATE(T0."RefDate"), T0."TransId", T1."Line_ID", T0."BatchNum" || '/' || T0."TransId",
           T0."TransCode", NULL, NULL, LEFT(COALESCE(NULLIF(T1."LineMemo", ''), T0."Memo"), 254),
           T1."ProfitCode", T1."U_VendorCode", T1."Debit", T1."Credit", 'N', NULL
      FROM "OBTF" T0 JOIN "BTF1" T1 ON T1."TransId" = T0."TransId" AND T1."BatchNum" = T0."BatchNum"
     WHERE T0."BtfStatus" = 'O' AND T0."RefDate" <= :d1 AND T1."Account" IN (SELECT "AcctCode" FROM :tbAcct)
    UNION ALL
    SELECT 'DRAFT', D."AcctCode", :d1, NULL, D."LineNo", NULL,
           D."TransCode", NULL, NULL, CASE WHEN P."TransCode" IS NOT NULL THEN '本期已过账或已在未清凭单中，不计入余额' END,
           D."OcrCode", D."VendorCode", D."Debit", D."Credit", CASE WHEN P."TransCode" IS NOT NULL THEN 'Y' ELSE 'N' END, NULL
      FROM "MTC_CA_R_JDT" D LEFT JOIN :pdc P ON P."TransCode" = D."TransCode" AND P."AcctCode" = D."AcctCode"
     WHERE D."RunId" = :RunId AND D."AcctCode" IN (SELECT "AcctCode" FROM :tbAcct);
END
@@
-- PUR1–PUR5 逐单据勾稽（POST-15，用户 2026-10-30）。只读。
-- PUR1–PUR5 的目的：B1 按标准成本自动生成收货 / 退货 / 发票凭证，金额不是公司要的入账价（期初和上线后部分单据系统 Price 有误、
-- 单据又不能改不能取消，行上另填 U_InitPrice；2026 年起几乎没有，但仍有未开票收货会用到）。PUR 把系统凭证在存货、暂估、加工费科目上的
-- 金额冲掉，按暂估口径（U_InitPrice → U_IsPrice='Y' 已确认价 → LineTotal）重记，开票时冲暂估、差额进存货 / 140803（再经 MR01 进产品）。
-- 所以每张采购单据：系统凭证 + PUR 冲回 + PUR 重记（+ MR01）= 业务端，按 单据 × 科目 逐行比较：
--   AP     应付暂估 220202     业务 = −本单据的暂估变动（S_AP_MOVE.AccrAmt，贷方为负）
--   STOCK  存货（OGAR.StockAct）业务 = 本单据计入物料成本的金额（R_LINE，含委外发票差异进产品的 APDIF）
--   FEE    委外加工费 140802   业务 = 本单据加工费物料的暂估、退货（S_AP_MOVE）
--   FEEDIF 140803              业务 = 0（PUR3 借 = MR01 贷）
--   VAR    价格差异（OGAR.PricDifAct / VariancAct + 参数 PUR_STDVAR_ACCTS）业务 = 0：标准成本留下的差异应全部清掉（Q23 的情况会出现在这里）
--   KEEP   业务伙伴行（ShortName ≠ Account）和税额行（VatLine='Y'）：系统凭证原样保留，不比较
--   OTHER  其他科目：收货 / 退货（20 / 21）业务 = 0（PUR5 全部冲回）；发票 / 贷项（18 / 19）系统凭证原样保留，不比较
-- 范围：本期有暂估变动、有 PUR / MR01 底稿、或计入物料成本的采购单据（含取消单），以及它们本期的系统凭证（OJDT.TransType + CreatedBy）。
CREATE OR REPLACE FUNCTION "MTC_CA_F_PUR_DOC" (IN RunId BIGINT)
RETURNS TABLE ("ObjType" NVARCHAR(2), "DocEntry" INTEGER, "DocNum" INTEGER, "CardCode" NVARCHAR(50), "Role" NVARCHAR(10),
               "AcctCode" NVARCHAR(15), "SysAmt" DECIMAL(19,2), "PurRev" DECIMAL(19,2), "PurBook" DECIMAL(19,2), "Mr01" DECIMAL(19,2),
               "FinAmt" DECIMAL(19,2), "BizAmt" DECIMAL(19,2), "Diff" DECIMAL(19,2), "InitLines" INT, "HasSysJe" NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE apAcct NVARCHAR(15); DECLARE wwFee NVARCHAR(15); DECLARE wwDif NVARCHAR(15); DECLARE varX NVARCHAR(500);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    apAcct := "MTC_CA_F_ACCT"('AP_ACCRUAL', :fc);
    wwFee := "MTC_CA_F_ACCT"('WW_FEE', :fc);
    wwDif := "MTC_CA_F_ACCT"('WW_FEE_DIF', :fc);
    varX := IFNULL("MTC_CA_F_PARAM"('PUR_STDVAR_ACCTS', :fc), ',');

    -- 科目角色（一个科目只取一个，优先级 AP > FEE > FEEDIF > STOCK > VAR）
    stockAct = SELECT TO_NVARCHAR("ItmsGrpCod") AS "ItmsGrpCod", MAX("StockAct") AS "Acct"
                 FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4) GROUP BY "ItmsGrpCod";
    role0 = SELECT :apAcct AS "AcctCode", 1 AS "Pri", 'AP' AS "Role" FROM DUMMY
            UNION ALL SELECT :wwFee, 2, 'FEE' FROM DUMMY
            UNION ALL SELECT :wwDif, 3, 'FEEDIF' FROM DUMMY
            UNION ALL SELECT DISTINCT "StockAct", 4, 'STOCK' FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4)
            UNION ALL SELECT DISTINCT "PricDifAct", 5, 'VAR' FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4)
            UNION ALL SELECT DISTINCT "VariancAct", 5, 'VAR' FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4)
            UNION ALL SELECT "AcctCode", 5, 'VAR' FROM "OACT" WHERE LOCATE(:varX, ',' || "AcctCode" || ',') > 0;
    roles = SELECT "AcctCode", MAX("Role") AS "Role" FROM (
                SELECT "AcctCode", "Role", RANK() OVER (PARTITION BY "AcctCode" ORDER BY "Pri") AS "Rk"
                  FROM :role0 WHERE IFNULL("AcctCode", '') <> '')
             WHERE "Rk" = 1 GROUP BY "AcctCode";

    -- 本期暂估变动（含取消单）
    mv = SELECT * FROM "MTC_CA_S_AP_MOVE" WHERE "RunId" = :RunId AND "DocDate" BETWEEN :d0 AND :d1;

    -- PUR / MR01 底稿 → 单据：GL = 冲回的系统凭证行（TransId-Line_ID）；DOC = 单据行（ObjType-DocEntry-LineNum）；MR01 = APDIF 的 S_LINE
    pur = SELECT "TransCode", "AcctCode", "Amount", "SrcType", "SrcKey" FROM "MTC_CA_R_JDT_SRC"
           WHERE "RunId" = :RunId AND "TransCode" IN ('PUR1', 'PUR2', 'PUR3', 'PUR4', 'PUR5', 'MR01');
    purM = SELECT TO_NVARCHAR(H."TransType") AS "ObjType", H."CreatedBy" AS "DocEntry", P."AcctCode", P."Amount", 'REV' AS "Kind"
             FROM :pur P
             JOIN "JDT1" J ON J."TransId" = TO_INTEGER(SUBSTR_BEFORE(P."SrcKey", '-')) AND J."Line_ID" = TO_INTEGER(SUBSTR_AFTER(P."SrcKey", '-'))
             JOIN "OJDT" H ON H."TransId" = J."TransId"
            WHERE P."SrcType" = 'GL'
           UNION ALL
           SELECT SUBSTR_BEFORE(P."SrcKey", '-'), TO_INTEGER(SUBSTR_BEFORE(SUBSTR_AFTER(P."SrcKey", '-'), '-')), P."AcctCode", P."Amount", 'BOOK'
             FROM :pur P WHERE P."SrcType" = 'DOC'
           UNION ALL
           SELECT S."ObjType", S."DocEntry", P."AcctCode", P."Amount", 'MR01'
             FROM :pur P JOIN "MTC_CA_S_LINE" S ON S."RunId" = :RunId AND TO_NVARCHAR(S."LineId") = P."SrcKey"
            WHERE P."TransCode" = 'MR01' AND P."SrcType" = 'LINE';

    -- 业务端计入物料成本的金额（采购单据行，含 APDIF）
    biz = SELECT S."ObjType", S."DocEntry", SA."Acct" AS "AcctCode", L."Amount"
            FROM "MTC_CA_R_LINE" L
            JOIN "MTC_CA_S_LINE" S ON S."RunId" = L."RunId" AND S."LineId" = L."LineId"
            LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = L."RunId" AND I."ItemCode" = L."ItemCode"
            LEFT JOIN :stockAct SA ON SA."ItmsGrpCod" = I."ItmsGrpCod"
           WHERE L."RunId" = :RunId AND S."ObjType" IN ('18', '19', '20', '21') AND L."Amount" <> 0;

    docs = SELECT DISTINCT "ObjType", "DocEntry" FROM (
               SELECT "ObjType", "DocEntry" FROM :mv
               UNION ALL SELECT "ObjType", "DocEntry" FROM :purM
               UNION ALL SELECT "ObjType", "DocEntry" FROM :biz);

    sys = SELECT TO_NVARCHAR(H."TransType") AS "ObjType", H."CreatedBy" AS "DocEntry", J."Account" AS "AcctCode", J."Debit" - J."Credit" AS "Amt",
                 CASE WHEN J."ShortName" <> J."Account" OR J."VatLine" = 'Y' THEN 'Y' ELSE 'N' END AS "Keep"
            FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
            JOIN :docs D ON D."ObjType" = TO_NVARCHAR(H."TransType") AND D."DocEntry" = H."CreatedBy"
           WHERE H."RefDate" BETWEEN :d0 AND :d1 AND H."TransType" IN ('18', '19', '20', '21');

    -- 指定单价（U_InitPrice ≠ 0）的暂估行：本期变动涉及几条
    init = SELECT M."ObjType", M."DocEntry", COUNT(DISTINCT M."BaseObj" || '-' || M."BaseEntry" || '-' || M."BaseLine") AS "N"
             FROM :mv M
             LEFT JOIN "PDN1" P ON M."BaseObj" = '20' AND P."DocEntry" = M."BaseEntry" AND P."LineNum" = M."BaseLine"
             LEFT JOIN "RPD1" R ON M."BaseObj" = '21' AND R."DocEntry" = M."BaseEntry" AND R."LineNum" = M."BaseLine"
            WHERE IFNULL(COALESCE(P."U_InitPrice", R."U_InitPrice"), 0) <> 0
            GROUP BY M."ObjType", M."DocEntry";

    u = SELECT "ObjType", "DocEntry", CASE WHEN "Keep" = 'Y' THEN 'KEEP' END AS "R0", "AcctCode",
               "Amt" AS "Sys", 0 AS "Rev", 0 AS "Book", 0 AS "Mr", 0 AS "Biz" FROM :sys
        UNION ALL SELECT "ObjType", "DocEntry", NULL, "AcctCode", 0, "Amount", 0, 0, 0 FROM :purM WHERE "Kind" = 'REV'
        UNION ALL SELECT "ObjType", "DocEntry", NULL, "AcctCode", 0, 0, "Amount", 0, 0 FROM :purM WHERE "Kind" = 'BOOK'
        UNION ALL SELECT "ObjType", "DocEntry", NULL, "AcctCode", 0, 0, 0, "Amount", 0 FROM :purM WHERE "Kind" = 'MR01'
        UNION ALL SELECT "ObjType", "DocEntry", NULL, :apAcct, 0, 0, 0, 0, -SUM("AccrAmt") FROM :mv GROUP BY "ObjType", "DocEntry"
        UNION ALL SELECT "ObjType", "DocEntry", NULL, :wwFee, 0, 0, 0, 0, SUM("AccrAmt") FROM :mv
                   WHERE "AccrType" = 'SUBFEE' AND "MoveType" IN ('ACCR', 'RET') GROUP BY "ObjType", "DocEntry"
        UNION ALL SELECT "ObjType", "DocEntry", NULL, "AcctCode", 0, 0, 0, 0, "Amount" FROM :biz;

    g = SELECT U."ObjType", U."DocEntry",
               CASE WHEN U."R0" = 'KEEP' THEN 'KEEP' ELSE IFNULL(R."Role", 'OTHER') END AS "Role", U."AcctCode",
               ROUND(SUM(U."Sys"), 2) AS "Sys", ROUND(SUM(U."Rev"), 2) AS "Rev", ROUND(SUM(U."Book"), 2) AS "Book",
               ROUND(SUM(U."Mr"), 2) AS "Mr", ROUND(SUM(U."Biz"), 2) AS "Biz"
          FROM :u U LEFT JOIN :roles R ON R."AcctCode" = U."AcctCode"
         GROUP BY U."ObjType", U."DocEntry", CASE WHEN U."R0" = 'KEEP' THEN 'KEEP' ELSE IFNULL(R."Role", 'OTHER') END, U."AcctCode";

    hdr = SELECT '20' AS "ObjType", "DocEntry", "DocNum", "CardCode" FROM "OPDN" WHERE "DocEntry" IN (SELECT "DocEntry" FROM :docs WHERE "ObjType" = '20')
          UNION ALL SELECT '21', "DocEntry", "DocNum", "CardCode" FROM "ORPD" WHERE "DocEntry" IN (SELECT "DocEntry" FROM :docs WHERE "ObjType" = '21')
          UNION ALL SELECT '18', "DocEntry", "DocNum", "CardCode" FROM "OPCH" WHERE "DocEntry" IN (SELECT "DocEntry" FROM :docs WHERE "ObjType" = '18')
          UNION ALL SELECT '19', "DocEntry", "DocNum", "CardCode" FROM "ORPC" WHERE "DocEntry" IN (SELECT "DocEntry" FROM :docs WHERE "ObjType" = '19');
    je = SELECT DISTINCT "ObjType", "DocEntry" FROM :sys;

    RETURN SELECT CAST(G."ObjType" AS NVARCHAR(2)) AS "ObjType", G."DocEntry", H."DocNum", CAST(H."CardCode" AS NVARCHAR(50)) AS "CardCode",
                  CAST(G."Role" AS NVARCHAR(10)) AS "Role", CAST(G."AcctCode" AS NVARCHAR(15)) AS "AcctCode",
                  CAST(G."Sys" AS DECIMAL(19,2)) AS "SysAmt", CAST(G."Rev" AS DECIMAL(19,2)) AS "PurRev",
                  CAST(G."Book" AS DECIMAL(19,2)) AS "PurBook", CAST(G."Mr" AS DECIMAL(19,2)) AS "Mr01",
                  CAST(G."Sys" + G."Rev" + G."Book" + G."Mr" AS DECIMAL(19,2)) AS "FinAmt",
                  CAST(CASE WHEN G."Role" = 'KEEP' OR (G."Role" = 'OTHER' AND G."ObjType" IN ('18', '19')) THEN NULL ELSE G."Biz" END AS DECIMAL(19,2)) AS "BizAmt",
                  CAST(CASE WHEN G."Role" = 'KEEP' OR (G."Role" = 'OTHER' AND G."ObjType" IN ('18', '19')) THEN NULL
                            ELSE G."Sys" + G."Rev" + G."Book" + G."Mr" - G."Biz" END AS DECIMAL(19,2)) AS "Diff",
                  CAST(IFNULL(I."N", 0) AS INT) AS "InitLines",
                  CAST(CASE WHEN J."DocEntry" IS NULL THEN 'N' ELSE 'Y' END AS NVARCHAR(1)) AS "HasSysJe"
             FROM :g G
             LEFT JOIN :hdr H ON H."ObjType" = G."ObjType" AND H."DocEntry" = G."DocEntry"
             LEFT JOIN :init I ON I."ObjType" = G."ObjType" AND I."DocEntry" = G."DocEntry"
             LEFT JOIN :je J ON J."ObjType" = G."ObjType" AND J."DocEntry" = G."DocEntry";
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P75_POSTCHECK" (IN RunId BIGINT, OUT FailCnt INT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE basis NVARCHAR(10); DECLARE posted NVARCHAR(1000); DECLARE rmsg NVARCHAR(1000); DECLARE oth DECIMAL(19,2);
    DECLARE blockOn NVARCHAR(10); DECLARE gmsg NVARCHAR(1000); DECLARE wmsg NVARCHAR(1000);
    DECLARE custDom NVARCHAR(50); DECLARE custExp NVARCHAR(50);
    DECLARE nSub INT;
    DECLARE initFrom DATE; DECLARE feeItem NVARCHAR(50);
    DECLARE nPurDoc INT; DECLARE nPurBad INT; DECLARE nInit INT; DECLARE initAmt DECIMAL(19,2);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    custDom := IFNULL("MTC_CA_F_PARAM"('CUST_DOM', :fc), '国内客户');   -- 客户类型（参数，2026-10-27）
    custExp := IFNULL("MTC_CA_F_PARAM"('CUST_EXP', :fc), '国外客户');

    -- POST-08 借贷平衡、科目齐全
    t08 = SELECT "TransCode" AS "KeyCode", '借方 ' || TO_NVARCHAR(SUM("Debit")) || ' ≠ 贷方 ' || TO_NVARCHAR(SUM("Credit")) AS "Info"
            FROM "MTC_CA_R_JDT" WHERE "RunId" = :RunId GROUP BY "TransCode" HAVING ABS(SUM("Debit") - SUM("Credit")) > 0.001
          UNION ALL
          SELECT "TransCode" || '-' || "SrcType" || '-' || IFNULL("SrcKey", ''), '取不到科目，金额 ' || TO_NVARCHAR("Amount")
            FROM "MTC_CA_R_JDT_SRC" WHERE "RunId" = :RunId AND "AcctCode" IS NULL;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-08', :t08, NULL);

    -- POST-06 / 09 / 10 / 11 / 13 财务端与业务端对账：期初 / 本期 / 期末分开列示（MTC_CA_F_RECON），rec."Diff" = 用来判断的那一列差额
    SELECT MAX("Basis"), MAX("PostedCodes") INTO basis, posted FROM "MTC_CA_F_RECON_STATUS"(:RunId);
    -- 按哪一列阻断：CUR = 本期差额（默认，期初差额是承接前就有的，只列示）/ END = 期末差额（用户 2026-10-15）
    blockOn := IFNULL("MTC_CA_F_PARAM"('RECON_BLOCK_ON', :fc), 'CUR');
    rmsg := LEFT('期初 / 本期 / 期末分开列示，按' || CASE WHEN :blockOn = 'END' THEN '期末' ELSE '本期' END || '差额判断；'
                 || '财务本期 = 本期分录 + 底稿中本期尚未过账的凭证；'
                 || CASE WHEN :basis = 'DRAFT' THEN '本期成本凭证都未过账'
                         ELSE '本期已过账（底稿中这部分不再加）：' || IFNULL(:posted, '无（凭证在未清凭单中）') END, 900);
    rec = SELECT "Area", "AcctCode", "KeyCode",
                 '期初：业务 ' || TO_NVARCHAR("BegBiz") || '，财务 ' || TO_NVARCHAR("BegFin") || '，差额 ' || TO_NVARCHAR("BegDiff")
                 || '；本期：业务 ' || TO_NVARCHAR("CurBiz") || '，财务 ' || TO_NVARCHAR("CurFin")
                 || CASE WHEN "PendCodes" IS NOT NULL THEN '（含未过账底稿 ' || TO_NVARCHAR("DraftAmt" - "DupAmt") || '：' || "PendCodes" || '）' ELSE '' END
                 || '，差额 ' || TO_NVARCHAR("CurDiff")
                 || '；期末：业务 ' || TO_NVARCHAR("BizAmt") || '，财务 ' || TO_NVARCHAR("EndFin") || '，差额 ' || TO_NVARCHAR("Diff")
                 || CASE WHEN "DupCodes" IS NOT NULL THEN '。底稿中 ' || "DupCodes" || ' 本期已过账或已在未清凭单（'
                         || TO_NVARCHAR("DupAmt") || '），没有重复加' ELSE '' END
                 || CASE WHEN ABS("OtherAmt") > 0.01 THEN '。不参与对账的分录 ' || TO_NVARCHAR("OtherAmt") ELSE '' END AS "Info",
                 CASE WHEN :blockOn = 'END' THEN "Diff" ELSE "CurDiff" END AS "Diff"
            FROM "MTC_CA_F_RECON"(:RunId);

    -- POST-06 委外：140801 = 委外在产品（材料），140802 = 订单上未结转加工费
    -- 加工费留在订单上的订单（未关闭、本期没有入库，等下次入库结转）只在说明里列示、不阻断（Q35，用户 2026-10-17）；
    -- 截至期末已关闭的订单不再留加工费（P30 按关单转关单差异）
    t06 = SELECT "AcctCode" AS "KeyCode", "Info" FROM :rec WHERE "Area" IN ('WW_MAT', 'WW_FEE') AND ABS("Diff") > 0.01;
    -- 列出金额最大的 30 张（说明最长 1000 字）。没有这种订单时不能执行带 ORDER BY 的 STRING_AGG … INTO（HANA 报 1299 no data found，
    -- 2026-10-30 FH100_COST_TEST 2026-10 加工费全部结转时遇到），先数一下
    SELECT COUNT(*) INTO nSub FROM "MTC_CA_R_ORDER_MAT"
     WHERE "RunId" = :RunId AND "ItemCode" = '#SUBFEE' AND ABS("WipSub") > 0.01;
    wmsg := :rmsg;
    IF :nSub > 0 THEN
    SELECT LEFT(:rmsg || CASE WHEN MAX("Cnt") IS NULL THEN ''
                         ELSE '。加工费留在订单上（未关闭、待下次入库结转，只列示）' || MAX("Cnt") || ' 张，合计 ' || TO_NVARCHAR(ROUND(MAX("Tot"), 2))
                              || '：' || STRING_AGG("K" || ' ' || TO_NVARCHAR(ROUND("Amt", 2)), '、' ORDER BY ABS("Amt") DESC) END, 1000)
      INTO wmsg
      FROM (SELECT M."OrderType" || '-' || M."OrderEntry" AS "K", M."WipSub" AS "Amt",
                   COUNT(*) OVER () AS "Cnt", SUM(M."WipSub") OVER () AS "Tot",
                   ROW_NUMBER() OVER (ORDER BY ABS(M."WipSub") DESC) AS "Rn"
              FROM "MTC_CA_R_ORDER_MAT" M
             WHERE M."RunId" = :RunId AND M."ItemCode" = '#SUBFEE' AND ABS(M."WipSub") > 0.01)
     WHERE "Rn" <= 30;
    END IF;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-06', :t06, :wmsg);

    -- POST-09 存货科目（替代 JZ04 尾差凭证，Q15）
    t09 = SELECT "AcctCode" AS "KeyCode", "Info" FROM :rec WHERE "Area" = 'STOCK' AND ABS("Diff") > 0.01;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-09', :t09, :rmsg);

    -- POST-10 发出商品（用户 2026-10-15）：140601 期末 = 期初 = 0。本期构成：① 冲销上月计提（B1 自动冲销）② 发货 DN01 ③ 样品转出 DN02 / DN04
    -- ④ 发票 DN03 ⑤ 本月计提 AR03 / AR04；合计应为 0。另核对 ① = 上期末未开票（R_GOODS_OUT_BEG）、⑤ = 本期末未开票（R_GOODS_OUT），哪项不等就是哪边的问题
    -- 手工调整（InRecon='N'：GOODS 在 RECON_COSTONLY_AREAS 中时，本期凭证代码不在 COST_TRANSCODES 的分录）单独列出、不算差异，
    -- 期末差额扣除手工调整后应等于期初差额（用户 2026-10-17）
    gp = SELECT IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'REV' THEN "Amt" END), 0) AS "Rev",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'DN01' THEN "Amt" END), 0) AS "Dn01",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'SAMPLE' THEN "Amt" END), 0) AS "Smp",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'DN03' THEN "Amt" END), 0) AS "Dn03",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'ACCR' THEN "Amt" END), 0) AS "Accr",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'TAIL' THEN "Amt" END), 0) AS "Tail",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'OTHER' THEN "Amt" END), 0) AS "Oth",
                IFNULL(SUM(CASE WHEN "InRecon" = 'N' THEN "Amt" END), 0) AS "Man"
           FROM "MTC_CA_F_RECON_LEDGER"(:RunId)
          WHERE "Area" = 'GOODS' AND "Phase" = 'CUR' AND NOT ("Src" = 'DRAFT' AND "Dup" = 'Y');
    gb = SELECT (SELECT IFNULL(SUM("CostAmt"), 0) FROM "MTC_CA_R_GOODS_OUT_BEG" WHERE "RunId" = :RunId AND "IsSample" = 'N') AS "Beg",
                (SELECT IFNULL(SUM("CostAmt"), 0) FROM "MTC_CA_R_GOODS_OUT" WHERE "RunId" = :RunId AND "IsSample" = 'N') AS "End" FROM DUMMY;
    SELECT LEFT('本期构成：① 冲销上月计提 ' || TO_NVARCHAR(G."Rev") || '，② 发货 ' || TO_NVARCHAR(G."Dn01") || '，③ 样品转出 ' || TO_NVARCHAR(G."Smp")
                || '，④ 发票 ' || TO_NVARCHAR(G."Dn03") || '，⑤ 本月计提 ' || TO_NVARCHAR(G."Accr")
                || CASE WHEN G."Tail" <> 0 THEN '，尾差结转 JZ04 ' || TO_NVARCHAR(G."Tail") ELSE '' END
                || CASE WHEN G."Oth" <> 0 THEN '，其他凭证 ' || TO_NVARCHAR(G."Oth") ELSE '' END
                || '；合计 ' || TO_NVARCHAR(G."Rev" + G."Dn01" + G."Smp" + G."Dn03" + G."Accr" + G."Tail" + G."Oth") || '（应为 0）'
                || CASE WHEN G."Man" <> 0 THEN '；另有手工调整 ' || TO_NVARCHAR(G."Man") || '（不参与对账，期末差额扣除后应等于期初差额）' ELSE '' END || '。'
                || '上期末未开票 ' || TO_NVARCHAR(B."Beg") || '，本期末未开票 ' || TO_NVARCHAR(B."End") || '。' || :rmsg, 1000)
      INTO gmsg FROM :gp G, :gb B;
    -- 140601 差额一分钱也不放过（用户 2026-11-01：财务不允许 0.01；±GOODS_TAIL_MAX 以内的尾差 P70 已用 JZ04 转入 640101）
    t10 = SELECT "AcctCode" AS "KeyCode", "Info" FROM :rec WHERE "Area" = 'GOODS' AND ABS("Diff") >= 0.005
          UNION ALL
          SELECT '① 冲销上月计提', '冲销 ' || TO_NVARCHAR(G."Rev") || ' ≠ 上期末未开票 ' || TO_NVARCHAR(B."Beg") || '，差 ' || TO_NVARCHAR(G."Rev" - B."Beg")
                 || '：上月计提与上期末未开票明细不一致（如旧框架按当前未清数量计提），或上月计提没有自动冲销'
            FROM :gp G, :gb B WHERE ABS(G."Rev" - B."Beg") > 0.01
          UNION ALL
          SELECT '⑤ 本月计提', '计提 ' || TO_NVARCHAR(-G."Accr") || ' ≠ 本期末未开票 ' || TO_NVARCHAR(B."End") || '，差 ' || TO_NVARCHAR(-G."Accr" - B."End")
                 || '：有未开票交货没有客户类型（POST-12）或单位成本为空'
            FROM :gp G, :gb B WHERE ABS(-G."Accr" - B."End") > 0.01;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-10', :t10, :gmsg);

    -- POST-11 应付暂估：220202 按 U_VendorCode = 应付暂估（按供应商）
    t11 = SELECT CASE WHEN "KeyCode" = '' THEN '（无供应商）' ELSE "KeyCode" END AS "KeyCode", "Info" FROM :rec WHERE "Area" = 'AP' AND ABS("Diff") > 0.01;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-11', :t11, :rmsg);

    -- POST-13 生产在产品：500101 的成本凭证 = 生产 / 包装 / 返工订单在产品（不含加工费）；
    -- 非成本凭证分录允许存在，不参与比较，金额写进说明（用户 2026-10-13）
    t13 = SELECT "AcctCode" AS "KeyCode", "Info" FROM :rec WHERE "Area" = 'WIP_PROD' AND ABS("Diff") > 0.01;
    SELECT IFNULL(SUM("OtherAmt"), 0) INTO oth FROM "MTC_CA_F_RECON"(:RunId) WHERE "Area" = 'WIP_PROD';
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-13', :t13,
         :rmsg || CASE WHEN ABS(:oth) > 0.01 THEN '；另有非成本凭证分录 ' || TO_NVARCHAR(:oth) || '（本期分录，允许，不参与对账，见执行台“财务对账”）' ELSE '' END);

    -- POST-12 销售成本取价：找不到交货成本、没有客户类型
    t12 = SELECT "MTC_CA_F_DOCKEY"("ObjType", "DocEntry") || '-LineNum ' || "LineNum" AS "KeyCode", '找不到交货 / 退货行成本' AS "Info"
            FROM "MTC_CA_R_DNCOST" WHERE "RunId" = :RunId AND "UnitCost" IS NULL
          UNION ALL
          SELECT "MTC_CA_F_DOCKEY"("ObjType", "DocEntry") || '-LineNum ' || "LineNum", '未开票交货没有客户类型，AR03/AR04 不计提'
            FROM "MTC_CA_R_GOODS_OUT" WHERE "RunId" = :RunId AND "IsSample" = 'N' AND IFNULL("CustType", '') NOT IN (:custDom, :custExp);
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-12', :t12, NULL);

    -- POST-15 PUR1–PUR5 与业务端逐单据勾稽（用户 2026-10-30，只警告：参数 POST_WARN_IDS）。
    -- ① 单据 × 科目：系统凭证 + PUR 冲回 + PUR 重记（+ MR01）≠ 业务端（MTC_CA_F_PUR_DOC，口径见函数头）
    -- ② 有暂估变动的单据本期没有系统凭证（PUR5 / PUR2 没有可冲回的分录）
    -- ③ 暂估行已全部开票 / 退回，暂估金额没有清零（Q27 清余数没生效）
    -- ④ 加工费收货 / 退货：PUR4 记 140802 的金额 ≠ 计入订单的加工费（两边都取 S_AP_MOVE 暂估金额，用户 2026-10-30 方案 B；差额通常是没关联生产收货 U_BaseType=59）
    -- ⑤ 收货 / 退货中既不是库存物料也不是加工费物料的行：PUR5 冲掉了系统分录、不重记（Q25），列出核对
    -- ⑥ 本期新收货 / 退货用了指定单价 U_InitPrice（参数 INITPRICE_NEW_FROM 起；2026 年起应很少出现，确认系统 Price 确实有误）
    -- ⑦ 已过账（OJDT）的 PUR1–PUR5 按 代码 × 科目 × 供应商 ≠ 本次底稿（只比较本期已过账的代码）
    initFrom := TO_DATE(IFNULL("MTC_CA_F_PARAM"('INITPRICE_NEW_FROM', :fc), '2026-01-01'));
    feeItem := IFNULL("MTC_CA_F_PARAM"('SUBFEE_ITEM', :fc), 'X0510001');
    pd = SELECT * FROM "MTC_CA_F_PUR_DOC"(:RunId);
    t15 = SELECT "MTC_CA_F_DOCKEY"("ObjType", "DocEntry") || ' ' || MAP("Role", 'AP', '应付暂估', 'STOCK', '存货', 'FEE', '委外加工费', 'FEEDIF', '加工费差异',
                 'VAR', '价格差异', '其他科目') || ' ' || "AcctCode" AS "KeyCode",
                 '① 系统凭证 ' || TO_NVARCHAR("SysAmt") || '，PUR 冲回 ' || TO_NVARCHAR("PurRev") || '，PUR 重记 ' || TO_NVARCHAR("PurBook")
                 || CASE WHEN "Mr01" <> 0 THEN '，MR01 ' || TO_NVARCHAR("Mr01") ELSE '' END
                 || '，财务合计 ' || TO_NVARCHAR("FinAmt") || '；业务 ' || TO_NVARCHAR("BizAmt") || '；差 ' || TO_NVARCHAR("Diff")
                 || CASE WHEN "Role" = 'VAR' THEN '（标准成本差异没有清掉，见 Q23）'
                         WHEN "Role" = 'OTHER' THEN '（收货 / 退货的系统分录没有全部冲回）' ELSE '' END
                 || CASE WHEN "InitLines" > 0 THEN '；涉及指定单价 U_InitPrice 的暂估行 ' || "InitLines" || ' 条' ELSE '' END
                 || CASE WHEN "HasSysJe" = 'N' THEN '；本期没有系统凭证' ELSE '' END AS "Info"
            FROM :pd WHERE ABS(IFNULL("Diff", 0)) > 0.01
          UNION ALL
          SELECT DISTINCT "MTC_CA_F_DOCKEY"(M."ObjType", M."DocEntry") || ' 没有系统凭证',
                 '② 本期有暂估变动，但找不到 B1 自动生成的凭证（OJDT.TransType = ' || M."ObjType" || '，CreatedBy = DocEntry），PUR5 / PUR2 没有可冲回的分录'
            FROM "MTC_CA_S_AP_MOVE" M
           WHERE M."RunId" = :RunId AND M."DocDate" BETWEEN :d0 AND :d1
             AND NOT EXISTS (SELECT 1 FROM "OJDT" H WHERE TO_NVARCHAR(H."TransType") = M."ObjType" AND H."CreatedBy" = M."DocEntry")
          UNION ALL
          SELECT "MTC_CA_F_DOCKEY"("BaseObj", "BaseEntry") || '-LineNum ' || "BaseLine" || ' 暂估没清零',
                 '③ 已全部开票 / 退回（未清数量 0），暂估余 ' || TO_NVARCHAR(SUM("AccrAmt"))
            FROM "MTC_CA_S_AP_MOVE" WHERE "RunId" = :RunId
           GROUP BY "BaseObj", "BaseEntry", "BaseLine"
          HAVING ABS(SUM("Qty")) <= 0.000001 AND ABS(SUM("AccrAmt")) >= 0.01 AND MAX("DocDate") >= :d0
          UNION ALL
          SELECT "MTC_CA_F_DOCKEY"("ObjType", "DocEntry") || '-LineNum ' || "LineNum" || ' 加工费',
                 '④ PUR4 记 140802 ' || TO_NVARCHAR("Pur") || '，计入订单加工费 ' || TO_NVARCHAR("Ord") || '，差 ' || TO_NVARCHAR("Pur" - "Ord")
                 || CASE WHEN "Init" = 'Y' THEN '（这行用了指定单价 U_InitPrice）' ELSE '' END
                 || CASE WHEN "Ord" = 0 THEN '（没有关联生产收货 U_BaseType=59，加工费没进订单）' ELSE '' END
            FROM (SELECT "ObjType", "DocEntry", "LineNum", SUM("Pur") AS "Pur", SUM("Ord") AS "Ord", MAX("Init") AS "Init" FROM (
                      SELECT M."ObjType", M."DocEntry", M."LineNum", ROUND(M."AccrAmt", 2) AS "Pur", 0 AS "Ord",
                             CASE WHEN IFNULL(COALESCE(P."U_InitPrice", R."U_InitPrice"), 0) <> 0 THEN 'Y' ELSE 'N' END AS "Init"
                        FROM "MTC_CA_S_AP_MOVE" M
                        LEFT JOIN "PDN1" P ON M."BaseObj" = '20' AND P."DocEntry" = M."BaseEntry" AND P."LineNum" = M."BaseLine"
                        LEFT JOIN "RPD1" R ON M."BaseObj" = '21' AND R."DocEntry" = M."BaseEntry" AND R."LineNum" = M."BaseLine"
                       WHERE M."RunId" = :RunId AND M."AccrType" = 'SUBFEE' AND M."MoveType" IN ('ACCR', 'RET') AND M."DocDate" BETWEEN :d0 AND :d1
                      UNION ALL
                      SELECT CASE WHEN "Src" = 'PDN' THEN '20' ELSE '21' END, TO_INTEGER(SUBSTR_BEFORE("SrcKey", '-')),
                             TO_INTEGER(SUBSTR_AFTER("SrcKey", '-')), 0, ROUND("Amount", 2), 'N'
                        FROM "MTC_CA_S_SUBFEE" WHERE "RunId" = :RunId AND "Src" IN ('PDN', 'RPD'))
                  GROUP BY "ObjType", "DocEntry", "LineNum")
           WHERE ABS("Pur" - "Ord") > 0.01
          UNION ALL
          SELECT "MTC_CA_F_DOCKEY"(X."ObjType", X."DocEntry") || '-LineNum ' || X."LineNum" || ' 非库存',
                 '⑤ ' || X."ItemCode" || ' 不是库存物料也不是加工费物料，金额 ' || TO_NVARCHAR(ROUND(X."LineTotal", 2))
                 || '：PUR5 冲掉了收货的系统分录、不重记（Q25 按发票处理），确认开票时费用已入账'
            FROM (SELECT '20' AS "ObjType", M."DocEntry", D."LineNum", D."ItemCode", D."LineTotal"
                    FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry" WHERE M."DocDate" BETWEEN :d0 AND :d1
                  UNION ALL
                  SELECT '21', M."DocEntry", D."LineNum", D."ItemCode", -D."LineTotal"
                    FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry" WHERE M."DocDate" BETWEEN :d0 AND :d1) X
            JOIN "OITM" I ON I."ItemCode" = X."ItemCode"
           WHERE I."InvntItem" <> 'Y' AND X."ItemCode" <> :feeItem AND X."LineTotal" <> 0
          UNION ALL
          SELECT "MTC_CA_F_DOCKEY"(X."ObjType", X."DocEntry") || '-LineNum ' || X."LineNum" || ' 指定单价',
                 '⑥ 本期新单据用了指定单价 U_InitPrice ' || TO_NVARCHAR(X."U_InitPrice") || '（系统 Price ' || TO_NVARCHAR(X."Price")
                 || '），暂估按指定单价计：' || TO_NVARCHAR(:initFrom) || ' 以后应很少出现，确认系统 Price 确实有误'
            FROM (SELECT '20' AS "ObjType", M."DocEntry", D."LineNum", D."U_InitPrice", D."Price", M."DocDate"
                    FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry"
                  UNION ALL
                  SELECT '21', M."DocEntry", D."LineNum", D."U_InitPrice", D."Price", M."DocDate"
                    FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry") X
           WHERE X."DocDate" BETWEEN :d0 AND :d1 AND X."DocDate" >= :initFrom AND IFNULL(X."U_InitPrice", 0) <> 0
          UNION ALL
          SELECT "TransCode" || ' ' || "AcctCode" || CASE WHEN "Vendor" <> '' THEN ' ' || "Vendor" ELSE '' END || ' 已过账',
                 '⑦ B1 已过账 ' || TO_NVARCHAR(SUM("Gl")) || '，本次底稿 ' || TO_NVARCHAR(SUM("Dr")) || '，差 ' || TO_NVARCHAR(SUM("Gl") - SUM("Dr"))
            FROM (SELECT H."TransCode", J."Account" AS "AcctCode", IFNULL(J."U_VendorCode", '') AS "Vendor", J."Debit" - J."Credit" AS "Gl", 0 AS "Dr"
                    FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
                   WHERE H."RefDate" BETWEEN :d0 AND :d1 AND H."TransCode" IN ('PUR1', 'PUR2', 'PUR3', 'PUR4', 'PUR5') AND H."StornoToTr" IS NULL
                  UNION ALL
                  SELECT "TransCode", "AcctCode", IFNULL("VendorCode", ''), 0, "Debit" - "Credit"
                    FROM "MTC_CA_R_JDT" WHERE "RunId" = :RunId
                     AND "TransCode" IN (SELECT DISTINCT "TransCode" FROM "OJDT"
                                          WHERE "RefDate" BETWEEN :d0 AND :d1 AND "TransCode" IN ('PUR1', 'PUR2', 'PUR3', 'PUR4', 'PUR5') AND "StornoToTr" IS NULL))
           GROUP BY "TransCode", "AcctCode", "Vendor"
          HAVING ABS(SUM("Gl") - SUM("Dr")) > 0.01;
    SELECT COUNT(DISTINCT "ObjType" || '-' || "DocEntry"), IFNULL(SUM(CASE WHEN ABS(IFNULL("Diff", 0)) > 0.01 THEN 1 ELSE 0 END), 0)
      INTO nPurDoc, nPurBad FROM :pd;
    SELECT COUNT(*), IFNULL(SUM("OpenAmt"), 0) INTO nInit, initAmt
      FROM "MTC_CA_R_AP_ACCR" A
      LEFT JOIN "PDN1" P ON A."ObjType" = '20' AND P."DocEntry" = A."DocEntry" AND P."LineNum" = A."LineNum"
      LEFT JOIN "RPD1" R ON A."ObjType" = '21' AND R."DocEntry" = A."DocEntry" AND R."LineNum" = A."LineNum"
     WHERE A."RunId" = :RunId AND IFNULL(COALESCE(P."U_InitPrice", R."U_InitPrice"), 0) <> 0;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-15', :t15,
         LEFT('本期采购单据 ' || :nPurDoc || ' 张，单据 × 科目不一致 ' || :nPurBad || ' 行（逐行见执行台“应付暂估 → 凭证勾稽”）。'
              || '截至期末仍未开票、按指定单价 U_InitPrice 暂估的行 ' || :nInit || ' 条，暂估金额 ' || TO_NVARCHAR(:initAmt)
              || '（期初和上线后系统 Price 有误的单据，开票时按指定单价冲暂估、差额进存货）。只警告，不阻断生成凭单。', 1000));

    SELECT COUNT(*) INTO FailCnt FROM "MTC_CA_R_CHECK"
     WHERE "RunId" = :RunId AND "CheckId" IN ('POST-06', 'POST-08', 'POST-09', 'POST-10', 'POST-11', 'POST-12', 'POST-13') AND "Result" = 'FAIL';
END
