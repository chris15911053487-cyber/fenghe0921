CREATE PROCEDURE "MTC_COST_PROC_0402_CAL_OWOR_BACKUP_20240113"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50),IN iLevel INT,IN WorNum NVARCHAR(30) DEFAULT '')
LANGUAGE SQLSCRIPT
AS
BEGIN



	DELETE FROM MTC_COST_0321_OWOR_SUM WHERE "iLevel"=:iLevel AND "FcCode"=:FcCode AND ("WorNum" = :WorNum OR :WorNum='');
	
	INSERT INTO MTC_COST_0321_OWOR_SUM(
	"BPLId", "FcCode", "WorType", "WorEntry", "WorNum",
	"ItemCode", "ItemName", "ItmsGrpCod","iLevel","Amount_SUM", "Quantity",
	 "IgnQty" ,	"Price", "Amount",
		 "1Material", "2ManExp", "3LabAmount" , "4WWExp",
		 "CreateDate", "Creator")
	SELECT 0,T0."FcCode",T9."U_OrdType",T0."WorEntry",T0."WorNum"
	,T0."ItemCode" AS "物料编码",'','',T2."iLevel" AS "物料等级"
	,(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0)) AS "完工成本合计"
--,T0."Amount" AS "投入合计"
	,T4."IgnQty" AS "已完工数量合计"
--,T1."IgeQty" AS "材料已投入数量"
	,T0."IgnQty" AS "当月完工数量"
	,(CASE WHEN T0."Quantity"-IFNULL(T0."IgnQty",0)>0 THEN IFNULL(T1."Amount",0) ELSE IFNULL(T1."OriAmount",0) END+IFNULL(T3."Amount",0))/NULLIF(T4."IgnQty",0) AS "完工成本单价"
	,CASE WHEN T0."Quantity"-IFNULL(T0."IgnQty",0)>0 THEN IFNULL(T1."Amount",0) ELSE IFNULL(T1."OriAmount",0) END	AS "计入完工材料"	--理论完工总额（计入已完工生产成本）
	,T4."1Material" AS "投入材料合计" --实际投料总额
	,0,0
--,IFNULL(T3."Amount",0)	AS "计入完工费用"	--理论完工总额（计入已完工生产成本）
--,IFNULL(T4."1Material",0)-IFNULL(T1."Amount",0) AS "在制品（1材料）"
	,T4."Amount" AS "投入费用WW合计"
