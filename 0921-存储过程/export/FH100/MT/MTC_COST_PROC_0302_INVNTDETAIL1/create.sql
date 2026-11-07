CREATE PROCEDURE "MTC_COST_PROC_0302_INVNTDETAIL1"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 仅入库数据明细到静态表 MTC_COST_0302_INVNTDETAIL1
     * CALL "MTC_COST_PROC_0302_INVNTDETAIL1"(0,'2024-01','manager');
    */
    
    
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
  	
  	
  	--拉取库存交易明细
    CALL "MTC_COST_PROC_0303_INVNTDETAIL2"(:BPLId,:FcCode,:UserCode);
  	
  	
	
	--初始化数量，将库存数量写入收发存表MTC_COST_0303_INVNT
	/*
		321 生产成品入库
        322 包装成品入库
        232 委外加工入库

    */
	UPDATE T0 SET 
	 T0."In_Qty"=IFNULL(T1."In_Qty",0)
	,T0."Out_Qty"=IFNULL(T1."Out_Qty",0)
	,T0."QM_Qty"=IFNULL(T0."QC_Qty",0)+IFNULL(T1."In_Qty",0)-IFNULL(T1."Out_Qty",0)
	FROM "MTC_COST_0301_INVNT" T0
	LEFT JOIN (
			SELECT T1."FcCode",T1."ItemCode"
			,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Quantity" ELSE 0 END) AS "In_Qty"
			,SUM(CASE WHEN T2."U_IOType"='O' THEN -1*T1."Quantity" ELSE 0 END) AS "Out_Qty"
			FROM "MTC_COST_0302_INVNTDETAIL1" T1
			JOIN "@MTC_COST_IOTYPE" T2 ON T1."TransCode"=T2."Code"
			WHERE 1=1
			GROUP BY T1."FcCode",T1."ItemCode"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	WHERE 1=1 AND T0."FcCode"=:FcCode;	
	
	
	--SELECT '1',* FROM MTC_COST_0302_INVNTDETAIL1 WHERE "ItemCode"='FH0100402' ;
	
	
	UPDATE MTC_COST_0302_INVNTDETAIL1 SET "IsUpdatePrice"='NoCost'
	WHERE "FcCode"=:FcCode AND IFNULL("Quantity",0)<>0  AND "BusiType" IN ('305','311','207'); --报废出入库
	
	UPDATE MTC_COST_0302_INVNTDETAIL1 SET "IsUpdatePrice"='P'
	WHERE "FcCode"=:FcCode AND "TransCode" IN ('I01','I06','I11')
	AND IFNULL("IsUpdatePrice",'')<>'NoCost'
	; --采购
	
	--作为入库加权的一部分（采购的加权入口）MTC_COST_0303_INVNTLIST
	INSERT INTO MTC_COST_0303_INVNTLIST(
	"BPLId","FcCode","CalType","ItemCode","ItemName","ItmsGrpCod","iLevel"
	,"ObjType","TransCode","SourceMemo"
	,"Qty","Price","Amt")
	SELECT :BPLId,"FcCode","CalType","ItemCode","ItemName","ItmsGrpCod","iLevel"
	,"ObjType","TransCode",'采购金额-'||"ObjType"||'-'||"DocEntry"||'-'||"LineNum"
	,("Quantity") AS "In_Qty",("Amount")/NULLIF(("Quantity"),0),("Amount") AS "In_Amount"
	FROM "MTC_COST_0302_INVNTDETAIL1" 
	WHERE "TransCode" IN ('I01','I06','I11')		--入库数量 
	AND "FcCode"=:FcCode
	AND IFNULL("IsUpdatePrice",'')<>'NoCost'
	--GROUP BY "FcCode","CalType","ItemCode","ItemName","ItmsGrpCod","iLevel","ObjType"
	;
	
	/*
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	FROM MTC_COST_0302_INVNTDETAIL1 T0
    JOIN MTC_COST_0210_QCPRICE T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."ObjType" IN ('59','16')
	AND T0."TransCode" IN ('59-304','59-204')
	AND T0."FcCode"='2024-12'
	;	*/
	
	--UPDATE MTC_COST_0302_INVNTDETAIL1 SET "Amount"="Quantity"*"Price" WHERE "ItemCode"='102000904' AND "ObjType"='59';
	
	--SELECT '2',* FROM MTC_COST_0302_INVNTDETAIL1 WHERE "ItemCode"='FH0627201' ;
	--SELECT * FROM MTC_COST_0301_INVNT WHERE "ItemCode"='FH0627201';
	--将采购入库单价写到
	UPDATE T0
	SET T0."In_Amount"=T1."In_Amount",T0."In_Price"=T1."In_Amount"/NULLIF(T1."In_Qty",0)
	,T0."Price"=(IFNULL(T0."QC_Amount",0)+IFNULL(T1."In_Amount",0))
				/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."In_Qty",0)),0)
	,"PriceMemo"=IFNULL("PriceMemo",'')||'->'||'从MTC_COST_PROC_0302_INVNTDETAIL1写入Step1001采购写入,单价,'
	||TO_CHAR((IFNULL(T0."QC_Amount",0)+IFNULL(T1."In_Amount",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."In_Qty",0)),0))
	FROM MTC_COST_0301_INVNT T0
	LEFT JOIN (SELECT "FcCode","ItemCode","CostCode"
			,SUM("Quantity") AS "In_Qty",SUM(ROUND("Amount",2)) AS "In_Amount"
			FROM "MTC_COST_0302_INVNTDETAIL1" 
			WHERE "TransCode" IN ('I01','I06','I11')		--入库数量
			AND IFNULL("IsUpdatePrice",'')<>'NoCost'
			--AND "TransCode" IN ('20-101','59-321','59-322','59-323')
			GROUP BY "FcCode","ItemCode","CostCode"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode" AND T0."CostCode"=T1."CostCode" 
	WHERE T0."CostCode"='20'	--材料
	AND T0."FcCode"=:FcCode;
	
	
	
	--SELECT '3',* FROM MTC_COST_0302_INVNTDETAIL1 WHERE "ItemCode"='FH0627201' ;
	--SELECT * FROM MTC_COST_0301_INVNT WHERE "ItemCode"='FH0627201';
	
	--计算外购品的加权出库单价
	/*
	UPDATE T0 SET T0."Price"=T1."Price"
	FROM "MTC_COST_0301_INVNT" T0
	JOIN (SELECT "FcCode","ItemCode","CostCode"
		  ,SUM(IFNULL(T0."QC_Qty",0)+IFNULL(T0."In_Qty",0)) AS "Qty"
		  ,SUM(IFNULL(T0."QC_Amount",0)+IFNULL(T0."In_Amount",0)) AS "Amount"
		  ,SUM(IFNULL(T0."QC_Amount",0)+IFNULL(T0."In_Amount",0))/NULLIF(SUM(IFNULL(T0."QC_Qty",0)+IFNULL(T0."In_Qty",0)),0) AS "Price"
		  FROM "MTC_COST_0301_INVNT" T0 GROUP BY "FcCode","ItemCode","CostCode"
		  ) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode" AND T0."CostCode"=T1."CostCode"
	WHERE T0."CostCode"='20'	--材料
	AND T0."FcCode"=:FcCode
	--AND T0."CalType"='01'
	;
	*/
		
	--SELECT '4',* FROM MTC_COST_0302_INVNTDETAIL1 WHERE "ItemCode"='FH0100402' ;
	--写原材料出库数据MTC_COST_0302_INVNTDETAIL1
	--59-203,60-203
	UPDATE T0
	SET T0."Amount"=ROUND(T0."Quantity"*IFNULL(T1."Price",0),2),T0."Price"=IFNULL(T1."Price",0)
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0302_INVNTDETAIL1中写入Step1002当期(上期+本期采购),单价为:'||TO_CHAR(IFNULL(T1."Price",0))
	,T0."IsUpdatePrice"='N'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	LEFT JOIN MTC_COST_0301_INVNT T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode" AND T0."CostCode"=T1."CostCode"
	WHERE 1=1
	AND IFNULL(T0."IsUpdatePrice",'')<>'NoCost'
	AND T0."ObjType" IN ('60','59')
	AND T0."TransCode" IN ('I04','O04','O07','O08','O05','I10','O10')  --'I07','I08'返工（生产返工、委外返工） ,'I05','O05'转换出入库
	AND T0."CostCode"='20'	--材料
	AND IFNULL(T1."Price",0)<>0 --2026.2.8增加此条件
	AND T0."FcCode"=:FcCode;
	
	--根据期初维护的价格写入价格为0的
	UPDATE T0
	SET T0."Amount"=ROUND(T0."Quantity"*IFNULL(T1."U_Price",0),2),T0."Price"=IFNULL(T1."U_Price",0)
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0302_INVNTDETAIL1中写入Step1003期初价格为0'
	,T0."IsUpdatePrice"='N'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT T1."U_ItemCode",T1."U_Price",T1."U_IsY"
			FROM "@MTC_COST_QCPRICE" T0
			JOIN "@MTC_COST_QCPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
			WHERE T0."Canceled"='N' AND T0."U_FcCode"=:FcCode
		) T1 ON T0."ItemCode"=T1."U_ItemCode"
	WHERE 1=1
	AND IFNULL(T0."IsUpdatePrice",'')<>'NoCost'
	AND T0."ObjType" IN ('60','59')
	AND T0."TransCode" IN ('I04','O04','O07','O08','O05','I10')  --'I07','I08'返工（生产返工、委外返工） ,'I05','O05'转换出入库
	AND T0."CostCode"='20'	--材料
	AND T0."FcCode"=:FcCode
	AND ((IFNULL(T1."U_Price",0)<>0 AND IFNULL(T0."Price",0)=0) OR T1."U_IsY"='Y');
	
	--I05转换入库
	UPDATE T0
	SET 
	 T0."Amount"=-1*IFNULL(T1."Amount",0)
	,T0."Price"=-1*IFNULL(T1."Amount",0)/T0."Quantity"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0302_INVNTDETAIL1中转换出入库写入'
	,T0."IsUpdatePrice"='I05'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT T0."BaseType",T0."BaseEntry",T0."BaseLine",T0."Amount"
			FROM "MTC_COST_0302_INVNTDETAIL1" T0
			WHERE T0."TransCode"='O05' AND T0."FcCode"=:FcCode
		) T1 ON T0."BaseType"=T1."BaseType" AND T0."BaseEntry"=T1."BaseEntry" AND T0."BaseLine"=T1."BaseLine"
	WHERE 1=1
	AND IFNULL(T0."IsUpdatePrice",'')<>'NoCost'
	AND T0."ObjType" IN ('60','59')
	AND T0."TransCode" IN ('I05')  --'I05','O05'转换出入库
	AND T0."CostCode"='20'	--材料
	AND T0."FcCode"=:FcCode;
	
	
	
	--更新出库的加权价
	UPDATE T0 SET 
	T0."Price"=
	CASE WHEN IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)=0
	THEN T0."Price"
	ELSE ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6) END
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0302_INVNTDETAIL1写入Step1009加权计算写入'
	FROM MTC_COST_0301_INVNT T0
	LEFT JOIN (SELECT "FcCode","ItemCode","CostCode",SUM("Quantity") AS "Qty",SUM("Amount") AS "Amt"
			FROM "MTC_COST_0302_INVNTDETAIL1" 
			WHERE IFNULL("IsUpdatePrice",'')<>'' --已经被初始过价格的
			GROUP BY "FcCode","ItemCode","CostCode"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode" AND T0."CostCode"=T1."CostCode" 
	WHERE 1=1
	AND T0."CostCode"='20'	--材料
	AND T0."FcCode"=:FcCode;
	
	
	
	/*
	
	--将出库数写到
	UPDATE T0 SET T0."Out_Qty"=T1."Out_Qty",T0."Out_Amount"=T1."Out_Amount"
	FROM MTC_COST_0301_INVNT T0
	JOIN (SELECT "FcCode","ItemCode","CostCode",-1*SUM("Quantity") AS "Out_Qty",-1*SUM("Amount") AS "Out_Amount"
			FROM "MTC_COST_0302_INVNTDETAIL1" 
			WHERE "ObjType" IN ('60')		--出库数量
			GROUP BY "FcCode","ItemCode","CostCode"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode" AND T0."CostCode"=T1."CostCode" 
	WHERE 1=1
	AND T0."CostCode"='20'	--材料
	AND T0."FcCode"=:FcCode
	AND T0."CalType"='01';
	
	
	--将期末数写到
	UPDATE T0 SET T0."QM_Qty"=IFNULL(T0."QC_Qty",0)+IFNULL(T0."In_Qty",0)-IFNULL(T0."Out_Qty",0)
	,T0."QM_Amount"=IFNULL(T0."QC_Amount",0)+IFNULL(T0."In_Amount",0)-IFNULL(T0."Out_Amount",0)
	FROM MTC_COST_0301_INVNT T0
	WHERE 1=1
	AND T0."CostCode"='20'	--材料
	AND T0."FcCode"=:FcCode;*/
	
	SELECT 0 AS "代码",'写入库存明细'||:FcCode||',成功！' AS "信息" FROM DUMMY;

END