-- 只读：一张其他收货 / 发货单（59 OIGN / 60 OIGE）为什么没进 YF01 凭证（用户 2026-11-08）。不输出金额。
-- 改掉 P 里的单据类型和单号后执行；RunId 留 NULL 时取该账期最近一次成功的正式运行（RunType F），也可填运行号。
-- 每个单据行一行，“判断”是第一个卡住的环节。新框架 YF01 按 科目 + 部门 + 项目 汇总，凭证上没有单号，单据级明细在 MTC_CA_R_JDT_SRC。
-- 新框架链路：OIVL（计价仓库）→ S_LINE（TransCode 来自表头 U_TrsName → @U_CIOTRN.U_IOType）→ R_LINE（Amount <> 0）→ R_JDT_SRC（YF01 只收 I04 / O04）→ R_JDT
-- 旧框架链路：0302_INVNTDETAIL1（CostCode 20，TransCode I04 / O04，排除 S300）→ 0802_OJDTBASEDETAIL（YF01）
WITH P AS (SELECT '59' AS "ObjType", 88358 AS "DocNum", CAST(NULL AS BIGINT) AS "RunId" FROM DUMMY),
     H AS (SELECT P."ObjType", T."DocEntry", T."DocNum", TO_DATE(T."DocDate") AS "DocDate", T."CANCELED", T."U_TrsName"
             FROM "OIGN" T JOIN P ON P."ObjType" = '59' AND T."DocNum" = P."DocNum"
           UNION ALL
           SELECT P."ObjType", T."DocEntry", T."DocNum", TO_DATE(T."DocDate"), T."CANCELED", T."U_TrsName"
             FROM "OIGE" T JOIN P ON P."ObjType" = '60' AND T."DocNum" = P."DocNum"),
     L AS (SELECT '59' AS "ObjType", "DocEntry", "LineNum", "ItemCode", "WhsCode", "AcctCode", "OcrCode", "Project" FROM "IGN1"
           UNION ALL
           SELECT '60', "DocEntry", "LineNum", "ItemCode", "WhsCode", "AcctCode", "OcrCode", "Project" FROM "IGE1"),
     F AS (SELECT H.*, O."Code" AS "FcCode" FROM H LEFT JOIN "OFPR" O ON H."DocDate" BETWEEN TO_DATE(O."F_RefDate") AND TO_DATE(O."T_RefDate")),
     R AS (SELECT F."FcCode", COALESCE(MAX(P."RunId"), MAX(U."RunId")) AS "RunId"
             FROM F CROSS JOIN P
             LEFT JOIN "MTC_CA_RUN" U ON U."FcCode" = F."FcCode" AND U."RunType" = 'F' AND U."Status" = 'OK'
            GROUP BY F."FcCode"),
     X AS (SELECT F."ObjType", F."DocEntry", F."DocNum", F."DocDate", F."FcCode", F."CANCELED", F."U_TrsName", C."U_IOType" AS "MapTrans",
                  L."LineNum", L."ItemCode", L."WhsCode", W."U_IsCost", L."AcctCode", L."OcrCode", L."Project", R."RunId",
                  S."LineId", S."TransCode" AS "SnapTrans", S."Canceled" AS "SnapCanceled", S."NoCost", S."AcctCode" AS "SnapAcct",
                  CASE WHEN RL."LineId" IS NULL THEN NULL WHEN RL."Amount" = 0 THEN 'Y' ELSE 'N' END AS "ZeroAmt",
                  SA."StockAct",
                  (SELECT STRING_AGG(J."TransCode", ',') FROM "MTC_CA_R_JDT_SRC" J
                    WHERE J."RunId" = R."RunId" AND J."SrcType" = 'LINE' AND J."SrcKey" = TO_NVARCHAR(S."LineId")) AS "JdtCodes",
                  (SELECT COUNT(*) FROM "MTC_COST_0302_INVNTDETAIL1" O2
                    WHERE O2."FcCode" = F."FcCode" AND TO_NVARCHAR(O2."ObjType") = F."ObjType" AND O2."DocEntry" = F."DocEntry"
                      AND O2."LineNum" = L."LineNum" AND O2."CostCode" = '20') AS "Old0302",
                  (SELECT MAX(O2."TransCode") FROM "MTC_COST_0302_INVNTDETAIL1" O2
                    WHERE O2."FcCode" = F."FcCode" AND TO_NVARCHAR(O2."ObjType") = F."ObjType" AND O2."DocEntry" = F."DocEntry"
                      AND O2."LineNum" = L."LineNum" AND O2."CostCode" = '20') AS "Old0302Trans",
                  (SELECT COUNT(*) FROM "MTC_COST_0802_OJDTBASEDETAIL" O8
                    WHERE O8."FcCode" = F."FcCode" AND O8."TransCode" = 'YF01' AND TO_NVARCHAR(O8."U_ObjType") = F."ObjType"
                      AND TO_NVARCHAR(O8."U_DocEntry") = TO_NVARCHAR(F."DocEntry") AND TO_NVARCHAR(O8."U_LineNum") = TO_NVARCHAR(L."LineNum")) AS "Old0802"
             FROM F
             JOIN L ON L."ObjType" = F."ObjType" AND L."DocEntry" = F."DocEntry"
             LEFT JOIN R ON R."FcCode" = F."FcCode"
             LEFT JOIN "@U_CIOTRN" C ON C."Code" = F."U_TrsName"
             LEFT JOIN "OWHS" W ON W."WhsCode" = L."WhsCode"
             LEFT JOIN "MTC_CA_S_LINE" S ON S."RunId" = R."RunId" AND S."ObjType" = F."ObjType" AND S."DocEntry" = F."DocEntry" AND S."LineNum" = L."LineNum"
             LEFT JOIN "MTC_CA_R_LINE" RL ON RL."RunId" = S."RunId" AND RL."LineId" = S."LineId"
             LEFT JOIN "MTC_CA_S_ITEM" SI ON SI."RunId" = S."RunId" AND SI."ItemCode" = S."ItemCode"
             LEFT JOIN (SELECT "PeriodCat", TO_NVARCHAR("ItmsGrpCod") AS "ItmsGrpCod", MAX("StockAct") AS "StockAct" FROM "OGAR" GROUP BY "PeriodCat", "ItmsGrpCod") SA
                    ON SA."PeriodCat" = LEFT(F."FcCode", 4) AND SA."ItmsGrpCod" = TO_NVARCHAR(SI."ItmsGrpCod"))
