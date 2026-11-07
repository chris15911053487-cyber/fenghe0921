-- =====================================================================
-- 历史回填核对（22_legacy_load.sql 的配套，用户 2026-11-02）：只读，每段返回一行 “编号 · 说明 · 账期数 · 不通过数”。
-- 范围：成本报表取到的全部历史运行（MTC_CA_F_RPT_RUN 选中的 RunType H 运行）。只把不为 0 的编号反馈即可（不要贴明细）。
-- 用法：python3 新框架/tools/hana_exec.py -f 新框架/sql/22_legacy_verify.sql
-- L01–L06 核对回填与旧表一致；L07、L08 是旧框架自身不一致的提示（照原样带过来，不修改旧数据，记作“已知差异”）；
-- H01… 是 21_reports_verify.sql 的 V01 / V02 / V03 / V05 / V06 / V13 / V14 对历史运行再跑一遍。差额容忍 0.05。离线写的，还没执行过。
-- =====================================================================
-- L01 物料期末金额 = 旧 0301 QM_Amount（按物料）
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'L01' AS "编号", '物料期末金额 = 旧 0301 期末（不通过数 = 物料数）' AS "说明", COUNT(DISTINCT H."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(R."EndAmount", 0) - IFNULL(O."A", 0)) > 0.05 OR ABS(IFNULL(R."EndQty", 0) - IFNULL(O."Q", 0)) > 0.000001 THEN 1 ELSE 0 END) AS "不通过数"
  FROM H
  JOIN (SELECT "FcCode", "ItemCode", SUM(IFNULL("QM_Qty", 0)) AS "Q", SUM(IFNULL("QM_Amount", 0)) AS "A" FROM "MTC_COST_0301_INVNT"
         WHERE "CostCode" = '20' GROUP BY "FcCode", "ItemCode") O ON O."FcCode" = H."FcCode"
  LEFT JOIN "MTC_CA_R_ITEM" R ON R."RunId" = H."RunId" AND R."ItemCode" = O."ItemCode"
 WHERE O."Q" <> 0 OR O."A" <> 0 OR R."ItemCode" IS NOT NULL
@@
-- L02 订单完工成本 = 旧 0321_OWOR_SUM.Amount
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'L02' AS "编号", '订单完工成本 = 旧 0321_OWOR_SUM（不通过数 = 订单数）' AS "说明", COUNT(DISTINCT H."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(R."CostAmt", 0) - IFNULL(O."A", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM H
  JOIN (SELECT "FcCode", IFNULL("DocType", '202') AS "OT", TO_INTEGER("WorEntry") AS "OE", SUM(IFNULL("Amount", 0)) AS "A"
          FROM "MTC_COST_0321_OWOR_SUM" WHERE TO_NVARCHAR("WorEntry") LIKE_REGEXPR '^[0-9]+$'
         GROUP BY "FcCode", IFNULL("DocType", '202'), TO_INTEGER("WorEntry") HAVING SUM(IFNULL("Amount", 0)) <> 0) O ON O."FcCode" = H."FcCode"
  LEFT JOIN "MTC_CA_R_ORDER" R ON R."RunId" = H."RunId" AND R."OrderType" = O."OT" AND R."OrderEntry" = O."OE"
@@
-- L03 订单期末在产品（倒挤）= 旧 0322_OWOR_ZCP “在产品新”。
--     不通过多数是旧框架 5ClosedAmt / CloseDifAmt 的运行顺序问题或 ZCP1 与 ZCP 不一致（BOOT-01），列为已知差异
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H'),
     N AS (SELECT H."FcCode", O."OrderType" AS "OT", O."OrderEntry" AS "OE", O."WipAmt" AS "W" FROM H JOIN "MTC_CA_R_ORDER" O ON O."RunId" = H."RunId"),
     Z AS (SELECT "期间" AS "FcCode", IFNULL("DocType", '202') AS "OT", "WorEntry" AS "OE", SUM(IFNULL("在产品新", 0)) AS "W"
             FROM "MTC_COST_0322_OWOR_ZCP" WHERE "期间" IN (SELECT "FcCode" FROM H) GROUP BY "期间", IFNULL("DocType", '202'), "WorEntry")
SELECT 'L03' AS "编号", '订单在产品 = 旧 ZCP 在产品新（不通过数 = 订单数）' AS "说明", COUNT(DISTINCT IFNULL(N."FcCode", Z."FcCode")) AS "账期数",
       IFNULL(SUM(CASE WHEN ABS(IFNULL(N."W", 0) - IFNULL(Z."W", 0)) > 0.05 THEN 1 ELSE 0 END), 0) AS "不通过数"
  FROM N FULL JOIN Z ON Z."FcCode" = N."FcCode" AND Z."OT" = N."OT" AND Z."OE" = N."OE"
@@
-- L04 四项合计 = 总额（单据行、物料期末、订单完工成本三层）
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'L04' AS "编号", '四项合计 = 总额（不通过数 = 行 + 物料 + 订单数）' AS "说明", (SELECT COUNT(*) FROM H) AS "账期数",
       (SELECT COUNT(*) FROM H JOIN "MTC_CA_R_LINE" L ON L."RunId" = H."RunId" WHERE ABS(L."MatAmt" + L."MfgAmt" + L."LabAmt" + L."SubAmt" - L."Amount") > 0.005)
     + (SELECT COUNT(*) FROM H JOIN "MTC_CA_R_ITEM" I ON I."RunId" = H."RunId" WHERE ABS(I."EndMat" + I."EndMfg" + I."EndLab" + I."EndSub" - I."EndAmount") > 0.005)
     + (SELECT COUNT(*) FROM H JOIN "MTC_CA_R_ORDER" O ON O."RunId" = H."RunId" WHERE ABS(O."CostMat" + O."CostMfg" + O."CostLab" + O."CostSub" - O."CostAmt") > 0.005)
       AS "不通过数"
  FROM DUMMY
@@
-- L05 本期期初 = 上期期末（物料四项，历史运行之间）
WITH H AS (SELECT U."FcCode", U."RunId", U."PrevFc" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H'),
     P AS (SELECT A."FcCode", A."RunId", B."RunId" AS "PrevRunId" FROM H A JOIN H B ON B."FcCode" = A."PrevFc"),
     C AS (SELECT P."FcCode", I."ItemCode", I."OpenQty" AS "Q", I."OpenMat" AS "M", I."OpenMfg" AS "F", I."OpenLab" AS "L", I."OpenSub" AS "S"
             FROM P JOIN "MTC_CA_R_ITEM" I ON I."RunId" = P."RunId"),
     E AS (SELECT P."FcCode", I."ItemCode", I."EndQty" AS "Q", I."EndMat" AS "M", I."EndMfg" AS "F", I."EndLab" AS "L", I."EndSub" AS "S"
             FROM P JOIN "MTC_CA_R_ITEM" I ON I."RunId" = P."PrevRunId")
SELECT 'L05' AS "编号", '物料本期期初 = 上期期末（不通过数 = 物料数）' AS "说明", (SELECT COUNT(*) FROM P) AS "账期数",
       IFNULL(SUM(CASE WHEN ABS(IFNULL(C."M", 0) - IFNULL(E."M", 0)) > 0.005 OR ABS(IFNULL(C."F", 0) - IFNULL(E."F", 0)) > 0.005
                         OR ABS(IFNULL(C."L", 0) - IFNULL(E."L", 0)) > 0.005 OR ABS(IFNULL(C."S", 0) - IFNULL(E."S", 0)) > 0.005
                         OR ABS(IFNULL(C."Q", 0) - IFNULL(E."Q", 0)) > 0.000001 THEN 1 ELSE 0 END), 0) AS "不通过数"
  FROM C FULL JOIN E ON E."FcCode" = C."FcCode" AND E."ItemCode" = C."ItemCode"
@@
-- L06 承接账期的历史运行期末 = 期初承接 MTC_CA_BOOT_ITEM（与新框架起始账期期初衔接）
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId"
            WHERE R."RunType" = 'H' AND U."FcCode" = "MTC_CA_F_PARAM"('BOOTSTRAP_FC', U."FcCode")),
     E AS (SELECT H."FcCode", I."ItemCode", I."EndQty" AS "Q", I."EndMat" AS "M", I."EndMfg" AS "F", I."EndLab" AS "L", I."EndSub" AS "S"
             FROM H JOIN "MTC_CA_R_ITEM" I ON I."RunId" = H."RunId" WHERE I."EndQty" <> 0 OR I."EndAmount" <> 0),
     B AS (SELECT "FcCode", "ItemCode", "Qty" AS "Q", "MatAmt" AS "M", "MfgAmt" AS "F", "LabAmt" AS "L", "SubAmt" AS "S"
             FROM "MTC_CA_BOOT_ITEM" WHERE "FcCode" IN (SELECT "FcCode" FROM H))
SELECT 'L06' AS "编号", '承接账期历史运行期末 = 期初承接（不通过数 = 物料数）' AS "说明", (SELECT COUNT(*) FROM H) AS "账期数",
       IFNULL(SUM(CASE WHEN ABS(IFNULL(E."M", 0) - IFNULL(B."M", 0)) > 0.005 OR ABS(IFNULL(E."F", 0) - IFNULL(B."F", 0)) > 0.005
                         OR ABS(IFNULL(E."L", 0) - IFNULL(B."L", 0)) > 0.005 OR ABS(IFNULL(E."S", 0) - IFNULL(B."S", 0)) > 0.005
                         OR ABS(IFNULL(E."Q", 0) - IFNULL(B."Q", 0)) > 0.000001 THEN 1 ELSE 0 END), 0) AS "不通过数"
  FROM E FULL JOIN B ON B."FcCode" = E."FcCode" AND B."ItemCode" = E."ItemCode"
@@
-- L07（提示）旧框架期末 ≠ 期初 + 本期收发的物料：差额记在 R_ITEM.TailAmt（R03“尾差结转”列），多数是旧 0401 手工覆盖期末或上期期末与本期期初不一致
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'L07' AS "编号", '（提示）旧框架期末 ≠ 期初 + 收发，差额记尾差（物料数）' AS "说明", COUNT(DISTINCT H."FcCode") AS "账期数",
       COUNT(I."ItemCode") AS "不通过数"
  FROM H LEFT JOIN "MTC_CA_R_ITEM" I ON I."RunId" = H."RunId" AND ABS(I."TailAmt") >= 0.005
@@
-- L08（提示）订单完工材料没有领料可分（补了 '#LEGACY' 行，在产品为负）
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'L08' AS "编号", '（提示）完工材料没有领料记录的订单（订单数）' AS "说明", COUNT(DISTINCT H."FcCode") AS "账期数",
       COUNT(M."OrderEntry") AS "不通过数"
  FROM H LEFT JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = H."RunId" AND M."ItemCode" = '#LEGACY'
@@
-- H01（= V01）完工成本合计 = 生产入库（I03 / I07 / I08 / I09 / I90 带订单的入库金额）。旧框架有“只有委外加工费、本期没有入库”的订单时会不等
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'H01' AS "编号", '历史期 完工成本 = 生产入库（V01）' AS "说明", COUNT(*) AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(O."Amt", 0) - IFNULL(L."Amt", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM H
  LEFT JOIN (SELECT "RunId", SUM("CostAmt") AS "Amt" FROM "MTC_CA_R_ORDER" GROUP BY "RunId") O ON O."RunId" = H."RunId"
  LEFT JOIN (SELECT "RunId", SUM("Amount") AS "Amt" FROM "MTC_CA_R_LINE" WHERE "TransCode" IN ('I03', 'I07', 'I08', 'I09', 'I90') AND "OrderEntry" IS NOT NULL
              GROUP BY "RunId") L ON L."RunId" = H."RunId"
@@
-- H02（= V02）订单：期初在产品 + 本期投入 + 本级分摊 − 完工转出 − 关单差异 − 期末在产品 = 0
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'H02' AS "编号", '历史期 订单勾稽差额 = 0（V02，不通过数 = 订单数）' AS "说明", COUNT(DISTINCT H."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(M."Net", 0) + O."AllocLab" + O."AllocMfg" - O."CostAmt" - O."CloseDifAmt" - O."WipAmt") > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM H
  JOIN "MTC_CA_R_ORDER" O ON O."RunId" = H."RunId"
  LEFT JOIN (SELECT "RunId", "OrderType", "OrderEntry",
                    SUM("OpenIssMat" + "OpenIssLab" + "OpenIssMfg" + "OpenIssSub" - "OpenCarMat" - "OpenCarLab" - "OpenCarMfg" - "OpenCarSub"
                        + "IssMat" + "IssLab" + "IssMfg" + "IssSub") AS "Net"
               FROM "MTC_CA_R_ORDER_MAT" GROUP BY "RunId", "OrderType", "OrderEntry") M
         ON M."RunId" = O."RunId" AND M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
@@
-- H03（= V03）物料：期初 + 本期收发 + 尾差结转 = 期末
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'H03' AS "编号", '历史期 期初 + 收发 = 期末（V03，不通过数 = 物料数）' AS "说明", COUNT(DISTINCT H."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(R."OpenMat" + R."OpenLab" + R."OpenMfg" + R."OpenSub" + IFNULL(L."Amt", 0) + R."TailAmt" - R."EndAmount") > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM H
  JOIN "MTC_CA_R_ITEM" R ON R."RunId" = H."RunId"
  LEFT JOIN (SELECT "RunId", "ItemCode", SUM("Amount") AS "Amt" FROM "MTC_CA_R_LINE" GROUP BY "RunId", "ItemCode") L
         ON L."RunId" = R."RunId" AND L."ItemCode" = R."ItemCode"
@@
-- H05（= V05）订单在产品 = 订单 × 材料在产品合计
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'H05' AS "编号", '历史期 订单在产品 = 订单 × 材料合计（V05，不通过数 = 订单数）' AS "说明", COUNT(DISTINCT H."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(O."WipAmt" - IFNULL(M."Wip", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM H
  JOIN "MTC_CA_R_ORDER" O ON O."RunId" = H."RunId"
  LEFT JOIN (SELECT "RunId", "OrderType", "OrderEntry", SUM("WipMat" + "WipLab" + "WipMfg" + "WipSub") AS "Wip"
               FROM "MTC_CA_R_ORDER_MAT" GROUP BY "RunId", "OrderType", "OrderEntry") M
         ON M."RunId" = O."RunId" AND M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
@@
-- H06（= V06）凭证来源明细合计 = 分录合计（按凭证代码）
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'H06' AS "编号", '历史期 凭证来源 = 分录（V06，不通过数 = 凭证代码数）' AS "说明", COUNT(DISTINCT H."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(IFNULL(J."Amt", 0) - IFNULL(S."Amt", 0)) > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM H
  JOIN (SELECT "RunId", "TransCode" FROM "MTC_CA_R_JDT" UNION SELECT "RunId", "TransCode" FROM "MTC_CA_R_JDT_SRC") K ON K."RunId" = H."RunId"
  LEFT JOIN (SELECT "RunId", "TransCode", SUM("Debit" - "Credit") AS "Amt" FROM "MTC_CA_R_JDT" GROUP BY "RunId", "TransCode") J
         ON J."RunId" = K."RunId" AND J."TransCode" = K."TransCode"
  LEFT JOIN (SELECT "RunId", "TransCode", SUM("Amount") AS "Amt" FROM "MTC_CA_R_JDT_SRC" GROUP BY "RunId", "TransCode") S
         ON S."RunId" = K."RunId" AND S."TransCode" = K."TransCode"
@@
-- H13（= V13）订单 × 材料：期初 + 领料 − 完工转出 − 关单差异 = 期末在产品
WITH H AS (SELECT U."FcCode", U."RunId" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') U JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId" WHERE R."RunType" = 'H')
SELECT 'H13' AS "编号", '历史期 订单 × 材料勾稽（V13，不通过数 = 行数）' AS "说明", COUNT(DISTINCT H."FcCode") AS "账期数",
       SUM(CASE WHEN ABS(M."OpenIssMat" + M."OpenIssLab" + M."OpenIssMfg" + M."OpenIssSub" - M."OpenCarMat" - M."OpenCarLab" - M."OpenCarMfg" - M."OpenCarSub"
                         + M."IssMat" + M."IssLab" + M."IssMfg" + M."IssSub" - M."CarMat" - M."CarLab" - M."CarMfg" - M."CarSub"
                         - M."ClsMat" - M."ClsLab" - M."ClsMfg" - M."ClsSub" - M."WipMat" - M."WipLab" - M."WipMfg" - M."WipSub") > 0.05 THEN 1 ELSE 0 END) AS "不通过数"
  FROM H
  JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = H."RunId"
@@
-- H14（= V14）订单 × 材料：本期期初在产品 = 上期期末在产品（含承接账期历史运行 → 新框架起始账期）
WITH U AS (SELECT X."FcCode", X."RunId", X."PrevFc" FROM "MTC_CA_F_RPT_RUN"('0000-00', '9999-99') X WHERE X."RunId" IS NOT NULL),
     P AS (SELECT A."FcCode", A."RunId", B."RunId" AS "PrevRunId"
             FROM U A JOIN U B ON B."FcCode" = A."PrevFc" JOIN "MTC_CA_RUN" R ON R."RunId" = B."RunId" WHERE R."RunType" = 'H'),
     C AS (SELECT P."FcCode", M."OrderType", M."OrderEntry", M."ItemCode",
                  M."OpenIssMat" + M."OpenIssLab" + M."OpenIssMfg" + M."OpenIssSub" - M."OpenCarMat" - M."OpenCarLab" - M."OpenCarMfg" - M."OpenCarSub" AS "B"
             FROM P JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = P."RunId"),
     L AS (SELECT P."FcCode", M."OrderType", M."OrderEntry", M."ItemCode", M."WipMat" + M."WipLab" + M."WipMfg" + M."WipSub" AS "W"
             FROM P JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = P."PrevRunId")
SELECT 'H14' AS "编号", '历史期 本期期初在产品 = 上期期末（V14，不通过数 = 行数）' AS "说明",
       (SELECT COUNT(*) FROM P) AS "账期数",
       IFNULL(SUM(CASE WHEN ABS(IFNULL(C."B", 0) - IFNULL(L."W", 0)) > 0.05 THEN 1 ELSE 0 END), 0) AS "不通过数"
  FROM C FULL JOIN L ON L."FcCode" = C."FcCode" AND L."OrderType" = C."OrderType" AND L."OrderEntry" = C."OrderEntry" AND L."ItemCode" = C."ItemCode"
