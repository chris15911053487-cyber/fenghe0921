/* =====================================================================
 * FH100 成本核算 · 勾稽校验与追溯查询（只读，不修改任何数据）
 *
 * 用法：每段查询都以 P（账期）开头，把 '2026-08' 改成要查的账期后单独执行。
 *       T 开头的追溯查询还要填物料编码或订单号。
 * 结果：C 开头的校验，正常情况下应返回 0 行（C11、C15、C16 是对照表，看各行是否一致）。
 * 顺序：建议按编号从小到大执行；越靠前越接近数据源头，先修上游再看下游。
 *
 * 每段头部格式（供关系图页面读取，请保留）：
 *   -- @check 编号 | 标题
 *   -- @step  所属步骤
 *   -- @ok    正常结果
 *   -- @bad   异常说明 / 下一步去哪查
 *   -- @nodes 关联节点
 *   -- @fields 关联字段
 * ===================================================================== */


-- @check C01 | 物料层级是否都在 0401 的计算范围内
-- @step 1 GetItemLevel
-- @ok 返回 0 行
-- @bad 有 -1 级（BOM 子件缺失或循环引用）或 6 级以上的物料，这些物料的订单不会计算完工成本，入库明细不会定价。查 OITT/ITT1 的 BOM。
-- @nodes p_level,t_coilv
-- @fields U_COILV.iLevel
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT L."iLevel", COUNT(*) AS "物料数", MIN(L."ItemCode") AS "示例物料"
FROM "U_COILV" L JOIN P ON L."FcCode" = P."FC"
WHERE L."iLevel" < 0 OR L."iLevel" > 5
GROUP BY L."iLevel";


-- @check C02 | 期初是否等于上期期末
-- @step 5 0301_INVNT
-- @ok 返回 0 行
-- @bad 期初与上期期末不一致，通常是上期在本期之后又重算过，需要按顺序重跑本期；2024-11 开账期和 2025-04 有手工期初，属于预期差异。
-- @nodes p0301,t_invnt,t_qc
-- @fields 0301_INVNT.QC_Qty,0301_INVNT.QC_Amount,0301_INVNT.QM_Qty,0301_INVNT.QM_Amount
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
     L AS (SELECT MAX(O."Code") AS "LC" FROM OFPR O, P WHERE O."Code" < P."FC")
SELECT C."ItemCode", C."ItemName",
       C."QC_Qty", Q."QM_Qty" AS "上期期末数量",
       C."QC_Amount", Q."QM_Amount" AS "上期期末金额",
       ROUND(IFNULL(C."QC_Amount",0) - IFNULL(Q."QM_Amount",0), 2) AS "金额差"
FROM "MTC_COST_0301_INVNT" C
JOIN P ON C."FcCode" = P."FC"
CROSS JOIN L
LEFT JOIN "MTC_COST_0301_INVNT" Q ON Q."FcCode" = L."LC" AND Q."ItemCode" = C."ItemCode" AND Q."CostCode" = C."CostCode"
WHERE C."CostCode" = '20'
  AND (ABS(IFNULL(C."QC_Qty",0) - IFNULL(Q."QM_Qty",0)) > 0.0001
    OR ABS(IFNULL(C."QC_Amount",0) - IFNULL(Q."QM_Amount",0)) > 0.01)
ORDER BY ABS(IFNULL(C."QC_Amount",0) - IFNULL(Q."QM_Amount",0)) DESC;


-- @check C03 | 有没有交易类型识别不了的库存变动
-- @step 6 0302 + 0303
-- @ok 返回 0 行
-- @bad 这些行的 TransCode 为空或不在 @MTC_COST_IOTYPE 中，0302/0401 汇总时会被静默忽略，导致期末数量与 B1 不一致。按 ObjType 查 MTC_VIEW_Document 是否覆盖了该单据类型，或收发货单表头 U_TrsName 是否为空。
-- @nodes p0302,t_dtl,v_doc,u_iotype,u_ciotrn,b_ivl
-- @fields 0302_INVNTDETAIL1.TransCode,MTC_VIEW_Document.TransCode
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT D."ObjType", IFNULL(D."TransCode",'(空)') AS "TransCode",
       COUNT(*) AS "行数", SUM(D."Quantity") AS "数量", SUM(D."Amount") AS "金额",
       MIN(D."DocEntry") AS "示例单据", MIN(D."ItemCode") AS "示例物料"
FROM "MTC_COST_0302_INVNTDETAIL1" D
JOIN P ON D."FcCode" = P."FC"
LEFT JOIN "@MTC_COST_IOTYPE" T ON T."Code" = D."TransCode"
WHERE T."Code" IS NULL
GROUP BY D."ObjType", IFNULL(D."TransCode",'(空)')
ORDER BY COUNT(*) DESC;


-- @check C04 | 期末库存数量是否与 B1 一致
-- @step 6 0302 + 0303
-- @ok 返回 0 行
-- @bad 成本表的期末数量和 B1 库存（OIVL，不含 S300 报废库）不一致。先看 C03（被忽略的行），再看 C02（期初），最后看该物料的 T01 明细。
-- @nodes t_invnt,b_ivl,p0302,p0401
-- @fields 0301_INVNT.QM_Qty,0302_INVNTDETAIL1.Quantity
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
     E AS (SELECT O."T_RefDate" AS "EDate" FROM OFPR O, P WHERE O."Code" = P."FC"),
     B AS (SELECT V."ItemCode",
                  SUM(V."InQty" - V."OutQty") AS "B1数量含S300",
                  SUM(CASE WHEN V."LocCode" <> 'S300' THEN V."InQty" - V."OutQty" ELSE 0 END) AS "B1数量"
           FROM OIVL V, E WHERE V."DocDate" <= E."EDate" GROUP BY V."ItemCode")
SELECT I."ItemCode", I."ItemName", I."iLevel", I."QM_Qty" AS "成本表期末数量",
       B."B1数量", B."B1数量含S300",
       IFNULL(I."QM_Qty",0) - IFNULL(B."B1数量",0) AS "差异"
FROM "MTC_COST_0301_INVNT" I
JOIN P ON I."FcCode" = P."FC"
LEFT JOIN B ON B."ItemCode" = I."ItemCode"
WHERE I."CostCode" = '20'
  AND ABS(IFNULL(I."QM_Qty",0) - IFNULL(B."B1数量",0)) > 0.0001
ORDER BY ABS(IFNULL(I."QM_Qty",0) - IFNULL(B."B1数量",0)) DESC;


-- @check C05 | 有没有数量不为 0 却没有定价的明细
-- @step 6 0302 + 0303 / 10 0401
-- @ok 返回 0 行
-- @bad Price 为 0 或空。外购料缺价看 @MTC_COST_QCPRICE1 是否维护；完工入库缺价看该订单 0321_OWOR_SUM（C10）；IsUpdatePrice 为空说明 0401 没有走到它，检查物料层级（C01）和 TransCode。
-- @nodes t_dtl,p0302,p0401,u_qcprice
-- @fields 0302_INVNTDETAIL1.Price,0302_INVNTDETAIL1.Amount,0302_INVNTDETAIL1.IsUpdatePrice
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT D."TransCode", D."iLevel", IFNULL(D."IsUpdatePrice",'(空)') AS "IsUpdatePrice",
       COUNT(*) AS "行数", SUM(D."Quantity") AS "数量",
       MIN(D."ItemCode") AS "示例物料", MIN(D."DocEntry") AS "示例单据"
FROM "MTC_COST_0302_INVNTDETAIL1" D
JOIN P ON D."FcCode" = P."FC"
WHERE IFNULL(D."Quantity",0) <> 0
  AND IFNULL(D."Price",0) = 0
  AND IFNULL(D."IsUpdatePrice",'') <> 'NoCost'
GROUP BY D."TransCode", D."iLevel", IFNULL(D."IsUpdatePrice",'(空)')
ORDER BY COUNT(*) DESC;


-- @check C06 | 进销存是否自身平衡
-- @step 10 0401 / 11 0501
-- @ok 返回 0 行
-- @bad 期初 + 入库 − 出库 ≠ 期末。说明 0401 最后一步没有跑完，或有人手工改过 0301_INVNT。重跑 0401、0501。
-- @nodes t_invnt,p0401,p0501
-- @fields 0301_INVNT.QC_Amount,0301_INVNT.In_Amount,0301_INVNT.Out_Amount,0301_INVNT.QM_Amount
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT I."ItemCode", I."ItemName",
       I."QC_Qty", I."In_Qty", I."Out_Qty", I."QM_Qty",
       I."QC_Amount", I."In_Amount", I."Out_Amount", I."QM_Amount",
       ROUND(IFNULL(I."QC_Amount",0) + IFNULL(I."In_Amount",0) - IFNULL(I."Out_Amount",0) - IFNULL(I."QM_Amount",0), 2) AS "金额差",
       IFNULL(I."QC_Qty",0) + IFNULL(I."In_Qty",0) - IFNULL(I."Out_Qty",0) - IFNULL(I."QM_Qty",0) AS "数量差"
FROM "MTC_COST_0301_INVNT" I
JOIN P ON I."FcCode" = P."FC"
WHERE I."CostCode" = '20'
  AND (ABS(IFNULL(I."QC_Amount",0) + IFNULL(I."In_Amount",0) - IFNULL(I."Out_Amount",0) - IFNULL(I."QM_Amount",0)) > 0.05
    OR ABS(IFNULL(I."QC_Qty",0) + IFNULL(I."In_Qty",0) - IFNULL(I."Out_Qty",0) - IFNULL(I."QM_Qty",0)) > 0.0001);


