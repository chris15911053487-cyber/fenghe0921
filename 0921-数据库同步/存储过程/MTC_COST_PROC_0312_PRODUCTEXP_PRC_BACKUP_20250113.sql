CREATE PROCEDURE "MTC_COST_PROC_0312_PRODUCTEXP_PRC_BACKUP_20250113"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 费用归集表 MTC_COST_0312_PRODUCTEXP_PRC
     * CALL "MTC_COST_PROC_0312_PRODUCTEXP_PRC"(0,'2024-01','manager');
    */
	DELETE FROM MTC_COST_0312_PRODUCTEXP_PRC WHERE "FcCode" = :FcCode;
	DELETE FROM MTC_COST_0321_OWOR2 WHERE "FcCode" = :FcCode;
	
	INSERT INTO MTC_COST_0312_PRODUCTEXP_PRC("BPLId"
	,"FcCode"
	,"CostCode"	--制造费用/人工费用
	,"ExpType"  --费用类型
	,"ExpCode"  --费用大类编码
	,"ExpName" --费用大类名称
	,"ItemCode" 
	,"CJCode" 	--车间编码（All-所有车间）
	,"IgnQty"  --入库数量
	,"Time"	  --单位工时
	,"TimeTotal" --总单位工时
	,"Prc"
	,"ExpAmt"
	,"CreateDate"   --创建时间
	,"Creator"
	)
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,'30' AS "CostCode"
	,'制造费用' AS "ExpType"
	,NULL AS "ExpCode"
	,NULL AS "ExpName"
	,T0."ItemCode"		--产成品的物料
	,'All' AS "CJCode"
	,0 AS "IgnQty"
	,T1."Time" AS "Time"	  --单位工时
	,T1."TimeTotal" AS "TimeTotal"
	,T1."Prc" AS "Prc"
	,T1."ExpAmt"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "OITM" T0
	LEFT JOIN 
	(
		SELECT T1."ItemCode",T1."Time",T3."ItmsGrpCod",(T1."Time"*T2."IgnQty") AS "TimeTotal"
		,(T1."Time"*T2."IgnQty")/NULLIF(SUM(T1."Time"*T2."IgnQty") OVER (),0) AS "Prc"
		,(T1."Time"*T2."IgnQty")*T4."ExpAmount"/NULLIF(SUM(T1."Time"*T2."IgnQty") OVER (),0) AS "ExpAmt"
		FROM (SELECT "ItemCode",MAX("Time") AS "Time" FROM MTC_COST_TIME GROUP BY "ItemCode") T1
		JOIN (SELECT T0."ItemCode",-1*SUM(T0."Amount") AS "Amount",SUM(T0."IgnQty") AS "IgnQty"
				FROM MTC_COST_0321_OWOR T0 -- ON T1."FcCode"=T0."FcCode" AND T1."WorEntry"=T0."WorEntry"
				WHERE T0."FcCode"='2024-12'
				AND T0."WorType" IN ('10','20','30','40')
				--AND T0."ItemCode"='102000552'
				GROUP BY T0."ItemCode"
				) T2 ON T1."ItemCode"=T2."ItemCode"
		JOIN OITM T3 ON T1."ItemCode"=T3."ItemCode"
		LEFT JOIN (SELECT "FcCode",SUM("Amount") AS "ExpAmount" FROM "MTC_COST_0311_PRODUCTEXP_ADD"
					WHERE "FcCode"='2024-12' GROUP BY "FcCode"
				) T4 ON 1=1
		WHERE T3."ItmsGrpCod" IN ('102','103')
	) T1 ON T0."ItemCode"=T1."ItemCode"
	
	;
	
	
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"CostCode"	--制造费用/人工费用
	,"ExpType"  --费用类型
	,"Amount"
	,"CreateDate"   --创建时间
	,"Creator"
	)
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,T1."WorType"
	,T1."WorEntry"
	,T1."WorNum"
	,'30' AS "CostCode"
	,'制造费用' AS "ExpType"
	,-1*T0."ExpAmt"*T2."IgnQty"/NULLIF(SUM(T2."IgnQty") OVER (PARTITION BY T1."ItemCode",T1."FcCode"),0) AS "ExpAmt"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM MTC_COST_0312_PRODUCTEXP_PRC T0
	JOIN MTC_COST_0321_OWOR T1 ON T0."ItemCode"=T1."ItemCode" AND T0."FcCode"=T1."FcCode"
	JOIN (SELECT MAX("FcCode") AS "FcCode","WorEntry",SUM("IgnQty") AS "IgnQty"
			FROM MTC_COST_0321_OWOR
			WHERE "FcCode"='2024-12'
			GROUP BY "WorEntry"
			) T2 ON T1."FcCode"=T2."FcCode" AND T1."WorEntry"=T2."WorEntry"
	WHERE T0."FcCode"='2024-12'
	AND T1."WorType" IN ('10','20','30','40')
	;
	
	UPDATE T0 SET T0."3LabAmount"=IFNULL(T1."Amount",0),T0."Amount"=IFNULL(T0."1Material",0)+IFNULL(T1."Amount",0)
	FROM MTC_COST_0321_OWOR T0
	JOIN (SELECT MAX("FcCode") AS "FcCode","WorEntry",-1*SUM("Amount") AS "Amount"
		FROM MTC_COST_0321_OWOR2 GROUP BY "WorEntry"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	WHERE 1=1
	AND T0."FcCode"='2024-12';
	
	SELECT '制造费用比例计算成功' FROM DUMMY;
	

END