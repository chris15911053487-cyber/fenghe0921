CREATE PROCEDURE "MTC_RPT_CO4003"
(
  IN UserId INT,
  IN FcCode NVARCHAR(30),
  IN ItemCode NVARCHAR(50),
  IN WorNum NVARCHAR(50)
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 

	SELECT T0."FcCode",T0."DocType"
	,CASE T9."U_OrdType" WHEN 10 THEN '生产计划单' WHEN 20 THEN '包装计划单' WHEN 30 THEN '返工计划单' WHEN 40 THEN '生产试打' WHEN 50 THEN '委外工单' END 
		AS "工单类型"
	,T0."WorEntry",T0."WorNum"
	,T7."ItemCode",T7."ItemName" AS "产成品名称",T8."ItmsGrpNam" AS "产成品类型"
	,T0."Quantity"	AS "计划数量"
	,T0."IgnQty"	AS "入库数量"
	,T1."ItemCode"	AS "子件编码"
	,T11."ItemName" AS "子件名称"
	,T1."Qty"		AS "计入完工材料数量"
	,CASE WHEN T0."Quantity"-IFNULL(T0."IgnQty",0)>0 THEN IFNULL(T1."Amount",0) ELSE IFNULL(T1."ActAmount",0) END
		AS "计入完工材料金额"	--理论完工总额（计入已完工生产成本）

	,T1."IgeQty"	AS "领料数量"
	,T1."Amount"	AS "领料金额（在产品）"
	,T1."ActAmount" AS "实际领料金额"
	,CASE WHEN T0."Quantity"-IFNULL(T0."IgnQty",0)>0 THEN '在产品领料' ELSE '实际领料' END  AS "金额备注"
	,T0."2ManExp" AS "人工费用",T0."3LabAmount" AS "制造费用",T0."4WWExp" AS "委外费用"
	
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	JOIN (
				SELECT :FcCode AS "FcCode",T1."DocType",T1."WorEntry",T1."WorNum",T1."ItemCode",-1*SUM(T1."IgeQty") AS "IgeQty"
				--累计截止到现在的数据：SUM(单个完工产品成本=单位材料成本(领料金额/领料数量)*按照实际完工量计算出的理论用料)
				--按照实际完工量计算出的理论用料=实际入库数量*生产订单的计划用量比（材料计划用量/产成品计划完工数量）
				,SUM(CASE WHEN (-1*IFNULL(T1."IgeQty",0))/NULLIF(IFNULL(T0."IgnQty_SUM",0),0)-T1."Wor1Qty"/T1."OworQty"<0
						THEN -1*T1."Amount"/NULLIF(T0."IgnQty_SUM",0)*T0."IgnQty" ELSE
					  (-1*T1."Amount")/NULLIF((-1*T1."IgeQty"),0)*T0."IgnQty"*T1."Wor1Qty"/T1."OworQty" END) AS "Amount"	--按领料比例折算的金额（当领料数量少于入库数量比的时候，先取实际投料的金额）
				,SUM(CASE WHEN (-1*IFNULL(T1."IgeQty",0))/NULLIF(IFNULL(T0."IgnQty_SUM",0),0)-T1."Wor1Qty"/T1."OworQty"<0
						THEN -1*IFNULL(T1."IgeQty",0) ELSE
					  T0."IgnQty"*T1."Wor1Qty"/T1."OworQty" END) AS "Qty"	--按领料比例折算的在产品领料数量
				,SUM(-1*T1."Amount") AS "ActAmount"
				FROM 	
					(
						SELECT T1."DocType",T1."WorEntry",T1."WorNum",T1."ItemCode",T1."Amount",T1."IgeQty",T2."Wor1Qty",T2."OworQty"
						FROM 
						(SELECT T1."DocType",T1."WorEntry",T1."WorNum",T1."ItemCode",SUM(T1."Amount") AS "Amount",SUM(T1."IgeQty") AS "IgeQty"
							FROM MTC_COST_0321_OWOR1 T1
							WHERE T1."FcCode"<=:FcCode GROUP BY T1."DocType",T1."WorEntry",T1."WorNum",T1."ItemCode"
						) T1
						LEFT JOIN (SELECT M."DocType",D."WorEntry",D."ItemCode",SUM(D."Quantity") AS "Wor1Qty",M."Quantity" AS "OworQty"
										FROM MTC_COST_0106_OWORLIST1 D
										JOIN MTC_COST_0106_OWORLIST M ON M."FcCode"=D."FcCode" AND M."DocType"=D."DocType" AND D."WorEntry"=M."WorEntry"
										WHERE 1=1 AND M."FcCode"=:FcCode GROUP BY M."DocType",D."WorEntry",D."ItemCode",M."Quantity"
									) T2 ON T1."DocType"=T2."DocType" AND T1."WorEntry"=T2."WorEntry" AND T1."ItemCode"=T2."ItemCode"
					) T1
				JOIN (SELECT "DocType","WorEntry",SUM("IgnQty") AS "IgnQty_SUM"
					 ,SUM(CASE WHEN "FcCode"=:FcCode THEN "IgnQty" ELSE 0 END) AS "IgnQty"
					FROM MTC_COST_0321_OWOR WHERE "FcCode"<=:FcCode GROUP BY "DocType","WorEntry"
					) T0 ON T1."DocType"=T0."DocType" AND T1."WorEntry"=T0."WorEntry"
				WHERE 1=1
				AND (T1."WorNum"=:WorNum OR :WorNum='')
				GROUP BY T1."DocType",T1."WorEntry",T1."WorNum",T1."ItemCode"
			) T1 ON  T0."FcCode"=T1."FcCode" AND T1."DocType"=T0."DocType" AND T0."WorEntry"=T1."WorEntry"
		JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
		JOIN OITM T7 ON T0."ItemCode"=T7."ItemCode"
		JOIN OITB T8 ON T7."ItmsGrpCod"=T8."ItmsGrpCod"
		JOIN (SELECT '202' AS "DocType","DocEntry","DocNum","U_OrdType","PostDate","CloseDate","Status" FROM OWOR
				UNION ALL
			 SELECT "Object" AS "DocType","DocEntry","DocNum","U_OrdType","U_PostDate","U_PostDate","U_Status" FROM "@MTC_OWOR" 
			) T9 ON T0."DocType"=T9."DocType" AND T0."WorEntry"=T9."DocEntry"
		JOIN OITM T11 ON T1."ItemCode"=T11."ItemCode"
		WHERE T9."U_OrdType" NOT IN ('40','50')	--排除试打、委外
			;
				
END