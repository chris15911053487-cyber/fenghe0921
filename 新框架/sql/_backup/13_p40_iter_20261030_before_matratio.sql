-- =====================================================================
-- 新成本框架 第 2 期：P40 迭代（设计稿 4、4.2–4.4）
-- 替代：0311 / 0312（费用池与分摊）、0306（委外加工费）、0401_CAL 六段 + 返工段、0402_CAL_OWOR(_30)、
--       CO4001 / CO4011（在产品、关单差异）、“算两遍”。
-- 每轮：P41 按当前单价给加权价行定价 → P42 费用池 → P43 分摊 → P45 逐级（L = 0 … 最高层）→ P47 收敛判断。
-- 每轮只把“当前物料单价、上一轮关单差异”作为输入，结果只取决于快照和参数，与运行次数无关。
-- =====================================================================

-- P41：加权价类行（WAVG）按物料当前单价定价；公摊材料行也在其中
CREATE OR REPLACE PROCEDURE "MTC_CA_P41_PRICE" (IN RunId BIGINT, IN Iter INT)
LANGUAGE SQLSCRIPT AS
BEGIN
    UPDATE T0 SET T0."MatAmt" = ROUND(I."PMat" * T0."Qty", 2), T0."MfgAmt" = ROUND(I."PMfg" * T0."Qty", 2),
                  T0."LabAmt" = ROUND(I."PLab" * T0."Qty", 2), T0."SubAmt" = ROUND(I."PSub" * T0."Qty", 2),
                  T0."Amount" = ROUND(I."PMat" * T0."Qty", 2) + ROUND(I."PMfg" * T0."Qty", 2)
                              + ROUND(I."PLab" * T0."Qty", 2) + ROUND(I."PSub" * T0."Qty", 2),
                  -- 退货、取消单、形态转换的兜底说明保留，其余每轮刷新单价来源；上一轮挤尾差的标记去掉
                  T0."PriceSrc" = CASE WHEN T0."RuleId" IS NULL OR T0."RuleId" = 'WAVG-01'
                                       THEN '物料本期加权单价（' || I."PriceSrc" || '）' ELSE REPLACE(T0."PriceSrc", '；含期末尾差（RND-01）', '') END,
                  T0."RuleId" = IFNULL(T0."RuleId", 'WAVG-01'), T0."Iter" = :Iter
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_R_ITEM" I ON I."RunId" = T0."RunId" AND I."ItemCode" = T0."ItemCode"
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'WAVG';

    -- 尾差（RND-01，2026-10-13）：逐行 ROUND(单价 × 数量, 2) 后，出光的物料期末会剩 ±0.01（如 101100111：5 × 1527.555 = 7637.775 → 7637.78，
    -- 9 × 1527.555 = 13747.995 → 13748.00，合计多出 0.01）。在这里挤进数量最大的加权价出库行，公摊材料行也可以挤——在 P42 之前，
    -- 费用池和分摊用的就是挤过的金额；P50 只能挤非公摊行（那时费用已分摊），只给没收敛的情况兜底。形态转换转出行不挤（P45 按层重新定价）。
    -- 用的入库金额是上一轮的，收敛后与最终结果一致。
    -- 2026-10-13：候选行加上订单领料（ISSUE）。全部领给订单出光的物料（如 040600093）原来没有可挤的行，期末剩 0.01；
    -- 数量最大的出库行是领料行时这里不挤，由 P45 在该订单所在层给领料定价后挤，再汇总订单材料。
    tail = SELECT I."ItemCode",
                  I."OpenMat" + S."Mat" AS "TMat", I."OpenMfg" + S."Mfg" AS "TMfg", I."OpenLab" + S."Lab" AS "TLab", I."OpenSub" + S."Sub" AS "TSub"
             FROM "MTC_CA_R_ITEM" I
             JOIN (SELECT "ItemCode", SUM("Qty") AS "Qty", SUM("MatAmt") AS "Mat", SUM("MfgAmt") AS "Mfg", SUM("LabAmt") AS "Lab", SUM("SubAmt") AS "Sub"
                     FROM "MTC_CA_R_LINE" WHERE "RunId" = :RunId GROUP BY "ItemCode") S ON S."ItemCode" = I."ItemCode"
            WHERE I."RunId" = :RunId AND I."OpenQty" + S."Qty" = 0
              AND (I."OpenMat" + S."Mat" <> 0 OR I."OpenMfg" + S."Mfg" <> 0 OR I."OpenLab" + S."Lab" <> 0 OR I."OpenSub" + S."Sub" <> 0);
    cand = SELECT L."LineId", L."Cat", T."TMat", T."TMfg", T."TLab", T."TSub",
                  ROW_NUMBER() OVER (PARTITION BY L."ItemCode" ORDER BY ABS(L."Qty") DESC, L."LineId") AS "Rn"
             FROM "MTC_CA_R_LINE" L
             JOIN :tail T ON T."ItemCode" = L."ItemCode"
            WHERE L."RunId" = :RunId AND L."Cat" IN ('WAVG', 'ISSUE') AND L."Qty" < 0
              AND L."LineId" NOT IN (SELECT "SrcLineId" FROM "MTC_CA_R_PAIR" WHERE "RunId" = :RunId AND "SrcLineId" IS NOT NULL);
    UPDATE T0 SET T0."MatAmt" = T0."MatAmt" - C."TMat", T0."MfgAmt" = T0."MfgAmt" - C."TMfg",
                  T0."LabAmt" = T0."LabAmt" - C."TLab", T0."SubAmt" = T0."SubAmt" - C."TSub",
                  T0."Amount" = T0."Amount" - C."TMat" - C."TMfg" - C."TLab" - C."TSub",
                  T0."PriceSrc" = T0."PriceSrc" || '；含期末尾差（RND-01）'
      FROM "MTC_CA_R_LINE" T0
      JOIN :cand C ON C."LineId" = T0."LineId" AND C."Rn" = 1 AND C."Cat" = 'WAVG'
     WHERE T0."RunId" = :RunId;
