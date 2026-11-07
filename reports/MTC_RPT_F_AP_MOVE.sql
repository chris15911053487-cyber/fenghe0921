/* =====================================================================
 * 新报表（未部署，用户 2026-10-30）：MTC_RPT_F_AP_MOVE 截至某日的应付暂估变动（表函数，只读）
 * 给 MTC_RPT_FI5005_V2（至今未清的采购收退货明细）、MTC_RPT_FI5009_V2（采购收货明细大表）共用，先部署本函数。
 * 口径与 PUR1–PUR5 凭证、新框架 MTC_CA_P20_AP（S_AP_MOVE）、取数 SQL tools/console/srcsql/ap_accr.sql 相同，改口径时几处一起改：
 *   - 暂估行：截至 edate 的采购收货行（不基于退货）、不基于收货的采购退货行（方向为负）；只暂估库存物料（OITM.InvntItem='Y'）和委外加工费 X0510001
 *   - 暂估单价：U_InitPrice ≠ 0（期初和上线后系统 Price 有误时填的指定单价）→ U_InitPrice；U_IsPrice='Y'（价格已确认）→ Price；否则 LineTotal ÷ 数量
 *     整行暂估 = 同样顺序取 数量 × 单价 或 LineTotal，保留 2 位（材料、委外加工费相同，用户 2026-10-30）
 *   - 冲减：基于暂估行的应付发票 / 贷项（INV）、退货 / 换货（RET），每笔 = 数量 × 暂估单价（保留 2 位）；
 *     累计数量达到暂估数量的那一笔 = 整行暂估 − 之前已冲回（清余数）；退货按收货行的暂估单价
 *   - 截至 edate：只计过账日期 ≤ edate 的单据；取消单（CANCELED='C'）过账日期 ≤ edate 才算取消，取原单金额的相反数
 *   - 不看 LineStatus / OpenQty 等当前状态：手工关闭的收货行不释放暂估（用户 2026-10-30），重查历史日期结果不变
 * 返回：一行 = 一条暂估行的一笔变动。Qty、AccrAmt 为正 = 增加暂估（AccrAmt 即对 220202 贷方余额的影响）；
 *       ACCR 暂估本身 / 暂估行被取消，INV 开票，RET 退货；DocAmt = 发票 / 贷项行金额（贷项为负，取消单取反）。
 * 用法：SELECT * FROM "MTC_RPT_F_AP_MOVE"('2026-09-30');
 * ===================================================================== */
