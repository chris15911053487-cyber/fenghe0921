CREATE PROCEDURE "MTC_COST_PROC_0312_PRODUCTEXP_PRC"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 费用归集表 MTC_COST_0312_PRODUCTEXP_PRC
     * CALL "MTC_COST_PROC_0312_PRODUCTEXP_PRC"(0,'2024-01','manager');
    */
    
    --CALL "MTC_COST_PROC_0312_PRODUCTEXP_PRC"(0,:FcCode,'manager');
    
    
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
  	
	DELETE FROM MTC_COST_0312_PRODUCTEXP_PRC WHERE "FcCode" = :FcCode;
	DELETE FROM MTC_COST_0321_OWOR2 WHERE "FcCode" = :FcCode;
	
	--------------------------------------制造费用---------------------------------------------
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
	,'制造车间' AS "CJCode"
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
		,ROUND((T1."Time"*T2."IgnQty")*T4."ExpAmount"/NULLIF(SUM(T1."Time"*T2."IgnQty") OVER (),0),2) AS "ExpAmt"
		FROM (SELECT T1."U_ItemCode" AS "ItemCode",MAX(T1."U_Time") AS "Time" 
					FROM "@MTC_COST_TIME" T0 JOIN "@MTC_COST_TIME1" T1 ON T0."DocEntry"=T1."DocEntry"
					WHERE T0."U_FcCode"=:FcCode GROUP BY T1."U_ItemCode"
				) T1
		JOIN (SELECT T0."ItemCode",-1*SUM(T0."Amount") AS "Amount",SUM(T0."IgnQty") AS "IgnQty"
				FROM MTC_COST_0321_OWOR T0 -- ON T1."FcCode"=T0."FcCode" AND T1."WorEntry"=T0."WorEntry"
				WHERE T0."FcCode"=:FcCode
				AND T0."WorType" IN ('10','20','30','40')
				--AND T0."ItemCode"='102000552'
				GROUP BY T0."ItemCode"
				) T2 ON T1."ItemCode"=T2."ItemCode"
		JOIN OITM T3 ON T1."ItemCode"=T3."ItemCode"
		LEFT JOIN (SELECT "FcCode",SUM("Amount") AS "ExpAmount"
					FROM "MTC_COST_0311_PRODUCTEXP_ADD"
					WHERE "FcCode"=:FcCode
					AND ("ExpType" IN ('制造费用','公摊材料费用') OR "ExpType" LIKE '库存重估%') AND IFNULL("OcrCode",'')<>'P017'
					GROUP BY "FcCode"
				) T4 ON 1=1
		WHERE T3."ItmsGrpCod" IN ('102','103')
	) T1 ON T0."ItemCode"=T1."ItemCode"	
	;
	
	
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
	,"DocType"
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
	,T1."DocType"
	,T1."WorType"
	,T1."WorEntry"
	,T1."WorNum"
	,'30' AS "CostCode"
	,'制造费用' AS "ExpType"
	,ROUND(-1*T0."ExpAmt"*T2."IgnQty"/NULLIF(SUM(T2."IgnQty") OVER (PARTITION BY T1."ItemCode",T1."FcCode"),0),2) AS "ExpAmt"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM MTC_COST_0312_PRODUCTEXP_PRC T0
	JOIN MTC_COST_0321_OWOR T1 ON T0."ItemCode"=T1."ItemCode" AND T0."FcCode"=T1."FcCode"
	JOIN (SELECT MAX("FcCode") AS "FcCode","DocType","WorEntry",SUM("IgnQty") AS "IgnQty"
			FROM MTC_COST_0321_OWOR
			WHERE "FcCode"=:FcCode
			GROUP BY "WorEntry","DocType"
			) T2 ON T1."FcCode"=T2."FcCode" AND T1."DocType"=T2."DocType" AND T1."WorEntry"=T2."WorEntry"
	WHERE T0."FcCode"=:FcCode
	AND T1."WorType" IN ('10','20','30','40')
	AND T0."ExpType"='制造费用' AND T0."CJCode"='制造车间'		
	;
	
	
	---------P017包装车间的领用
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
	,'包装车间' AS "CJCode"
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
		,ROUND((T1."Time"*T2."IgnQty")*T4."ExpAmount"/NULLIF(SUM(T1."Time"*T2."IgnQty") OVER (),0),2) AS "ExpAmt"
		FROM (SELECT T1."U_ItemCode" AS "ItemCode",MAX(T1."U_Time") AS "Time" 
					FROM "@MTC_COST_TIME" T0 JOIN "@MTC_COST_TIME1" T1 ON T0."DocEntry"=T1."DocEntry"
					WHERE T0."U_FcCode"=:FcCode GROUP BY T1."U_ItemCode"
				) T1
		JOIN (SELECT T0."ItemCode",-1*SUM(T0."Amount") AS "Amount",SUM(T0."IgnQty") AS "IgnQty"
				FROM MTC_COST_0321_OWOR T0 -- ON T1."FcCode"=T0."FcCode" AND T1."WorEntry"=T0."WorEntry"
				WHERE T0."FcCode"=:FcCode
				AND T0."WorType" IN ('10','20','30','40')
				--AND T0."ItemCode"='102000552'
				GROUP BY T0."ItemCode"
				) T2 ON T1."ItemCode"=T2."ItemCode"
		JOIN OITM T3 ON T1."ItemCode"=T3."ItemCode"
		LEFT JOIN (SELECT "FcCode",SUM("Amount") AS "ExpAmount"
					FROM "MTC_COST_0311_PRODUCTEXP_ADD"
					WHERE "FcCode"=:FcCode
					AND "ExpType" IN ('制造费用','公摊材料费用') AND IFNULL("OcrCode",'')='P017'
					GROUP BY "FcCode"
				) T4 ON 1=1
		WHERE T3."ItmsGrpCod" IN ('101')
	) T1 ON T0."ItemCode"=T1."ItemCode"	
	;
	
	
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
	,"DocType"
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
	,T1."DocType"
	,T1."WorType"
	,T1."WorEntry"
	,T1."WorNum"
	,'30' AS "CostCode"
	,'制造费用' AS "ExpType"
	,ROUND(-1*T0."ExpAmt"*T2."IgnQty"/NULLIF(SUM(T2."IgnQty") OVER (PARTITION BY T1."ItemCode",T1."FcCode"),0),2) AS "ExpAmt"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM MTC_COST_0312_PRODUCTEXP_PRC T0
	JOIN MTC_COST_0321_OWOR T1 ON T0."ItemCode"=T1."ItemCode" AND T0."FcCode"=T1."FcCode"
	JOIN (SELECT MAX("FcCode") AS "FcCode","DocType","WorEntry",SUM("IgnQty") AS "IgnQty"
			FROM MTC_COST_0321_OWOR
			WHERE "FcCode"=:FcCode
			GROUP BY "DocType","WorEntry"
			) T2 ON T1."FcCode"=T2."FcCode" AND T1."DocType"=T2."DocType" AND T1."WorEntry"=T2."WorEntry"
	WHERE T0."FcCode"=:FcCode
	AND T1."WorType" IN ('10','20','30','40')
	AND T0."ExpType"='制造费用' AND "CJCode"='包装车间'		
	;
	
	
	--------------------------------------人工费用（制造车间）---------------------------------------------
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
	,'40' AS "CostCode"
	,'人工费用' AS "ExpType"
	,NULL AS "ExpCode"
	,NULL AS "ExpName"
	,T0."ItemCode"		--产成品的物料
	,'制造车间' AS "CJCode"
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
		,ROUND((T1."Time"*T2."IgnQty")*T4."ExpAmount"/NULLIF(SUM(T1."Time"*T2."IgnQty") OVER (),0),2) AS "ExpAmt"
		FROM (SELECT T1."U_ItemCode" AS "ItemCode",MAX(T1."U_Time") AS "Time" 
					FROM "@MTC_COST_TIME" T0 JOIN "@MTC_COST_TIME1" T1 ON T0."DocEntry"=T1."DocEntry"
					WHERE T0."U_FcCode"=:FcCode GROUP BY T1."U_ItemCode"
				) T1
		JOIN (SELECT T0."ItemCode",-1*SUM(T0."Amount") AS "Amount",SUM(T0."IgnQty") AS "IgnQty"
				FROM MTC_COST_0321_OWOR T0 -- ON T1."FcCode"=T0."FcCode" AND T1."WorEntry"=T0."WorEntry"
				WHERE T0."FcCode"=:FcCode
				AND T0."WorType" IN ('10','20','30','40')
				--AND T0."ItemCode"='102000552'
				GROUP BY T0."ItemCode"
				) T2 ON T1."ItemCode"=T2."ItemCode"
		JOIN OITM T3 ON T1."ItemCode"=T3."ItemCode"
		LEFT JOIN (SELECT "FcCode",SUM("Amount") AS "ExpAmount"
					FROM "MTC_COST_0311_PRODUCTEXP_ADD"
					WHERE "FcCode"=:FcCode 
					AND "ExpType"='人工费用' AND IFNULL("OcrCode",'')<>'P017'
					GROUP BY "FcCode"
				) T4 ON 1=1
		WHERE T3."ItmsGrpCod" IN ('102','103')
	) T1 ON T0."ItemCode"=T1."ItemCode"
	
	;
	
	
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
	,"DocType"
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
	,T1."DocType"
	,T1."WorType"
	,T1."WorEntry"
	,T1."WorNum"
	,'40' AS "CostCode"
	,'人工费用' AS "ExpType"
	,ROUND(-1*T0."ExpAmt"*T2."IgnQty"/NULLIF(SUM(T2."IgnQty") OVER (PARTITION BY T1."ItemCode",T1."FcCode"),0),2) AS "ExpAmt"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM MTC_COST_0312_PRODUCTEXP_PRC T0
	JOIN MTC_COST_0321_OWOR T1 ON T0."ItemCode"=T1."ItemCode" AND T0."FcCode"=T1."FcCode"
	JOIN (SELECT MAX("FcCode") AS "FcCode","DocType","WorEntry",SUM("IgnQty") AS "IgnQty"
			FROM MTC_COST_0321_OWOR
			WHERE "FcCode"=:FcCode
			GROUP BY "DocType","WorEntry"
			) T2 ON T1."FcCode"=T2."FcCode" AND T1."DocType"=T2."DocType" AND T1."WorEntry"=T2."WorEntry"
	WHERE T0."FcCode"=:FcCode
	AND T1."WorType" IN ('10','20','30','40')
	AND T0."ExpType"='人工费用' AND T0."CJCode"='制造车间'
	;
	
	
	
	--------------------------------------人工费用（包装车间）---------------------------------------------
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
	,'40' AS "CostCode"
	,'人工费用' AS "ExpType"
	,NULL AS "ExpCode"
	,NULL AS "ExpName"
	,T0."ItemCode"		--产成品的物料
	,'包装车间' AS "CJCode"
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
		,ROUND((T1."Time"*T2."IgnQty")*T4."ExpAmount"/NULLIF(SUM(T1."Time"*T2."IgnQty") OVER (),0),2) AS "ExpAmt"
		FROM (SELECT T1."U_ItemCode" AS "ItemCode",MAX(T1."U_Time") AS "Time" 
					FROM "@MTC_COST_TIME" T0 JOIN "@MTC_COST_TIME1" T1 ON T0."DocEntry"=T1."DocEntry"
					WHERE T0."U_FcCode"=:FcCode GROUP BY T1."U_ItemCode"
				) T1
		JOIN (SELECT T0."ItemCode",-1*SUM(T0."Amount") AS "Amount",SUM(T0."IgnQty") AS "IgnQty"
				FROM MTC_COST_0321_OWOR T0 -- ON T1."FcCode"=T0."FcCode" AND T1."WorEntry"=T0."WorEntry"
				WHERE T0."FcCode"=:FcCode
				AND T0."WorType" IN ('10','20','30','40')
				--AND T0."ItemCode"='102000552'
				GROUP BY T0."ItemCode"
				) T2 ON T1."ItemCode"=T2."ItemCode"
		JOIN OITM T3 ON T1."ItemCode"=T3."ItemCode"
		LEFT JOIN (SELECT "FcCode",SUM("Amount") AS "ExpAmount"
					FROM "MTC_COST_0311_PRODUCTEXP_ADD"
					WHERE "FcCode"=:FcCode 
					AND "ExpType"='人工费用' AND IFNULL("OcrCode",'')='P017'
					GROUP BY "FcCode"
				) T4 ON 1=1
		WHERE T3."ItmsGrpCod" IN ('101')
	) T1 ON T0."ItemCode"=T1."ItemCode"
	
	;
	
	
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
	,"DocType"
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
	,T1."DocType"
	,T1."WorType"
	,T1."WorEntry"
	,T1."WorNum"
	,'40' AS "CostCode"
	,'人工费用' AS "ExpType"
	,ROUND(-1*T0."ExpAmt"*T2."IgnQty"/NULLIF(SUM(T2."IgnQty") OVER (PARTITION BY T1."ItemCode",T1."FcCode"),0),2) AS "ExpAmt"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM MTC_COST_0312_PRODUCTEXP_PRC T0
	JOIN MTC_COST_0321_OWOR T1 ON T0."ItemCode"=T1."ItemCode" AND T0."FcCode"=T1."FcCode"
	JOIN (SELECT MAX("FcCode") AS "FcCode","DocType","WorEntry",SUM("IgnQty") AS "IgnQty"
			FROM MTC_COST_0321_OWOR
			WHERE "FcCode"=:FcCode
			GROUP BY "DocType","WorEntry"
			) T2 ON T1."FcCode"=T2."FcCode" AND T1."DocType"=T2."DocType" AND T1."WorEntry"=T2."WorEntry"
	WHERE T0."FcCode"=:FcCode
	AND T1."WorType" IN ('10','20','30','40')
	AND T0."ExpType"='人工费用' AND T0."CJCode"='包装车间'
	;
	
	--检查费用尾差
	TMP_DIFF=SELECT T0."ExpType",T0."CJCode",SUM(T0."分摊前") AS "分摊前",SUM(T0."分摊后") AS "分摊后"
	,SUM(IFNULL(T0."分摊前",0)-IFNULL(T0."分摊后",0)) AS"Diff"
	FROM (
		SELECT
		    CASE
		        WHEN "ExpType" IN ('制造费用','公摊材料费用') OR "ExpType" LIKE '库存重估%' THEN '制造费用'
		        WHEN "ExpType" = '人工费用' THEN '人工费用'
		    END AS "ExpType",
		    CASE
		        WHEN IFNULL("OcrCode",'') = 'P017' THEN '包装车间'
		        ELSE '制造车间'
		    END AS "CJCode",
		    CAST(SUM("Amount") AS DECIMAL(19,6)) AS "分摊前",
		    CAST(0.000000 AS DECIMAL(19,6)) AS "分摊后"
		FROM "MTC_COST_0311_PRODUCTEXP_ADD"
		WHERE "FcCode" = :FcCode
		GROUP BY
		    CASE
		        WHEN "ExpType" IN ('制造费用','公摊材料费用') OR "ExpType" LIKE '库存重估%' THEN '制造费用'
		        WHEN "ExpType" = '人工费用' THEN '人工费用'
		    END,
		    CASE
		        WHEN IFNULL("OcrCode",'') = 'P017' THEN '包装车间'
		        ELSE '制造车间'
		    END
		UNION ALL
		SELECT
		    "ExpType",
		    "CJCode",
		    CAST(0.000000 AS DECIMAL(19,6)) AS "分摊前",
		    CAST(SUM("ExpAmt") AS DECIMAL(19,6)) AS "分摊后"
		FROM MTC_COST_0312_PRODUCTEXP_PRC
		WHERE "FcCode" = :FcCode
		GROUP BY "CostCode", "ExpType", "CJCode"
	) T0 GROUP BY T0."ExpType",T0."CJCode";
	
	--差异
	SELECT '分摊前的差异',* FROM :TMP_DIFF;
	
	--处理尾差
	UPDATE T0 SET T0."ExpAmt"=T0."ExpAmt"+IFNULL(T1."Diff",0)
	FROM MTC_COST_0312_PRODUCTEXP_PRC T0
	JOIN :TMP_DIFF T1 ON T0."ExpType"=T1."ExpType" AND T0."CJCode"=T1."CJCode"
	JOIN (SELECT "ID","ExpType","CJCode","ExpAmt","ItemCode"
				,ROW_NUMBER() OVER (PARTITION BY "ExpType","CJCode" ORDER BY "ExpAmt" DESC) AS "NUMID"
				FROM MTC_COST_0312_PRODUCTEXP_PRC
				WHERE "FcCode" = :FcCode
			) T2 ON T0."ID"=T2."ID"
	WHERE T0."FcCode" = :FcCode
	AND T2.NUMID=1;
	
	--
	SELECT '检查分摊后的差异',T0."ExpType",T0."CJCode",SUM(T0."分摊前") AS "分摊前",SUM(T0."分摊后") AS "分摊后"
	,SUM(IFNULL(T0."分摊前",0)-IFNULL(T0."分摊后",0)) AS"Diff"
	FROM (
		SELECT
		    CASE
		        WHEN "ExpType" IN ('制造费用','公摊材料费用') OR "ExpType" LIKE '库存重估%' THEN '制造费用'
		        WHEN "ExpType" = '人工费用' THEN '人工费用'
		    END AS "ExpType",
		    CASE
		        WHEN IFNULL("OcrCode",'') = 'P017' THEN '包装车间'
		        ELSE '制造车间'
		    END AS "CJCode",
		    CAST(SUM("Amount") AS DECIMAL(19,6)) AS "分摊前",
		    CAST(0.000000 AS DECIMAL(19,6)) AS "分摊后"
		FROM "MTC_COST_0311_PRODUCTEXP_ADD"
		WHERE "FcCode" = :FcCode
		GROUP BY
		    CASE
		        WHEN "ExpType" IN ('制造费用','公摊材料费用') OR "ExpType" LIKE '库存重估%' THEN '制造费用'
		        WHEN "ExpType" = '人工费用' THEN '人工费用'
		    END,
		    CASE
		        WHEN IFNULL("OcrCode",'') = 'P017' THEN '包装车间'
		        ELSE '制造车间'
		    END
		UNION ALL
		SELECT
		    "ExpType",
		    "CJCode",
		    CAST(0.000000 AS DECIMAL(19,6)) AS "分摊前",
		    CAST(SUM("ExpAmt") AS DECIMAL(19,6)) AS "分摊后"
		FROM MTC_COST_0312_PRODUCTEXP_PRC
		WHERE "FcCode" = :FcCode
		GROUP BY "CostCode", "ExpType", "CJCode"
	) T0 GROUP BY T0."ExpType",T0."CJCode";
	
	--
	UPDATE T0 SET T0."3LabAmount"=IFNULL(T1."3LabAmount",0)
	,T0."2ManExp"=IFNULL(T1."2ManExp",0)
	,T0."Amount"=IFNULL(T0."1Material",0)+IFNULL(T1."Amount",0)
	FROM MTC_COST_0321_OWOR T0
	JOIN (SELECT MAX("FcCode") AS "FcCode","DocType","WorEntry"
		,-1*SUM("Amount") AS "Amount"
		,-1*SUM(CASE WHEN "CostCode"='30' THEN "Amount" ELSE 0 END) AS "3LabAmount"
		,-1*SUM(CASE WHEN "CostCode"='40' THEN "Amount" ELSE 0 END) AS "2ManExp"
		FROM MTC_COST_0321_OWOR2 GROUP BY "DocType","WorEntry"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
	WHERE 1=1
	AND T0."FcCode"=:FcCode;
	
	SELECT "BPLId",
	"FcCode",
	"WorType",
	"WorEntry",
	"WorNum",
	"CostCode",
	"ExpType",
	-1*"Amount" AS "分摊金额",
	"CreateDate",
	"Creator",
	"IgeQty",
	"DocType"
	FROM "MTC_COST_0321_OWOR2" WHERE "FcCode"=:FcCode AND IFNULL("Amount",0)<>0;

	
	

END