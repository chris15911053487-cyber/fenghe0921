CREATE PROCEDURE "MTC_COST_PROC_0402_CAL_OWOR_30"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50),IN iLevel INT,IN WorNum NVARCHAR(30) DEFAULT '')
LANGUAGE SQLSCRIPT
AS
BEGIN
	--返工单
	DELETE FROM MTC_COST_0321_OWOR_SUM WHERE "iLevel"=:iLevel AND "FcCode"=:FcCode AND ("WorNum" = :WorNum OR :WorNum='') AND "WorType"='30';
	DELETE FROM MTC_COST_0321_OWOR1_REG WHERE "iLevel"=:iLevel AND "FcCode"=:FcCode AND ("WorNum" = :WorNum OR :WorNum='') AND "WorType"='30';
	
	
	INSERT INTO MTC_COST_0321_OWOR_SUM(
	"BPLId", "FcCode","DocType","WorType", "WorEntry", "WorNum",
	"DocDate","CloseDate","Status",
	"ItemCode","ItemName","ItmsGrpCod","iLevel"
	,"WorQty","Ign_SUM","Amount_SUM","1Material_SUM","2ManExp_SUM","3LabAmount_SUM","4WWExp_SUM","CloseDifAmt"
	,"IgnQty","Price","Amount","1Material","2ManExp","3LabAmount","4WWExp"
	,"CreateDate", "Creator")
	SELECT 0,T0."FcCode",T0."DocType",T9."U_OrdType",T0."WorEntry",T0."WorNum"
	,T9."PostDate",T9."CloseDate",T9."Status"
	,T0."ItemCode" AS "物料编码",T7."ItemName",T8."ItmsGrpNam",T2."iLevel" AS "物料等级"
	,T0."Quantity" AS "生产订单数量",T3."IgnQty" AS "Ign_SUM"
	,ROUND(IFNULL(T3."Amount",0),2) AS "Amount_SUM"
	,ROUND(T3."1Material",2) AS "1Material_SUM" --实际投料总额(累计投料)
	,ROUND(T3."2ManExp",2) AS "2ManExp_SUM",ROUND(T3."3LabAmount",2) AS "3LabAmount_SUM"
	,ROUND(T3."4WWExp",2) AS "4WWExp_SUM",ROUND(T3."5ClosedAmt",2) AS "CloseDifAmt"
	,T0."IgnQty" AS "IgnQty"
	--当订单数量大于完工入库数量的时候，则是未完工，取实际折算半成品的数量，否则是实际的金额
	,(CASE WHEN T0."Quantity"-IFNULL(T0."IgnQty",0)>0 THEN IFNULL(T1."Amount",0) ELSE IFNULL(T1."ActAmount",0) END
			+IFNULL(T0."2ManExp",0)+IFNULL(T0."3LabAmount",0)+IFNULL(T0."4WWExp",0))/NULLIF(T0."IgnQty",0)
			AS "Price"
	,ROUND(CASE WHEN T0."Quantity"-IFNULL(T0."IgnQty",0)>0 THEN IFNULL(T1."Amount",0) ELSE IFNULL(T1."ActAmount",0) END
		+IFNULL(T0."2ManExp",0)+IFNULL(T0."3LabAmount",0)+IFNULL(T0."4WWExp",0),2) AS "Amount"	
	,ROUND(CASE WHEN T0."Quantity"-IFNULL(T0."IgnQty",0)>0 THEN IFNULL(T1."Amount",0) ELSE IFNULL(T1."ActAmount",0) END,2)
		AS "计入完工材料"	--理论完工总额（计入已完工生产成本）
	,ROUND(T0."2ManExp",2),ROUND(T0."3LabAmount",2),ROUND(T0."4WWExp",2)
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
				SELECT :FcCode AS "FcCode",T1."DocType",T1."WorEntry",-1*SUM(T1."IgeQty") AS "IgeQty"
				--累计截止到现在的数据：SUM(单个完工产品成本=单位材料成本(领料金额/领料数量)*按照实际完工量计算出的理论用料)
				--按照实际完工量计算出的理论用料=实际入库数量*生产订单的计划用量比（材料计划用量/产成品计划完工数量）
				,SUM(CASE WHEN (-1*IFNULL(T1."IgeQty",0))/NULLIF(IFNULL(T0."IgnQty_SUM",0),0)-T1."Wor1Qty"/T1."OworQty"<0
						THEN -1*T1."Amount"/NULLIF(T0."IgnQty_SUM",0)*T0."IgnQty" ELSE
					  (-1*T1."Amount")/NULLIF((-1*T1."IgeQty"),0)*T0."IgnQty"*T1."Wor1Qty"/T1."OworQty" END) AS "Amount"	--按领料比例折算的金额（当领料数量少于入库数量比的时候，先取实际投料的金额）
				,SUM(-1*T1."Amount") AS "ActAmount"
				FROM 	
					(
						SELECT T1."DocType",T1."WorEntry",T1."ItemCode",T1."Amount",T1."IgeQty",T2."Wor1Qty",T2."OworQty"
						FROM 
						(SELECT T1."DocType",T1."WorEntry",T1."ItemCode",SUM(T1."Amount") AS "Amount",SUM(T1."IgeQty") AS "IgeQty"
							FROM MTC_COST_0321_OWOR1 T1
							WHERE T1."FcCode"<=:FcCode GROUP BY T1."DocType",T1."WorEntry",T1."ItemCode") T1
						LEFT JOIN (SELECT M."DocType",D."WorEntry",D."ItemCode",SUM(D."Quantity") AS "Wor1Qty",M."Quantity" AS "OworQty"
										FROM MTC_COST_0106_OWORLIST1 D
										JOIN MTC_COST_0106_OWORLIST M ON M."FcCode"=D."FcCode" AND M."DocType"=D."DocType" AND D."WorEntry"=M."WorEntry"
										WHERE 1=1 AND M."FcCode"=:FcCode GROUP BY M."DocType",D."WorEntry",D."ItemCode",M."Quantity"
									) T2 ON T1."DocType"=T2."DocType" AND T1."WorEntry"=T2."WorEntry" AND T1."ItemCode"=T2."ItemCode"
					) T1
				JOIN (SELECT "DocType","WorEntry",SUM("IgnQty") AS "IgnQty_SUM"
					 ,SUM(CASE WHEN "FcCode"=:FcCode THEN "IgnQty" ELSE 0 END) AS "IgnQty"
					FROM MTC_COST_0321_OWOR WHERE "FcCode"<=:FcCode GROUP BY "DocType","WorEntry") T0 ON T1."DocType"=T0."DocType" AND T1."WorEntry"=T0."WorEntry"
				WHERE 1=1 GROUP BY T1."DocType",T1."WorEntry"
			) T1 ON  T0."FcCode"=T1."FcCode" AND T1."DocType"=T0."DocType" AND T0."WorEntry"=T1."WorEntry"
		--累计【制造费用+人工费用+委外费用】
		LEFT JOIN (
				SELECT T0."BPLId",:FcCode AS "FcCode",T0."DocType",T0."WorEntry"
				,SUM(T0."Amount") AS "Amount"
				--,SUM((-1*T2."Amount")/(-1*NULLIF(T2."IgeQty",0))*T0."IgnQty") AS "Amount"
				,SUM("4WWExp") AS "4WWExp"
				,SUM("3LabAmount") AS "3LabAmount"
				,SUM("2ManExp") AS "2ManExp"
				,SUM("1Material") AS "1Material"
				,SUM("IgnQty") AS "IgnQty"
				,SUM("5ClosedAmt") AS "5ClosedAmt"
				FROM MTC_COST_0321_OWOR T0
				WHERE T0."FcCode"<=:FcCode GROUP BY T0."BPLId",T0."DocType",T0."WorEntry"
			) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."DocType"=T3."DocType" AND T0."WorEntry"=T3."WorEntry"
		JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
		JOIN OITM T7 ON T0."ItemCode"=T7."ItemCode"
		JOIN OITB T8 ON T7."ItmsGrpCod"=T8."ItmsGrpCod"
		JOIN (SELECT '202' AS "DocType","DocEntry","DocNum","U_OrdType","PostDate","CloseDate","Status" FROM OWOR
				UNION ALL
			 SELECT "Object" AS "DocType","DocEntry","DocNum","U_OrdType","U_PostDate","U_CloseDate","U_Status" FROM "@MTC_OWOR" 
			) T9 ON T0."DocType"=T9."DocType" AND T0."WorEntry"=T9."DocEntry"
		WHERE T2."iLevel"=:iLevel AND T0."FcCode"=:FcCode AND (T0."WorNum" = :WorNum OR :WorNum='')
		AND T0."WorType"='30'
		;
		
		--写入在产品结转明细表
		INSERT INTO "MTC_COST_0321_OWOR1_REG"(
		"BPLId","FcCode","iLevel","DocType","WorType","WorEntry","WorNum",
		"LineNum","ItemCode","ItemName","ItmsGrpCod",
		"IgeQty","Price","Amount",
		"CreateDate","Creator"
		)
		SELECT 0 AS "BPLId",:FcCode AS "FcCode",T."iLevel",T1."DocType",T1."WorType",T1."WorEntry",T1."WorNum",
		0 AS "LineNum",T1."ItemCode",T7."ItemName",T7."ItmsGrpCod",
		-1*SUM(T1."IgeQty") AS "IgeQty",0 AS "Price",
		--累计截止到现在的数据：SUM(单个完工产品成本=单位材料成本(领料金额/领料数量)*按照实际完工量计算出的理论用料)
		--按照实际完工量计算出的理论用料=实际入库数量*生产订单的计划用量比（材料计划用量/产成品计划完工数量）
		SUM(CASE WHEN (-1*IFNULL(T1."IgeQty",0))/NULLIF(IFNULL(T0."IgnQty_SUM",0),0)-T1."Wor1Qty"/T1."OworQty"<0
				THEN -1*T1."Amount"/NULLIF(T0."IgnQty_SUM",0)*T0."IgnQty" ELSE
			  (-1*T1."Amount")/NULLIF((-1*T1."IgeQty"),0)*T0."IgnQty"*T1."Wor1Qty"/T1."OworQty" END) AS "Amount",	--按领料比例折算的金额（当领料数量少于入库数量比的时候，先取实际投料的金额）
		--,SUM(-1*T1."Amount") AS "ActAmount"
		CURRENT_TIMESTAMP,:UserCode
		FROM MTC_COST_0321_OWOR T 
		JOIN
			(
				SELECT T1."DocType",T1."WorType",T1."WorEntry",T1."WorNum",T1."ItemCode",T1."Amount",T1."IgeQty",T2."Wor1Qty",T2."OworQty"
				FROM 
				(SELECT T1."DocType",T1."WorType",T1."WorEntry",T1."WorNum",T1."ItemCode",SUM(T1."Amount") AS "Amount",SUM(T1."IgeQty") AS "IgeQty"
					FROM MTC_COST_0321_OWOR1 T1
					WHERE T1."FcCode"<=:FcCode GROUP BY T1."DocType",T1."WorType",T1."WorEntry",T1."WorNum",T1."ItemCode"
				) T1
				LEFT JOIN (SELECT M."DocType",D."WorEntry",D."ItemCode",SUM(D."Quantity") AS "Wor1Qty",M."Quantity" AS "OworQty"
								FROM MTC_COST_0106_OWORLIST1 D
								JOIN MTC_COST_0106_OWORLIST M ON M."FcCode"=D."FcCode" AND M."DocType"=D."DocType" AND D."WorEntry"=M."WorEntry"
								WHERE 1=1 AND M."FcCode"=:FcCode GROUP BY M."DocType",D."WorEntry",D."ItemCode",M."Quantity"
							) T2 ON T1."DocType"=T2."DocType" AND T1."WorEntry"=T2."WorEntry" AND T1."ItemCode"=T2."ItemCode"
			) T1 ON T."DocType"=T1."DocType" AND T."WorEntry"=T1."WorEntry"
		JOIN (SELECT "DocType","WorEntry",SUM("IgnQty") AS "IgnQty_SUM"
			 ,SUM(CASE WHEN "FcCode"=:FcCode THEN "IgnQty" ELSE 0 END) AS "IgnQty"
			FROM MTC_COST_0321_OWOR WHERE "FcCode"<=:FcCode GROUP BY "DocType","WorEntry"
			) T0 ON T1."DocType"=T0."DocType" AND T1."WorEntry"=T0."WorEntry"
		JOIN U_COILV T2 ON T."FcCode"=T2."FcCode" AND T."ItemCode"=T2."ItemCode"
		JOIN OITM T7 ON T1."ItemCode"=T7."ItemCode"
		WHERE 1=1 AND T2."iLevel"=:iLevel AND T."FcCode"=:FcCode AND (T."WorNum" = :WorNum OR :WorNum='')
		AND T."WorType"='30'
		GROUP BY T1."DocType",T1."WorType",T1."WorEntry",T1."WorNum",T."iLevel",
		T1."ItemCode",T7."ItemName",T7."ItmsGrpCod";
END