-- @check C07 | 负库存、负金额和期末零数量仍有金额
-- @step 11 0501
-- @ok 返回 0 行
-- @bad 负数量说明出库早于入库或漏了入库；数量为正金额为负通常是单价被前面某步算错（看 T01 的 PriceMemo）；数量为 0 金额不为 0 应已被 0501 的 MRV2 清掉，若仍存在说明 0501 未执行。
-- @nodes t_invnt,p0501,u_omrv
-- @fields 0301_INVNT.QM_Qty,0301_INVNT.QM_Amount,0301_INVNT.Price
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT I."ItemCode", I."ItemName", I."iLevel", I."QM_Qty", I."QM_Amount", I."Price",
       CASE WHEN I."QM_Qty" < 0 THEN '负库存数量'
            WHEN I."QM_Qty" > 0 AND I."QM_Amount" < 0 THEN '数量为正、金额为负'
            WHEN I."QM_Qty" = 0 AND ABS(I."QM_Amount") > 0.01 THEN '数量为 0、仍有金额'
            WHEN I."Price" < 0 THEN '单价为负' END AS "问题"
FROM "MTC_COST_0301_INVNT" I
JOIN P ON I."FcCode" = P."FC"
WHERE I."CostCode" = '20'
  AND (I."QM_Qty" < 0 OR (I."QM_Qty" > 0 AND I."QM_Amount" < 0)
    OR (I."QM_Qty" = 0 AND ABS(I."QM_Amount") > 0.01) OR I."Price" < 0)
ORDER BY ABS(I."QM_Amount") DESC;


-- @check C08 | 单价与上期相比是否异常波动
-- @step 6 0302 / 10 0401
-- @ok 返回 0 行（或只有能解释的物料）
-- @bad 单价变动超过 3 倍。用 T01 看这个物料本期的入库明细和 PriceMemo，确认是哪一步把价格带偏的；自制品继续往下追它的订单（T02）。
-- @nodes t_invnt,p0302,p0401
-- @fields 0301_INVNT.Price
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
     L AS (SELECT MAX(O."Code") AS "LC" FROM OFPR O, P WHERE O."Code" < P."FC")
SELECT C."ItemCode", C."ItemName", C."iLevel",
       Q."Price" AS "上期单价", C."Price" AS "本期单价",
       ROUND(C."Price" / NULLIF(Q."Price",0), 2) AS "倍数",
       C."In_Qty", C."In_Amount"
FROM "MTC_COST_0301_INVNT" C
JOIN P ON C."FcCode" = P."FC"
CROSS JOIN L
JOIN "MTC_COST_0301_INVNT" Q ON Q."FcCode" = L."LC" AND Q."ItemCode" = C."ItemCode" AND Q."CostCode" = C."CostCode"
WHERE C."CostCode" = '20' AND C."Price" > 0 AND Q."Price" > 0
  AND (C."Price" / Q."Price" > 3 OR C."Price" / Q."Price" < 1.0/3)
ORDER BY ABS(LN(C."Price" / Q."Price")) DESC;


-- @check C09 | 订单领料：订单行与出入库明细是否一致
-- @step 4 0321_OWOR / 10 0401
-- @ok 返回 0 行
-- @bad 数量差：0321 的领料数量来自 0201（只算 U_IsCost='Y' 仓库），明细来自 OIVL（排除 S300），两边仓库口径不同。金额差：0401 回写订单行时漏了某些行（IsUpdatePrice 已有值的行不会再写）。
-- @nodes t_owor1,t_dtl,p0321,p0401,t_0201
-- @fields 0321_OWOR1.IgeQty,0321_OWOR1.Amount,0302_INVNTDETAIL1.Amount
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
     A AS (SELECT O."DocType", O."WorEntry", MAX(O."WorNum") AS "WorNum",
                  SUM(O."IgeQty") AS "订单领料数量", SUM(O."Amount") AS "订单领料金额"
           FROM "MTC_COST_0321_OWOR1" O, P WHERE O."FcCode" = P."FC"
           GROUP BY O."DocType", O."WorEntry"),
     B AS (SELECT D."BaseType", TO_NVARCHAR(D."BaseEntry") AS "BaseEntry",
                  SUM(D."Quantity") AS "明细领料数量", SUM(D."Amount") AS "明细领料金额"
           FROM "MTC_COST_0302_INVNTDETAIL1" D, P
           WHERE D."FcCode" = P."FC" AND D."TransCode" IN ('O03','O07','O08','O09')
           GROUP BY D."BaseType", D."BaseEntry")
SELECT COALESCE(A."DocType", B."BaseType") AS "DocType", COALESCE(A."WorEntry", B."BaseEntry") AS "WorEntry", A."WorNum",
       A."订单领料数量", B."明细领料数量", A."订单领料金额", B."明细领料金额",
       ROUND(IFNULL(A."订单领料金额",0) - IFNULL(B."明细领料金额",0), 2) AS "金额差"
FROM A FULL OUTER JOIN B ON A."DocType" = B."BaseType" AND A."WorEntry" = B."BaseEntry"
WHERE ABS(IFNULL(A."订单领料数量",0) - IFNULL(B."明细领料数量",0)) > 0.0001
   OR ABS(IFNULL(A."订单领料金额",0) - IFNULL(B."明细领料金额",0)) > 0.05
ORDER BY ABS(IFNULL(A."订单领料金额",0) - IFNULL(B."明细领料金额",0)) DESC;


-- @check C10 | 完工入库：订单成本结果与入库明细是否一致
-- @step 10 0401
-- @ok 返回 0 行（允许几分钱的四舍五入差）
-- @bad 与报表 MTC_RPT_CO4004、检查 MTC_COST_PROC_CAL_1004_CHECK_LS 同口径（完工入库 = @U_CIOTRN.U_TransType='B01'，含 321/322/323/324/325 及 903 期初生产入库），这里只列出有差异的订单。0401 会把 2 分钱以内的尾差挤平，超过的就是实际问题。0321_OWOR_SUM 算出的完工金额没有完整落到入库明细。数量差同样来自 0201 与 OIVL 的仓库口径；金额差看该订单的 T02，重点看入库行的 IsUpdatePrice 是否为 IN01。
-- @nodes t_sum,t_dtl,p0401
-- @fields 0321_OWOR_SUM.Amount,0321_OWOR_SUM.Price,0302_INVNTDETAIL1.Amount
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
     A AS (SELECT S."DocType", S."WorEntry", MAX(S."WorNum") AS "WorNum", MAX(S."ItemCode") AS "ItemCode",
                  SUM(S."IgnQty") AS "成本完工数量", SUM(S."Amount") AS "成本完工金额"
           FROM "MTC_COST_0321_OWOR_SUM" S, P WHERE S."FcCode" = P."FC"
           GROUP BY S."DocType", S."WorEntry"),
     B AS (SELECT D."BaseType", TO_NVARCHAR(D."BaseEntry") AS "BaseEntry",
                  SUM(D."Quantity") AS "入库数量", SUM(D."Amount") AS "入库金额"
           FROM "MTC_COST_0302_INVNTDETAIL1" D
           JOIN P ON D."FcCode" = P."FC"
           JOIN "@U_CIOTRN" U ON U."Code" = D."BusiType" AND U."U_TransType" = 'B01'
           WHERE D."CostCode" = '20'
           GROUP BY D."BaseType", D."BaseEntry")
SELECT COALESCE(A."DocType", B."BaseType") AS "DocType", COALESCE(A."WorEntry", B."BaseEntry") AS "WorEntry",
       A."WorNum", A."ItemCode",
       A."成本完工数量", B."入库数量", A."成本完工金额", B."入库金额",
       ROUND(IFNULL(A."成本完工金额",0) - IFNULL(B."入库金额",0), 2) AS "金额差"
FROM A FULL OUTER JOIN B ON A."DocType" = B."BaseType" AND A."WorEntry" = B."BaseEntry"
WHERE ABS(IFNULL(A."成本完工数量",0) - IFNULL(B."入库数量",0)) > 0.0001
   OR ABS(IFNULL(A."成本完工金额",0) - IFNULL(B."入库金额",0)) > 1
ORDER BY ABS(IFNULL(A."成本完工金额",0) - IFNULL(B."入库金额",0)) DESC;


