-- =====================================================================
-- 新成本框架 第 1 期：P10 计算前检查（设计稿第 6 节；替代 CAL_1001_CHECK，只读）
-- 在 P20 快照之后执行，检查快照和 B1 单据；不修改 B1、不重建旧表、不写期初维护价。
-- 结果写 MTC_CA_R_CHECK（每项一行）和 MTC_CA_R_CHECK_DTL（问题明细，每项最多 CHECK_DTL_MAX 行）。
-- 检查项的标题、是否阻断登记在 MTC_CA_C_CHECK；Active='N' 的记为 SKIP。
-- =====================================================================
CREATE OR REPLACE PROCEDURE "MTC_CA_P_CHECK_PUT" (
    IN RunId   BIGINT,
    IN CheckId NVARCHAR(20),
    IN dtl     TABLE ("KeyCode" NVARCHAR(5000), "Info" NVARCHAR(5000)),
    IN Msg     NVARCHAR(1000)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE cnt BIGINT;
    DECLARE blk NVARCHAR(1);
    DECLARE act NVARCHAR(1);
    DECLARE stage NVARCHAR(4);
    DECLARE maxDtl INT;
    DECLARE title NVARCHAR(200);
    DECLARE nDone INT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    maxDtl := TO_INTEGER(IFNULL("MTC_CA_F_PARAM"('CHECK_DTL_MAX', :fc), '200'));
    SELECT IFNULL(MAX("IsBlock"), 'N'), IFNULL(MAX("Active"), 'Y'), IFNULL(MAX("Stage"), 'PRE'), IFNULL(MAX("Title"), '')
      INTO blk, act, stage, title FROM "MTC_CA_C_CHECK" WHERE "CheckId" = :CheckId;
    -- 计算后校验（POST）不通过一律阻断，没有警告（用户 2026-10-14）；
    -- 例外：参数 POST_WARN_IDS 中的检查按 C_CHECK.IsBlock（POST-15 PUR 逐单据勾稽先只警告，用户 2026-10-30）
    IF :stage = 'POST' AND LOCATE(IFNULL("MTC_CA_F_PARAM"('POST_WARN_IDS', :fc), ',POST-15,'), ',' || :CheckId || ',') = 0 THEN blk := 'Y'; END IF;
    SELECT COUNT(*) INTO cnt FROM :dtl;

    INSERT INTO "MTC_CA_R_CHECK" ("FcCode", "RunType", "Scenario", "RunId", "CheckId", "Stage", "Result", "IssueCnt", "IsBlock", "Msg", "CheckTime")
    VALUES (:fc, :rt, :scen, :RunId, :CheckId, :stage,
            CASE WHEN :act = 'N' THEN 'SKIP' WHEN :cnt = 0 THEN 'PASS' WHEN :blk = 'Y' THEN 'FAIL' ELSE 'WARN' END,
            :cnt, :blk, :Msg, CURRENT_TIMESTAMP);

    IF :act = 'Y' AND :cnt > 0 THEN
        INSERT INTO "MTC_CA_R_CHECK_DTL" ("FcCode", "RunType", "Scenario", "RunId", "CheckId", "SeqNo", "KeyCode", "Info")
        SELECT :fc, :rt, :scen, :RunId, :CheckId, "SeqNo", LEFT("KeyCode", 200), LEFT("Info", 1000)
          FROM (SELECT ROW_NUMBER() OVER (ORDER BY "KeyCode", "Info") AS "SeqNo", "KeyCode", "Info" FROM :dtl)
         WHERE "SeqNo" <= :maxDtl;
    END IF;

    -- 执行台进度：已完成几项、刚完成哪一项（不含明细）
    SELECT COUNT(*) INTO nDone FROM "MTC_CA_R_CHECK" WHERE "RunId" = :RunId AND "Stage" = :stage;
    CALL "MTC_CA_P_LOG_NOTE"(:RunId, '已完成 ' || :nDone || ' 项校验，刚完成 ' || :CheckId || ' ' || :title || '：'
         || CASE WHEN :act = 'N' THEN '跳过' WHEN :cnt = 0 THEN '通过' ELSE :cnt || ' 条问题' END);
END
@@
-- 校验明细的单号：单据类型 + DocEntry → “类型-DocNum 单号”（SAP 里按 DocNum 查，用户 2026-10-29）；查不到单号时仍写“类型-DocEntry n”
-- P10、P60、P75 共用，放在 08 是因为它最先部署
CREATE OR REPLACE FUNCTION "MTC_CA_F_DOCKEY" (IN ObjType NVARCHAR(20), IN DocEntry INTEGER)
RETURNS KeyText NVARCHAR(100)
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE num INTEGER;
    SELECT MAX("DocNum") INTO num FROM (
        SELECT "DocNum" FROM "OINV" WHERE :ObjType = '13' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "ORIN" WHERE :ObjType = '14' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "ODLN" WHERE :ObjType = '15' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "ORDN" WHERE :ObjType = '16' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "OPCH" WHERE :ObjType = '18' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "ORPC" WHERE :ObjType = '19' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "OPDN" WHERE :ObjType = '20' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "ORPD" WHERE :ObjType = '21' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "OIGN" WHERE :ObjType = '59' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "OIGE" WHERE :ObjType = '60' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "OWTR" WHERE :ObjType = '67' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "OWOR" WHERE :ObjType = '202' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "@MTC_OWOR" WHERE :ObjType = 'MTC_OWOR' AND "DocEntry" = :DocEntry UNION ALL
        SELECT "DocNum" FROM "@MTC_OMRV" WHERE :ObjType = 'MTC_OMRV' AND "DocEntry" = :DocEntry);
    KeyText := IFNULL(:ObjType, '') || CASE WHEN :num IS NULL THEN '-DocEntry ' || IFNULL(TO_NVARCHAR(:DocEntry), '')
                                            ELSE '-DocNum ' || TO_NVARCHAR(:num) END;
END
@@
-- 发出商品（P71 和 PRE-27 共用；放在这里是因为 08 比 16 先部署）
-- 截至某日（含）已交货未开票的交货 / 独立退货行（口径同 CO6103），P71 用它取期末和期初（上期末）两份（用户 2026-10-15 对账列示期初 / 本期 / 期末）
CREATE OR REPLACE FUNCTION "MTC_CA_F_GOODS_OPEN" (IN d DATE)
RETURNS TABLE ("ObjType" NVARCHAR(20), "DocEntry" INTEGER, "LineNum" INTEGER, "DocDate" DATE, "CardCode" NVARCHAR(50),
               "CustType" NVARCHAR(20), "IsSample" NVARCHAR(1), "ItemCode" NVARCHAR(50),
               "DocQty" DECIMAL(19,6), "InvQty" DECIMAL(19,6), "RetQty" DECIMAL(19,6), "OpenQty" DECIMAL(19,6))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE smpSt NVARCHAR(500);
    -- 样品销售的销售订单类型（@MTC_SALORDTYPE.U_BusiType，参数 SAMPLE_SALTYPES，2026-10-27）；账期取 d 所在月
    smpSt := IFNULL("MTC_CA_F_PARAM"('SAMPLE_SALTYPES', TO_NVARCHAR(:d, 'YYYY-MM')), ',样品销售,');
    salType = SELECT "Name", MAX("U_CustType") AS "CustType", MAX("U_BusiType") AS "BusiType"
                FROM "@MTC_SALORDTYPE" GROUP BY "Name";

    -- 截至 d 已取消的原单、截至 d 有效的后续单据（同 CO6103）
    cxl = SELECT DISTINCT D."BaseType" AS "ObjType", D."BaseEntry" AS "DocEntry"
            FROM "ODLN" M JOIN "DLN1" D ON M."DocEntry" = D."DocEntry" WHERE M."CANCELED" = 'C' AND M."DocDate" <= :d AND D."BaseType" = 15
          UNION
          SELECT DISTINCT D."BaseType", D."BaseEntry" FROM "ORDN" M JOIN "RDN1" D ON M."DocEntry" = D."DocEntry" WHERE M."CANCELED" = 'C' AND M."DocDate" <= :d AND D."BaseType" = 16
          UNION
          SELECT DISTINCT D."BaseType", D."BaseEntry" FROM "OINV" M JOIN "INV1" D ON M."DocEntry" = D."DocEntry" WHERE M."CANCELED" = 'C' AND M."DocDate" <= :d AND D."BaseType" = 13
          UNION
          SELECT DISTINCT D."BaseType", D."BaseEntry" FROM "ORIN" M JOIN "RIN1" D ON M."DocEntry" = D."DocEntry" WHERE M."CANCELED" = 'C' AND M."DocDate" <= :d AND D."BaseType" = 14;
    nxt = SELECT D."BaseType", D."BaseEntry", D."BaseLine", SUM(D."Quantity") AS "Qty", 'INV' AS "K"
            FROM "OINV" M JOIN "INV1" D ON M."DocEntry" = D."DocEntry"
           WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d AND D."BaseType" = 15
             AND NOT EXISTS (SELECT 1 FROM :cxl X WHERE X."ObjType" = 13 AND X."DocEntry" = M."DocEntry")
           GROUP BY D."BaseType", D."BaseEntry", D."BaseLine"
          UNION ALL
          SELECT D."BaseType", D."BaseEntry", D."BaseLine", SUM(D."Quantity"), 'INV'
            FROM "ORIN" M JOIN "RIN1" D ON M."DocEntry" = D."DocEntry"
           WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d AND D."BaseType" = 16
             AND NOT EXISTS (SELECT 1 FROM :cxl X WHERE X."ObjType" = 14 AND X."DocEntry" = M."DocEntry")
           GROUP BY D."BaseType", D."BaseEntry", D."BaseLine"
          UNION ALL
          SELECT D."BaseType", D."BaseEntry", D."BaseLine", SUM(D."Quantity"), 'RET'
            FROM "ORDN" M JOIN "RDN1" D ON M."DocEntry" = D."DocEntry"
           WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d AND D."BaseType" = 15
             AND NOT EXISTS (SELECT 1 FROM :cxl X WHERE X."ObjType" = 16 AND X."DocEntry" = M."DocEntry")
           GROUP BY D."BaseType", D."BaseEntry", D."BaseLine";
    src = SELECT '15' AS "ObjType", M."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate", M."CardCode", M."U_SalOrdType",
                 D."ItemCode", 1 AS "Sign", D."Quantity"
            FROM "ODLN" M JOIN "DLN1" D ON M."DocEntry" = D."DocEntry"
           WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d
             AND NOT EXISTS (SELECT 1 FROM :cxl X WHERE X."ObjType" = 15 AND X."DocEntry" = M."DocEntry")
          UNION ALL
          SELECT '16', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), M."CardCode", M."U_SalOrdType",
                 D."ItemCode", -1, D."Quantity"
            FROM "ORDN" M JOIN "RDN1" D ON M."DocEntry" = D."DocEntry"
           WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d AND IFNULL(D."BaseType", -1) <> 15
             AND NOT EXISTS (SELECT 1 FROM :cxl X WHERE X."ObjType" = 16 AND X."DocEntry" = M."DocEntry");

    RETURN
    SELECT S."ObjType", S."DocEntry", S."LineNum", S."DocDate", S."CardCode",
           T."CustType", CASE WHEN LOCATE(:smpSt, ',' || T."BusiType" || ',') > 0 THEN 'Y' ELSE 'N' END AS "IsSample", S."ItemCode",
           S."Sign" * S."Quantity" AS "DocQty", IFNULL(N1."Qty", 0) AS "InvQty", IFNULL(N2."Qty", 0) AS "RetQty",
           S."Sign" * (S."Quantity" - IFNULL(N1."Qty", 0) - IFNULL(N2."Qty", 0)) AS "OpenQty"
      FROM :src S
      JOIN "OITM" I ON I."ItemCode" = S."ItemCode" AND I."InvntItem" = 'Y'
      LEFT JOIN :salType T ON T."Name" = S."U_SalOrdType"
      LEFT JOIN :nxt N1 ON N1."K" = 'INV' AND TO_NVARCHAR(N1."BaseType") = S."ObjType" AND N1."BaseEntry" = S."DocEntry" AND N1."BaseLine" = S."LineNum"
      LEFT JOIN :nxt N2 ON N2."K" = 'RET' AND TO_NVARCHAR(N2."BaseType") = S."ObjType" AND N2."BaseEntry" = S."DocEntry" AND N2."BaseLine" = S."LineNum"
     WHERE ABS(S."Quantity" - IFNULL(N1."Qty", 0) - IFNULL(N2."Qty", 0)) > 0.000001;
