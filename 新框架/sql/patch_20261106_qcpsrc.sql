-- 2026-11-06 补丁：PRE-23 的价格来源改看能不能给出单价，新增 POST-17（用户：盘盈入库没有单价时要报出来）
--   0 金额的采购收货不算来源；加权单价的分母（期初数量 + 计入加权单价的行）要大于 0（MTC_CA_F_QCP_SRC，PRE-04 同一口径）。
--   POST-17 加权价入库 0 成本，固定只警告；原有 POST-07 的阻断不变。
-- 已部署的库依次执行：08_precheck.sql（函数、P_CHECK_PUT、PRE-04），本文件，14_p50_p60_p65.sql（P60），再 CALL "MTC_CA_P_META_SYNC"()。
-- 离线写的，还没编译。
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('PRE-23', 'PRE', 230, '需要维护期初成本价的物料', '本期有要按单价计价的变动（出库、其他入库、盘点、无原单退货等），计算前却没有任何价格来源（无期初结存金额、无采购 / 完工 / 形态转换入库、无维护价；0 金额的采购收货不算来源，加权单价的分母（期初数量 + 计入加权单价的行）要大于 0）；区分首次出现和以前出现过，给出建议价（以前最近一期单价，或最近采购价）。只列清单，不写 @MTC_COST_QCPRICE，在 B1 维护后重新检查（用户 2026-10-13）', 'N', 'S1') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-17', 'POST', 179, '加权价入库 0 成本', '盘盈、其他入库、无原单退货等按加权价入库的物料，算出的单价为 0（如只有 0 金额的采购收货，或期初有数量没有金额），这些入库都是 0 成本；固定只警告（用户 2026-11-06）。完全没有单价来源的归 POST-07', 'N', 'S1') WITH PRIMARY KEY
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P10_QCP" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE pricedIn NVARCHAR(200);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    pricedIn := IFNULL("MTC_CA_F_PARAM"('QCP_PRICED_IN', :fc), ',I01,I03,I05,I07,I08,I09,I90,');

    ln = SELECT "LineId", "ItemCode", IFNULL("TransCode", '') AS "TransCode", "Qty",
                "ObjType", "DocEntry", "DocNum", "LineNum", "DocDate", "BusiType", "WhsCode",
                CASE WHEN "SrcAmt" IS NOT NULL THEN 'N'
                     WHEN LOCATE(:pricedIn, ',' || IFNULL("TransCode", '') || ',') > 0 THEN 'N'
                     WHEN "TransCode" = 'O06' AND "BaseType" = '15' AND "BaseEntry" IS NOT NULL THEN 'N'   -- 与 P30 SRT 同一判断（2026-10-29）
                     ELSE 'Y' END AS "IsNeed"
           FROM "MTC_CA_S_LINE"
          WHERE "RunId" = :RunId AND "Qty" <> 0 AND IFNULL("NoCost", 'N') = 'N';
    fs = SELECT "ItemCode", "HasIn", "IsSrc" FROM "MTC_CA_F_QCP_SRC"(:RunId, :pricedIn);
    src = SELECT "ItemCode" FROM :fs WHERE "IsSrc" = 'Y'
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

    -- 来源单据行和按交易类型的单号清单（用户 2026-10-30：清单和 B1 行备注里要看得出这个物料为什么要维护）
    INSERT INTO "MTC_CA_R_QCP_LINE" ("FcCode", "RunType", "Scenario", "RunId", "LineId", "ItemCode", "ObjType", "DocEntry", "DocNum",
                                     "LineNum", "DocDate", "TransCode", "BusiType", "WhsCode", "Qty")
    SELECT :fc, :rt, :scen, :RunId, "LineId", "ItemCode", "ObjType", "DocEntry", "DocNum", "LineNum", "DocDate", "TransCode", "BusiType", "WhsCode", "Qty"
      FROM :ln WHERE "IsNeed" = 'Y' AND "ItemCode" IN (SELECT "ItemCode" FROM :need);
    dt = SELECT "ItemCode", "TransCode", "ObjType", IFNULL("DocNum", 'Entry ' || "DocEntry") AS "DocNum", MIN("DocDate") AS "DocDate"
           FROM :ln WHERE "IsNeed" = 'Y' AND "ItemCode" IN (SELECT "ItemCode" FROM :need)
          GROUP BY "ItemCode", "TransCode", "ObjType", IFNULL("DocNum", 'Entry ' || "DocEntry");
    dt2 = SELECT "ItemCode", "TransCode", "DocNum",
                 ROW_NUMBER() OVER (PARTITION BY "ItemCode", "TransCode" ORDER BY "DocDate", "DocNum") AS "Rn",
                 COUNT(*) OVER (PARTITION BY "ItemCode", "TransCode") AS "Cnt"
            FROM :dt;
    tx = SELECT X."ItemCode", X."TransCode", IFNULL(T."Name", '') AS "TransName", MAX(X."Cnt") AS "Cnt",
                STRING_AGG(X."DocNum", '、' ORDER BY X."Rn") AS "Docs"
           FROM :dt2 X LEFT JOIN "@MTC_COST_IOTYPE" T ON T."Code" = X."TransCode"
          WHERE X."Rn" <= 10
          GROUP BY X."ItemCode", X."TransCode", IFNULL(T."Name", '');
    nd = SELECT "ItemCode",
                STRING_AGG(CASE WHEN "TransCode" = '' THEN '交易类型识别不了' ELSE "TransCode" || ' ' || "TransName" END, '、' ORDER BY "TransCode") AS "Names",
                STRING_AGG(CASE WHEN "TransCode" = '' THEN '交易类型识别不了' ELSE "TransCode" || ' ' || "TransName" END
                           || ' ' || "Cnt" || ' 张（单号 Num ' || "Docs" || CASE WHEN "Cnt" > 10 THEN ' 等' ELSE '' END || '）', '；' ORDER BY "TransCode") AS "Docs"
           FROM :tx GROUP BY "ItemCode";

    INSERT INTO "MTC_CA_R_QCP_NEED" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "ItemName", "ItmsGrpCod", "iLevel",
                                     "FirstSeen", "LastFc", "NeedTrans", "NeedQty", "SuggPrice", "SuggSrc", "SuggFc", "Reason", "NeedDocs")
    SELECT :fc, :rt, :scen, :RunId, N."ItemCode", I."ItemName", I."ItmsGrpCod", I."iLevel",
           CASE WHEN S."LastFc" IS NULL THEN 'Y' ELSE 'N' END, S."LastFc", LEFT(N."NeedTrans", 500), N."NeedQty",
           CASE WHEN G."Price" IS NOT NULL THEN G."Price" WHEN IFNULL(M."LastPurPrc", 0) > 0 THEN M."LastPurPrc" END,
           CASE WHEN G."Price" IS NOT NULL THEN G."Src" WHEN IFNULL(M."LastPurPrc", 0) > 0 THEN 'LASTPUR' END,
           G."FcCode",
           LEFT(CASE WHEN S."LastFc" IS NULL THEN '首次出现（以前各期和本期期初都没有这个物料）'
                     ELSE '以前出现过（最近 ' || S."LastFc" || '），本期期初没有结存金额' END
                || '；本期有 ' || IFNULL(D."Names", N."NeedTrans") || ' 要按单价计价'
                || CASE WHEN H."ItemCode" IS NOT NULL THEN '，本期的采购 / 完工入库给不出单价（金额为 0 或已退回），也没有期初维护价'
                        ELSE '，计算前没有采购 / 完工 / 形态转换入库，也没有期初维护价' END, 500),
           LEFT(D."Docs", 1000)
      FROM :need N
      LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = :RunId AND I."ItemCode" = N."ItemCode"
      LEFT JOIN (SELECT "ItemCode", MAX("FcCode") AS "LastFc" FROM :seen GROUP BY "ItemCode") S ON S."ItemCode" = N."ItemCode"
      LEFT JOIN :sugg G ON G."ItemCode" = N."ItemCode"
      LEFT JOIN :nd D ON D."ItemCode" = N."ItemCode"
      LEFT JOIN (SELECT "ItemCode" FROM :fs WHERE "HasIn" = 'Y') H ON H."ItemCode" = N."ItemCode"
      LEFT JOIN "OITM" M ON M."ItemCode" = N."ItemCode";
    RowCnt := ::ROWCOUNT;

    t23 = SELECT "ItemCode" AS "KeyCode",
                 IFNULL("Reason", '') || '；'
                 || CASE WHEN "SuggPrice" IS NULL THEN '没有可参考的价格'
                         ELSE '建议价 ' || TO_NVARCHAR(ROUND("SuggPrice", 6)) || '（'
                              || MAP("SuggSrc", 'NEW', IFNULL("SuggFc", '') || ' 新框架期末单价', 'OLD', IFNULL("SuggFc", '') || ' 旧框架单价',
                                     'BOOT', IFNULL("SuggFc", '') || ' 期初承接', 'LASTPUR', '物料主数据最近采购价', "SuggSrc") || '）' END
                 || IFNULL('；单据：' || "NeedDocs", '') AS "Info"
            FROM "MTC_CA_R_QCP_NEED" WHERE "RunId" = :RunId;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-23', :t23, CASE WHEN :RowCnt > 0 THEN :RowCnt || ' 个物料，完整清单见执行台“期初价维护”页（MTC_CA_R_QCP_NEED）' END);
END
@@