-- @check C11 | 费用从归集到订单是否守恒
-- @step 7 0311 / 8 0312 / 9 0306 / 10 0401
-- @ok 同一 CostCode 的 A、B、C、D 四行金额相等（允许几分钱差）
-- @bad C ≠ D 时用 C17 逐单定位。A > B：有费用没分出去（该车间对应物料组本期没有完工，或物料没有维护单位工时 @MTC_COST_TIME1），这部分费用直接丢失；B ≠ C：二次分到订单时出错；C ≠ D：0401 没有把订单费用写回。
-- @nodes t_exp,t_prc,t_owor2,t_owor,p0311,p0312,p0306,p0401,u_time
-- @fields 0311_PRODUCTEXP_ADD.Amount,0312_PRODUCTEXP_PRC.ExpAmt,0321_OWOR2.Amount,0321_OWOR.2ManExp,0321_OWOR.3LabAmount,0321_OWOR.4WWExp
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT "CostCode", "阶段", ROUND(SUM("金额"), 2) AS "金额" FROM (
  SELECT CASE WHEN E."ExpType" = '人工费用' THEN '40' ELSE '30' END AS "CostCode", 'A 0311 归集' AS "阶段", E."Amount" AS "金额"
  FROM "MTC_COST_0311_PRODUCTEXP_ADD" E, P WHERE E."FcCode" = P."FC" AND IFNULL(E."IsCal",'Y') = 'Y'
  UNION ALL
  SELECT R."CostCode", 'B 0312 分到物料', R."ExpAmt" FROM "MTC_COST_0312_PRODUCTEXP_PRC" R, P WHERE R."FcCode" = P."FC"
  UNION ALL
  SELECT W."CostCode", 'C 0321_OWOR2 分到订单', -1 * W."Amount" FROM "MTC_COST_0321_OWOR2" W, P WHERE W."FcCode" = P."FC"
  UNION ALL
  SELECT '40', 'D 0321_OWOR 订单成本', O."2ManExp" FROM "MTC_COST_0321_OWOR" O, P WHERE O."FcCode" = P."FC"
  UNION ALL
  SELECT '30', 'D 0321_OWOR 订单成本', O."3LabAmount" FROM "MTC_COST_0321_OWOR" O, P WHERE O."FcCode" = P."FC"
  UNION ALL
  SELECT '20', 'D 0321_OWOR 订单成本', O."4WWExp" FROM "MTC_COST_0321_OWOR" O, P WHERE O."FcCode" = P."FC"
) X
GROUP BY "CostCode", "阶段"
ORDER BY "CostCode", "阶段";


-- @check C12 | 有成本却没有完工的订单
-- @step 10 0401
-- @ok 返回 0 行
-- @bad 本期完工数为 0 但有成本，Price 为空，这些金额停在 0321_OWOR_SUM，不会结转到入库明细（多为本期分摊了费用但没完工的订单）。
-- @nodes t_sum,t_owor,p0401,p0312
-- @fields 0321_OWOR_SUM.Amount,0321_OWOR_SUM.Price,0321_OWOR.IgnQty
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT S."DocType", S."WorType", S."WorEntry", S."WorNum", S."ItemCode", S."iLevel",
       S."IgnQty", S."Amount", S."1Material", S."2ManExp", S."3LabAmount", S."4WWExp", S."Price"
FROM "MTC_COST_0321_OWOR_SUM" S
JOIN P ON S."FcCode" = P."FC"
WHERE IFNULL(S."IgnQty",0) = 0 AND ABS(IFNULL(S."Amount",0)) > 0.01
ORDER BY ABS(S."Amount") DESC;


-- @check C13 | 在产品：成本算法与明细表算法的差额
-- @step 12 CO4001 / 13 CO4011
-- @ok 每张订单差额接近 0
-- @bad 差额大的订单，就是 0402 结转在产品可能有偏差的订单。注意：0000 运行时 JZCY='Y' 已把差额挤进金额最大的材料，要看真实差额，先运行
--      CALL "MTC_RPT_CO4011"(0,'2026-08','生产工单','','','Y','N');
--      查完后再用 'Y','Y' 运行一次恢复。
-- @nodes t_zcp,t_zcp1,p4001,p4011,p0401
-- @fields 0322_OWOR_ZCP.在产品新,0322_OWOR_ZCP1.Amount
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT Z."DocType", Z."WorType", Z."WorEntry", Z."WorNum", Z."订单状态",
       Z."在产品新" AS "表头在产品", SUM(D."Amount") AS "明细合计",
       ROUND(IFNULL(SUM(D."Amount"),0) - IFNULL(Z."在产品新",0), 2) AS "差额"
FROM "MTC_COST_0322_OWOR_ZCP" Z
JOIN P ON Z."期间" = P."FC"
LEFT JOIN "MTC_COST_0322_OWOR_ZCP1" D ON D."FcCode" = Z."期间" AND D."DocType" = Z."DocType" AND D."WorEntry" = Z."WorEntry"
GROUP BY Z."DocType", Z."WorType", Z."WorEntry", Z."WorNum", Z."订单状态", Z."在产品新"
HAVING ABS(IFNULL(SUM(D."Amount"),0) - IFNULL(Z."在产品新",0)) > 1
ORDER BY ABS(IFNULL(SUM(D."Amount"),0) - IFNULL(Z."在产品新",0)) DESC;


-- @check C14 | 同一单据行是否被写入多次
-- @step 6 0302 + 0303
-- @ok 返回 0 行（MRV2 重估行除外）
-- @bad 同一条单据行出现多次，常见原因是视图按单号 DocNum 关联生产订单、单号重复导致行被放大。查该单据在 MTC_VIEW_Document 中返回几行。
-- @nodes t_dtl,v_doc,p0302
-- @fields 0302_INVNTDETAIL1.Quantity,0302_INVNTDETAIL1.Amount
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT D."ObjType", D."DocEntry", D."LineNum", D."ItemCode", COUNT(*) AS "行数", SUM(D."Quantity") AS "数量合计"
FROM "MTC_COST_0302_INVNTDETAIL1" D
JOIN P ON D."FcCode" = P."FC"
GROUP BY D."ObjType", D."DocEntry", D."LineNum", D."ItemCode"
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;


-- @check C15 | 凭证借贷是否平衡
-- @step 14 0801
-- @ok 每种凭证类型的借贷差为 0
-- @bad 借贷不平的凭证类型，看 0801 中对应 MRxx/PPxx 段的取数，以及 OGAR 科目确定是否缺科目。
-- @nodes t_jdt,p0801,b_gl
-- @fields 0801_TOOJDT.Debit,0801_TOOJDT.Credit
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT J."TransCode", MAX(J."TransName") AS "TransName", COUNT(*) AS "行数",
       SUM(J."Debit") AS "借方", SUM(J."Credit") AS "贷方",
       ROUND(SUM(J."Debit") - SUM(J."Credit"), 2) AS "借贷差",
       SUM(CASE WHEN IFNULL(J."AcctCode",'') = '' THEN 1 ELSE 0 END) AS "缺科目行数"
FROM "MTC_COST_0801_TOOJDT" J
JOIN P ON J."FcCode" = P."FC"
GROUP BY J."TransCode"
ORDER BY ABS(SUM(J."Debit") - SUM(J."Credit")) DESC;


-- @check C16 | 凭证金额与出入库明细对照
-- @step 14 0801
-- @ok 各凭证类型的借方合计与对应交易类型的明细金额（取绝对值）基本一致
-- @bad 差额大的凭证类型，按交易类型回到 0302 明细（T01）或检查 0801 对应段的过滤条件。PP05、WW03 的借方还包含费用，与明细不完全可比。
-- @nodes t_jdt,t_dtl,p0801
-- @fields 0801_TOOJDT.Debit,0302_INVNTDETAIL1.Amount
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
     M AS (SELECT 'PP01' AS "JE", 'O03' AS "TC" FROM DUMMY UNION ALL SELECT 'PP01','O07' FROM DUMMY
           UNION ALL SELECT 'WW01','O08' FROM DUMMY UNION ALL SELECT 'WW01','O09' FROM DUMMY
           UNION ALL SELECT 'IO01','I10' FROM DUMMY UNION ALL SELECT 'IO01','O10' FROM DUMMY
           UNION ALL SELECT 'IO02','I05' FROM DUMMY UNION ALL SELECT 'IO02','O05' FROM DUMMY
           UNION ALL SELECT 'YF01','I04' FROM DUMMY UNION ALL SELECT 'YF01','O04' FROM DUMMY
           UNION ALL SELECT 'DN01','O01' FROM DUMMY UNION ALL SELECT 'DN01','O06' FROM DUMMY
           UNION ALL SELECT 'PP05','I03' FROM DUMMY UNION ALL SELECT 'PP05','I07' FROM DUMMY
           UNION ALL SELECT 'WW03','I08' FROM DUMMY UNION ALL SELECT 'WW03','I09' FROM DUMMY),
     D AS (SELECT M."JE", SUM(CASE WHEN X."Amount" > 0 THEN X."Amount" ELSE 0 END) AS "明细正向",
                  SUM(CASE WHEN X."Amount" < 0 THEN -X."Amount" ELSE 0 END) AS "明细负向"
           FROM "MTC_COST_0302_INVNTDETAIL1" X JOIN P ON X."FcCode" = P."FC" JOIN M ON M."TC" = X."TransCode"
           WHERE IFNULL(X."IsUpdatePrice",'') <> 'NoCost'
           GROUP BY M."JE"),
     J AS (SELECT T."TransCode", SUM(T."Debit") AS "凭证借方", SUM(T."Credit") AS "凭证贷方"
           FROM "MTC_COST_0801_TOOJDT" T JOIN P ON T."FcCode" = P."FC" GROUP BY T."TransCode")
SELECT D."JE" AS "凭证类型", D."明细正向", D."明细负向", J."凭证借方", J."凭证贷方",
       ROUND(IFNULL(J."凭证借方",0) - (D."明细正向" + D."明细负向"), 2) AS "借方与明细绝对值之差"
FROM D LEFT JOIN J ON J."TransCode" = D."JE"
ORDER BY D."JE";


