-- 修 P55 除零（2026-11-04）：报错 SQL 304 division by zero，在 MTC_CA_P55_REVAL 的单价计算。
-- 只替换这一个过程，不动表和数据；执行后重新发起计算即可。分隔符 @@。未编译。
CREATE OR REPLACE PROCEDURE "MTC_CA_P55_REVAL" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE devPct DECIMAL(19,6);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    devPct := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('REVAL_DEV_PCT', :fc), '10'), 19, 6);

    ln = SELECT L."ItemCode", L."Qty", L."Amount", L."InVal", L."Cat", S."Src", S."ObjType",
                CASE WHEN L."Qty" = 0 AND L."Cat" = 'FIX' AND S."ObjType" IN ('18', '19') THEN 'Y' ELSE 'N' END AS "IsDif"
           FROM "MTC_CA_R_LINE" L
           JOIN "MTC_CA_S_LINE" S ON S."RunId" = L."RunId" AND S."LineId" = L."LineId"
          WHERE L."RunId" = :RunId;
    sm = SELECT "ItemCode",
                SUM(CASE WHEN "InVal" = 'Y' THEN "Qty" ELSE 0 END) AS "InQ",
                SUM(CASE WHEN "InVal" = 'Y' THEN "Amount" ELSE 0 END) AS "InA",
                SUM(CASE WHEN "IsDif" = 'Y' THEN "Amount" ELSE 0 END) AS "Dif",
                SUM(CASE WHEN "Src" = 'OMRV' AND "Cat" = 'FIX' THEN "Amount" ELSE 0 END) AS "Rvl"
           FROM :ln GROUP BY "ItemCode";
    p0 = SELECT I."ItemCode", I."iLevel", I."EndQty", I."EndMat" + I."EndMfg" + I."EndLab" + I."EndSub" AS "EndAmt",
                I."OpenQty" + IFNULL(S."InQ", 0) AS "Q",
                I."OpenMat" + I."OpenMfg" + I."OpenLab" + I."OpenSub" + IFNULL(S."InA", 0) AS "A",
                IFNULL(S."Dif", 0) AS "Dif", IFNULL(S."Rvl", 0) AS "Rvl"
           FROM "MTC_CA_R_ITEM" I
           LEFT JOIN :sm S ON S."ItemCode" = I."ItemCode"
          WHERE I."RunId" = :RunId AND I."OpenQty" + IFNULL(S."InQ", 0) > 0;
    -- 除数都要 NULLIF：HANA 合并表变量后，除法可能先于 p0 的 Q > 0 过滤、CASE 的判断计算，Q = 0 的物料会报 304（2026-11-04 运行时遇到）
    p1 = SELECT P.*, "A" / NULLIF("Q", 0) AS "CurP", ("A" - "Dif" - "Rvl") / NULLIF("Q", 0) AS "BaseP" FROM :p0 P;
    p2 = SELECT P.*, CASE WHEN "Dif" <> 0 AND "BaseP" > 0 THEN ABS("CurP" - "BaseP") / NULLIF("BaseP", 0) * 100 END AS "Dev" FROM :p1 P;
    cand = SELECT P.*, CASE WHEN "Dev" >= :devPct AND "Rvl" = 0 THEN 'APDIF'
                            WHEN "EndQty" > 0 AND "EndAmt" < 0.005 THEN 'ZERO' END AS "Kind"
             FROM :p2 P;
    need = SELECT * FROM :cand WHERE "Kind" IS NOT NULL;

    hist = SELECT "ItemCode", "FcCode", "Price", "Src", "Pri" FROM (
               SELECT "ItemCode", "FcCode", "PMat" + "PMfg" + "PLab" + "PSub" AS "Price", 'NEW' AS "Src", 1 AS "Pri"
                 FROM "MTC_CA_R_ITEM" WHERE "RunType" = 'F' AND "FcCode" < :fc AND "ItemCode" IN (SELECT "ItemCode" FROM :need)
               UNION ALL
               SELECT "ItemCode", "FcCode", "Price", 'OLD', 2
                 FROM "MTC_COST_0301_INVNT" WHERE "CostCode" = '20' AND "FcCode" < :fc AND "ItemCode" IN (SELECT "ItemCode" FROM :need)
               UNION ALL
               SELECT "ItemCode", "FcCode", "Amount" / NULLIF("Qty", 0), 'BOOT', 3
                 FROM "MTC_CA_BOOT_ITEM" WHERE "FcCode" < :fc AND "ItemCode" IN (SELECT "ItemCode" FROM :need))
            WHERE IFNULL("Price", 0) > 0;
    sugg = SELECT "ItemCode", "FcCode", "Price", "Src"
             FROM (SELECT H.*, ROW_NUMBER() OVER (PARTITION BY "ItemCode" ORDER BY "FcCode" DESC, "Pri") AS "Rn" FROM :hist H)
            WHERE "Rn" = 1;

    -- 造成差额的单据：按单据类型列单号 Num，每类最多 10 张
    dd = SELECT DISTINCT S."ItemCode", S."ObjType", IFNULL(S."DocNum", 'Entry ' || S."DocEntry") AS "DocNum"
           FROM "MTC_CA_S_LINE" S
          WHERE S."RunId" = :RunId AND S."Qty" = 0 AND S."ObjType" IN ('18', '19')
            AND S."ItemCode" IN (SELECT "ItemCode" FROM :need);
    dd2 = SELECT D.*, ROW_NUMBER() OVER (PARTITION BY "ItemCode", "ObjType" ORDER BY "DocNum") AS "Rn",
                 COUNT(*) OVER (PARTITION BY "ItemCode", "ObjType") AS "Cnt" FROM :dd D;
    dd3 = SELECT "ItemCode", "ObjType", MAX("Cnt") AS "Cnt", STRING_AGG("DocNum", '、' ORDER BY "Rn") AS "Docs"
            FROM :dd2 WHERE "Rn" <= 10 GROUP BY "ItemCode", "ObjType";
    docs = SELECT "ItemCode", STRING_AGG(MAP("ObjType", '18', '应付发票 ', '应付贷项 ') || "Docs"
                                         || CASE WHEN "Cnt" > 10 THEN ' 等 ' || "Cnt" || ' 张' ELSE '' END, '；' ORDER BY "ObjType") AS "Docs"
             FROM :dd3 GROUP BY "ItemCode";

    pick = SELECT N.*, CASE WHEN N."Dif" <> 0 AND N."BaseP" > 0 THEN N."BaseP" WHEN G."Price" IS NOT NULL THEN G."Price"
                            WHEN IFNULL(M."LastPurPrc", 0) > 0 THEN M."LastPurPrc" END AS "Sugg",
                  CASE WHEN N."Dif" <> 0 AND N."BaseP" > 0 THEN 'EXDIF' WHEN G."Price" IS NOT NULL THEN G."Src"
                       WHEN IFNULL(M."LastPurPrc", 0) > 0 THEN 'LASTPUR' END AS "SuggSrc",
                  CASE WHEN N."Dif" <> 0 AND N."BaseP" > 0 THEN NULL ELSE G."FcCode" END AS "SuggFc"
             FROM :need N
             LEFT JOIN :sugg G ON G."ItemCode" = N."ItemCode"
             LEFT JOIN "OITM" M ON M."ItemCode" = N."ItemCode";

    INSERT INTO "MTC_CA_R_REVAL_NEED" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "ItemName", "ItmsGrpCod", "iLevel", "Kind",
        "EndQty", "EndAmt", "BaseQty", "CurPrice", "ApDif", "RevalAmt", "DevPct", "SuggPrice", "SuggSrc", "SuggFc", "AdjAmt", "Reason", "NeedDocs")
    SELECT :fc, :rt, :scen, :RunId, P."ItemCode", I."ItemName", I."ItmsGrpCod", P."iLevel", P."Kind",
           P."EndQty", P."EndAmt", P."Q", P."CurP", P."Dif", P."Rvl", P."Dev", P."Sugg", P."SuggSrc", P."SuggFc",
           ROUND((P."Sugg" - P."CurP") * P."Q", 2),
           LEFT(CASE WHEN P."Kind" = 'APDIF'
                     THEN '本期发票 / 贷项差额 ' || TO_NVARCHAR(ROUND(P."Dif", 2)) || '，加权价 ' || TO_NVARCHAR(ROUND(P."CurP", 6))
                          || ' 偏离剔除差异后单价 ' || TO_NVARCHAR(ROUND(P."BaseP", 6)) || ' 达 ' || TO_NVARCHAR(ROUND(P."Dev", 1)) || '%'
                     ELSE '结存数量 ' || TO_NVARCHAR(ROUND(P."EndQty", 2)) || '，结存金额 ' || TO_NVARCHAR(ROUND(P."EndAmt", 2)) || '（<= 0）' END, 500),
           LEFT(D."Docs", 1000)
      FROM :pick P
      LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = :RunId AND I."ItemCode" = P."ItemCode"
      LEFT JOIN :docs D ON D."ItemCode" = P."ItemCode";
    RowCnt := ::ROWCOUNT;
END
@@
