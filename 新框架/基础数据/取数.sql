-- 基础数据取数：在 FH100 上执行（只读，只建一张会话级临时表 #S，断开连接自动消失）
-- 目的：给测试库 TEST20261012 准备一套有代表性的主数据，覆盖 2026-09 的各类成本场景。
-- 用法：
--   1. 在同一个 SQL 控制台里按顺序执行【第一部分】，建立样本物料清单 #S。
--   2. 再逐条执行【第二部分】的 Q1…Q10，每条结果按导出科目表的方式另存为
--      新框架/基础数据/导出/<文件名>.txt（UTF-8、分号分隔、首行字段名）。文件名见每条上方。
--   3. 告诉我导完了，我用 Service Layer 导入 TEST20261012，只报行数和错误，不读明细。
-- 某条报“列不存在”时把那一列删掉再跑，告诉我删了哪列即可。

-- ======================== 第一部分：样本物料 ========================
CREATE LOCAL TEMPORARY TABLE "#S" ("ItemCode" NVARCHAR(50), "Src" NVARCHAR(20));

-- A. 最深 BOM：5 级产成品 3 个、3 级 2 个（当期有生产订单的）
INSERT INTO "#S" SELECT TOP 3 L."ItemCode", 'L5' FROM "U_COILV" L
 WHERE L."FcCode" = '2026-09' AND L."iLevel" = 5
   AND EXISTS (SELECT 1 FROM OWOR W, OFPR P WHERE P."Code" = '2026-09' AND W."ItemCode" = L."ItemCode" AND W."PostDate" BETWEEN P."F_RefDate" AND P."T_RefDate")
 GROUP BY L."ItemCode" ORDER BY L."ItemCode";
INSERT INTO "#S" SELECT TOP 2 L."ItemCode", 'L3' FROM "U_COILV" L
 WHERE L."FcCode" = '2026-09' AND L."iLevel" = 3
   AND EXISTS (SELECT 1 FROM OWOR W, OFPR P WHERE P."Code" = '2026-09' AND W."ItemCode" = L."ItemCode" AND W."PostDate" BETWEEN P."F_RefDate" AND P."T_RefDate")
 GROUP BY L."ItemCode" ORDER BY L."ItemCode";

-- B. 委外工单（WorType 50）2 个
INSERT INTO "#S" SELECT TOP 2 W."ItemCode", 'WW' FROM OWOR W, OFPR P
 WHERE P."Code" = '2026-09' AND W."U_OrdType" = '50' AND W."PostDate" BETWEEN P."F_RefDate" AND P."T_RefDate"
 GROUP BY W."ItemCode" ORDER BY W."ItemCode";

-- C. 返工单（@MTC_OWOR，WorType 30）2 个
INSERT INTO "#S" SELECT TOP 2 R."U_ItemCode", 'FG' FROM "@MTC_OWOR" R, OFPR P
 WHERE P."Code" = '2026-09' AND R."U_OrdType" = '30' AND R."U_PostDate" BETWEEN P."F_RefDate" AND P."T_RefDate"
 GROUP BY R."U_ItemCode" ORDER BY R."U_ItemCode";

-- D. 形态转换：204 收货的 A 物料 2 个 + 配对的 205 发出 B 物料
INSERT INTO "#S" SELECT TOP 2 N1."ItemCode", 'XT-A' FROM OIGN N0 JOIN IGN1 N1 ON N1."DocEntry" = N0."DocEntry", OFPR P
 WHERE P."Code" = '2026-09' AND N0."U_TrsName" = '204' AND N0."DocDate" BETWEEN P."F_RefDate" AND P."T_RefDate"
 GROUP BY N1."ItemCode" ORDER BY N1."ItemCode";
INSERT INTO "#S" SELECT DISTINCT E1."ItemCode", 'XT-B'
  FROM OIGN N0 JOIN IGN1 N1 ON N1."DocEntry" = N0."DocEntry"
  JOIN IGE1 E1 ON E1."U_BaseType" = N1."U_BaseType" AND E1."U_BaseEntry" = N1."U_BaseEntry" AND E1."U_BaseLineGrpNum" = N1."U_BaseLineGrpNum"
  JOIN OIGE E0 ON E0."DocEntry" = E1."DocEntry" AND E0."U_TrsName" = '205', OFPR P
 WHERE P."Code" = '2026-09' AND N0."U_TrsName" = '204' AND N0."DocDate" BETWEEN P."F_RefDate" AND P."T_RefDate"
   AND N1."ItemCode" IN (SELECT "ItemCode" FROM "#S" WHERE "Src" = 'XT-A');