-- @check C17 | 订单费用逐单对照：0321_OWOR 与 0321_OWOR2
-- @step 10 0401
-- @ok 返回 0 行
-- @bad C11 的 D 行大于 C 行时，用它定位是哪些订单。已知原因：0401 在 iLevel 3、4、5 汇总订单材料和费用时只按 WorEntry 关联、没有带 DocType，B1 生产订单（202）和返工单（MTC_OWOR）DocEntry 相同时，费用被重复计入 202 订单。若“同号的另一类订单”列为 Y，即为此原因。
-- @nodes t_owor,t_owor2,p0401,t_sum
-- @fields 0321_OWOR.2ManExp,0321_OWOR.3LabAmount,0321_OWOR.4WWExp,0321_OWOR2.Amount
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
     C AS (SELECT W."DocType", W."WorEntry",
                  -1 * SUM(CASE WHEN W."CostCode" = '40' THEN W."Amount" ELSE 0 END) AS "人工",
                  -1 * SUM(CASE WHEN W."CostCode" = '30' THEN W."Amount" ELSE 0 END) AS "制造",
                  -1 * SUM(CASE WHEN W."CostCode" = '20' THEN W."Amount" ELSE 0 END) AS "委外"
           FROM "MTC_COST_0321_OWOR2" W, P WHERE W."FcCode" = P."FC"
           GROUP BY W."DocType", W."WorEntry")
SELECT O."DocType", O."WorType", O."WorEntry", O."WorNum", O."ItemCode", L."iLevel",
       O."2ManExp" AS "订单人工", C."人工" AS "分摊人工", ROUND(IFNULL(O."2ManExp",0) - IFNULL(C."人工",0), 2) AS "人工差",
       O."3LabAmount" AS "订单制造", C."制造" AS "分摊制造", ROUND(IFNULL(O."3LabAmount",0) - IFNULL(C."制造",0), 2) AS "制造差",
       O."4WWExp" AS "订单委外", C."委外" AS "分摊委外", ROUND(IFNULL(O."4WWExp",0) - IFNULL(C."委外",0), 2) AS "委外差",
       CASE WHEN EXISTS (SELECT 1 FROM "MTC_COST_0321_OWOR" X
                         WHERE X."FcCode" = O."FcCode" AND X."WorEntry" = O."WorEntry" AND X."DocType" <> O."DocType")
            THEN 'Y' ELSE 'N' END AS "同号的另一类订单"
FROM "MTC_COST_0321_OWOR" O
JOIN P ON O."FcCode" = P."FC"
LEFT JOIN C ON C."DocType" = O."DocType" AND C."WorEntry" = O."WorEntry"
LEFT JOIN "U_COILV" L ON L."FcCode" = O."FcCode" AND L."ItemCode" = O."ItemCode"
WHERE ABS(IFNULL(O."2ManExp",0) - IFNULL(C."人工",0)) > 0.01
   OR ABS(IFNULL(O."3LabAmount",0) - IFNULL(C."制造",0)) > 0.01
   OR ABS(IFNULL(O."4WWExp",0) - IFNULL(C."委外",0)) > 0.01
ORDER BY ABS(IFNULL(O."3LabAmount",0) - IFNULL(C."制造",0)) + ABS(IFNULL(O."2ManExp",0) - IFNULL(C."人工",0)) DESC;


-- @check C18 | 委外加工物资 140801：总账余额与委外在产品对账
-- @step 9 0306 / 12 CO4001 / 14 0801
-- @ok 第 1 行（期初）和第 9 行（期末）的“差额”为 0；第 2–8 行逐项说明本期差额的来源
-- @bad 140801（委外加工物资-材料）业务端 = CO4001 写入 0322_OWOR_ZCP 的委外订单（WorType 50）“在产品新”合计，只含材料。WW01 借 140801 = 委外领料 O08/O09；WW03 贷 140801 = 委外入库金额 − 当月 140802 发生额，所以“0306 计入完工的加工费”与“140802 发生额”之差（第 5 行）会直接落进 140801。第 6 行是业务端已转入关单差异的金额，总账需要有凭证冲掉它，否则就留在 140801；第 3、7 行是非 WW01/WW03 的凭证，第 11 行起按交易代码逐类列出（手工凭证、ProWW 库存重估等）。需要先运行当期的 CO4001（IsInsert='Y'），否则业务端为空。
-- @nodes p0306,p0801,t_jdt,t_owor,t_sum
-- @fields 0322_OWOR_ZCP.在产品新,0321_OWOR_SUM.1Material,0321_OWOR_SUM.4WWExp,0801_TOOJDT.Credit
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
     D AS (SELECT P."FC", F."F_RefDate" AS "SD", F."T_RefDate" AS "ED",
                  (SELECT MAX(X."Code") FROM "OFPR" X WHERE X."Code" < P."FC") AS "LFC"
           FROM P JOIN "OFPR" F ON F."Code" = P."FC"),
     G AS (SELECT CASE WHEN J."RefDate" < D."SD" THEN 'QC' ELSE 'BQ' END AS "K",
                  LEFT(J."Account", 6) AS "Acct", IFNULL(H."TransCode", '') AS "TC",
                  SUM(J."Debit") AS "Dr", SUM(J."Credit") AS "Cr", SUM(J."Debit" - J."Credit") AS "Bal"
           FROM "JDT1" J JOIN "OJDT" H ON H."TransId" = J."TransId" JOIN D ON J."RefDate" <= D."ED"
           WHERE LEFT(J."Account", 6) IN ('140801', '140802')
           GROUP BY CASE WHEN J."RefDate" < D."SD" THEN 'QC' ELSE 'BQ' END, LEFT(J."Account", 6), IFNULL(H."TransCode", '')),
     Z AS (SELECT SUM(CASE WHEN Z."期间" = D."LFC" THEN Z."在产品新" ELSE 0 END) AS "QC",
                  SUM(CASE WHEN Z."期间" = D."FC" THEN Z."在产品新" ELSE 0 END) AS "QM",
                  SUM(CASE WHEN Z."期间" = D."FC" AND Z."关单结算期间" = D."FC" THEN Z."关单差异" ELSE 0 END) AS "GD"
           FROM "MTC_COST_0322_OWOR_ZCP" Z JOIN D ON Z."期间" IN (D."FC", D."LFC")
           WHERE Z."WorType" = '50'),
     S AS (SELECT SUM(S."1Material") AS "WG", SUM(S."4WWExp") AS "JGF"
           FROM "MTC_COST_0321_OWOR_SUM" S JOIN D ON S."FcCode" = D."FC"
           WHERE S."WorType" = '50'),
     L AS (SELECT -1 * SUM(X."Amount") AS "LL"
           FROM "MTC_COST_0302_INVNTDETAIL1" X JOIN D ON X."FcCode" = D."FC"
           WHERE X."TransCode" IN ('O08', 'O09') AND IFNULL(X."IsUpdatePrice", '') <> 'NoCost'),
     R AS (SELECT 1 AS "序号", '期初余额（140801 / 上期委外在产品）' AS "项目",
                  (SELECT SUM("Bal") FROM G WHERE "K" = 'QC' AND "Acct" = '140801') AS "总账", (SELECT "QC" FROM Z) AS "业务"
           FROM DUMMY
           UNION ALL
           SELECT 2, '本期领料：WW01 借 140801 / 0302 委外领料 O08+O09',
                  (SELECT SUM("Dr") FROM G WHERE "K" = 'BQ' AND "Acct" = '140801' AND "TC" = 'WW01'), (SELECT "LL" FROM L)
           FROM DUMMY
           UNION ALL
           SELECT 3, '本期其他借方（非 WW01）',
                  (SELECT SUM("Dr") FROM G WHERE "K" = 'BQ' AND "Acct" = '140801' AND "TC" <> 'WW01'), 0
           FROM DUMMY
           UNION ALL
           SELECT 4, '本期完工：WW03 贷 140801 / 委外订单完工材料 1Material',
                  (SELECT SUM("Cr") FROM G WHERE "K" = 'BQ' AND "Acct" = '140801' AND "TC" = 'WW03'), (SELECT "WG" FROM S)
           FROM DUMMY
           UNION ALL
           SELECT 5, '加工费：140802 本期借方发生 / 0306 计入完工的加工费 4WWExp',
                  (SELECT SUM("Dr") FROM G WHERE "K" = 'BQ' AND "Acct" = '140802' AND "TC" <> 'WW03'), (SELECT "JGF" FROM S)
           FROM DUMMY
           UNION ALL
           SELECT 6, '关单差异：本期转入关单差异的委外在产品（业务端已清零）',
                  NULL, (SELECT "GD" FROM Z)
           FROM DUMMY
           UNION ALL
           SELECT 7, '本期其他贷方（非 WW03）',
                  (SELECT SUM("Cr") FROM G WHERE "K" = 'BQ' AND "Acct" = '140801' AND "TC" <> 'WW03'), 0
           FROM DUMMY
           UNION ALL
           SELECT 8, '140802 期末余额（应为 0）',
                  (SELECT SUM("Bal") FROM G WHERE "Acct" = '140802'), 0
           FROM DUMMY
           UNION ALL
           SELECT 9, '期末余额（140801 / 本期委外在产品）',
                  (SELECT SUM("Bal") FROM G WHERE "Acct" = '140801'), (SELECT "QM" FROM Z)
           FROM DUMMY
           UNION ALL
           SELECT 10 + ROW_NUMBER() OVER (ORDER BY "TC"), '  其中 140801 非 WW01/WW03 凭证，交易代码：' || CASE WHEN "TC" = '' THEN '（空，手工凭证等）' ELSE "TC" END,
                  SUM("Bal"), NULL
           FROM G WHERE "K" = 'BQ' AND "Acct" = '140801' AND "TC" NOT IN ('WW01', 'WW03')
           GROUP BY "TC")