CREATE FUNCTION "MTC_RPT_F_AP_MOVE" (IN edate DATE)
RETURNS TABLE ("BaseObj" NVARCHAR(2), "BaseEntry" INTEGER, "BaseLine" INTEGER, "BaseDocNum" INTEGER, "BaseDate" DATE,
               "BaseSign" INTEGER, "BaseQty" DECIMAL(19,6), "CardCode" NVARCHAR(50), "ItemCode" NVARCHAR(50),
               "AccrType" NVARCHAR(10), "PriceRule" NVARCHAR(10), "UnitPrice" DECIMAL(19,6), "FullAmt" DECIMAL(19,2),
               "MoveType" NVARCHAR(10), "IsCancel" NVARCHAR(1), "ObjType" NVARCHAR(2), "DocEntry" INTEGER, "LineNum" INTEGER,
               "DocDate" DATE, "SortKey" INTEGER, "Qty" DECIMAL(19,6), "AccrAmt" DECIMAL(19,2), "DocAmt" DECIMAL(19,2), "AmtRule" NVARCHAR(10))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE feeItem NVARCHAR(50) := 'X0510001';

    -- ① 暂估行
    base = SELECT '20' AS "BaseObj", M."DocEntry" AS "BaseEntry", D."LineNum" AS "BaseLine", M."DocNum" AS "BaseDocNum",
                  TO_DATE(M."DocDate") AS "BaseDate", 1 AS "BaseSign", D."Quantity" AS "BaseQty", M."CardCode", D."ItemCode",
                  D."U_InitPrice", D."U_IsPrice", D."Price", D."LineTotal"
             FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :edate AND IFNULL(D."BaseType", -1) <> 21
           UNION ALL
           SELECT '21', M."DocEntry", D."LineNum", M."DocNum", TO_DATE(M."DocDate"), -1, D."Quantity", M."CardCode", D."ItemCode",
                  D."U_InitPrice", D."U_IsPrice", D."Price", D."LineTotal"
             FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :edate AND IFNULL(D."BaseType", -1) <> 20;
    bp = SELECT B."BaseObj", B."BaseEntry", B."BaseLine", B."BaseDocNum", B."BaseDate", B."BaseSign", B."BaseQty", B."CardCode", B."ItemCode",
                CASE WHEN B."ItemCode" = :feeItem THEN 'SUBFEE' ELSE 'MAT' END AS "AccrType",
                CASE WHEN IFNULL(B."U_InitPrice", 0) <> 0 THEN 'INIT' WHEN B."U_IsPrice" = 'Y' THEN 'CONF' ELSE 'LT' END AS "PriceRule",
                CASE WHEN IFNULL(B."U_InitPrice", 0) <> 0 THEN B."U_InitPrice" WHEN B."U_IsPrice" = 'Y' THEN B."Price"
                     ELSE B."LineTotal" / NULLIF(B."BaseQty", 0) END AS "UP",
                ROUND(CASE WHEN IFNULL(B."U_InitPrice", 0) <> 0 THEN B."BaseQty" * B."U_InitPrice"
                           WHEN B."U_IsPrice" = 'Y' THEN B."BaseQty" * B."Price" ELSE B."LineTotal" END, 2) AS "FullAmt"
           FROM :base B JOIN "OITM" I ON I."ItemCode" = B."ItemCode"
          WHERE I."InvntItem" = 'Y' OR B."ItemCode" = :feeItem;

    -- ② 取消单行 → 原单行
    cx = SELECT '20' AS "ObjType", M."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate", '20' AS "OrigObj", D."BaseEntry" AS "OrigEntry", D."BaseLine" AS "OrigLine"
           FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND D."BaseType" = 20 AND M."DocDate" <= :edate
         UNION ALL
         SELECT '21', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '21', D."BaseEntry", D."BaseLine"
           FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND D."BaseType" = 21 AND M."DocDate" <= :edate
         UNION ALL
         SELECT '18', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '18', D."BaseEntry", D."BaseLine"
           FROM "OPCH" M JOIN "PCH1" D ON D."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND D."BaseType" = 18 AND M."DocDate" <= :edate
         UNION ALL
         SELECT '19', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '19', D."BaseEntry", D."BaseLine"
           FROM "ORPC" M JOIN "RPC1" D ON D."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND D."BaseType" = 19 AND M."DocDate" <= :edate;

    -- ③ 冲减暂估的原单：发票 / 贷项（INV）、退货 / 换货（RET）。关联时同时比 BaseType，避免基于采购订单的同号单据被算进来
    cons = SELECT '18' AS "ObjType", M."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate",
                  TO_NVARCHAR(D."BaseType") AS "BaseObj", D."BaseEntry", D."BaseLine", D."Quantity" AS "Q", D."LineTotal" AS "DocAmt", 'INV' AS "MoveType"
             FROM "OPCH" M JOIN "PCH1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :edate AND D."BaseType" IN (20, 21)
           UNION ALL
           SELECT '19', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), TO_NVARCHAR(D."BaseType"), D."BaseEntry", D."BaseLine", D."Quantity", -D."LineTotal", 'INV'
             FROM "ORPC" M JOIN "RPC1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :edate AND D."BaseType" IN (20, 21)
           UNION ALL
           SELECT '21', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '20', D."BaseEntry", D."BaseLine", D."Quantity", NULL, 'RET'
             FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :edate AND D."BaseType" = 20
           UNION ALL
           SELECT '20', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '21', D."BaseEntry", D."BaseLine", D."Quantity", NULL, 'RET'
             FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :edate AND D."BaseType" = 21;

    -- ④ 冲减事件 = 原单 + 取消单；先按 数量 × 暂估单价 取整，再找累计数量达到暂估数量的那一笔（清余数）
    ev = SELECT B."BaseObj", B."BaseEntry", B."BaseLine", C."ObjType", C."DocEntry", C."LineNum", C."DocDate", 'N' AS "IsCancel",
                C."ObjType" AS "OrigObj", C."DocEntry" AS "OrigEntry", C."LineNum" AS "OrigLine",
                C."Q" AS "CQ", ROUND(C."Q" * B."UP", 2) AS "Simple", C."DocAmt", C."MoveType"
           FROM :cons C JOIN :bp B ON B."BaseObj" = C."BaseObj" AND B."BaseEntry" = C."BaseEntry" AND B."BaseLine" = C."BaseLine"
         UNION ALL
         SELECT B."BaseObj", B."BaseEntry", B."BaseLine", X."ObjType", X."DocEntry", X."LineNum", X."DocDate", 'Y',
                C."ObjType", C."DocEntry", C."LineNum", -C."Q", -ROUND(C."Q" * B."UP", 2), -C."DocAmt", C."MoveType"
           FROM :cx X
           JOIN :cons C ON C."ObjType" = X."OrigObj" AND C."DocEntry" = X."OrigEntry" AND C."LineNum" = X."OrigLine"
           JOIN :bp B ON B."BaseObj" = C."BaseObj" AND B."BaseEntry" = C."BaseEntry" AND B."BaseLine" = C."BaseLine";
    ew = SELECT E.*, B."BaseQty", B."FullAmt",
                SUM(E."CQ") OVER (PARTITION BY E."BaseObj", E."BaseEntry", E."BaseLine"
                                  ORDER BY E."DocDate", E."IsCancel", E."ObjType", E."DocEntry", E."LineNum" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "CumQ",
                SUM(E."Simple") OVER (PARTITION BY E."BaseObj", E."BaseEntry", E."BaseLine"
                                      ORDER BY E."DocDate", E."IsCancel", E."ObjType", E."DocEntry", E."LineNum" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "CumS"
           FROM :ev E JOIN :bp B ON B."BaseObj" = E."BaseObj" AND B."BaseEntry" = E."BaseEntry" AND B."BaseLine" = E."BaseLine";
    eo = SELECT W.*,
                CASE WHEN W."IsCancel" = 'N' AND W."CumQ" >= W."BaseQty" - 0.000001 AND W."CumQ" - W."CQ" < W."BaseQty" - 0.000001
                     THEN W."FullAmt" - (W."CumS" - W."Simple") ELSE W."Simple" END AS "Mag",
                CASE WHEN W."IsCancel" = 'N' AND W."CumQ" >= W."BaseQty" - 0.000001 AND W."CumQ" - W."CQ" < W."BaseQty" - 0.000001
                     THEN 'LAST' ELSE 'ROUND' END AS "Rule"
           FROM :ew W;
    ef = SELECT E."BaseObj", E."BaseEntry", E."BaseLine", E."ObjType", E."DocEntry", E."LineNum", E."DocDate", E."IsCancel",
                E."CQ", CASE WHEN E."IsCancel" = 'Y' THEN -O."Mag" ELSE E."Mag" END AS "Mag",
                CASE WHEN E."IsCancel" = 'Y' THEN 'CANCEL' ELSE E."Rule" END AS "Rule", E."DocAmt", E."MoveType"
           FROM :eo E
           LEFT JOIN :eo O ON E."IsCancel" = 'Y' AND O."IsCancel" = 'N' AND O."ObjType" = E."OrigObj" AND O."DocEntry" = E."OrigEntry" AND O."LineNum" = E."OrigLine"
                          AND O."BaseObj" = E."BaseObj" AND O."BaseEntry" = E."BaseEntry" AND O."BaseLine" = E."BaseLine";

    -- ⑤ 全部变动
    mv = SELECT B."BaseObj", B."BaseEntry", B."BaseLine", 'ACCR' AS "MoveType", 'N' AS "IsCancel", B."BaseObj" AS "ObjType",
                B."BaseEntry" AS "DocEntry", B."BaseLine" AS "LineNum", B."BaseDate" AS "DocDate", 0 AS "SortKey",
                B."BaseQty" AS "Qty", B."BaseSign" * B."FullAmt" AS "AccrAmt", CAST(NULL AS DECIMAL(19,2)) AS "DocAmt", 'FULL' AS "AmtRule"
           FROM :bp B
         UNION ALL
         SELECT B."BaseObj", B."BaseEntry", B."BaseLine", 'ACCR', 'Y', X."ObjType", X."DocEntry", X."LineNum", X."DocDate", 1,
                -B."BaseQty", -B."BaseSign" * B."FullAmt", NULL, 'CANCEL'
           FROM :cx X JOIN :bp B ON B."BaseObj" = X."OrigObj" AND B."BaseEntry" = X."OrigEntry" AND B."BaseLine" = X."OrigLine"
         UNION ALL
         SELECT F."BaseObj", F."BaseEntry", F."BaseLine", F."MoveType", F."IsCancel", F."ObjType", F."DocEntry", F."LineNum", F."DocDate", 1,
                -F."CQ", -B."BaseSign" * F."Mag", F."DocAmt", F."Rule"
           FROM :ef F JOIN :bp B ON B."BaseObj" = F."BaseObj" AND B."BaseEntry" = F."BaseEntry" AND B."BaseLine" = F."BaseLine";

    RETURN SELECT CAST(B."BaseObj" AS NVARCHAR(2)) AS "BaseObj", B."BaseEntry", B."BaseLine", B."BaseDocNum", B."BaseDate",
                  B."BaseSign", CAST(B."BaseQty" AS DECIMAL(19,6)) AS "BaseQty", CAST(B."CardCode" AS NVARCHAR(50)) AS "CardCode",
                  CAST(B."ItemCode" AS NVARCHAR(50)) AS "ItemCode", CAST(B."AccrType" AS NVARCHAR(10)) AS "AccrType",
                  CAST(B."PriceRule" AS NVARCHAR(10)) AS "PriceRule", CAST(B."UP" AS DECIMAL(19,6)) AS "UnitPrice",
                  CAST(B."FullAmt" AS DECIMAL(19,2)) AS "FullAmt",
                  CAST(M."MoveType" AS NVARCHAR(10)) AS "MoveType", CAST(M."IsCancel" AS NVARCHAR(1)) AS "IsCancel",
                  CAST(M."ObjType" AS NVARCHAR(2)) AS "ObjType", M."DocEntry", M."LineNum", M."DocDate", M."SortKey",
                  CAST(M."Qty" AS DECIMAL(19,6)) AS "Qty", CAST(M."AccrAmt" AS DECIMAL(19,2)) AS "AccrAmt",
                  CAST(M."DocAmt" AS DECIMAL(19,2)) AS "DocAmt", CAST(M."AmtRule" AS NVARCHAR(10)) AS "AmtRule"
             FROM :mv M JOIN :bp B ON B."BaseObj" = M."BaseObj" AND B."BaseEntry" = M."BaseEntry" AND B."BaseLine" = M."BaseLine";
END;