--,IFNULL(T4."Amount",0)-IFNULL(T3."Amount",0) AS "在制品（费用）"
		,CURRENT_TIMESTAMP
		,'manager'
		FROM MTC_COST_0321_OWOR T0
		--材料费用
		LEFT JOIN (
				SELECT :FcCode AS "FcCode",T1."WorEntry",-1*SUM(T1."IgeQty") AS "IgeQty"
				--SUM(单个完工产品成本=单位材料成本(领料金额/领料数量)*按照实际完工量计算出的理论用料)
				--按照实际完工量计算出的理论用料=实际入库数量*生产订单的计划用量比（材料计划用量/产成品计划完工数量）
				,SUM((-1*T1."Amount")/NULLIF((-1*T1."IgeQty"),0)*T0."IgnQty"*T1."Wor1Qty"/T1."OworQty") AS "Amount"
				,SUM(-1*T1."Amount") AS "OriAmount"
				FROM (SELECT T1."WorEntry",T1."ItemCode",SUM(T1."Amount") AS "Amount",SUM(T1."IgeQty") AS "IgeQty"
							,SUM(T2."Wor1Qty") AS "Wor1Qty",MAX(T2."OworQty") AS "OworQty"
							FROM MTC_COST_0321_OWOR1 T1
							LEFT JOIN (SELECT D."WorEntry",D."LineNum",D."Quantity" AS "Wor1Qty",M."Quantity" AS "OworQty"
										FROM MTC_COST_0106_OWORLIST1 D
										JOIN MTC_COST_0106_OWORLIST M ON M."FcCode"=D."FcCode" AND D."WorEntry"=M."WorEntry"
										WHERE 1=1 AND M."FcCode"=:FcCode
									) T2 ON T1."WorEntry"=T2."WorEntry" AND T1."LineNum"=T2."LineNum"
							WHERE T1."FcCode"<=:FcCode GROUP BY T1."WorEntry",T1."ItemCode"
					) T1
				JOIN (SELECT "WorEntry",SUM("IgnQty") AS "IgnQty"
					FROM MTC_COST_0321_OWOR WHERE "FcCode"<=:FcCode GROUP BY "WorEntry") T0 ON  T1."WorEntry"=T0."WorEntry"
				WHERE 1=1 GROUP BY T1."WorEntry"
			) T1 ON  T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
		--制造费用+人工费用+委外费用
		LEFT JOIN (
				SELECT T2."BPLId",:FcCode AS "FcCode",T2."WorEntry"
				,SUM((-1*T2."Amount")) AS "Amount"
				--,SUM((-1*T2."Amount")/(-1*NULLIF(T2."IgeQty",0))*T0."IgnQty") AS "Amount"
				,SUM(CASE WHEN T2."CostCode"='20' THEN (-1*T2."Amount") ELSE 0 END) AS "4ExpAmt"
				FROM MTC_COST_0321_OWOR2 T2
				JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T2."WorEntry"=T0."WorEntry"
				WHERE T2."FcCode"<=:FcCode GROUP BY T2."BPLId",T2."WorEntry"
			) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."WorEntry"=T3."WorEntry"
		JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
		LEFT JOIN (SELECT :FcCode AS "FcCode","WorEntry",SUM("IgnQty") AS "IgnQty"
					,SUM("1Material") AS "1Material",SUM("4WWExp") AS "Amount"
					FROM MTC_COST_0321_OWOR
					WHERE "FcCode"<=:FcCode GROUP BY "WorEntry"
					) T4 ON T0."FcCode"=T4."FcCode" AND T0."WorEntry"=T4."WorEntry"
		JOIN OWOR T9 ON T0."WorEntry"=T9."DocEntry"
		WHERE T2."iLevel"=:iLevel AND T0."FcCode"=:FcCode AND (T0."WorNum" = :WorNum OR :WorNum='');
		
		--AND T0."WorType"<>'50'
		
	
	
	
	/* 查询语句
SELECT T0."FcCode",T0."WorEntry",T0."WorNum"
,T9."U_OrdType",T9."U_OrdType2"
,T0."ItemCode" AS "物料编码"
,T2."iLevel" AS "物料等级"
,T0."Amount" AS "投入合计"
,T0."IgnQty" AS "当月完工数量"
,T4."IgnQty" AS "已完工数量合计"
,T1."IgeQty" AS "材料已投入数量"
,T4."1Material" AS "投入材料合计" --实际投料总额
,IFNULL(T1."Amount",0)	AS "计入完工材料"	--理论完工总额（计入已完工生产成本）
,IFNULL(T4."1Material",0)-IFNULL(T1."Amount",0) AS "在制品（1材料）"
,T4."Amount" AS "投入费用WW合计"
,IFNULL(T3."Amount",0)	AS "计入完工费用"	--理论完工总额（计入已完工生产成本）
,IFNULL(T4."Amount",0)-IFNULL(T3."Amount",0) AS "在制品（费用）"
,(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0)) AS "完工成本合计"
,(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))/T4."IgnQty" AS "完工成本单价"
,T0."1Material",T1."Amount"
	,T0."4WWExp",T3."4ExpAmt",T0."IgnQty",T0.*
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT :FcCode AS "FcCode",T1."WorEntry",-1*SUM(T1."IgeQty") AS "IgeQty"
			--SUM(单个完工产品成本=单位材料成本(领料金额/领料数量)*按照实际完工量计算出的理论用料)
			--按照实际完工量计算出的理论用料=实际入库数量*生产订单的计划用量比（材料计划用量/产成品计划完工数量）
			,SUM((-1*T1."Amount")/NULLIF((-1*T1."IgeQty"),0)*T0."IgnQty"*T1."Wor1Qty"/T1."OworQty") AS "Amount"
			FROM (SELECT T1."WorEntry",T1."ItemCode",SUM(T1."Amount") AS "Amount",SUM(T1."IgeQty") AS "IgeQty"
						,SUM(T2."Wor1Qty") AS "Wor1Qty",MAX(T2."OworQty") AS "OworQty"
						FROM MTC_COST_0321_OWOR1 T1
						LEFT JOIN (SELECT D."WorEntry",D."LineNum",D."Quantity" AS "Wor1Qty",M."Quantity" AS "OworQty"
									FROM MTC_COST_0106_OWORLIST1 D
									JOIN MTC_COST_0106_OWORLIST M ON M."FcCode"=D."FcCode" AND D."WorEntry"=M."WorEntry"
									WHERE 1=1 AND M."FcCode"=:FcCode
								) T2 ON T1."WorEntry"=T2."WorEntry" AND T1."LineNum"=T2."LineNum"
						WHERE T1."FcCode"<=:FcCode GROUP BY T1."WorEntry",T1."ItemCode"
				) T1
			JOIN (SELECT "WorEntry",SUM("IgnQty") AS "IgnQty"
				FROM MTC_COST_0321_OWOR WHERE "FcCode"<=:FcCode GROUP BY "WorEntry") T0 ON  T1."WorEntry"=T0."WorEntry"
			WHERE 1=1 GROUP BY T1."WorEntry"
		) T1 ON  T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T2."WorEntry"
			,SUM((-1*T2."Amount")) AS "Amount"
			--,SUM((-1*T2."Amount")/(-1*NULLIF(T2."IgeQty",0))*T0."IgnQty") AS "Amount"
			,SUM(CASE WHEN T2."CostCode"='20' THEN (-1*T2."Amount") ELSE 0 END) AS "4ExpAmt"
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"<=:FcCode GROUP BY T2."BPLId",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	LEFT JOIN (SELECT :FcCode AS "FcCode","WorEntry",SUM("IgnQty") AS "IgnQty"
				,SUM("1Material") AS "1Material",SUM("4WWExp") AS "Amount"
				FROM MTC_COST_0321_OWOR
				WHERE "FcCode"<=:FcCode GROUP BY "WorEntry"
				) T4 ON T0."FcCode"=T4."FcCode" AND T0."WorEntry"=T4."WorEntry"
	JOIN OWOR T9 ON T0."WorEntry"=T9."DocEntry"
	WHERE 1=1
	--AND T2."iLevel"=3
	AND T0."FcCode"=:FcCode
	AND T0."WorNum"='267'
	AND T0."WorType"='50';*/
END