SELECT "ObjType" AS "单据类型", "DocEntry" AS "单号 Entry", "DocNum" AS "单号 Num", "LineNum" AS "行号", "DocDate" AS "过账日期", "FcCode" AS "账期",
       "CANCELED" AS "取消", "U_TrsName" AS "业务类型", "MapTrans" AS "业务类型对应交易类型",
       "ItemCode" AS "物料编码", "WhsCode" AS "仓库", "U_IsCost" AS "计价仓库", "AcctCode" AS "行上科目", "StockAct" AS "存货科目",
       "RunId" AS "运行号", "LineId" AS "快照行 LineId", "SnapTrans" AS "快照交易类型", "NoCost" AS "快照不计成本", "ZeroAmt" AS "计算金额为0",
       "JdtCodes" AS "新框架凭证代码", "Old0302" AS "旧0302行数", "Old0302Trans" AS "旧0302交易类型", "Old0802" AS "旧YF01明细行数",
       CASE WHEN "FcCode" IS NULL THEN '过账日期没有对应账期'
            WHEN "RunId" IS NULL THEN '该账期没有成功的正式运行（或 P 里填的运行号不对）'
            WHEN IFNULL("U_IsCost", 'N') <> 'Y' THEN '不是计价仓库（U_IsCost <> Y），不进成本计算'
            WHEN "LineId" IS NULL THEN '计价仓库但不在快照里：OIVL 没有这行，或运行之后才建 / 改的单据'
            WHEN "SnapTrans" IS NULL THEN '交易类型识别不了（业务类型为空或 @U_CIOTRN 没配 U_IOType），PRE-05'
            WHEN "SnapTrans" NOT IN ('I04', 'O04') THEN '交易类型是 ' || "SnapTrans" || '，不走 YF01'
                 || CASE "SnapTrans" WHEN 'I10' THEN '（走 IO01）' WHEN 'O10' THEN '（走 IO01）' ELSE '' END
            WHEN "ZeroAmt" = 'Y' THEN '计算金额为 0，P70 不出分录'
            WHEN IFNULL("JdtCodes", '') = '' THEN '有金额但 R_JDT_SRC 没有：这次运行可能在 P70 之前就停了'
            WHEN "CANCELED" IN ('Y', 'C') THEN '已进 YF01 来源明细；单据已取消 / 是取消单，与对应单据在汇总凭证里相互抵消'
            WHEN "AcctCode" = "StockAct" THEN '已进 YF01 来源明细；行上科目 = 存货科目，借贷记同一科目'
            ELSE '已进 YF01 来源明细（' || "JdtCodes" || '），汇总在凭证的 行上科目 + 部门 + 项目 那一行里' END AS "判断"
  FROM X
 ORDER BY "LineNum"
