-- =====================================================================
-- 新成本框架 第 2 期：P50 定稿、P60 计算后校验与指标快照、P65 新旧比对（设计稿 4、6）
-- 替代：0401 末尾“91 写入”和入库尾差处理、CAL_1004_CHECK(_LS)、CO4004 的勾稽部分、C01–C18 中与新表相关的项。
-- =====================================================================

-- P50：按最终单价给加权价行定价；物料进销存四项；期末数量为 0 而金额不为 0 的，尾差挤进该物料数量最大的普通出库行；
-- 没有可挤的出库行、且尾差在参数 TAIL_MAX（±0.02，Q32 用户 2026-10-14）以内的，记入 R_ITEM.TailAmt 结转（TAIL-01，凭证 JZ04，借 / 贷 TAIL_ADJ 科目）
CREATE OR REPLACE PROCEDURE "MTC_CA_P50_FINALIZE" (IN RunId BIGINT, IN Iters INT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE tailMax DECIMAL(19,6);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    tailMax := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('TAIL_MAX', :fc), '0'), 19, 6);
    CALL "MTC_CA_P41_PRICE"(:RunId, :Iters);

    -- 形态转换：P41 重新给 O05 定价后，I05 再对齐
    UPDATE T0 SET T0."MatAmt" = -B."MatAmt", T0."MfgAmt" = -B."MfgAmt", T0."LabAmt" = -B."LabAmt", T0."SubAmt" = -B."SubAmt",
                  T0."Amount" = -B."Amount"
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_R_PAIR" P ON P."RunId" = T0."RunId" AND P."LineId" = T0."LineId" AND P."PairType" = 'TRF'
      JOIN "MTC_CA_R_LINE" B ON B."RunId" = T0."RunId" AND B."LineId" = P."SrcLineId"
     WHERE T0."RunId" = :RunId;

    -- 进销存：数量为正是入库、为负是出库；数量为 0 的（发票差额、重估）按交易类型方向
    UPDATE "MTC_CA_R_ITEM"
       SET "InQty" = 0, "InMat" = 0, "InMfg" = 0, "InLab" = 0, "InSub" = 0,
           "OutQty" = 0, "OutMat" = 0, "OutMfg" = 0, "OutLab" = 0, "OutSub" = 0, "Flags" = NULL, "TailAmt" = 0
     WHERE "RunId" = :RunId;
    flow = SELECT "ItemCode",
                  CASE WHEN "Qty" > 0 THEN 'I' WHEN "Qty" < 0 THEN 'O'
                       WHEN LEFT(IFNULL("TransCode", 'I'), 1) = 'O' AND "TransCode" <> 'O06' THEN 'O' ELSE 'I' END AS "Dir",
                  "Qty", "MatAmt", "MfgAmt", "LabAmt", "SubAmt"
             FROM "MTC_CA_R_LINE" WHERE "RunId" = :RunId;
    UPDATE T0 SET T0."InQty" = S."InQty", T0."InMat" = S."InMat", T0."InMfg" = S."InMfg", T0."InLab" = S."InLab", T0."InSub" = S."InSub",
                  T0."OutQty" = S."OutQty", T0."OutMat" = S."OutMat", T0."OutMfg" = S."OutMfg", T0."OutLab" = S."OutLab", T0."OutSub" = S."OutSub"
      FROM "MTC_CA_R_ITEM" T0
      JOIN (SELECT "ItemCode",
                   SUM(CASE WHEN "Dir" = 'I' THEN "Qty" ELSE 0 END) AS "InQty",
                   SUM(CASE WHEN "Dir" = 'I' THEN "MatAmt" ELSE 0 END) AS "InMat", SUM(CASE WHEN "Dir" = 'I' THEN "MfgAmt" ELSE 0 END) AS "InMfg",
                   SUM(CASE WHEN "Dir" = 'I' THEN "LabAmt" ELSE 0 END) AS "InLab", SUM(CASE WHEN "Dir" = 'I' THEN "SubAmt" ELSE 0 END) AS "InSub",
                   SUM(CASE WHEN "Dir" = 'O' THEN "Qty" ELSE 0 END) AS "OutQty",
                   SUM(CASE WHEN "Dir" = 'O' THEN "MatAmt" ELSE 0 END) AS "OutMat", SUM(CASE WHEN "Dir" = 'O' THEN "MfgAmt" ELSE 0 END) AS "OutMfg",
                   SUM(CASE WHEN "Dir" = 'O' THEN "LabAmt" ELSE 0 END) AS "OutLab", SUM(CASE WHEN "Dir" = 'O' THEN "SubAmt" ELSE 0 END) AS "OutSub"
              FROM :flow GROUP BY "ItemCode") S
        ON S."ItemCode" = T0."ItemCode"
     WHERE T0."RunId" = :RunId;
    UPDATE "MTC_CA_R_ITEM"
       SET "EndQty" = "OpenQty" + "InQty" + "OutQty",
           "EndMat" = "OpenMat" + "InMat" + "OutMat", "EndMfg" = "OpenMfg" + "InMfg" + "OutMfg",
           "EndLab" = "OpenLab" + "InLab" + "OutLab", "EndSub" = "OpenSub" + "InSub" + "OutSub"
     WHERE "RunId" = :RunId;

    -- 尾差（RND-01）：不挤公摊材料行（费用已分摊）和形态转换转出行（要与转入相等）
    cand = SELECT L."LineId", L."ItemCode",
                  ROW_NUMBER() OVER (PARTITION BY L."ItemCode" ORDER BY ABS(L."Qty") DESC, L."LineId") AS "Rn"
             FROM "MTC_CA_R_LINE" L
             JOIN "MTC_CA_R_ITEM" I ON I."RunId" = L."RunId" AND I."ItemCode" = L."ItemCode"
            WHERE L."RunId" = :RunId AND L."Cat" = 'WAVG' AND L."Qty" < 0 AND L."IsShared" = 'N'
              AND L."LineId" NOT IN (SELECT "SrcLineId" FROM "MTC_CA_R_PAIR" WHERE "RunId" = :RunId AND "SrcLineId" IS NOT NULL)
              AND I."EndQty" = 0
              AND (I."EndMat" <> 0 OR I."EndMfg" <> 0 OR I."EndLab" <> 0 OR I."EndSub" <> 0);
    UPDATE T0 SET T0."MatAmt" = T0."MatAmt" - I."EndMat", T0."MfgAmt" = T0."MfgAmt" - I."EndMfg",
                  T0."LabAmt" = T0."LabAmt" - I."EndLab", T0."SubAmt" = T0."SubAmt" - I."EndSub",
                  T0."Amount" = T0."Amount" - I."EndMat" - I."EndMfg" - I."EndLab" - I."EndSub",
                  T0."PriceSrc" = T0."PriceSrc" || '；含期末尾差', T0."RuleId" = 'RND-01'
      FROM "MTC_CA_R_LINE" T0
      JOIN :cand C ON C."LineId" = T0."LineId" AND C."Rn" = 1
      JOIN "MTC_CA_R_ITEM" I ON I."RunId" = T0."RunId" AND I."ItemCode" = T0."ItemCode"
     WHERE T0."RunId" = :RunId;
    UPDATE T0 SET T0."OutMat" = T0."OutMat" - T0."EndMat", T0."OutMfg" = T0."OutMfg" - T0."EndMfg",
                  T0."OutLab" = T0."OutLab" - T0."EndLab", T0."OutSub" = T0."OutSub" - T0."EndSub",
                  T0."EndMat" = 0, T0."EndMfg" = 0, T0."EndLab" = 0, T0."EndSub" = 0
      FROM "MTC_CA_R_ITEM" T0
      JOIN :cand C ON C."ItemCode" = T0."ItemCode" AND C."Rn" = 1
     WHERE T0."RunId" = :RunId;

    -- 零库存尾差结转（TAIL-01）：仍是期末数量 0、金额不为 0（没有可挤的出库行），总额和四项都在 ±TAIL_MAX 以内的，
    -- 计入出库方向、期末清零，金额记 TailAmt，由 P70 生成 JZ04 凭证；超过的留在期末，POST-07 报出
    UPDATE "MTC_CA_R_ITEM"
       SET "TailAmt" = -("EndMat" + "EndMfg" + "EndLab" + "EndSub"),
           "OutMat" = "OutMat" - "EndMat", "OutMfg" = "OutMfg" - "EndMfg", "OutLab" = "OutLab" - "EndLab", "OutSub" = "OutSub" - "EndSub",
           "EndMat" = 0, "EndMfg" = 0, "EndLab" = 0, "EndSub" = 0
     WHERE "RunId" = :RunId AND "EndQty" = 0
       AND ("EndMat" <> 0 OR "EndMfg" <> 0 OR "EndLab" <> 0 OR "EndSub" <> 0)
       AND ABS("EndMat" + "EndMfg" + "EndLab" + "EndSub") <= :tailMax
       AND ABS("EndMat") <= :tailMax AND ABS("EndMfg") <= :tailMax AND ABS("EndLab") <= :tailMax AND ABS("EndSub") <= :tailMax;

    UPDATE "MTC_CA_R_ITEM"
       SET "EndAmount" = "EndMat" + "EndMfg" + "EndLab" + "EndSub",
           "Flags" = NULLIF(
                     CASE WHEN "EndQty" < 0 THEN '负库存；' ELSE '' END
                  || CASE WHEN "OutQty" <> 0 AND "PriceSrc" = 'QCPRICE' THEN '用了维护价兜底；' ELSE '' END
                  || CASE WHEN "OutQty" <> 0 AND "PriceSrc" = 'OPEN' THEN '本期无计价入库，用期初单价；' ELSE '' END
                  || CASE WHEN "OutQty" <> 0 AND "PriceSrc" = 'ZERO' THEN '无价；' ELSE '' END
                  || CASE WHEN "EndQty" = 0 AND ("EndMat" <> 0 OR "EndMfg" <> 0 OR "EndLab" <> 0 OR "EndSub" <> 0)
                          THEN '期末数量为 0 但金额不为 0，没有可挤尾差的出库行，且超过尾差结转上限 TAIL_MAX；' ELSE '' END, '')
     WHERE "RunId" = :RunId;

    -- 料工费占比（用户 2026-10-18）：期初、入库、出库、期末各自的材料 / 人工 / 制造 / 委外 ÷ 该项四项合计 × 100，保留 4 位；
    -- 四项合计为 0（绝对值不超过 0.005）时为空。出库四项都是负数，比值仍为正。物料组小计、合计的占比由执行台按汇总金额现算
    UPDATE "MTC_CA_R_ITEM"
       SET
           "RtOpenMat" = CASE WHEN ABS("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") > 0.005 THEN ROUND("OpenMat" / ("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") * 100, 4) END,
           "RtOpenLab" = CASE WHEN ABS("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") > 0.005 THEN ROUND("OpenLab" / ("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") * 100, 4) END,
           "RtOpenMfg" = CASE WHEN ABS("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") > 0.005 THEN ROUND("OpenMfg" / ("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") * 100, 4) END,
           "RtOpenSub" = CASE WHEN ABS("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") > 0.005 THEN ROUND("OpenSub" / ("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") * 100, 4) END,
           "RtInMat" = CASE WHEN ABS("InMat" + "InMfg" + "InLab" + "InSub") > 0.005 THEN ROUND("InMat" / ("InMat" + "InMfg" + "InLab" + "InSub") * 100, 4) END,
           "RtInLab" = CASE WHEN ABS("InMat" + "InMfg" + "InLab" + "InSub") > 0.005 THEN ROUND("InLab" / ("InMat" + "InMfg" + "InLab" + "InSub") * 100, 4) END,
           "RtInMfg" = CASE WHEN ABS("InMat" + "InMfg" + "InLab" + "InSub") > 0.005 THEN ROUND("InMfg" / ("InMat" + "InMfg" + "InLab" + "InSub") * 100, 4) END,
           "RtInSub" = CASE WHEN ABS("InMat" + "InMfg" + "InLab" + "InSub") > 0.005 THEN ROUND("InSub" / ("InMat" + "InMfg" + "InLab" + "InSub") * 100, 4) END,
           "RtOutMat" = CASE WHEN ABS("OutMat" + "OutMfg" + "OutLab" + "OutSub") > 0.005 THEN ROUND("OutMat" / ("OutMat" + "OutMfg" + "OutLab" + "OutSub") * 100, 4) END,
           "RtOutLab" = CASE WHEN ABS("OutMat" + "OutMfg" + "OutLab" + "OutSub") > 0.005 THEN ROUND("OutLab" / ("OutMat" + "OutMfg" + "OutLab" + "OutSub") * 100, 4) END,
           "RtOutMfg" = CASE WHEN ABS("OutMat" + "OutMfg" + "OutLab" + "OutSub") > 0.005 THEN ROUND("OutMfg" / ("OutMat" + "OutMfg" + "OutLab" + "OutSub") * 100, 4) END,
           "RtOutSub" = CASE WHEN ABS("OutMat" + "OutMfg" + "OutLab" + "OutSub") > 0.005 THEN ROUND("OutSub" / ("OutMat" + "OutMfg" + "OutLab" + "OutSub") * 100, 4) END,
           "RtEndMat" = CASE WHEN ABS("EndMat" + "EndMfg" + "EndLab" + "EndSub") > 0.005 THEN ROUND("EndMat" / ("EndMat" + "EndMfg" + "EndLab" + "EndSub") * 100, 4) END,
           "RtEndLab" = CASE WHEN ABS("EndMat" + "EndMfg" + "EndLab" + "EndSub") > 0.005 THEN ROUND("EndLab" / ("EndMat" + "EndMfg" + "EndLab" + "EndSub") * 100, 4) END,
           "RtEndMfg" = CASE WHEN ABS("EndMat" + "EndMfg" + "EndLab" + "EndSub") > 0.005 THEN ROUND("EndMfg" / ("EndMat" + "EndMfg" + "EndLab" + "EndSub") * 100, 4) END,
           "RtEndSub" = CASE WHEN ABS("EndMat" + "EndMfg" + "EndLab" + "EndSub") > 0.005 THEN ROUND("EndSub" / ("EndMat" + "EndMfg" + "EndLab" + "EndSub") * 100, 4) END
     WHERE "RunId" = :RunId;

    UPDATE "MTC_CA_R_LINE" SET "Price" = "Amount" / NULLIF("Qty", 0) WHERE "RunId" = :RunId;