-- E. 样本产品当期订单实际领用的物料（可能不在 BOM 里）
INSERT INTO "#S" SELECT DISTINCT W1."ItemCode", 'WOR1' FROM OWOR W0 JOIN WOR1 W1 ON W1."DocEntry" = W0."DocEntry", OFPR P
 WHERE P."Code" = '2026-09' AND W0."PostDate" BETWEEN P."F_RefDate" AND P."T_RefDate" AND W1."ItemType" = 4
   AND W0."ItemCode" IN (SELECT "ItemCode" FROM "#S")
   AND W1."ItemCode" NOT IN (SELECT "ItemCode" FROM "#S");
INSERT INTO "#S" SELECT DISTINCT R1."U_ItemCode", 'MWOR1' FROM "@MTC_OWOR" R0 JOIN "@MTC_WOR1" R1 ON R1."DocEntry" = R0."DocEntry", OFPR P
 WHERE P."Code" = '2026-09' AND R0."U_PostDate" BETWEEN P."F_RefDate" AND P."T_RefDate"
   AND R0."U_ItemCode" IN (SELECT "ItemCode" FROM "#S")
   AND R1."U_ItemCode" NOT IN (SELECT "ItemCode" FROM "#S");

-- F. 沿 BOM 往下展开子件。下面这条执行 8 次（最高 8 级），直到提示影响 0 行
INSERT INTO "#S" SELECT DISTINCT C."Code", 'BOM' FROM ITT1 C
 WHERE C."Type" = 4 AND C."Father" IN (SELECT "ItemCode" FROM "#S")
   AND C."Code" NOT IN (SELECT "ItemCode" FROM "#S");

-- 看一下样本规模（只需告诉我这个结果）
SELECT "Src", COUNT(DISTINCT "ItemCode") AS "物料数" FROM "#S" GROUP BY "Src" ORDER BY 1;

-- ======================== 第二部分：导出 ========================

-- Q1 → 01_货币.txt
SELECT "CurrCode", "CurrName", "ChkName", "Chk100Name", "DocCurrCod", "FrgnName", "F100Name", "Decimals", "RoundSys" FROM OCRN;

-- Q2 → 02_仓库.txt
SELECT "WhsCode", "WhsName", "Locked", "BalInvntAc", "SaleCostAc", "TransferAc", "VarianceAc", "PriceDifAc", "ExpensesAc",
       "RevenuesAc", "WipAcct", "DecreasAc", "IncreasAc", "ExchangeAc", "U_IsCost", "U_IsMRP", "U_MRPPrior", "U_ToWhsCode"
  FROM OWHS ORDER BY "WhsCode";

-- Q3 → 03_物料组.txt
SELECT "ItmsGrpCod", "ItmsGrpNam", "U_ItemGrpType", "BalInvntAc", "SaleCostAc", "TransferAc", "VarianceAc", "PriceDifAc",
       "ExpensesAc", "RevenuesAc", "WipAcct", "DecreasAc", "IncreasAc", "ExchangeAc"
  FROM OITB ORDER BY "ItmsGrpCod";

-- Q4 → 04_计量单位.txt（Q5 的 UgpEntry 全是 -1 时可跳过 Q4 和 Q4b）
SELECT "UomEntry", "UomCode", "UomName" FROM OUOM ORDER BY "UomEntry";
-- Q4b → 04b_计量单位组.txt
SELECT G."UgpEntry", G."UgpCode", G."UgpName", G."BaseUom", L."UomEntry", L."AltQty", L."BaseQty"
  FROM OUGP G JOIN UGP1 L ON L."UgpEntry" = G."UgpEntry"
 WHERE G."UgpEntry" IN (SELECT "UgpEntry" FROM OITM WHERE "ItemCode" IN (SELECT "ItemCode" FROM "#S"))
 ORDER BY G."UgpEntry", L."UomEntry";

