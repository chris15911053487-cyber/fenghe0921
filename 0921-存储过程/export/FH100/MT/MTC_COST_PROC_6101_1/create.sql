CREATE PROCEDURE "MTC_COST_PROC_6101_1"
(
  UserCode NVARCHAR(50),
  FcCode NVARCHAR(50),
  STYPE NVARCHAR(30),    --SUM Detail ToOJDT 明细 
  CalType NVARCHAR(30),	--PUR1 材料计提   PUR4委外费用计提 CL_ZG WWExp_ZG
  IsOJDT NVARCHAR(10)
)
AS
BEGIN
	
	DECLARE MAXEntry INT;
	DECLARE TransCode NVARCHAR(30)=''; --交易代码
	DECLARE sdate DATE;
	DECLARE edate DATE;
	
	--SELECT '2024-01-01',"T_RefDate" INTO sdate,edate FROM "OFPR" WHERE "Code"=:FcCode;
	SELECT "F_RefDate","T_RefDate" INTO sdate,edate FROM "OFPR" WHERE "Code"=:FcCode;
	
  	

	TMP=
	SELECT CASE WHEN T1."ItemCode"='X0510001' THEN '委外费用' ELSE '材料' END AS "Type"
	,T0."CardCode",T0."CardName",T0."DocDate",T4."U_OldSysNo" AS "OPOROldSN",T0."U_OldSysNo" AS "OPDNOldSN"
	,T0."ObjType" AS "CalObjType",T0."DocEntry" AS "CalDocEntry",T0."DocNum" AS "CalDocNum",T1."LineNum" AS "CalLineNum"
	,T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_ItemCode"
	,T1."ItemCode"
	,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity" AS "Qty"
	,CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS "Price"
	,ROUND(CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END
			*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0
			THEN T1."Quantity"*T1."U_InitPrice" WHEN T1."U_IsPrice"='Y' THEN T1."Price"*T1."Quantity" ELSE T1."LineTotal" END,2) AS "Amt" --注释掉LineTotal OPDN.DocNum=2002有类似这样的情况
	,ROUND(CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."LineTotal",2) AS "LineTotal"
	,ROUND(CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."GTotal",2) AS "GTotal"
	FROM "OPDN" T0
	INNER JOIN "PDN1" T1 ON T0."DocEntry"=T1."DocEntry"
	INNER JOIN "OITM" T2 ON T1."ItemCode"=T2."ItemCode"
	LEFT JOIN "POR1" T3 ON T1."BaseEntry" =T3."DocEntry" AND T1."BaseLine" =T3."LineNum" AND T1."BaseType"=T3."ObjType"
	LEFT JOIN "OPOR" T4 ON T3."DocEntry" =T4."DocEntry"
	WHERE 1=1
	--AND (T0."CANCELED"='N' OR T0."DocNum" iN (9029,9760,13841))
	AND T0."DocDate">=:sdate
	AND T0."DocDate"<=:edate
	
	UNION ALL
	SELECT CASE WHEN T1."ItemCode"='X0510001' THEN '委外费用' ELSE '材料' END AS "Type"
	,T0."CardCode",T0."CardName",T0."DocDate",T2."OPOROldSN",T2."OPDNOldSN"
	,T0."ObjType" AS "CalObjType",T0."DocEntry" AS "CalDocEntry",T0."DocNum" AS "CalDocNum",T1."LineNum" AS "CalLineNum"
	,T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_ItemCode"
	,T1."ItemCode"
	,CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity" AS "Qty"
	,CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" WHEN T1."U_IsPrice"='Y' THEN T1."Price"*T1."Quantity" ELSE T1."LineTotal" END AS "Price"
	,ROUND(CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END
			*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0
			THEN T1."Quantity"*T1."U_InitPrice" ELSE T1."LineTotal" END,2) AS "Amt"
	,ROUND(CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."LineTotal",2) AS "LineTotal"
	,ROUND(CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."GTotal",2) AS "GTotal"
	FROM "ORPD" T0
	INNER JOIN "RPD1" T1 ON T0."DocEntry"=T1."DocEntry"
	LEFT JOIN (SELECT M."ObjType",D."DocEntry",M."DocNum",D."LineNum"
			,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN D."U_InitPrice" ELSE D."Price" END AS "Price"
			,M2."U_OldSysNo" "OPOROldSN",M."U_OldSysNo" "OPDNOldSN"
			 FROM "OPDN" M
			 JOIN "PDN1" D ON M."DocEntry"=D."DocEntry"
			 LEFT JOIN "POR1" D2 ON D."BaseEntry" =D2."DocEntry" AND D."BaseLine" =D2."LineNum" AND D."BaseType"=D2."ObjType"
			 LEFT JOIN "OPOR" M2 ON D2."DocEntry" =M2."DocEntry"
			 ) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
	WHERE 1=1
	--AND T0."CANCELED"='N'
	AND T0."DocDate">=:sdate
	AND T0."DocDate"<=:edate
	
	--针对来源于采购收货，才需要冲销暂估，需要按照采购收货的价格进行（冲暂估的金额，所以价格的取数要和采购收货单的一致）
	--发票取消的单据-视为无效，需要为0
	UNION ALL
	SELECT CASE WHEN T1."ItemCode"='X0510001' THEN '委外费用' ELSE '材料' END
	,T0."CardCode",T0."CardName",T0."DocDate",T2."OPOROldSN",T2."OPDNOldSN"
	,T2."ObjType" AS "CalObjType",T2."DocEntry" AS "CalDocEntry",T2."DocNum" AS "CalDocNum",T2."LineNum" AS "CalLineNum"
	,T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_ItemCode"
	,T1."ItemCode"
	,CASE WHEN T0."CANCELED"='Y' THEN 0 ELSE -1 END*T1."Quantity" AS "Qty"
	,T2."Price" AS "Price"
	,ROUND(CASE WHEN T0."CANCELED"='Y' THEN 0 ELSE -1 END
			*CASE WHEN T1."Quantity"=T2."Quantity" THEN T2."LineTotal"
				 ELSE T1."Quantity"*T2."Price" END,2) AS "Amt"
	,ROUND(CASE WHEN T0."CANCELED"='Y' THEN 0 ELSE -1 END*T1."LineTotal",2) AS "LineTotal"
	,ROUND(CASE WHEN T0."CANCELED"='Y' THEN 0 ELSE -1 END*T1."GTotal",2) AS "GTotal"
	FROM "OPCH" T0
	INNER JOIN "PCH1" T1 ON T0."DocEntry"=T1."DocEntry"
	JOIN (SELECT M."ObjType",D."DocEntry",M."DocNum",D."LineNum",D."Quantity",D."U_InitPrice"
			,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN D."U_InitPrice" ELSE D."Price" END AS "Price"
			,ROUND(CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN D."Quantity"*D."U_InitPrice" ELSE D."LineTotal" END,2) AS "LineTotal"
			,M2."U_OldSysNo" "OPOROldSN",M."U_OldSysNo" "OPDNOldSN"
			FROM "OPDN" M
			 JOIN "PDN1" D ON M."DocEntry"=D."DocEntry"
			 LEFT JOIN "POR1" D2 ON D."BaseEntry" =D2."DocEntry" AND D."BaseLine" =D2."LineNum" AND D."BaseType"=D2."ObjType"
			 LEFT JOIN "OPOR" M2 ON D2."DocEntry" =M2."DocEntry"
			 ) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
	WHERE 1=1
	AND T0."DocDate">=:sdate
	AND T0."DocDate"<=:edate
	--AND T0."CANCELED"='N'
	
	UNION ALL
	SELECT CASE WHEN T1."ItemCode"='X0510001' THEN '委外费用' ELSE '材料' END
	,T0."CardCode",T0."CardName",T0."DocDate",'' AS "OPOROldSN",'' AS "OPDNOldSN"
	,T2."ObjType" AS "CalObjType",T2."DocEntry" AS "CalDocEntry",T2."DocNum" AS "CalDocNum",T2."LineNum" AS "CalLineNum"
	,T0."ObjType",T0."DocEntry",T0."DocNum",T1."LineNum",T1."U_ItemCode"
	,T1."ItemCode"
	,CASE WHEN T0."CANCELED"='Y' THEN 0 ELSE 1 END*T1."Quantity" AS "Qty"
	,T2."Price" AS "Price"
	,ROUND(CASE WHEN T0."CANCELED"='Y' THEN 0 ELSE 1 END
			*CASE WHEN T1."Quantity"=T2."Quantity" THEN T2."LineTotal"
				 ELSE T1."Quantity"*T2."Price" END,2) AS "Amt"
	,ROUND(CASE WHEN T0."CANCELED"='Y' THEN 0 ELSE 1 END*T1."LineTotal",2) AS "LineTotal"
	,ROUND(CASE WHEN T0."CANCELED"='Y' THEN 0 ELSE 1 END*T1."GTotal",2) AS "GTotal"
	FROM "ORPC" T0
	INNER JOIN "RPC1" T1 ON T0."DocEntry"=T1."DocEntry"
	JOIN (SELECT M."ObjType",D."DocEntry",M."DocNum",D."LineNum",D."Quantity",D."U_InitPrice"
			,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN D."U_InitPrice" ELSE D."Price" END AS "Price"
			,ROUND(CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN D."Quantity"*D."U_InitPrice" ELSE D."LineTotal" END,2) AS "LineTotal"
			 FROM "ORPD" M
			 JOIN "RPD1" D ON M."DocEntry"=D."DocEntry"
			 ) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
	WHERE 1=1
	AND T0."DocDate">=:sdate
	AND T0."DocDate"<=:edate
	--AND T0."CANCELED"='N'
	;
	
	IF :STYPE='SUM' THEN
		OPDN_SUM=
		SELECT T0."供应商编码",T0."供应商名称",SUM("计入暂估") AS "计入暂估"
			FROM (
			SELECT
			'采购收货' AS "类型"
			,T0."DocNum" AS "收退货Num"
			,T0."U_SupNum" AS "收退货单号"
			,T0."U_OldSysNo" AS "老系统单号"
			,T0."NumAtCard" AS "参考号"
			, T0."DocDate" AS "过账日期"
			, T0."DocCur" AS "币种"
			, T0."DocRate" AS "汇率"
			, T0."CardCode" AS "供应商编码"
			, T0."CardName" AS "供应商名称"
			, T1."ItemCode" AS "物料编号"
			, T1."Dscription" AS "物料名称"
			, CAST(CAST(CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "数量"
			, T1."Price" AS "未税单价"
			, T1."PriceAfVAT" AS "含税单价"
			, T1."LineTotal" AS "未税金额（本币）"
			, T1."GTotal"  AS "含税金额（本币）"
			, T1."U_InitPrice" AS "初始单价(未税)"
			,  CAST(CAST(CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END
				*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "暂估单价"
			, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*
			  CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END *
				ROUND(CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."Quantity"*T1."U_InitPrice" WHEN T1."U_IsPrice"='Y' THEN T1."Price"*T1."Quantity" ELSE T1."LineTotal" END
					,2) AS "计入暂估"
			, CASE when T1."LineStatus"='O' then N'未清' when T1."LineStatus"='C' then N'已清'  END  AS "行状态"
			, T0."TransId" AS "交易编码"
			, T1."AcctCode" AS "收入科目" 
			, T0."ObjType"  
			, T0."DocEntry"
			FROM OPDN T0  
			INNER JOIN PDN1 T1 ON T0."DocEntry" = T1."DocEntry" 
			LEFT JOIN "OCRD" T5 ON T0."CardCode"=T5."CardCode"
			LEFT JOIN OITM T11 ON T1."ItemCode"=T11."ItemCode"
			--WHERE T0."CANCELED"='N'   
			
			UNION ALL 
			
			SELECT 
			'采购退货' AS "类型"
			,T0."DocNum" AS "收退货Num" /*退货*/
			,T0."U_SupNum" AS "收退货单号"
			,T0."U_OldSysNo" AS "老系统单号"
			,T0."NumAtCard" AS "参考号"
			, T0."DocDate" AS "过账日期"
			, T0."DocCur" AS "币种"
			, T0."DocRate" AS "汇率"
			, T0."CardCode" AS "供应商编码"
			, T0."CardName" AS "供应商名称"
			, T1."ItemCode" AS "物料编号"
			, T1."Dscription" AS "物料名称"
			, CAST(CAST(CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "数量"
			, T1."Price" AS "未税单价"
			, T1."PriceAfVAT" AS "含税单价"
			, -1*T1."LineTotal" AS "未税金额（本币）"
			, -1*T1."GTotal"  AS "含税金额（本币）"
			, T1."U_InitPrice" AS "初始单价(未税)"
			, CAST(CAST(CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END
				*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "暂估单价"
			, CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END *
				ROUND(CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."Quantity"*T1."U_InitPrice" WHEN T1."U_IsPrice"='Y' THEN T1."Price"*T1."Quantity" ELSE T1."LineTotal" END
					,2) AS "计入暂估"
			, CASE when T1."LineStatus"='O' then N'未清' when T1."LineStatus"='C' then N'已清'  END  AS "行状态"
			, T0."TransId" AS "交易编码"
			, T1."AcctCode" AS "收入科目" 
			, T0."ObjType"
			, T0."DocEntry"
			FROM ORPD T0  
			INNER JOIN RPD1 T1 ON T0."DocEntry" = T1."DocEntry" 
			LEFT JOIN OITM T11 ON T1."ItemCode"=T11."ItemCode"
			--WHERE T0."CANCELED"='N'
			) T0
			WHERE  1=1 
			AND  (T0."过账日期">=:sdate)
			AND (T0."过账日期"<=:edate)
			GROUP BY T0."供应商编码",T0."供应商名称"
			;
			
		
		--取分录计提的数据
        OJDT_Amt=
        SELECT T2."CardCode" ,T2."CardName"
        ,SUM(CASE WHEN T0."TransCode" IN ('PUR1','PUR4') THEN T1."Debit"-T1."Credit" ELSE 0 END) AS "OJDT_OPDNAmt"
        ,SUM(CASE WHEN IFNULL(T0."TransCode",'') NOT IN ('PUR1','PUR4') THEN -1*(T1."Debit"-T1."Credit") ELSE 0 END) AS "OJDT_OPCHAmt"
		FROM OJDT T0
		JOIN JDT1 T1 ON T0."TransId"=T1."TransId"
		LEFT JOIN "OCRD" T2 ON T1."U_VendorCode"=T2."CardCode"
		WHERE 1=1
		AND T0."RefDate">=:sdate
		AND T0."RefDate"<=:edate
		AND T1."Account"='220202'
		GROUP BY T2."CardCode" ,T2."CardName";
		
		SELECT :FcCode AS "期间",T0."CardCode",T1."CardName",SUM("YW_OPDNAmt") AS "业务端计提"
		,SUM("OPDNAmt") AS "收退货金额"
		,SUM("OJDT_OPDNAmt") AS "分录计提金额"
		,IFNULL(SUM("YW_OPDNAmt"),0)-IFNULL(SUM("OPDNAmt"),0) AS "差异[业务端-收退货]"
		,IFNULL(SUM("YW_OPDNAmt"),0)-IFNULL(SUM("OJDT_OPDNAmt"),0) AS "差异[业务端计提-分录计提金额]"
		,SUM("YW_OPCHAmt") AS "业务端冲回"
		,SUM("OJDT_OPCHAmt") AS "分录暂估冲回"
		,IFNULL(SUM("YW_OPCHAmt"),0)-IFNULL(SUM("OJDT_OPCHAmt"),0) AS "差异[业务端冲回-分录暂估冲回]"
		FROM
			(
				SELECT 1 AS "ID",T0."CardCode",T0."CardName"
				,SUM(CASE WHEN T2."ItemCode"='X0510001' OR T2."InvntItem"='Y' THEN T0."Amt" ELSE 0 END) AS "YW_OPDNAmt"
				,0 AS "YW_OPCHAmt"
				,0 AS "OPDNAmt",0 AS "OJDT_OPDNAmt",0 AS "OJDT_OPCHAmt"
				FROM :TMP T0 
				JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
				LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
						) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
				LEFT JOIN OACT T4 ON T4."AcctCode"=CASE WHEN T0."Type"='委外费用' THEN '140802' ELSE T3."StockAct" END
				WHERE T0."ObjType" IN (20,21)
				GROUP BY T0."CardCode",T0."CardName"
				
				UNION ALL
				SELECT 4 AS "ID",T0."CardCode",T0."CardName"
				,0.00 AS "YW_OPDNAmt",SUM(CASE WHEN T2."ItemCode"='X0510001' OR T2."InvntItem"='Y' THEN T0."Amt" ELSE 0 END) AS "YW_OPCHAmt"
				,0,0 AS "OJDT_PDAAmt",0 AS "OJDT_OPCHAmt"
				FROM :TMP T0 
				JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
				LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
				WHERE T0."ObjType" IN (18,19)
				GROUP BY T0."CardCode",T0."CardName"
				
				UNION ALL
				SELECT 2 AS "ID",T0."供应商编码",T0."供应商名称"
				,0,0,SUM("计入暂估") AS "计入暂估",0,0
				FROM :OPDN_SUM T0 GROUP BY T0."供应商编码",T0."供应商名称"
				
				UNION ALL
				SELECT 3 AS "ID",T0."CardCode",T0."CardName"
				,0,0,0,-1*SUM("OJDT_OPDNAmt"),SUM("OJDT_OPCHAmt")
				FROM :OJDT_Amt T0
				GROUP BY T0."CardCode",T0."CardName"
			) T0
		JOIN OCRD T1 ON T0."CardCode"=T1."CardCode"
		GROUP BY T0."CardCode",T1."CardName"
		ORDER BY T0."CardCode"
		;
			
		
		/*
		SELECT '当月应付暂估计提' AS "Memo",T0."Type",NULL AS "CardCode",NULL AS "CardName",T0."ObjType"
		,T4."AcctCode",T4."AcctName"
		,SUM(T0."Amt") AS "Debit",0.00 AS "Credit"
		FROM :TMP T0 
		JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
		LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
				) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
		LEFT JOIN OACT T4 ON T4."AcctCode"=CASE WHEN T0."Type"='委外费用' THEN '140802' ELSE T3."StockAct" END
		WHERE T0."ObjType" IN (20,21)
		GROUP BY T0."Type",T0."ObjType",T4."AcctCode",T4."AcctName"
		
		UNION ALL
		SELECT '当月应付暂估计提' AS "Memo",T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
		,T4."AcctCode",T4."AcctName",0.00
		,SUM(T0."Amt") AS "Credit"
		FROM :TMP T0 
		LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
		WHERE T0."ObjType" IN (20,21)
		GROUP BY T0."Type",T0."CardCode",T0."CardName",T0."ObjType",T4."AcctCode",T4."AcctName"
		
		UNION ALL
		SELECT '当月冲销应付暂估' AS "Memo",T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
		,T4."AcctCode",T4."AcctName",0.00
		,SUM(T0."Amt") AS "Amt"
		FROM :TMP T0 
		LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
		WHERE T0."ObjType" IN (18,19)
		GROUP BY T0."Type",T0."ObjType",T4."AcctCode",T4."AcctName",T0."CardCode",T0."CardName"
		
		;*/
		
	ELSEIF :STYPE = 'Detail' THEN
		
			SELECT T0."Type" AS "类型"
			,CASE WHEN T0."ObjType"='20' THEN '采购收货' WHEN T0."ObjType"='21' THEN '采购退货'
				 WHEN T0."ObjType"='18' THEN '应付发票' WHEN T0."ObjType"='19' THEN '应付贷项凭证' END AS "单据类型"
			,T0."CardCode" AS "供应商编码",T0."CardName" AS "供应商名称",T0."DocDate" AS "过账日期"
			,T0."OPOROldSN" AS "采购订单OldSN",T0."OPDNOldSN" AS "采购收货OldSN"
			,T0."ItemCode" AS "物料编码",T1."ItemName" AS "物料名称",T0."U_ItemCode" AS "委外物料编码"
			,T0."Qty" AS "数量"
			,T0."Price" AS "未税单价"
			,CASE WHEN T1."ItemCode"='X0510001' OR T1."InvntItem"='Y' THEN T0."Amt" ELSE 0 END AS "未税金额(计入暂估)"
			,T0."LineTotal" AS "参考未税金额"
			,T0."GTotal" AS "参考含税金额"
			,T0."CalObjType",T0."CalDocEntry",T0."CalDocNum",T0."CalLineNum"
			,T0."ObjType",T0."DocEntry",T0."DocNum",T0."LineNum"
			,T3."StockAct"
			FROM :TMP T0
			LEFT JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
			LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
					) T3 ON T1."ItmsGrpCod"=T3."ItmsGrpCod"
			;
	
	ELSEIF :STYPE = 'ToOJDT' THEN 
		
		
		--PUR1 '当月应付暂估计提(材料)'
		IF :CalType = 'PUR1' THEN
			TMP_CL_JT=
			SELECT :FcCode AS "FcCode",1 AS "ID",T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo",T0."Type",NULL AS "CardCode",NULL AS "CardName",T0."ObjType"
			,T4."AcctCode",T4."AcctName"
			,SUM(T0."Amt") AS "Debit",0.00 AS "Credit"
			FROM :TMP T0 
			JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
					) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
			LEFT JOIN OACT T4 ON T4."AcctCode"=CASE WHEN T0."Type"='委外费用' THEN '140802' ELSE T3."StockAct" END
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR1'
			WHERE T0."ObjType" IN (20,21)
			AND T0."Type"='材料'
			AND T2."InvntItem"='Y'
			GROUP BY T0."Type",T0."ObjType",T4."AcctCode",T4."AcctName",T11."TrnsCode",T11."TrnsCodDsc"
			
			UNION ALL
			SELECT :FcCode AS "FcCode",2 AS "ID",T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo",T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
			,T4."AcctCode",T4."AcctName",0.00
			,SUM(T0."Amt") AS "Credit"
			FROM :TMP T0 
			JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR1'
			WHERE T0."ObjType" IN (20,21)
			AND T0."Type"='材料'
			AND T2."InvntItem"='Y'
			GROUP BY T0."Type",T0."CardCode",T0."CardName",T0."ObjType",T4."AcctCode",T4."AcctName",T11."TrnsCode",T11."TrnsCodDsc"
			ORDER BY "ID","ObjType","AcctCode","CardCode"
			;
			
			IF :IsOJDT = 'N' THEN
				SELECT T0."FcCode",T0."ID",T0."TransCode",T0."TransName",T0."Memo",T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
				,T0."AcctCode",T0."AcctName",T0."Debit",T0."Credit"
				FROM :TMP_CL_JT T0
				ORDER BY T0."ID",T0."ObjType",T0."AcctCode",T0."CardCode";
			ELSEIF :IsOJDT = 'Y' THEN
			
				IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
			  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
			  		RETURN;
			  	END IF;
			  	
				TransCode := 'PUR1'; --材料计提
				SELECT IFNULL(MAX("DocEntry"),0) INTO MAXEntry FROM "@MTC_COST_OJDT";
				DELETE FROM "@MTC_COST_OJDT" WHERE "U_FcCode"=:FcCode AND "U_TransCode"=:TransCode;
				DELETE FROM "@MTC_COST_OJDT1" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
				DELETE FROM "@MTC_COST_OJDT2" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
				
				INSERT INTO "@MTC_COST_OJDT"("DocEntry","DocNum","Object","Canceled","U_RefDate","U_FcCode"
				,"U_TransCode","U_Memo","U_IsRev","U_RevDate")
				SELECT TOP 1 :MAXEntry+1 AS "DocEntry",:MAXEntry+1 AS "DocNum",'MTC_COST_OJDT','N',:edate,:FcCode
					,T0."TransCode",T0."Memo",'N',NULL
					FROM :TMP_CL_JT T0;
				
				INSERT INTO "@MTC_COST_OJDT1"(
					"DocEntry","LineId","U_LineMemo"
					,"U_AcctCode","U_AcctName","U_VendorCode","U_VendorName","U_CardCode","U_CardName","U_FCCurrency"
					,"U_FCDebit","U_FCCredit","U_Debit","U_Credit"
					)
				SELECT :MAXEntry+1 AS "DocEntry"
					,ROW_NUMBER() OVER (PARTITION BY "TransCode" ORDER BY T0."ID",T0."ObjType",T0."AcctCode",T0."CardCode") AS "LineId","Memo"
					,T0."AcctCode",T0."AcctName",T0."CardCode",T0."CardName",NULL,NULL,'RMB' AS "FCCurrency"
					,0.00 AS "FCDebit",0.00 AS "FCCredit",ROUND(T0."Debit",2),ROUND(T0."Credit",2)
					FROM :TMP_CL_JT T0 
					WHERE 1=1
					AND (ABS(IFNULL(ROUND(T0."Debit",2),0))+ABS(IFNULL(ROUND(T0."Credit",2),0)))<>0
				;
				
				INSERT INTO "@MTC_COST_OJDT2"(
					"DocEntry","LineId","VisOrder",
					"Object","LogInst","U_Type",
					"U_ObjType","U_DocEntry","U_DocNum","U_LineNum",
					"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
					"U_ItemCode","U_ItemName","U_Quantity",
					"U_CardCode","U_CardName","U_AcctCode","U_AcctName",
					"U_Price","U_LineTotal","U_PriceAfVAT","U_GTotal",
					"U_Debit","U_Credit","U_Point"
					)
				SELECT :MAXEntry+1 AS "DocEntry"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "LineId"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "VisOrder"
				,'MTC_COST_OJDT' AS "Object",NULL AS "LogInst",P0."U_Type"
				,P0."ObjType",P0."DocEntry",P0."DocNum",P0."LineNum"
				,P0."CalObjType" AS "U_BaseType",P0."CalDocEntry" AS "U_BaseEntry",P0."CalDocNum" AS "U_BaseRef",P0."CalLineNum" AS "U_BaseLine"
				,P0."U_ItemCode",P0."U_ItemName",P0."U_Quantity"
				,P0."U_CardCode",P0."U_CardName",P0."U_AcctCode",P0."U_AcctName"
				,P0."U_Price",P0."U_LineTotal",P0."U_PriceAfVAT",P0."U_GTotal"
				,P0."U_Debit",P0."U_Credit",P0."U_Point"
				
				FROM (
						SELECT T11."TrnsCodDsc" AS "U_Type",NULL AS "U_CardCode",NULL AS "U_CardName"
						,T0."ObjType",T0."DocEntry",T0."DocNum",T0."LineNum"
						,T0."CalObjType",T0."CalDocEntry",T0."CalDocNum",T0."CalLineNum"
						,T2."ItemCode" AS "U_ItemCode",T2."ItemName" AS "U_ItemName"
						,T0."Qty" AS "U_Quantity",T0."Price" AS "U_Price",T0."Amt" AS "U_LineTotal",0 AS "U_PriceAfVAT",T0."GTotal" AS "U_GTotal"
						,T4."AcctCode" AS "U_AcctCode",T4."AcctName" AS "U_AcctName"
						,T0."Amt" AS "U_Debit",0.00 AS "U_Credit",'D' AS "U_Point"
						FROM :TMP T0 
						JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
						LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
								) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
						LEFT JOIN OACT T4 ON T4."AcctCode"=CASE WHEN T0."Type"='委外费用' THEN '140802' ELSE T3."StockAct" END
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR1'
						WHERE T0."ObjType" IN (20,21)
						AND T0."Type"='材料'
						AND T2."InvntItem"='Y'
						
						UNION ALL
						SELECT T11."TrnsCodDsc" AS "U_Type",NULL AS "CardCode",NULL AS "CardName"
						,T0."ObjType",T0."DocEntry",T0."DocNum",T0."LineNum"
						,T0."CalObjType",T0."CalDocEntry",T0."CalDocNum",T0."CalLineNum"
						,T2."ItemCode",T2."ItemName"
						,T0."Qty" AS "U_Quantity",T0."Price" AS "U_Price",T0."Amt" AS "U_LineTotal",0 AS "U_PriceAfVAT",T0."GTotal" AS "U_GTotal"
						,T4."AcctCode",T4."AcctName"
						,0.00 AS "U_Debit",T0."Amt" AS "U_Credit",'C' AS "U_Point"
						FROM :TMP T0 
						JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
						LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR1'
						WHERE T0."ObjType" IN (20,21)
						AND T0."Type"='材料'
						AND T2."InvntItem"='Y'
				) P0
			;
				
				SELECT 'Y' AS "flag",T0."DocEntry",T1."LineId",TO_VARCHAR(T0."U_RefDate",'YYYYMMDD') AS "RefDate"
					,T0."U_TransCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName",T0."U_Memo" AS "Memo"
					,T1."U_AcctCode" AS "AcctCode",T1."U_AcctName" AS "AcctName"
					,T1."U_VendorCode",T1."U_VendorName"
					,T1."U_FCCurrency" AS "FCCurrency"
					,T1."U_FCDebit" AS "FCDebit",T1."U_FCCredit" AS "FCCredit",T1."U_Debit" AS "Debit",T1."U_Credit" AS "Credit"
					,T0."U_IsRev" AS "IsRev"		--是否需要冲销
					,TO_VARCHAR(T0."U_RevDate",'YYYYMMDD') AS "RevDate"
					,T1."U_CardCode" AS "U_CardCode"
					,T1."U_CardName" AS "U_CardName"
				FROM "@MTC_COST_OJDT" T0
				JOIN "@MTC_COST_OJDT1" T1 ON T0."DocEntry"=T1."DocEntry"
				LEFT JOIN OTRC T11 ON T0."U_TransCode"=T11."TrnsCode"
				WHERE T0."U_FcCode"=:FcCode AND T0."U_TransCode"=:TransCode
				AND (ABS(IFNULL(T1."U_Debit",0))+ABS(IFNULL(T1."U_Credit",0))+ABS(IFNULL(T1."U_FCDebit",0))+ABS(IFNULL(T1."U_FCCredit",0)))<>0
				;
			END IF;
			
		--PUR4 委外费用的计提
		ELSEIF :CalType = 'PUR4' THEN 
			TMP_WWExp_JT=
			SELECT :FcCode AS "FcCode",1 AS "ID",T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo",T0."Type",NULL AS "CardCode",NULL AS "CardName",T0."ObjType"
			,T4."AcctCode",T4."AcctName"
			,SUM(T0."Amt") AS "Debit",0.00 AS "Credit"
			FROM :TMP T0 
			JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
					) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
			LEFT JOIN OACT T4 ON T4."AcctCode"=CASE WHEN T0."Type"='委外费用' THEN '140802' ELSE T3."StockAct" END
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR4'
			WHERE T0."ObjType" IN (20,21)
			AND T0."Type"='委外费用'
			AND T2."InvntItem"='N'
			GROUP BY T0."Type",T0."ObjType",T4."AcctCode",T4."AcctName",T11."TrnsCode",T11."TrnsCodDsc"
			
			UNION ALL
			SELECT :FcCode AS "FcCode",2 AS "ID",T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo",T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
			,T4."AcctCode",T4."AcctName",0.00
			,SUM(T0."Amt") AS "Credit"
			FROM :TMP T0 
			JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR4'
			WHERE T0."ObjType" IN (20,21)
			AND T0."Type"='委外费用'
			AND T2."InvntItem"='N'
			GROUP BY T0."Type",T0."CardCode",T0."CardName",T0."ObjType",T4."AcctCode",T4."AcctName",T11."TrnsCode",T11."TrnsCodDsc"
			ORDER BY "ID","ObjType","AcctCode","CardCode"
			;
			
			IF :IsOJDT = 'N' THEN
				SELECT T0."FcCode",T0."ID",T0."TransCode",T0."TransName",T0."Memo",T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
				,T0."AcctCode",T0."AcctName",T0."Debit",T0."Credit"
				FROM :TMP_CL_JT T0
				ORDER BY T0."ID",T0."ObjType",T0."AcctCode",T0."CardCode";
			ELSEIF :IsOJDT = 'Y' THEN
				IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
			  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
			  		RETURN;
			  	END IF;
			  	
				TransCode := 'PUR4'; --委外费用计提
				SELECT IFNULL(MAX("DocEntry"),0) INTO MAXEntry FROM "@MTC_COST_OJDT";
				DELETE FROM "@MTC_COST_OJDT" WHERE "U_FcCode"=:FcCode AND "U_TransCode"=:TransCode;
				DELETE FROM "@MTC_COST_OJDT1" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
				DELETE FROM "@MTC_COST_OJDT2" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
				
				INSERT INTO "@MTC_COST_OJDT"("DocEntry","DocNum","Object","Canceled","U_RefDate","U_FcCode"
				,"U_TransCode","U_Memo","U_IsRev","U_RevDate")
				SELECT TOP 1 :MAXEntry+1 AS "DocEntry",:MAXEntry+1 AS "DocNum",'MTC_COST_OJDT','N',:edate,:FcCode
					,T0."TransCode",T0."Memo",'N',NULL
					FROM :TMP_WWExp_JT T0;
				
				INSERT INTO "@MTC_COST_OJDT1"(
					"DocEntry","LineId","U_LineMemo"
					,"U_AcctCode","U_AcctName","U_VendorCode","U_VendorName","U_CardCode","U_CardName","U_FCCurrency"
					,"U_FCDebit","U_FCCredit","U_Debit","U_Credit"
					)
				SELECT :MAXEntry+1 AS "DocEntry"
					,ROW_NUMBER() OVER (PARTITION BY "TransCode" ORDER BY T0."ID",T0."ObjType",T0."AcctCode",T0."CardCode") AS "LineId","Memo"
					,T0."AcctCode",T0."AcctName",T0."CardCode",T0."CardName",NULL,NULL,'RMB' AS "FCCurrency"
					,0.00 AS "FCDebit",0.00 AS "FCCredit",ROUND(T0."Debit",2),ROUND(T0."Credit",2)
					FROM :TMP_WWExp_JT T0 
					WHERE 1=1
					AND (ABS(IFNULL(ROUND(T0."Debit",2),0))+ABS(IFNULL(ROUND(T0."Credit",2),0)))<>0
				;
				
				INSERT INTO "@MTC_COST_OJDT2"(
					"DocEntry","LineId","VisOrder",
					"Object","LogInst","U_Type",
					"U_ObjType","U_DocEntry","U_DocNum","U_LineNum",
					"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
					"U_ItemCode","U_ItemName","U_Quantity",
					"U_CardCode","U_CardName","U_AcctCode","U_AcctName",
					"U_Price","U_LineTotal","U_PriceAfVAT","U_GTotal",
					"U_Debit","U_Credit","U_Point"
					)
				SELECT :MAXEntry+1 AS "DocEntry"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "LineId"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "VisOrder"
				,'MTC_COST_OJDT' AS "Object",NULL AS "LogInst",P0."U_Type"
				,P0."ObjType",P0."DocEntry",P0."DocNum",P0."LineNum"
				,P0."CalObjType" AS "U_BaseType",P0."CalDocEntry" AS "U_BaseEntry",P0."CalDocNum" AS "U_BaseRef",P0."CalLineNum" AS "U_BaseLine"
				,P0."U_ItemCode",P0."U_ItemName",P0."U_Quantity"
				,P0."U_CardCode",P0."U_CardName",P0."U_AcctCode",P0."U_AcctName"
				,P0."U_Price",P0."U_LineTotal",P0."U_PriceAfVAT",P0."U_GTotal"
				,P0."U_Debit",P0."U_Credit",P0."U_Point"
				
				FROM (
				
						SELECT T11."TrnsCodDsc" AS "U_Type",NULL AS "U_CardCode",NULL AS "U_CardName"
						,T0."ObjType",T0."DocEntry",T0."DocNum",T0."LineNum"
						,T0."CalObjType",T0."CalDocEntry",T0."CalDocNum",T0."CalLineNum"
						,T2."ItemCode" AS "U_ItemCode",T2."ItemName" AS "U_ItemName"
						,T0."Qty" AS "U_Quantity",T0."Price" AS "U_Price",T0."Amt" AS "U_LineTotal",0 AS "U_PriceAfVAT",T0."GTotal" AS "U_GTotal"
						,T4."AcctCode" AS "U_AcctCode",T4."AcctName" AS "U_AcctName"
						,T0."Amt" AS "U_Debit",0.00 AS "U_Credit",'D' AS "U_Point"
						FROM :TMP T0 
						JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
						LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
								) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
						LEFT JOIN OACT T4 ON T4."AcctCode"=CASE WHEN T0."Type"='委外费用' THEN '140802' ELSE T3."StockAct" END
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR4'
						WHERE T0."ObjType" IN (20,21)
						AND T0."Type"='委外费用'
						AND T2."InvntItem"='N'
						
						UNION ALL
						SELECT T11."TrnsCodDsc" AS "U_Type",NULL AS "CardCode",NULL AS "CardName"
						,T0."ObjType",T0."DocEntry",T0."DocNum",T0."LineNum"
						,T0."CalObjType",T0."CalDocEntry",T0."CalDocNum",T0."CalLineNum"
						,T2."ItemCode",T2."ItemName"
						,T0."Qty" AS "U_Quantity",T0."Price" AS "U_Price",T0."Amt" AS "U_LineTotal",0 AS "U_PriceAfVAT",T0."GTotal" AS "U_GTotal"
						,T4."AcctCode",T4."AcctName"
						,0.00 AS "U_Debit",T0."Amt" AS "U_Credit",'C' AS "U_Point"
						FROM :TMP T0 
						JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
						LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR4'
						WHERE T0."ObjType" IN (20,21)
						AND T0."Type"='委外费用'
						AND T2."InvntItem"='N'
				) P0
			;
				
				SELECT 'Y' AS "flag",T0."DocEntry",T1."LineId",TO_VARCHAR(T0."U_RefDate",'YYYYMMDD') AS "RefDate"
					,T0."U_TransCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName",T0."U_Memo" AS "Memo"
					,T1."U_AcctCode" AS "AcctCode",T1."U_AcctName" AS "AcctName"
					,T1."U_VendorCode",T1."U_VendorName"
					,T1."U_FCCurrency" AS "FCCurrency"
					,T1."U_FCDebit" AS "FCDebit",T1."U_FCCredit" AS "FCCredit",T1."U_Debit" AS "Debit",T1."U_Credit" AS "Credit"
					,T0."U_IsRev" AS "IsRev"		--是否需要冲销
					,TO_VARCHAR(T0."U_RevDate",'YYYYMMDD') AS "RevDate"
					,T1."U_CardCode" AS "U_CardCode"
					,T1."U_CardName" AS "U_CardName"
				FROM "@MTC_COST_OJDT" T0
				JOIN "@MTC_COST_OJDT1" T1 ON T0."DocEntry"=T1."DocEntry"
				LEFT JOIN OTRC T11 ON T0."U_TransCode"=T11."TrnsCode"
				WHERE T0."U_FcCode"=:FcCode AND T0."U_TransCode"=:TransCode
				AND (ABS(IFNULL(T1."U_Debit",0))+ABS(IFNULL(T1."U_Credit",0))+ABS(IFNULL(T1."U_FCDebit",0))+ABS(IFNULL(T1."U_FCCredit",0)))<>0
				;
			END IF;
		
		--PUR5 系统自带生成的采购收货和采购退货的分录冲销 取OJDT
		ELSEIF :CalType = 'PUR5' THEN 
			--冲销系统分录
			TMP_CL_CXOJDT=
			SELECT :FcCode AS "FcCode",T2."AcctCode",T2."AcctName",T0."TransType",T7."DocName"
			,T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo"
			,-1*SUM(T1."Debit") AS "Debit"
			,-1*SUM(T1."Credit") AS "Credit"
			FROM "OJDT" T0
			JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
			JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
			LEFT JOIN "MTC_DocType" T7 ON T0."TransType" = T7."ObjType"
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR5'
			WHERE 1=1
			AND T0."TransType" IN ('20','21')
			AND (T0."RefDate" >= :sdate )
			AND (T0."RefDate" <= :edate)
			GROUP BY T2."AcctCode",T2."AcctName",T0."TransType",T7."DocName",T11."TrnsCode",T11."TrnsCodDsc"
			ORDER BY T2."AcctCode",T0."TransType";
			
			IF :IsOJDT = 'N' THEN
				SELECT T0."FcCode",T0."TransCode",T0."TransName",T0."Memo"
				,T0."AcctCode",T0."AcctName",T0."Debit",T0."Credit"
				FROM :TMP_CL_CXOJDT T0
				ORDER BY T0."AcctCode";
			ELSEIF :IsOJDT = 'Y' THEN
				IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
			  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
			  		RETURN;
			  	END IF;
			  	
				TransCode := 'PUR5'; --委外费用计提
				SELECT IFNULL(MAX("DocEntry"),0) INTO MAXEntry FROM "@MTC_COST_OJDT";
				DELETE FROM "@MTC_COST_OJDT" WHERE "U_FcCode"=:FcCode AND "U_TransCode"=:TransCode;
				DELETE FROM "@MTC_COST_OJDT1" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
				DELETE FROM "@MTC_COST_OJDT2" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
				
				INSERT INTO "@MTC_COST_OJDT"("DocEntry","DocNum","Object","Canceled","U_RefDate","U_FcCode"
				,"U_TransCode","U_Memo","U_IsRev","U_RevDate")
				SELECT TOP 1 :MAXEntry+1 AS "DocEntry",:MAXEntry+1 AS "DocNum",'MTC_COST_OJDT','N',:edate,:FcCode
					,T0."TransCode",T0."Memo",'N',NULL
					FROM :TMP_CL_CXOJDT T0;
				
				INSERT INTO "@MTC_COST_OJDT1"(
					"DocEntry","LineId","U_LineMemo"
					,"U_AcctCode","U_AcctName","U_FCCurrency"
					,"U_FCDebit","U_FCCredit","U_Debit","U_Credit"
					)
				SELECT :MAXEntry+1 AS "DocEntry"
					,ROW_NUMBER() OVER (PARTITION BY "TransCode" ORDER BY T0."AcctCode") AS "LineId","Memo"
					,T0."AcctCode",T0."AcctName",'RMB' AS "FCCurrency"
					,0.00 AS "FCDebit",0.00 AS "FCCredit",ROUND(T0."Debit",2),ROUND(T0."Credit",2)
					FROM :TMP_CL_CXOJDT T0 
					WHERE 1=1
					AND (ABS(IFNULL(ROUND(T0."Debit",2),0))+ABS(IFNULL(ROUND(T0."Credit",2),0)))<>0
				;
				
				INSERT INTO "@MTC_COST_OJDT2"(
					"DocEntry","LineId","VisOrder",
					"Object","LogInst","U_Type",
					"U_ObjType","U_DocEntry","U_DocNum","U_LineNum",
					"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
					"U_ItemCode","U_ItemName","U_Quantity",
					"U_CardCode","U_CardName","U_AcctCode","U_AcctName",
					"U_Price","U_LineTotal","U_PriceAfVAT","U_GTotal",
					"U_Debit","U_Credit","U_Point"
					)
				SELECT :MAXEntry+1 AS "DocEntry"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "LineId"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "VisOrder"
				,'MTC_COST_OJDT' AS "Object",NULL AS "LogInst",P0."U_Type"
				,P0."ObjType",P0."DocEntry",P0."DocNum",P0."LineNum"
				,P0."CalObjType" AS "U_BaseType",P0."CalDocEntry" AS "U_BaseEntry",P0."CalDocNum" AS "U_BaseRef",P0."CalLineNum" AS "U_BaseLine"
				,P0."U_ItemCode",P0."U_ItemName",P0."U_Quantity"
				,P0."U_CardCode",P0."U_CardName",P0."U_AcctCode",P0."U_AcctName"
				,P0."U_Price",P0."U_LineTotal",P0."U_PriceAfVAT",P0."U_GTotal"
				,P0."U_Debit",P0."U_Credit",P0."U_Point"
				
				FROM (
						SELECT T11."TrnsCodDsc" AS "U_Type",NULL AS "U_CardCode",NULL AS "U_CardName"
						,'30' AS "ObjType",T0."TransId" AS "DocEntry",T0."TransId" AS "DocNum",T1."Line_ID" AS "LineNum"
						,NULL AS"CalObjType",NULL AS "CalDocEntry",NULL AS "CalDocNum",NULL AS"CalLineNum"
						,NULL AS "U_ItemCode",NULL AS "U_ItemName"
						,0 AS "U_Quantity",0 AS "U_Price",0 AS "U_LineTotal",0 AS "U_PriceAfVAT",T1."Debit"-T1."Credit" AS "U_GTotal"
						,T2."AcctCode" AS "U_AcctCode",T2."AcctName" AS "U_AcctName"
						,T1."Debit" AS "U_Debit",T1."Credit" AS "U_Credit",CASE WHEN T1."Debit"<>0 THEN 'D' ELSE 'C' END AS "U_Point"
						
						FROM "OJDT" T0
						JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
						JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
						LEFT JOIN "MTC_DocType" T7 ON T0."TransType" = T7."ObjType"
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR5'
						WHERE 1=1
						AND T0."TransType" IN ('20','21')
						AND (T0."RefDate" >= :sdate )
						AND (T0."RefDate" <= :edate)
				) P0
			;
				
				SELECT 'Y' AS "flag",T0."DocEntry",T1."LineId",TO_VARCHAR(T0."U_RefDate",'YYYYMMDD') AS "RefDate"
					,T0."U_TransCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName",T0."U_Memo" AS "Memo"
					,T1."U_AcctCode" AS "AcctCode",T1."U_AcctName" AS "AcctName"
					,T1."U_VendorCode",T1."U_VendorName"
					,T1."U_FCCurrency" AS "FCCurrency"
					,T1."U_FCDebit" AS "FCDebit",T1."U_FCCredit" AS "FCCredit",T1."U_Debit" AS "Debit",T1."U_Credit" AS "Credit"
					,T0."U_IsRev" AS "IsRev"		--是否需要冲销
					,TO_VARCHAR(T0."U_RevDate",'YYYYMMDD') AS "RevDate"
					,T1."U_CardCode" AS "U_CardCode"
					,T1."U_CardName" AS "U_CardName"
				FROM "@MTC_COST_OJDT" T0
				JOIN "@MTC_COST_OJDT1" T1 ON T0."DocEntry"=T1."DocEntry"
				LEFT JOIN OTRC T11 ON T0."U_TransCode"=T11."TrnsCode"
				WHERE T0."U_FcCode"=:FcCode AND T0."U_TransCode"=:TransCode
				AND (ABS(IFNULL(T1."U_Debit",0))+ABS(IFNULL(T1."U_Credit",0))+ABS(IFNULL(T1."U_FCDebit",0))+ABS(IFNULL(T1."U_FCCredit",0)))<>0
				;
			END IF;
		ELSEIF :CalType = 'PUR2' THEN
			TMP_CL_OPCH=
			SELECT :FcCode AS "FcCode",11 AS "ID"
			,T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo"
			,'冲销系统应付发票' AS "LineMemo"
			,'材料' AS "Type",NULL AS "CardCode",NULL AS "CardName",T0."TransType" AS "ObjType"
			,T2."AcctCode",T2."AcctName"
			,-1*SUM(T1."Debit") AS "Debit"
			,-1*SUM(T1."Credit") AS "Credit"
			FROM "OJDT" T0
			JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
			JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR2'
			WHERE 1=1
			AND T0."TransType" IN ('18','19')
			AND (T0."RefDate" >= :sdate )
			AND (T0."RefDate" <= :edate)
			AND (LEFT(T2."AcctCode",4) IN ('1403','1405','1409') OR T2."AcctCode"='220202')
			GROUP BY T2."AcctCode",T2."AcctName",T0."TransType",T11."TrnsCode",T11."TrnsCodDsc"
			
			UNION ALL
			
			SELECT :FcCode AS "FcCode",21 AS "ID",T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo"
			,'发票库存影响差异' AS "LineMemo"
			,T0."Type",NULL AS "CardCode",NULL AS "CardName",T0."ObjType"
			,T4."AcctCode",T4."AcctName"
			,SUM(T0."Amt"-T0."LineTotal") AS "Debit",0.00 AS "Credit"
			FROM :TMP T0 
			JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
					) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
			LEFT JOIN OACT T4 ON T4."AcctCode"=CASE WHEN T0."Type"='委外费用' THEN '140802' ELSE T3."StockAct" END
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR2'
			WHERE T0."ObjType" IN (18,19)
			AND T0."Type"='材料'
			AND T2."InvntItem"='Y'
			GROUP BY T0."Type",T0."ObjType",T4."AcctCode",T4."AcctName",T11."TrnsCode",T11."TrnsCodDsc"
			
			UNION ALL
			SELECT :FcCode AS "FcCode",31 AS "ID",T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo"
			,'当月发票冲回暂估' AS "LineMemo"
			,T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
			,T4."AcctCode",T4."AcctName"
			,-1*SUM(T0."Amt") AS "Debit",0.00
			FROM :TMP T0 
			JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR2'
			WHERE T0."ObjType" IN (18,19)
			AND T0."Type"='材料'
			AND T2."InvntItem"='Y'
			GROUP BY T0."Type",T0."CardCode",T0."CardName",T0."ObjType",T4."AcctCode",T4."AcctName",T11."TrnsCode",T11."TrnsCodDsc"
			ORDER BY "ID","ObjType","AcctCode","CardCode"
			;
			
			IF :IsOJDT = 'N' THEN
				SELECT T0."FcCode",T0."ID",T0."TransCode",T0."TransName",T0."Memo",T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
				,T0."AcctCode",T0."AcctName",T0."Debit",T0."Credit"
				FROM :TMP_CL_OPCH T0
				ORDER BY T0."ID",T0."ObjType",T0."AcctCode",T0."CardCode";
			ELSEIF :IsOJDT = 'Y' THEN
				TransCode := 'PUR2'; --材料计提
				SELECT IFNULL(MAX("DocEntry"),0) INTO MAXEntry FROM "@MTC_COST_OJDT";
				DELETE FROM "@MTC_COST_OJDT" WHERE "U_FcCode"=:FcCode AND "U_TransCode"=:TransCode;
				DELETE FROM "@MTC_COST_OJDT1" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
				DELETE FROM "@MTC_COST_OJDT2" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
				
				INSERT INTO "@MTC_COST_OJDT"("DocEntry","DocNum","Object","Canceled","U_RefDate","U_FcCode"
				,"U_TransCode","U_Memo","U_IsRev","U_RevDate")
				SELECT TOP 1 :MAXEntry+1 AS "DocEntry",:MAXEntry+1 AS "DocNum",'MTC_COST_OJDT','N',:edate,:FcCode
					,T0."TransCode",T0."Memo",'N',NULL
					FROM :TMP_CL_OPCH T0;
				
				INSERT INTO "@MTC_COST_OJDT1"(
					"DocEntry","LineId","U_LineMemo"
					,"U_AcctCode","U_AcctName","U_VendorCode","U_VendorName","U_CardCode","U_CardName","U_FCCurrency"
					,"U_FCDebit","U_FCCredit","U_Debit","U_Credit"
					)
				SELECT :MAXEntry+1 AS "DocEntry"
					,ROW_NUMBER() OVER (PARTITION BY "TransCode" ORDER BY T0."ID",T0."ObjType",T0."AcctCode",T0."CardCode") AS "LineId","LineMemo"
					,T0."AcctCode",T0."AcctName",T0."CardCode",T0."CardName",NULL,NULL,'RMB' AS "FCCurrency"
					,0.00 AS "FCDebit",0.00 AS "FCCredit",ROUND(T0."Debit",2),ROUND(T0."Credit",2)
					FROM :TMP_CL_OPCH T0 
					WHERE 1=1
					AND (ABS(IFNULL(ROUND(T0."Debit",2),0))+ABS(IFNULL(ROUND(T0."Credit",2),0)))<>0
				;
				
				INSERT INTO "@MTC_COST_OJDT2"(
					"DocEntry","LineId","VisOrder",
					"Object","LogInst","U_Type",
					"U_ObjType","U_DocEntry","U_DocNum","U_LineNum",
					"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
					"U_ItemCode","U_ItemName","U_Quantity",
					"U_CardCode","U_CardName","U_AcctCode","U_AcctName",
					"U_Price","U_LineTotal","U_PriceAfVAT","U_GTotal",
					"U_Debit","U_Credit","U_Point"
					)
				SELECT :MAXEntry+1 AS "DocEntry"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "LineId"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "VisOrder"
				,'MTC_COST_OJDT' AS "Object",NULL AS "LogInst",P0."U_Type"
				,P0."ObjType",P0."DocEntry",P0."DocNum",P0."LineNum"
				,P0."CalObjType" AS "U_BaseType",P0."CalDocEntry" AS "U_BaseEntry",P0."CalDocNum" AS "U_BaseRef",P0."CalLineNum" AS "U_BaseLine"
				,P0."U_ItemCode",P0."U_ItemName",P0."U_Quantity"
				,P0."U_CardCode",P0."U_CardName",P0."U_AcctCode",P0."U_AcctName"
				,P0."U_Price",P0."U_LineTotal",P0."U_PriceAfVAT",P0."U_GTotal"
				,P0."U_Debit",P0."U_Credit",P0."U_Point"
				
				FROM (
						SELECT '冲销系统应付发票' AS "U_Type",NULL AS "U_CardCode",NULL AS "U_CardName"
						,'30' AS "ObjType",T0."TransId" AS "DocEntry",T0."TransId" AS "DocNum",T1."Line_ID" AS "LineNum"
						,NULL AS"CalObjType",NULL AS "CalDocEntry",NULL AS "CalDocNum",NULL AS"CalLineNum"
						,NULL AS "U_ItemCode",NULL AS "U_ItemName"
						,0 AS "U_Quantity",0 AS "U_Price",0 AS "U_LineTotal",0 AS "U_PriceAfVAT",T1."Debit"-T1."Credit" AS "U_GTotal"
						,T2."AcctCode" AS "U_AcctCode",T2."AcctName" AS "U_AcctName"
						,T1."Debit" AS "U_Debit",T1."Credit" AS "U_Credit",CASE WHEN T1."Debit"<>0 THEN 'D' ELSE 'C' END AS "U_Point"
						FROM "OJDT" T0
						JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
						JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR2'
						WHERE 1=1
						AND T0."TransType" IN ('18','19')
						AND (T0."RefDate" >= :sdate )
						AND (T0."RefDate" <= :edate)
						AND (LEFT(T2."AcctCode",4) IN ('1403','1405','1409') OR T2."AcctCode"='220202')
						
						UNION ALL
						
						SELECT '发票库存影响差异' AS "U_Type",NULL AS "U_CardCode",NULL AS "U_CardName"
						,T0."ObjType",T0."DocEntry",T0."DocNum",T0."LineNum"
						,T0."CalObjType",T0."CalDocEntry",T0."CalDocNum",T0."CalLineNum"
						,T2."ItemCode" AS "U_ItemCode",T2."ItemName" AS "U_ItemName"
						,T0."Qty" AS "U_Quantity",T0."Price" AS "U_Price",T0."Amt" AS "U_LineTotal",0 AS "U_PriceAfVAT",T0."GTotal" AS "U_GTotal"
						,T4."AcctCode" AS "U_AcctCode",T4."AcctName" AS "U_AcctName"
						,(T0."Amt"-T0."LineTotal") AS "Debit",0.00 AS "Credit",'D' AS "U_Point"
						FROM :TMP T0 
						JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
						LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
								) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
						LEFT JOIN OACT T4 ON T4."AcctCode"=CASE WHEN T0."Type"='委外费用' THEN '140802' ELSE T3."StockAct" END
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR2'
						WHERE T0."ObjType" IN (18,19)
						AND T0."Type"='材料'
						AND T2."InvntItem"='Y'
						
						UNION ALL
						SELECT '当月发票冲回暂估' AS "U_Type",T0."CardCode",T0."CardName"
						,T0."ObjType",T0."DocEntry",T0."DocNum",T0."LineNum"
						,T0."CalObjType",T0."CalDocEntry",T0."CalDocNum",T0."CalLineNum"
						,T2."ItemCode",T2."ItemName"
						,T0."Qty" AS "U_Quantity",T0."Price" AS "U_Price",T0."Amt" AS "U_LineTotal",0 AS "PriceAfVAT",T0."GTotal" AS "U_GTotal"
						,T4."AcctCode",T4."AcctName"
						,-1*(T0."Amt") AS "Debit",0.00,'D' AS "U_Point"
						FROM :TMP T0 
						JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
						LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR2'
						WHERE T0."ObjType" IN (18,19)
						AND T0."Type"='材料'
						AND T2."InvntItem"='Y'
				) P0
			;
				
				SELECT 'Y' AS "flag",T0."DocEntry",T1."LineId",TO_VARCHAR(T0."U_RefDate",'YYYYMMDD') AS "RefDate"
					,T0."U_TransCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName",T0."U_Memo" AS "Memo"
					,T1."U_LineMemo" AS "LineMemo"
					,T1."U_AcctCode" AS "AcctCode",T1."U_AcctName" AS "AcctName"
					,T1."U_VendorCode",T1."U_VendorName"
					,T1."U_FCCurrency" AS "FCCurrency"
					,T1."U_FCDebit" AS "FCDebit",T1."U_FCCredit" AS "FCCredit",T1."U_Debit" AS "Debit",T1."U_Credit" AS "Credit"
					,T0."U_IsRev" AS "IsRev"		--是否需要冲销
					,TO_VARCHAR(T0."U_RevDate",'YYYYMMDD') AS "RevDate"
					,T1."U_CardCode" AS "U_CardCode"
					,T1."U_CardName" AS "U_CardName"
				FROM "@MTC_COST_OJDT" T0
				JOIN "@MTC_COST_OJDT1" T1 ON T0."DocEntry"=T1."DocEntry"
				LEFT JOIN OTRC T11 ON T0."U_TransCode"=T11."TrnsCode"
				WHERE T0."U_FcCode"=:FcCode AND T0."U_TransCode"=:TransCode
				AND (ABS(IFNULL(T1."U_Debit",0))+ABS(IFNULL(T1."U_Credit",0))+ABS(IFNULL(T1."U_FCDebit",0))+ABS(IFNULL(T1."U_FCCredit",0)))<>0
				;
				
				
			END IF;
		
		ELSEIF :CalType = 'PUR3' THEN
			TMP_WWExp_OPCH=
			SELECT :FcCode AS "FcCode",11 AS "ID"
			,T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo"
			,'冲销系统应付发票' AS "LineMemo"
			,'材料' AS "Type",NULL AS "CardCode",NULL AS "CardName",T0."TransType" AS "ObjType"
			,T2."AcctCode",T2."AcctName"
			,-1*SUM(T1."Debit") AS "Debit"
			,-1*SUM(T1."Credit") AS "Credit"
			FROM "OJDT" T0
			JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
			JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR3'
			WHERE 1=1
			AND T0."TransType" IN ('18','19')
			AND (T0."RefDate" >= :sdate )
			AND (T0."RefDate" <= :edate)
			AND (T2."AcctCode"='140802')
			GROUP BY T2."AcctCode",T2."AcctName",T0."TransType",T11."TrnsCode",T11."TrnsCodDsc"
			
			UNION ALL
			
			SELECT :FcCode AS "FcCode",21 AS "ID",T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo"
			,'委外费用差异' AS "LineMemo"
			,T0."Type",NULL AS "CardCode",NULL AS "CardName",T0."ObjType"
			,T4."AcctCode",T4."AcctName"
			,0.00 AS "Debit",-1*SUM(T0."Amt"-T0."LineTotal") AS "Credit"
			FROM :TMP T0 
			JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
					) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
			LEFT JOIN OACT T4 ON T4."AcctCode"='140803'
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR3'
			WHERE T0."ObjType" IN (18,19)
			AND T0."Type"='委外费用'
			GROUP BY T0."Type",T0."ObjType",T4."AcctCode",T4."AcctName",T11."TrnsCode",T11."TrnsCodDsc"
			
			UNION ALL
			SELECT :FcCode AS "FcCode",31 AS "ID",T11."TrnsCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName"
			,T11."TrnsCodDsc"||','||:FcCode||'月' AS "Memo"
			,'当月发票冲回暂估' AS "LineMemo"
			,T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
			,T4."AcctCode",T4."AcctName"
			,-1*SUM(T0."Amt") AS "Debit",0.00
			FROM :TMP T0 
			JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
			LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
			LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR3'
			WHERE T0."ObjType" IN (18,19)
			AND T0."Type"='委外费用'
			GROUP BY T0."Type",T0."CardCode",T0."CardName",T0."ObjType",T4."AcctCode",T4."AcctName",T11."TrnsCode",T11."TrnsCodDsc"
			ORDER BY "ID","ObjType","AcctCode","CardCode"
			;
			
			IF :IsOJDT = 'N' THEN
				SELECT T0."FcCode",T0."ID",T0."TransCode",T0."TransName",T0."Memo",T0."Type",T0."CardCode",T0."CardName",T0."ObjType"
				,T0."AcctCode",T0."AcctName",T0."Debit",T0."Credit"
				FROM :TMP_WWExp_OPCH T0
				ORDER BY T0."ID",T0."ObjType",T0."AcctCode",T0."CardCode";
			ELSEIF :IsOJDT = 'Y' THEN
				TransCode := 'PUR3'; --材料计提
				SELECT IFNULL(MAX("DocEntry"),0) INTO MAXEntry FROM "@MTC_COST_OJDT";
				DELETE FROM "@MTC_COST_OJDT" WHERE "U_FcCode"=:FcCode AND "U_TransCode"=:TransCode;
				DELETE FROM "@MTC_COST_OJDT1" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
				DELETE FROM "@MTC_COST_OJDT2" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_OJDT");
				
				INSERT INTO "@MTC_COST_OJDT"("DocEntry","DocNum","Object","Canceled","U_RefDate","U_FcCode"
				,"U_TransCode","U_Memo","U_IsRev","U_RevDate")
				SELECT TOP 1 :MAXEntry+1 AS "DocEntry",:MAXEntry+1 AS "DocNum",'MTC_COST_OJDT','N',:edate,:FcCode
					,T0."TransCode",T0."Memo",'N',NULL
					FROM :TMP_WWExp_OPCH T0;
				
				INSERT INTO "@MTC_COST_OJDT1"(
					"DocEntry","LineId","U_LineMemo"
					,"U_AcctCode","U_AcctName","U_VendorCode","U_VendorName","U_CardCode","U_CardName","U_FCCurrency"
					,"U_FCDebit","U_FCCredit","U_Debit","U_Credit"
					)
				SELECT :MAXEntry+1 AS "DocEntry"
					,ROW_NUMBER() OVER (PARTITION BY "TransCode" ORDER BY T0."ID",T0."ObjType",T0."AcctCode",T0."CardCode") AS "LineId","LineMemo"
					,T0."AcctCode",T0."AcctName",T0."CardCode",T0."CardName",NULL,NULL,'RMB' AS "FCCurrency"
					,0.00 AS "FCDebit",0.00 AS "FCCredit",ROUND(T0."Debit",2),ROUND(T0."Credit",2)
					FROM :TMP_WWExp_OPCH T0 
					WHERE 1=1
					AND (ABS(IFNULL(ROUND(T0."Debit",2),0))+ABS(IFNULL(ROUND(T0."Credit",2),0)))<>0
				;
				
				INSERT INTO "@MTC_COST_OJDT2"(
					"DocEntry","LineId","VisOrder",
					"Object","LogInst","U_Type",
					"U_ObjType","U_DocEntry","U_DocNum","U_LineNum",
					"U_BaseType","U_BaseEntry","U_BaseRef","U_BaseLine",
					"U_ItemCode","U_ItemName","U_Quantity",
					"U_CardCode","U_CardName","U_AcctCode","U_AcctName",
					"U_Price","U_LineTotal","U_PriceAfVAT","U_GTotal",
					"U_Debit","U_Credit","U_Point"
					)
				SELECT :MAXEntry+1 AS "DocEntry"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "LineId"
				,ROW_NUMBER() OVER(ORDER BY P0."U_Type") AS "VisOrder"
				,'MTC_COST_OJDT' AS "Object",NULL AS "LogInst",P0."U_Type"
				,P0."ObjType",P0."DocEntry",P0."DocNum",P0."LineNum"
				,P0."CalObjType" AS "U_BaseType",P0."CalDocEntry" AS "U_BaseEntry",P0."CalDocNum" AS "U_BaseRef",P0."CalLineNum" AS "U_BaseLine"
				,P0."U_ItemCode",P0."U_ItemName",P0."U_Quantity"
				,P0."U_CardCode",P0."U_CardName",P0."U_AcctCode",P0."U_AcctName"
				,P0."U_Price",P0."U_LineTotal",P0."U_PriceAfVAT",P0."U_GTotal"
				,P0."U_Debit",P0."U_Credit",P0."U_Point"
				
				FROM (
						SELECT '冲销系统应付发票' AS "U_Type",NULL AS "U_CardCode",NULL AS "U_CardName"
						,'30' AS "ObjType",T0."TransId" AS "DocEntry",T0."TransId" AS "DocNum",T1."Line_ID" AS "LineNum"
						,NULL AS "CalObjType",NULL AS "CalDocEntry",NULL AS "CalDocNum",NULL AS "CalLineNum"						
						,NULL AS "U_ItemCode",NULL AS "U_ItemName"
						,0 AS "U_Quantity",0 AS "U_Price",0 AS "U_LineTotal",0 AS "U_PriceAfVAT",-1*T1."Debit"+T1."Credit" AS "U_GTotal"
						,T2."AcctCode" AS "U_AcctCode",T2."AcctName" AS "U_AcctName"
						,-1*(T1."Debit") AS "U_Debit",-1*(T1."Credit") AS "U_Credit",CASE WHEN T1."Debit"<>0 THEN 'D' ELSE 'C' END AS "U_Point"
						FROM "OJDT" T0
						JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
						JOIN "OACT" T2 ON T1."Account"=T2."AcctCode"
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR3'
						WHERE 1=1
						AND T0."TransType" IN ('18','19')
						AND (T0."RefDate" >= :sdate )
						AND (T0."RefDate" <= :edate)
						AND (T2."AcctCode"='140802')
						
						UNION ALL
						SELECT '委外费用差异' AS "U_Type",NULL AS "U_CardCode",NULL AS "U_CardName"
						,T0."ObjType",T0."DocEntry",T0."DocNum",T0."LineNum"
						,T0."CalObjType",T0."CalDocEntry",T0."CalDocNum",T0."CalLineNum"
						,T2."ItemCode" AS "U_ItemCode",T2."ItemName" AS "U_ItemName"
						,T0."Qty" AS "U_Quantity",T0."Price" AS "U_Price",T0."Amt" AS "U_LineTotal",0 AS "U_PriceAfVAT",T0."GTotal" AS "U_GTotal"
						,T4."AcctCode" AS "U_AcctCode",T4."AcctName" AS "U_AcctName"
						,0.00 AS "U_Debit",-1*(T0."Amt"-T0."LineTotal") AS "U_Credit",'C' AS "U_Point"
						FROM :TMP T0 
						JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
						LEFT JOIN OACT T4 ON T4."AcctCode"='140803'
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR3'
						WHERE T0."ObjType" IN (18,19)
						AND T0."Type"='委外费用'
					
						UNION ALL
						SELECT '当月发票冲回暂估' AS "U_Type",T0."CardCode",T0."CardName"
						,T0."ObjType",T0."DocEntry",T0."DocNum",T0."LineNum"
						,T0."CalObjType",T0."CalDocEntry",T0."CalDocNum",T0."CalLineNum"
						,T2."ItemCode",T2."ItemName"
						,T0."Qty" AS "U_Quantity",T0."Price" AS "U_Price",T0."Amt" AS "U_LineTotal",0 AS "PriceAfVAT",T0."GTotal" AS "U_GTotal"
						,T4."AcctCode",T4."AcctName"
						,-1*(T0."Amt") AS "Debit",0.00,'D' AS "U_Point"
						FROM :TMP T0 
						JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
						LEFT JOIN OACT T4 ON T4."AcctCode"='220202'
						LEFT JOIN OTRC T11 ON T11."TrnsCode"='PUR3'
						WHERE T0."ObjType" IN (18,19)
						AND T0."Type"='委外费用'
				) P0
			;
				SELECT 'Y' AS "flag",T0."DocEntry",T1."LineId",TO_VARCHAR(T0."U_RefDate",'YYYYMMDD') AS "RefDate"
					,T0."U_TransCode" AS "TransCode",T11."TrnsCodDsc" AS "TransName",T0."U_Memo" AS "Memo"
					,T1."U_LineMemo" AS "LineMemo"
					,T1."U_AcctCode" AS "AcctCode",T1."U_AcctName" AS "AcctName"
					,T1."U_VendorCode",T1."U_VendorName"
					,T1."U_FCCurrency" AS "FCCurrency"
					,T1."U_FCDebit" AS "FCDebit",T1."U_FCCredit" AS "FCCredit",T1."U_Debit" AS "Debit",T1."U_Credit" AS "Credit"
					,T0."U_IsRev" AS "IsRev"		--是否需要冲销
					,TO_VARCHAR(T0."U_RevDate",'YYYYMMDD') AS "RevDate"
					,T1."U_CardCode" AS "U_CardCode"
					,T1."U_CardName" AS "U_CardName"
				FROM "@MTC_COST_OJDT" T0
				JOIN "@MTC_COST_OJDT1" T1 ON T0."DocEntry"=T1."DocEntry"
				LEFT JOIN OTRC T11 ON T0."U_TransCode"=T11."TrnsCode"
				WHERE T0."U_FcCode"=:FcCode AND T0."U_TransCode"=:TransCode
				AND (ABS(IFNULL(T1."U_Debit",0))+ABS(IFNULL(T1."U_Credit",0))+ABS(IFNULL(T1."U_FCDebit",0))+ABS(IFNULL(T1."U_FCCredit",0)))<>0
				;

				--发票暂估差异
				DELETE FROM "@MTC_OMRV" WHERE "U_DocDate"=:edate AND "U_BaseType"='WW';
				DELETE FROM "@MTC_OMRV1" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_OMRV");
				
				INSERT INTO "@MTC_OMRV"("DocEntry","DocNum","Object","Canceled","U_DocDate"
				,"U_BaseType","U_Memo","U_Total")
				SELECT TOP 1 U_MTC_OMRV_S.NEXTVAL AS "DocEntry",U_MTC_OMRV_S.NEXTVAL AS "DocNum",'MTC_OMRV','N',:edate
					,'WW','系统自动生成委外发票差异' AS "Memo",T0."Total"
					FROM (SELECT SUM("Credit") AS "Total" FROM :TMP_WWExp_OPCH T0 WHERE "ID"=21) T0;
				
				INSERT INTO "@MTC_OMRV1"(
					"DocEntry","LineId","U_LineMemo"
					,"U_CalType","U_ItemCode","U_ItemName"
					,"U_Quantity","U_Price","U_Amount"
					,"U_BaseType","U_BaseEntry","U_BaseNum","U_BaseLine"
					,"U_StockCode","U_StockName","U_AcctCode","U_AcctName"
					)
				SELECT T1."DocEntry"
					,ROW_NUMBER() OVER (ORDER BY T0."ObjType",T0."DocEntry",T0."LineNum") AS "LineId"
					,'委外费用差异' AS "U_LineMemo",'ProCost' AS "U_CalType"
					,T2."ItemCode",T2."ItemName"
					,0 AS "U_Quantity",0 AS "U_Price",(T0."Amt"-T0."LineTotal") AS "U_Amount"
					,T0."ObjType" AS "U_BaseType",T0."DocEntry" AS "U_BaseEntry",T0."DocNum" AS "U_BaseNum",T0."LineNum" AS "U_BaseLine"
					,T4."AcctCode",T4."AcctName",T6."AcctCode",T6."AcctName"
					FROM :TMP T0
					LEFT JOIN (SELECT "DocEntry" FROM "@MTC_OMRV" WHERE "U_DocDate"=:edate AND "U_BaseType"='WW' AND "Canceled"='N') T1 ON 1=1
					JOIN "OITM" T2 ON T0."U_ItemCode"=T2."ItemCode"
					LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct" FROm OGAR WHERE "PeriodCat"=LEFT(:FcCode,4) GROUP BY "ItmsGrpCod"
						) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
					LEFT JOIN OACT T4 ON T3."StockAct"=T4."AcctCode"
					LEFT JOIN "@MTC_MRVTYPE" T5 ON T5."Code"='WW'
					LEFT JOIN OACT T6 ON T6."AcctCode"=T5."U_AcctCode"
					WHERE T0."ObjType" IN (18,19)
					AND T0."Type"='委外费用'
					AND T0."Amt"-T0."LineTotal"<>0
				;
				
				
			END IF;
		
		--CalType：PUR1\4\5结束
		END IF;
		
	--STYPE结束
	END IF;
	

END