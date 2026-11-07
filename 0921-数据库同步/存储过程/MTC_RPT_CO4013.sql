CREATE PROCEDURE "MTC_RPT_CO4013"
(
  IN STYPE INT,	--0汇总  1明细
  IN sdate DATE,
  IN edate DATE,
  IN ItemCode NVARCHAR(50)
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 
	--CALL "MTC_RPT_CO4013"('2025-06-01','2025-06-30','')
	
	TMP_QC=
	SELECT -1 AS "ObjType"
	,T1."DocEntry",T1."DocEntry" AS "DocNum"
	,'202' AS "WorType",-1 AS "WorEntry",-1 AS "WorNum",'50' AS "U_OrdType",'' AS "Status",'2024-12-31' AS "DocDate"
	,T2."CardCode",T2."CardName",T1."U_Text1" AS "ItemCode"
	--,T2."PlannedQty" AS "子件计划数量"
	,T1."U_Dec1" AS "S_IgeQty"
	,0.00 AS "Due_IgeQty"
	,0.00 AS "E_IgeQty"
	,0.00 AS "S_IgnQty"
	,0.00 AS "Due_IgnQty"
	,-1*T1."U_Dec1" AS "E_IgnQty"
	FROM "@MTC_IMPT1" T1
	LEFT JOIN OCRD T2 ON T1."U_Text2"=T2."CardCode"
	WHERE T1."DocEntry"=10;
	
	TMP_In=
	SELECT T0."ObjType",T0."DocEntry",T0."DocNum",'202' AS "WorType",T1."DocEntry" AS "WorEntry",T1."DocNum" AS "WorNum",T1."U_OrdType",T1."Status",T0."DocDate"
	,T3."CardCode",T3."CardName",T0."ItemCode"
	--,T2."PlannedQty" AS "子件计划数量"
	,T0."S_IgeQty"
	,T0."Due_IgeQty"
	,T0."E_IgeQty"
	,0.00 AS "S_IgnQty"
	,0.00 AS "Due_IgnQty"
	,0.00 AS "E_IgnQty"
	FROM (SELECT "ObjType","DocEntry","DocNum","OWOREntry","OWORNum","ItemCode","DocDate"
			,-1*(CASE WHEN "DocDate"<:sdate THEN "Quantity" ELSE 0 END) AS "S_IgeQty"
			,-1*(CASE WHEN "DocDate">=:sdate AND "DocDate"<=:edate THEN "Quantity" ELSE 0 END) AS "Due_IgeQty"
			,-1*(CASE WHEN "DocDate"<=:edate THEN "Quantity" ELSE 0 END) AS "E_IgeQty"
			FROM "MTC_VIEW_ProductDetail"
			WHERE "DocDate"<=:edate AND "ID"<>3 AND "Type"='子件'
			AND "DocDate">='2025-01-01'
			 --GROUP BY "OWOREntry","OWORNum","ItemCode"
			) T0
	LEFT JOIN OWOR T1 ON T0."OWOREntry"=T1."DocEntry"
	LEFT JOIN OCRD T3 ON T1."U_CardCode"=T3."CardCode"
	WHERE 1=1
	AND T1."U_OrdType"='50'
	--AND T1."DocNum"=301
	;
	
	TMP_Out=
	SELECT T0."ObjType",T0."DocEntry",T0."DocNum",'202' AS "WorType",T1."DocEntry" AS "WorEntry",T1."DocNum" AS "WorNum",T1."U_OrdType",T1."Status",T0."DocDate"
	--,T0."IgnQty" AS "主件实际领料",T1."PlannedQty" AS "主件计划数量"
	,T3."CardCode",T3."CardName",T2."ItemCode"
	--,T2."PlannedQty" AS "子件计划数量"
	,0.00 AS "S_IgeQty"
	,0.00 AS "Due_IgeQty"
	,0.00 AS "E_IgeQty"
	,T0."S_IgnQty"*T2."PlannedQty"/T1."PlannedQty"
	,T0."Due_IgnQty"*T2."PlannedQty"/T1."PlannedQty"
	,T0."E_IgnQty"*T2."PlannedQty"/T1."PlannedQty"
	FROM (SELECT "ObjType","DocEntry","DocNum","OWOREntry","OWORNum","DocDate"
			,(CASE WHEN "DocDate"<:sdate THEN "Quantity" ELSE 0 END) AS "S_IgnQty"
			,(CASE WHEN "DocDate">=:sdate AND "DocDate"<=:edate THEN "Quantity" ELSE 0 END) AS "Due_IgnQty"
			,(CASE WHEN "DocDate"<=:edate THEN "Quantity" ELSE 0 END) AS "E_IgnQty"
			FROM "MTC_VIEW_ProductDetail"
			WHERE "DocDate"<=:edate AND "Type"='主件'
			AND "DocDate">='2025-01-01' --GROUP BY "OWOREntry","OWORNum"
			) T0
	LEFT JOIN OWOR T1 ON T0."OWOREntry"=T1."DocEntry"
	LEFT JOIN WOR1 T2 ON T1."DocEntry"=T2."DocEntry"
	LEFT JOIN OCRD T3 ON T1."U_CardCode"=T3."CardCode"
	WHERE 1=1
	AND T1."U_OrdType"='50'
	--AND T1."DocNum"=301
	;
	
	--汇总
	IF :STYPE = 0 THEN
	
		SELECT 
		 T0."CardCode",T0."CardName",T0."ItemCode",T1."ItemName"
		,SUM(IFNULL(T0."S_IgeQty",0)-IFNULL(T0."S_IgnQty",0)) AS "期初数量"
		,SUM(IFNULL(T0."Due_IgeQty",0)) AS "委外发出(入库)"
		,SUM(IFNULL(T0."Due_IgnQty",0)) AS "委外收回(出库)"
		,SUM(IFNULL(T0."E_IgeQty",0)-IFNULL(T0."E_IgnQty",0)) AS "期末数量"
		,:sdate AS sdate
		,:edate AS edate
		FROM (
			SELECT * FROM :TMP_QC
			UNION ALL
			SELECT * FROM :TMP_In
			UNION ALL
			SELECT * FROM :TMP_Out
			) T0
		LEFT JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
		--LEFT JOIN (SELECT * FROM MTC_COST_0301_INVNT WHERE "FcCode"='[%0]' AND "CostCode"='20') T1 ON T0."ItemCode"=T1."ItemCode"
		WHERE 1=1
		AND T1."InvntItem"='Y'
		GROUP BY T0."CardCode",T0."CardName",T0."ItemCode",T1."ItemName"
		ORDER BY T0."CardCode",T0."ItemCode"
		;
	--明细
	ELSEIF :STYPE = 1 THEN
	
		SELECT T0."类型",T0."ObjType",T0."DocEntry",T0."DocNum" AS "出入库单号",T0."DocDate" AS "日期",T0."WorEntry" AS "生产订单号Entry",T0."WorNum" AS "生产订单号Num"
		,T0."CardCode",T0."CardName",T0."ItemCode"
		,T0."Due_IgeQty" AS "委外发出(入库)"
		,T0."Due_IgnQty" AS "委外收回(出库)"
		 FROM (
			SELECT '期初' AS "类型",* FROM :TMP_QC
			UNION ALL
			SELECT '材料领用' AS "类型",* FROM :TMP_In WHERE "DocDate">=:sdate AND "DocDate"<=:edate
			UNION ALL
			SELECT '入库倒冲' AS "类型",* FROM :TMP_Out  WHERE "DocDate">=:sdate AND "DocDate"<=:edate
			) T0 WHERE (T0."ItemCode"=:ItemCode OR :ItemCode = '')
			ORDER BY T0."ItemCode",T0."DocDate",T0."DocEntry"
			;
	--按订单汇总
	ELSEIF :STYPE = 2 THEN
	
		SELECT 
		T0."WorType" AS "生产订单类型"
		,CASE T0."U_OrdType" WHEN 10 THEN '生产计划单' WHEN 20 THEN '包装计划单' WHEN 30 THEN '返工计划单' WHEN 40 
			THEN '生产试打' WHEN 50 THEN '委外工单' END AS "工单类型"
		,T0."WorEntry" AS "生产订单号Entry",T0."WorNum" AS "生产订单号Num"
		,CASE WHEN T1."Status"='R' THEN '已下达' WHEN T1."Status"='L' THEN '已结算' WHEN T1."Status"='P' THEN '已计划' END AS "生产订单状态"
		,T1."CloseDate" AS "生产订单关闭日期"
		,T0."CardCode",T0."CardName",T0."ItemCode",T5."ItemName"
		,SUM(CASE WHEN T0."类型"='期初' THEN IFNULL(T0."Due_IgeQty",0)-IFNULL(T0."Due_IgnQty",0) ELSE 0 END) AS "期初数量"
		,SUM(T0."Due_IgeQty") AS "委外发出(入库)"
		,SUM(T0."Due_IgnQty") AS "委外收回(出库)"
		,SUM(IFNULL(T0."Due_IgeQty",0)-IFNULL(T0."Due_IgnQty",0)) AS "库存数量"
		 FROM (
			SELECT '期初' AS "类型",* FROM :TMP_QC
			UNION ALL
			SELECT '材料领用' AS "类型",* FROM :TMP_In WHERE "DocDate">=:sdate AND "DocDate"<=:edate
			UNION ALL
			SELECT '入库倒冲' AS "类型",* FROM :TMP_Out  WHERE "DocDate">=:sdate AND "DocDate"<=:edate
			) T0
		LEFT JOIN (SELECT '202' AS "ObjType","DocEntry","DocNum","Status","CloseDate" FROM OWOR 
			) T1 ON T0."WorType"=T1."ObjType" AND T0."WorEntry"=T1."DocEntry"
		LEFT JOIN OITM T5 ON T0."ItemCode"=T5."ItemCode"
		WHERE (T0."ItemCode"=:ItemCode OR :ItemCode = '')
		GROUP BY T0."WorType",T0."U_OrdType",T0."WorEntry",T0."WorNum",T1."Status",T1."CloseDate",T0."CardCode",T0."CardName",T0."ItemCode",T5."ItemName"
			ORDER BY T0."ItemCode",T0."WorEntry"
			;
	
	--从订单角度看
	ELSEIF :STYPE = 3 THEN 
		SELECT T6."CardCode",T6."CardName"
		,T1."DocEntry" AS "OWOREntry",T1."DocNum" AS "OWORNum"
		,T0."IgnQty"
		,T1."CloseDate",T1."PostDate"
		,T4."ItemCode",T5."ItemName",T5."U_Specs" AS "规格",T5."InvntryUom" AS "单位"
		,T2."PlannedQty"/T1."PlannedQty" AS "料比"
		,-1*T4."IgeQty" AS "领料发出"
		,T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty" AS "倒冲入库"
		,IFNULL(-1*T4."IgeQty",0)-IFNULL(T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty",0) AS "结存数量"
		,T10."Price" AS "结存单价"
		,(IFNULL(-1*T4."IgeQty",0)-IFNULL(T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty",0))*IFNULL(T10."Price",0) AS "结存金额"
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
			AND T1."U_OrdType"='50'
			
			ORDER BY T1."PostDate";
	END IF;
	
	
END