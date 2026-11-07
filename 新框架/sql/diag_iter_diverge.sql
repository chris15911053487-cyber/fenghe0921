-- =====================================================================
-- 排查：迭代不收敛 / 单价越算越大（2026-10-30，起因 #14 迭代 49 轮后第 50 轮金额溢出）
-- 只读，不进部署包。前提是这次运行的快照和中间结果还在：未收敛或 P40 及以后出错、参数 KEEP_NOCONV = Y、
-- 库上已执行 patch_20261029_noconv.sql 和 patch_20261030_failkeep.sql。
-- 用法：改掉每段 P 里的运行号，逐段执行；按数据边界只需反馈每段有没有返回行、几行，
-- 或者用导出脚本导出这次运行（R_ITEM / R_LINE / S_OPEN / RUN_ITER_ITEM 都会带上）交给 AI 看。
-- =====================================================================

-- ① 每轮放大多少倍：相邻两轮“最大单价变化”之比稳定在 1 以上就是发散；PoolDelta / CloseDifDelta 一起变大说明回路经过费用池 / 关单差异
WITH P AS (SELECT 14 AS "RunId" FROM DUMMY)
SELECT I."Iter", I."MaxPriceDelta", I."UnconvItems", I."PoolDelta", I."CloseDifDelta",
       ROUND(I."MaxPriceDelta" / NULLIF(LAG(I."MaxPriceDelta") OVER (ORDER BY I."Iter"), 0), 4) AS "放大倍数"
  FROM "MTC_CA_RUN_ITER" I, P
 WHERE I."RunId" = P."RunId"
 ORDER BY I."Iter";

-- ② 最后一轮单价变化最大的物料（MTC_CA_RUN_ITER_ITEM，每轮前 ITER_TRACE_TOP 个）：同一个物料每轮都在前面、单价成倍变化，就是源头或回路上的物料
WITH P AS (SELECT 14 AS "RunId" FROM DUMMY)
SELECT T."Iter", T."Rk", T."ItemCode", T."iLevel", T."LastPrice", T."Price",
       ROUND(T."Price" / NULLIF(T."LastPrice", 0), 4) AS "本轮 / 上轮",
       T."OpenQty", T."OpenAmt", T."InQty", T."InAmt", T."OpenQty" + T."InQty" AS "加权分母"
  FROM "MTC_CA_RUN_ITER_ITEM" T, P
 WHERE T."RunId" = P."RunId" AND T."Iter" = (SELECT MAX("Iter") FROM "MTC_CA_RUN_ITER_ITEM" WHERE "RunId" = P."RunId")
 ORDER BY T."Rk";

-- ③ 加权单价分母里“随单价变化”的入库占比过大（读代码推断的发散条件）：
--    单价 =（期初 + 计价入库）÷（期初数量 + 计价入库数量）；计价入库中完工入库（RCPT，含返工单自己加工自己）、生产退料（RTN304）、
--    形态转换入库（TRF_IN）的金额随本轮单价变化。其他数量（期初、采购、采购退货等）合计为负、分母仍大于 0 时，
--    随单价变化的数量 ÷ 分母 > 1，每轮放大。“倍数上限”> 1 的物料优先看。
WITH P AS (SELECT 14 AS "RunId" FROM DUMMY),
 L AS (SELECT L."ItemCode",
              SUM(CASE WHEN L."Cat" IN ('RCPT', 'RTN304', 'TRF_IN') THEN L."Qty" ELSE 0 END) AS "DepQty",
              SUM(CASE WHEN L."Cat" NOT IN ('RCPT', 'RTN304', 'TRF_IN') THEN L."Qty" ELSE 0 END) AS "FixQty"
         FROM "MTC_CA_R_LINE" L, P
        WHERE L."RunId" = P."RunId" AND L."InVal" = 'Y'
        GROUP BY L."ItemCode")
SELECT I."ItemCode", I."iLevel", I."OpenQty", L."FixQty", L."DepQty",
       I."OpenQty" + I."InQty" AS "加权分母",
       ROUND(L."DepQty" / NULLIF(I."OpenQty" + I."InQty", 0), 4) AS "倍数上限",
       I."PMat" + I."PMfg" + I."PLab" + I."PSub" AS "当前单价", I."PriceSrc"
  FROM "MTC_CA_R_ITEM" I
  JOIN P ON I."RunId" = P."RunId"
  JOIN L ON L."ItemCode" = I."ItemCode"
 WHERE I."OpenQty" + I."InQty" > 0 AND L."DepQty" > 0
   AND L."DepQty" / (I."OpenQty" + I."InQty") > 1
 ORDER BY L."DepQty" / (I."OpenQty" + I."InQty") DESC;

-- ④ 分母接近 0：计价数量合计大于 0 但不到计价入库数量绝对值合计的 1%，金额又不为 0，单价会被放大很多倍
WITH P AS (SELECT 14 AS "RunId" FROM DUMMY),
 L AS (SELECT L."ItemCode", SUM(ABS(L."Qty")) AS "AbsQty"
         FROM "MTC_CA_R_LINE" L, P WHERE L."RunId" = P."RunId" AND L."InVal" = 'Y' GROUP BY L."ItemCode")
SELECT I."ItemCode", I."iLevel", I."OpenQty", I."InQty", I."OpenQty" + I."InQty" AS "加权分母", L."AbsQty" AS "入库数量绝对值合计",
       I."OpenMat" + I."OpenMfg" + I."OpenLab" + I."OpenSub" + I."InMat" + I."InMfg" + I."InLab" + I."InSub" AS "加权金额",
       I."PMat" + I."PMfg" + I."PLab" + I."PSub" AS "当前单价"
  FROM "MTC_CA_R_ITEM" I
  JOIN P ON I."RunId" = P."RunId"
  JOIN L ON L."ItemCode" = I."ItemCode"
 WHERE I."OpenQty" + I."InQty" > 0
   AND I."OpenQty" + I."InQty" < 0.01 * (L."AbsQty" + ABS(I."OpenQty"))
   AND I."OpenMat" + I."OpenMfg" + I."OpenLab" + I."OpenSub" + I."InMat" + I."InMfg" + I."InLab" + I."InSub" <> 0
 ORDER BY 8 DESC;

-- ⑤ 期初异常：期初数量为负，或数量极小（绝对值 < 0.01）而金额不为 0。第 1 轮初值 = 期初金额 ÷ 期初数量
WITH P AS (SELECT 14 AS "RunId" FROM DUMMY)
SELECT O."ItemCode", O."Qty", O."MatAmt" + O."MfgAmt" + O."LabAmt" + O."SubAmt" AS "期初金额",
       (O."MatAmt" + O."MfgAmt" + O."LabAmt" + O."SubAmt") / NULLIF(O."Qty", 0) AS "期初单价",
       CASE WHEN O."Qty" < 0 THEN '期初负库存' ELSE '期初数量极小' END AS "情况"
  FROM "MTC_CA_S_OPEN" O, P
 WHERE O."RunId" = P."RunId"
   AND (O."Qty" < 0 OR (ABS(O."Qty") < 0.01 AND O."MatAmt" + O."MfgAmt" + O."LabAmt" + O."SubAmt" <> 0))
 ORDER BY ABS((O."MatAmt" + O."MfgAmt" + O."LabAmt" + O."SubAmt") / NULLIF(O."Qty", 0)) DESC;