END
@@
-- P60：计算后校验（结果写 R_CHECK，Stage = POST）和指标快照（RUN_KPI，每次运行都保留）
CREATE OR REPLACE PROCEDURE "MTC_CA_P60_POSTCHECK" (IN RunId BIGINT, OUT FailCnt INT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE boot NVARCHAR(10); DECLARE prev NVARCHAR(10);
    DECLARE tailMax DECIMAL(19,6); DECLARE tailWarn DECIMAL(19,6); DECLARE pjPct DECIMAL(19,6); DECLARE pjAmt DECIMAL(19,6);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    boot := "MTC_CA_F_PARAM"('BOOTSTRAP_FC', :fc);
    tailMax := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('TAIL_MAX', :fc), '0.02'), 19, 6);
    tailWarn := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('TAIL_WARN', :fc), '0.1'), 19, 6);
    pjPct := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('PRICE_JUMP_PCT', :fc), '30'), 19, 6);
    pjAmt := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('PRICE_JUMP_AMT', :fc), '100'), 19, 6);
    SELECT MAX("Code") INTO prev FROM "OFPR" WHERE "Code" < :fc;

    -- POST-01 期末数量 = B1（计价仓库 OIVL 截至期末）
    b1 = SELECT P0."ItemCode", SUM(P0."InQty" - P0."OutQty") AS "Qty"
           FROM "OIVL" P0 JOIN "MTC_CA_V_WHS" W ON W."WhsCode" = P0."LocCode" AND W."IsCost" = 'Y'
          WHERE P0."DocDate" <= :d1
          GROUP BY P0."ItemCode";
    t01 = SELECT K."ItemCode" AS "KeyCode",
                 '新框架期末 ' || TO_NVARCHAR(IFNULL(I."EndQty", 0)) || '，B1 ' || TO_NVARCHAR(IFNULL(B."Qty", 0)) AS "Info"
            FROM (SELECT "ItemCode" FROM "MTC_CA_R_ITEM" WHERE "RunId" = :RunId UNION SELECT "ItemCode" FROM :b1) K
            LEFT JOIN "MTC_CA_R_ITEM" I ON I."RunId" = :RunId AND I."ItemCode" = K."ItemCode"
            LEFT JOIN :b1 B ON B."ItemCode" = K."ItemCode"
           WHERE ABS(IFNULL(I."EndQty", 0) - IFNULL(B."Qty", 0)) > 0.000001;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-01', :t01, NULL);

    -- POST-02 进销存四项平衡
    t02 = SELECT "ItemCode" AS "KeyCode", '期初 + 入 + 出 ≠ 期末' AS "Info"
            FROM "MTC_CA_R_ITEM"
           WHERE "RunId" = :RunId
             AND (ABS("OpenMat" + "InMat" + "OutMat" - "EndMat") > 0.01 OR ABS("OpenMfg" + "InMfg" + "OutMfg" - "EndMfg") > 0.01
               OR ABS("OpenLab" + "InLab" + "OutLab" - "EndLab") > 0.01 OR ABS("OpenSub" + "InSub" + "OutSub" - "EndSub") > 0.01
               OR ABS("OpenQty" + "InQty" + "OutQty" - "EndQty") > 0.000001);
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-02', :t02, NULL);

    -- POST-03 费用守恒：池 = 已分摊 + 未分摊；未分摊报出（Q13）
    t03 = SELECT P."PoolCode" || '-' || P."Elem" AS "KeyCode",
                 '费用池 ' || TO_NVARCHAR(ROUND(P."Amt", 2)) || '，已分摊 ' || TO_NVARCHAR(IFNULL(A."Amt", 0)) || '，未分摊 '
                 || TO_NVARCHAR(ROUND(P."Amt" - IFNULL(A."Amt", 0), 2)) AS "Info"
            FROM (SELECT "PoolCode", "Elem", SUM("Amount") AS "Amt" FROM "MTC_CA_R_POOL" WHERE "RunId" = :RunId GROUP BY "PoolCode", "Elem") P
            LEFT JOIN (SELECT "PoolCode", "Elem", SUM("Amount") AS "Amt" FROM "MTC_CA_R_ALLOC" WHERE "RunId" = :RunId GROUP BY "PoolCode", "Elem") A
              ON A."PoolCode" = P."PoolCode" AND A."Elem" = P."Elem"
           WHERE ABS(P."Amt" - IFNULL(A."Amt", 0)) > 0.01;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-03', :t03, NULL);

    -- POST-04 订单勾稽：累计领料 = 累计结转 + 在产品 + 关单差异；本期关单的订单在产品为 0
    t04 = SELECT M."OrderType" || '-DocEntry ' || M."OrderEntry" || '-' || M."ItemCode" AS "KeyCode", '累计领料 ≠ 累计结转 + 在产品 + 关单差异' AS "Info"
            FROM "MTC_CA_R_ORDER_MAT" M
           WHERE M."RunId" = :RunId
             AND ABS(M."OpenIssMat" + M."IssMat" + M."OpenIssMfg" + M."IssMfg" + M."OpenIssLab" + M."IssLab" + M."OpenIssSub" + M."IssSub"
                     - (M."OpenCarMat" + M."CarMat" + M."OpenCarMfg" + M."CarMfg" + M."OpenCarLab" + M."CarLab" + M."OpenCarSub" + M."CarSub")
                     - (M."WipMat" + M."WipMfg" + M."WipLab" + M."WipSub") - (M."ClsMat" + M."ClsMfg" + M."ClsLab" + M."ClsSub")) > 0.01
          UNION ALL
          SELECT "OrderType" || '-DocEntry ' || "OrderEntry", '本期关单但在产品不为 0'
            FROM "MTC_CA_R_ORDER" WHERE "RunId" = :RunId AND "ClosedInFc" = 'Y' AND ABS("WipAmt") > 0.01
          UNION ALL
          SELECT O."OrderType" || '-DocEntry ' || O."OrderEntry", '完工入库行合计 ≠ 订单完工成本'
            FROM "MTC_CA_R_ORDER" O
            JOIN (SELECT "OrderType", "OrderEntry", SUM("Amount") AS "Amt" FROM "MTC_CA_R_LINE"
                   WHERE "RunId" = :RunId AND "Cat" = 'RCPT' GROUP BY "OrderType", "OrderEntry") L
              ON L."OrderType" = O."OrderType" AND L."OrderEntry" = O."OrderEntry"
           WHERE O."RunId" = :RunId AND O."RecvQty" <> 0 AND ABS(L."Amt" - O."CostAmt") > 0.05;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-04', :t04, NULL);

    -- POST-05 配对：I05 = −O05；退货、取消单按原单成本
    -- 明细按单据写（用户 2026-10-13：只有行号看不出是什么单）：KeyCode = ObjType-DocNum-LineNum，与 PRE 检查一致；
    -- Info 开头写单据类型中文名、取消单 / 被取消、物料、交易类型
    t05r = SELECT P."LineId", P."PairType" || '：金额与来源行不对应' AS "Msg"
             FROM "MTC_CA_R_PAIR" P
             JOIN "MTC_CA_R_LINE" A ON A."RunId" = P."RunId" AND A."LineId" = P."LineId"
             LEFT JOIN "MTC_CA_R_LINE" B ON B."RunId" = P."RunId" AND B."LineId" = P."SrcLineId"
            WHERE P."RunId" = :RunId
              AND ((P."PairType" = 'TRF' AND ABS(A."Amount" + IFNULL(B."Amount", 0)) > 0.01)
                OR (P."PairType" IN ('SRT', 'CNL') AND P."SrcLineId" IS NULL
                    AND ABS(A."Amount" - ROUND((IFNULL(P."UMat", 0) + IFNULL(P."UMfg", 0) + IFNULL(P."ULab", 0) + IFNULL(P."USub", 0)) * A."Qty", 2)) > 0.05))
           UNION ALL
           SELECT "LineId", '找不到原交货成本或配对，按加权价兜底（' || "RuleId" || '）'
             FROM "MTC_CA_R_LINE"
            WHERE "RunId" = :RunId AND ("RuleId" = 'SRT-02' OR ("RuleId" = 'TRF-01' AND "Cat" = 'WAVG'))
           -- 取消单：原单在本期、按加权价的与原单同价相抵，不报；只报本期找不到原单的（2026-10-14）
           UNION ALL
           SELECT T."LineId", '取消单本期找不到原单，按加权价兜底（CNL-01）'
             FROM "MTC_CA_R_LINE" T
             JOIN "MTC_CA_S_LINE" S ON S."RunId" = T."RunId" AND S."LineId" = T."LineId"
            WHERE T."RunId" = :RunId AND T."RuleId" = 'CNL-01' AND T."Cat" = 'WAVG'
              AND NOT EXISTS (SELECT 1 FROM "MTC_CA_S_LINE" O
                               WHERE O."RunId" = S."RunId" AND O."ObjType" = S."ObjType" AND O."ItemCode" = S."ItemCode"
                                 AND TO_NVARCHAR(O."DocEntry") = S."BaseEntry" AND TO_NVARCHAR(O."LineNum") = S."BaseLine");
    t05 = SELECT IFNULL(S."ObjType" || '-DocNum ' || S."DocNum" || '-LineNum ' || IFNULL(TO_NVARCHAR(S."LineNum"), ''), 'LineId ' || TO_NVARCHAR(T."LineId")) AS "KeyCode",
                 CASE S."ObjType" WHEN '13' THEN '应收发票' WHEN '14' THEN '应收贷项' WHEN '15' THEN '销售交货' WHEN '16' THEN '销售退货'
                                  WHEN '18' THEN '应付发票' WHEN '19' THEN '应付贷项' WHEN '20' THEN '采购收货' WHEN '21' THEN '采购退货'
                                  WHEN '59' THEN '收货单' WHEN '60' THEN '发货单' WHEN '67' THEN '库存转储' WHEN '162' THEN '库存重估'
                                  ELSE IFNULL(S."ObjType", '') END
                 || CASE S."Canceled" WHEN 'C' THEN '（取消单）' WHEN 'Y' THEN '（已被取消）' ELSE '' END
                 || ' ' || IFNULL(S."DocNum", '') || ' 第 ' || IFNULL(TO_NVARCHAR(S."LineNum"), '') || ' 行，物料 ' || IFNULL(S."ItemCode", '')
                 || '，' || IFNULL(S."TransCode", '') || '：' || T."Msg" AS "Info"
            FROM :t05r T
            LEFT JOIN "MTC_CA_S_LINE" S ON S."RunId" = :RunId AND S."LineId" = T."LineId";
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-05', :t05, NULL);

    -- POST-06 委外对账移到 P75（MTC_CA_F_RECON，要用到凭证底稿，用户 2026-10-13）

    -- POST-07 物料标记：负库存、兜底价、无价、尾差无处挤
    t07 = SELECT "ItemCode" AS "KeyCode", "Flags" AS "Info" FROM "MTC_CA_R_ITEM" WHERE "RunId" = :RunId AND "Flags" IS NOT NULL;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-07', :t07, NULL);

    -- POST-14 物料成本异常（用户 2026-10-14）：单价、数量、金额异常，含小尾差和价格大幅波动；原为只警告，2026-10-14 起计算后校验不通过一律阻断。
    -- 单价 P = 本期加权单价四项之和；期初单价 = 期初金额 ÷ 期初数量。阈值：TAIL_MAX（零库存尾差）、TAIL_WARN（挤入出库行的尾差）、PRICE_JUMP_PCT（%）、PRICE_JUMP_AMT（影响金额下限）
    itm = SELECT "ItemCode", "OpenQty", "OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub" AS "OpenAmt",
                 "PMat" + "PMfg" + "PLab" + "PSub" AS "P", "OutQty", "EndQty", "EndAmount", "TailAmt"
            FROM "MTC_CA_R_ITEM" WHERE "RunId" = :RunId;
    t14 = -- ① 小尾差：零库存尾差已结转（TAIL-01）
          SELECT "ItemCode" AS "KeyCode", '小尾差：期末数量 0，尾差 ' || TO_NVARCHAR(ROUND(-"TailAmt", 2)) || ' 已结转（JZ04，TAIL-01）' AS "Info"
            FROM :itm WHERE ROUND("TailAmt", 2) <> 0
          -- ② 尾差偏大：挤进出库行的尾差（行金额 − 数量 × 单价）绝对值 ≥ TAIL_WARN（0.1）；
          --    这行吸收的是其他出库行四项分别四舍五入的累积差，行多时几分钱是正常的，不用 TAIL_MAX（用户 2026-10-14）
          UNION ALL
          SELECT L."ItemCode", '尾差偏大：' || IFNULL(S."ObjType" || '-' || S."DocNum" || '-' || TO_NVARCHAR(S."LineNum"), 'LineId ' || L."LineId")
                 || ' 挤入尾差 ' || TO_NVARCHAR(ROUND(L."Amount" - ROUND(L."Qty" * I."P", 2), 2))
            FROM "MTC_CA_R_LINE" L
            JOIN :itm I ON I."ItemCode" = L."ItemCode"
            LEFT JOIN "MTC_CA_S_LINE" S ON S."RunId" = L."RunId" AND S."LineId" = L."LineId"
           WHERE L."RunId" = :RunId AND (L."RuleId" = 'RND-01' OR L."PriceSrc" LIKE '%含期末尾差%')
             AND ABS(L."Amount" - ROUND(L."Qty" * I."P", 2)) >= :tailWarn
          -- ③ 期末数量 0 但金额不为 0（超过 TAIL_MAX，未结转）
          UNION ALL
          SELECT "ItemCode", '数量 0 金额不为 0：期末金额 ' || TO_NVARCHAR(ROUND("EndAmount", 2)) || '（超过尾差上限，未结转）'
            FROM :itm WHERE "EndQty" = 0 AND ROUND("EndAmount", 2) <> 0
          -- ④ 期末数量与金额方向不一致：有数量没金额、金额为负、负库存
          UNION ALL
          SELECT "ItemCode", CASE WHEN "EndQty" < 0 THEN '负库存：' WHEN "EndAmount" = 0 THEN '有数量无金额：' ELSE '金额为负：' END
                 || '期末数量 ' || TO_NVARCHAR(ROUND("EndQty", 6)) || '，金额 ' || TO_NVARCHAR(ROUND("EndAmount", 2))
            FROM :itm WHERE ("EndQty" > 0 AND "EndAmount" <= 0) OR "EndQty" < 0
          -- ⑤ 期末单价偏离本期加权单价（期末金额 ÷ 期末数量 与 P 相差超过 PRICE_JUMP_PCT，且金额差超过 PRICE_JUMP_AMT）
          UNION ALL
          SELECT "ItemCode", '期末单价偏离：期末单价 ' || TO_NVARCHAR(ROUND("EndAmount" / NULLIF("EndQty", 0), 4)) || '，本期加权单价 ' || TO_NVARCHAR(ROUND("P", 4))
                 || '，金额差 ' || TO_NVARCHAR(ROUND("EndAmount" - "EndQty" * "P", 2))
            FROM :itm
           WHERE "EndQty" > 0 AND "EndAmount" > 0 AND "P" > 0
             AND ABS("EndAmount" / NULLIF("EndQty", 0) - "P") / NULLIF("P", 0) * 100 > :pjPct AND ABS("EndAmount" - "EndQty" * "P") > :pjAmt
          -- ⑥ 价格波动：本期加权单价与期初单价相差超过 PRICE_JUMP_PCT，且影响金额（单价差 × 本期出库和期末数量）超过 PRICE_JUMP_AMT
          UNION ALL
          SELECT "ItemCode", '价格波动：期初单价 ' || TO_NVARCHAR(ROUND("OpenAmt" / NULLIF("OpenQty", 0), 4)) || ' → 本期 ' || TO_NVARCHAR(ROUND("P", 4))
                 || '（' || CASE WHEN "P" > "OpenAmt" / NULLIF("OpenQty", 0) THEN '+' ELSE '' END
                 || TO_NVARCHAR(ROUND(("P" - "OpenAmt" / NULLIF("OpenQty", 0)) / NULLIF("OpenAmt" / NULLIF("OpenQty", 0), 0) * 100, 1)) || '%），影响金额约 '
                 || TO_NVARCHAR(ROUND(ABS("P" - "OpenAmt" / NULLIF("OpenQty", 0)) * (ABS("OutQty") + ABS("EndQty")), 2))
            FROM :itm
           WHERE "OpenQty" > 0 AND "OpenAmt" > 0
             AND ABS("P" - "OpenAmt" / NULLIF("OpenQty", 0)) / NULLIF("OpenAmt" / NULLIF("OpenQty", 0), 0) * 100 > :pjPct
             AND ABS("P" - "OpenAmt" / NULLIF("OpenQty", 0)) * (ABS("OutQty") + ABS("EndQty")) > :pjAmt
          -- ⑦ 有数量无金额的单据行（物料本期单价大于 0）
          UNION ALL
          SELECT L."ItemCode", '有数量无金额的单据行 ' || COUNT(*) || ' 行，数量合计 ' || TO_NVARCHAR(ROUND(SUM(L."Qty"), 6))
            FROM "MTC_CA_R_LINE" L JOIN :itm I ON I."ItemCode" = L."ItemCode"
           WHERE L."RunId" = :RunId AND L."Qty" <> 0 AND L."Amount" = 0 AND I."P" > 0
           GROUP BY L."ItemCode";
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-14', :t14, NULL);

    -- BOOT-01 期初承接核对（仅本期期初取自承接账期时）
    t08 = SELECT "OrderType" || '-DocEntry ' || "OrderEntry" || IFNULL('-' || "ItemCode", '') AS "KeyCode",
                 "Issue" || '：' || TO_NVARCHAR(ROUND("Value1", 2)) || ' / ' || TO_NVARCHAR(ROUND("Value2", 2)) AS "Info"
            FROM "MTC_CA_V_BOOT_CHECK" WHERE "FcCode" = :boot AND :prev = :boot;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'BOOT-01', :t08, NULL);

    SELECT COUNT(*) INTO FailCnt FROM "MTC_CA_R_CHECK" WHERE "RunId" = :RunId AND "Stage" = 'POST' AND "Result" = 'FAIL';

    -- 指标快照（每次运行都保留，用于比较两次运行）
    INSERT INTO "MTC_CA_RUN_KPI" ("RunId", "KpiType", "KeyCode", "Value")
    SELECT :RunId, 'ITEM_PRICE', "ItemCode", "PMat" + "PMfg" + "PLab" + "PSub" FROM "MTC_CA_R_ITEM" WHERE "RunId" = :RunId
    UNION ALL
    SELECT :RunId, 'ITEM_END_AMT', "ItemCode", "EndAmount" FROM "MTC_CA_R_ITEM" WHERE "RunId" = :RunId AND "EndAmount" <> 0
    UNION ALL
    SELECT :RunId, 'ORDER_COST', "OrderType" || '-' || "OrderEntry", "CostAmt" FROM "MTC_CA_R_ORDER" WHERE "RunId" = :RunId AND "CostAmt" <> 0
    UNION ALL
    SELECT :RunId, 'ORDER_WIP', "OrderType" || '-' || "OrderEntry", "WipAmt" FROM "MTC_CA_R_ORDER" WHERE "RunId" = :RunId AND "WipAmt" <> 0
    UNION ALL
    SELECT :RunId, 'POOL', "PoolCode" || '-' || "Elem", SUM("Amount") FROM "MTC_CA_R_POOL" WHERE "RunId" = :RunId GROUP BY "PoolCode", "Elem"
    UNION ALL
    SELECT :RunId, 'TOTAL_END_AMT', '', IFNULL(SUM("EndAmount"), 0) FROM "MTC_CA_R_ITEM" WHERE "RunId" = :RunId
    UNION ALL
    SELECT :RunId, 'TOTAL_WIP', '', IFNULL(SUM("WipAmt"), 0) FROM "MTC_CA_R_ORDER" WHERE "RunId" = :RunId
    UNION ALL
    SELECT :RunId, 'TOTAL_CLOSEDIF', '', IFNULL(SUM("CloseDifAmt"), 0) FROM "MTC_CA_R_ORDER" WHERE "RunId" = :RunId;
