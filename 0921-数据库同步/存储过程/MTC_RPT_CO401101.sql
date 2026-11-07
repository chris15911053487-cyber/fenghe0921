CREATE PROCEDURE "MTC_RPT_CO401101"
(
  IN OrdType NVARCHAR(50) ,  --生产工单/委外工单
  IN STYPE INT,	--0汇总  1明细 3对比表
  IN sdate DATE,
  IN edate DATE,
  IN ItemCode NVARCHAR(50)
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 
	
	TMP_DETAIL=
	SELECT T6."CardCode",T6."CardName",T1."U_SupNum",'202' AS "WorType" --"生产订单类型"
	,CASE T1."U_OrdType" WHEN 10 THEN '生产计划单' WHEN 20 THEN '包装计划单' WHEN 30 THEN '返工计划单' 
	WHEN 40 THEN '生产试打' WHEN 50 THEN '委外工单' END AS "OcdType" --"工单类型"
	,T1."DocEntry" AS "OWOREntry"
	,T1."DocNum" AS "OWORNum"
	,CASE T1."Status" WHEN 'P' THEN '已计划' WHEN 'R' THEN '已下达' WHEN 'L' THEN '已结算' WHEN 'C' THEN '已取消' END AS "Status"
	,T0."IgnQty"
	,T1."CloseDate"
	,T1."PostDate"
	,T4."ItemCode"
	,T5."ItemName"
	,T5."U_Specs"
	,T5."InvntryUom"
	,T2."PlannedQty"/T1."PlannedQty" AS "Prc"	--料比
	,-1*T4."IgeQty" AS "InQty"  --领料发出
	,T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty" AS "OutQty" --"倒冲入库"
	,IFNULL(-1*T4."IgeQty",0)-IFNULL(T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty",0) AS "InvntQty" -- "结存数量"
	,CASE WHEN T1."CloseDate"<=:edate AND T1."Status" IN ('C','L') THEN 0
			ELSE IFNULL(-1*T4."IgeQty",0)-IFNULL(T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty",0)
			END AS "ActInvntQty" -- "结存数量"
	,T10."Price" AS "InvntPrice" --"单价"
	,CASE WHEN T1."CloseDate"<=:edate AND T1."Status" IN ('C','L') THEN 0
		ELSE (IFNULL(-1*T4."IgeQty",0)-IFNULL(T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty",0))*IFNULL(T10."Price",0)
		END AS "InvntAmt"  --"结存金额"
	FROM OWOR T1
	JOIN (SELECT "DocEntry","ItemCode",SUM("PlannedQty") AS "PlannedQty"
			FROM WOR1 GROUP BY "DocEntry","ItemCode") T2 ON T1."DocEntry"=T2."DocEntry"
	LEFT JOIN (SELECT "OWOREntry","OWORNum"
			,SUM("Quantity") AS "IgnQty"
			FROM "MTC_VIEW_ProductDetail"
			WHERE 1=1 AND "Type"='主件' AND "DocDate"<=:edate
			GROUP BY "OWOREntry","OWORNum"
			) T0 ON T0."OWOREntry"=T1."DocEntry"
	JOIN (SELECT "OWOREntry","OWORNum","ItemCode",SUM("Quantity") AS "IgeQty"
			FROM "MTC_VIEW_ProductDetail"
			WHERE "Type"='子件' AND "DocDate"<=:edate
			GROUP BY "OWOREntry","OWORNum","ItemCode" 
		) T4 ON T2."DocEntry"=T4."OWOREntry" AND T2."ItemCode"=T4."ItemCode"
	LEFT JOIN OCRD T6 ON T1."U_CardCode"=T6."CardCode"
	LEFT JOIN OITM T5 ON T2."ItemCode"=T5."ItemCode"
	LEFT JOIN (SELECT "ItemCode","Price",ROW_NUMBER() OVER(PARTITION BY "ItemCode" ORDER BY "FcCode" DESC) AS "ID"
				FROM MTC_COST_0301_INVNT 
				WHERE "FcCode"<=TO_CHAR(:edate,'YYYY-MM') AND "CostCode"='20' AND "Price"<>0
				) T10 ON T5."ItemCode"=T10."ItemCode" AND T10."ID"=1
	WHERE 1=1
	AND T1."U_OrdType" NOT IN ('40')
	AND ((:OrdType='生产工单' AND T1."U_OrdType" IN ('10','20','30'))
			OR (:OrdType='委外工单' AND T1."U_OrdType"='50')
			)
	AND IFNULL(-1*T4."IgeQty",0)-IFNULL(T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty",0)<>0
	
	UNION ALL
	SELECT T6."CardCode",T6."CardName",T1."U_SupNum",T1."Object" AS "生产订单类型"
	,CASE T1."U_OrdType" WHEN 10 THEN '生产计划单' WHEN 20 THEN '包装计划单' WHEN 30 THEN '返工计划单' 
	WHEN 40 THEN '生产试打' WHEN 50 THEN '委外工单' END AS "工单类型",T1."DocEntry" AS "OWOREntry",T1."DocNum" AS "OWORNum"
	,CASE T1."U_Status" WHEN 'P' THEN '已计划' WHEN 'R' THEN '已下达' WHEN 'L' THEN '已结算' WHEN 'C' THEN '已取消' END AS "U_Status",T0."IgnQty"
	,T1."U_CloseDate" AS "CloseDate",T1."U_PostDate" AS "PostDate"
	,T4."ItemCode",T5."ItemName"
	,T5."U_Specs"
	,T5."InvntryUom",T2."PlannedQty"/T1."U_PlannedQty" AS "料比"
	,-1*T4."IgeQty" AS "领料发出"
	,T0."IgnQty"*T2."PlannedQty"/T1."U_PlannedQty" AS "倒冲入库"
	,IFNULL(-1*T4."IgeQty",0)-IFNULL(T0."IgnQty"*T2."PlannedQty"/T1."U_PlannedQty",0) AS "结存数量"
	,CASE WHEN T1."U_CloseDate"<=:edate AND T1."U_Status" IN ('C','L') THEN 0 
		ELSE IFNULL(-1*T4."IgeQty",0)-IFNULL(T0."IgnQty"*T2."PlannedQty"/T1."U_PlannedQty",0)
		END AS "计入结存数量"
	,T10."Price"
	,CASE WHEN T1."U_CloseDate"<=:edate AND T1."U_Status" IN ('C','L') THEN 0 
		ELSE (IFNULL(-1*T4."IgeQty",0)-IFNULL(T0."IgnQty"*T2."PlannedQty"/T1."U_PlannedQty",0))*IFNULL(T10."Price",0)
		END AS "结存金额"
	FROM "@MTC_OWOR" T1
	JOIN (SELECT "DocEntry","U_ItemCode" AS "ItemCode",SUM("U_PlannedQty") AS "PlannedQty"
			FROM "@MTC_WOR1" GROUP BY "DocEntry","U_ItemCode") T2 ON T1."DocEntry"=T2."DocEntry"
	LEFT JOIN (SELECT "BaseEntry" AS "OWOREntry"
			,SUM("Quantity") AS "IgnQty"
			FROM "MTC_VIEW_ProductDetail_MTCOWOR"
			WHERE 1=1 AND "Type"='主件' AND "DocDate"<=:edate
			GROUP BY "BaseEntry"
			) T0 ON T0."OWOREntry"=T1."DocEntry"
	JOIN (SELECT "BaseEntry" AS "OWOREntry","ItemCode" AS "ItemCode",SUM("Quantity") AS "IgeQty"
			FROM "MTC_VIEW_ProductDetail_MTCOWOR"
			WHERE "Type"='子件' AND "DocDate"<=:edate
			GROUP BY "BaseEntry","ItemCode" 
		) T4 ON T2."DocEntry"=T4."OWOREntry" AND T2."ItemCode"=T4."ItemCode"
	LEFT JOIN OCRD T6 ON T1."U_CardCode"=T6."CardCode"
	LEFT JOIN OITM T5 ON T2."ItemCode"=T5."ItemCode"
	LEFT JOIN (SELECT "ItemCode","Price",ROW_NUMBER() OVER(PARTITION BY "ItemCode" ORDER BY "FcCode" DESC) AS "ID"
				FROM MTC_COST_0301_INVNT 
				WHERE "FcCode"<=TO_CHAR(:edate,'YYYY-MM') AND "CostCode"='20' AND "Price"<>0
				) T10 ON T5."ItemCode"=T10."ItemCode" AND T10."ID"=1
	WHERE 1=1
	AND T1."U_OrdType" NOT IN ('40')
	AND ((:OrdType='生产工单' AND T1."U_OrdType" IN ('10','20','30'))
			OR (:OrdType='委外工单' AND T1."U_OrdType"='50')
			)
	AND IFNULL(-1*T4."IgeQty",0)-IFNULL(T0."IgnQty"*T2."PlannedQty"/T1."U_PlannedQty",0)<>0
	
	ORDER BY T1."PostDate";
	
	IF :STYPE = 2 THEN
		SELECT 
		T0."U_SupNum"
		,T0."WorType" 	--"生产订单类型"
		,T0."OcdType" 			--"工单类型"
		,T0."OWOREntry"
		,T0."OWORNum"
		,T0."Status"
		,T0."CloseDate"
		,T0."PostDate"
		,SUM(T0."InQty") AS "InQty"  			--领料发出
		,SUM(T0."OutQty") AS "OutQty" 			--"倒冲入库"
		,SUM(T0."InvntQty") AS "InvntQty" 			-- "结存数量"
		,SUM(T0."ActInvntQty") AS "ActInvntQty" 			-- "结存数量"
		--,T0."InvntPrice" 		--"单价"
		,SUM(T0."InvntAmt") AS "InvntAmt"
		,T0."CardCode",T0."CardName"
		FROM :TMP_DETAIL T0
		GROUP BY T0."U_SupNum",T0."WorType" 	--"生产订单类型"
		,T0."OcdType" 			--"工单类型"
		,T0."OWOREntry"
		,T0."OWORNum"
		,T0."Status"
		,T0."CloseDate"
		,T0."PostDate"--,T0."InvntPrice"
		,T0."CardCode",T0."CardName"
		ORDER BY T0."PostDate"
		;
		
	ELSEIF :STYPE = 1 THEN 
		SELECT T0."U_SupNum",T0."WorType" 	--"生产订单类型"
		,T0."OcdType" 			--"工单类型"
		,T0."OWOREntry"
		,T0."OWORNum"
		,T0."Status"
		,T0."IgnQty"
		,T0."CloseDate"
		,T0."PostDate"
		,T0."ItemCode"
		,T0."ItemName"
		,T0."U_Specs"
		,T0."InvntryUom"
		,T0."Prc"				--料比
		,T0."InQty"  			--领料发出
		,T0."OutQty" 			--"倒冲入库"
		,T0."InvntQty" 			-- "结存数量"
		,T0."ActInvntQty" 			-- "结存数量"
		,T0."InvntPrice" 		--"单价"
		,T0."InvntAmt"
		,T0."CardCode",T0."CardName"
		FROM :TMP_DETAIL T0
		ORDER BY T0."PostDate"
		;
	ELSEIF :STYPE = 3 THEN
	
		TMP_OJDT = 
		SELECT T2."AcctCode",T2."AcctName",SUM(T1."Debit"-T1."Credit") AS "OJDTAmt"
		FROM "OJDT" T0
		JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
		JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
		WHERE T0."RefDate"<=:edate
		AND T2."AcctCode"='500101'
		GROUP BY T2."AcctCode",T2."AcctName"
		;
		
		SELECT 
		TO_CHAR(:edate,'YYYY-MM') AS "期间"
		,T0."PrjName" AS "项目"
		,SUM(T0."InvntAmt") AS "在产品结存金额"
		,SUM(T0."OJDTAmt") AS "分录结存金额"
		,SUM(T0."InvntAmt")-SUM(T0."OJDTAmt") AS "差异"
		FROM (
			SELECT '生产成本-在产品' AS "PrjName",SUM(T0."InvntAmt") AS "InvntAmt",0.00 AS "OJDTAmt"
			FROM :TMP_DETAIL T0
			WHERE T0."InvntQty">0
			UNION ALL
			SELECT '生产成本-在产品' AS "PrjName",0.00 AS "InvntAmt",SUM("OJDTAmt") AS "OJDTAmt" FROM :TMP_OJDT
			) T0
		GROUP BY T0."PrjName";
		
	END IF;
	
END