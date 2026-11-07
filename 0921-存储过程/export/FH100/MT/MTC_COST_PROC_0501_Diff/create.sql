CREATE PROCEDURE "MTC_COST_PROC_0501_Diff"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 抽取物料等级 到 明细到静态表 MTC_COST_0105_ITEM
     * CALL "MTC_COST_PROC_0401_CAL"(0,'2024-01','manager');
    */
    
    DECLARE CNT INT = 0;
    DECLARE ILEVEL INT = 1;
    DECLARE MAXLEVEL INT = 0;
    DECLARE edate DATE;
    
    
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
  	
  	SELECT "T_RefDate" INTO edate FROM "OFPR" WHERE "Code"=:FcCode;
  	
    
    TMP_OMRV=
    SELECT 'InvntCost' AS "U_CalType"
    ,T0."ItemCode" AS "U_ItemCode"
    ,T0."ItemName" AS "U_ItemName"
    ,0 AS "U_Quantity",0 AS "U_Price"
	,-1*T0."QM_Amount" AS "U_Amount"
	,NULL AS "U_BaseType",NULL AS "U_BaseEntry",NULL AS "U_BaseNum",NULL AS "U_BaseLine"
	,T4."AcctCode" AS "U_StockCode",T4."AcctName" AS "U_StockName"
	,T5."AcctCode" AS "U_AcctCode",T5."AcctName" AS "U_AcctName"
	FROM MTC_COST_0301_INVNT T0
	JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
	LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
		) T3 ON T1."ItmsGrpCod"=T3."ItmsGrpCod"
	LEFT JOIN "OACT" T4 ON T3."StockAct"=T4."AcctCode"
	LEFT JOIN OACT T5 ON T5."AcctCode"='510197'
	WHERE T0."FcCode"=:FcCode
	AND T0."QM_Qty"=0 AND T0."QM_Amount"<>0;
    
	--0数量、有金额的差异
	DELETE FROM "@MTC_OMRV" WHERE "U_DocDate"=:edate AND "U_BaseType"='MRV2';
	DELETE FROM "@MTC_OMRV1" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_OMRV");
	
	INSERT INTO "@MTC_OMRV"("DocEntry","DocNum","Object","Canceled","U_DocDate"
	,"U_BaseType","U_Memo","U_Total")
	SELECT TOP 1 U_MTC_OMRV_S.NEXTVAL AS "DocEntry",U_MTC_OMRV_S.NEXTVAL AS "DocNum",'MTC_OMRV','N',:edate
		,'MRV2','0数量，有金额的差异' AS "Memo",T0."Total"
		FROM (SELECT SUM("U_Amount") AS "Total" FROM :TMP_OMRV T0) T0;
	
	INSERT INTO "@MTC_OMRV1"(
		"DocEntry","LineId","U_LineMemo"
		,"U_CalType","U_ItemCode","U_ItemName"
		,"U_Quantity","U_Price","U_Amount"
		,"U_BaseType","U_BaseEntry","U_BaseNum","U_BaseLine"
		,"U_StockCode","U_StockName","U_AcctCode","U_AcctName"
		)
	SELECT T1."DocEntry"
		,ROW_NUMBER() OVER (ORDER BY T0."U_ItemCode") AS "LineId"
		,'期末0数量、有金额的差异' AS "U_LineMemo",'ProCost' AS "U_CalType"
		,T2."ItemCode",T2."ItemName"
		,T0."U_Quantity",T0."U_Price",T0."U_Amount"
		,T0."U_BaseType",T0."U_BaseEntry",T0."U_BaseNum",T0."U_BaseLine"
		,T4."AcctCode",T4."AcctName",T6."AcctCode",T6."AcctName"
		FROM :TMP_OMRV T0
		LEFT JOIN (SELECT "DocEntry" FROM "@MTC_OMRV" WHERE "U_DocDate"=:edate AND "U_BaseType"='MRV2' AND "Canceled"='N') T1 ON 1=1
		JOIN "OITM" T2 ON T0."U_ItemCode"=T2."ItemCode"
		LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
			) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
		LEFT JOIN OACT T4 ON T3."StockAct"=T4."AcctCode"
		LEFT JOIN "@MTC_MRVTYPE" T5 ON T5."Code"='MRV2'
		LEFT JOIN OACT T6 ON T6."AcctCode"=T5."U_AcctCode"
		WHERE 1=1
	;
	
	INSERT INTO "MTC_COST_0302_INVNTDETAIL1"
	("BPLId","FcCode","ObjType","DocEntry","DocNum","LineNum",
		"DocDate","CostCode","TransCode",
		"ItemCode","ItemName","ItmsGrpCod","CalType",
		"Quantity","Amount","Price","WhsCode",
		"PriceMemo","IsUpdatePrice","AcctCode"
	)
	SELECT 0 AS "BPLId"
	,:FcCode AS "FcCode"
	,T0."Object",T0."DocEntry",T0."DocNum",T1."LineId"
	,T0."U_DocDate",'20','I11' AS "TransCode"
	,T1."U_ItemCode",T1."U_ItemName",T2."ItmsGrpCod",'01' AS "CalType"
	,T1."U_Quantity",T1."U_Amount",T1."U_Price"
	,'' AS "WhsCode",'库存重估MRV2','MRV2' AS "IsUpdatePrice",'' AS "AcctCode"
	FROM "@MTC_OMRV" T0
	JOIN "@MTC_OMRV1" T1 ON T0."DocEntry"=T1."DocEntry"
	JOIN OITM T2 ON T1."U_ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."U_BaseType"='MRV2'
	AND TO_CHAR(T0."U_DocDate",'YYYY-MM')=:FcCode
	;
	
	
	--写入进销存列表（最终的加权单价）
    UPDATE T0 SET 
     T0."In_Amount"=ROUND(IFNULL(T1."In_Amt",0),2)
    ,T0."In_Price"=ROUND(IFNULL(T1."In_Amt",0)/NULLIF(IFNULL(T1."In_Qty",0),0),6)
    ,T0."Out_Amount"=ROUND(IFNULL(T1."Out_Amt",0),2)
    ,T0."Out_Price"=ROUND(IFNULL(T1."Out_Amt",0)/NULLIF(IFNULL(T1."Out_Qty",0),0),6)
    ,T0."QM_Amount"=ROUND(ROUND(IFNULL(T0."QC_Amount",0),2)+ROUND(IFNULL(T1."Amt",0),2),2)
    ,T0."Price"=ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6)
    ,T0."QM_Price"=ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF(IFNULL(T0."QM_Qty",0),0),6)
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.91写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT T1."FcCode",T1."ItemCode"
			,SUM(T1."Quantity") AS "Qty"
			,SUM(T1."Amount") AS "Amt"
			,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Quantity" ELSE 0 END) AS "In_Qty"
			,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Amount" ELSE 0 END) AS "In_Amt"
			,SUM(CASE WHEN T2."U_IOType"='O' THEN -1*T1."Quantity" ELSE 0 END) AS "Out_Qty"
			,SUM(CASE WHEN T2."U_IOType"='O' THEN -1*T1."Amount" ELSE 0 END) AS "Out_Amt"
			FROM "MTC_COST_0302_INVNTDETAIL1" T1
			JOIN "@MTC_COST_IOTYPE" T2 ON T1."TransCode"=T2."Code"
			WHERE 1=1 AND T1."FcCode"=:FcCode-- AND T1."ItemCode"='102000095'
			GROUP BY T1."FcCode",T1."ItemCode"
    	) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
    WHERE T0."CostCode"='20'
	AND T0."FcCode"=:FcCode	--20材料
    ;
	
    
	SELECT 0 AS "代码",'差异计算完成'||:FcCode||',成功！' AS "信息" FROM DUMMY;

END