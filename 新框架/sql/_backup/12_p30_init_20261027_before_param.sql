-- =====================================================================
-- 新成本框架 第 2 期：P30 初始化与固定价格（设计稿 4、4.1）
-- 替代：0302 Step1001–1009 中与迭代无关的部分、0321_OWOR 的订单汇总、0311 的凭证与重估段。
--
-- 单据行定价类别 Cat（R_LINE.Cat）：
--   FIX     采购收货 / 退货、应付发票 / 贷项差额、库存重估 I11、委外发票差异 APDIF：取 S_LINE.SrcAmt（规则 FIX-01；APDIF 记委外要素）
--   NOCOST  U_CalType=InvntCost 的重估：金额计入期末，不参与加权单价（RVL-01）
--   SRT     有原交货的销售退货：原交货在以前账期的，按原交货单位成本（SRT-01）；原交货在本期的改为 WAVG（与原交货同价）
--   SRTQ    没有原交货的销售退货：期初维护价（SRT-01）；没有维护价的改为 WAVG（SRT-03，PRE-04 警告）
--   CNL     交货 / 退货的取消单：原单为固定价的按原单单位成本反向；否则 WAVG（CNL-01）
--           原单在本期按加权价的，与原单同价相抵，正常；本期找不到原单的才由 POST-05 报出
--   TRF_IN  形态转换入库 I05：= 配对 O05 的金额（迭代中计算，TRF-01）
--   RCPT    订单完工入库：订单本期完工成本按数量分配（WIP-01）
--   ISSUE   订单领料：子件当前单价（WAVG-01）
--   RTN304  生产退料 304：该订单该材料的平均领料单价（RTN-01）
--   B1      没有订单的期初生产入库 I90：取 B1 金额（B1-01）
--   WAVG    其余（销售出库、其他出入库、盘点、形态转换出库等）：物料本期加权单价（WAVG-01）
-- InVal='Y' 的行计入物料加权单价的分子分母：FIX、SRT、SRTQ、CNL（固定价）、TRF_IN、RCPT、RTN304、B1。
-- 金额约定：每条单据行定价时四项分别取整到 2 位；订单内部的结转、在产品保留 6 位，完工入库行按订单成本取整后尾差挤最大行。
-- =====================================================================
-- PRE-23 需要维护期初成本价的物料（用户 2026-10-13，替代旧 CAL_1001_CHECK 第 2 项的收集部分；只读，不写 @MTC_COST_QCPRICE）
-- 判断：物料本期有要按单价计价的行（不是带固定金额的行、不是参数 QCP_PRICED_IN 中的入库、不是有原交货的销售退货），
-- 且计算前没有任何价格来源——没有期初结存金额、没有 QCP_PRICED_IN 中的入库（采购、生产 / 委外 / 返工完工、形态转换）、
-- 没有带金额的入库、没有期初维护价。这些物料不维护价格，本期出库会按 0 或按迭代中偶然得到的价格计价（POST-07 事后报出）。
-- 首次出现 = 以前各期的新框架结果、期初承接、旧 0301 和本期期初都没有这个物料；建议价取以前最近一个账期不为 0 的单价，
-- 都没有时取物料主数据最近采购价。结果写 MTC_CA_R_QCP_NEED（只做检查时也保留），PRE-23 明细最多 CHECK_DTL_MAX 行。
-- 部署在 11 之后（读 R_ITEM 历史）；由 MTC_CA_P_RUN、MTC_CA_P_PRECHECK 在 P10 之后调用。
CREATE OR REPLACE PROCEDURE "MTC_CA_P10_QCP" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE pricedIn NVARCHAR(200);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    pricedIn := IFNULL("MTC_CA_F_PARAM"('QCP_PRICED_IN', :fc), ',I01,I03,I05,I07,I08,I09,I90,');

    ln = SELECT "ItemCode", IFNULL("TransCode", '') AS "TransCode", "Qty",
                CASE WHEN "SrcAmt" IS NOT NULL AND "SrcAmt" <> 0 AND "Qty" > 0 THEN 'Y'
                     WHEN "Qty" > 0 AND LOCATE(:pricedIn, ',' || IFNULL("TransCode", '') || ',') > 0 THEN 'Y'
                     ELSE 'N' END AS "IsSrc",
                CASE WHEN "SrcAmt" IS NOT NULL THEN 'N'
                     WHEN LOCATE(:pricedIn, ',' || IFNULL("TransCode", '') || ',') > 0 THEN 'N'
                     WHEN "TransCode" = 'O06' AND IFNULL("BaseEntry", '') <> '' THEN 'N'
                     ELSE 'Y' END AS "IsNeed"
           FROM "MTC_CA_S_LINE"
          WHERE "RunId" = :RunId AND "Qty" <> 0 AND IFNULL("NoCost", 'N') = 'N';
    src = SELECT DISTINCT "ItemCode" FROM :ln WHERE "IsSrc" = 'Y'
          UNION SELECT "ItemCode" FROM "MTC_CA_S_OPEN" WHERE "RunId" = :RunId AND "Qty" > 0 AND "Amount" <> 0
          UNION SELECT "ItemCode" FROM "MTC_CA_S_QCPRICE" WHERE "RunId" = :RunId AND "Price" <> 0;
    need = SELECT X."ItemCode", STRING_AGG(X."TransCode", ',' ORDER BY X."TransCode") AS "NeedTrans", SUM(X."Qty") AS "NeedQty"
             FROM (SELECT "ItemCode", "TransCode", SUM(ABS("Qty")) AS "Qty" FROM :ln
                    WHERE "IsNeed" = 'Y' AND "ItemCode" NOT IN (SELECT "ItemCode" FROM :src)
                    GROUP BY "ItemCode", "TransCode") X
            GROUP BY X."ItemCode";

    -- 以前出现过（不论有没有价格）与以前的单价
    seen = SELECT "ItemCode", "FcCode" FROM "MTC_CA_R_ITEM"
            WHERE "RunType" = 'F' AND "FcCode" < :fc AND "ItemCode" IN (SELECT "ItemCode" FROM :need)
           UNION ALL
           SELECT "ItemCode", "FcCode" FROM "MTC_CA_BOOT_ITEM"
            WHERE "FcCode" < :fc AND "ItemCode" IN (SELECT "ItemCode" FROM :need)
           UNION ALL
           SELECT "ItemCode", "FcCode" FROM "MTC_COST_0301_INVNT"
            WHERE "CostCode" = '20' AND "FcCode" < :fc AND "ItemCode" IN (SELECT "ItemCode" FROM :need)
           UNION ALL
           SELECT "ItemCode", :fc FROM "MTC_CA_S_OPEN" WHERE "RunId" = :RunId AND "ItemCode" IN (SELECT "ItemCode" FROM :need);
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

    INSERT INTO "MTC_CA_R_QCP_NEED" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "ItemName", "ItmsGrpCod", "iLevel",
                                     "FirstSeen", "LastFc", "NeedTrans", "NeedQty", "SuggPrice", "SuggSrc", "SuggFc")
    SELECT :fc, :rt, :scen, :RunId, N."ItemCode", I."ItemName", I."ItmsGrpCod", I."iLevel",
           CASE WHEN S."LastFc" IS NULL THEN 'Y' ELSE 'N' END, S."LastFc", LEFT(N."NeedTrans", 500), N."NeedQty",
           CASE WHEN G."Price" IS NOT NULL THEN G."Price" WHEN IFNULL(M."LastPurPrc", 0) > 0 THEN M."LastPurPrc" END,
           CASE WHEN G."Price" IS NOT NULL THEN G."Src" WHEN IFNULL(M."LastPurPrc", 0) > 0 THEN 'LASTPUR' END,
           G."FcCode"
      FROM :need N
      LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = :RunId AND I."ItemCode" = N."ItemCode"
      LEFT JOIN (SELECT "ItemCode", MAX("FcCode") AS "LastFc" FROM :seen GROUP BY "ItemCode") S ON S."ItemCode" = N."ItemCode"
      LEFT JOIN :sugg G ON G."ItemCode" = N."ItemCode"
      LEFT JOIN "OITM" M ON M."ItemCode" = N."ItemCode";
    RowCnt := ::ROWCOUNT;

    t23 = SELECT "ItemCode" AS "KeyCode",
                 CASE WHEN "FirstSeen" = 'Y' THEN '首次出现' ELSE '以前出现过（最近 ' || "LastFc" || '），期初没有结存金额' END
                 || '；本期 ' || IFNULL("NeedTrans", '') || ' 需要单价；'
                 || CASE WHEN "SuggPrice" IS NULL THEN '没有可参考的价格'
                         ELSE '建议价 ' || TO_NVARCHAR(ROUND("SuggPrice", 6)) || '（'
                              || MAP("SuggSrc", 'NEW', IFNULL("SuggFc", '') || ' 新框架期末单价', 'OLD', IFNULL("SuggFc", '') || ' 旧框架单价',
                                     'BOOT', IFNULL("SuggFc", '') || ' 期初承接', 'LASTPUR', '物料主数据最近采购价', "SuggSrc") || '）' END AS "Info"
            FROM "MTC_CA_R_QCP_NEED" WHERE "RunId" = :RunId;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-23', :t23, CASE WHEN :RowCnt > 0 THEN :RowCnt || ' 个物料，完整清单见执行台“期初价维护”页（MTC_CA_R_QCP_NEED）' END);
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P30_INIT" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE maxLv INT;
    DECLARE defPool NVARCHAR(20);
    DECLARE boot NVARCHAR(10);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    SELECT MAX("PoolCode") INTO defPool FROM "MTC_CA_C_POOL" WHERE "IsDefault" = 'Y';
    boot := "MTC_CA_F_PARAM"('BOOTSTRAP_FC', :fc);

    -- 1. 单据行与定价类别
    INSERT INTO "MTC_CA_R_LINE" ("FcCode", "RunType", "Scenario", "RunId", "LineId", "ItemCode", "TransCode", "Qty", "Cat",
                                 "OrderType", "OrderEntry", "IsShared", "PoolCode", "RuleId")
    SELECT :fc, :rt, :scen, :RunId, L."LineId", L."ItemCode", L."TransCode", L."Qty",
           CASE WHEN L."NoCost" = 'Y' THEN 'NOCOST'
                WHEN L."Src" IN ('OMRV', 'APDIF') OR L."ObjType" IN ('20', '21', '18', '19') THEN 'FIX'
                WHEN L."TransCode" = 'I05' THEN 'TRF_IN'
                WHEN L."Canceled" = 'C' AND L."ObjType" IN ('15', '16') THEN 'CNL'
                WHEN L."TransCode" = 'O06' AND L."BaseType" = '15' AND L."BaseEntry" IS NOT NULL THEN 'SRT'
                WHEN L."TransCode" = 'O06' THEN 'SRTQ'
                WHEN L."BusiClass" = 'B01' AND L."OrderEntry" IS NOT NULL AND L."OrderLine" IS NULL THEN 'RCPT'
                WHEN L."BusiType" = '304' AND L."OrderEntry" IS NOT NULL THEN 'RTN304'
                WHEN L."BusiClass" = 'B03' AND L."OrderEntry" IS NOT NULL THEN 'ISSUE'
                WHEN L."TransCode" = 'I90' THEN 'B1'
                ELSE 'WAVG' END,
           L."OrderType", L."OrderEntry", L."SharedExp",
           CASE WHEN L."SharedExp" = 'Y' THEN IFNULL(PS."PoolCode", :defPool) END,
           NULL
      FROM "MTC_CA_S_LINE" L
      LEFT JOIN "MTC_CA_C_POOL_SRC" PS ON PS."OcrCode" = L."OcrCode" AND :fc BETWEEN PS."FromFc" AND PS."ToFc"
     WHERE L."RunId" = :RunId;
    RowCnt := ::ROWCOUNT;

    -- 2. 固定价格
    UPDATE T0 SET T0."MatAmt" = CASE WHEN S."Src" = 'APDIF' THEN 0 ELSE ROUND(IFNULL(S."SrcAmt", 0), 2) END,
                  T0."SubAmt" = CASE WHEN S."Src" = 'APDIF' THEN ROUND(IFNULL(S."SrcAmt", 0), 2) ELSE 0 END,
                  T0."Amount" = ROUND(IFNULL(S."SrcAmt", 0), 2),
                  T0."PriceSrc" = CASE WHEN T0."Cat" = 'NOCOST' THEN '重估（InvntCost，只调整结存）'
                                       WHEN S."Src" = 'APDIF' THEN '委外加工费发票差异（发票 − 暂估）' ELSE '来源金额' END,
                  T0."RuleId" = CASE WHEN T0."Cat" = 'NOCOST' THEN 'RVL-01' ELSE 'FIX-01' END
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_S_LINE" S ON S."RunId" = T0."RunId" AND S."LineId" = T0."LineId"
     WHERE T0."RunId" = :RunId AND T0."Cat" IN ('FIX', 'NOCOST');

    UPDATE T0 SET T0."MatAmt" = ROUND(IFNULL(S."B1Amt", 0), 2), T0."Amount" = ROUND(IFNULL(S."B1Amt", 0), 2),
                  T0."PriceSrc" = '没有订单的期初生产入库，取 B1 金额', T0."RuleId" = 'B1-01'
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_S_LINE" S ON S."RunId" = T0."RunId" AND S."LineId" = T0."LineId"
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'B1';

    UPDATE T0 SET T0."MatAmt" = ROUND(Q."Price" * T0."Qty", 2), T0."Amount" = ROUND(Q."Price" * T0."Qty", 2),
                  T0."PriceSrc" = '没有原交货，按期初维护价', T0."RuleId" = 'SRT-01'
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_S_QCPRICE" Q ON Q."RunId" = T0."RunId" AND Q."ItemCode" = T0."ItemCode"
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'SRTQ';
    UPDATE T0 SET T0."Cat" = 'WAVG', T0."PriceSrc" = '没有原交货，也没有期初维护价，按本期加权价', T0."RuleId" = 'SRT-03'
      FROM "MTC_CA_R_LINE" T0
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'SRTQ'
       AND NOT EXISTS (SELECT 1 FROM "MTC_CA_S_QCPRICE" Q WHERE Q."RunId" = T0."RunId" AND Q."ItemCode" = T0."ItemCode");

    -- 3. 销售退货配对：原交货在本期 → WAVG；在以前账期 → 新框架当期结果，2026-08 及以前取旧 0302；都没有 → WAVG 并标注
    srt = SELECT T0."LineId", S."BaseEntry", S."BaseLine"
            FROM "MTC_CA_R_LINE" T0
            JOIN "MTC_CA_S_LINE" S ON S."RunId" = T0."RunId" AND S."LineId" = T0."LineId"
           WHERE T0."RunId" = :RunId AND T0."Cat" = 'SRT';
    same = SELECT R."LineId", MIN(O."LineId") AS "SrcLineId"
             FROM :srt R
             JOIN "MTC_CA_S_LINE" O ON O."RunId" = :RunId AND O."ObjType" = '15'
                                   AND TO_NVARCHAR(O."DocEntry") = R."BaseEntry" AND TO_NVARCHAR(O."LineNum") = R."BaseLine"
            GROUP BY R."LineId";
    prevNew = SELECT R."LineId", S."FcCode",
                     SUM(L."MatAmt") / NULLIF(SUM(L."Qty"), 0) AS "UMat", SUM(L."MfgAmt") / NULLIF(SUM(L."Qty"), 0) AS "UMfg",
                     SUM(L."LabAmt") / NULLIF(SUM(L."Qty"), 0) AS "ULab", SUM(L."SubAmt") / NULLIF(SUM(L."Qty"), 0) AS "USub"
                FROM :srt R
                JOIN "MTC_CA_S_LINE" S ON S."ObjType" = '15' AND TO_NVARCHAR(S."DocEntry") = R."BaseEntry"
                                      AND TO_NVARCHAR(S."LineNum") = R."BaseLine" AND S."FcCode" < :fc
                JOIN "MTC_CA_RUN" U ON U."RunId" = S."RunId" AND U."Status" = 'OK' AND U."RunType" = 'F'
                JOIN "MTC_CA_R_LINE" L ON L."RunId" = S."RunId" AND L."LineId" = S."LineId"
               WHERE R."LineId" NOT IN (SELECT "LineId" FROM :same)
               GROUP BY R."LineId", S."FcCode";
    prevOld = SELECT R."LineId", MAX(O."FcCode") AS "FcCode",
                     SUM(O."Amount") / NULLIF(SUM(O."Quantity"), 0) AS "UMat"
                FROM :srt R
                JOIN "MTC_COST_0302_INVNTDETAIL1" O ON O."ObjType" = '15' AND TO_NVARCHAR(O."DocEntry") = R."BaseEntry"
                                                   AND TO_NVARCHAR(O."LineNum") = R."BaseLine" AND O."FcCode" <= :boot
               WHERE R."LineId" NOT IN (SELECT "LineId" FROM :same)
                 AND R."LineId" NOT IN (SELECT "LineId" FROM :prevNew)
               GROUP BY R."LineId";

    INSERT INTO "MTC_CA_R_PAIR" ("FcCode", "RunType", "Scenario", "RunId", "LineId", "PairType", "SrcLineId", "SrcFc", "SrcTable",
                                 "UMat", "UMfg", "ULab", "USub", "Note")
    SELECT :fc, :rt, :scen, :RunId, "LineId", 'SRT', "SrcLineId", :fc, 'MTC_CA_S_LINE', NULL, NULL, NULL, NULL,
           '原交货在本期，按本期加权价（与原交货同价）'
      FROM :same
    UNION ALL
    SELECT :fc, :rt, :scen, :RunId, P."LineId", 'SRT', NULL, P."FcCode", 'MTC_CA_R_LINE', P."UMat", P."UMfg", P."ULab", P."USub",
           '原交货在 ' || P."FcCode" || '，取新框架当期成本'
      FROM (SELECT X.*, ROW_NUMBER() OVER (PARTITION BY X."LineId" ORDER BY X."FcCode" DESC) AS "Rn" FROM :prevNew X) P
     WHERE P."Rn" = 1
    UNION ALL
    SELECT :fc, :rt, :scen, :RunId, "LineId", 'SRT', NULL, "FcCode", 'MTC_COST_0302_INVNTDETAIL1', "UMat", 0, 0, 0,
           '原交货在 ' || "FcCode" || '，取旧框架成本（全部记材料）'
      FROM :prevOld;

    UPDATE T0 SET T0."Cat" = 'WAVG', T0."PriceSrc" = P."Note", T0."RuleId" = 'SRT-01'
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_R_PAIR" P ON P."RunId" = T0."RunId" AND P."LineId" = T0."LineId" AND P."SrcLineId" IS NOT NULL
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'SRT';
    UPDATE T0 SET T0."MatAmt" = ROUND(IFNULL(P."UMat", 0) * T0."Qty", 2), T0."MfgAmt" = ROUND(IFNULL(P."UMfg", 0) * T0."Qty", 2),
                  T0."LabAmt" = ROUND(IFNULL(P."ULab", 0) * T0."Qty", 2), T0."SubAmt" = ROUND(IFNULL(P."USub", 0) * T0."Qty", 2),
                  T0."Amount" = ROUND(IFNULL(P."UMat", 0) * T0."Qty", 2) + ROUND(IFNULL(P."UMfg", 0) * T0."Qty", 2)
                              + ROUND(IFNULL(P."ULab", 0) * T0."Qty", 2) + ROUND(IFNULL(P."USub", 0) * T0."Qty", 2),
                  T0."PriceSrc" = P."Note", T0."RuleId" = 'SRT-01'
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_R_PAIR" P ON P."RunId" = T0."RunId" AND P."LineId" = T0."LineId" AND P."SrcLineId" IS NULL
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'SRT';
    UPDATE "MTC_CA_R_LINE" SET "Cat" = 'WAVG', "PriceSrc" = '找不到原交货成本，按本期加权价', "RuleId" = 'SRT-02'
     WHERE "RunId" = :RunId AND "Cat" = 'SRT'
       AND "LineId" NOT IN (SELECT "LineId" FROM "MTC_CA_R_PAIR" WHERE "RunId" = :RunId);

    -- 4. 交货 / 退货的取消单：原单在本期且为固定价 → 按原单单位成本；否则 WAVG
    cnl = SELECT T0."LineId", MIN(O."LineId") AS "SrcLineId"
            FROM "MTC_CA_R_LINE" T0
            JOIN "MTC_CA_S_LINE" S ON S."RunId" = T0."RunId" AND S."LineId" = T0."LineId"
            JOIN "MTC_CA_S_LINE" O ON O."RunId" = :RunId AND O."ObjType" = S."ObjType"
                                  AND TO_NVARCHAR(O."DocEntry") = S."BaseEntry" AND TO_NVARCHAR(O."LineNum") = S."BaseLine"
                                  AND O."ItemCode" = S."ItemCode"
           WHERE T0."RunId" = :RunId AND T0."Cat" = 'CNL'
           GROUP BY T0."LineId";
    INSERT INTO "MTC_CA_R_PAIR" ("FcCode", "RunType", "Scenario", "RunId", "LineId", "PairType", "SrcLineId", "SrcFc", "SrcTable",
                                 "UMat", "UMfg", "ULab", "USub", "Note")
    SELECT :fc, :rt, :scen, :RunId, C."LineId", 'CNL', C."SrcLineId", :fc, 'MTC_CA_S_LINE',
           O."MatAmt" / NULLIF(O."Qty", 0), O."MfgAmt" / NULLIF(O."Qty", 0), O."LabAmt" / NULLIF(O."Qty", 0), O."SubAmt" / NULLIF(O."Qty", 0),
           '取消原单（本期，固定价）'
      FROM :cnl C
      JOIN "MTC_CA_R_LINE" O ON O."RunId" = :RunId AND O."LineId" = C."SrcLineId"
     WHERE O."Cat" IN ('FIX', 'SRT', 'SRTQ');
    UPDATE T0 SET T0."MatAmt" = ROUND(IFNULL(P."UMat", 0) * T0."Qty", 2), T0."MfgAmt" = ROUND(IFNULL(P."UMfg", 0) * T0."Qty", 2),
                  T0."LabAmt" = ROUND(IFNULL(P."ULab", 0) * T0."Qty", 2), T0."SubAmt" = ROUND(IFNULL(P."USub", 0) * T0."Qty", 2),
                  T0."Amount" = ROUND(IFNULL(P."UMat", 0) * T0."Qty", 2) + ROUND(IFNULL(P."UMfg", 0) * T0."Qty", 2)
                              + ROUND(IFNULL(P."ULab", 0) * T0."Qty", 2) + ROUND(IFNULL(P."USub", 0) * T0."Qty", 2),
                  T0."PriceSrc" = P."Note", T0."RuleId" = 'CNL-01'
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_R_PAIR" P ON P."RunId" = T0."RunId" AND P."LineId" = T0."LineId"
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'CNL';
    -- 原单在本期、按加权价（普通交货）：取消单与原单同一个本期加权单价，金额正好相抵，不是异常（2026-10-14）
    UPDATE "MTC_CA_R_LINE" SET "Cat" = 'WAVG', "PriceSrc" = '取消单：原单在本期、按加权价，与原单同价相抵', "RuleId" = 'CNL-01'
     WHERE "RunId" = :RunId AND "Cat" = 'CNL'
       AND "LineId" NOT IN (SELECT "LineId" FROM "MTC_CA_R_PAIR" WHERE "RunId" = :RunId)
       AND "LineId" IN (SELECT "LineId" FROM :cnl);
    UPDATE "MTC_CA_R_LINE" SET "Cat" = 'WAVG', "PriceSrc" = '取消单：本期找不到原单，按本期加权价', "RuleId" = 'CNL-01'
     WHERE "RunId" = :RunId AND "Cat" = 'CNL'
       AND "LineId" NOT IN (SELECT "LineId" FROM "MTC_CA_R_PAIR" WHERE "RunId" = :RunId);

    -- 5. 形态转换配对：I05 ↔ 同配对键、同取消状态的 O05，必须正好一行；否则 WAVG 并标注
    trf = SELECT I."LineId", MAX(O."LineId") AS "SrcLineId", COUNT(*) AS "Cnt"
            FROM "MTC_CA_S_LINE" I
            JOIN "MTC_CA_S_LINE" O ON O."RunId" = I."RunId" AND O."TransCode" = 'O05' AND O."PairKey" = I."PairKey"
                                  AND IFNULL(O."Canceled", 'N') = IFNULL(I."Canceled", 'N')
           WHERE I."RunId" = :RunId AND I."TransCode" = 'I05'
           GROUP BY I."LineId";
    INSERT INTO "MTC_CA_R_PAIR" ("FcCode", "RunType", "Scenario", "RunId", "LineId", "PairType", "SrcLineId", "SrcFc", "SrcTable", "Note")
    SELECT :fc, :rt, :scen, :RunId, "LineId", 'TRF', "SrcLineId", :fc, 'MTC_CA_S_LINE', '形态转换：A 入库 = B 出库'
      FROM :trf WHERE "Cnt" = 1;
    UPDATE "MTC_CA_R_LINE" SET "Cat" = 'WAVG', "PriceSrc" = '形态转换配不上唯一的转出行，按本期加权价', "RuleId" = 'TRF-01'
     WHERE "RunId" = :RunId AND "Cat" = 'TRF_IN'
       AND "LineId" NOT IN (SELECT "LineId" FROM "MTC_CA_R_PAIR" WHERE "RunId" = :RunId AND "PairType" = 'TRF');

    UPDATE "MTC_CA_R_LINE" SET "InVal" = 'Y'
     WHERE "RunId" = :RunId AND "Cat" IN ('FIX', 'SRT', 'SRTQ', 'CNL', 'TRF_IN', 'RCPT', 'RTN304', 'B1');

    -- 6. 物料：有变动、有期初或是订单产品的物料；层级 -1 / 无层级的放在最高层之后
    SELECT IFNULL(MAX("iLevel"), 0) INTO maxLv FROM "MTC_CA_S_ITEM" WHERE "RunId" = :RunId;
    INSERT INTO "MTC_CA_R_ITEM" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "iLevel",
                                 "OpenQty", "OpenMat", "OpenMfg", "OpenLab", "OpenSub", "PMat", "PMfg", "PLab", "PSub", "PriceSrc")
    SELECT :fc, :rt, :scen, :RunId, K."ItemCode",
           CASE WHEN IFNULL(I."iLevel", -1) < 0 THEN :maxLv + 1 ELSE I."iLevel" END,
           IFNULL(O."Qty", 0), IFNULL(O."MatAmt", 0), IFNULL(O."MfgAmt", 0), IFNULL(O."LabAmt", 0), IFNULL(O."SubAmt", 0),
           -- 第 1 轮初值：期初维护价；没有则上期期末单价；都没有为 0
           CASE WHEN Q."ItemCode" IS NOT NULL THEN Q."Price" WHEN O."Qty" > 0 THEN O."MatAmt" / O."Qty" ELSE 0 END,
           CASE WHEN Q."ItemCode" IS NULL AND O."Qty" > 0 THEN O."MfgAmt" / O."Qty" ELSE 0 END,
           CASE WHEN Q."ItemCode" IS NULL AND O."Qty" > 0 THEN O."LabAmt" / O."Qty" ELSE 0 END,
           CASE WHEN Q."ItemCode" IS NULL AND O."Qty" > 0 THEN O."SubAmt" / O."Qty" ELSE 0 END,
           CASE WHEN Q."ItemCode" IS NOT NULL THEN 'QCPRICE' WHEN O."Qty" > 0 THEN 'OPEN' ELSE 'ZERO' END
      FROM (SELECT "ItemCode" FROM "MTC_CA_S_LINE" WHERE "RunId" = :RunId
            UNION SELECT "ItemCode" FROM "MTC_CA_S_OPEN" WHERE "RunId" = :RunId
            UNION SELECT "ItemCode" FROM "MTC_CA_S_ORDER" WHERE "RunId" = :RunId AND "ItemCode" IS NOT NULL) K
      LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = :RunId AND I."ItemCode" = K."ItemCode"
      LEFT JOIN "MTC_CA_S_OPEN" O ON O."RunId" = :RunId AND O."ItemCode" = K."ItemCode"
      LEFT JOIN "MTC_CA_S_QCPRICE" Q ON Q."RunId" = :RunId AND Q."ItemCode" = K."ItemCode";

    -- 7. 订单：结转比例 r = min(累计入库 ÷ 计划, 1)，本期无入库为空（S5）；R_ORDER.ClosedInFc = 截至期末已关闭（含以前账期关闭的，Q35）
    INSERT INTO "MTC_CA_R_ORDER" ("FcCode", "RunType", "Scenario", "RunId", "OrderType", "OrderEntry", "WorType", "ItemCode", "iLevel",
                                  "PlannedQty", "PrevRecvQty", "RecvQty", "Ratio", "ClosedInFc")
    SELECT :fc, :rt, :scen, :RunId, O."OrderType", O."OrderEntry", O."WorType", O."ItemCode",
           IFNULL(I."iLevel", :maxLv + 1), O."PlannedQty", O."PrevRecvQty", O."RecvQty",
           CASE WHEN O."RecvQty" = 0 THEN NULL
                WHEN IFNULL(O."PlannedQty", 0) <= 0 THEN 1
                ELSE LEAST(GREATEST((O."PrevRecvQty" + O."RecvQty") / O."PlannedQty", 0), 1) END,
           -- 按关单处理（期末在产品转关单差异）：本期关闭，或以前账期已关闭、本期仍有单据挂上来的（如加工费退货，Q35，用户 2026-10-17）
           CASE WHEN O."ClosedInFc" = 'Y' OR O."StatusAtEnd" = 'CLOSED' THEN 'Y' ELSE 'N' END
      FROM "MTC_CA_S_ORDER" O
      LEFT JOIN "MTC_CA_R_ITEM" I ON I."RunId" = :RunId AND I."ItemCode" = O."ItemCode"
     WHERE O."RunId" = :RunId;

    -- 8. 订单 × 材料：期初累计 + 本期领料行；委外加工费作为 '#SUBFEE' 行
    INSERT INTO "MTC_CA_R_ORDER_MAT" ("FcCode", "RunType", "Scenario", "RunId", "OrderType", "OrderEntry", "ItemCode",
                                      "OpenIssQty", "OpenIssMat", "OpenIssMfg", "OpenIssLab", "OpenIssSub",
                                      "OpenCarMat", "OpenCarMfg", "OpenCarLab", "OpenCarSub", "IssQty", "IssSub")
    SELECT :fc, :rt, :scen, :RunId, K."OrderType", K."OrderEntry", K."ItemCode",
           IFNULL(P."CumIssueQty", 0), IFNULL(P."CumIssueMat", 0), IFNULL(P."CumIssueMfg", 0), IFNULL(P."CumIssueLab", 0), IFNULL(P."CumIssueSub", 0),
           IFNULL(P."CumCarriedMat", 0), IFNULL(P."CumCarriedMfg", 0), IFNULL(P."CumCarriedLab", 0), IFNULL(P."CumCarriedSub", 0),
           IFNULL(L."Qty", 0), IFNULL(F."Amount", 0)
      FROM (SELECT "OrderType", "OrderEntry", "ItemCode" FROM "MTC_CA_S_ORDER_OPEN" WHERE "RunId" = :RunId
            UNION
            SELECT "OrderType", "OrderEntry", "ItemCode" FROM "MTC_CA_R_LINE"
             WHERE "RunId" = :RunId AND "Cat" IN ('ISSUE', 'RTN304')
            UNION
            SELECT "OrderType", "OrderEntry", '#SUBFEE' FROM "MTC_CA_S_SUBFEE"
             WHERE "RunId" = :RunId AND "OrderEntry" IS NOT NULL) K
      JOIN "MTC_CA_R_ORDER" O ON O."RunId" = :RunId AND O."OrderType" = K."OrderType" AND O."OrderEntry" = K."OrderEntry"
      LEFT JOIN "MTC_CA_S_ORDER_OPEN" P ON P."RunId" = :RunId AND P."OrderType" = K."OrderType"
                                       AND P."OrderEntry" = K."OrderEntry" AND P."ItemCode" = K."ItemCode"
      LEFT JOIN (SELECT "OrderType", "OrderEntry", "ItemCode", -SUM("Qty") AS "Qty" FROM "MTC_CA_R_LINE"
                  WHERE "RunId" = :RunId AND "Cat" IN ('ISSUE', 'RTN304')
                  GROUP BY "OrderType", "OrderEntry", "ItemCode") L
        ON L."OrderType" = K."OrderType" AND L."OrderEntry" = K."OrderEntry" AND L."ItemCode" = K."ItemCode"
      LEFT JOIN (SELECT "OrderType", "OrderEntry", SUM("Amount") AS "Amount" FROM "MTC_CA_S_SUBFEE"
                  WHERE "RunId" = :RunId AND "OrderEntry" IS NOT NULL GROUP BY "OrderType", "OrderEntry") F
        ON K."ItemCode" = '#SUBFEE' AND F."OrderType" = K."OrderType" AND F."OrderEntry" = K."OrderEntry";

    -- 9. 费用池固定部分：凭证、重估（按成本中心归池，没配置或没有成本中心的进默认池，Q12）
    INSERT INTO "MTC_CA_R_POOL" ("FcCode", "RunType", "Scenario", "RunId", "PoolCode", "Elem", "Src", "Amount")
    -- HANA 不接受 GROUP BY 里带变量的表达式，先在子查询里算出池代码
    SELECT :fc, :rt, :scen, :RunId, X."PoolCode", X."Elem", X."Src", SUM(X."Amount")
      FROM (SELECT IFNULL(PS."PoolCode", :defPool) AS "PoolCode", E."Elem", E."Src", E."Amount"
              FROM "MTC_CA_S_EXP" E
              LEFT JOIN "MTC_CA_C_POOL_SRC" PS ON PS."OcrCode" = E."OcrCode" AND :fc BETWEEN PS."FromFc" AND PS."ToFc"
             WHERE E."RunId" = :RunId) X
     GROUP BY X."PoolCode", X."Elem", X."Src";
END