END
@@
-- 截至某日（含）交货 / 独立退货行的后续消耗：开票（INV 应收发票、RIN 应收贷项）、基于交货的退货（RET），取消单数量反号、经原单找到交货 / 退货行。
-- Qty 与原行 DocQty 同号（交货的开票、退货为正，独立退货的贷项为负），所以 原行未清数量 = DocQty − SUM(Qty)，与 F_GOODS_OPEN 一致。
-- P71 用它算 DN03 转出金额、尾差和发出商品余额（用户 2026-10-15：分次开票的尾差在全部消耗完时清掉）
CREATE OR REPLACE FUNCTION "MTC_CA_F_GOODS_MOVE" (IN d DATE)
RETURNS TABLE ("SrcObj" NVARCHAR(20), "SrcEntry" INTEGER, "SrcLine" INTEGER, "K" NVARCHAR(10), "DocEntry" INTEGER, "LineNum" INTEGER,
               "DocDate" DATE, "U_SalOrdType" NVARCHAR(100), "Qty" DECIMAL(19,6))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    RETURN
    SELECT TO_NVARCHAR(CASE WHEN D."BaseType" = 13 THEN O."BaseType" ELSE D."BaseType" END) AS "SrcObj",
           CASE WHEN D."BaseType" = 13 THEN O."BaseEntry" ELSE D."BaseEntry" END AS "SrcEntry",
           CASE WHEN D."BaseType" = 13 THEN O."BaseLine" ELSE D."BaseLine" END AS "SrcLine",
           CAST('INV' AS NVARCHAR(10)) AS "K", M."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate",
           CAST(M."U_SalOrdType" AS NVARCHAR(100)) AS "U_SalOrdType",
           CAST(CASE WHEN M."CANCELED" = 'C' THEN -1 ELSE 1 END * D."Quantity" AS DECIMAL(19,6)) AS "Qty"
      FROM "OINV" M JOIN "INV1" D ON M."DocEntry" = D."DocEntry"
      JOIN "OITM" I ON I."ItemCode" = D."ItemCode" AND I."InvntItem" = 'Y'
      LEFT JOIN "INV1" O ON D."BaseType" = 13 AND O."DocEntry" = D."BaseEntry" AND O."LineNum" = D."BaseLine"
     WHERE M."DocDate" <= :d AND (D."BaseType" = 15 OR (D."BaseType" = 13 AND O."BaseType" = 15))
    UNION ALL
    SELECT TO_NVARCHAR(CASE WHEN D."BaseType" = 14 THEN O."BaseType" ELSE D."BaseType" END),
           CASE WHEN D."BaseType" = 14 THEN O."BaseEntry" ELSE D."BaseEntry" END,
           CASE WHEN D."BaseType" = 14 THEN O."BaseLine" ELSE D."BaseLine" END,
           'RIN', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), M."U_SalOrdType",
           CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END * D."Quantity"
      FROM "ORIN" M JOIN "RIN1" D ON M."DocEntry" = D."DocEntry"
      JOIN "OITM" I ON I."ItemCode" = D."ItemCode" AND I."InvntItem" = 'Y'
      LEFT JOIN "RIN1" O ON D."BaseType" = 14 AND O."DocEntry" = D."BaseEntry" AND O."LineNum" = D."BaseLine"
     WHERE M."DocDate" <= :d AND (D."BaseType" = 16 OR (D."BaseType" = 14 AND O."BaseType" = 16))
    UNION ALL
    SELECT TO_NVARCHAR(CASE WHEN D."BaseType" = 16 THEN O."BaseType" ELSE D."BaseType" END),
           CASE WHEN D."BaseType" = 16 THEN O."BaseEntry" ELSE D."BaseEntry" END,
           CASE WHEN D."BaseType" = 16 THEN O."BaseLine" ELSE D."BaseLine" END,
           'RET', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), M."U_SalOrdType",
           CASE WHEN M."CANCELED" = 'C' THEN -1 ELSE 1 END * D."Quantity"
      FROM "ORDN" M JOIN "RDN1" D ON M."DocEntry" = D."DocEntry"
      JOIN "OITM" I ON I."ItemCode" = D."ItemCode" AND I."InvntItem" = 'Y'
      LEFT JOIN "RDN1" O ON D."BaseType" = 16 AND O."DocEntry" = D."BaseEntry" AND O."LineNum" = D."BaseLine"
     WHERE M."DocDate" <= :d AND (D."BaseType" = 15 OR (D."BaseType" = 16 AND O."BaseType" = 15));
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P10_PRECHECK" (IN RunId BIGINT, OUT BlockCnt INT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE stat NVARCHAR(1);
    DECLARE n BIGINT;
    DECLARE feeItem NVARCHAR(50);
    DECLARE bt25 NVARCHAR(500);
    DECLARE convIn NVARCHAR(20); DECLARE convOut NVARCHAR(20);
    DECLARE wwWt NVARCHAR(200); DECLARE trialWt NVARCHAR(200); DECLARE trialBt NVARCHAR(500);
    DECLARE custDom NVARCHAR(50); DECLARE custExp NVARCHAR(50);
    DECLARE exWhs08 NVARCHAR(5000);
    DECLARE pricedIn NVARCHAR(200);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    -- 业务口径参数（MTC_CA_C_PARAM，2026-10-27 从代码中的固定值改为参数）
    convIn := IFNULL("MTC_CA_F_PARAM"('CONV_IN_BUSITYPE', :fc), '204');
    convOut := IFNULL("MTC_CA_F_PARAM"('CONV_OUT_BUSITYPE', :fc), '205');
    wwWt := IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', :fc), ',50,');
    trialWt := IFNULL("MTC_CA_F_PARAM"('TRIAL_WORTYPES', :fc), ',40,');
    trialBt := IFNULL("MTC_CA_F_PARAM"('TRIAL_ISSUE_BUSITYPES', :fc), ',307,305,');
    custDom := IFNULL("MTC_CA_F_PARAM"('CUST_DOM', :fc), '国内客户');
    custExp := IFNULL("MTC_CA_F_PARAM"('CUST_EXP', :fc), '国外客户');
    exWhs08 := IFNULL("MTC_CA_F_PARAM"('PRE08_EXCL_WHS', :fc), ',');
    pricedIn := IFNULL("MTC_CA_F_PARAM"('QCP_PRICED_IN', :fc), ',I01,I03,I05,I07,I08,I09,I90,');

    -- PRE-01 账期未锁定（正式运行在 P00 已拦截；模拟运行允许算锁定账期）
    SELECT MAX("PeriodStat") INTO stat FROM "OFPR" WHERE "Code" = :fc;
    t01 = SELECT :fc AS "KeyCode", '账期已锁定' AS "Info" FROM DUMMY WHERE :rt = 'F' AND :stat = 'Y';
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-01', :t01, NULL);

    -- PRE-02 本期有变动的物料、有出入库订单的产品都有层级，且不是 -1
    t02 = SELECT L."ItemCode" AS "KeyCode",
                 CASE WHEN I."ItemCode" IS NULL THEN '物料不在物料主数据' ELSE '层级为 -1：' || IFNULL(I."LevelNote", '') END AS "Info"
            FROM (SELECT DISTINCT "ItemCode" FROM "MTC_CA_S_LINE" WHERE "RunId" = :RunId
                  UNION   -- 本期有领料或入库的订单的产品：层级决定订单在第几层结转
                  SELECT DISTINCT O."ItemCode" FROM "MTC_CA_S_ORDER" O
                   WHERE O."RunId" = :RunId AND O."ItemCode" IS NOT NULL
                     AND EXISTS (SELECT 1 FROM "MTC_CA_S_LINE" X WHERE X."RunId" = :RunId
                                    AND X."OrderType" = O."OrderType" AND X."OrderEntry" = O."OrderEntry")) L
            LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = :RunId AND I."ItemCode" = L."ItemCode"
           WHERE IFNULL(I."iLevel", -1) = -1;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-02', :t02, NULL);

    -- PRE-03 形态转换同月一对一（同修正稿 CAL_1001_CHECK 第 15 项：每个配对键正好一行转出 CONV_OUT_BUSITYPE、一行转入 CONV_IN_BUSITYPE）
    t03 = SELECT "ObjType" || '-DocNum ' || "DocNum" || '-LineNum ' || "LineNum" AS "KeyCode",
                 '业务类型 ' || "BusiType" || ' 的行缺少配对键（U_BaseType / U_BaseEntry / U_BaseLineGrpNum）' AS "Info"
            FROM "MTC_CA_S_LINE"
           WHERE "RunId" = :RunId AND "BusiType" IN (:convIn, :convOut) AND "Canceled" = 'N' AND "PairKey" IS NULL
          UNION ALL
          SELECT "PairKey", '本月转入 ' || SUM(CASE WHEN "BusiType" = :convIn THEN 1 ELSE 0 END)
                            || ' 行、转出 ' || SUM(CASE WHEN "BusiType" = :convOut THEN 1 ELSE 0 END) || ' 行（应各 1 行）'
            FROM "MTC_CA_S_LINE"
           WHERE "RunId" = :RunId AND "BusiType" IN (:convIn, :convOut) AND "Canceled" = 'N' AND "PairKey" IS NOT NULL
           GROUP BY "PairKey"
          HAVING SUM(CASE WHEN "BusiType" = :convIn THEN 1 ELSE 0 END) <> 1
              OR SUM(CASE WHEN "BusiType" = :convOut THEN 1 ELSE 0 END) <> 1;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-03', :t03, NULL);

    -- PRE-04 没有原交货的销售退货：允许发生，只警告（用户 2026-10-13）；有期初维护价按维护价，没有按本期加权价（清单 S10）
    -- 原交货键在 P20_LINE 中确定：RDN1 标准来源是交货时用标准来源，否则用行上 U_BaseType='15' / U_BaseEntry / U_BaseLine
    -- 物料没有维护价、也没有其他价格来源（与 PRE-23 同一口径：期初有数量有金额、本期有 QCP_PRICED_IN 入库或带金额的入库）时，
    -- 加权价为 0，退货会按 0 成本入库，说明里写明（用户 2026-10-29）
    s04 = SELECT DISTINCT "ItemCode" FROM "MTC_CA_S_LINE"
           WHERE "RunId" = :RunId AND "Qty" > 0 AND IFNULL("NoCost", 'N') = 'N'
             AND (("SrcAmt" IS NOT NULL AND "SrcAmt" <> 0) OR LOCATE(:pricedIn, ',' || IFNULL("TransCode", '') || ',') > 0)
          UNION SELECT "ItemCode" FROM "MTC_CA_S_OPEN" WHERE "RunId" = :RunId AND "Qty" > 0 AND "Amount" <> 0;
    t04 = SELECT L."ObjType" || '-DocNum ' || L."DocNum" || '-LineNum ' || L."LineNum" AS "KeyCode",
                 L."ItemCode" || ' 退货没有原交货，' || CASE WHEN Q."ItemCode" IS NOT NULL THEN '按期初维护价'
                                                                 WHEN P."ItemCode" IS NOT NULL THEN '也没有期初维护价，按本期加权价'
                                                                 ELSE '也没有期初维护价和其他价格来源，将按 0 成本入库，请在期初成本价维护中填价' END AS "Info"
            FROM "MTC_CA_S_LINE" L
            LEFT JOIN "MTC_CA_S_QCPRICE" Q ON Q."RunId" = :RunId AND Q."ItemCode" = L."ItemCode"
            LEFT JOIN :s04 P ON P."ItemCode" = L."ItemCode"
           WHERE L."RunId" = :RunId AND L."TransCode" = 'O06' AND IFNULL(L."Canceled", 'N') <> 'C'
             AND NOT (L."BaseType" = '15' AND L."BaseEntry" IS NOT NULL);
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-04', :t04, NULL);

    -- PRE-05 计价仓库的每条库存变动都能识别交易类型（旧流程静默丢弃，#13）
    -- 数量和金额都为 0 的 OIVL 行（如基于交货的应收发票 13）不影响库存，不报；数量为 0 但有金额的仍报出
    t05 = SELECT "ObjType" || '-DocNum ' || "DocNum" || '-LineNum ' || IFNULL(TO_NVARCHAR("LineNum"), '') AS "KeyCode",
                 '单据类型 ' || "ObjType" || CASE WHEN "BusiType" IS NOT NULL THEN '，业务类型 ' || "BusiType" ELSE '' END
                 || ' 识别不了交易类型；物料 ' || "ItemCode"
                 || CASE WHEN "Qty" = 0 THEN '（数量为 0，但 OIVL 金额不为 0）' ELSE '' END AS "Info"
            FROM "MTC_CA_S_LINE"
           WHERE "RunId" = :RunId AND "Src" = 'OIVL' AND "TransCode" IS NULL
             AND NOT ("Qty" = 0 AND IFNULL("B1Amt", 0) = 0);
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-05', :t05, NULL);

    -- PRE-06 订单领料 / 入库行能找到订单（只看工单交易 I03/O03/I07/O07/I08/O08/I09/O09，与 P20_LINE 关联订单的口径一致，用户 2026-10-14）
    t06 = SELECT L."ObjType" || '-DocNum ' || L."DocNum" || '-LineNum ' || IFNULL(TO_NVARCHAR(L."LineNum"), '') AS "KeyCode",
                 CASE WHEN L."OrderEntry" IS NULL THEN '交易类型 ' || IFNULL(L."TransCode", '') || '（业务类型 ' || IFNULL(L."BusiType", '') || '）是订单领料 / 入库，但没有关联订单'
                      ELSE '关联的订单 ' || L."OrderType" || '-DocEntry ' || L."OrderEntry" || ' 不存在' END AS "Info"
            FROM "MTC_CA_S_LINE" L
            LEFT JOIN "MTC_CA_S_ORDER" O ON O."RunId" = :RunId AND O."OrderType" = L."OrderType" AND O."OrderEntry" = L."OrderEntry"
           WHERE L."RunId" = :RunId AND L."TransCode" IN ('I03', 'O03', 'I07', 'O07', 'I08', 'O08', 'I09', 'O09') AND O."OrderEntry" IS NULL;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-06', :t06, NULL);

    -- PRE-07 库存转储一端是计价仓库、另一端不是：不允许（Q7）
    t07 = SELECT '67' || '-DocNum ' || T0."DocNum" || '-LineNum ' || T1."LineNum" AS "KeyCode",
                 T1."ItemCode" || ' 从 ' || T1."FromWhsCod" || CASE WHEN A."IsCost" = 'Y' THEN '（计价）' ELSE '（不计价）' END
                 || ' 转到 ' || T1."WhsCode" || CASE WHEN B."IsCost" = 'Y' THEN '（计价）' ELSE '（不计价）' END AS "Info"
            FROM "OWTR" T0
            JOIN "WTR1" T1 ON T1."DocEntry" = T0."DocEntry"
            JOIN "MTC_CA_V_WHS" A ON A."WhsCode" = T1."FromWhsCod"
            JOIN "MTC_CA_V_WHS" B ON B."WhsCode" = T1."WhsCode"
           WHERE T0."DocDate" BETWEEN :d0 AND :d1 AND A."IsCost" <> B."IsCost";
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-07', :t07, NULL);

    -- PRE-08 不计价仓库中有采购、订单领料或完工（这些行不计成本，提示核对仓库设置）
    --   参数 PRE08_EXCL_WHS 列出的仓库不报（用户 2026-10-29：警告太多）
    t08 = SELECT TO_NVARCHAR(P0."TransType") || '-DocNum ' || TO_NVARCHAR(P0."BASE_REF") || '-LineNum ' || TO_NVARCHAR(P0."DocLineNum") AS "KeyCode",
                 '仓库 ' || P0."LocCode" || ' 不计价，交易类型 ' || V."TransCode" || '，物料 ' || P0."ItemCode" AS "Info"
            FROM "OIVL" P0
            JOIN "MTC_CA_V_WHS" W ON W."WhsCode" = P0."LocCode" AND W."IsCost" = 'N'
            JOIN "MTC_VIEW_Document" V ON TO_NVARCHAR(V."ObjType") = TO_NVARCHAR(P0."TransType")
                                      AND TO_NVARCHAR(V."DocEntry") = TO_NVARCHAR(P0."CreatedBy")
                                      AND TO_NVARCHAR(V."LineNum") = TO_NVARCHAR(P0."DocLineNum")
           WHERE P0."DocDate" BETWEEN :d0 AND :d1 AND P0."TransType" <> 67
             AND V."TransCode" IN ('I01', 'I06', 'I03', 'I07', 'I08', 'I09', 'I90', 'O03', 'O07', 'O08', 'O09', 'O90')
             AND LOCATE(:exWhs08, ',' || P0."LocCode" || ',') = 0;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-08', :t08, NULL);

    -- PRE-09 试打订单（TRIAL_WORTYPES，默认 40）只能用 TRIAL_ISSUE_BUSITYPES（默认 307 试打领用、305 生产报废）领料（旧检查第 4 项）
    t09 = SELECT L."ObjType" || '-DocNum ' || L."DocNum" || '-LineNum ' || IFNULL(TO_NVARCHAR(L."LineNum"), '') AS "KeyCode",
                 '试打订单 ' || O."OrderNum" || ' 的领料业务类型是 ' || IFNULL(L."BusiType", '空') AS "Info"
            FROM "MTC_CA_S_LINE" L
            JOIN "MTC_CA_S_ORDER" O ON O."RunId" = :RunId AND O."OrderType" = L."OrderType" AND O."OrderEntry" = L."OrderEntry"
           WHERE L."RunId" = :RunId AND LOCATE(:trialWt, ',' || O."WorType" || ',') > 0 AND L."BusiClass" = 'B03'
             AND LOCATE(:trialBt, ',' || IFNULL(L."BusiType", '') || ',') = 0;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-09', :t09, NULL);

    -- PRE-10 期初前已关闭或已取消的订单本期仍有出入库 / 加工费（旧检查第 13、14 项）
    --   只有工单交易 I03/O03/I07/O07/I08/O08/I09/O09 会关联订单（P20_LINE），其他交易填了订单号也不报（用户 2026-10-14）
    t10 = SELECT O."OrderType" || '-DocNum ' || O."OrderNum" AS "KeyCode",
                 '订单状态 ' || IFNULL(O."B1Status", '') || '，关单日期 ' || IFNULL(TO_NVARCHAR(O."CloseDate"), '空') || '，本期仍有单据引用' AS "Info"
            FROM "MTC_CA_S_ORDER" O
           WHERE O."RunId" = :RunId AND O."InScope" = 'N';
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-10', :t10, NULL);

    -- PRE-11 订单状态为关闭但没有关单日期：无法判断在哪一期结转关单差异
    t11 = SELECT O."OrderType" || '-DocNum ' || O."OrderNum" AS "KeyCode", '状态为关闭，但关单日期为空' AS "Info"
            FROM "MTC_CA_S_ORDER" O
           WHERE O."RunId" = :RunId AND O."B1Status" = 'L' AND O."CloseDate" IS NULL;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-11', :t11, NULL);

    -- PRE-12 委外加工费找不到订单（这笔金额不进任何订单；只警告，用户 2026-10-13）；SrcKey = DocEntry-LineNum（ProWW 为 @MTC_OMRV DocEntry-LineId）
    --   报出时显示 DocNum（SAP 里按它查，用户 2026-10-29）：PDN → 20 OPDN，RPD → 21 ORPD，PROWW → @MTC_OMRV；查不到单号时仍显示 DocEntry
    --   第二段（用户 2026-11-04）：S_AP_MOVE 里本期计提的加工费行，却不在 S_SUBFEE（收货行没填 U_BaseType = '59' 等）：PUR4 记了 140802，订单没有这笔
    t12 = SELECT CASE F."Src" WHEN 'PDN' THEN '20' WHEN 'RPD' THEN '21' WHEN 'PROWW' THEN 'MTC_OMRV' ELSE F."Src" END
                 || IFNULL('-DocNum ' || TO_NVARCHAR(COALESCE(P."DocNum", R."DocNum", M."DocNum")), '-DocEntry ' || SUBSTR_BEFORE(F."SrcKey", '-'))
                 || CASE WHEN F."Src" = 'PROWW' THEN '-LineId ' ELSE '-LineNum ' END || SUBSTR_AFTER(F."SrcKey", '-') AS "KeyCode",
                 IFNULL(F."MatchNote", '') || '；加工费物料 ' || IFNULL(F."ItemCode", '') AS "Info"
            FROM "MTC_CA_S_SUBFEE" F
            LEFT JOIN "OPDN" P ON F."Src" = 'PDN' AND TO_NVARCHAR(P."DocEntry") = SUBSTR_BEFORE(F."SrcKey", '-')
            LEFT JOIN "ORPD" R ON F."Src" = 'RPD' AND TO_NVARCHAR(R."DocEntry") = SUBSTR_BEFORE(F."SrcKey", '-')
            LEFT JOIN "@MTC_OMRV" M ON F."Src" = 'PROWW' AND TO_NVARCHAR(M."DocEntry") = SUBSTR_BEFORE(F."SrcKey", '-')
           WHERE F."RunId" = :RunId AND F."OrderEntry" IS NULL
          UNION ALL
          SELECT A."ObjType" || IFNULL('-DocNum ' || TO_NVARCHAR(COALESCE(P."DocNum", R."DocNum")), '-DocEntry ' || TO_NVARCHAR(A."DocEntry"))
                 || '-LineNum ' || TO_NVARCHAR(A."LineNum"),
                 '已按加工费计提暂估，但收货 / 退货行没有指向生产收货（U_BaseType 不是 59）；加工费物料 ' || IFNULL(A."ItemCode", '')
            FROM (SELECT DISTINCT "ObjType", "DocEntry", "LineNum", "ItemCode"
                    FROM "MTC_CA_S_AP_MOVE"
                   WHERE "RunId" = :RunId AND "AccrType" = 'SUBFEE' AND "MoveType" IN ('ACCR', 'RET')
                     AND "ObjType" IN ('20', '21') AND "DocDate" BETWEEN :d0 AND :d1) A
            LEFT JOIN "OPDN" P ON A."ObjType" = '20' AND P."DocEntry" = A."DocEntry"
            LEFT JOIN "ORPD" R ON A."ObjType" = '21' AND R."DocEntry" = A."DocEntry"
           WHERE NOT EXISTS (SELECT 1 FROM "MTC_CA_S_SUBFEE" F
                              WHERE F."RunId" = :RunId AND F."Src" = CASE WHEN A."ObjType" = '20' THEN 'PDN' ELSE 'RPD' END
                                AND F."SrcKey" = A."DocEntry" || '-' || A."LineNum");
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-12', :t12, NULL);

    -- PRE-13 同一账期同一产品有多个不同的单位工时（Q21 阻断；用户说明正常不会出现）
    t13 = SELECT "ItemCode" AS "KeyCode", '工时单中有 ' || "LineCnt" || ' 行，最小 ' || TO_NVARCHAR("MinHours") || '，最大 ' || TO_NVARCHAR("Hours") AS "Info"
            FROM "MTC_CA_S_HOURS"
           WHERE "RunId" = :RunId AND "LineCnt" > 1 AND "MinHours" <> "Hours";
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-13', :t13, NULL);

    -- PRE-14 本期有入库、应分摊费用的订单，产品没有工时（Q11）
    t14 = SELECT O."OrderType" || '-DocNum ' || O."OrderNum" AS "KeyCode",
                 '产品 ' || O."ItemCode" || '（费用池 ' || T."PoolCode" || '）本期有入库，但没有工时' AS "Info"
            FROM "MTC_CA_S_ORDER" O
            JOIN "MTC_CA_V_ITEM_POOL" T ON T."RunId" = :RunId AND T."ItemCode" = O."ItemCode"
                                       AND LOCATE(T."WorTypes", ',' || O."WorType" || ',') > 0
            LEFT JOIN "MTC_CA_S_HOURS" H ON H."RunId" = :RunId AND H."ItemCode" = O."ItemCode"
           WHERE O."RunId" = :RunId AND O."RecvQty" > 0 AND IFNULL(H."Hours", 0) = 0;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-14', :t14, NULL);

    -- PRE-15 制造费用凭证来自其他出入库 / 盘点单，而该单据行又作为公摊材料计入费用池（可能重复计入）
    t15 = SELECT DISTINCT "MTC_CA_F_DOCKEY"(E."SrcObj", E."SrcDoc") AS "KeyCode",
                 '凭证 ' || SUBSTR_BEFORE(E."SrcKey", '-') || '（代码 ' || IFNULL(NULLIF(E."SrcTrans", ''), '空') || '）记 ' || E."AcctCode"
                 || '，来源单据同时有公摊材料行' AS "Info"
            FROM "MTC_CA_S_EXP" E
            JOIN "MTC_CA_S_LINE" L ON L."RunId" = :RunId AND L."SharedExp" = 'Y' AND L."ObjType" = E."SrcObj" AND L."DocEntry" = E."SrcDoc"
           WHERE E."RunId" = :RunId AND E."Src" = 'JDT' AND E."SrcObj" IN ('59', '60');
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-15', :t15, NULL);

    -- PRE-16 有期初（上期承接或上期新框架结果）
    SELECT COUNT(*) INTO n FROM "MTC_CA_S_OPEN" WHERE "RunId" = :RunId;
    t16 = SELECT :fc AS "KeyCode", '没有取到期初：上期既不是承接账期（需先运行 MTC_CA_P_BOOTSTRAP），也没有上期新框架结果' AS "Info"
            FROM DUMMY WHERE :n = 0;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-16', :t16, NULL);

    -- PRE-17 本期有入库的生产订单，产品不在任何费用池的分摊范围（按物料组或 U_ItemGrpType 匹配，见 MTC_CA_V_ITEM_POOL）
    t17 = SELECT O."OrderType" || '-DocNum ' || O."OrderNum" AS "KeyCode",
                 '产品 ' || O."ItemCode" || '（物料组 ' || IFNULL(I."ItmsGrpCod", '空') || '，车间类别 ' || IFNULL(I."GrpType", '空')
                 || '）不在 MTC_CA_C_POOL_TGT 的范围内，分不到制造费用和人工' AS "Info"
            FROM "MTC_CA_S_ORDER" O
            LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = :RunId AND I."ItemCode" = O."ItemCode"
           WHERE O."RunId" = :RunId AND O."RecvQty" > 0 AND LOCATE(:wwWt, ',' || O."WorType" || ',') = 0
             AND NOT EXISTS (SELECT 1 FROM "MTC_CA_V_ITEM_POOL" T
                              WHERE T."RunId" = :RunId AND T."ItemCode" = O."ItemCode"
                                AND LOCATE(T."WorTypes", ',' || O."WorType" || ',') > 0);
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-17', :t17, NULL);

    -- PRE-18 费用池配置有效：正好一个默认池；关单差异池、成本中心映射、分摊范围引用的池都存在；
    --        同一产品本期只属于一个池（Q22；按物料组和按 U_ItemGrpType 的配置混用时也能查出）
    t18 = SELECT 'C_POOL' AS "KeyCode", '默认池应正好 1 个，实际 ' || COUNT(*) || ' 个' AS "Info"
            FROM "MTC_CA_C_POOL" WHERE "IsDefault" = 'Y'
          HAVING COUNT(*) <> 1
          UNION ALL
          SELECT 'CLOSE_DIF_POOL', '关单差异池 ' || IFNULL(P."V", '空') || ' 不在 MTC_CA_C_POOL 中'
            FROM (SELECT "MTC_CA_F_PARAM"('CLOSE_DIF_POOL', :fc) AS "V" FROM DUMMY) P
           WHERE NOT EXISTS (SELECT 1 FROM "MTC_CA_C_POOL" C WHERE C."PoolCode" = P."V")
          UNION ALL
          SELECT 'C_POOL_SRC-' || S."OcrCode", '引用的池 ' || S."PoolCode" || ' 不存在'
            FROM "MTC_CA_C_POOL_SRC" S
           WHERE :fc BETWEEN S."FromFc" AND S."ToFc"
             AND NOT EXISTS (SELECT 1 FROM "MTC_CA_C_POOL" C WHERE C."PoolCode" = S."PoolCode")
          UNION ALL
          SELECT 'C_POOL_TGT-' || T."ItmsGrpCod", '引用的池 ' || T."PoolCode" || ' 不存在'
            FROM "MTC_CA_C_POOL_TGT" T
           WHERE :fc BETWEEN T."FromFc" AND T."ToFc"
             AND NOT EXISTS (SELECT 1 FROM "MTC_CA_C_POOL" C WHERE C."PoolCode" = T."PoolCode")
          UNION ALL
          SELECT 'C_POOL_TGT-' || T."ItmsGrpCod", 'MatchBy 只能是 GRP 或 GRPTYPE，实际 ' || IFNULL(T."MatchBy", '空')
            FROM "MTC_CA_C_POOL_TGT" T
           WHERE :fc BETWEEN T."FromFc" AND T."ToFc" AND IFNULL(T."MatchBy", '') NOT IN ('GRP', 'GRPTYPE')
          UNION ALL
          -- 同一产品匹配到多条分摊范围（即使是同一个池，权重也会重复计入）
          SELECT 'ITEM-' || V."ItemCode", '产品匹配到 ' || COUNT(*) || ' 条分摊范围：' || STRING_AGG(V."PoolCode" || '/' || V."MatchBy" || ':' || V."MatchKey", '、')
            FROM "MTC_CA_V_ITEM_POOL" V
           WHERE V."RunId" = :RunId
           GROUP BY V."ItemCode"
          HAVING COUNT(*) > 1
          UNION ALL
          -- 以下用户 2026-10-14 增加（配置改在 B1 维护）：B1 同步失败、成本中心不存在或同期多条、匹配值不存在
          SELECT 'B1 配置', "Msg" FROM "MTC_CA_RUN_STEP" WHERE "RunId" = :RunId AND "StepCode" = 'P05' AND "Status" = 'FAIL'
          UNION ALL
          SELECT 'C_POOL_SRC-' || S."OcrCode", '成本中心 ' || S."OcrCode" || ' 在 OPRC 中不存在，也没有成本中心的 U_CalType 等于它'
            FROM "MTC_CA_C_POOL_SRC" S
           WHERE :fc BETWEEN S."FromFc" AND S."ToFc" AND NOT EXISTS (SELECT 1 FROM "OPRC" P WHERE P."PrcCode" = S."OcrCode")
             -- 作为 OPRC.U_CalType 取值使用、已展开到成本中心的不报（P05）
             AND NOT EXISTS (SELECT 1 FROM "MTC_CA_C_POOL_SRC" E WHERE E."Descr" = 'OPRC.U_CalType=' || S."OcrCode")
          UNION ALL
          SELECT 'C_POOL_SRC-' || S."OcrCode", '成本中心本期匹配到 ' || COUNT(*) || ' 条配置：' || STRING_AGG(S."PoolCode" || '（' || S."FromFc" || '~' || S."ToFc" || '）', '、')
            FROM "MTC_CA_C_POOL_SRC" S
           WHERE :fc BETWEEN S."FromFc" AND S."ToFc"
           GROUP BY S."OcrCode" HAVING COUNT(*) > 1
          UNION ALL
          SELECT 'C_POOL_TGT-' || T."ItmsGrpCod",
                 CASE WHEN T."MatchBy" = 'GRP' THEN '物料组 ' ELSE '车间类别（OITB.U_ItemGrpType）' END || T."ItmsGrpCod" || ' 在 OITB 中不存在'
            FROM "MTC_CA_C_POOL_TGT" T
           WHERE :fc BETWEEN T."FromFc" AND T."ToFc"
             AND ((T."MatchBy" = 'GRP' AND NOT EXISTS (SELECT 1 FROM "OITB" B WHERE TO_NVARCHAR(B."ItmsGrpCod") = T."ItmsGrpCod"))
               OR (T."MatchBy" = 'GRPTYPE' AND NOT EXISTS (SELECT 1 FROM "OITB" B WHERE B."U_ItemGrpType" = T."ItmsGrpCod")));
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-18', :t18, NULL);

    -- PRE-19 本期净入库为负的生产订单（完工退回多于入库）：不分摊制造费用和人工（Q20）
    t19 = SELECT O."OrderType" || '-DocNum ' || O."OrderNum" AS "KeyCode",
                 '产品 ' || O."ItemCode" || ' 本期净入库 ' || TO_NVARCHAR(O."RecvQty") || '，不分摊制造费用和人工' AS "Info"
            FROM "MTC_CA_S_ORDER" O
           WHERE O."RunId" = :RunId AND O."RecvQty" < 0 AND LOCATE(:wwWt, ',' || O."WorType" || ',') = 0;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-19', :t19, NULL);

    -- PRE-20 本期应付发票 / 贷项中，库存物料或委外加工费的行不基于收货 / 退货（直接开票、基于采购订单、基于发票的调价贷项）：
    --        PUR2 / PUR3 会冲回它们的系统分录却没有对应的暂估可冲（Q24，用户说明不会出现）
    feeItem := IFNULL("MTC_CA_F_PARAM"('SUBFEE_ITEM', :fc), 'X0510001');
    t20 = SELECT '18' || '-DocNum ' || M."DocNum" || '-LineNum ' || D."LineNum" AS "KeyCode",
                 '应付发票行 ' || D."ItemCode" || ' 不基于收货 / 退货（来源类型 ' || IFNULL(TO_NVARCHAR(D."BaseType"), '无') || '）' AS "Info"
            FROM "OPCH" M JOIN "PCH1" D ON D."DocEntry" = M."DocEntry" JOIN "OITM" I ON I."ItemCode" = D."ItemCode"
           WHERE M."DocDate" BETWEEN :d0 AND :d1 AND M."CANCELED" <> 'C' AND IFNULL(D."BaseType", -1) NOT IN (20, 21)
             AND (I."InvntItem" = 'Y' OR D."ItemCode" = :feeItem)
          UNION ALL
          SELECT '19' || '-DocNum ' || M."DocNum" || '-LineNum ' || D."LineNum",
                 '应付贷项行 ' || D."ItemCode" || ' 不基于收货 / 退货（来源类型 ' || IFNULL(TO_NVARCHAR(D."BaseType"), '无') || '）'
            FROM "ORPC" M JOIN "RPC1" D ON D."DocEntry" = M."DocEntry" JOIN "OITM" I ON I."ItemCode" = D."ItemCode"
           WHERE M."DocDate" BETWEEN :d0 AND :d1 AND M."CANCELED" <> 'C' AND IFNULL(D."BaseType", -1) NOT IN (20, 21)
             AND (I."InvntItem" = 'Y' OR D."ItemCode" = :feeItem);
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-20', :t20, NULL);

    -- PRE-21 本期委外加工费发票的“发票 − 暂估”差额找不到产品（发票行 U_ItemCode 为空或不是物料），差额进不了成本
    t21 = SELECT "MTC_CA_F_DOCKEY"(A."ObjType", A."DocEntry") || '-LineNum ' || A."LineNum" AS "KeyCode",
                 '委外加工费发票差额 ' || TO_NVARCHAR(A."DocAmt" + A."AccrAmt") || '，产品物料 ' || IFNULL(A."ProdItem", '空') || ' 无效' AS "Info"
            FROM "MTC_CA_S_AP_MOVE" A
            LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = A."RunId" AND I."ItemCode" = A."ProdItem"
           WHERE A."RunId" = :RunId AND A."AccrType" = 'SUBFEE' AND A."MoveType" = 'INV'
             AND A."DocDate" BETWEEN :d0 AND :d1 AND A."DocAmt" + A."AccrAmt" <> 0 AND I."ItemCode" IS NULL;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-21', :t21, NULL);

    -- PRE-22 本期材料暂估变动（收货、退货、发票差额）在计价仓库没有库存记录：凭证记了存货科目，物料成本却不含这笔（Q29）
    t22 = SELECT "MTC_CA_F_DOCKEY"(A."ObjType", A."DocEntry") || '-LineNum ' || A."LineNum" AS "KeyCode",
                 CASE A."MoveType" WHEN 'INV' THEN '发票差额 ' || TO_NVARCHAR(IFNULL(A."DocAmt", 0) + A."AccrAmt")
                      ELSE '暂估 ' || TO_NVARCHAR(A."AccrAmt") END || '，物料 ' || A."ItemCode" || ' 没有计价仓库的 OIVL 记录' AS "Info"
            FROM "MTC_CA_S_AP_MOVE" A
           WHERE A."RunId" = :RunId AND A."AccrType" = 'MAT' AND A."DocDate" BETWEEN :d0 AND :d1
             AND CASE WHEN A."MoveType" = 'INV' THEN IFNULL(A."DocAmt", 0) + A."AccrAmt" ELSE A."AccrAmt" END <> 0
             AND NOT EXISTS (SELECT 1 FROM "MTC_CA_S_LINE" L
                              WHERE L."RunId" = :RunId AND L."Src" = 'OIVL' AND L."ObjType" = A."ObjType"
                                AND L."DocEntry" = A."DocEntry" AND L."LineNum" = A."LineNum");
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-22', :t22, NULL);

    -- PRE-24 工单类型（U_OrdType）不能为空：为空时分不到制造费用和人工（PRE-17 只看 10–40），对账也归不到生产 / 委外在产品（用户 2026-10-14）
    t24 = SELECT O."OrderType" || '-DocNum ' || O."OrderNum" AS "KeyCode",
                 '产品 ' || IFNULL(O."ItemCode", '空') || '，工单类型（U_OrdType）为空' AS "Info"
            FROM "MTC_CA_S_ORDER" O
           WHERE O."RunId" = :RunId AND IFNULL(O."WorType", '') = '';
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-24', :t24, NULL);

    -- PRE-25 其他收发货行上的科目与库存交易事务配置（@U_CITRN1：业务类型 + 部门 U_CtrCode + 物料组 → U_AcctCode）不一致（用户 2026-10-15）
    -- 例：210 其他辅助领用配的是 5101 制造费用，单据上填了 500101，YF01 借 500101 却没有订单承接，生产在产品对账（POST-13）对不上。
    -- 范围由参数 ACCT_CHECK_BUSITYPES 控制（默认 210）；配置里找不到 业务类型 + 部门 + 物料组 的组合也报出。
    bt25 := IFNULL("MTC_CA_F_PARAM"('ACCT_CHECK_BUSITYPES', :fc), ',210,');
    cfg25 = SELECT TO_NVARCHAR("Code") AS "BusiType", TO_NVARCHAR("U_CtrCode") AS "OcrCode", TO_NVARCHAR("U_ItmGrpCod") AS "ItmsGrpCod",
                   MAX("U_AcctCode") AS "CfgAcct", COUNT(DISTINCT "U_AcctCode") AS "AcctCnt"
              FROM "@U_CITRN1"
             WHERE IFNULL("U_AcctCode", '') <> ''
             GROUP BY TO_NVARCHAR("Code"), TO_NVARCHAR("U_CtrCode"), TO_NVARCHAR("U_ItmGrpCod");
    t25 = SELECT L."ObjType" || '-DocNum ' || L."DocNum" || '-LineNum ' || L."LineNum" AS "KeyCode",
                 '业务类型 ' || L."BusiType" || '，部门 ' || IFNULL(L."OcrCode", '空') || '，物料 ' || L."ItemCode"
                 || '（物料组 ' || IFNULL(I."ItmsGrpCod", '空') || '）：单据科目 ' || IFNULL(L."AcctCode", '空')
                 || CASE WHEN C."CfgAcct" IS NULL THEN '，库存交易事务配置中没有这个 业务类型 + 部门 + 物料组'
                         WHEN C."AcctCnt" > 1 THEN '，库存交易事务配置中同一组合有多个科目'
                         ELSE ' ≠ 配置科目 ' || C."CfgAcct" END AS "Info"
            FROM "MTC_CA_S_LINE" L
            LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = L."RunId" AND I."ItemCode" = L."ItemCode"
            LEFT JOIN :cfg25 C ON C."BusiType" = L."BusiType" AND C."OcrCode" = L."OcrCode"
                              AND C."ItmsGrpCod" = TO_NVARCHAR(I."ItmsGrpCod")
           WHERE L."RunId" = :RunId AND L."ObjType" IN ('59', '60') AND IFNULL(L."Canceled", 'N') = 'N'
             AND LOCATE(:bt25, ',' || L."BusiType" || ',') > 0
             AND (C."CfgAcct" IS NULL OR C."AcctCnt" > 1 OR IFNULL(L."AcctCode", '') <> C."CfgAcct");
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-25', :t25, NULL);

    -- PRE-26 本期应收发票 / 贷项的库存物料行不基于交货 / 退货（直接开票出库、预留发票、基于发票的退货贷项）：
    --        发出商品和 DN03 只认基于交货 / 退货的开票，这类行的成本结转不了（用户 2026-10-15：不会出现，出现就阻断）
    t26 = SELECT '13' || '-DocNum ' || M."DocNum" || '-LineNum ' || D."LineNum" AS "KeyCode",
                 '应收发票行 ' || D."ItemCode" || ' 不基于交货（来源类型 ' || IFNULL(TO_NVARCHAR(D."BaseType"), '无') || '）' AS "Info"
            FROM "OINV" M JOIN "INV1" D ON D."DocEntry" = M."DocEntry" JOIN "OITM" I ON I."ItemCode" = D."ItemCode" AND I."InvntItem" = 'Y'
           WHERE M."DocDate" BETWEEN :d0 AND :d1 AND M."CANCELED" <> 'C' AND IFNULL(D."BaseType", -1) <> 15
          UNION ALL
          SELECT '14' || '-DocNum ' || M."DocNum" || '-LineNum ' || D."LineNum",
                 '应收贷项行 ' || D."ItemCode" || ' 不基于退货（来源类型 ' || IFNULL(TO_NVARCHAR(D."BaseType"), '无') || '）'
            FROM "ORIN" M JOIN "RIN1" D ON D."DocEntry" = M."DocEntry" JOIN "OITM" I ON I."ItemCode" = D."ItemCode" AND I."InvntItem" = 'Y'
           WHERE M."DocDate" BETWEEN :d0 AND :d1 AND M."CANCELED" <> 'C' AND IFNULL(D."BaseType", -1) <> 16;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-26', :t26, NULL);

    -- PRE-27 销售单据没有客户类型（U_SalOrdType 在 @MTC_SALORDTYPE 中找不到，或 U_CustType 不是参数 CUST_DOM / CUST_EXP，默认 国内客户 / 国外客户）：
    --        DN03 取不到 6401 科目、AR03/AR04 不计提、样品 DN02/DN04 不生成（用户 2026-10-15 阻断）。
    --        范围：本期交货 / 退货 / 应收发票 / 贷项的库存物料行，以及截至期末仍未开票的交货 / 独立退货行
    st27 = SELECT "Name", MAX("U_CustType") AS "CustType" FROM "@MTC_SALORDTYPE" GROUP BY "Name";
    doc27 = SELECT '15' AS "ObjType", M."DocNum", M."DocEntry", M."U_SalOrdType", TO_DATE(M."DocDate") AS "DocDate"
              FROM "ODLN" M WHERE M."CANCELED" <> 'C'
            UNION ALL SELECT '16', M."DocNum", M."DocEntry", M."U_SalOrdType", TO_DATE(M."DocDate") FROM "ORDN" M WHERE M."CANCELED" <> 'C'
            UNION ALL SELECT '13', M."DocNum", M."DocEntry", M."U_SalOrdType", TO_DATE(M."DocDate") FROM "OINV" M WHERE M."CANCELED" <> 'C'
            UNION ALL SELECT '14', M."DocNum", M."DocEntry", M."U_SalOrdType", TO_DATE(M."DocDate") FROM "ORIN" M WHERE M."CANCELED" <> 'C';
    itm27 = SELECT '15' AS "ObjType", D."DocEntry" FROM "DLN1" D JOIN "OITM" I ON I."ItemCode" = D."ItemCode" AND I."InvntItem" = 'Y'
            UNION SELECT '16', D."DocEntry" FROM "RDN1" D JOIN "OITM" I ON I."ItemCode" = D."ItemCode" AND I."InvntItem" = 'Y'
            UNION SELECT '13', D."DocEntry" FROM "INV1" D JOIN "OITM" I ON I."ItemCode" = D."ItemCode" AND I."InvntItem" = 'Y'
            UNION SELECT '14', D."DocEntry" FROM "RIN1" D JOIN "OITM" I ON I."ItemCode" = D."ItemCode" AND I."InvntItem" = 'Y';
    open27 = SELECT DISTINCT "ObjType", "DocEntry" FROM "MTC_CA_F_GOODS_OPEN"(:d1);
    t27 = SELECT D."ObjType" || '-DocNum ' || D."DocNum" AS "KeyCode",
                 '销售订单类型 ' || IFNULL(D."U_SalOrdType", '空')
                 || CASE WHEN T."Name" IS NULL THEN ' 在 @MTC_SALORDTYPE 中没有' ELSE ' 的客户类型为 ' || IFNULL(T."CustType", '空') END
                 || CASE WHEN D."DocDate" < :d0 THEN '（以前账期的单据，截至期末仍未开票）' ELSE '' END AS "Info"
            FROM :doc27 D
            LEFT JOIN :st27 T ON T."Name" = D."U_SalOrdType"
           WHERE IFNULL(T."CustType", '') NOT IN (:custDom, :custExp)
             AND ((D."DocDate" BETWEEN :d0 AND :d1
                   AND EXISTS (SELECT 1 FROM :itm27 X WHERE X."ObjType" = D."ObjType" AND X."DocEntry" = D."DocEntry"))
                  OR EXISTS (SELECT 1 FROM :open27 O WHERE O."ObjType" = D."ObjType" AND O."DocEntry" = D."DocEntry"));
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-27', :t27, NULL);

    -- PRE-28 参数目录 MTC_CA_C_PARAM_DEF 里的参数，B1 @MTC_CA_PARAM 没有适用于本账期的行（用户 2026-11-01 阻断，为保证准确）：
    --        P05 对 B1 里没有的参数静默沿用新框架种子值，新加的参数（如 GOODS_TAIL_MAX）B1 没补也照算，这里拦下。
    --        判断用 B1 原样快照 MTC_CA_C_PARAM_B1（P05 每次同步时整表刷新）：Code 中 @ 前 = 参数代码，起止账期为空 = 不限。
    --        只看有没有行；取值是否为空、格式、账期重叠由 PRE-18（B1 同步出错）管，列表型参数可以填空值。
    --        旧表 @MTC_CA_EXPSET 不算维护（2026-10-28 起参数在 @MTC_CA_PARAM 维护）。
    SELECT COUNT(*) INTO n FROM SYS."TABLES" WHERE "SCHEMA_NAME" = CURRENT_SCHEMA AND "TABLE_NAME" = '@MTC_CA_PARAM';
    t28 = SELECT '@MTC_CA_PARAM' AS "KeyCode",
                 'B1 没有计算参数表 @MTC_CA_PARAM：参数目录中的 ' || (SELECT COUNT(*) FROM "MTC_CA_C_PARAM_DEF") || ' 个参数都没有维护（在 B1 建表后用 sl_import_costcfg.py --param 导入）' AS "Info"
            FROM DUMMY WHERE :n = 0
          UNION ALL
          SELECT D."ParamCode",
                 D."CnName" || '（' || D."Category" || '）：'
                 || CASE WHEN B."P" IS NOT NULL THEN 'B1 有这个参数（' || B."Ranges" || '），但没有一行的起止账期包含 ' || :fc
                         ELSE 'B1 @MTC_CA_PARAM 没有这个参数' END
                 || CASE WHEN IFNULL(D."Hint", '') <> '' THEN '；填法：' || D."Hint" ELSE '' END
            FROM "MTC_CA_C_PARAM_DEF" D
            LEFT JOIN (SELECT "P", STRING_AGG("F" || '~' || "T", '、' ORDER BY "F") AS "Ranges",
                              MAX(CASE WHEN "F" <= :fc AND "T" >= :fc THEN 1 ELSE 0 END) AS "InFc"
                         FROM (SELECT SUBSTR_BEFORE(TRIM("Code") || '@', '@') AS "P",
                                      IFNULL(NULLIF(TRIM("FromFc"), ''), '0000-00') AS "F", IFNULL(NULLIF(TRIM("ToFc"), ''), '9999-99') AS "T"
                                 FROM "MTC_CA_C_PARAM_B1")
                        GROUP BY "P") B ON B."P" = D."ParamCode"
           WHERE :n > 0 AND IFNULL(B."InFc", 0) = 0;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'PRE-28', :t28, NULL);

    SELECT COUNT(*) INTO BlockCnt FROM "MTC_CA_R_CHECK" WHERE "RunId" = :RunId AND "Stage" = 'PRE' AND "Result" = 'FAIL';
END
