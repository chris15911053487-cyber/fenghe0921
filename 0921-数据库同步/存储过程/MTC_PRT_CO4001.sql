CREATE PROCEDURE "MTC_PRT_CO4001" (
   IN sFcCode NVARCHAR(50)
   ,IN eFcCode NVARCHAR(50)
   ,IN ItemCode NVARCHAR(100)
   ,IN WorType NVARCHAR(30)
   ,IN WorNum NVARCHAR(30)
   ,IN IsOnlyAmt NVARCHAR(10) DEFAULT 'N'		--仅显示有余额
   ,IN IsInsert NVARCHAR(10) DEFAULT 'N'	--是否写入静态表
   )
LANGUAGE SQLSCRIPT
AS
BEGIN
	--CALL "MTC_PRT_CO4001"('','2026-01','','Y');
		IF :IsInsert = 'N' THEN
			
			SELECT T0."期间",
			T0."DocType",
			T0."WorType",
			T0."工单类型",
			T0."订单日期",
			T0."订单关单日期",
			T0."订单状态",
			T0."订单号",
			T0."WorEntry",
			T0."WorNum",
			T0."CardCode",
			T0."CardName",
			T0."物料编码" ,
			T0."物料名称",
			T0."物料组",
			T0."订单数量",
			T0."当期入库数量",
			T0."完工入库单价",
			T0."当期入库成本金额",
			T0."当期成本合计",
			T0."当期材料金额",
			T0."当期人工费用",
			T0."当期制造费用",
			T0."当期委外费用",
			T0."累计入库数量",
			T0."累计成本合计",
			T0."累计材料",
			T0."累计人工费用",
			T0."累计制造费用",
			T0."累计委外费用",
			T0."累计完工材料合计",
			T0."累计材料总",
			T0."关单差异",
			--CASE WHEN T0."WorNum"='22' THEN 531099.66 ELSE T0."在产品新" END AS "在产品新",
			--累计领料IFNULL(T4."1Material",0)-已经进入完工材料IFNULL(T1."1Material",0)-关单差异IFNULL(T0."CloseDifAmt",0)
			T0."在产品新" AS "在产品金额",
			T0."在产品金额" AS "在产品金额（参考）",
			T0."库存科目",
			T0."物料等级",
			T0."老系统订单号",
			T0."创建时间",
			T0."创建人",T9."CloseDate" AS "实际关闭日期"
			FROM "MTC_COST_0322_OWOR_ZCP" T0
			LEFT JOIN
					(SELECT '202' AS "DocType","DocEntry","DocNum","U_SupNum","U_OldSysNo","U_CardCode","U_CardName","CloseDate" FROM OWOR
						UNION ALL
					SELECT "Object","DocEntry","DocNum","U_SupNum","U_OldSysNo","U_CardCode","U_CardName","U_CloseDate" FROM "@MTC_OWOR"
					) T9 ON T0."WorEntry"=T9."DocEntry" AND T0."DocType"=T9."DocType"
			WHERE T0."期间">=:sFcCode AND T0."期间"<=:eFcCode
			AND (T0."物料编码"=:ItemCode OR :ItemCode='')
			AND (T0."WorNum"=:WorNum OR :WorNum='')
			AND ((:WorType = '生产工单' AND T0."WorType" IN ('20','30','10'))
					OR (:WorType = '委外工单' AND T0."WorType"='50')
					OR :WorType = ''
				)
			AND IFNULL(T0."WorType",'')<>'40'
			AND ((:IsOnlyAmt = 'Y' AND (IFNULL(T0."在产品新",0)<>0 OR IFNULL("当期入库数量",0)<>0) OR LEFT(T0."订单关单日期",7) BETWEEN :sFcCode AND :eFcCode)
				  OR :IsOnlyAmt='N'
				)
			;
	    
		ELSEIF :IsInsert = 'Y' THEN 	
			
	  		IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:eFcCode) THEN
	  			SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
		  		RETURN;
		  	END IF;
		    DELETE FROM MTC_COST_0322_OWOR_ZCP WHERE "期间"=:eFcCode;
		    
		    INSERT INTO "MTC_COST_0322_OWOR_ZCP"( 
			"期间", "DocType","WorType", "工单类型", "订单日期",
			"订单关单日期", "订单状态", "订单号", "WorEntry", "WorNum",
			"CardCode", "CardName", "物料编码", "物料名称", "物料组",
			"订单数量", "当期入库数量", "完工入库单价", "当期入库成本金额", "当期成本合计",
			"当期材料金额", "当期人工费用", "当期制造费用", "当期委外费用",
			"累计入库数量", "累计成本合计", "累计材料", "累计人工费用", "累计制造费用",
			"累计委外费用", "累计完工材料合计", "关单差异", "在产品金额","累计材料总","在产品新",
			"库存科目", "物料等级", "老系统订单号", "创建时间", "创建人")
			SELECT  
			T0."FcCode" AS "期间",
			T0."DocType",
			T0."WorType",
			(CASE T0."WorType" WHEN 10 THEN '生产计划单' WHEN 20 THEN '包装计划单' WHEN 30 THEN '返工计划单' 
			WHEN 40 THEN '生产试打' WHEN 50 THEN '委外工单' END) AS "工单类型",
			T0."DocDate" AS "订单日期",
			CASE WHEN T0."WorType"='50' 
				 AND T0."Status"='L' 
				 AND TO_CHAR(T0."CloseDate",'YYYY-MM')>='2026-07' 
				 AND TO_CHAR(T0."CloseDate",'YYYY-MM')<=:eFcCode
				 THEN T0."CloseDate"
			WHEN T0."Status"='L' AND TO_CHAR(T0."CloseDate",'YYYY-MM')<=:eFcCode
				THEN T0."CloseDate"
				ELSE '' END AS "订单关单日期",
			CASE WHEN T0."Status"='R' THEN '已下达'
			WHEN T0."WorType"='50' AND TO_CHAR(T0."CloseDate",'YYYY-MM')<'2026-07' AND TO_CHAR(T0."CloseDate",'YYYY-MM')>:eFcCode THEN '已下达'
			WHEN T0."WorType"='50' AND TO_CHAR(T0."CloseDate",'YYYY-MM')>='2026-07' AND TO_CHAR(T0."CloseDate",'YYYY-MM')<=:eFcCode THEN '已结算'
			WHEN T0."Status"='L' AND TO_CHAR(T0."CloseDate",'YYYY-MM')>:eFcCode THEN '已下达'
			WHEN T0."Status"='L' AND TO_CHAR(T0."CloseDate",'YYYY-MM')<=:eFcCode THEN '已结算'
			WHEN T0."Status"='P' THEN '已计划' END  AS "订单状态",
			T9."U_SupNum" AS "订单号",
			T0."WorEntry" AS "生产订单号Entry",
			T0."WorNum",
			T9."U_CardCode",
			T10."CardName",
			T0."ItemCode" AS "物料编码" ,
			T0."ItemName" AS "物料名称",
			T0."ItmsGrpCod" AS "物料组",
			T0."WorQty" AS "订单数量",
			T0."IgnQty" AS "当期入库数量",
			TO_CHAR(CAST(T0."Price" AS DECIMAL(19,6))) AS "完工入库单价",
			T0."Amount" AS "当期入库成本金额",
			--T0."IgnQty"*T0."Price" AS "当期入库成本金额",
			T0."Amount" AS "当期成本合计",
			T0."1Material" AS "当期材料金额",
			T0."2ManExp" AS "当期人工费用",
			T0."3LabAmount" AS "当期制造费用",
			T0."4WWExp" AS "当期委外费用",
			T0."Ign_SUM" AS "累计入库数量",
			T0."Amount_SUM" AS "累计成本合计",
			T0."1Material_SUM" AS "累计材料",
			T0."2ManExp_SUM" AS "累计人工费用",
			T0."3LabAmount_SUM" AS "累计制造费用",
			T0."4WWExp_SUM" AS "累计委外费用",
			IFNULL(T1."1Material",0) AS "累计完工材料合计",
			IFNULL(T0."CloseDifAmt",0) AS "关单差异",
			IFNULL(T0."1Material_SUM",0)-IFNULL(T1."1Material",0)-IFNULL(T0."CloseDifAmt",0) AS "在产品金额",
			IFNULL(T4."1Material",0) AS "累计材料总",
			--累计领料减去已结转的完工材料-关单差异
			IFNULL(T4."1Material",0)-IFNULL(T1."1Material",0)-IFNULL(T0."CloseDifAmt",0) AS "在产品新",
			T3."StockAct" AS "库存科目",
			T0."iLevel" AS "物料等级",
			T9."U_OldSysNo" AS "老系统订单号",
			CURRENT_TIMESTAMP AS "创建时间",
			T0."Creator" AS "创建人"
			FROM MTC_COST_0321_OWOR_SUM T0
			LEFT JOIN (SELECT "WorEntry","DocType",SUM("1Material") AS "1Material" FROM MTC_COST_0321_OWOR_SUM WHERE "FcCode"<=:eFcCode 
						GROUP BY "WorEntry","DocType"
			            ) T1 ON T0."WorEntry"=T1."WorEntry" AND T0."DocType"=T1."DocType"
			JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROM OGAR WHERE "PeriodCat"=LEFT(:eFcCode,4) GROUP BY "ItmsGrpCod"
							) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
			LEFT JOIN (SELECT "WorEntry","DocType",SUM(-1*"Amount") AS "1Material"
						FROM MTC_COST_0321_OWOR1 WHERE "FcCode"<=:eFcCode 
						GROUP BY "WorEntry","DocType"
			            ) T4 ON T0."WorEntry"=T4."WorEntry" AND T0."DocType"=T4."DocType"
			LEFT JOIN
					(SELECT '202' AS "DocType","DocEntry","DocNum","U_SupNum","U_OldSysNo","U_CardCode","U_CardName" FROM OWOR
						UNION ALL
					SELECT "Object","DocEntry","DocNum","U_SupNum","U_OldSysNo","U_CardCode","U_CardName" FROM "@MTC_OWOR"
					) T9 ON T0."WorEntry"=T9."DocEntry" AND T0."DocType"=T9."DocType"
			LEFT JOIN OCRD T10 ON T10."CardCode"=T9."U_CardCode"
			WHERE 1=1
			AND T0."FcCode" >= :eFcCode
			AND T0."FcCode" <= :eFcCode
			AND (T2."ItemCode"=:ItemCode OR :ItemCode='')
			ORDER BY T0."DocDate",CAST(T0."WorNum" AS INT);
			
			
			
			UPDATE "MTC_COST_0322_OWOR_ZCP" 
			SET "关单差异"="在产品新","在产品新"=0,"关单结算期间"=:eFcCode
			WHERE "WorType" IN ('10','20','30') AND "订单状态"='已结算' AND "期间"=:eFcCode
			AND IFNULL("在产品新",0)<>0
			AND TO_CHAR("订单关单日期",'YYYY-MM')=:eFcCode
			;
			
			
			UPDATE "MTC_COST_0322_OWOR_ZCP" 
			SET "关单差异"="在产品新","在产品新"=0,"关单结算期间"=:eFcCode
			WHERE "WorType" IN ('50') AND "订单状态"='已结算' AND "期间"=:eFcCode
			AND IFNULL("在产品新",0)<>0
			AND TO_CHAR("订单关单日期",'YYYY-MM')=:eFcCode
			AND TO_CHAR("订单关单日期",'YYYY-MM')>='2026-08'
			;
			
			UPDATE T0
			SET "5ClosedAmt"=IFNULL(T1."关单差异",0)
			FROM "MTC_COST_0321_OWOR" T0
			JOIN "MTC_COST_0322_OWOR_ZCP" T1 ON T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry" AND T0."FcCode"=T1."期间"
			WHERE 1=1
			AND T1."期间"=:eFcCode
			AND IFNULL(T1."关单差异",0)<>0
			AND T1."关单结算期间"=:eFcCode
			AND T1."订单状态"='已结算'
			;
			
			--UPDATE "MTC_COST_0322_OWOR_ZCP" SET "关单差异"="在产品新","在产品新"=0
			--WHERE "WorType" IN ('10','20','30') AND "订单状态"='已结算' AND "期间"='2026-04';
			/*
			UPDATE "MTC_COST_0322_OWOR_ZCP" SET "关单差异"="在产品新","在产品新"=0
			WHERE "WorType" IN ('10','20','30') AND "订单状态"='已结算' AND "期间" iN ('2026-06')
			AND :eFcCode='2026-06'
			;*/
		
			
			/*
		SELECT  
T0."FcCode" AS "期间",
T0."DocType",
(CASE T0."WorType" WHEN 10 THEN '生产计划单' WHEN 20 THEN '包装计划单' WHEN 30 THEN '返工计划单' WHEN 40 THEN '生产试打' WHEN 50 THEN '委外工单' END) AS "工单类型",
T0."DocDate" AS "订单日期",
T0."CloseDate" AS "订单关单日期",
CASE WHEN T0."Status"='R' THEN '已下达' WHEN T0."Status"='L' THEN '已结算' WHEN T0."Status"='P' THEN '已计划' END  AS "订单状态",
T9."U_SupNum" AS "订单号",
T0."WorEntry" AS "生产订单号Entry",
T0."WorNum",
T9."U_CardCode",
T10."CardName",
T0."ItemCode" AS "物料编码" ,
T0."ItemName" AS "物料名称",
T0."ItmsGrpCod" AS "物料组",
T0."WorQty" AS "订单数量",
T0."IgnQty" AS "当期入库数量",
TO_CHAR(CAST(T0."Price" AS DECIMAL(19,6))) AS "完工入库单价",
T0."IgnQty"*T0."Price" AS "当期入库成本金额",
T0."Amount" AS "当期成本合计",
T0."1Material" AS "当期材料金额",
T0."2ManExp" AS "当期人工费用",
T0."3LabAmount" AS "当期制造费用",
T0."4WWExp" AS "当期委外费用",
T0."Ign_SUM" AS "累计入库数量",
T0."Amount_SUM" AS "累计成本合计",
T0."1Material_SUM" AS "累计材料",
T0."2ManExp_SUM" AS "累计人工费用",
T0."3LabAmount_SUM" AS "累计制造费用",
T0."4WWExp_SUM" AS "累计委外费用",
IFNULL(T1."1Material",0) AS "累计完工材料合计",
IFNULL(T0."CloseDifAmt",0) AS "关单差异",
IFNULL(T0."1Material_SUM",0)-IFNULL(T1."1Material",0)+IFNULL(T0."CloseDifAmt",0) AS "在产品金额",
T3."StockAct" AS "库存科目",
T0."iLevel" AS "物料等级",
T9."U_OldSysNo" AS "老系统订单号",
T0."CreateDate" AS "创建时间",
T0."Creator" AS "创建人"
FROM MTC_COST_0321_OWOR_SUM T0
LEFT JOIN (SELECT "WorEntry","DocType",SUM("1Material") AS "1Material" FROM MTC_COST_0321_OWOR_SUM WHERE "FcCode"<='[%0]' 
			GROUP BY "WorEntry","DocType"
            ) T1 ON T0."WorEntry"=T1."WorEntry" AND T0."DocType"=T1."DocType"
JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROM OGAR WHERE "PeriodCat"=LEFT('[%0]',4) GROUP BY "ItmsGrpCod"
				) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
LEFT JOIN
		(SELECT '202' AS "DocType","DocEntry","DocNum","U_SupNum","U_OldSysNo","U_CardCode","U_CardName" FROM OWOR
			UNION ALL
		SELECT "Object","DocEntry","DocNum","U_SupNum","U_OldSysNo","U_CardCode","U_CardName" FROM "@MTC_OWOR"
		) T9 ON T0."WorEntry"=T9."DocEntry" AND T0."DocType"=T9."DocType"
LEFT JOIN OCRD T10 ON T10."CardCode"=T9."U_CardCode"
WHERE T0."FcCode" >= '[%0]'
AND T0."FcCode" <= '[%1]'
AND (T2."ItemCode"='[%2]' OR '[%2]'='')
ORDER BY T0."DocDate",CAST(T0."WorNum" AS INT)*/
		
		END IF;
END;