END
@@
-- P42：费用池 = 固定部分（凭证、重估，P30 已写）+ 公摊材料（按当前单价）+ 关单差异（上一轮，全部进 CLOSE_DIF_POOL）
CREATE OR REPLACE PROCEDURE "MTC_CA_P42_POOL" (IN RunId BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE clsPool NVARCHAR(20);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    clsPool := "MTC_CA_F_PARAM"('CLOSE_DIF_POOL', :fc);

    DELETE FROM "MTC_CA_R_POOL" WHERE "RunId" = :RunId AND "Src" IN ('SHARED', 'CLOSEDIF');

    -- 公摊材料：出库为负，计入费用为正
    INSERT INTO "MTC_CA_R_POOL" ("FcCode", "RunType", "Scenario", "RunId", "PoolCode", "Elem", "Src", "Amount")
    SELECT :fc, :rt, :scen, :RunId, "PoolCode", 'MFG', 'SHARED', -SUM("Amount")
      FROM "MTC_CA_R_LINE"
     WHERE "RunId" = :RunId AND "IsShared" = 'Y'
     GROUP BY "PoolCode";

    INSERT INTO "MTC_CA_R_POOL" ("FcCode", "RunType", "Scenario", "RunId", "PoolCode", "Elem", "Src", "Amount")
    SELECT :fc, :rt, :scen, :RunId, :clsPool, 'MFG', 'CLOSEDIF', SUM("CloseDifAmt")
      FROM "MTC_CA_R_ORDER"
     WHERE "RunId" = :RunId
    HAVING SUM("CloseDifAmt") <> 0;
END
@@
-- P43：各池按“单位工时 × 本期入库数”一步分到池范围内本期有入库的订单；金额取 2 位，尾差挤最大行；
-- 制造、人工用同一权重（Q19）；返工单用产品的正常单位工时（Q18）；只分给本期净入库 > 0 的订单，净入库为负的由 PRE-19 报出（Q20）；
-- 池内没有可分摊订单的金额留在池里（未分摊，POST-03 报出，Q13）
CREATE OR REPLACE PROCEDURE "MTC_CA_P43_ALLOC" (IN RunId BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);

    DELETE FROM "MTC_CA_R_ALLOC" WHERE "RunId" = :RunId;

    elig = SELECT T."PoolCode", O."OrderType", O."OrderEntry", H."Hours", O."RecvQty", H."Hours" * O."RecvQty" AS "W"
             FROM "MTC_CA_R_ORDER" O
             JOIN "MTC_CA_V_ITEM_POOL" T ON T."RunId" = O."RunId" AND T."ItemCode" = O."ItemCode"
                                        AND LOCATE(T."WorTypes", ',' || O."WorType" || ',') > 0
             JOIN "MTC_CA_S_HOURS" H ON H."RunId" = O."RunId" AND H."ItemCode" = O."ItemCode"
            WHERE O."RunId" = :RunId AND O."RecvQty" > 0 AND H."Hours" <> 0;
    pools = SELECT "PoolCode", "Elem", SUM("Amount") AS "Amt"
              FROM "MTC_CA_R_POOL" WHERE "RunId" = :RunId GROUP BY "PoolCode", "Elem";
    raw = SELECT P."PoolCode", P."Elem", P."Amt", E."OrderType", E."OrderEntry", E."Hours", E."RecvQty", E."W",
                 E."W" / NULLIF(SUM(E."W") OVER (PARTITION BY P."PoolCode", P."Elem"), 0) AS "Ratio"
            FROM :pools P JOIN :elig E ON E."PoolCode" = P."PoolCode";
    rnd = SELECT R.*, ROUND(R."Amt" * R."Ratio", 2) AS "A",
                 ROUND(R."Amt", 2) - SUM(ROUND(R."Amt" * R."Ratio", 2)) OVER (PARTITION BY R."PoolCode", R."Elem") AS "Tail",
                 ROW_NUMBER() OVER (PARTITION BY R."PoolCode", R."Elem" ORDER BY ABS(R."W") DESC, R."OrderType", R."OrderEntry") AS "Rn"
            FROM :raw R WHERE R."Ratio" IS NOT NULL;

    INSERT INTO "MTC_CA_R_ALLOC" ("FcCode", "RunType", "Scenario", "RunId", "PoolCode", "Elem", "OrderType", "OrderEntry",
                                  "Hours", "RecvQty", "Weight", "Ratio", "Amount")
    SELECT :fc, :rt, :scen, :RunId, "PoolCode", "Elem", "OrderType", "OrderEntry", "Hours", "RecvQty", "W", "Ratio",
           "A" + CASE WHEN "Rn" = 1 THEN "Tail" ELSE 0 END
      FROM :rnd;

    UPDATE "MTC_CA_R_ORDER" SET "AllocMfg" = 0, "AllocLab" = 0 WHERE "RunId" = :RunId;
    UPDATE T0 SET T0."AllocMfg" = A."Mfg", T0."AllocLab" = A."Lab"
      FROM "MTC_CA_R_ORDER" T0
      JOIN (SELECT "OrderType", "OrderEntry",
                   SUM(CASE WHEN "Elem" = 'MFG' THEN "Amount" ELSE 0 END) AS "Mfg",
                   SUM(CASE WHEN "Elem" = 'LAB' THEN "Amount" ELSE 0 END) AS "Lab"
              FROM "MTC_CA_R_ALLOC" WHERE "RunId" = :RunId GROUP BY "OrderType", "OrderEntry") A
        ON A."OrderType" = T0."OrderType" AND A."OrderEntry" = T0."OrderEntry"
     WHERE T0."RunId" = :RunId;
END
@@
-- P45：第 Lv 层
--   a 本层订单的领料按子件当前单价定价（下层本轮已更新；同层 / 上层用上一轮，返工单靠迭代收敛，S2）；生产退料按订单该材料平均领料单价
--   b 订单 × 材料结转：本期有入库时 结转 = 累计领料 × r − 以前已结转（加工费 r 取 1）；在产品 = 累计领料 − 累计结转；本期关单的在产品转关单差异
--   c 订单完工成本 = 材料结转（四项）+ 分摊制造 / 人工 + 加工费结转
--   d 完工入库行按订单成本 × 行数量 ÷ 本期入库数，取 2 位，尾差挤数量最大的行
--   e 形态转换 I05 = −O05（B 的当前单价）；本层物料加权单价 =（期初 + 计价入库）÷（期初数量 + 计价入库数量）
CREATE OR REPLACE PROCEDURE "MTC_CA_P45_LEVEL" (IN RunId BIGINT, IN Lv INT, IN Iter INT)
LANGUAGE SQLSCRIPT AS
BEGIN
    -- a 领料
    UPDATE T0 SET T0."MatAmt" = ROUND(I."PMat" * T0."Qty", 2), T0."MfgAmt" = ROUND(I."PMfg" * T0."Qty", 2),
                  T0."LabAmt" = ROUND(I."PLab" * T0."Qty", 2), T0."SubAmt" = ROUND(I."PSub" * T0."Qty", 2),
                  T0."Amount" = ROUND(I."PMat" * T0."Qty", 2) + ROUND(I."PMfg" * T0."Qty", 2)
                              + ROUND(I."PLab" * T0."Qty", 2) + ROUND(I."PSub" * T0."Qty", 2),
                  T0."PriceSrc" = '子件当前单价（' || I."PriceSrc" || '）', T0."RuleId" = 'WAVG-01', T0."Iter" = :Iter
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_R_ORDER" O ON O."RunId" = T0."RunId" AND O."OrderType" = T0."OrderType" AND O."OrderEntry" = T0."OrderEntry"
      JOIN "MTC_CA_R_ITEM" I ON I."RunId" = T0."RunId" AND I."ItemCode" = T0."ItemCode"
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'ISSUE' AND O."iLevel" = :Lv;

    avg304 = SELECT M."OrderType", M."OrderEntry", M."ItemCode",
                    (M."OpenIssMat" + IFNULL(S."Mat", 0)) / NULLIF(M."OpenIssQty" + IFNULL(S."Qty", 0), 0) AS "UMat",
                    (M."OpenIssMfg" + IFNULL(S."Mfg", 0)) / NULLIF(M."OpenIssQty" + IFNULL(S."Qty", 0), 0) AS "UMfg",
                    (M."OpenIssLab" + IFNULL(S."Lab", 0)) / NULLIF(M."OpenIssQty" + IFNULL(S."Qty", 0), 0) AS "ULab",
                    (M."OpenIssSub" + IFNULL(S."Sub", 0)) / NULLIF(M."OpenIssQty" + IFNULL(S."Qty", 0), 0) AS "USub"
               FROM "MTC_CA_R_ORDER_MAT" M
               JOIN "MTC_CA_R_ORDER" O ON O."RunId" = M."RunId" AND O."OrderType" = M."OrderType" AND O."OrderEntry" = M."OrderEntry"
               LEFT JOIN (SELECT "OrderType", "OrderEntry", "ItemCode", -SUM("Qty") AS "Qty",
                                 -SUM("MatAmt") AS "Mat", -SUM("MfgAmt") AS "Mfg", -SUM("LabAmt") AS "Lab", -SUM("SubAmt") AS "Sub"
                            FROM "MTC_CA_R_LINE" WHERE "RunId" = :RunId AND "Cat" = 'ISSUE'
                           GROUP BY "OrderType", "OrderEntry", "ItemCode") S
                 ON S."OrderType" = M."OrderType" AND S."OrderEntry" = M."OrderEntry" AND S."ItemCode" = M."ItemCode"
              WHERE M."RunId" = :RunId AND O."iLevel" = :Lv;
    UPDATE T0 SET T0."MatAmt" = ROUND(IFNULL(A."UMat", I."PMat") * T0."Qty", 2), T0."MfgAmt" = ROUND(IFNULL(A."UMfg", I."PMfg") * T0."Qty", 2),
                  T0."LabAmt" = ROUND(IFNULL(A."ULab", I."PLab") * T0."Qty", 2), T0."SubAmt" = ROUND(IFNULL(A."USub", I."PSub") * T0."Qty", 2),
                  T0."Amount" = ROUND(IFNULL(A."UMat", I."PMat") * T0."Qty", 2) + ROUND(IFNULL(A."UMfg", I."PMfg") * T0."Qty", 2)
                              + ROUND(IFNULL(A."ULab", I."PLab") * T0."Qty", 2) + ROUND(IFNULL(A."USub", I."PSub") * T0."Qty", 2),
                  T0."PriceSrc" = CASE WHEN A."UMat" IS NULL THEN '订单没有领料可参考，按物料当前单价' ELSE '该订单该材料平均领料单价' END,
                  T0."RuleId" = 'RTN-01', T0."Iter" = :Iter
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_R_ORDER" O ON O."RunId" = T0."RunId" AND O."OrderType" = T0."OrderType" AND O."OrderEntry" = T0."OrderEntry"
      JOIN "MTC_CA_R_ITEM" I ON I."RunId" = T0."RunId" AND I."ItemCode" = T0."ItemCode"
      LEFT JOIN :avg304 A ON A."OrderType" = T0."OrderType" AND A."OrderEntry" = T0."OrderEntry" AND A."ItemCode" = T0."ItemCode"
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'RTN304' AND O."iLevel" = :Lv;

    -- a 尾差（RND-01，2026-10-13）：出光的物料，数量最大的出库行（选法同 P41）是本层订单的领料行时，尾差挤进这一行，
    -- 再在 b 汇总进订单材料。物料其他行的金额用当前值（以后层级的领料是上一轮的），收敛后与最终结果一致。
    ttail = SELECT I."ItemCode",
                  I."OpenMat" + S."Mat" AS "TMat", I."OpenMfg" + S."Mfg" AS "TMfg", I."OpenLab" + S."Lab" AS "TLab", I."OpenSub" + S."Sub" AS "TSub"
             FROM "MTC_CA_R_ITEM" I
             JOIN (SELECT "ItemCode", SUM("Qty") AS "Qty", SUM("MatAmt") AS "Mat", SUM("MfgAmt") AS "Mfg", SUM("LabAmt") AS "Lab", SUM("SubAmt") AS "Sub"
                     FROM "MTC_CA_R_LINE" WHERE "RunId" = :RunId GROUP BY "ItemCode") S ON S."ItemCode" = I."ItemCode"
            WHERE I."RunId" = :RunId AND I."OpenQty" + S."Qty" = 0
              AND (I."OpenMat" + S."Mat" <> 0 OR I."OpenMfg" + S."Mfg" <> 0 OR I."OpenLab" + S."Lab" <> 0 OR I."OpenSub" + S."Sub" <> 0);
    tcand = SELECT L."LineId", L."Cat", L."OrderType", L."OrderEntry", T."TMat", T."TMfg", T."TLab", T."TSub",
                  ROW_NUMBER() OVER (PARTITION BY L."ItemCode" ORDER BY ABS(L."Qty") DESC, L."LineId") AS "Rn"
             FROM "MTC_CA_R_LINE" L
             JOIN :ttail T ON T."ItemCode" = L."ItemCode"
            WHERE L."RunId" = :RunId AND L."Cat" IN ('WAVG', 'ISSUE') AND L."Qty" < 0
              AND L."LineId" NOT IN (SELECT "SrcLineId" FROM "MTC_CA_R_PAIR" WHERE "RunId" = :RunId AND "SrcLineId" IS NOT NULL);
    UPDATE T0 SET T0."MatAmt" = T0."MatAmt" - C."TMat", T0."MfgAmt" = T0."MfgAmt" - C."TMfg",
                  T0."LabAmt" = T0."LabAmt" - C."TLab", T0."SubAmt" = T0."SubAmt" - C."TSub",
                  T0."Amount" = T0."Amount" - C."TMat" - C."TMfg" - C."TLab" - C."TSub",
                  T0."PriceSrc" = T0."PriceSrc" || '；含期末尾差（RND-01）'
      FROM "MTC_CA_R_LINE" T0
      JOIN :tcand C ON C."LineId" = T0."LineId" AND C."Rn" = 1 AND C."Cat" = 'ISSUE'
      JOIN "MTC_CA_R_ORDER" O ON O."RunId" = T0."RunId" AND O."OrderType" = C."OrderType" AND O."OrderEntry" = C."OrderEntry"
     WHERE T0."RunId" = :RunId AND O."iLevel" = :Lv;

    -- b 订单 × 材料
    UPDATE T0 SET T0."IssMat" = S."Mat", T0."IssMfg" = S."Mfg", T0."IssLab" = S."Lab", T0."IssSub" = S."Sub"
      FROM "MTC_CA_R_ORDER_MAT" T0
      JOIN "MTC_CA_R_ORDER" O ON O."RunId" = T0."RunId" AND O."OrderType" = T0."OrderType" AND O."OrderEntry" = T0."OrderEntry"
      JOIN (SELECT "OrderType", "OrderEntry", "ItemCode",
                   -SUM("MatAmt") AS "Mat", -SUM("MfgAmt") AS "Mfg", -SUM("LabAmt") AS "Lab", -SUM("SubAmt") AS "Sub"
              FROM "MTC_CA_R_LINE" WHERE "RunId" = :RunId AND "Cat" IN ('ISSUE', 'RTN304')
             GROUP BY "OrderType", "OrderEntry", "ItemCode") S
        ON S."OrderType" = T0."OrderType" AND S."OrderEntry" = T0."OrderEntry" AND S."ItemCode" = T0."ItemCode"
     WHERE T0."RunId" = :RunId AND O."iLevel" = :Lv;

    -- 结转按 订单 × 材料 × 要素 取 2 位（用户 2026-10-14）：完工成本 = 各行结转之和，在产品 = 领料 − 结转，都是 2 位，与 PP05 / WW03 凭证逐笔一致
    UPDATE T0 SET
           T0."CarMat" = IFNULL(ROUND((T0."OpenIssMat" + T0."IssMat") * CASE WHEN O."RecvQty" = 0 THEN NULL WHEN T0."ItemCode" = '#SUBFEE' THEN 1 ELSE O."Ratio" END - T0."OpenCarMat", 2), 0),
           T0."CarMfg" = IFNULL(ROUND((T0."OpenIssMfg" + T0."IssMfg") * CASE WHEN O."RecvQty" = 0 THEN NULL WHEN T0."ItemCode" = '#SUBFEE' THEN 1 ELSE O."Ratio" END - T0."OpenCarMfg", 2), 0),
           T0."CarLab" = IFNULL(ROUND((T0."OpenIssLab" + T0."IssLab") * CASE WHEN O."RecvQty" = 0 THEN NULL WHEN T0."ItemCode" = '#SUBFEE' THEN 1 ELSE O."Ratio" END - T0."OpenCarLab", 2), 0),
           T0."CarSub" = IFNULL(ROUND((T0."OpenIssSub" + T0."IssSub") * CASE WHEN O."RecvQty" = 0 THEN NULL WHEN T0."ItemCode" = '#SUBFEE' THEN 1 ELSE O."Ratio" END - T0."OpenCarSub", 2), 0)
      FROM "MTC_CA_R_ORDER_MAT" T0
      JOIN "MTC_CA_R_ORDER" O ON O."RunId" = T0."RunId" AND O."OrderType" = T0."OrderType" AND O."OrderEntry" = T0."OrderEntry"
     WHERE T0."RunId" = :RunId AND O."iLevel" = :Lv;

    UPDATE T0 SET
           T0."ClsMat" = CASE WHEN O."ClosedInFc" = 'Y' THEN T0."OpenIssMat" + T0."IssMat" - T0."OpenCarMat" - T0."CarMat" ELSE 0 END,
           T0."ClsMfg" = CASE WHEN O."ClosedInFc" = 'Y' THEN T0."OpenIssMfg" + T0."IssMfg" - T0."OpenCarMfg" - T0."CarMfg" ELSE 0 END,
           T0."ClsLab" = CASE WHEN O."ClosedInFc" = 'Y' THEN T0."OpenIssLab" + T0."IssLab" - T0."OpenCarLab" - T0."CarLab" ELSE 0 END,
           T0."ClsSub" = CASE WHEN O."ClosedInFc" = 'Y' THEN T0."OpenIssSub" + T0."IssSub" - T0."OpenCarSub" - T0."CarSub" ELSE 0 END,
           T0."WipMat" = CASE WHEN O."ClosedInFc" = 'Y' THEN 0 ELSE T0."OpenIssMat" + T0."IssMat" - T0."OpenCarMat" - T0."CarMat" END,
           T0."WipMfg" = CASE WHEN O."ClosedInFc" = 'Y' THEN 0 ELSE T0."OpenIssMfg" + T0."IssMfg" - T0."OpenCarMfg" - T0."CarMfg" END,
           T0."WipLab" = CASE WHEN O."ClosedInFc" = 'Y' THEN 0 ELSE T0."OpenIssLab" + T0."IssLab" - T0."OpenCarLab" - T0."CarLab" END,
           T0."WipSub" = CASE WHEN O."ClosedInFc" = 'Y' THEN 0 ELSE T0."OpenIssSub" + T0."IssSub" - T0."OpenCarSub" - T0."CarSub" END
      FROM "MTC_CA_R_ORDER_MAT" T0
      JOIN "MTC_CA_R_ORDER" O ON O."RunId" = T0."RunId" AND O."OrderType" = T0."OrderType" AND O."OrderEntry" = T0."OrderEntry"
     WHERE T0."RunId" = :RunId AND O."iLevel" = :Lv;

    -- c 订单完工成本
    UPDATE "MTC_CA_R_ORDER"
       SET "CostMat" = 0, "CostMfg" = "AllocMfg", "CostLab" = "AllocLab", "CostSub" = 0, "WipAmt" = 0, "CloseDifAmt" = 0
     WHERE "RunId" = :RunId AND "iLevel" = :Lv;
    UPDATE T0 SET T0."CostMat" = S."CarMat", T0."CostMfg" = T0."AllocMfg" + S."CarMfg",
                  T0."CostLab" = T0."AllocLab" + S."CarLab", T0."CostSub" = S."CarSub",
                  T0."WipAmt" = S."Wip", T0."CloseDifAmt" = S."Cls"
      FROM "MTC_CA_R_ORDER" T0
      JOIN (SELECT "OrderType", "OrderEntry", SUM("CarMat") AS "CarMat", SUM("CarMfg") AS "CarMfg",
                   SUM("CarLab") AS "CarLab", SUM("CarSub") AS "CarSub",
                   SUM("WipMat" + "WipMfg" + "WipLab" + "WipSub") AS "Wip",
                   SUM("ClsMat" + "ClsMfg" + "ClsLab" + "ClsSub") AS "Cls"
              FROM "MTC_CA_R_ORDER_MAT" WHERE "RunId" = :RunId GROUP BY "OrderType", "OrderEntry") S
        ON S."OrderType" = T0."OrderType" AND S."OrderEntry" = T0."OrderEntry"
     WHERE T0."RunId" = :RunId AND T0."iLevel" = :Lv;
    UPDATE "MTC_CA_R_ORDER"
       SET "CostAmt" = "CostMat" + "CostMfg" + "CostLab" + "CostSub",
           "UnitCost" = ("CostMat" + "CostMfg" + "CostLab" + "CostSub") / NULLIF("RecvQty", 0)
     WHERE "RunId" = :RunId AND "iLevel" = :Lv;

    -- d 完工入库行
    UPDATE T0 SET T0."MatAmt" = CASE WHEN O."RecvQty" = 0 THEN 0 ELSE ROUND(O."CostMat" * T0."Qty" / O."RecvQty", 2) END,
                  T0."MfgAmt" = CASE WHEN O."RecvQty" = 0 THEN 0 ELSE ROUND(O."CostMfg" * T0."Qty" / O."RecvQty", 2) END,
                  T0."LabAmt" = CASE WHEN O."RecvQty" = 0 THEN 0 ELSE ROUND(O."CostLab" * T0."Qty" / O."RecvQty", 2) END,
                  T0."SubAmt" = CASE WHEN O."RecvQty" = 0 THEN 0 ELSE ROUND(O."CostSub" * T0."Qty" / O."RecvQty", 2) END,
                  T0."PriceSrc" = '订单本期完工成本', T0."RuleId" = 'WIP-01', T0."Iter" = :Iter
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_R_ORDER" O ON O."RunId" = T0."RunId" AND O."OrderType" = T0."OrderType" AND O."OrderEntry" = T0."OrderEntry"
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'RCPT' AND O."iLevel" = :Lv;
    tail = SELECT L."LineId",
                  ROUND(O."CostMat", 2) - SUM(L."MatAmt") OVER (PARTITION BY L."OrderType", L."OrderEntry") AS "TMat",
                  ROUND(O."CostMfg", 2) - SUM(L."MfgAmt") OVER (PARTITION BY L."OrderType", L."OrderEntry") AS "TMfg",
                  ROUND(O."CostLab", 2) - SUM(L."LabAmt") OVER (PARTITION BY L."OrderType", L."OrderEntry") AS "TLab",
                  ROUND(O."CostSub", 2) - SUM(L."SubAmt") OVER (PARTITION BY L."OrderType", L."OrderEntry") AS "TSub",
                  ROW_NUMBER() OVER (PARTITION BY L."OrderType", L."OrderEntry" ORDER BY ABS(L."Qty") DESC, L."LineId") AS "Rn"
             FROM "MTC_CA_R_LINE" L
             JOIN "MTC_CA_R_ORDER" O ON O."RunId" = L."RunId" AND O."OrderType" = L."OrderType" AND O."OrderEntry" = L."OrderEntry"
            WHERE L."RunId" = :RunId AND L."Cat" = 'RCPT' AND O."iLevel" = :Lv AND O."RecvQty" <> 0;
    UPDATE T0 SET T0."MatAmt" = T0."MatAmt" + X."TMat", T0."MfgAmt" = T0."MfgAmt" + X."TMfg",
                  T0."LabAmt" = T0."LabAmt" + X."TLab", T0."SubAmt" = T0."SubAmt" + X."TSub"
      FROM "MTC_CA_R_LINE" T0
      JOIN :tail X ON X."LineId" = T0."LineId" AND X."Rn" = 1
     WHERE T0."RunId" = :RunId;
    UPDATE T0 SET T0."Amount" = T0."MatAmt" + T0."MfgAmt" + T0."LabAmt" + T0."SubAmt"
      FROM "MTC_CA_R_LINE" T0
      JOIN "MTC_CA_R_ORDER" O ON O."RunId" = T0."RunId" AND O."OrderType" = T0."OrderType" AND O."OrderEntry" = T0."OrderEntry"
     WHERE T0."RunId" = :RunId AND T0."Cat" = 'RCPT' AND O."iLevel" = :Lv;

    -- e 形态转换：本层 A 的 I05 = −O05（B 按当前单价）
    trf = SELECT P."LineId", P."SrcLineId"
            FROM "MTC_CA_R_PAIR" P
            JOIN "MTC_CA_R_LINE" A ON A."RunId" = P."RunId" AND A."LineId" = P."LineId"
            JOIN "MTC_CA_R_ITEM" IA ON IA."RunId" = P."RunId" AND IA."ItemCode" = A."ItemCode"
           WHERE P."RunId" = :RunId AND P."PairType" = 'TRF' AND IA."iLevel" = :Lv;
    UPDATE T0 SET T0."MatAmt" = ROUND(I."PMat" * T0."Qty", 2), T0."MfgAmt" = ROUND(I."PMfg" * T0."Qty", 2),
                  T0."LabAmt" = ROUND(I."PLab" * T0."Qty", 2), T0."SubAmt" = ROUND(I."PSub" * T0."Qty", 2),
                  T0."Amount" = ROUND(I."PMat" * T0."Qty", 2) + ROUND(I."PMfg" * T0."Qty", 2)
                              + ROUND(I."PLab" * T0."Qty", 2) + ROUND(I."PSub" * T0."Qty", 2), T0."Iter" = :Iter
      FROM "MTC_CA_R_LINE" T0
      JOIN :trf X ON X."SrcLineId" = T0."LineId"
      JOIN "MTC_CA_R_ITEM" I ON I."RunId" = T0."RunId" AND I."ItemCode" = T0."ItemCode"
     WHERE T0."RunId" = :RunId;
    UPDATE T0 SET T0."MatAmt" = -B."MatAmt", T0."MfgAmt" = -B."MfgAmt", T0."LabAmt" = -B."LabAmt", T0."SubAmt" = -B."SubAmt",
                  T0."Amount" = -B."Amount", T0."PriceSrc" = '形态转换：= 转出行金额', T0."RuleId" = 'TRF-01', T0."Iter" = :Iter
      FROM "MTC_CA_R_LINE" T0
      JOIN :trf X ON X."LineId" = T0."LineId"
      JOIN "MTC_CA_R_LINE" B ON B."RunId" = T0."RunId" AND B."LineId" = X."SrcLineId"
     WHERE T0."RunId" = :RunId;

    -- e 本层物料加权单价
    UPDATE "MTC_CA_R_ITEM" SET "InQty" = 0, "InMat" = 0, "InMfg" = 0, "InLab" = 0, "InSub" = 0
     WHERE "RunId" = :RunId AND "iLevel" = :Lv;
    UPDATE T0 SET T0."InQty" = S."Qty", T0."InMat" = S."Mat", T0."InMfg" = S."Mfg", T0."InLab" = S."Lab", T0."InSub" = S."Sub"
      FROM "MTC_CA_R_ITEM" T0
      JOIN (SELECT "ItemCode", SUM("Qty") AS "Qty", SUM("MatAmt") AS "Mat", SUM("MfgAmt") AS "Mfg",
                   SUM("LabAmt") AS "Lab", SUM("SubAmt") AS "Sub"
              FROM "MTC_CA_R_LINE" WHERE "RunId" = :RunId AND "InVal" = 'Y' GROUP BY "ItemCode") S
        ON S."ItemCode" = T0."ItemCode"
     WHERE T0."RunId" = :RunId AND T0."iLevel" = :Lv;
    UPDATE "MTC_CA_R_ITEM"
       SET "PMat" = ("OpenMat" + "InMat") / ("OpenQty" + "InQty"), "PMfg" = ("OpenMfg" + "InMfg") / ("OpenQty" + "InQty"),
           "PLab" = ("OpenLab" + "InLab") / ("OpenQty" + "InQty"), "PSub" = ("OpenSub" + "InSub") / ("OpenQty" + "InQty"),
           "PriceSrc" = 'WAVG'
     WHERE "RunId" = :RunId AND "iLevel" = :Lv AND "OpenQty" + "InQty" > 0;
END
@@
-- P40：迭代到收敛或达到最大轮数
CREATE OR REPLACE PROCEDURE "MTC_CA_P40_ITERATE" (IN RunId BIGINT, OUT Converged NVARCHAR(1), OUT Iters INT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE maxIter INT; DECLARE convP DECIMAL(19,6); DECLARE convA DECIMAL(19,6);
    DECLARE maxLv INT; DECLARE lv INT;
    DECLARE k INT := 0;
    DECLARE lastPool DECIMAL(19,6); DECLARE newPool DECIMAL(19,6);
    DECLARE lastCls DECIMAL(19,6); DECLARE newCls DECIMAL(19,6);
    DECLARE dP DECIMAL(19,6); DECLARE nUnconv INT;
    DECLARE topN INT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    topN := TO_INTEGER(IFNULL("MTC_CA_F_PARAM"('ITER_TRACE_TOP', :fc), '30'));
    maxIter := TO_INTEGER(IFNULL("MTC_CA_F_PARAM"('MAX_ITER', :fc), '50'));
    convP := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('CONV_PRICE', :fc), '0.000001'), 19, 6);
    convA := TO_DECIMAL(IFNULL("MTC_CA_F_PARAM"('CONV_AMT', :fc), '0.01'), 19, 6);
    SELECT GREATEST(IFNULL(MAX("iLevel"), 0), 0) INTO maxLv FROM "MTC_CA_R_ITEM" WHERE "RunId" = :RunId;
    Converged := 'N';

    WHILE :k < :maxIter DO
        k := :k + 1;
        UPDATE "MTC_CA_R_ITEM" SET "LastPMat" = "PMat", "LastPMfg" = "PMfg", "LastPLab" = "PLab", "LastPSub" = "PSub"
         WHERE "RunId" = :RunId;
        SELECT IFNULL(SUM("Amount"), 0) INTO lastPool FROM "MTC_CA_R_POOL" WHERE "RunId" = :RunId;
        SELECT IFNULL(SUM("CloseDifAmt"), 0) INTO lastCls FROM "MTC_CA_R_ORDER" WHERE "RunId" = :RunId;

        -- 执行台进度（MTC_CA_P_LOG_NOTE 自治提交，页面轮询时能看到当前在第几轮、第几级）
        CALL "MTC_CA_P_LOG_NOTE"(:RunId, '第 ' || :k || ' 轮：加权价行定价（P41）');
        CALL "MTC_CA_P41_PRICE"(:RunId, :k);
        CALL "MTC_CA_P_LOG_NOTE"(:RunId, '第 ' || :k || ' 轮：费用池归集（P42）');
        CALL "MTC_CA_P42_POOL"(:RunId);
        CALL "MTC_CA_P_LOG_NOTE"(:RunId, '第 ' || :k || ' 轮：费用分摊（P43）');
        CALL "MTC_CA_P43_ALLOC"(:RunId);
        -- 这个 HANA 版本的 FOR 循环变量不能直接在 CALL 中引用（报 identifier must be declared），改用 WHILE
        lv := 0;
        WHILE :lv <= :maxLv DO
            CALL "MTC_CA_P_LOG_NOTE"(:RunId, '第 ' || :k || ' 轮：逐级结转第 ' || :lv || ' 级 / 共 0–' || :maxLv || ' 级（P45）');
            CALL "MTC_CA_P45_LEVEL"(:RunId, :lv, :k);
            lv := :lv + 1;
        END WHILE;

        SELECT IFNULL(SUM("Amount"), 0) INTO newPool FROM "MTC_CA_R_POOL" WHERE "RunId" = :RunId;
        SELECT IFNULL(SUM("CloseDifAmt"), 0) INTO newCls FROM "MTC_CA_R_ORDER" WHERE "RunId" = :RunId;
        SELECT IFNULL(MAX(GREATEST(ABS("PMat" - "LastPMat"), ABS("PMfg" - "LastPMfg"), ABS("PLab" - "LastPLab"), ABS("PSub" - "LastPSub"))), 0),
               SUM(CASE WHEN GREATEST(ABS("PMat" - "LastPMat"), ABS("PMfg" - "LastPMfg"), ABS("PLab" - "LastPLab"), ABS("PSub" - "LastPSub")) > :convP THEN 1 ELSE 0 END)
          INTO dP, nUnconv
          FROM "MTC_CA_R_ITEM" WHERE "RunId" = :RunId;

        -- 迭代日志自治提交：运行中执行台就能看到每一轮，计算出错回滚后也保留供排查
        BEGIN AUTONOMOUS TRANSACTION
            INSERT INTO "MTC_CA_RUN_ITER" ("RunId", "Iter", "MaxPriceDelta", "PoolDelta", "CloseDifDelta", "UnconvItems", "EndTime")
            VALUES (:RunId, :k, :dP, ROUND(:newPool - :lastPool, 2), ROUND(:newCls - :lastCls, 2), IFNULL(:nUnconv, 0), CURRENT_TIMESTAMP);
        END;
        -- 迭代明细（2026-10-29）：本轮单价变化最大的前 topN 个物料。R_ITEM 的本轮单价还没提交，自治事务看不到，所以在本事务里写，
        -- 和本轮结果一起在本轮末尾提交（2026-10-30）
        IF :topN > 0 AND :dP > :convP THEN
            INSERT INTO "MTC_CA_RUN_ITER_ITEM" ("RunId", "Iter", "Rk", "ItemCode", "iLevel", "PriceDelta", "Price", "LastPrice",
                                                "PMat", "PMfg", "PLab", "PSub", "OpenQty", "OpenAmt", "InQty", "InAmt", "PriceSrc")
            SELECT :RunId, :k, "Rk", "ItemCode", "iLevel", "D", "PMat" + "PMfg" + "PLab" + "PSub",
                   "LastPMat" + "LastPMfg" + "LastPLab" + "LastPSub", "PMat", "PMfg", "PLab", "PSub",
                   "OpenQty", "OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub", "InQty", "InMat" + "InMfg" + "InLab" + "InSub", "PriceSrc"
              FROM (SELECT I.*, ROW_NUMBER() OVER (ORDER BY I."D" DESC, I."ItemCode") AS "Rk"
                      FROM (SELECT T.*, GREATEST(ABS("PMat" - "LastPMat"), ABS("PMfg" - "LastPMfg"),
                                                 ABS("PLab" - "LastPLab"), ABS("PSub" - "LastPSub")) AS "D"
                              FROM "MTC_CA_R_ITEM" T WHERE T."RunId" = :RunId) I
                     WHERE I."D" > :convP)
             WHERE "Rk" <= :topN;
        END IF;
        CALL "MTC_CA_P_LOG_NOTE"(:RunId, '第 ' || :k || ' 轮完成，还有 ' || IFNULL(:nUnconv, 0) || ' 个物料单价未收敛');
        -- 每轮提交（2026-10-30，#14 发散到第 50 轮溢出、全部回滚后无从排查）：后面某一轮出错时，回滚的只是出错那一轮，
        -- R_* 停在最后一轮完成时的状态，和 MTC_CA_RUN_ITER_ITEM 对得上；P_RUN 出错时按 KEEP_NOCONV 保留供排查
        COMMIT;

        -- 本轮所用的关单差异（上一轮结果）与本轮算出的一致、单价不再变化，即收敛
        IF :dP <= :convP AND ABS(:newCls - :lastCls) <= :convA AND ABS(:newPool - :lastPool) <= :convA THEN
            Converged := 'Y';
            BREAK;
        END IF;
    END WHILE;
    Iters := :k;
END