SELECT "序号", "项目", ROUND("总账", 2) AS "总账", ROUND("业务", 2) AS "业务",
       ROUND(IFNULL("总账", 0) - IFNULL("业务", 0), 2) AS "差额"
FROM R
ORDER BY "序号";


-- @check C19 | 应付暂估 220202：总账余额与未开票收退货逐供应商核对
-- @step 15 期末暂估
-- @ok 返回 0 行（每个供应商的总账 220202 余额 = 截至期末已收货未开票的暂估金额）
-- @bad 业务端口径同 reports/MTC_RPT_CO6102（STYPE=2）：库存物料和委外加工费 X0510001；收货行未清 = 收货 − 截至期末已开票 − 已退货，独立退货为负，按收货暂估价（U_InitPrice / U_IsPrice / LineTotal）计价。总账按 JDT1.U_VendorCode 归属供应商。常见原因：当月 6101_1 的 PUR1–PUR4 凭证没有生成或没有过账；发票冲回时价格与收货暂估价不同；凭证行没有填 U_VendorCode（供应商编码为空的一行）；跨期取消的单据。
-- @nodes t_jdt
-- @fields JDT1.U_VendorCode
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
     D AS (SELECT F."T_RefDate" AS "ED" FROM P JOIN "OFPR" F ON F."Code" = P."FC"),
     CXL AS (SELECT DISTINCT X."BaseType" AS "ObjType", X."BaseEntry" AS "DocEntry"
             FROM (SELECT M."DocDate", L."BaseType", L."BaseEntry" FROM "OPDN" M JOIN "PDN1" L ON L."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND L."BaseType" = 20
                   UNION ALL SELECT M."DocDate", L."BaseType", L."BaseEntry" FROM "ORPD" M JOIN "RPD1" L ON L."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND L."BaseType" = 21
                   UNION ALL SELECT M."DocDate", L."BaseType", L."BaseEntry" FROM "OPCH" M JOIN "PCH1" L ON L."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND L."BaseType" = 18
                   UNION ALL SELECT M."DocDate", L."BaseType", L."BaseEntry" FROM "ORPC" M JOIN "RPC1" L ON L."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND L."BaseType" = 19) X
             JOIN D ON X."DocDate" <= D."ED"),
     NXT AS (SELECT X."K", X."BaseType", X."BaseEntry", X."BaseLine", SUM(X."Quantity") AS "Qty"
             FROM (SELECT 'INV' AS "K", 18 AS "OT", M."DocEntry", M."DocDate", M."CANCELED", L."BaseType", L."BaseEntry", L."BaseLine", L."Quantity" FROM "OPCH" M JOIN "PCH1" L ON L."DocEntry" = M."DocEntry" WHERE L."BaseType" IN (20, 21)
                   UNION ALL SELECT 'INV', 19, M."DocEntry", M."DocDate", M."CANCELED", L."BaseType", L."BaseEntry", L."BaseLine", L."Quantity" FROM "ORPC" M JOIN "RPC1" L ON L."DocEntry" = M."DocEntry" WHERE L."BaseType" = 21
                   UNION ALL SELECT 'RET', 21, M."DocEntry", M."DocDate", M."CANCELED", L."BaseType", L."BaseEntry", L."BaseLine", L."Quantity" FROM "ORPD" M JOIN "RPD1" L ON L."DocEntry" = M."DocEntry" WHERE L."BaseType" = 20
                   UNION ALL SELECT 'RET', 20, M."DocEntry", M."DocDate", M."CANCELED", L."BaseType", L."BaseEntry", L."BaseLine", L."Quantity" FROM "OPDN" M JOIN "PDN1" L ON L."DocEntry" = M."DocEntry" WHERE L."BaseType" = 21) X
             JOIN D ON X."DocDate" <= D."ED"
             WHERE X."CANCELED" <> 'C' AND NOT EXISTS (SELECT 1 FROM CXL C WHERE C."ObjType" = X."OT" AND C."DocEntry" = X."DocEntry")
             GROUP BY X."K", X."BaseType", X."BaseEntry", X."BaseLine"),
     SRC AS (SELECT X.* FROM (
               SELECT 20 AS "OT", 1 AS "Sign", M."DocEntry", M."DocDate", M."CANCELED", M."CardCode", M."CardName", L."LineNum", L."BaseType", L."ItemCode", L."Quantity", L."U_InitPrice", L."U_IsPrice", L."Price", L."LineTotal"
               FROM "OPDN" M JOIN "PDN1" L ON L."DocEntry" = M."DocEntry" WHERE IFNULL(L."BaseType", -1) <> 21
               UNION ALL
               SELECT 21, -1, M."DocEntry", M."DocDate", M."CANCELED", M."CardCode", M."CardName", L."LineNum", L."BaseType", L."ItemCode", L."Quantity", L."U_InitPrice", L."U_IsPrice", L."Price", L."LineTotal"
               FROM "ORPD" M JOIN "RPD1" L ON L."DocEntry" = M."DocEntry" WHERE IFNULL(L."BaseType", -1) <> 20) X
             JOIN D ON X."DocDate" <= D."ED"
             JOIN "OITM" I ON I."ItemCode" = X."ItemCode"
             WHERE X."CANCELED" <> 'C' AND (I."InvntItem" = 'Y' OR X."ItemCode" = 'X0510001')
               AND NOT EXISTS (SELECT 1 FROM CXL C WHERE C."ObjType" = X."OT" AND C."DocEntry" = X."DocEntry")),
     DTL AS (SELECT S."CardCode", S."CardName", S."Sign", S."Quantity",
                    S."Quantity" - IFNULL(N1."Qty", 0) - IFNULL(N2."Qty", 0) AS "OpenQty",
                    CASE WHEN IFNULL(S."U_InitPrice", 0) <> 0 THEN S."U_InitPrice" WHEN S."U_IsPrice" = 'Y' THEN S."Price" ELSE S."LineTotal" / NULLIF(S."Quantity", 0) END AS "ZGPrice",
                    ROUND(CASE WHEN IFNULL(S."U_InitPrice", 0) <> 0 THEN S."Quantity" * S."U_InitPrice" WHEN S."U_IsPrice" = 'Y' THEN S."Quantity" * S."Price" ELSE S."LineTotal" END, 2) AS "ZGAmt"
             FROM SRC S
             LEFT JOIN NXT N1 ON N1."K" = 'INV' AND N1."BaseType" = S."OT" AND N1."BaseEntry" = S."DocEntry" AND N1."BaseLine" = S."LineNum"
             LEFT JOIN NXT N2 ON N2."K" = 'RET' AND N2."BaseType" = S."OT" AND N2."BaseEntry" = S."DocEntry" AND N2."BaseLine" = S."LineNum"),
     B AS (SELECT "CardCode", MAX("CardName") AS "CardName", COUNT(*) AS "Lines",
                  SUM("Sign" * CASE WHEN ABS("OpenQty" - "Quantity") < 0.000001 THEN "ZGAmt" ELSE ROUND("OpenQty" * "ZGPrice", 2) END) AS "Amt"
           FROM DTL WHERE ABS("OpenQty") > 0.000001 GROUP BY "CardCode"),
     G AS (SELECT IFNULL(J."U_VendorCode", '') AS "CardCode", SUM(J."Credit" - J."Debit") AS "Bal"
           FROM "JDT1" J JOIN D ON J."RefDate" <= D."ED"
           WHERE J."Account" = '220202'
           GROUP BY IFNULL(J."U_VendorCode", ''))
SELECT COALESCE(B."CardCode", G."CardCode") AS "供应商编码", IFNULL(B."CardName", C."CardName") AS "供应商名称",
       B."Lines" AS "未清行数", ROUND(IFNULL(B."Amt", 0), 2) AS "业务暂估余额", ROUND(IFNULL(G."Bal", 0), 2) AS "总账220202余额",
       ROUND(IFNULL(G."Bal", 0) - IFNULL(B."Amt", 0), 2) AS "差额[总账-业务]"
FROM B FULL OUTER JOIN G ON G."CardCode" = B."CardCode"
LEFT JOIN "OCRD" C ON C."CardCode" = COALESCE(B."CardCode", G."CardCode")
WHERE ABS(IFNULL(G."Bal", 0) - IFNULL(B."Amt", 0)) > 0.01
ORDER BY ABS(IFNULL(G."Bal", 0) - IFNULL(B."Amt", 0)) DESC;


-- @check C20 | 发出商品 140601：总账与未开票交货核对
-- @step 15 期末暂估
-- @ok 第 1–3 行的“差额”为 0
-- @bad 业务端口径同 reports/MTC_RPT_CO6103（STYPE=2）：库存物料，排除样品销售；交货行未清 = 交货 − 截至期末已开票 − 已退货，独立销售退货为负；按 0302 中该行成本计价（2024-12-31 及以前用 U_InitPrice）。第 1 行差额常见原因：基于交货的销售退货按退货当月的加权单价冲 140601（DN01 的 O06），而不是按原交货成本；DN03 开票转出的价格与交货成本不同；手工凭证。第 2、3 行差额常见原因：AR03/AR04 用 DLN1.OpenQty 的当前值，期末之后的开票或退货会让历史账期对不上；没有客户类型的交货不计提（第 4 行）。第 7 行大于 0 时先运行当期成本计算。
-- @nodes t_jdt,t_dtl,p0801
-- @fields 0302_INVNTDETAIL1.Price,0801_TOOJDT.Credit
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
     D AS (SELECT F."T_RefDate" AS "ED" FROM P JOIN "OFPR" F ON F."Code" = P."FC"),
     CXL AS (SELECT DISTINCT X."BaseType" AS "ObjType", X."BaseEntry" AS "DocEntry"
             FROM (SELECT M."DocDate", L."BaseType", L."BaseEntry" FROM "ODLN" M JOIN "DLN1" L ON L."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND L."BaseType" = 15
                   UNION ALL SELECT M."DocDate", L."BaseType", L."BaseEntry" FROM "ORDN" M JOIN "RDN1" L ON L."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND L."BaseType" = 16
                   UNION ALL SELECT M."DocDate", L."BaseType", L."BaseEntry" FROM "OINV" M JOIN "INV1" L ON L."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND L."BaseType" = 13
                   UNION ALL SELECT M."DocDate", L."BaseType", L."BaseEntry" FROM "ORIN" M JOIN "RIN1" L ON L."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND L."BaseType" = 14) X
             JOIN D ON X."DocDate" <= D."ED"),
     NXT AS (SELECT X."K", X."BaseType", X."BaseEntry", X."BaseLine", SUM(X."Quantity") AS "Qty"
             FROM (SELECT 'INV' AS "K", 13 AS "OT", M."DocEntry", M."DocDate", M."CANCELED", L."BaseType", L."BaseEntry", L."BaseLine", L."Quantity" FROM "OINV" M JOIN "INV1" L ON L."DocEntry" = M."DocEntry" WHERE L."BaseType" = 15
                   UNION ALL SELECT 'INV', 14, M."DocEntry", M."DocDate", M."CANCELED", L."BaseType", L."BaseEntry", L."BaseLine", L."Quantity" FROM "ORIN" M JOIN "RIN1" L ON L."DocEntry" = M."DocEntry" WHERE L."BaseType" = 16
                   UNION ALL SELECT 'RET', 16, M."DocEntry", M."DocDate", M."CANCELED", L."BaseType", L."BaseEntry", L."BaseLine", L."Quantity" FROM "ORDN" M JOIN "RDN1" L ON L."DocEntry" = M."DocEntry" WHERE L."BaseType" = 15) X
             JOIN D ON X."DocDate" <= D."ED"
             WHERE X."CANCELED" <> 'C' AND NOT EXISTS (SELECT 1 FROM CXL C WHERE C."ObjType" = X."OT" AND C."DocEntry" = X."DocEntry")
             GROUP BY X."K", X."BaseType", X."BaseEntry", X."BaseLine"),
     SRC AS (SELECT X.* FROM (
               SELECT 15 AS "OT", 1 AS "Sign", M."DocEntry", M."DocDate", M."CANCELED", M."U_SalOrdType", L."LineNum", L."ItemCode", L."Quantity", L."U_InitPrice"
               FROM "ODLN" M JOIN "DLN1" L ON L."DocEntry" = M."DocEntry"
               UNION ALL
               SELECT 16, -1, M."DocEntry", M."DocDate", M."CANCELED", M."U_SalOrdType", L."LineNum", L."ItemCode", L."Quantity", L."U_InitPrice"
               FROM "ORDN" M JOIN "RDN1" L ON L."DocEntry" = M."DocEntry" WHERE IFNULL(L."BaseType", -1) <> 15) X
             JOIN D ON X."DocDate" <= D."ED"
             JOIN "OITM" I ON I."ItemCode" = X."ItemCode" AND I."InvntItem" = 'Y'
             WHERE X."CANCELED" <> 'C' AND NOT EXISTS (SELECT 1 FROM CXL C WHERE C."ObjType" = X."OT" AND C."DocEntry" = X."DocEntry")),
     PRC AS (SELECT "ObjType", "DocEntry", "LineNum", SUM("Amount") / NULLIF(SUM("Quantity"), 0) AS "Price"
             FROM "MTC_COST_0302_INVNTDETAIL1" WHERE "CostCode" = '20' AND "ObjType" IN ('15', '16')
             GROUP BY "ObjType", "DocEntry", "LineNum"),
     DTL AS (SELECT S."Sign", T91."U_CustType", T91."U_BusiType",
                    S."Quantity" - IFNULL(N1."Qty", 0) - IFNULL(N2."Qty", 0) AS "OpenQty",
                    CASE WHEN S."DocDate" <= '2024-12-31' THEN S."U_InitPrice" ELSE R."Price" END AS "CostPrice",
                    CASE WHEN S."DocDate" > '2024-12-31' AND R."Price" IS NULL THEN 1 ELSE 0 END AS "NoCost"
             FROM SRC S
             LEFT JOIN (SELECT DISTINCT "Name", "U_CustType", "U_BusiType" FROM "@MTC_SALORDTYPE") T91 ON T91."Name" = S."U_SalOrdType"
             LEFT JOIN PRC R ON R."ObjType" = TO_NVARCHAR(S."OT") AND R."DocEntry" = S."DocEntry" AND R."LineNum" = S."LineNum"
             LEFT JOIN NXT N1 ON N1."K" = 'INV' AND N1."BaseType" = S."OT" AND N1."BaseEntry" = S."DocEntry" AND N1."BaseLine" = S."LineNum"
             LEFT JOIN NXT N2 ON N2."K" = 'RET' AND N2."BaseType" = S."OT" AND N2."BaseEntry" = S."DocEntry" AND N2."BaseLine" = S."LineNum"),
     B AS (SELECT SUM(CASE WHEN "Y" = 1 THEN "Amt" ELSE 0 END) AS "All",
                  SUM(CASE WHEN "Y" = 1 AND "U_CustType" = '国内客户' THEN "Amt" ELSE 0 END) AS "GN",
                  SUM(CASE WHEN "Y" = 1 AND "U_CustType" = '国外客户' THEN "Amt" ELSE 0 END) AS "GW",
                  SUM(CASE WHEN "Y" = 1 AND IFNULL("U_CustType", '') NOT IN ('国内客户', '国外客户') THEN "Amt" ELSE 0 END) AS "NoType",
                  SUM(CASE WHEN "Y" = 0 THEN "Amt" ELSE 0 END) AS "Sample",
                  SUM("NoCost") AS "NoCost"
           FROM (SELECT DTL.*, CASE WHEN IFNULL("U_BusiType", '') = '样品销售' THEN 0 ELSE 1 END AS "Y",
                        "Sign" * ROUND("OpenQty" * "CostPrice", 2) AS "Amt"
                 FROM DTL WHERE ABS("OpenQty") > 0.000001) Z),
     G AS (SELECT SUM(CASE WHEN IFNULL(H."TransCode", '') NOT IN ('AR03', 'AR04') THEN J."Debit" - J."Credit" ELSE 0 END) AS "BalExAR",
                  SUM(J."Debit" - J."Credit") AS "Bal",
                  SUM(CASE WHEN H."TransCode" = 'AR03' AND J."RefDate" = D."ED" THEN J."Credit" - J."Debit" ELSE 0 END) AS "AR03",
                  SUM(CASE WHEN H."TransCode" = 'AR04' AND J."RefDate" = D."ED" THEN J."Credit" - J."Debit" ELSE 0 END) AS "AR04"
           FROM "JDT1" J JOIN "OJDT" H ON H."TransId" = J."TransId" JOIN D ON J."RefDate" <= D."ED"
           WHERE LEFT(J."Account", 6) = '140601')
SELECT 1 AS "序号", '140601 余额（不含 AR03/AR04）/ 发出商品合计' AS "项目", ROUND(G."BalExAR", 2) AS "总账", ROUND(B."All", 2) AS "业务", ROUND(IFNULL(G."BalExAR", 0) - IFNULL(B."All", 0), 2) AS "差额" FROM G, B
UNION ALL SELECT 2, 'AR03 期末计提（国内）/ 国内客户发出商品', ROUND(G."AR03", 2), ROUND(B."GN", 2), ROUND(IFNULL(G."AR03", 0) - IFNULL(B."GN", 0), 2) FROM G, B
UNION ALL SELECT 3, 'AR04 期末计提（国外）/ 国外客户发出商品', ROUND(G."AR04", 2), ROUND(B."GW", 2), ROUND(IFNULL(G."AR04", 0) - IFNULL(B."GW", 0), 2) FROM G, B
UNION ALL SELECT 4, '没有客户类型的发出商品（AR03/AR04 不会计提）', NULL, ROUND(B."NoType", 2), NULL FROM B
UNION ALL SELECT 5, '140601 期末余额（含 AR03/AR04）', ROUND(G."Bal", 2), NULL, NULL FROM G
UNION ALL SELECT 6, '样品销售未开票（不计入发出商品，仅供参考）', NULL, ROUND(B."Sample", 2), NULL FROM B
UNION ALL SELECT 7, '成本未计算的未清行数（先运行当期成本计算）', NULL, B."NoCost", NULL FROM B
ORDER BY 1;

/* =====================================================================
 * 追溯查询：已经知道是哪个物料或哪张订单有问题时使用
 * ===================================================================== */

-- @check T01 | 追一个物料的单价：每一步是谁改的
-- @step 追溯
-- @ok 按顺序读 PriceMemo：每段“->从<过程>.<步骤>写入”就是一次改写
-- @bad 找到第一次出现异常价格的那一步，再看那一步的上游：外购料看采购入库行，自制品看 IsUpdatePrice='IN01' 的入库行对应的订单（T02）。
-- @nodes t_invnt,t_dtl
-- @fields 0301_INVNT.Price,0301_INVNT.PriceMemo,0302_INVNTDETAIL1.PriceMemo,0302_INVNTDETAIL1.IsUpdatePrice
WITH P AS (SELECT '2026-08' AS "FC", '<物料编码>' AS "ITEM" FROM DUMMY)
SELECT '0301 汇总' AS "来源", CAST(NULL AS DATE) AS "DocDate", CAST(NULL AS NVARCHAR(50)) AS "ObjType",
       CAST(NULL AS INTEGER) AS "DocEntry", CAST(NULL AS NVARCHAR(50)) AS "TransCode",
       CAST(NULL AS NVARCHAR(50)) AS "BaseType", CAST(NULL AS INTEGER) AS "BaseEntry",
       I."QM_Qty" AS "Quantity", I."Price", I."QM_Amount" AS "Amount",
       CAST(NULL AS NVARCHAR(50)) AS "IsUpdatePrice", I."PriceMemo"
FROM "MTC_COST_0301_INVNT" I JOIN P ON I."FcCode" = P."FC" AND I."ItemCode" = P."ITEM"
WHERE I."CostCode" = '20'
UNION ALL
SELECT '0302 明细', D."DocDate", D."ObjType", D."DocEntry", D."TransCode",
       D."BaseType", D."BaseEntry", D."Quantity", D."Price", D."Amount",
       D."IsUpdatePrice", D."PriceMemo"
FROM "MTC_COST_0302_INVNTDETAIL1" D JOIN P ON D."FcCode" = P."FC" AND D."ItemCode" = P."ITEM"
ORDER BY 1, 5, 2;


-- @check T02 | 追一张订单的成本：材料、费用、结果、入库
-- @step 追溯
-- @ok 从上到下依次是：订单头 → 领料行 → 费用 → 成本结果 → 完工入库明细
-- @bad 领料行金额不对 → 回到该材料的 T01；费用不对 → 看 C11；结果单价不对 → 按 0402 公式手算一遍（累计领料、累计完工、计划用量比）；入库金额与结果不一致 → C10。
-- @nodes t_owor,t_owor1,t_owor2,t_sum,t_dtl,t_0106
-- @fields 0321_OWOR.IgnQty,0321_OWOR1.Amount,0321_OWOR2.Amount,0321_OWOR_SUM.Price
WITH P AS (SELECT '2026-08' AS "FC", '<订单号 WorNum>' AS "WN" FROM DUMMY)
SELECT '1 订单头' AS "层", O."FcCode", O."ItemCode", CAST(NULL AS INTEGER) AS "LineNum", CAST(NULL AS NVARCHAR(50)) AS "CostCode",
       O."Quantity" AS "计划数", O."IgnQty" AS "数量", O."Amount", O."PriceMemo" AS "备注"
FROM "MTC_COST_0321_OWOR" O JOIN P ON O."WorNum" = P."WN" AND O."FcCode" <= P."FC"
UNION ALL
SELECT '2 领料行', L."FcCode", L."ItemCode", L."LineNum", CAST(NULL AS NVARCHAR(50)), CAST(NULL AS DECIMAL(19,6)), L."IgeQty", L."Amount", L."PriceMemo"
FROM "MTC_COST_0321_OWOR1" L JOIN P ON L."WorNum" = P."WN" AND L."FcCode" <= P."FC"
UNION ALL
SELECT '3 费用', W."FcCode", CAST(NULL AS NVARCHAR(50)), CAST(NULL AS INTEGER), W."CostCode", CAST(NULL AS DECIMAL(19,6)), W."IgeQty", W."Amount", W."ExpType"
FROM "MTC_COST_0321_OWOR2" W JOIN P ON W."WorNum" = P."WN" AND W."FcCode" <= P."FC"
UNION ALL
SELECT '4 成本结果', S."FcCode", S."ItemCode", S."iLevel", CAST(NULL AS NVARCHAR(50)), S."WorQty", S."IgnQty", S."Amount",
       'Price=' || TO_NVARCHAR(S."Price") || '；累计完工=' || TO_NVARCHAR(S."Ign_SUM") || '；累计材料=' || TO_NVARCHAR(S."1Material_SUM")
FROM "MTC_COST_0321_OWOR_SUM" S JOIN P ON S."WorNum" = P."WN" AND S."FcCode" <= P."FC"
UNION ALL
SELECT '5 完工入库', D."FcCode", D."ItemCode", D."LineNum", D."TransCode", CAST(NULL AS DECIMAL(19,6)), D."Quantity", D."Amount", D."IsUpdatePrice"
FROM "MTC_COST_0302_INVNTDETAIL1" D
JOIN P ON D."FcCode" <= P."FC"
JOIN "MTC_COST_0321_OWOR" O ON O."FcCode" = D."FcCode" AND O."DocType" = D."BaseType"
     AND O."WorEntry" = TO_NVARCHAR(D."BaseEntry") AND O."WorNum" = P."WN"
WHERE D."TransCode" IN ('I03','I07','I08','I09') AND D."BaseLine" IS NULL
ORDER BY 2, 1, 4;


-- @check T03 | 同号的 B1 生产订单与返工单是否有关联
-- @step 追溯
-- @ok 看最后一列：都是“否”，说明两张订单只是 DocEntry 碰巧相同，0401 在 3–5 级按 WorEntry 合并它们的材料和费用是错误的
-- @bad 如果是“是”（返工单的来源正是这张生产订单），说明两者确有业务关联；但即便如此，返工单自己也保留了这笔费用，同一笔钱仍被算了两次（C11 的 D > C）
-- @nodes t_owor,u_owor,p0401
-- @fields 0321_OWOR.2ManExp,0321_OWOR.3LabAmount
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY)
SELECT A."WorEntry", A."WorNum" AS "生产订单号", A."WorType" AS "生产订单类型", A."ItemCode" AS "生产订单物料", L1."iLevel" AS "生产订单层级",
       A."2ManExp" AS "生产订单人工", A."3LabAmount" AS "生产订单制造",
       B."WorNum" AS "返工单号", B."WorType" AS "返工单类型", B."ItemCode" AS "返工单物料", L2."iLevel" AS "返工单层级",
       B."2ManExp" AS "返工单人工", B."3LabAmount" AS "返工单制造",
       M."U_OriginType", M."U_OriginAbs", M."U_OriginNum", M."U_BaseType", M."U_BaseEntry",
       CASE WHEN TO_NVARCHAR(M."U_OriginAbs") = A."WorEntry" OR TO_NVARCHAR(M."U_BaseEntry") = A."WorEntry"
                 OR TO_NVARCHAR(M."U_OriginNum") = A."WorNum" THEN '是' ELSE '否' END AS "返工单来源于这张生产订单"
FROM "MTC_COST_0321_OWOR" A
JOIN P ON A."FcCode" = P."FC"
JOIN "MTC_COST_0321_OWOR" B ON B."FcCode" = A."FcCode" AND B."WorEntry" = A."WorEntry" AND B."DocType" = 'MTC_OWOR'
LEFT JOIN "@MTC_OWOR" M ON TO_NVARCHAR(M."DocEntry") = B."WorEntry"
LEFT JOIN "U_COILV" L1 ON L1."FcCode" = A."FcCode" AND L1."ItemCode" = A."ItemCode"
LEFT JOIN "U_COILV" L2 ON L2."FcCode" = B."FcCode" AND L2."ItemCode" = B."ItemCode"
WHERE A."DocType" = '202'
ORDER BY L1."iLevel" DESC, A."WorEntry";


-- @check T04 | 追形态转换：I05 配到了哪张转出单，单价为什么是 0
-- @step 追溯
-- @ok 每行“诊断”都是“正常”（单价为 0 的行排在最前）
-- @bad I05 的单价只在 0302 写一次：按配对键（收货单行的 U_BaseType/U_BaseEntry/U_BaseLineGrpNum）找本月的 O05，取其金额的相反数，0401 不会再改。“诊断”列给出原因：配对键不全、转出单跨月、业务类型不是 205、从 S300 发出、配到多行，或 B 自身没有单价。
--      B 没有单价时，看右侧 B 的期初、本期采购和期初维护价：三者都没有时，O05 沿用 B1 出库单上的金额。要在期初单价维护（@MTC_COST_QCPRICE）里给 B 填价后重跑 0000；给 A 填价没有用，0302 不给 I05 读维护价。
-- @nodes t_dtl,p0302,v_doc,u_qcprice,t_invnt
-- @fields 0302_INVNTDETAIL1.Price,0302_INVNTDETAIL1.Amount,0302_INVNTDETAIL1.IsUpdatePrice,0301_INVNT.QC_Amount
WITH P AS (SELECT '2026-08' AS "FC" FROM DUMMY),
-- 本月的 I05（转入 A）
I AS (SELECT D.* FROM "MTC_COST_0302_INVNTDETAIL1" D JOIN P ON D."FcCode" = P."FC" WHERE D."TransCode" = 'I05'),
-- 同一配对键下 I05 的行数（大于 1 = 一转多，每行都拿到整笔 O05 金额）
IK AS (SELECT "BaseType", "BaseEntry", "BaseLine", COUNT(*) AS "N" FROM I GROUP BY "BaseType", "BaseEntry", "BaseLine"),
-- 本月的 O05（转出 B），与 0302 的配对条件相同
O AS (SELECT D."BaseType", D."BaseEntry", D."BaseLine", COUNT(*) AS "N", MIN(D."ItemCode") AS "ItemB",
             SUM(D."Quantity") AS "Qty", SUM(D."Amount") AS "Amt",
             MIN(IFNULL(D."IsUpdatePrice",'(空)')) AS "Upd", MIN(RIGHT(D."PriceMemo",150)) AS "Memo"
      FROM "MTC_COST_0302_INVNTDETAIL1" D JOIN P ON D."FcCode" = P."FC"
      WHERE D."TransCode" = 'O05'
      GROUP BY D."BaseType", D."BaseEntry", D."BaseLine"),
-- B1 中配对键相同的其他出库单行（不限月份、业务类型和仓库），用来判断为什么没配上
G AS (SELECT TO_NVARCHAR(L."U_BaseType") AS "BT", TO_NVARCHAR(L."U_BaseEntry") AS "BE", TO_NVARCHAR(L."U_BaseLineGrpNum") AS "BL",
             COUNT(*) AS "N",
             SUM(CASE WHEN TO_CHAR(H."DocDate",'YYYY-MM') <> P."FC" THEN 1 ELSE 0 END) AS "OtherFc",
             SUM(CASE WHEN TO_CHAR(H."DocDate",'YYYY-MM') = P."FC" AND IFNULL(H."U_TrsName",'') <> '205' THEN 1 ELSE 0 END) AS "Not205",
             SUM(CASE WHEN TO_CHAR(H."DocDate",'YYYY-MM') = P."FC" AND L."WhsCode" = 'S300' THEN 1 ELSE 0 END) AS "S300",
             STRING_AGG(TO_NVARCHAR(H."DocNum") || '（' || TO_CHAR(H."DocDate",'YYYY-MM-DD') || ' 类型' || IFNULL(H."U_TrsName",'空')
                        || ' ' || IFNULL(L."WhsCode",'') || ' ' || IFNULL(L."ItemCode",'') || '）', '、') AS "Docs"
      FROM "OIGE" H JOIN "IGE1" L ON L."DocEntry" = H."DocEntry" CROSS JOIN P
      WHERE EXISTS (SELECT 1 FROM I WHERE TO_NVARCHAR(I."BaseEntry") = TO_NVARCHAR(L."U_BaseEntry"))
      GROUP BY TO_NVARCHAR(L."U_BaseType"), TO_NVARCHAR(L."U_BaseEntry"), TO_NVARCHAR(L."U_BaseLineGrpNum")),
-- 0302 Step1001/1002 用的 B 单价 =（期初金额 + 本期采购金额）/（期初数量 + 本期采购数量）
B0 AS (SELECT V."ItemCode", V."QC_Qty", V."QC_Amount" FROM "MTC_COST_0301_INVNT" V JOIN P ON V."FcCode" = P."FC" WHERE V."CostCode" = '20'),
PU AS (SELECT D."ItemCode", SUM(D."Quantity") AS "Qty", SUM(D."Amount") AS "Amt"
       FROM "MTC_COST_0302_INVNTDETAIL1" D JOIN P ON D."FcCode" = P."FC"
       WHERE D."TransCode" IN ('I01','I06','I11') AND IFNULL(D."IsUpdatePrice",'') <> 'NoCost'
       GROUP BY D."ItemCode"),
-- 本期期初单价维护（0302 Step1003 只给 O05 读，不给 I05 读）
Q AS (SELECT L."U_ItemCode" AS "ItemCode", MAX(L."U_Price") AS "Price", MAX(L."U_IsY") AS "IsY"
      FROM "@MTC_COST_QCPRICE" H JOIN "@MTC_COST_QCPRICE1" L ON L."DocEntry" = H."DocEntry"
      JOIN P ON H."U_FcCode" = P."FC"
      WHERE H."Canceled" = 'N'
      GROUP BY L."U_ItemCode")
SELECT
  CASE
    WHEN IFNULL(I."Price",0) <> 0 AND IK."N" > 1 THEN '一转多：本月有 ' || TO_NVARCHAR(IK."N") || ' 行 I05 共用这个配对键，每行都拿到整笔 O05 金额，被重复计入'
    WHEN IFNULL(I."Price",0) <> 0 AND O."N" > 1 THEN '多转一：配到 ' || TO_NVARCHAR(O."N") || ' 行 O05，UPDATE 只取其中一行，结果不确定'
    WHEN IFNULL(I."Price",0) <> 0 THEN '正常'
    WHEN I."BaseType" IS NULL OR I."BaseEntry" IS NULL OR I."BaseLine" IS NULL
      THEN '①配对键不全：收货单行的 U_BaseType/U_BaseEntry/U_BaseLineGrpNum 有空值，配不到 O05'
    WHEN O."N" IS NULL AND G."OtherFc" > 0 THEN '②跨月：配对的转出单不在本月，0302 只在本月的 O05 中配对'
    WHEN O."N" IS NULL AND G."Not205" > 0 THEN '③转出单的业务类型（表头 U_TrsName）不是 205，没有被识别为 O05'
    WHEN O."N" IS NULL AND G."S300" > 0 THEN '④转出单从 S300 报废库发出，0302 不收 S300 的行'
    WHEN O."N" IS NULL AND G."N" > 0 THEN '⑤B1 有配对的 205 转出单，0302 中却没有对应的 O05：查该出库单在 MTC_VIEW_Document 中的 BaseType/BaseEntry/BaseLine'
    WHEN O."N" IS NULL THEN '⑥B1 中没有配对键相同的其他出库单行：收货单行的配对字段填错了'
    WHEN O."N" > 1 THEN '⑦多转一：配到 ' || TO_NVARCHAR(O."N") || ' 行 O05，UPDATE 结果不确定'
    WHEN IFNULL(O."Amt",0) = 0 AND Q."IsY" = 'Y' AND IFNULL(Q."Price",0) = 0
      THEN '⑧期初单价维护中 B 的价格是 0，且勾了强制使用（U_IsY=Y）'
    WHEN IFNULL(O."Amt",0) = 0 AND O."Upd" = '(空)'
      THEN '⑨B 在计算前没有单价（期初金额 + 本期采购为 0，期初单价维护里也没有 B），O05 沿用了 B1 出库单上的金额 0'
    WHEN IFNULL(O."Amt",0) = 0 THEN '⑩O05 金额为 0：看 O05 的 PriceMemo'
    ELSE '其他：看本行的 PriceMemo'
  END AS "诊断",
  I."DocNum" AS "收货单号", I."LineNum", I."DocDate", I."ItemCode" AS "转入物料A",
  I."Quantity" AS "I05数量", I."Price" AS "I05单价", I."Amount" AS "I05金额", IFNULL(I."IsUpdatePrice",'(空)') AS "I05_IsUpdatePrice",
  IFNULL(I."BaseType",'(空)') || ' / ' || IFNULL(TO_NVARCHAR(I."BaseEntry"),'(空)') || ' / ' || IFNULL(TO_NVARCHAR(I."BaseLine"),'(空)') AS "配对键",
  IK."N" AS "同键I05行数", O."N" AS "本月O05行数", O."ItemB" AS "转出物料B", O."Qty" AS "O05数量", O."Amt" AS "O05金额",
  O."Upd" AS "O05_IsUpdatePrice", O."Memo" AS "O05_PriceMemo末尾",
  G."Docs" AS "B1同键出库单",
  B0."QC_Qty" AS "B期初数量", B0."QC_Amount" AS "B期初金额", PU."Qty" AS "B本期采购数量", PU."Amt" AS "B本期采购金额",
  Q."Price" AS "B期初维护价", Q."IsY" AS "B强制使用", QA."Price" AS "A期初维护价（I05不读）"
FROM I
LEFT JOIN IK ON IK."BaseType" = I."BaseType" AND IK."BaseEntry" = I."BaseEntry" AND IK."BaseLine" = I."BaseLine"
LEFT JOIN O ON O."BaseType" = I."BaseType" AND O."BaseEntry" = I."BaseEntry" AND O."BaseLine" = I."BaseLine"
LEFT JOIN G ON G."BT" = I."BaseType" AND G."BE" = TO_NVARCHAR(I."BaseEntry") AND G."BL" = TO_NVARCHAR(I."BaseLine")
LEFT JOIN B0 ON B0."ItemCode" = O."ItemB"
LEFT JOIN PU ON PU."ItemCode" = O."ItemB"
LEFT JOIN Q ON Q."ItemCode" = O."ItemB"
LEFT JOIN Q QA ON QA."ItemCode" = I."ItemCode"
ORDER BY CASE WHEN IFNULL(I."Price",0) = 0 THEN 0 ELSE 1 END, I."DocNum", I."LineNum";
