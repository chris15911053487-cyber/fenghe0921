/* =====================================================================
 * 新报表函数（未部署，用户 2026-11-05）：MTC_RPT_F_SALE_COST 交货 / 销售退货行的单位成本
 * 一行 = 一条 DLN1 / RDN1；给 B1 查询按单据行关联，取代 MTC_COST_0302_INVNTDETAIL1 的 Price（reports/销售发票明细_新框架成本.sql）。
 * 取数优先级同 FI4004_V2、P71：
 *   INIT  LEGACY_INITPRICE_DATE（默认 2024-12-31）及以前的单据，行上 U_InitPrice 不为 0 → U_InitPrice
 *   NEW   该单据账期成本报表所用的运行（MTC_CA_F_RPT_RUN：已生成凭单取 PostRunId，否则 CalcRunId）→ R_LINE 金额 ÷ 数量
 *   HIST  承接账期 BOOTSTRAP_FC 及以前 → 旧框架回填的历史运行（RunType H），同上
 *   OLD   还没有回填的历史账期 → 旧 0302（只取 BOOTSTRAP_FC 及以前，并行期的旧结果不用）
 * 都没有的行不返回（该期未计算，或不在成本计算范围）。
 * 2026-11-05 R23 也用它，同样的定义已放进 新框架/sql/21_reports.sql（进部署包），两处保持一致；部署了 21_reports.sql 就不用再执行本文件。
 * 依赖：新框架 MTC_CA_F_RPT_RUN / MTC_CA_F_PARAM / MTC_CA_S_LINE / MTC_CA_R_LINE（21_reports.sql、07、11 先部署）。
 * ===================================================================== */
CREATE OR REPLACE FUNCTION "MTC_RPT_F_SALE_COST" ()
RETURNS TABLE ("ObjType" NVARCHAR(20), "DocEntry" INTEGER, "LineNum" INTEGER, "Price" DECIMAL(19,6), "CostSrc" NVARCHAR(10))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE f0 NVARCHAR(10); DECLARE f1 NVARCHAR(10); DECLARE boot NVARCHAR(10); DECLARE legacy DATE;
    -- 交货可能在开票之前任何账期，所以取全部账期
    SELECT MIN("Code"), MAX("Code") INTO f0, f1 FROM "OFPR";
    boot := IFNULL("MTC_CA_F_PARAM"('BOOTSTRAP_FC', :f1), '0000-00');
    legacy := TO_DATE(IFNULL("MTC_CA_F_PARAM"('LEGACY_INITPRICE_DATE', :f1), '1900-01-01'));

    runs = SELECT "RunId" FROM "MTC_CA_F_RPT_RUN"(:f0, :f1) WHERE "RunId" IS NOT NULL;
    nc = SELECT S."ObjType", S."DocEntry", S."LineNum", SUM(L."Amount") / SUM(L."Qty") AS "UC", MAX(R."RunType") AS "RT"
           FROM :runs U
           JOIN "MTC_CA_RUN" R ON R."RunId" = U."RunId"
           JOIN "MTC_CA_S_LINE" S ON S."RunId" = U."RunId" AND S."ObjType" IN ('15', '16')
           JOIN "MTC_CA_R_LINE" L ON L."RunId" = S."RunId" AND L."LineId" = S."LineId"
          GROUP BY S."ObjType", S."DocEntry", S."LineNum"
         HAVING SUM(L."Qty") <> 0;
    old = SELECT "ObjType", "DocEntry", "LineNum", SUM("Amount") / SUM("Quantity") AS "UC"
            FROM "MTC_COST_0302_INVNTDETAIL1"
           WHERE "CostCode" = '20' AND "ObjType" IN ('15', '16') AND "FcCode" <= :boot
           GROUP BY "ObjType", "DocEntry", "LineNum"
          HAVING SUM("Quantity") <> 0;
    ini = SELECT '15' AS "ObjType", D."DocEntry", D."LineNum", D."U_InitPrice" AS "UC"
            FROM "ODLN" M JOIN "DLN1" D ON M."DocEntry" = D."DocEntry"
           WHERE M."DocDate" <= :legacy AND IFNULL(D."U_InitPrice", 0) <> 0
          UNION ALL
          SELECT '16', D."DocEntry", D."LineNum", D."U_InitPrice"
            FROM "ORDN" M JOIN "RDN1" D ON M."DocEntry" = D."DocEntry"
           WHERE M."DocDate" <= :legacy AND IFNULL(D."U_InitPrice", 0) <> 0;
    k = SELECT "ObjType", "DocEntry", "LineNum" FROM :nc
        UNION SELECT "ObjType", "DocEntry", "LineNum" FROM :old
        UNION SELECT "ObjType", "DocEntry", "LineNum" FROM :ini;

    RETURN
    SELECT K."ObjType", K."DocEntry", K."LineNum",
           CAST(COALESCE(I."UC", N."UC", O."UC") AS DECIMAL(19,6)) AS "Price",
           CAST(CASE WHEN I."UC" IS NOT NULL THEN 'INIT'
                     WHEN N."UC" IS NOT NULL THEN CASE WHEN N."RT" = 'H' THEN 'HIST' ELSE 'NEW' END
                     ELSE 'OLD' END AS NVARCHAR(10)) AS "CostSrc"
      FROM :k K
      LEFT JOIN :ini I ON I."ObjType" = K."ObjType" AND I."DocEntry" = K."DocEntry" AND I."LineNum" = K."LineNum"
      LEFT JOIN :nc N ON N."ObjType" = K."ObjType" AND N."DocEntry" = K."DocEntry" AND N."LineNum" = K."LineNum"
      LEFT JOIN :old O ON O."ObjType" = K."ObjType" AND O."DocEntry" = K."DocEntry" AND O."LineNum" = K."LineNum";
END
