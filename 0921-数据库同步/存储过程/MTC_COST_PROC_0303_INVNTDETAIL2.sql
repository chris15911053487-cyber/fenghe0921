CREATE PROCEDURE "MTC_COST_PROC_0303_INVNTDETAIL2"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 为拉取数据到明细表的明细执行（包括①在"MTC_COST_PROC_0302_INVNTDETAIL1"中执行，②在"MTC_COST_PROC_CAL_1001_CHECK"中执行）
     * CALL "MTC_COST_PROC_0303_INVNTDETAIL2"(0,'2024-01','manager');
     * 写入：
       1.拉取除18、19的库存明细
       2.拉取18的交易明细
       3.拉取19的交易明细
       4.拉取MTC_OMRV的交易明细（需要计入当期成本计算）(类型是:WW委外发票差异，ProCost的)
    */
    
    
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
  	
	DELETE FROM MTC_COST_0302_INVNTDETAIL1 WHERE "FcCode" = :FcCode;
	DELETE FROM MTC_COST_0303_INVNTLIST WHERE "FcCode" = :FcCode;
	
	INSERT INTO MTC_COST_0302_INVNTDETAIL1(
	 "BPLId"
	 ,"FcCode"
	 ,"ObjType"
	 ,"DocEntry"
	 ,"DocNum"
	 ,"LineNum" 
	 ,"DocDate" 
	 ,"CostCode"   --归入成本计价类型
	 ,"TransCode"   --实际交易类型
	 ,"BaseType"
	 ,"BaseEntry"
	 ,"BaseNum"
	 ,"BaseLine"
	 ,"ItemCode"
	 ,"ItemName"
	 ,"ItmsGrpCod"
	 ,"iLevel"
	 ,"CalType" --成本计价类型
	 ,"Quantity"
	 ,"Amount"
	 ,"VarVal"
	 ,"Price"
	 ,"OcrCode1"
	 ,"WhsCode"
	 ,"BusiType"
	 ,"BusiTypeN"
	 ,"PriceMemo","AcctCode","CogsAcct"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,P0."TransType" AS "ObjType"
	,P0."CreatedBy" AS "DocEntry"
	,P0."BASE_REF" AS "DocNum"
	,P0."DocLineNum" AS "LineNum"
	,P0."DocDate"
	,P5."CostTypeCode" AS "CostCode"   --归入成本计价类型
	,P8."TransCode"   --实际交易类型
	,P8."BaseType"
	,P8."BaseEntry"
	,TO_CHAR(IFNULL(P8."BaseRef",'')) AS "BaseNum"
	,P8."BaseLine"
	,P0."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P3."iLevel"
	,P1."U_ItemProp" AS "CalType" --成本计价类型
	,P0."InQty"-P0."OutQty" AS "Quantity"
	,CASE WHEN P0."TransType" IN ('20','21') THEN P9."Amount" 
		ELSE P0."SumStock" END AS "Amount"
	,P0."VarVal"
	,0		------------2024.1.18注释掉
	,P8."OcrCode"
	,P0."LocCode"
	,P8."U_BusiType" AS "BusiType"
	,P8."U_YWLX" AS "BusiTypeN"
	,'从MTC_COST_PROC_0302_INVNTDETAIL1中抽取'
	,P8."AcctCode",P8."CogsAcct"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM OIVL P0
	LEFT JOIN OITM P1 ON P0."ItemCode"=P1."ItemCode"
	LEFT JOIN OITB P2 ON P1."ItmsGrpCod"=P2."ItmsGrpCod"
	LEFT JOIN U_COILV P3 ON P3."FcCode"=:FcCode AND P0."ItemCode"=P3."ItemCode"
	JOIN MTC_COST_0101_COSTTYPE P5 ON P5."CostTypeCode"='20'	--材料
	LEFT JOIN (SELECT T0."ObjType",T0."DocEntry",T0."LineNum",T0."OcrCode"
				,T0."BaseType",T0."BaseEntry",T0."BaseRef",T0."BaseLine"
				,T0."TransCode",T0."U_BusiType",T0."U_YWLX",T0."AcctCode",T0."CogsAcct"
				FROM "MTC_VIEW_Document" T0
		) P8 ON TO_CHAR(P0."TransType")=P8."ObjType" AND TO_CHAR(P0."CreatedBy")=P8."DocEntry" AND TO_CHAR(P0."DocLineNum")=P8."LineNum"
	LEFT JOIN (SELECT M."ObjType",M."DocEntry",D."LineNum"
				,CASE WHEN M."CANCELED"='C' THEN -1 ELSE 1 END
				 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."Price"*D."Quantity" END AS "Amount"
				FROM OPDN M JOIN PDN1 D ON M."DocEntry"=D."DocEntry"
				UNION ALL
				SELECT M."ObjType",M."DocEntry",D."LineNum"
				,CASE WHEN M."CANCELED"='C' THEN 1 ELSE -1 END
				 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."LineTotal" END AS "Amount"
				FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry"
			) P9 ON TO_CHAR(P0."TransType")=P9."ObjType" AND P0."CreatedBy"=P9."DocEntry" AND P0."DocLineNum"=P9."LineNum"
	WHERE 1=1
	AND P0."LocCode"<>'S300' --排除报废库
    AND P0."TransType"<>'67'	--排除67转储单
	AND P0."TransType" NOT IN ('18','19')
	AND LEFT(P0."DocDate",7)=:FcCode;
	
	--18
	INSERT INTO MTC_COST_0302_INVNTDETAIL1(
	 "BPLId"
	 ,"FcCode"
	 ,"ObjType"
	 ,"DocEntry"
	 ,"DocNum"
	 ,"LineNum" 
	 ,"DocDate" 
	 ,"CostCode"   --归入成本计价类型
	 ,"TransCode"   --实际交易类型
	 ,"BaseType"
	 ,"BaseEntry"
	 ,"BaseNum"
	 ,"BaseLine"
	 ,"ItemCode"
	 ,"ItemName"
	 ,"ItmsGrpCod"
	 ,"iLevel"
	 ,"CalType" --成本计价类型
	 ,"Quantity"
	 ,"Amount"
	 ,"VarVal"
	 ,"Price"
	 ,"OcrCode1"
	 ,"WhsCode"
	 ,"BusiType"
	 ,"BusiTypeN"
	 ,"PriceMemo","AcctCode","CogsAcct"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,P0."TransType" AS "ObjType"
	,P0."CreatedBy" AS "DocEntry"
	,P0."BASE_REF" AS "DocNum"
	,P0."DocLineNum" AS "LineNum"
	,P0."DocDate"
	,P5."CostTypeCode" AS "CostCode"   --归入成本计价类型
	,P8."TransCode"   --实际交易类型
	,P8."BaseType"
	,P8."BaseEntry"
	,TO_CHAR(P8."BaseRef") AS "BaseNum"
	,P8."BaseLine"
	,P0."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P3."iLevel"
	,P1."U_ItemProp" AS "CalType" --成本计价类型
	,P0."InQty"-P0."OutQty" AS "Quantity"
	,P9."Amount" AS "Amount"
	,P0."VarVal"
	,0		------------2024.1.18注释掉
	,P8."OcrCode"
	,P0."LocCode"
	,P8."U_BusiType" AS "BusiType"
	,P8."U_YWLX" AS "BusiTypeN"
	,'从MTC_COST_PROC_0302_INVNTDETAIL1中抽取'
	,P8."AcctCode",P8."CogsAcct"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM OIVL P0
	LEFT JOIN OITM P1 ON P0."ItemCode"=P1."ItemCode"
	LEFT JOIN OITB P2 ON P1."ItmsGrpCod"=P2."ItmsGrpCod"
	LEFT JOIN U_COILV P3 ON P3."FcCode"=:FcCode AND P0."ItemCode"=P3."ItemCode"
	JOIN MTC_COST_0101_COSTTYPE P5 ON P5."CostTypeCode"='20'	--材料
	LEFT JOIN (SELECT T0."ObjType",T0."DocEntry",T0."LineNum",T0."OcrCode"
				,T0."BaseType",T0."BaseEntry",T0."BaseRef",T0."BaseLine"
				,T0."TransCode",T0."U_BusiType",T0."U_YWLX",T0."AcctCode",T0."CogsAcct"
				FROM "MTC_VIEW_Document" T0
		) P8 ON TO_CHAR(P0."TransType")=P8."ObjType" AND TO_CHAR(P0."CreatedBy")=P8."DocEntry" AND TO_CHAR(P0."DocLineNum")=P8."LineNum"
	LEFT JOIN 
		(
		--18-正常单
		SELECT T1."ObjType",T1."DocEntry",T1."LineNum"
			,CASE WHEN T2."DocEntry" IS NULL THEN 0 ELSE T1."LineTotal"-T1."Quantity"*IFNULL(T2."Price",0) END AS "Amount"
			FROM OPCH T0
			JOIN PCH1 T1 ON T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (SELECT M."ObjType",M."DocEntry",D."LineNum"
						,CASE WHEN M."CANCELED"='C' THEN -1 ELSE 1 END
						 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."Price"*D."Quantity" END AS "Amount"
						 ,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0) ELSE D."Price" END AS "Price"
						FROM OPDN M JOIN PDN1 D ON M."DocEntry"=D."DocEntry"
						UNION ALL
						SELECT M."ObjType",M."DocEntry",D."LineNum"
						,CASE WHEN M."CANCELED"='C' THEN 1 ELSE -1 END
						 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."LineTotal" END AS "Amount"
						  ,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0) ELSE D."Price" END AS "Price"
						FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry"
					) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
		where T0."CANCELED" IN ('N','Y')
		
		UNION ALL
		--18-取消单（CANCELED='C'）
		SELECT T1."ObjType",T1."DocEntry",T1."LineNum"
			,CASE WHEN T2."DocEntry" IS NULL THEN 0 ELSE -1*T2."Amount" END AS "Amount"
			FROM OPCH T0
			JOIN PCH1 T1 ON T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (
			
						--18-正常单
						SELECT T1."ObjType",T1."DocEntry",T1."LineNum"
							,CASE WHEN T2."DocEntry" IS NULL THEN 0 ELSE T1."LineTotal"-T1."Quantity"*IFNULL(T2."Price",0) END AS "Amount"
							FROM OPCH T0
							JOIN PCH1 T1 ON T0."DocEntry"=T1."DocEntry"
							LEFT JOIN (SELECT M."ObjType",M."DocEntry",D."LineNum"
										,CASE WHEN M."CANCELED"='C' THEN -1 ELSE 1 END
										 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."Price"*D."Quantity" END AS "Amount"
										 ,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0) ELSE D."Price" END AS "Price"
										FROM OPDN M JOIN PDN1 D ON M."DocEntry"=D."DocEntry"
										UNION ALL
										SELECT M."ObjType",M."DocEntry",D."LineNum"
										,CASE WHEN M."CANCELED"='C' THEN 1 ELSE -1 END
										 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."LineTotal" END AS "Amount"
										  ,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0) ELSE D."Price" END AS "Price"
										FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry"
									) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
						where T0."CANCELED" IN ('N','Y')
			
			
					) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
		where T0."CANCELED" IN ('C')
		
		) P9 ON TO_CHAR(P0."TransType")=P9."ObjType" AND P0."CreatedBy"=P9."DocEntry" AND P0."DocLineNum"=P9."LineNum"
	WHERE 1=1
	AND P0."TransType" IN ('18')
	AND LEFT(P0."DocDate",7)=:FcCode;
	
	
	--19
	INSERT INTO MTC_COST_0302_INVNTDETAIL1(
	 "BPLId"
	 ,"FcCode"
	 ,"ObjType"
	 ,"DocEntry"
	 ,"DocNum"
	 ,"LineNum" 
	 ,"DocDate" 
	 ,"CostCode"   --归入成本计价类型
	 ,"TransCode"   --实际交易类型
	 ,"BaseType"
	 ,"BaseEntry"
	 ,"BaseNum"
	 ,"BaseLine"
	 ,"ItemCode"
	 ,"ItemName"
	 ,"ItmsGrpCod"
	 ,"iLevel"
	 ,"CalType" --成本计价类型
	 ,"Quantity"
	 ,"Amount"
	 ,"VarVal"
	 ,"Price"
	 ,"OcrCode1"
	 ,"WhsCode"
	 ,"BusiType"
	 ,"BusiTypeN"
	 ,"PriceMemo","AcctCode","CogsAcct"
	 ,"IsUpdatePrice"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,P0."TransType" AS "ObjType"
	,P0."CreatedBy" AS "DocEntry"
	,P0."BASE_REF" AS "DocNum"
	,P0."DocLineNum" AS "LineNum"
	,P0."DocDate"
	,P5."CostTypeCode" AS "CostCode"   --归入成本计价类型
	,P8."TransCode"   --实际交易类型
	,P8."BaseType"
	,P8."BaseEntry"
	,TO_CHAR(P8."BaseRef") AS "BaseNum"
	,P8."BaseLine"
	,P0."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P3."iLevel"
	,P1."U_ItemProp" AS "CalType" --成本计价类型
	,P0."InQty"-P0."OutQty" AS "Quantity"
	,P9."Amount" AS "Amount"
	,P0."VarVal"
	,0		------------2024.1.18注释掉
	,P8."OcrCode"
	,P0."LocCode"
	,P8."U_BusiType" AS "BusiType"
	,P8."U_YWLX" AS "BusiTypeN"
	,'从MTC_COST_PROC_0302_INVNTDETAIL1中抽取'
	,P8."AcctCode",P8."CogsAcct"
	,NULL AS "IsUpdatePrice"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM OIVL P0
	LEFT JOIN OITM P1 ON P0."ItemCode"=P1."ItemCode"
	LEFT JOIN OITB P2 ON P1."ItmsGrpCod"=P2."ItmsGrpCod"
	LEFT JOIN U_COILV P3 ON P3."FcCode"=:FcCode AND P0."ItemCode"=P3."ItemCode"
	JOIN MTC_COST_0101_COSTTYPE P5 ON P5."CostTypeCode"='20'	--材料
	LEFT JOIN (SELECT T0."ObjType",T0."DocEntry",T0."LineNum",T0."OcrCode"
				,T0."BaseType",T0."BaseEntry",T0."BaseRef",T0."BaseLine"
				,T0."TransCode",T0."U_BusiType",T0."U_YWLX",T0."AcctCode",T0."CogsAcct"
				FROM "MTC_VIEW_Document" T0
		) P8 ON TO_CHAR(P0."TransType")=P8."ObjType" AND TO_CHAR(P0."CreatedBy")=P8."DocEntry" AND TO_CHAR(P0."DocLineNum")=P8."LineNum"
	LEFT JOIN 
		(
		--正常单
		SELECT T1."ObjType",T1."DocEntry",T1."LineNum"
			,CASE WHEN T2."DocEntry" IS NULL THEN 0 ELSE -1*(T1."LineTotal"-T1."Quantity"*IFNULL(T2."Price",0)) END AS "Amount"
			FROM ORPC T0
			JOIN RPC1 T1 ON T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (SELECT M."ObjType",M."DocEntry",D."LineNum"
						,CASE WHEN M."CANCELED"='C' THEN -1 ELSE 1 END
						 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."Price"*D."Quantity" END AS "Amount"
						,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0) ELSE D."Price" END AS "Price"
						FROM OPDN M JOIN PDN1 D ON M."DocEntry"=D."DocEntry"
						UNION ALL
						SELECT M."ObjType",M."DocEntry",D."LineNum"
						,CASE WHEN M."CANCELED"='C' THEN 1 ELSE -1 END
						 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."LineTotal" END AS "Amount"
						,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0) ELSE D."Price" END AS "Price"
						FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry"
					) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
		where T0."CANCELED" IN ('N','Y')
		
		UNION ALL
		--19-取消单（CANCELED='C'）
		SELECT T1."ObjType",T1."DocEntry",T1."LineNum"
			,CASE WHEN T2."DocEntry" IS NULL THEN 0 ELSE 1*T2."Amount" END AS "Amount"
			FROM ORPC T0
			JOIN RPC1 T1 ON T0."DocEntry"=T1."DocEntry"
			LEFT JOIN (
			
						--19-取消单
						SELECT T1."ObjType",T1."DocEntry",T1."LineNum"
							,CASE WHEN T2."DocEntry" IS NULL THEN 0 ELSE T1."LineTotal"-T1."Quantity"*IFNULL(T2."Price",0) END AS "Amount"
							FROM ORPC T0
							JOIN RPC1 T1 ON T0."DocEntry"=T1."DocEntry"
							LEFT JOIN (SELECT M."ObjType",M."DocEntry",D."LineNum"
										,CASE WHEN M."CANCELED"='C' THEN -1 ELSE 1 END
										 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."Price"*D."Quantity" END AS "Amount"
										 ,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0) ELSE D."Price" END AS "Price"
										FROM OPDN M JOIN PDN1 D ON M."DocEntry"=D."DocEntry"
										UNION ALL
										SELECT M."ObjType",M."DocEntry",D."LineNum"
										,CASE WHEN M."CANCELED"='C' THEN 1 ELSE -1 END
										 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."LineTotal" END AS "Amount"
										  ,CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0) ELSE D."Price" END AS "Price"
										FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry"
									) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
						where T0."CANCELED" IN ('N','Y')
			
					) T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"
		where T0."CANCELED" IN ('C')
		) P9 ON TO_CHAR(P0."TransType")=P9."ObjType" AND P0."CreatedBy"=P9."DocEntry" AND P0."DocLineNum"=P9."LineNum"
	WHERE 1=1
	AND P0."TransType" IN ('19')
	--AND P0."BASE_REF" NOT IN (547,548)
	AND LEFT(P0."DocDate",7)=:FcCode;
	
	
	--"@MTC_OMRV"
	INSERT INTO MTC_COST_0302_INVNTDETAIL1(
	 "BPLId"
	 ,"FcCode"
	 ,"ObjType"
	 ,"DocEntry"
	 ,"DocNum"
	 ,"LineNum" 
	 ,"DocDate" 
	 ,"CostCode"   --归入成本计价类型
	 ,"TransCode"   --实际交易类型
	 ,"BaseType"
	 ,"BaseEntry"
	 ,"BaseNum"
	 ,"BaseLine"
	 ,"ItemCode"
	 ,"ItemName"
	 ,"ItmsGrpCod"
	 ,"iLevel"
	 ,"CalType" --成本计价类型
	 ,"Quantity"
	 ,"Amount"
	 ,"VarVal"
	 ,"Price"
	 ,"OcrCode1"
	 ,"WhsCode"
	 ,"BusiType"
	 ,"BusiTypeN"
	 ,"PriceMemo","AcctCode","CogsAcct"
	 ,"IsUpdatePrice"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,T0."Object" AS "ObjType"
	,T1."DocEntry" AS "DocEntry"
	,T0."DocNum" AS "DocNum"
	,T1."LineId" AS "LineNum"
	,T0."U_DocDate"
	,'20' AS "CostCode"   --归入成本计价类型
	,'I11' AS "TransCode"   --实际交易类型
	,T1."U_BaseType"
	,T1."U_BaseEntry"
	,TO_CHAR(T1."U_BaseNum")
	,T1."U_BaseLine"
	,T1."U_ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,P3."iLevel"
	,'02' AS "CalType" --成本计价类型
	,0 AS "Quantity"
	,T1."U_Amount" AS "Amount"
	,0 AS "VarVal"
	,0		------------2024.1.18注释掉
	,NULL AS "OcrCode"
	,NULL AS "LocCode"
	,'' AS "BusiType"
	,'' AS "BusiTypeN"
	,'从MTC_COST_PROC_0302_INVNTDETAIL1中抽取2'
	,NULL AS "AcctCode",NULL AS "CogsAcct"
	,CASE WHEN T1."U_CalType"='InvntCost' THEN 'NoCost' ELSE NULL END  AS "IsUpdatePrice" --'NoCost'时，不参与当期成本计算
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "@MTC_OMRV" T0
	JOIN "@MTC_OMRV1" T1 ON T0."DocEntry"=T1."DocEntry"
	LEFT JOIN OITM P1 ON T1."U_ItemCode"=P1."ItemCode"
	LEFT JOIN OITB P2 ON P1."ItmsGrpCod"=P2."ItmsGrpCod"
	LEFT JOIN U_COILV P3 ON P3."FcCode"=:FcCode AND T1."U_ItemCode"=P3."ItemCode"
	JOIN MTC_COST_0101_COSTTYPE P5 ON P5."CostTypeCode"='20'	--材料
	WHERE 1=1
	AND T0."U_BaseType" IN ('WW','MRV1') ---CL要改为按当期发生额
	AND LEFT(T0."U_DocDate",7)=:FcCode;
	
	SELECT 0 AS "代码",'写入库存明细'||:FcCode||',成功！' AS "信息" FROM DUMMY;

END