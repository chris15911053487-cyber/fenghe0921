-- =====================================================================
-- 成本报表勾稽语句（21_reports.sql 的配套，用户 2026-10-30）：只读，每段返回一行 “编号 · 说明 · 账期数 · 不通过数”。
-- 覆盖新框架所有已计算账期（MTC_CA_F_RPT_RUN 取数规则，和报表一致；承接账期及以前的历史运行由 22_legacy_verify.sql H 段核对，2026-11-02）；不通过数应为 0，只把不为 0 的编号反馈即可（不要贴明细）。
-- 用法：python3 新框架/tools/hana_exec.py -f 新框架/sql/21_reports_verify.sql
-- 差额容忍 0.05（各报表按 2 位小数取整后再加总的误差）。离线写的，还没执行过。
-- =====================================================================
-- V01 R01 / R02 完工成本合计 = R03 生产入库（I03 / I07 / I08 / I09 / I90 的入库金额）
SELECT 'V01' AS "编号", 'R01/R02 完工成本 = R03 生产入库' AS "说明", COUNT(*) AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(O."Amt", 0) - IFNULL(L."Amt", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
  LEFT JOIN (SELECT "RunId", SUM("CostAmt") AS "Amt" FROM "MTC_CA_R_ORDER" GROUP BY "RunId") O ON O."RunId" = U."RunId"
  LEFT JOIN (SELECT "RunId", SUM("Amount") AS "Amt" FROM "MTC_CA_R_LINE" WHERE "TransCode" IN ('I03', 'I07', 'I08', 'I09', 'I90') AND "OrderEntry" IS NOT NULL
              GROUP BY "RunId") L ON L."RunId" = U."RunId"
 WHERE U."RunId" IS NOT NULL
@@
-- V02 R01 每张订单：期初在产品 + 本期投入 + 本级分摊 − 完工转出 − 关单差异 − 期末在产品 = 0（R01“勾稽差额”）
SELECT 'V02' AS "编号", 'R01 订单勾稽差额 = 0（不通过数 = 订单数）' AS "说明", COUNT(DISTINCT U."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(M."Net", 0) + O."AllocLab" + O."AllocMfg" - O."CostAmt" - O."CloseDifAmt" - O."WipAmt") > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
  JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
  LEFT JOIN (SELECT "RunId", "OrderType", "OrderEntry",
                    SUM("OpenIssMat" + "OpenIssLab" + "OpenIssMfg" + "OpenIssSub" - "OpenCarMat" - "OpenCarLab" - "OpenCarMfg" - "OpenCarSub"
                        + "IssMat" + "IssLab" + "IssMfg" + "IssSub") AS "Net"
               FROM "MTC_CA_R_ORDER_MAT" GROUP BY "RunId", "OrderType", "OrderEntry") M
         ON M."RunId" = O."RunId" AND M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
@@
-- V03 R03 每个物料：期初 + 本期收发各类别 + 尾差结转 = 期末（按收发类别分列时的口径）
SELECT 'V03' AS "编号", 'R03 期初 + 收发 = 期末（不通过数 = 物料数）' AS "说明", COUNT(DISTINCT U."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(R."OpenMat" + R."OpenLab" + R."OpenMfg" + R."OpenSub" + IFNULL(L."Amt", 0) + R."TailAmt" - R."EndAmount") > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
  JOIN "MTC_CA_R_ITEM" R ON R."RunId" = U."RunId"
  LEFT JOIN (SELECT "RunId", "ItemCode", SUM("Amount") AS "Amt" FROM "MTC_CA_R_LINE" GROUP BY "RunId", "ItemCode") L
         ON L."RunId" = R."RunId" AND L."ItemCode" = R."ItemCode"
@@
-- V04 R06 已分配合计 = R01 本级分摊（人工 + 制造）
SELECT 'V04' AS "编号", 'R06 已分配 = R01 本级分摊' AS "说明", COUNT(*) AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(A."Amt", 0) - IFNULL(O."Amt", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
  LEFT JOIN (SELECT "RunId", SUM("Amount") AS "Amt" FROM "MTC_CA_R_ALLOC" GROUP BY "RunId") A ON A."RunId" = U."RunId"
  LEFT JOIN (SELECT "RunId", SUM("AllocLab" + "AllocMfg") AS "Amt" FROM "MTC_CA_R_ORDER" GROUP BY "RunId") O ON O."RunId" = U."RunId"
 WHERE U."RunId" IS NOT NULL
@@
-- V05 R01 期末在产品：订单 WipAmt = 订单 × 材料 Wip 四项合计（R01 两种显示方式一致）
SELECT 'V05' AS "编号", 'R01 订单在产品 = 订单 × 材料在产品合计（不通过数 = 订单数）' AS "说明", COUNT(DISTINCT U."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(O."WipAmt" - IFNULL(M."Wip", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
  JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
  LEFT JOIN (SELECT "RunId", "OrderType", "OrderEntry", SUM("WipMat" + "WipLab" + "WipMfg" + "WipSub") AS "Wip"
               FROM "MTC_CA_R_ORDER_MAT" GROUP BY "RunId", "OrderType", "OrderEntry") M
         ON M."RunId" = O."RunId" AND M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
@@
-- V06 R10 来源明细合计 = 分录合计（按凭证代码，借 − 贷）
SELECT 'V06' AS "编号", 'R10 来源明细 = 分录（不通过数 = 凭证代码数）' AS "说明", COUNT(DISTINCT U."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(J."Amt", 0) - IFNULL(S."Amt", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
  JOIN (SELECT "RunId", "TransCode" FROM "MTC_CA_R_JDT" UNION SELECT "RunId", "TransCode" FROM "MTC_CA_R_JDT_SRC") K ON K."RunId" = U."RunId"
  LEFT JOIN (SELECT "RunId", "TransCode", SUM("Debit" - "Credit") AS "Amt" FROM "MTC_CA_R_JDT" GROUP BY "RunId", "TransCode") J
         ON J."RunId" = K."RunId" AND J."TransCode" = K."TransCode"
  LEFT JOIN (SELECT "RunId", "TransCode", SUM("Amount") AS "Amt" FROM "MTC_CA_R_JDT_SRC" GROUP BY "RunId", "TransCode") S
         ON S."RunId" = K."RunId" AND S."TransCode" = K."TransCode"
@@
-- V07 R17 STYPE 3：截至期末暂估变动合计 = 逐行未清金额（按供应商）
SELECT 'V07' AS "编号", 'R17 期初 + 变动 = 期末未清（不通过数 = 供应商数）' AS "说明", COUNT(DISTINCT U."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(M."Amt", 0) - IFNULL(A."Amt", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
  JOIN (SELECT "RunId", IFNULL("CardCode", '') AS "CardCode" FROM "MTC_CA_S_AP_MOVE"
        UNION SELECT "RunId", IFNULL("CardCode", '') FROM "MTC_CA_R_AP_ACCR") K ON K."RunId" = U."RunId"
  LEFT JOIN (SELECT M."RunId", IFNULL(M."CardCode", '') AS "CardCode", SUM(M."AccrAmt") AS "Amt"
               FROM "MTC_CA_S_AP_MOVE" M JOIN "MTC_CA_RUN" R ON R."RunId" = M."RunId" JOIN "OFPR" P ON P."Code" = R."FcCode"
              WHERE M."DocDate" <= TO_DATE(P."T_RefDate") GROUP BY M."RunId", IFNULL(M."CardCode", '')) M
         ON M."RunId" = K."RunId" AND M."CardCode" = K."CardCode"
  LEFT JOIN (SELECT "RunId", IFNULL("CardCode", '') AS "CardCode", SUM("OpenAmt") AS "Amt" FROM "MTC_CA_R_AP_ACCR" GROUP BY "RunId", IFNULL("CardCode", '')) A
         ON A."RunId" = K."RunId" AND A."CardCode" = K."CardCode"
@@
-- V09 R08 / R18 STYPE 3：期初发出商品 + 本期发货 − 独立退货 − 本期消耗 = 期末发出商品（全部交货 / 退货行合计）
SELECT 'V09' AS "编号", 'R08/R18 发出商品期初 + 变动 = 期末' AS "说明", COUNT(*) AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(B."Amt", 0) + IFNULL(L."Iss", 0) - IFNULL(L."Ret0", 0) - IFNULL(M."Amt", 0) - IFNULL(E."Amt", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
  LEFT JOIN (SELECT "RunId", SUM("CostAmt") AS "Amt" FROM "MTC_CA_R_GOODS_OUT_BEG" GROUP BY "RunId") B ON B."RunId" = U."RunId"
  LEFT JOIN (SELECT "RunId", SUM("CostAmt") AS "Amt" FROM "MTC_CA_R_GOODS_OUT" GROUP BY "RunId") E ON E."RunId" = U."RunId"
  LEFT JOIN (SELECT "RunId", SUM("Amount") AS "Amt" FROM "MTC_CA_R_GOODS_MOVE" GROUP BY "RunId") M ON M."RunId" = U."RunId"
  LEFT JOIN (SELECT D."RunId", SUM(CASE WHEN D."ObjType" = '15' THEN -L."Amount" ELSE 0 END) AS "Iss",
                    SUM(CASE WHEN D."ObjType" = '16' AND IFNULL(D."BaseType", '') <> '15' THEN L."Amount" ELSE 0 END) AS "Ret0"
               FROM "MTC_CA_S_LINE" D JOIN "MTC_CA_R_LINE" L ON L."RunId" = D."RunId" AND L."LineId" = D."LineId"
              WHERE D."ObjType" IN ('15', '16') GROUP BY D."RunId") L ON L."RunId" = U."RunId"
 WHERE U."RunId" IS NOT NULL
@@
-- V10 R18 STYPE 4：期末未开票成本 = AR03 + AR04 计提（贷发出商品科目）
SELECT 'V10' AS "编号", 'R18 未开票成本 = AR03 + AR04 计提' AS "说明", COUNT(*) AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(G."Amt", 0) - IFNULL(J."Amt", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
  LEFT JOIN (SELECT "RunId", SUM("CostAmt") AS "Amt" FROM "MTC_CA_R_GOODS_OUT" GROUP BY "RunId") G ON G."RunId" = U."RunId"
  LEFT JOIN (SELECT J."RunId", SUM(J."Credit" - J."Debit") AS "Amt" FROM "MTC_CA_R_JDT" J JOIN "MTC_CA_RUN" R ON R."RunId" = J."RunId"
              WHERE J."TransCode" IN ('AR03', 'AR04') AND J."AcctCode" = "MTC_CA_F_ACCT"('GOODS_ISSUED', R."FcCode") GROUP BY J."RunId") J ON J."RunId" = U."RunId"
 WHERE U."RunId" IS NOT NULL
@@
-- V13 R19 / R20 每个订单 × 材料：期初在产品 + 本期领料 − 完工转出 − 关单差异 − 期末在产品 = 0（本级分摊随完工全部转出，不在这里）
SELECT 'V13' AS "编号", 'R19 / R20 订单 × 材料：期初 + 领料 − 完工转出 − 关单差异 = 期末在产品（不通过数 = 行数）' AS "说明", COUNT(DISTINCT U."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(M."OpenIssMat" + M."OpenIssLab" + M."OpenIssMfg" + M."OpenIssSub" - M."OpenCarMat" - M."OpenCarLab" - M."OpenCarMfg" - M."OpenCarSub"
                         + M."IssMat" + M."IssLab" + M."IssMfg" + M."IssSub" - M."CarMat" - M."CarLab" - M."CarMfg" - M."CarSub"
                         - M."ClsMat" - M."ClsLab" - M."ClsMfg" - M."ClsSub" - M."WipMat" - M."WipLab" - M."WipMfg" - M."WipSub") > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
  JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = U."RunId"
@@
-- V14 R19 本期期初在产品 = 上期期末在产品（订单 × 材料，四项合计）；上期也有新框架运行的账期才核对（起始账期的期初来自期初承接，不核对；承接账期历史运行 → 起始账期见 22_legacy_verify.sql H14）
WITH P AS (SELECT U."FcCode", U."RunId", V."RunId" AS "PrevRunId"
             FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H') U
             JOIN (SELECT XV.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XV JOIN "MTC_CA_RUN" XRV ON XRV."RunId" = XV."RunId" AND XRV."RunType" <> 'H') V ON V."FcCode" = U."PrevFc"
            WHERE U."RunId" IS NOT NULL AND V."RunId" IS NOT NULL),
     C AS (SELECT P."FcCode", M."OrderType", M."OrderEntry", M."ItemCode",
                  M."OpenIssMat" + M."OpenIssLab" + M."OpenIssMfg" + M."OpenIssSub" - M."OpenCarMat" - M."OpenCarLab" - M."OpenCarMfg" - M."OpenCarSub" AS "B"
             FROM P JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = P."RunId"),
     L AS (SELECT P."FcCode", M."OrderType", M."OrderEntry", M."ItemCode", M."WipMat" + M."WipLab" + M."WipMfg" + M."WipSub" AS "W"
             FROM P JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = P."PrevRunId")
SELECT 'V14' AS "编号", 'R19 本期期初在产品 = 上期期末在产品（不通过数 = 订单 × 材料行数）' AS "说明",
       (SELECT COUNT(*) FROM P) AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(C."B", 0) - IFNULL(L."W", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM C FULL JOIN L ON L."FcCode" = C."FcCode" AND L."OrderType" = C."OrderType" AND L."OrderEntry" = C."OrderEntry" AND L."ItemCode" = C."ItemCode"
@@
-- V08 / V11 / V12 与财务对账业务端（MTC_CA_F_RECON 要按运行号逐次调用，只核对最近一个已计算账期）：
--   V08 R17 未清合计 = 应付暂估业务端（FI5005_V2 截至期末合计也应等于它，那张直接读 B1，在 B1 里另跑核对）
--   V11 R03 期末金额合计 = 存货业务端
--   V12 R01 期末在产品合计 = 生产在产品 + 委外材料 + 委外加工费业务端
DO BEGIN
    DECLARE rid BIGINT; DECLARE fc NVARCHAR(10);
    DECLARE ap DECIMAL(19,2); DECLARE apB DECIMAL(19,2); DECLARE st DECIMAL(19,2); DECLARE stB DECIMAL(19,2); DECLARE wp DECIMAL(19,2); DECLARE wpB DECIMAL(19,2);
    SELECT MAX("RunId"), MAX("FcCode") INTO rid, fc FROM "MTC_CA_F_RPT_RUN"('', '');
    r = SELECT * FROM "MTC_CA_F_RECON"(:rid);
    SELECT IFNULL(SUM("OpenAmt"), 0) INTO ap FROM "MTC_CA_R_AP_ACCR" WHERE "RunId" = :rid;
    SELECT IFNULL(SUM("EndAmount"), 0) INTO st FROM "MTC_CA_R_ITEM" WHERE "RunId" = :rid;
    SELECT IFNULL(SUM("WipAmt"), 0) INTO wp FROM "MTC_CA_R_ORDER" WHERE "RunId" = :rid;
    SELECT IFNULL(SUM(CASE WHEN "Area" = 'AP' THEN "BizAmt" END), 0), IFNULL(SUM(CASE WHEN "Area" = 'STOCK' THEN "BizAmt" END), 0),
           IFNULL(SUM(CASE WHEN "Area" IN ('WIP_PROD', 'WW_MAT', 'WW_FEE') THEN "BizAmt" END), 0)
      INTO apB, stB, wpB FROM :r;
    SELECT 'V08' AS "编号", 'R17 未清合计 = R09 应付暂估业务端' AS "说明", :fc AS "账期", CASE WHEN ABS(:ap - :apB) > 0.05 THEN 1 ELSE 0 END AS "不通过数" FROM DUMMY
    UNION ALL
    SELECT 'V11', 'R03 期末 = R09 存货业务端', :fc, CASE WHEN ABS(:st - :stB) > 0.05 THEN 1 ELSE 0 END FROM DUMMY
    UNION ALL
    SELECT 'V12', 'R01 期末在产品 = R09 在产品业务端', :fc, CASE WHEN ABS(:wp - :wpB) > 0.05 THEN 1 ELSE 0 END FROM DUMMY;
END

-- V15 R23 收入（已开票 + 未归属，含样品）= 应收发票 − 应收贷项（本币不含税，取消单反号），按账期。全部月份
SELECT 'V15' AS "编号", 'R23 已开票 + 未归属收入 = 发票 − 贷项' AS "说明", COUNT(*) AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(T."Rev", 0) - IFNULL(B."Rev", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT "FcCode", SUM("Rev") AS "Rev" FROM "MTC_CA_F_SALE_TREND"('1900-01-01', CURRENT_DATE, '0') WHERE "Kind" <> 'ACC' GROUP BY "FcCode") T
  FULL JOIN (SELECT F."Code" AS "FcCode", SUM(X."Rev") AS "Rev"
               FROM (SELECT H."DocDate", CASE WHEN H."CANCELED" = 'C' THEN -1 ELSE 1 END * D."LineTotal" AS "Rev" FROM "OINV" H JOIN "INV1" D ON D."DocEntry" = H."DocEntry"
                     UNION ALL
                     SELECT H."DocDate", CASE WHEN H."CANCELED" = 'C' THEN 1 ELSE -1 END * D."LineTotal" FROM "ORIN" H JOIN "RIN1" D ON D."DocEntry" = H."DocEntry") X
               JOIN "OFPR" F ON X."DocDate" BETWEEN F."F_RefDate" AND F."T_RefDate"
              WHERE X."DocDate" <= CURRENT_DATE
              GROUP BY F."Code") B ON B."FcCode" = T."FcCode";
-- V16 R23 暂估数量合计（全部月份，含样品）= 截至今天未开票数量（F_GOODS_OPEN，发出商品同一口径）
SELECT 'V16' AS "编号", 'R23 暂估数量合计 = 至今未开票数量' AS "说明", 1 AS "账期数",
       CASE WHEN ABS(IFNULL(T."Qty", 0) - IFNULL(O."Qty", 0)) > 0.001 THEN 1 ELSE 0 END AS "不通过数"
  FROM (SELECT SUM("Qty") AS "Qty" FROM "MTC_CA_F_SALE_TREND"('1900-01-01', CURRENT_DATE, '0') WHERE "Kind" = 'ACC') T,
       (SELECT SUM("OpenQty") AS "Qty" FROM "MTC_CA_F_GOODS_OPEN"(CURRENT_DATE)) O;
-- V17 R23 月结固定：截至各已生成凭单账期期末的暂估成本累计 = R_GOODS_OUT 期末未开票成本（= AR03 / AR04 计提 + 样品），含样品，容忍 5 元（逐行取整的误差）
SELECT 'V17' AS "编号", 'R23 月结固定暂估累计 = 发出商品期末（容忍 5 元）' AS "说明", COUNT(*) AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(T."CumCost", 0) - IFNULL(G."Amt", 0)) > 5 THEN 1 ELSE 0 END) AS "不通过数"
  FROM (SELECT XU.* FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') XU JOIN "MTC_CA_RUN" XRU ON XRU."RunId" = XU."RunId" AND XRU."RunType" <> 'H'
         WHERE XU."PStatus" = 'POSTED') U
  LEFT JOIN (SELECT "FcCode", SUM(SUM("Cost")) OVER (ORDER BY "FcCode") AS "CumCost"
               FROM "MTC_CA_F_SALE_TREND"('1900-01-01', CURRENT_DATE, '1') WHERE "Kind" = 'ACC' GROUP BY "FcCode") T ON T."FcCode" = U."FcCode"
  LEFT JOIN (SELECT "RunId", SUM("CostAmt") AS "Amt" FROM "MTC_CA_R_GOODS_OUT" GROUP BY "RunId") G ON G."RunId" = U."RunId";
