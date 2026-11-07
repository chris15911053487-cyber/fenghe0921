CREATE PROCEDURE "MTC_RPT_CO4011"
(
  IN STYPE INT,	--0汇总  1明细
  IN FcCode NVARCHAR(30),
  IN WorType NVARCHAR(50),	--生产工单，委外工单
  IN ItemCode NVARCHAR(50),
  IN WorNum NVARCHAR(50),
  IN IsInsert NVARCHAR(10) DEFAULT 'N',
  IN JZCY NVARCHAR(10) DEFAULT 'N'		--是否结转差异
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 
	--在产品明细表（查看和写入）
	--CALL "MTC_RPT_CO4011"(0,'2026-04','生产工单','','','Y')
	
	IF :WorType = '生产工单' THEN 
		
		SELECT T0."DocType",T0."WorType"
		,T0."工单类型"
		,T0."订单状态"
		,T0."订单日期"
		,T0."订单关单日期"
		,T0."订单号"
		,T0."WorEntry",T0."WorNum"
		,T1."ItemCode" AS "材料编码",T1."ItemName" AS "材料名称",T1."Quantity" AS "材料数量"
		,T1."Amount" AS "材料金额",T1."Amount_SUM" AS "材料汇总"
		,T0."在产品新" AS "汇总表的在产品金额"
		,IFNULL(T1."Amount_SUM",0)-IFNULL(T0."在产品新",0) AS "差异"
		,T1."ActIgeQty" AS "实际领料数量"
		,T1."ActIgeAmt" AS "实际领料金额"
		,T1."AvgIgePrice" AS "领料平均单价"
		,T1."IgnQtyPrc" AS "入库倒冲数量"
		,T1."IgnAmtPrc" AS "入库倒冲金额"
		,T1."CalType" AS "计算方式"
		,T1."PriceMemo" AS "计算备注"
		FROM MTC_COST_0322_OWOR_ZCP T0
		LEFT JOIN (SELECT "FcCode","DocType","WorType","WorEntry","WorNum","ItemCode","ItemName","Quantity","Amount"
					,SUM("Amount") OVER (PARTITION BY "FcCode","DocType","WorEntry") AS "Amount_SUM"
					,"ActIgeQty","ActIgeAmt","CalType","PriceMemo"
					,"IgnQtyPrc","IgnAmtPrc","AvgIgePrice"
					FROM MTC_COST_0322_OWOR_ZCP1
				) T1 ON T0."期间"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
		WHERE T0."期间"=:FcCode
		AND T0."WorType" IN ('10','20','30')
		AND (T0."WorNum"=:WorNum OR WorNum='')
		AND (IFNULL(T1."Amount_SUM",0)<>0 OR IFNULL(T0."在产品新",0)<>0)
		ORDER BY T0."WorEntry"
		;

		IF :IsInsert = 'Y' THEN
			
			TMP_OWOR=
			SELECT T1."U_OrdType" AS "WorType",
			CASE T1."U_OrdType" WHEN 10 THEN '生产计划单' WHEN 20 THEN '包装计划单' WHEN 30 THEN '返工计划单' 
			WHEN 40 THEN '生产试打' WHEN 50 THEN '委外工单' END AS "工单类型"
			,T."订单状态"
			,T0."DocType",T1."DocEntry" AS "WorEntry",T1."DocNum" AS "WorNum",T5."ItemCode",T5."ItemName"
			,CASE WHEN IFNULL(T0."IgnQty",0)-IFNULL(T1."PlannedQty",0)>=0 THEN 0
					ELSE T4."IgeQty"-T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty" END AS "CL_ZCP_QTY"
			----计算的在产品（实际领料-）
			--1.当实际入库数量大于等于计划入库数量，在产品为0
			,CASE WHEN IFNULL(T0."IgnQty",0)-IFNULL(T1."PlannedQty",0)>=0 THEN 0
					ELSE T4."IgeAmt"-T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty"*IFNULL(T4."IgePrice",0) END AS "CL_ZCP_AMT"
			
			,T4."IgeQty" AS "ActIgeQty"		--实际领料数量
			,T4."IgeAmt" AS "ActIgeAmt"		--实际领料金额

			,T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty" AS "IgnQtyPrc" --入库倒冲数量
			,T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty"*IFNULL(T4."IgePrice",0) AS "IgnAmtPrc" --入库倒冲金额
			,IFNULL(T4."IgePrice",0) AS "AvgIgePrice"	--平均领料单价
			,CASE WHEN IFNULL(T0."IgnQty",0)-IFNULL(T1."PlannedQty",0)>=0 THEN 'ZERO'
				ELSE 'ZCP' END 
				AS "CalType"	--计算类型 ZERO-0在产品 ZCP-按领料比例倒挤计算
			,CASE WHEN IFNULL(T0."IgnQty",0)-IFNULL(T1."PlannedQty",0)>=0 
				THEN 'ZERO:实际已入库数量'||IFNULL(T0."IgnQty",0)||'减去计划入库数量'||IFNULL(T1."PlannedQty",0)||'>=0'
				ELSE 'ZCP:实际领料金额'||IFNULL(T4."IgeAmt",0)
					||'减去(实际已入库数量'||IFNULL(T0."IgnQty",0)||'*'
					||'子件计划数量'||T2."PlannedQty"||'/'
					||'订单主件计划数量'||T1."PlannedQty"||'*'
					||'材料平均单价'||IFNULL(T4."IgePrice",0)||')'
				END
				AS "PriceMemo"
			FROM MTC_COST_0322_OWOR_ZCP T
			JOIN (SELECT "DocType","WorEntry","ItemCode"
						,SUM("IgnQty") AS "IgnQty"
						FROM "MTC_COST_0321_OWOR" WHERE "FcCode"<=:FcCode
						--AND "WorNum"=4220
							GROUP BY "DocType","WorEntry","ItemCode"
					) T0 ON T."DocType"=T0."DocType" AND T."WorEntry"=T0."WorEntry"
			--订单主件计划数量
			LEFT JOIN (SELECT '202' AS "ObjType","DocEntry","DocNum","PostDate","PlannedQty","U_CardCode","U_OrdType" FROM OWOR
						UNION ALL
					   SELECT "Object" AS "ObjType","DocEntry","DocNum","U_PostDate","U_PlannedQty","U_CardCode","U_OrdType" FROM "@MTC_OWOR"
					) T1 ON T0."WorEntry"=T1."DocEntry" AND T0."DocType"=T1."ObjType"
			--订单子件计划数量
			LEFT JOIN (SELECT '202' AS "ObjType","DocEntry","ItemCode",SUM("PlannedQty") AS "PlannedQty" FROM WOR1 GROUP BY "DocEntry","ItemCode"
						UNION ALL
					   SELECT "Object" AS "ObjType","DocEntry","U_ItemCode",SUM("U_PlannedQty") AS "PlannedQty"
					   			FROM "@MTC_WOR1" GROUP BY "Object","DocEntry","U_ItemCode"
					) T2 ON T1."DocEntry"=T2."DocEntry" AND T0."DocType"=T2."ObjType"
			LEFT JOIN OCRD T3 ON T1."U_CardCode"=T3."CardCode"
			JOIN (SELECT "DocType","WorEntry","ItemCode"
						,SUM(-1*"IgeQty") AS "IgeQty" 
						,SUM(-1*"Amount") AS "IgeAmt"
						,SUM(-1*"Amount")/NULLIF(SUM(-1*"IgeQty"),0) AS "IgePrice"
						FROM "MTC_COST_0321_OWOR1" WHERE "FcCode"<=:FcCode
							GROUP BY "DocType","WorEntry","ItemCode" HAVING SUM(-1*"IgeQty")<>0
						) T4 ON T4."DocType"=T0."DocType" AND T4."WorEntry"=T1."DocEntry" AND T2."ItemCode"=T4."ItemCode" 
			LEFT JOIN OITM T5 ON T4."ItemCode"=T5."ItemCode"
			WHERE 1=1
			AND T."WorType" IN ('10','20','30')
			AND T."在产品新"<>0
			--AND T."订单状态"<>'已结算'
			AND T."期间"=:FcCode
			AND (T."WorNum"=:WorNum OR :WorNum='')
			--AND T1."U_OrdType"='50'
			;
			
			DELETE FROM "MTC_COST_0322_OWOR_ZCP1" WHERE "FcCode"=:FcCode AND "WorType" IN ('10','20','30'); 
			INSERT INTO "MTC_COST_0322_OWOR_ZCP1"(
			"FcCode","DocType","WorType","WorEntry","WorNum","iLevel",
		    "ItemCode","ItemName","ItmsGrpCod",
		    "Quantity","Amount","ActIgeQty","ActIgeAmt","IgnQtyPrc","IgnAmtPrc","AvgIgePrice",
		    "CalType","PriceMemo",
		    "CreateDate","Creator"
		    )
		    SELECT :FcCode,T0."DocType",T0."WorType",T0."WorEntry",T0."WorNum",NULL
		    ,T0."ItemCode",T0."ItemName",NULL
		    ,T0."CL_ZCP_QTY",T0."CL_ZCP_AMT",T0."ActIgeQty",T0."ActIgeAmt",T0."IgnQtyPrc",T0."IgnAmtPrc",T0."AvgIgePrice"
		    ,T0."CalType",T0."PriceMemo"
		    ,CURRENT_TIMESTAMP,:FcCode
		    FROM :TMP_OWOR T0
		    ORDER BY T0."WorEntry",T0."DocType"
		    ;
		    
		    /*
		    INSERT INTO "MTC_COST_0322_OWOR_ZCP1"(
			"FcCode","DocType","WorType","WorEntry","WorNum","iLevel",
		    "ItemCode","ItemName","ItmsGrpCod",
		    "Quantity","Amount","ActIgeQty","ActIgeAmt","IgnQtyPrc","IgnAmtPrc","AvgIgePrice",
		    "CalType","PriceMemo",
		    "CreateDate","Creator"
		    )
		    SELECT :FcCode,'202' AS "DocType",'10' AS "WorType",T0."DocEntry" AS "WorEntry",T0."DocNum" AS "WorNum",NULL
		    ,T1."ItemCode",T2."ItemName",NULL
		    ,T1."PlannedQty",478675.03 AS "CL_ZCP_AMT"
		    ,T1."PlannedQty" AS "ActIgeQty",478675.03 AS "ActIgeAmt",NULL AS "IgnQtyPrc",NULL AS "IgnAmtPrc",NULL AS "AvgIgePrice"
		    ,'ZCP' AS "CalType",NULL AS "PriceMemo"
		    ,CURRENT_TIMESTAMP,:FcCode
		    FROM "OWOR" T0 JOIN "WOR1" T1 ON T0."DocEntry"=T1."DocEntry"
		    JOIN OITM T2 ON T1."ItemCode"=T2."ItemCode"
		    WHERE T0."DocEntry"=308
		    ;*/
		    
		    
			--UPDATE "MTC_COST_0322_OWOR_ZCP1" SET "Amount"="Amount"+53893.65  
			--WHERE "FcCode"='2026-04' AND "WorEntry"='111' AND "DocType"='MTC_OWOR' AND "ItemCode"='102000086'
			--AND :FcCode='2026-04'
			--;

			TMP_DIFF=
		    SELECT T0."DocType"
			,T0."WorEntry",T0."WorNum"
			,T1."Amount_SUM" 	-- "在产品材料汇总"
			,T0."在产品新" -- "汇总表的在产品金额"
			,IFNULL(T1."Amount_SUM",0)-IFNULL(T0."在产品新",0) AS "DiffAmt"
			FROM MTC_COST_0322_OWOR_ZCP T0
			LEFT JOIN (SELECT "FcCode","DocType","WorType","WorEntry","WorNum","ItemCode","ItemName","Quantity","Amount"
						,SUM("Amount") OVER (PARTITION BY "FcCode","DocType","WorEntry") AS "Amount_SUM"
						,"ActIgeQty","ActIgeAmt","CalType","PriceMemo"
						,"IgnQtyPrc","IgnAmtPrc","AvgIgePrice"
						FROM MTC_COST_0322_OWOR_ZCP1
					) T1 ON T0."期间"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
			WHERE T0."期间"=:FcCode
			AND T0."WorType" IN ('10','20','30')
			AND (T0."WorNum"=:WorNum OR WorNum='')
			AND IFNULL(T1."Amount_SUM",0)-IFNULL(T0."在产品新",0)<>0
			GROUP BY T0."DocType"
			,T0."WorEntry",T0."WorNum"
			,T1."Amount_SUM" 	-- "在产品材料汇总"
			,T0."在产品新";
			
			
			IF :JZCY = 'Y' THEN
				UPDATE T2 SET T2."Amount"=T2."Amount"-T0."DiffAmt"
				FROM :TMP_DIFF T0
				JOIN (SELECT "DocType","WorEntry","WorNum","ItemCode","Amount"
						,ROW_NUMBER() OVER(PARTITION BY "FcCode","DocType","WorEntry" ORDER BY "Amount" DESC) AS "ID"
						FROM MTC_COST_0322_OWOR_ZCP1 WHERE "FcCode"=:FcCode
					) T1 ON T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry" AND T1."ID"=1
				JOIN MTC_COST_0322_OWOR_ZCP1 T2 ON T0."DocType"=T2."DocType" AND T0."WorEntry"=T2."WorEntry" 
													AND T1."ItemCode"=T2."ItemCode" AND T2."FcCode"=:FcCode
				WHERE T2."WorType" IN ('10','20','30')
				;
			END IF;
			
		END IF;
	
	ELSEIF :WorType='委外工单' THEN
	
			
		SELECT T0."DocType",T0."WorType"
		,T0."工单类型"
		,T0."订单状态"
		,T0."订单日期"
		,T0."订单关单日期"
		,T0."订单号"
		,T0."WorEntry",T0."WorNum"
		,T1."ItemCode" AS "材料编码",T1."ItemName" AS "材料名称",T1."Quantity" AS "材料数量"
		,T1."Amount" AS "材料金额",T1."Amount_SUM" AS "材料汇总"
		,T0."在产品新" AS "汇总表的在产品金额"
		,IFNULL(T1."Amount_SUM",0)-IFNULL(T0."在产品新",0) AS "差异"
		,T1."ActIgeQty" AS "实际领料数量"
		,T1."ActIgeAmt" AS "实际领料金额"
		,T1."AvgIgePrice" AS "领料平均单价"
		,T1."IgnQtyPrc" AS "入库倒冲数量"
		,T1."IgnAmtPrc" AS "入库倒冲金额"
		,T2."CardCode",T2."CardName"
		,T1."CalType" AS "计算方式"
		,T1."PriceMemo" AS "计算备注"
		FROM MTC_COST_0322_OWOR_ZCP T0
		LEFT JOIN (SELECT "FcCode","DocType","WorType","WorEntry","WorNum","ItemCode","ItemName","Quantity","Amount"
					,SUM("Amount") OVER (PARTITION BY "FcCode","DocType","WorEntry") AS "Amount_SUM"
					,"ActIgeQty","ActIgeAmt","CalType","PriceMemo"
					,"IgnQtyPrc","IgnAmtPrc","AvgIgePrice"
					FROM MTC_COST_0322_OWOR_ZCP1
				) T1 ON T0."期间"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
		LEFT JOIN OCRD T2 ON T0."CardCode"=T2."CardCode"
		WHERE T0."期间"=:FcCode
		AND T0."WorType" IN ('50')
		AND (T0."WorNum"=:WorNum OR WorNum='')
		AND (IFNULL(T1."Amount_SUM",0)<>0 OR IFNULL(T0."在产品新",0)<>0)
		ORDER BY T0."WorEntry"
		;

		IF :IsInsert = 'Y' THEN
			
			TMP_OWOR_50=
			SELECT T1."U_OrdType" AS "WorType",
			CASE T1."U_OrdType" WHEN 10 THEN '生产计划单' WHEN 20 THEN '包装计划单' WHEN 30 THEN '返工计划单' 
			WHEN 40 THEN '生产试打' WHEN 50 THEN '委外工单' END AS "工单类型"
			,T3."CardCode",T3."CardName"
			,T."订单状态"
			,T0."DocType",T1."DocEntry" AS "WorEntry",T1."DocNum" AS "WorNum",T5."ItemCode",T5."ItemName"
			,CASE WHEN IFNULL(T0."IgnQty",0)-IFNULL(T1."PlannedQty",0)>=0 THEN 0
					ELSE T4."IgeQty"-T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty" END AS "CL_ZCP_QTY"
			----计算的在产品（实际领料-）
			--1.当实际入库数量大于等于计划入库数量，在产品为0
			,CASE WHEN IFNULL(T0."IgnQty",0)-IFNULL(T1."PlannedQty",0)>=0 THEN 0
					ELSE T4."IgeAmt"-T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty"*IFNULL(T4."IgePrice",0) END AS "CL_ZCP_AMT"
			
			,T4."IgeQty" AS "ActIgeQty"		--实际领料数量
			,T4."IgeAmt" AS "ActIgeAmt"		--实际领料金额

			,T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty" AS "IgnQtyPrc" --入库倒冲数量
			,T0."IgnQty"*T2."PlannedQty"/T1."PlannedQty"*IFNULL(T4."IgePrice",0) AS "IgnAmtPrc" --入库倒冲金额
			,IFNULL(T4."IgePrice",0) AS "AvgIgePrice"	--平均领料单价
			,CASE WHEN IFNULL(T0."IgnQty",0)-IFNULL(T1."PlannedQty",0)>=0 THEN 'ZERO'
				ELSE 'ZCP' END 
				AS "CalType"	--计算类型 ZERO-0在产品 ZCP-按领料比例倒挤计算
			,CASE WHEN IFNULL(T0."IgnQty",0)-IFNULL(T1."PlannedQty",0)>=0 
				THEN 'ZERO:实际已入库数量'||IFNULL(T0."IgnQty",0)||'减去计划入库数量'||IFNULL(T1."PlannedQty",0)||'>=0'
				ELSE 'ZCP:实际领料金额'||IFNULL(T4."IgeAmt",0)
					||'减去(实际已入库数量'||IFNULL(T0."IgnQty",0)||'*'
					||'子件计划数量'||T2."PlannedQty"||'/'
					||'订单主件计划数量'||T1."PlannedQty"||'*'
					||'材料平均单价'||IFNULL(T4."IgePrice",0)||')'
				END
				AS "PriceMemo"
			FROM MTC_COST_0322_OWOR_ZCP T
			JOIN (SELECT "DocType","WorEntry","ItemCode"
						,SUM("IgnQty") AS "IgnQty"
						FROM "MTC_COST_0321_OWOR" WHERE "FcCode"<=:FcCode
						--AND "WorNum"=4220
							GROUP BY "DocType","WorEntry","ItemCode"
					) T0 ON T."DocType"=T0."DocType" AND T."WorEntry"=T0."WorEntry"
			--订单主件计划数量
			LEFT JOIN (SELECT '202' AS "ObjType","DocEntry","DocNum","PostDate","PlannedQty","U_CardCode","U_OrdType" FROM OWOR
						UNION ALL
					   SELECT "Object" AS "ObjType","DocEntry","DocNum","U_PostDate","U_PlannedQty","U_CardCode","U_OrdType" FROM "@MTC_OWOR"
					) T1 ON T0."WorEntry"=T1."DocEntry" AND T0."DocType"=T1."ObjType"
			--订单子件计划数量
			LEFT JOIN (SELECT '202' AS "ObjType","DocEntry","ItemCode",SUM("PlannedQty") AS "PlannedQty" FROM WOR1 GROUP BY "DocEntry","ItemCode"
						UNION ALL
					   SELECT "Object" AS "ObjType","DocEntry","U_ItemCode",SUM("U_PlannedQty") AS "PlannedQty"
					   			FROM "@MTC_WOR1" GROUP BY "Object","DocEntry","U_ItemCode"
					) T2 ON T1."DocEntry"=T2."DocEntry" AND T0."DocType"=T2."ObjType"
			LEFT JOIN OCRD T3 ON T1."U_CardCode"=T3."CardCode"
			JOIN (SELECT "DocType","WorEntry","ItemCode"
						,SUM(-1*"IgeQty") AS "IgeQty" 
						,SUM(-1*"Amount") AS "IgeAmt"
						,SUM(-1*"Amount")/NULLIF(SUM(-1*"IgeQty"),0) AS "IgePrice"
						FROM "MTC_COST_0321_OWOR1" WHERE "FcCode"<=:FcCode
							GROUP BY "DocType","WorEntry","ItemCode" HAVING SUM(-1*"IgeQty")<>0 OR SUM(-1*"Amount")<>0
						) T4 ON T4."DocType"=T0."DocType" AND T4."WorEntry"=T1."DocEntry" AND T2."ItemCode"=T4."ItemCode" 
			LEFT JOIN OITM T5 ON T4."ItemCode"=T5."ItemCode"
			WHERE 1=1
			AND T."WorType" IN ('50')
			AND T."订单状态"<>'已结算'
			--AND T."在产品新"<>0
			AND T."期间"=:FcCode
			AND (T."WorNum"=:WorNum OR :WorNum='')
			--AND T1."U_OrdType"='50'
			;
			
			DELETE FROM "MTC_COST_0322_OWOR_ZCP1" WHERE "FcCode"=:FcCode AND "WorType" IN ('50'); 
			INSERT INTO "MTC_COST_0322_OWOR_ZCP1"(
			"FcCode","DocType","WorType","WorEntry","WorNum","iLevel","CardCode","CardName",
		    "ItemCode","ItemName","ItmsGrpCod",
		    "Quantity","Amount","ActIgeQty","ActIgeAmt","IgnQtyPrc","IgnAmtPrc","AvgIgePrice",
		    "CalType","PriceMemo",
		    "CreateDate","Creator"
		    )
		    SELECT :FcCode,T0."DocType",T0."WorType",T0."WorEntry",T0."WorNum",NULL,T0."CardCode",T0."CardName"
		    ,T0."ItemCode",T0."ItemName",NULL
		    ,T0."CL_ZCP_QTY",T0."CL_ZCP_AMT",T0."ActIgeQty",T0."ActIgeAmt",T0."IgnQtyPrc",T0."IgnAmtPrc",T0."AvgIgePrice"
		    ,T0."CalType",T0."PriceMemo"
		    ,CURRENT_TIMESTAMP,:FcCode
		    FROM :TMP_OWOR_50 T0
		    ORDER BY T0."WorEntry",T0."DocType"
		    ;
		    
		    /*
		    INSERT INTO "MTC_COST_0322_OWOR_ZCP1"(
			"FcCode","DocType","WorType","WorEntry","WorNum","iLevel","CardCode","CardName",
		    "ItemCode","ItemName","ItmsGrpCod",
		    "Quantity","Amount","ActIgeQty","ActIgeAmt","IgnQtyPrc","IgnAmtPrc","AvgIgePrice",
		    "CalType","PriceMemo",
		    "CreateDate","Creator"
		    )
		    SELECT :FcCode,'202' AS "DocType",'10' AS "WorType",T0."DocEntry" AS "WorEntry",T0."DocNum" AS "WorNum",NULL,T3."CardCode",T3."CardName"
		    ,T1."ItemCode",T2."ItemName",NULL
		    ,T1."PlannedQty",5884.95 AS "CL_ZCP_AMT"
		    ,T1."PlannedQty" AS "ActIgeQty",5884.95 AS "ActIgeAmt",NULL AS "IgnQtyPrc",NULL AS "IgnAmtPrc",NULL AS "AvgIgePrice"
		    ,'ZCP' AS "CalType",NULL AS "PriceMemo"
		    ,CURRENT_TIMESTAMP,:FcCode
		    FROM "OWOR" T0 JOIN "WOR1" T1 ON T0."DocEntry"=T1."DocEntry"
		    JOIN OITM T2 ON T1."ItemCode"=T2."ItemCode"
		    LEFT JOIN OCRD T3 ON T0."U_CardCode"=T3."CardCode"
		    WHERE T0."DocEntry"=29222
		    ;
		    
		    
		    INSERT INTO "MTC_COST_0322_OWOR_ZCP1"(
			"FcCode","DocType","WorType","WorEntry","WorNum","iLevel","CardCode","CardName",
		    "ItemCode","ItemName","ItmsGrpCod",
		    "Quantity","Amount","ActIgeQty","ActIgeAmt","IgnQtyPrc","IgnAmtPrc","AvgIgePrice",
		    "CalType","PriceMemo",
		    "CreateDate","Creator"
		    )
		    SELECT :FcCode,'202' AS "DocType",'10' AS "WorType",T0."DocEntry" AS "WorEntry",T0."DocNum" AS "WorNum",NULL,T3."CardCode",T3."CardName"
		    ,T1."ItemCode",T2."ItemName",NULL
		    ,T1."PlannedQty",-874.86 AS "CL_ZCP_AMT"
		    ,T1."PlannedQty" AS "ActIgeQty",-874.86 AS "ActIgeAmt",NULL AS "IgnQtyPrc",NULL AS "IgnAmtPrc",NULL AS "AvgIgePrice"
		    ,'ZCP' AS "CalType",NULL AS "PriceMemo"
		    ,CURRENT_TIMESTAMP,:FcCode
		    FROM "OWOR" T0 JOIN "WOR1" T1 ON T0."DocEntry"=T1."DocEntry"
		    JOIN OITM T2 ON T1."ItemCode"=T2."ItemCode"
		    LEFT JOIN OCRD T3 ON T0."U_CardCode"=T3."CardCode"
		    WHERE T0."DocEntry"=723
		    ;*/
		
			TMP_DIFF_50=
		    SELECT T0."DocType"
			,T0."WorEntry",T0."WorNum"
			,T1."Amount_SUM" 	-- "在产品材料汇总"
			,T0."在产品新" -- "汇总表的在产品金额"
			,IFNULL(T1."Amount_SUM",0)-IFNULL(T0."在产品新",0) AS "DiffAmt"
			FROM MTC_COST_0322_OWOR_ZCP T0
			LEFT JOIN (SELECT "FcCode","DocType","WorType","WorEntry","WorNum","ItemCode","ItemName","Quantity","Amount"
						,SUM("Amount") OVER (PARTITION BY "FcCode","DocType","WorEntry") AS "Amount_SUM"
						,"ActIgeQty","ActIgeAmt","CalType","PriceMemo"
						,"IgnQtyPrc","IgnAmtPrc","AvgIgePrice"
						FROM MTC_COST_0322_OWOR_ZCP1
					) T1 ON T0."期间"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
			WHERE T0."期间"=:FcCode
			AND T0."WorType" IN ('50')
			AND (T0."WorNum"=:WorNum OR WorNum='')
			AND IFNULL(T1."Amount_SUM",0)-IFNULL(T0."在产品新",0)<>0
			GROUP BY T0."DocType"
			,T0."WorEntry",T0."WorNum"
			,T1."Amount_SUM" 	-- "在产品材料汇总"
			,T0."在产品新";
			
			
			IF :JZCY = 'Y' THEN
			
			
				UPDATE T2 SET T2."Amount"=T2."Amount"-T0."DiffAmt"
				FROM :TMP_DIFF_50 T0
				JOIN (SELECT "DocType","WorEntry","WorNum","ItemCode","Amount"
						,ROW_NUMBER() OVER(PARTITION BY "FcCode","DocType","WorEntry" ORDER BY "Amount" DESC) AS "ID"
						FROM MTC_COST_0322_OWOR_ZCP1 WHERE "FcCode"=:FcCode
					) T1 ON T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry" AND T1."ID"=1
				JOIN MTC_COST_0322_OWOR_ZCP1 T2 ON T0."DocType"=T2."DocType" AND T0."WorEntry"=T2."WorEntry" 
													AND T1."ItemCode"=T2."ItemCode" AND T2."FcCode"=:FcCode
				WHERE T2."WorType" IN ('50')
				;
			END IF;
		END IF;
	
		
	END IF;

END