END
@@
-- P65：新旧比对（旧框架同一账期已运行时）。差额 > 0.01 的写 R_CMP，原因先记 UNEXPLAINED，逐项归因
CREATE OR REPLACE PROCEDURE "MTC_CA_P65_COMPARE" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE n BIGINT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    RowCnt := 0;
    SELECT COUNT(*) INTO n FROM "MTC_COST_0301_INVNT" WHERE "FcCode" = :fc AND "CostCode" = '20';
    IF :n = 0 THEN
        RETURN;
    END IF;

    -- 旧单价（用户 2026-10-13）：旧 0401 最后的“91 写入”把 Price 改成期末结存单价，期末数量为 0 时为空；
    -- 所以期末数量不为 0 取 Price，为 0 取 Out_Price（出库金额 ÷ 出库数量）。两个都没有的不比单价，只比期末金额
    oldItem = SELECT "ItemCode", SUM(IFNULL("QM_Amount", 0)) AS "EndAmt",
                     MAX(CASE WHEN IFNULL("QM_Qty", 0) <> 0 THEN "Price" ELSE "Out_Price" END) AS "Price",
                     MAX(CASE WHEN IFNULL("QM_Qty", 0) <> 0 THEN '旧值取 0301.Price（期末单价）' ELSE '旧值取 0301.Out_Price（期末数量为 0，用出库单价）' END) AS "PriceFrom"
                FROM "MTC_COST_0301_INVNT" WHERE "FcCode" = :fc AND "CostCode" = '20' GROUP BY "ItemCode";
    oldOrd = SELECT IFNULL("DocType", '202') AS "OrderType", TO_INTEGER("WorEntry") AS "OrderEntry", SUM(IFNULL("Amount", 0)) AS "Cost"
               FROM "MTC_COST_0321_OWOR_SUM"
              WHERE "FcCode" = :fc AND TO_NVARCHAR("WorEntry") LIKE_REGEXPR '^[0-9]+$'
              GROUP BY IFNULL("DocType", '202'), TO_INTEGER("WorEntry");
    oldWip = SELECT "DocType" AS "OrderType", "WorEntry" AS "OrderEntry", SUM(IFNULL("在产品新", 0)) AS "Wip"
               FROM "MTC_COST_0322_OWOR_ZCP" WHERE "期间" = :fc GROUP BY "DocType", "WorEntry";

    INSERT INTO "MTC_CA_R_CMP" ("FcCode", "RunType", "Scenario", "RunId", "Kind", "KeyCode", "NewVal", "OldVal", "Diff", "Note")
    SELECT :fc, :rt, :scen, :RunId, 'ITEM_END', K."ItemCode", IFNULL(I."EndAmount", 0), IFNULL(O."EndAmt", 0),
           IFNULL(I."EndAmount", 0) - IFNULL(O."EndAmt", 0), CAST(NULL AS NVARCHAR(500))
      FROM (SELECT "ItemCode" FROM "MTC_CA_R_ITEM" WHERE "RunId" = :RunId UNION SELECT "ItemCode" FROM :oldItem) K
      LEFT JOIN "MTC_CA_R_ITEM" I ON I."RunId" = :RunId AND I."ItemCode" = K."ItemCode"
      LEFT JOIN :oldItem O ON O."ItemCode" = K."ItemCode"
     WHERE ABS(IFNULL(I."EndAmount", 0) - IFNULL(O."EndAmt", 0)) > 0.01
    UNION ALL
    SELECT :fc, :rt, :scen, :RunId, 'ITEM_PRICE', I."ItemCode", I."PMat" + I."PMfg" + I."PLab" + I."PSub", O."Price",
           I."PMat" + I."PMfg" + I."PLab" + I."PSub" - O."Price", O."PriceFrom"
      FROM "MTC_CA_R_ITEM" I JOIN :oldItem O ON O."ItemCode" = I."ItemCode"
     WHERE I."RunId" = :RunId AND O."Price" IS NOT NULL AND ABS(I."PMat" + I."PMfg" + I."PLab" + I."PSub" - O."Price") > 0.0001
    UNION ALL
    SELECT :fc, :rt, :scen, :RunId, 'ORDER_COST', K."OrderType" || '-' || K."OrderEntry", IFNULL(N."CostAmt", 0), IFNULL(O."Cost", 0),
           IFNULL(N."CostAmt", 0) - IFNULL(O."Cost", 0), NULL
      FROM (SELECT "OrderType", "OrderEntry" FROM "MTC_CA_R_ORDER" WHERE "RunId" = :RunId AND "RecvQty" <> 0
            UNION SELECT "OrderType", "OrderEntry" FROM :oldOrd) K
      LEFT JOIN "MTC_CA_R_ORDER" N ON N."RunId" = :RunId AND N."OrderType" = K."OrderType" AND N."OrderEntry" = K."OrderEntry"
      LEFT JOIN :oldOrd O ON O."OrderType" = K."OrderType" AND O."OrderEntry" = K."OrderEntry"
     WHERE ABS(IFNULL(N."CostAmt", 0) - IFNULL(O."Cost", 0)) > 0.01
    UNION ALL
    SELECT :fc, :rt, :scen, :RunId, 'WIP', K."OrderType" || '-' || K."OrderEntry", IFNULL(N."WipAmt", 0), IFNULL(O."Wip", 0),
           IFNULL(N."WipAmt", 0) - IFNULL(O."Wip", 0), NULL
      FROM (SELECT "OrderType", "OrderEntry" FROM "MTC_CA_R_ORDER" WHERE "RunId" = :RunId AND "WipAmt" <> 0
            UNION SELECT "OrderType", "OrderEntry" FROM :oldWip) K
      LEFT JOIN "MTC_CA_R_ORDER" N ON N."RunId" = :RunId AND N."OrderType" = K."OrderType" AND N."OrderEntry" = K."OrderEntry"
      LEFT JOIN :oldWip O ON O."OrderType" = K."OrderType" AND O."OrderEntry" = K."OrderEntry"
     WHERE ABS(IFNULL(N."WipAmt", 0) - IFNULL(O."Wip", 0)) > 0.01;
    RowCnt := ::ROWCOUNT;
END