-- Q5 → 05_物料.txt
SELECT M."ItemCode", M."ItemName", M."ItmsGrpCod", M."InvntItem", M."SellItem", M."PrchseItem", M."InvntryUom", M."BuyUnitMsr",
       M."SalUnitMsr", M."UgpEntry", M."EvalSystem", M."GLMethod", M."ManBtchNum", M."ManSerNum", M."DfltWH", M."PrcrmntMtd",
       M."validFor", M."frozenFor", M."U_ItemProp", M."U_FinType", M."U_RawOrWrap", M."U_Specs", M."U_Ver", M."U_KeyItem",
       (SELECT STRING_AGG(X."Src", ',') FROM "#S" X WHERE X."ItemCode" = M."ItemCode") AS "Src"
  FROM OITM M WHERE M."ItemCode" IN (SELECT "ItemCode" FROM "#S") ORDER BY M."ItemCode";

-- Q6 → 06_BOM表头.txt
SELECT "Code", "TreeType", "Qauntity", "ToWH", "U_VerNo", "U_Status", "U_ProdLossRate"
  FROM OITT WHERE "Code" IN (SELECT "ItemCode" FROM "#S") ORDER BY "Code";

-- Q7 → 07_BOM明细.txt（子件全部在样本里，导入时不会缺物料）
SELECT "Father", "ChildNum", "VisOrder", "Code", "Type", "Quantity", "Warehouse", "IssueMthd",
       "U_BaseQty", "U_ItemLossRate", "U_UnitQty", "U_IsComSub"
  FROM ITT1 WHERE "Father" IN (SELECT "ItemCode" FROM "#S") AND ("Type" <> 4 OR "Code" IN (SELECT "ItemCode" FROM "#S"))
 ORDER BY "Father", "VisOrder";

-- Q8 → 08_业务伙伴组.txt
SELECT "GroupCode", "GroupName", "GroupType" FROM OCRG ORDER BY "GroupCode";

-- Q9 → 09_业务伙伴.txt（名称已脱敏：供应商001 / 客户001）
--   委外订单的加工商 + 样本物料当期采购最多的 5 家供应商 + 交货最多的 3 家客户
SELECT B."CardCode", B."CardType",
       CASE B."CardType" WHEN 'S' THEN '供应商' ELSE '客户' END
         || LPAD(TO_NVARCHAR(ROW_NUMBER() OVER (PARTITION BY B."CardType" ORDER BY B."CardCode")), 3, '0') AS "CardName",
       B."GroupCode", B."Currency", B."DebPayAcct", B."validFor", B."frozenFor"
  FROM OCRD B
 WHERE B."CardCode" IN (
        SELECT W."CardCode" FROM OWOR W, OFPR P
         WHERE P."Code" = '2026-09' AND W."U_OrdType" = '50' AND W."ItemCode" IN (SELECT "ItemCode" FROM "#S")
           AND W."PostDate" BETWEEN P."F_RefDate" AND P."T_RefDate" AND W."CardCode" IS NOT NULL
        UNION
        SELECT "CardCode" FROM (
          SELECT TOP 5 D0."CardCode" FROM OPDN D0 JOIN PDN1 D1 ON D1."DocEntry" = D0."DocEntry", OFPR P
           WHERE P."Code" = '2026-09' AND D0."DocDate" BETWEEN P."F_RefDate" AND P."T_RefDate"
             AND D1."ItemCode" IN (SELECT "ItemCode" FROM "#S")
           GROUP BY D0."CardCode" ORDER BY COUNT(*) DESC)
        UNION
        SELECT "CardCode" FROM (
          SELECT TOP 3 D0."CardCode" FROM ODLN D0 JOIN DLN1 D1 ON D1."DocEntry" = D0."DocEntry", OFPR P
           WHERE P."Code" = '2026-09' AND D0."DocDate" BETWEEN P."F_RefDate" AND P."T_RefDate"
             AND D1."ItemCode" IN (SELECT "ItemCode" FROM "#S")
           GROUP BY D0."CardCode" ORDER BY COUNT(*) DESC))
 ORDER BY B."CardType", B."CardCode";

-- Q10 → 10_过账期间.txt（测试库要有 2026-09 等期间才能过账）
SELECT "Code", "Name", "F_RefDate", "T_RefDate", "F_DueDate", "T_DueDate", "F_TaxDate", "T_TaxDate", "PeriodStat", "Category"
  FROM OFPR WHERE "Code" >= '2026-01' ORDER BY "Code";

DROP TABLE "#S";
