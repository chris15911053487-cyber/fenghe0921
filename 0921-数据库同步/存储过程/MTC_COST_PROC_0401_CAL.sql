CREATE PROCEDURE "MTC_COST_PROC_0401_CAL"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 抽取物料等级 到 明细到静态表 MTC_COST_0105_ITEM
     * CALL "MTC_COST_PROC_0401_CAL"(0,'2024-01','manager');
    */
    
    DECLARE CNT INT = 0;
    DECLARE ILEVEL INT = 1;
    DECLARE MAXLEVEL INT = 0;
    
    
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
    
    DELETE FROM MTC_COST_0303_INVNTLIST WHERE "FcCode"=:FcCode AND "ObjType" NOT IN ('20','21');
    
    --SELECT * FROM MTC_COST_0301_INVNT WHERE "CostCode"='20' AND "ItemCode"='FH1360401';
	/* 2026.2.8去掉
	 --O07、O08返工领料，如果一定要写返工领料 需要先写入到MTC_COST_0302_INVNTDETAIL1
   	UPDATE T1 SET T1."Price"=T3."Price",T1."Amount"=T1."IgeQty"*T3."Price"
   	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Step0000写入'
   	,T1."IsUpdatePrice"='0000'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN U_COILV T2 ON T1."ItemCode"=T2."ItemCode" AND T1."FcCode"=T2."FcCode"
	JOIN (SELECT * FROM MTC_COST_0301_INVNT WHERE "CostCode"='20'
		) T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode"
	WHERE 1=1
	AND T1."FcCode"=:FcCode
	AND T1."DocType"='MTC_OWOR'
	--WHERE T2."ItmsGrpCod"='103'
	--AND T2."ItemCode"='102000866'	
	;
	*/
	
	--chris.li 2026.9.9 
	
		--取消的交货单取原始单据的成本,DLN01是取消上期的，DLN02是取消本期的
		UPDATE T0 SET T0."Amount"=-1*T1."Amount",T0."Price"=T1."Price"
	   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.8091取消交货单写入'
	   	,T0."IsUpdatePrice"='DLN01'
		FROM "MTC_COST_0302_INVNTDETAIL1" T0
		--取消关联的源单
		JOIN "MTC_COST_0302_INVNTDETAIL1" T1 ON T0."BaseType"=T1."ObjType" AND T0."BaseEntry"=T1."DocEntry" AND T0."BaseLine"=T1."LineNum"
		WHERE 1=1
		AND T0."ObjType"='15'
		AND T0."FcCode"=:FcCode
		AND T1."FcCode"<:FcCode --取上期的
		--AND IFNULL(T0."IsUpdatePrice",'')<>'DLN01'
		;
		
		
		--取消的销售退货单取原始单据的成本,RD01是取消上期的，RD02是取消本期的
		UPDATE T0 SET T0."Amount"=-1*T1."Amount",T0."Price"=T1."Price"
	   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.8092取消退货单写入'
	   	,T0."IsUpdatePrice"='RDN01'
		FROM "MTC_COST_0302_INVNTDETAIL1" T0
		--取消关联的源单
		JOIN "MTC_COST_0302_INVNTDETAIL1" T1 ON T0."BaseType"=T1."ObjType" AND T0."BaseEntry"=T1."DocEntry" AND T0."BaseLine"=T1."LineNum"
		WHERE 1=1
		AND T0."ObjType"='16'
		AND T0."FcCode"=:FcCode
		AND T1."FcCode"<:FcCode --取上期的
		--AND IFNULL(T0."IsUpdatePrice",'')<>'RDN01'
		;
	
	--2026.1.8增加退料的写入
    UPDATE T1 
	SET T1."Amount"=ROUND(T1."Quantity"*IFNULL(T2."Price",0),2),T1."Price"=IFNULL(T2."Price",0)
	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.TL44写入,退料'
	,T1."IsUpdatePrice"='TL44'
    FROM MTC_COST_0302_INVNTDETAIL1 T1
    JOIN (SELECT "BaseType","BaseEntry","BaseLine",SUM("Amount")/NULLIF(SUM("Quantity"),0) AS "Price"
    		FROM MTC_COST_0302_INVNTDETAIL1 WHERE "ObjType"='60'
    		GROUP BY "BaseType","BaseEntry","BaseLine"
    	) T2 ON T1."BaseType"=T2."BaseType" AND T1."BaseEntry"=T2."BaseEntry" AND T1."BaseLine"=T2."BaseLine"
    WHERE 1=1
	AND IFNULL(T1."IsUpdatePrice",'')<>'NoCost'
	AND T1."ObjType" IN ('59')
	AND T1."TransCode" IN ('O03','O07')  --O03 生产发料  O07生产返工领料 2026.2.8增加O07
	AND T1."BusiType"='304' --生产退料
	AND T1."CostCode"='20'	--材料
	AND T1."FcCode"=:FcCode
	AND ((IFNULL(T2."Price",0)<>0 AND IFNULL(T1."Price",0)=0));
	
	--20251204增加只有生产退料
	--根据期初维护的价格写入价格为0的
	UPDATE T0
	SET T0."Amount"=ROUND(T0."Quantity"*IFNULL(T1."U_Price",0),2),T0."Price"=IFNULL(T1."U_Price",0)
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Step43写入,退料'
	,T0."IsUpdatePrice"='304'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT T1."U_ItemCode",T1."U_Price",T1."U_IsY"
			FROM "@MTC_COST_QCPRICE" T0
			JOIN "@MTC_COST_QCPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
			WHERE T0."Canceled"='N' AND T0."U_FcCode"=:FcCode
		) T1 ON T0."ItemCode"=T1."U_ItemCode"
	WHERE 1=1
	AND IFNULL(T0."IsUpdatePrice",'')<>'NoCost'
	AND T0."ObjType" IN ('60','59')
	AND T0."TransCode" IN ('O03','O07') -- 2026.2.8增加O07生产返工
	AND T0."BusiType"='304' --生产退料
	AND T0."CostCode"='20'	--材料
	AND T0."FcCode"=:FcCode
	AND ((IFNULL(T1."U_Price",0)<>0 AND IFNULL(T0."Price",0)=0));
	
    
	--更新写入价格至MTC_COST_0302_INVNTDETAIL1
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*CASE WHEN IFNULL(T1."Price",0)=0 THEN T9."Price" ELSE T1."Price" END,2)
	,T0."Price"=CASE WHEN IFNULL(T1."Price",0)=0 THEN T9."Price" ELSE T1."Price" END
   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Step1201写入(O03、O09)'
   	,T0."IsUpdatePrice"='PP00'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN MTC_COST_0301_INVNT T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	LEFT JOIN (SELECT "FcCode","ItemCode",SUM("Amount")/NULLIF(SUM("Quantity"),0) AS "Price" FROM MTC_COST_0302_INVNTDETAIL1
				WHERE "Quantity">0
				GROUP BY "FcCode","ItemCode"
				) T9 ON T0."FcCode"=T9."FcCode" AND T0."ItemCode"=T9."ItemCode"
	WHERE T1."CostCode"='20'
	AND T0."TransCode" IN ('O03','O09','O07','O08')  --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=0
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;
	/*
	 --写入生产订单明细 2026.2.8注释掉
   	UPDATE T1 SET T1."Price"=T3."Price",T1."Amount"=T1."IgeQty"*T3."Price"
   	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Step1001写入'
   	,T1."IsUpdatePrice"='1001'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN U_COILV T2 ON T1."ItemCode"=T2."ItemCode" AND T1."FcCode"=T2."FcCode"
	JOIN (SELECT * FROM MTC_COST_0301_INVNT WHERE "CostCode"='20'
		) T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode"
	WHERE 1=1
	AND T1."FcCode"=:FcCode
	AND T2."iLevel"=0
	--WHERE T2."ItmsGrpCod"='103'
	--AND T2."ItemCode"='102000866'	
	;*/
	
	 --写入生产订单明细 2026.2.8修改从出入库明细里取
   	UPDATE T1 SET 
   	 T1."Price"=T3."IgeAmt"/NULLIF(T1."IgeQty",0)
   	,T1."Amount"=T3."IgeAmt"
   	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Step1001写入new Line=119'
   	,T1."IsUpdatePrice"='1001'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN U_COILV T2 ON T1."ItemCode"=T2."ItemCode" AND T1."FcCode"=T2."FcCode"
	JOIN (SELECT "FcCode","BaseType","BaseEntry","BaseLine","ItemCode",SUM(ROUND("Amount",2)) AS "IgeAmt"
			FROM MTC_COST_0302_INVNTDETAIL1
			WHERE "TransCode" IN ('O03','O07','O08','O09') --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
			GROUP BY "FcCode","BaseType","BaseEntry","BaseLine","ItemCode"
		) T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode" AND T1."DocType"=T3."BaseType"
				AND T1."WorEntry"=T3."BaseEntry" AND T1."LineNum"=T3."BaseLine"
	WHERE 1=1
	AND T1."FcCode"=:FcCode
	AND T2."iLevel"=0
	--WHERE T2."ItmsGrpCod"='103'
	--AND T2."ItemCode"='102000866'	
	;
	
	/* 还需要等待确认
	--期初的写入生产退料
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN MTC_COST_0301_INVNT T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T1."CostCode"='20'
	AND T0."TransCode" IN ('59-303','59-304','59-305','59-203')
	AND T0."FcCode"=:FcCode 
	--AND T2."iLevel"=0 AND T0."ItemCode"='122000002'
   ;*/
    
    ----------------------------------------------------iLevel = 0 -------------------------------------------
	
    --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Level0写入'
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."DocType",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(ROUND(T1."Amount",2)) AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON T0."DocType"=T1."DocType" AND T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."DocType",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T0."DocType",T2."WorEntry"
			,-1*SUM(ROUND(T2."Amount",2)) AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN ROUND(T2."Amount",2) ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN ROUND(T2."Amount",2) ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN ROUND(T2."Amount",2) ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T0."DocType"=T2."DocType" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T0."DocType",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."DocType"=T3."DocType" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=0
	AND T0."FcCode"=:FcCode;
	
	--SELECT "Price",* FROM "MTC_COST_0301_INVNT" WHERE "ItemCode"='102001308-B0.1';
	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,0,'');
	--CALL MTC_COST_PROC_0402_CAL_OWOR_WW(:BPLId,:FcCode,:UserCode,0,'');
	
	--SELECT "Price",* FROM "MTC_COST_0301_INVNT" WHERE "ItemCode"='102001308-B0.1';
	--iLevel = 1的入库明细
	--更新生产订单完工的金额至59、16
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level0.00写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorEntry","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	--AND IFNULL(T0."TransCode",'') NOT IN ('59-305','59-211')	--305生产报废不参与
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=0
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;
	
	
	
	/*
	--对生产退货60-I03
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level0.21写入'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amount")/NULLIF(SUM("Quantity"),0) AS "Price"
			FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20' AND "ObjType"='59' AND "TransCode"='I03'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."ObjType"='60'
	AND T0."TransCode" IN ('I03')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=0
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;*/
	
	--iLevel = 1的入库列表（包含59、16）
	INSERT INTO MTC_COST_0303_INVNTLIST(
	"BPLId","FcCode","ItemCode","ItemName"
	,"ObjType","TransCode","SourceMemo"
	,"Qty","Price","Amt")
	SELECT 0,T0."FcCode",T0."ItemCode",T0."ItemName"
	,T0."ObjType",T0."TransCode",'生产入库金额iLevel=0'
	,SUM(T0."Quantity") AS "In_Qty",SUM(T0."Amount")/NULLIF(SUM(T0."Quantity"),0),SUM(T0."Amount") AS "In_Amount"
	FROM "MTC_COST_0302_INVNTDETAIL1" T0
	JOIN U_COILV T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	WHERE 1=1
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T0."FcCode"=:FcCode
	AND T1."iLevel"=0
	GROUP BY T0."FcCode",T0."ItemCode",T0."ItemName",T0."CostCode",T0."ObjType",T0."TransCode";
	
	--更新价格至MTC_COST_0301_INVNT
    UPDATE T0 SET T0."Price"=ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6)
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level0.11写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Qty") AS "Qty",SUM("Amt") AS "Amt"
    		FROM "MTC_COST_0303_INVNTLIST"
    		WHERE "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=0
	AND T0."FcCode"=:FcCode	--20材料
    ;
    
    --补充
	 UPDATE T0 SET T0."Price"=
	 CASE WHEN IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)=0
	 THEN ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."IN_Amount",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."IN_QTY",0)),0),6)
	 ELSE ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6) END
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level0.12写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Quantity") AS "Qty",SUM(ROUND("Amount",2)) AS "Amt"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Quantity" ELSE 0 END) AS "IN_QTY"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN ROUND(T1."Amount",2) ELSE 0 END) AS "IN_Amount"
    		FROM "MTC_COST_0302_INVNTDETAIL1" T1
			LEFT JOIN "@MTC_COST_IOTYPE" T2 ON T1."TransCode"=T2."Code"
    		WHERE 1=1 AND IFNULL("IsUpdatePrice",'')<>''
    		--AND "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=0
	AND T0."FcCode"=:FcCode	--20材料
    ;
    --更新写入价格至MTC_COST_0302_INVNTDETAIL1
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel0写入(O03、O09)'
   	,T0."IsUpdatePrice"='PP01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN MTC_COST_0301_INVNT T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T1."CostCode"='20'
	AND T0."TransCode" IN ('O03','O09','O07','O08')  --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=0
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;
	/*
    --将价格写入下一环节的生产订单
	UPDATE T1 
	SET  T1."Price"=T4."Price",T1."Amount"=T1."IgeQty"*T4."Price"
   	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel0.01写入'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN U_COILV T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode"		--子件
	JOIN MTC_COST_0301_INVNT T4 ON T1."ItemCode"=T4."ItemCode" AND T1."FcCode"=T4."FcCode"
	WHERE 1=1 AND T4."CostCode"='20'
	--AND T2."iLevel"=2
	AND T3."iLevel"=0
	AND T1."FcCode"=:FcCode
	AND IFNULL(T1."IsUpdatePrice",'')=''
	;
	*/
	
	 --写入生产订单明细 2026.2.8修改从出入库明细里取
   	UPDATE T1 SET 
   	 T1."Price"=T3."IgeAmt"/NULLIF(T1."IgeQty",0)
   	,T1."Amount"=T3."IgeAmt"
   	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel0.01写入new Line=308'
   	--,T1."IsUpdatePrice"='1001'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN U_COILV T2 ON T1."ItemCode"=T2."ItemCode" AND T1."FcCode"=T2."FcCode"
	JOIN (SELECT "FcCode","BaseType","BaseEntry","BaseLine","ItemCode",SUM(ROUND("Amount",2)) AS "IgeAmt"
			FROM MTC_COST_0302_INVNTDETAIL1
			WHERE "TransCode" IN ('O03','O07','O08','O09') --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
			GROUP BY "FcCode","BaseType","BaseEntry","BaseLine","ItemCode"
		) T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode" AND T1."DocType"=T3."BaseType"
				AND T1."WorEntry"=T3."BaseEntry" AND T1."LineNum"=T3."BaseLine"
	WHERE 1=1
	AND T1."FcCode"=:FcCode
	AND T2."iLevel"=0
	AND IFNULL(T1."IsUpdatePrice",'')=''
	--WHERE T2."ItmsGrpCod"='103'
	--AND T2."ItemCode"='102000866'	
	;
	
    ----------------------------------------------------iLevel = 1 -------------------------------------------
	--1.计算成本


	  --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Level0—1写入'
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."DocType",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(ROUND(T1."Amount",2)) AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON T0."DocType"=T1."DocType" AND T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."DocType",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T0."DocType",T2."WorEntry"
			,-1*SUM(ROUND(T2."Amount",2)) AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN ROUND(T2."Amount",2) ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN ROUND(T2."Amount",2) ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN ROUND(T2."Amount",2) ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T0."DocType"=T2."DocType" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T0."DocType",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."DocType"=T3."DocType" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=0
	AND T0."DocType"='MTC_OWOR'
	AND T0."FcCode"=:FcCode;

	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,0,'');
	
	
    --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Level1写入'
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."DocType",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON T0."DocType"=T1."DocType" AND T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."DocType",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T0."DocType",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T0."DocType"=T2."DocType" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T0."DocType",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."DocType"=T3."DocType" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=1
	AND T0."FcCode"=:FcCode;
	
	--2.写入考虑了前期已投入的成品写入MTC_COST_0321_OWOR_SUM
	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,1,'');
	--CALL MTC_COST_PROC_0402_CAL_OWOR_WW(:BPLId,:FcCode,:UserCode,1,'');
	
	--iLevel = 1的生产入库明细
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level1.11写入('||T1."Price"||')'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorEntry","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=1
	;	
	
	--SELECT 1,* FROM MTC_COST_0302_INVNTDETAIL1 WHERE "ItemCode"='102002056';
	/*待验证
    --生产退料
    UPDATE T0 SET T0."Price"=T2."Price",T0."Amount"=T0."Quantity"*T2."Price"
    FROM "MTC_COST_0302_INVNTDETAIL1" T0
    JOIN MTC_COST_0210_QCPRICE T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	JOIN U_COILV T3 ON T0."FcCode"=T3."FcCode" AND T0."ItemCode"=T3."ItemCode" 
    WHERE T0."CostCode"='20'	--20材料
	AND T0."FcCode"=:FcCode
	AND (T0."ObjType" = '16' 
			OR (T0."ObjType"='59' AND "TransCode" IN ('59-304','59-208','59-204'))
			OR (T0."ObjType"='60' AND "TransCode" IN ('60-304','60-208','60-205')))  --59-208其他入库 59-304生产退料 204形态转入 205形态转出
	AND T0."Price"=0
	AND T3."iLevel"=1
    ;
    
	--SELECT 1,* FROM MTC_COST_0302_INVNTDETAIL1 WHERE "ItemCode"='102002056';
	
     UPDATE T0 SET T0."Amount"=T0."Quantity"*T0."Price"
    FROM "MTC_COST_0302_INVNTDETAIL1" T0
	JOIN U_COILV T3 ON T0."FcCode"=T3."FcCode" AND T0."ItemCode"=T3."ItemCode" 
	AND T3."iLevel"=1
	AND T0."FcCode"=:FcCode
	AND T0."TransCode" IN ('59-304');*/
    
    
	--对生产退货60-I03
	/*
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level1.21写入'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amount")/NULLIF(SUM("Quantity"),0) AS "Price"
			FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20' AND "ObjType"='59' AND "TransCode"='I03'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."ObjType"='60'
	AND T0."TransCode" IN ('I03')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=1
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;*/
	
	--iLevel = 1的入库列表
	INSERT INTO MTC_COST_0303_INVNTLIST(
	"BPLId","FcCode","ItemCode","ItemName"
	,"ObjType","TransCode","SourceMemo"
	,"Qty","Price","Amt")
	SELECT 0,T0."FcCode",T0."ItemCode",T0."ItemName"
	,T0."ObjType",T0."TransCode",'生产入库金额iLevel=1'
	,SUM(T0."Quantity") AS "In_Qty",SUM(ROUND(T0."Amount",2))/NULLIF(SUM(T0."Quantity"),0),SUM(T0."Amount") AS "In_Amount"
	FROM "MTC_COST_0302_INVNTDETAIL1" T0
	JOIN U_COILV T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T0."FcCode"=:FcCode
	AND T1."iLevel"=1
	GROUP BY T0."FcCode",T0."ItemCode",T0."ItemName",T0."CostCode",T0."ObjType",T0."TransCode";
	
	/*待验证
	--增加对其他的处理(将其他收货的价格写入到销售退货)
	UPDATE T0
	SET T0."Price"=IFNULL(T1."Price",0),T0."Amt"=T0."Qty"*IFNULL(T1."Price",0)
	,T0."SourceMemo"='从生产入库金额iLevel=1的59收货写入'
	FROM MTC_COST_0303_INVNTLIST T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amt")/NULLIF(SUM("Qty"),0) AS "Price"
			FROM MTC_COST_0303_INVNTLIST WHERE "ObjType"='59' AND "TransCode" NOT IN ('59-304','59-208')
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND (T0."ObjType" = '16' OR (T0."ObjType"='59' AND "TransCode" IN ('59-304','59-208')))  --59-208其他入库 59-304生产退料
	AND T2."iLevel"=1
	;
	
	
	--增加对其他的处理(204形态转换入库)
	UPDATE T0
	SET T0."Price"=IFNULL(T1."Price",0),T0."Amt"=T0."Qty"*IFNULL(T1."Price",0)
	,T0."SourceMemo"='从生产入库金额iLevel=1的59收货写入(形态转换)'
	FROM MTC_COST_0303_INVNTLIST T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amt")/NULLIF(SUM("Qty"),0) AS "Price"
			FROM MTC_COST_0303_INVNTLIST WHERE "ObjType"='59' AND "TransCode"='59-321'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND T0."TransCode"='59-204'  --59-208其他入库 59-304生产退料 204形态转换入库
	AND T0."Price"=0
	AND T2."iLevel"=1
	;*/
	
	--更新价格至MTC_COST_0301_INVNT
    UPDATE T0 SET T0."Price"=ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6)
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level1.11写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Qty") AS "Qty",SUM("Amt") AS "Amt"
    		FROM "MTC_COST_0303_INVNTLIST"
    		WHERE "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=1
	AND T0."FcCode"=:FcCode	--20材料
    ;
    
    --补充
	 UPDATE T0 SET T0."Price"=
	 CASE WHEN IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)=0
	 THEN ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."IN_Amount",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."IN_QTY",0)),0),6)
	 ELSE ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6) END
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level1.12写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Quantity") AS "Qty",SUM("Amount") AS "Amt"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Quantity" ELSE 0 END) AS "IN_QTY"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Amount" ELSE 0 END) AS "IN_Amount"
    		FROM "MTC_COST_0302_INVNTDETAIL1" T1
			LEFT JOIN "@MTC_COST_IOTYPE" T2 ON T1."TransCode"=T2."Code"
    		WHERE 1=1 AND IFNULL("IsUpdatePrice",'')<>''
    		--AND "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=1
	AND T0."FcCode"=:FcCode	--20材料
    ;
    
    --更新写入价格至MTC_COST_0302_INVNTDETAIL1
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel1写入(O03、O09) Line=549'
   	,T0."IsUpdatePrice"='PP10'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN MTC_COST_0301_INVNT T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T1."CostCode"='20'
	AND T0."TransCode" IN ('O03','O09','O07','O08')  --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=1
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;
    /*
    --将价格写入下一环节的生产订单 2026.2.8改之前
	UPDATE T1 
	SET  T1."Price"=T4."Price",T1."Amount"=T1."IgeQty"*T4."Price"
	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel1.01写入'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN MTC_COST_0321_OWOR T0 ON T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	JOIN U_COILV T2 ON T0."ItemCode"=T2."ItemCode" AND T0."FcCode"=T2."FcCode"		--主件
	JOIN U_COILV T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode"		--子件
	JOIN MTC_COST_0301_INVNT T4 ON T1."ItemCode"=T4."ItemCode" AND T1."FcCode"=T4."FcCode"
	WHERE 1=1 AND T4."CostCode"='20'
	--AND T2."iLevel"=2
	AND T3."iLevel"=1
	AND IFNULL(T1."IsUpdatePrice",'')=''
	AND T0."FcCode"=:FcCode
	;*/
	
	
	 --写入生产订单明细 2026.2.8修改从出入库明细里取
   	UPDATE T1 SET 
   	 T1."Price"=T3."IgeAmt"/NULLIF(T1."IgeQty",0)
   	,T1."Amount"=T3."IgeAmt"
   	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel1.01写入new Line=581'
   	--,T1."IsUpdatePrice"='1001'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN U_COILV T2 ON T1."ItemCode"=T2."ItemCode" AND T1."FcCode"=T2."FcCode"
	JOIN (SELECT "FcCode","BaseType","BaseEntry","BaseLine","ItemCode",SUM(ROUND("Amount",2)) AS "IgeAmt"
			FROM MTC_COST_0302_INVNTDETAIL1
			WHERE "TransCode" IN ('O03','O07','O08','O09')  --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
			GROUP BY "FcCode","BaseType","BaseEntry","BaseLine","ItemCode"
		) T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode" AND T1."DocType"=T3."BaseType"
				AND T1."WorEntry"=T3."BaseEntry" AND T1."LineNum"=T3."BaseLine"
	WHERE 1=1
	AND T1."FcCode"=:FcCode
	AND T2."iLevel"=1
	AND IFNULL(T1."IsUpdatePrice",'')=''
	--WHERE T2."ItmsGrpCod"='103'
	--AND T2."ItemCode"='102000866'	
	;
    
    ----------------------------------------------------iLevel = 2 -------------------------------------------
	--1.计算成本
	
	  --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Level1—1写入'
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."DocType",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON T0."DocType"=T1."DocType" AND T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."DocType",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T0."DocType",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T0."DocType"=T2."DocType" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T0."DocType",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."DocType"=T3."DocType" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=1
	AND T0."DocType"='MTC_OWOR'
	AND T0."FcCode"=:FcCode;

	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,1,'');
	
	--chrlis.li 2026.3.6有返工单自己加工自己的情况 返工单号287#、288#、289#
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level2.11-641写入'
	,T0."IsUpdatePrice"='IN01-641'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorType","WorEntry","WorNum","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T1."WorType"='30'	--返工单
	--AND IFNULL(T0."TransCode",'') NOT IN ('59-305')	--305生产报废不参与
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=1
	--AND T1."WorNum" IN (287,288,289,292,293,294,295,296,297,298)
	--AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	
     --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=ROUND(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0),2)
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Level2写入'
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."DocType",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON T0."DocType"=T1."DocType" AND T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."DocType",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T0."DocType",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T0."DocType"=T2."DocType" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T0."DocType",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."DocType"=T3."DocType" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=2
	AND T0."FcCode"=:FcCode;
	
	--2.写入考虑了前期已投入的成品写入MTC_COST_0321_OWOR_SUM
	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,2,'');
	--CALL MTC_COST_PROC_0402_CAL_OWOR_WW(:BPLId,:FcCode,:UserCode,2,'');
   
	--iLevel = 3的入库明细MTC_COST_0302_INVNTDETAIL1（将iLevel=3的产成品的成本写入入库明细）
	--从考虑了在产品的累计生产订单的成本MTC_COST_0321_OWOR_SUM
	
	
	--iLevel = 2的入库明细
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level2.11写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorEntry","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	--AND IFNULL(T0."TransCode",'') NOT IN ('59-305')	--305生产报废不参与
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=2
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	
	
	/*
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	FROM MTC_COST_0302_INVNTDETAIL1 T0
    JOIN MTC_COST_0210_QCPRICE T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."ObjType" IN ('59','16')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=2;*/
	/*
	--对生产退货60-I03
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level2.21写入'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amount")/NULLIF(SUM("Quantity"),0) AS "Price"
			FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20' AND "ObjType"='59' AND "TransCode"='I03'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."ObjType"='60'
	AND T0."TransCode" IN ('I03')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=2
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;*/
	
	--iLevel = 2的入库列表
	DELETE FROM MTC_COST_0303_INVNTLIST WHERE "FcCode"=:FcCode AND "ItemCode" IN (SELECT "ItemCode" FROM "U_COILV" WHERE "FcCode"=:FcCode
				AND "iLevel"=2);
	INSERT INTO MTC_COST_0303_INVNTLIST(
	"BPLId","FcCode","ItemCode","ItemName"
	,"ObjType","TransCode","SourceMemo"
	,"Qty","Price","Amt")
	SELECT 0,T0."FcCode",T0."ItemCode",T0."ItemName"
	,T0."ObjType",T0."TransCode",'生产入库金额iLevel=2'
	,SUM(T0."Quantity") AS "In_Qty",SUM(T0."Amount")/NULLIF(SUM(T0."Quantity"),0),SUM(ROUND(T0."Amount",2)) AS "In_Amount"
	FROM "MTC_COST_0302_INVNTDETAIL1" T0
	JOIN U_COILV T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T0."FcCode"=:FcCode
	AND T1."iLevel"=2
	GROUP BY T0."FcCode",T0."ItemCode",T0."ItemName",T0."CostCode",T0."ObjType",T0."TransCode";
	/*
	--增加对其他的处理(将其他收货的价格写入到销售退货)
	UPDATE T0
	SET T0."Price"=IFNULL(T1."Price",0),T0."Amt"=T0."Qty"*IFNULL(T1."Price",0)
	,T0."SourceMemo"='从生产入库金额iLevel=2的59收货写入'
	FROM MTC_COST_0303_INVNTLIST T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amt")/NULLIF(SUM("Qty"),0) AS "Price"
			FROM MTC_COST_0303_INVNTLIST WHERE "ObjType"='59' AND "TransCode" NOT IN ('59-304','59-208')
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND (T0."ObjType" = '16' OR (T0."ObjType"='59' AND "TransCode" IN ('59-304','59-208')))  --59-208其他入库 59-304生产退料
	AND T2."iLevel"=2
	;
	
	
	--增加对其他的处理(204形态转换入库)
	UPDATE T0
	SET T0."Price"=IFNULL(T1."Price",0),T0."Amt"=T0."Qty"*IFNULL(T1."Price",0)
	,T0."SourceMemo"='从生产入库金额iLevel=2的59收货写入(形态转换)'
	FROM MTC_COST_0303_INVNTLIST T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amt")/NULLIF(SUM("Qty"),0) AS "Price"
			FROM MTC_COST_0303_INVNTLIST WHERE "ObjType"='59' AND "TransCode"='59-321'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND T0."TransCode"='59-204'  --59-208其他入库 59-304生产退料 204形态转换入库
	AND T0."Price"=0
	AND T2."iLevel"=2
	;*/
	--
	UPDATE T0 SET T0."Price"=ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6)
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level2.11写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Qty") AS "Qty",SUM("Amt") AS "Amt"
    		FROM "MTC_COST_0303_INVNTLIST"
    		WHERE "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=2
	AND T0."FcCode"=:FcCode	--20材料
    ;
    
    
    --补充
	 UPDATE T0 SET T0."Price"=
	 CASE WHEN IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)=0
	 THEN ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."IN_Amount",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."IN_QTY",0)),0),6)
	 ELSE ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6) END
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level2.12写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Quantity") AS "Qty",SUM("Amount") AS "Amt"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Quantity" ELSE 0 END) AS "IN_QTY"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Amount" ELSE 0 END) AS "IN_Amount"
    		FROM "MTC_COST_0302_INVNTDETAIL1" T1
			LEFT JOIN "@MTC_COST_IOTYPE" T2 ON T1."TransCode"=T2."Code"
    		WHERE 1=1 AND IFNULL("IsUpdatePrice",'')<>''
    		--AND "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=2
	AND T0."FcCode"=:FcCode	--20材料
    ;
    
    --更新写入价格至MTC_COST_0302_INVNTDETAIL1
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel2写入(O03、O09)'
   	,T0."IsUpdatePrice"='PP20'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN MTC_COST_0301_INVNT T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T1."CostCode"='20'
	AND T0."TransCode" IN ('O03','O09','O07','O08')  --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=2
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;
	/* 2026.2.8修改之前
    --将价格写入下一环节的生产订单
	UPDATE T1 
	SET  T1."Price"=T4."Price",T1."Amount"=T1."IgeQty"*T4."Price"
	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel2.02写入'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN MTC_COST_0321_OWOR T0 ON T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	JOIN U_COILV T2 ON T0."ItemCode"=T2."ItemCode" AND T0."FcCode"=T2."FcCode"		--主件
	JOIN U_COILV T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode"		--子件
	JOIN MTC_COST_0301_INVNT T4 ON T1."ItemCode"=T4."ItemCode" AND T1."FcCode"=T4."FcCode"
	WHERE 1=1 AND T4."CostCode"='20'
	--AND T2."iLevel"=3
	AND T3."iLevel"=2
	AND T0."FcCode"=:FcCode
	AND IFNULL(T1."IsUpdatePrice",'')=''
	;
    */
	 --写入生产订单明细 2026.2.8修改从出入库明细里取
   	UPDATE T1 SET 
   	 T1."Price"=T3."IgeAmt"/NULLIF(T1."IgeQty",0)
   	,T1."Amount"=T3."IgeAmt"
   	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel2.02写入new Line=840'
   	--,T1."IsUpdatePrice"='1001'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN U_COILV T2 ON T1."ItemCode"=T2."ItemCode" AND T1."FcCode"=T2."FcCode"
	JOIN (SELECT "FcCode","BaseType","BaseEntry","BaseLine","ItemCode",SUM(ROUND("Amount",2)) AS "IgeAmt"
			FROM MTC_COST_0302_INVNTDETAIL1
			WHERE "TransCode" IN ('O03','O07','O08','O09') --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
			GROUP BY "FcCode","BaseType","BaseEntry","BaseLine","ItemCode"
		) T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode" AND T1."DocType"=T3."BaseType"
				AND T1."WorEntry"=T3."BaseEntry" AND T1."LineNum"=T3."BaseLine"
	WHERE 1=1
	AND T1."FcCode"=:FcCode
	AND T2."iLevel"=2
	AND IFNULL(T1."IsUpdatePrice",'')=''
	--WHERE T2."ItmsGrpCod"='103'
	--AND T2."ItemCode"='102000866'	
	;
	
    ----------------------------------------------------iLevel = 3 -------------------------------------------
	--1.计算成本

	  --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=ROUND(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0),2)
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Level2—1写入'
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."DocType",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON T0."DocType"=T1."DocType" AND T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."DocType",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T0."DocType",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T0."DocType"=T2."DocType" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T0."DocType",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."DocType"=T3."DocType" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=2
	AND T0."DocType"='MTC_OWOR'
	AND T0."FcCode"=:FcCode;

	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,2,'');
	
	--chrlis.li 2026.3.6有返工单自己加工自己的情况 返工单号287#、288#、289#
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level2.11写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorType","WorEntry","WorNum","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T1."WorType"='30'	--返工单
	--AND IFNULL(T0."TransCode",'') NOT IN ('59-305')	--305生产报废不参与
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=2
	--AND T1."WorNum" IN (287,288,289,292,293,294,295,296,297,298)
	--AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	
    --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON  T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=3
	AND T0."FcCode"=:FcCode;
	
	--2.写入考虑了前期已投入的成品写入MTC_COST_0321_OWOR_SUM
	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,3,'');
	--CALL MTC_COST_PROC_0402_CAL_OWOR_WW(:BPLId,:FcCode,:UserCode,3,'');
   
   
   
	--iLevel = 3的入库明细MTC_COST_0302_INVNTDETAIL1（将iLevel=3的产成品的成本写入入库明细）
	--从考虑了在产品的累计生产订单的成本MTC_COST_0321_OWOR_SUM
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level3.11写入 Line=936'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorEntry","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	--AND T0."ObjType" IN ('59','16','60')
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=3
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	
	--------
	/*待验证
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	FROM MTC_COST_0302_INVNTDETAIL1 T0
    JOIN MTC_COST_0210_QCPRICE T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND (T0."ObjType" = '16' OR (T0."ObjType"='59' AND "TransCode" IN ('59-304','59-208')))  --59-208其他入库 59-304生产退料
	AND T0."FcCode"=:FcCode
	AND T0."Price"=0
	AND T2."iLevel"=3
	AND 1=0
	;	
	--对生产退货60-I03
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level3.21写入'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amount")/NULLIF(SUM("Quantity"),0) AS "Price"
			FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20' AND "ObjType"='59' AND "TransCode"='I03'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."ObjType"='60'
	AND T0."TransCode" IN ('I03')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=3
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;*/
	
	--iLevel = 3的入库列表MTC_COST_0303_INVNTLIST（作为入库的加权计算依据）
	--
	DELETE FROM MTC_COST_0303_INVNTLIST WHERE "FcCode"=:FcCode AND "ItemCode" IN (SELECT "ItemCode" FROM "U_COILV" WHERE "FcCode"=:FcCode
				AND "iLevel"=3);
	INSERT INTO MTC_COST_0303_INVNTLIST(
	"BPLId","FcCode","ItemCode","ItemName"
	,"ObjType"
	,"TransCode"
	,"SourceMemo"
	,"Qty","Price","Amt")
	SELECT 0,T0."FcCode",T0."ItemCode",T0."ItemName"
	,T0."ObjType"
	,T0."TransCode",'生产入库金额iLevel=3'
	,(T0."Quantity") AS "In_Qty",(T0."Amount")/NULLIF((T0."Quantity"),0),ROUND(T0."Amount",2) AS "In_Amount"
	FROM "MTC_COST_0302_INVNTDETAIL1" T0
	JOIN U_COILV T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	WHERE 1=1
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T0."FcCode"=:FcCode
	AND T1."iLevel"=3;
	
	/*待验证
	--增加对其他的处理(将其他收货的价格写入到销售退货)
	UPDATE T0
	SET T0."Price"=IFNULL(T1."Price",0),T0."Amt"=T0."Qty"*IFNULL(T1."Price",0)
	,T0."SourceMemo"='从生产入库金额iLevel=3的59收货写入'
	FROM MTC_COST_0303_INVNTLIST T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amt")/NULLIF(SUM("Qty"),0) AS "Price"
			FROM MTC_COST_0303_INVNTLIST WHERE "ObjType"='59' AND "TransCode" NOT IN ('59-304','59-208')
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND (T0."ObjType" = '16' OR (T0."ObjType"='59' AND "TransCode" IN ('59-304','59-208')))  --59-208其他入库 59-304生产退料
	AND T2."iLevel"=3
	;
	
	
	--增加对其他的处理(204形态转换入库)
	UPDATE T0
	SET T0."Price"=IFNULL(T1."Price",0),T0."Amt"=T0."Qty"*IFNULL(T1."Price",0)
	,T0."SourceMemo"='从生产入库金额iLevel=3的59收货写入(形态转换)'
	FROM MTC_COST_0303_INVNTLIST T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amt")/NULLIF(SUM("Qty"),0) AS "Price"
			FROM MTC_COST_0303_INVNTLIST WHERE "ObjType"='59' AND "TransCode"='59-321'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND T0."TransCode" IN ('59-204','59-203')  --59-208其他入库 59-304生产退料 204形态转换入库  59-203是辅料退货
	AND T0."Price"=0
	AND T2."iLevel"=3
	;*/
	
	--更新价格到MTC_COST_0301_INVNT，作为期初+入库=期末的加权价
	UPDATE T0 SET T0."Price"=ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6)
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level3.11写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Qty") AS "Qty",SUM("Amt") AS "Amt"
    		FROM "MTC_COST_0303_INVNTLIST"
    		WHERE "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=3
	AND T0."FcCode"=:FcCode	--20材料
    ;
    
    --补充
	 UPDATE T0 SET T0."Price"=
	 CASE WHEN IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)=0
	 THEN ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."IN_Amount",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."IN_QTY",0)),0),6)
	 ELSE ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6) END
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level3.12写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Quantity") AS "Qty",SUM("Amount") AS "Amt"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Quantity" ELSE 0 END) AS "IN_QTY"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Amount" ELSE 0 END) AS "IN_Amount"
    		FROM "MTC_COST_0302_INVNTDETAIL1" T1
			LEFT JOIN "@MTC_COST_IOTYPE" T2 ON T1."TransCode"=T2."Code"
    		WHERE 1=1 AND IFNULL("IsUpdatePrice",'')<>''
    		--AND "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=3
	AND T0."FcCode"=:FcCode	--20材料
    ;
    
    --更新写入价格至MTC_COST_0302_INVNTDETAIL1
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel3写入(O03、O09)'
   	,T0."IsUpdatePrice"='PP30'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN MTC_COST_0301_INVNT T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T1."CostCode"='20'
	AND T0."TransCode" IN ('O03','O09','O07','O08')  --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=3
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;
	
	/* 2026.2.8 修改之前
    --将iLevel=3的物料作为子件，价格写入下一环节的生产订单
	UPDATE T1 
	SET  T1."Price"=T4."Price",T1."Amount"=T1."IgeQty"*T4."Price"
	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel3.03写入'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN MTC_COST_0321_OWOR T0 ON T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	JOIN U_COILV T2 ON T0."ItemCode"=T2."ItemCode" AND T0."FcCode"=T2."FcCode"		--主件
	JOIN U_COILV T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode"		--子件
	JOIN MTC_COST_0301_INVNT T4 ON T1."ItemCode"=T4."ItemCode" AND T1."FcCode"=T4."FcCode"
	WHERE 1=1 AND T4."CostCode"='20'
	--AND T2."iLevel"=3
	AND T3."iLevel"=3
	AND T0."FcCode"=:FcCode
	AND IFNULL(T1."IsUpdatePrice",'')=''
	;*/
	
	
	 --写入生产订单明细 2026.2.8修改从出入库明细里取
   	UPDATE T1 SET 
   	 T1."Price"=T3."IgeAmt"/NULLIF(T1."IgeQty",0)
   	,T1."Amount"=T3."IgeAmt"
   	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel3.03写入new Line=1108'
   	--,T1."IsUpdatePrice"='1001'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN U_COILV T2 ON T1."ItemCode"=T2."ItemCode" AND T1."FcCode"=T2."FcCode"
	JOIN (SELECT "FcCode","BaseType","BaseEntry","BaseLine","ItemCode",SUM("Amount") AS "IgeAmt"
			FROM MTC_COST_0302_INVNTDETAIL1
			WHERE "TransCode" IN ('O03','O07','O08','O09') --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
			GROUP BY "FcCode","BaseType","BaseEntry","BaseLine","ItemCode"
		) T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode" AND T1."DocType"=T3."BaseType"
				AND T1."WorEntry"=T3."BaseEntry" AND T1."LineNum"=T3."BaseLine"
	WHERE 1=1
	AND T1."FcCode"=:FcCode
	AND T2."iLevel"=3
	AND IFNULL(T1."IsUpdatePrice",'')=''
	--WHERE T2."ItmsGrpCod"='103'
	--AND T2."ItemCode"='102000866'	
	;
    ----------------------------------------------------iLevel = 4 -------------------------------------------

   --1.计算成本

	  --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Level3—1写入'
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."DocType",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON T0."DocType"=T1."DocType" AND T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."DocType",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T0."DocType",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T0."DocType"=T2."DocType" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T0."DocType",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."DocType"=T3."DocType" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=3
	AND T0."DocType"='MTC_OWOR'
	AND T0."FcCode"=:FcCode;

	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,3,'');
	
	--chrlis.li 2026.3.6有返工单自己加工自己的情况 返工单号287#、288#、289#
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level2.11写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorType","WorEntry","WorNum","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	--AND IFNULL(T0."TransCode",'') NOT IN ('59-305')	--305生产报废不参与
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=3
	AND T1."WorType"='30'
	--AND T1."WorNum" IN (287,288,289,292,293,294,295,296,297,298)
	--AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
    --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON  T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=4
	AND T0."FcCode"=:FcCode;
   
	--2.写入考虑了前期已投入的成品写入MTC_COST_0321_OWOR_SUM
	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,4,'');
	--CALL MTC_COST_PROC_0402_CAL_OWOR_WW(:BPLId,:FcCode,:UserCode,4,'');
   
	--iLevel = 4的入库明细
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level4.11写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorEntry","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=4
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	
	--------
	/*
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	FROM MTC_COST_0302_INVNTDETAIL1 T0
    JOIN MTC_COST_0210_QCPRICE T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND (T0."ObjType" = '16' OR (T0."ObjType"='59' AND "TransCode" IN ('59-304','59-208')))  --59-208其他入库 59-304生产退料
	AND T0."FcCode"=:FcCode
	AND T0."Price"=0
	AND T2."iLevel"=4
	;	
	
	--对生产退货60-I03
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level4.21写入'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amount")/NULLIF(SUM("Quantity"),0) AS "Price"
			FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20' AND "ObjType"='59' AND "TransCode"='I03'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."ObjType"='60'
	AND T0."TransCode" IN ('I03')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=4
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;*/
	
	--iLevel = 4的入库列表
	DELETE FROM MTC_COST_0303_INVNTLIST WHERE "FcCode"=:FcCode AND "ItemCode" IN (SELECT "ItemCode" FROM "U_COILV" WHERE "FcCode"=:FcCode
				AND "iLevel"=4);
	INSERT INTO MTC_COST_0303_INVNTLIST(
	"BPLId","FcCode","ItemCode","ItemName"
	,"ObjType","TransCode","SourceMemo"
	,"Qty","Price","Amt")
	SELECT 0,T0."FcCode",T0."ItemCode",T0."ItemName"
	,T0."ObjType",T0."TransCode",'生产入库金额iLevel=4,'||T0."DocNum"
	,(T0."Quantity") AS "In_Qty",(T0."Amount")/NULLIF((T0."Quantity"),0),(T0."Amount") AS "In_Amount"
	FROM "MTC_COST_0302_INVNTDETAIL1" T0
	JOIN U_COILV T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T0."FcCode"=:FcCode
	AND T1."iLevel"=4;
	
	--
	/*待验证
	--增加对其他的处理(将其他收货的价格写入到销售退货)
	UPDATE T0
	SET T0."Price"=IFNULL(T1."Price",0),T0."Amt"=T0."Qty"*IFNULL(T1."Price",0)
	,T0."SourceMemo"='从生产入库金额iLevel=4的59收货写入'
	FROM MTC_COST_0303_INVNTLIST T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amt")/NULLIF(SUM("Qty"),0) AS "Price"
			FROM MTC_COST_0303_INVNTLIST WHERE "ObjType"='59' AND "TransCode" NOT IN ('59-304','59-208')
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND (T0."ObjType" = '16' OR (T0."ObjType"='59' AND "TransCode" IN ('59-304','59-208')))  --59-208其他入库 59-304生产退料
	AND T2."iLevel"=4
	;
	
	
	--增加对其他的处理(204形态转换入库)
	UPDATE T0
	SET T0."Price"=IFNULL(T1."Price",0),T0."Amt"=T0."Qty"*IFNULL(T1."Price",0)
	,T0."SourceMemo"='从生产入库金额iLevel=4的59收货写入(形态转换)'
	FROM MTC_COST_0303_INVNTLIST T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amt")/NULLIF(SUM("Qty"),0) AS "Price"
			FROM MTC_COST_0303_INVNTLIST WHERE "ObjType"='59' AND "TransCode"='59-321'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND T0."TransCode"='59-204'  --59-208其他入库 59-304生产退料 204形态转换入库
	AND T0."Price"=0
	AND T2."iLevel"=4
	;*/
	--
	UPDATE T0 SET T0."Price"=ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6)
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level4.11写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Qty") AS "Qty",SUM("Amt") AS "Amt"
    		FROM "MTC_COST_0303_INVNTLIST"
    		WHERE "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=4
	AND T0."FcCode"=:FcCode	--20材料
    ;
    --补充
	 UPDATE T0 SET T0."Price"=
	 CASE WHEN IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)=0
	 THEN ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."IN_Amount",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."IN_QTY",0)),0),6)
	 ELSE ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6) END
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level4.12写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Quantity") AS "Qty",SUM("Amount") AS "Amt"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Quantity" ELSE 0 END) AS "IN_QTY"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Amount" ELSE 0 END) AS "IN_Amount"
    		FROM "MTC_COST_0302_INVNTDETAIL1" T1
			LEFT JOIN "@MTC_COST_IOTYPE" T2 ON T1."TransCode"=T2."Code"
    		WHERE 1=1 AND IFNULL("IsUpdatePrice",'')<>''
    		--AND "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=4
	AND T0."FcCode"=:FcCode	--20材料
    ;
    
    --更新写入价格至MTC_COST_0302_INVNTDETAIL1
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel4写入(O03、O09)'
   	,T0."IsUpdatePrice"='PP40'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN MTC_COST_0301_INVNT T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T1."CostCode"='20'
	AND T0."TransCode" IN ('O03','O09','O07','O08')  --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=4
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;
    /* 2026.2.8
    --将价格写入下一环节的生产订单
	UPDATE T1 
	SET  T1."Price"=T4."Price",T1."Amount"=T1."IgeQty"*T4."Price"
	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel4.01写入'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN MTC_COST_0321_OWOR T0 ON T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	JOIN U_COILV T2 ON T0."ItemCode"=T2."ItemCode" AND T0."FcCode"=T2."FcCode"		--主件
	JOIN U_COILV T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode"		--子件
	JOIN MTC_COST_0301_INVNT T4 ON T1."ItemCode"=T4."ItemCode" AND T1."FcCode"=T4."FcCode"
	WHERE 1=1 AND T4."CostCode"='20'
	--AND T2."iLevel"=3
	AND T3."iLevel"=4
	AND T0."FcCode"=:FcCode
	AND IFNULL(T1."IsUpdatePrice",'')=''
	;*/
	
	
	 --写入生产订单明细 2026.2.8修改从出入库明细里取
   	UPDATE T1 SET 
   	 T1."Price"=T3."IgeAmt"/NULLIF(T1."IgeQty",0)
   	,T1."Amount"=T3."IgeAmt"
   	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel4.01写入new Line=1363'
   	--,T1."IsUpdatePrice"='1001'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN U_COILV T2 ON T1."ItemCode"=T2."ItemCode" AND T1."FcCode"=T2."FcCode"
	JOIN (SELECT "FcCode","BaseType","BaseEntry","BaseLine","ItemCode",SUM("Amount") AS "IgeAmt"
			FROM MTC_COST_0302_INVNTDETAIL1
			WHERE "TransCode" IN ('O03','O07','O08','O09') --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
			GROUP BY "FcCode","BaseType","BaseEntry","BaseLine","ItemCode"
		) T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode" AND T1."DocType"=T3."BaseType"
				AND T1."WorEntry"=T3."BaseEntry" AND T1."LineNum"=T3."BaseLine"
	WHERE 1=1
	AND T1."FcCode"=:FcCode
	AND T2."iLevel"=4
	AND IFNULL(T1."IsUpdatePrice",'')=''
	--WHERE T2."ItmsGrpCod"='103'
	--AND T2."ItemCode"='102000866'	
	;
	
    ----------------------------------------------------iLevel = 5 -------------------------------------------
	--1.计算成本

	  --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Level4—1写入'
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."DocType",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON T0."DocType"=T1."DocType" AND T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."DocType",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T0."DocType",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T0."DocType"=T2."DocType" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T0."DocType",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."DocType"=T3."DocType" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=4
	AND T0."DocType"='MTC_OWOR'
	AND T0."FcCode"=:FcCode;

	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,4,'');
    --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON  T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=5
	AND T0."FcCode"=:FcCode;
	
	--2.写入考虑了前期已投入的成品写入MTC_COST_0321_OWOR_SUM
	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,5,'');
	--CALL MTC_COST_PROC_0402_CAL_OWOR_WW(:BPLId,:FcCode,:UserCode,5,'');
	
	--iLevel = 5入库明细
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level5.11写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorEntry","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=5
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	/*
	--对生产退货60-I03
	UPDATE T0 SET T0."Amount"=T0."Quantity"*T1."Price",T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level5.21写入'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amount")/NULLIF(SUM("Quantity"),0) AS "Price"
			FROM MTC_COST_0302_INVNTDETAIL1 WHERE "CostCode"='20' AND "ObjType"='59' AND "TransCode"='I03'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."ObjType"='60'
	AND T0."TransCode" IN ('I03')
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=5
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;*/
	
	--iLevel = 5的入库列表
	DELETE FROM MTC_COST_0303_INVNTLIST WHERE "FcCode"=:FcCode AND "ItemCode" IN (SELECT "ItemCode" FROM "U_COILV" WHERE "FcCode"=:FcCode
				AND "iLevel"=5);
	INSERT INTO MTC_COST_0303_INVNTLIST(
	"BPLId","FcCode","ItemCode","ItemName"
	,"ObjType","TransCode","SourceMemo"
	,"Qty","Price","Amt")
	SELECT 0,T0."FcCode",T0."ItemCode",T0."ItemName"
	,T0."ObjType",T0."TransCode",'生产入库金额iLevel=5'
	,SUM(T0."Quantity") AS "In_Qty",SUM(T0."Amount")/NULLIF(SUM(T0."Quantity"),0),SUM(T0."Amount") AS "In_Amount"
	FROM "MTC_COST_0302_INVNTDETAIL1" T0
	JOIN U_COILV T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T0."FcCode"=:FcCode
	AND T1."iLevel"=5
	GROUP BY T0."FcCode",T0."ItemCode",T0."ItemName",T0."CostCode",T0."ObjType",T0."TransCode";
	
	/*待验证
	--增加对其他的处理(将其他收货的价格写入到销售退货)
	UPDATE T0
	SET T0."Price"=IFNULL(T1."Price",0),T0."Amt"=T0."Qty"*IFNULL(T1."Price",0)
	,T0."SourceMemo"='从生产入库金额iLevel=5的59收货写入'
	FROM MTC_COST_0303_INVNTLIST T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amt")/NULLIF(SUM("Qty"),0) AS "Price"
			FROM MTC_COST_0303_INVNTLIST WHERE "ObjType"='59' AND "TransCode" NOT IN ('59-304','59-208')
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND (T0."ObjType" = '16' OR (T0."ObjType"='59' AND "TransCode" IN ('59-304','59-208')))  --59-208其他入库 59-304生产退料
	AND T2."iLevel"=5
	;
	
	--增加对其他的处理(204形态转换入库)
	UPDATE T0
	SET T0."Price"=IFNULL(T1."Price",0),T0."Amt"=T0."Qty"*IFNULL(T1."Price",0)
	,T0."SourceMemo"='从生产入库金额iLevel=5的59收货写入(形态转换)'
	FROM MTC_COST_0303_INVNTLIST T0
	JOIN (SELECT "FcCode","ItemCode",SUM("Amt")/NULLIF(SUM("Qty"),0) AS "Price"
			FROM MTC_COST_0303_INVNTLIST WHERE "ObjType"='59' AND "TransCode"='59-321'
			GROUP BY "FcCode","ItemCode") T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."FcCode"=:FcCode
	AND T0."TransCode"='59-204'  --59-208其他入库 59-304生产退料 204形态转换入库
	AND T0."Price"=0
	AND T2."iLevel"=5
	;*/
	--更新截止目前的入库单价
	UPDATE T0 SET T0."Price"=ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6)
   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level5.11写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Qty") AS "Qty",SUM("Amt") AS "Amt"
    		FROM "MTC_COST_0303_INVNTLIST"
    		WHERE "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=5
	AND T0."FcCode"=:FcCode	--20材料
    ;
    
    --补充
	 UPDATE T0 SET T0."Price"=
	 CASE WHEN IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)=0
	 THEN ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."IN_Amount",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."IN_QTY",0)),0),6)
	 ELSE ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6) END
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level5.12写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT "BPLId","FcCode","ItemCode",SUM("Quantity") AS "Qty",SUM("Amount") AS "Amt"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Quantity" ELSE 0 END) AS "IN_QTY"
    		,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Amount" ELSE 0 END) AS "IN_Amount"
    		FROM "MTC_COST_0302_INVNTDETAIL1" T1
			LEFT JOIN "@MTC_COST_IOTYPE" T2 ON T1."TransCode"=T2."Code"
    		WHERE 1=1 AND IFNULL("IsUpdatePrice",'')<>''
    		--AND "TransCode" IN ('I01','I03','I07','I08','I09')
    		GROUP BY "BPLId","FcCode","ItemCode"
    	) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
    WHERE T0."CostCode"='20'
	AND T2."iLevel"=5
	AND T0."FcCode"=:FcCode	--20材料
    ;
    --更新写入价格至MTC_COST_0302_INVNTDETAIL1
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel5写入(O03、O09)'
   	,T0."IsUpdatePrice"='PP50'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN MTC_COST_0301_INVNT T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T1."CostCode"='20'
	AND T0."TransCode" IN ('O03','O09','O07','O08')  --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=5
	AND IFNULL(T0."IsUpdatePrice",'')=''
	;
	/*
    --将价格写入下一环节的生产订单 2026.2.8修改之前
	UPDATE T1 
	SET  T1."Price"=T4."Price",T1."Amount"=T1."IgeQty"*T4."Price"
	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel5.01写入'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN MTC_COST_0321_OWOR T0 ON T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry"
	JOIN U_COILV T2 ON T0."ItemCode"=T2."ItemCode" AND T0."FcCode"=T2."FcCode"		--主件
	JOIN U_COILV T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode"		--子件
	JOIN MTC_COST_0301_INVNT T4 ON T1."ItemCode"=T4."ItemCode" AND T1."FcCode"=T4."FcCode"
	WHERE 1=1 AND T4."CostCode"='20'
	--AND T2."iLevel"=3
	AND T3."iLevel"=5
	AND T0."FcCode"=:FcCode
	AND IFNULL(T1."IsUpdatePrice",'')=''
	;*/
	
	 --写入生产订单明细 2026.2.8修改从出入库明细里取
   	UPDATE T1 SET 
   	 T1."Price"=T3."IgeAmt"/NULLIF(T1."IgeQty",0)
   	,T1."Amount"=T3."IgeAmt"
   	,T1."PriceMemo"=IFNULL(T1."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.iLevel5.01写入new Line=1603'
   	--,T1."IsUpdatePrice"='1001'
	FROM MTC_COST_0321_OWOR1 T1
	JOIN U_COILV T2 ON T1."ItemCode"=T2."ItemCode" AND T1."FcCode"=T2."FcCode"
	JOIN (SELECT "FcCode","BaseType","BaseEntry","BaseLine","ItemCode",SUM("Amount") AS "IgeAmt"
			FROM MTC_COST_0302_INVNTDETAIL1
			WHERE "TransCode" IN ('O03','O07','O08','O09') --O03 生产发料 O09委外出库  O07生产返工领料  O08委外返工领料  2026.2.8增加O07、O08
			GROUP BY "FcCode","BaseType","BaseEntry","BaseLine","ItemCode"
		) T3 ON T1."ItemCode"=T3."ItemCode" AND T1."FcCode"=T3."FcCode" AND T1."DocType"=T3."BaseType"
				AND T1."WorEntry"=T3."BaseEntry" AND T1."LineNum"=T3."BaseLine"
	WHERE 1=1
	AND T1."FcCode"=:FcCode
	AND T2."iLevel"=5
	AND IFNULL(T1."IsUpdatePrice",'')=''
	--WHERE T2."ItmsGrpCod"='103'
	--AND T2."ItemCode"='102000866'	
	;
	
	
	  --写入当月成本只当月的MTC_COST_0321_OWOR
	 UPDATE T0 SET T0."Amount"=(IFNULL(T1."Amount",0)+IFNULL(T3."Amount",0))
	,T0."1Material"=T1."Amount"
	,T0."2ManExp"=T3."2ManExp"
	,T0."3LabAmount"=T3."3LabAmount"
	,T0."4WWExp"=T3."4ExpAmt"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.Level5—1写入'
	FROM MTC_COST_0321_OWOR T0
	--材料费用
	LEFT JOIN (
			SELECT T1."BPLId",:FcCode AS "FcCode",T1."DocType",T1."WorEntry",SUM(T1."IgeQty") AS "IgeQty"
			,-1*SUM(T1."Amount") AS "Amount"
			--,SUM(T1."Amount"/NULLIF(T1."IgeQty",0)*T0."IgnQty") AS "Amount"
			FROM MTC_COST_0321_OWOR1 T1
			JOIN MTC_COST_0321_OWOR T0 ON T0."DocType"=T1."DocType" AND T1."WorEntry"=T0."WorEntry" AND T0."FcCode"=T1."FcCode"
			WHERE T1."FcCode"=:FcCode GROUP BY T1."BPLId",T1."DocType",T1."WorEntry"
		) T1 ON T0."BPLId"=T1."BPLId" AND T0."FcCode"=T1."FcCode" AND T0."DocType"=T1."DocType" AND T0."WorEntry"=T1."WorEntry"
	--制造费用+人工费用+委外费用
	LEFT JOIN (
			SELECT T2."BPLId",:FcCode AS "FcCode",T0."DocType",T2."WorEntry"
			,-1*SUM(T2."Amount") AS "Amount"
			,-1*SUM(CASE WHEN T2."CostCode"='20' THEN T2."Amount" ELSE 0 END) AS "4ExpAmt" --20委外
			,-1*SUM(CASE WHEN T2."CostCode"='30' THEN T2."Amount" ELSE 0 END) AS "3LabAmount"	--30制造费用
			,-1*SUM(CASE WHEN T2."CostCode"='40' THEN T2."Amount" ELSE 0 END) AS "2ManExp"	--40人工费用
			FROM MTC_COST_0321_OWOR2 T2
			JOIN MTC_COST_0321_OWOR T0 ON T2."FcCode"=T0."FcCode" AND T0."DocType"=T2."DocType" AND T2."WorEntry"=T0."WorEntry"
			WHERE T2."FcCode"=:FcCode GROUP BY T2."BPLId",T0."DocType",T2."WorEntry"
		) T3 ON T0."BPLId"=T3."BPLId" AND T0."FcCode"=T3."FcCode" AND T0."DocType"=T3."DocType" AND T0."WorEntry"=T3."WorEntry"
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode"
	WHERE T2."iLevel"=5
	AND T0."DocType"='MTC_OWOR'
	AND T0."FcCode"=:FcCode;

	CALL MTC_COST_PROC_0402_CAL_OWOR(:BPLId,:FcCode,:UserCode,5,'');
	
	--------------------------------END-----------------------------------
	
	--SELECT * FROM "MTC_COST_0301_INVNT" WHERE "FcCode"=:FcCode AND "ItemCode"='FH1138901';
	
	
	----------------------------返工单-----------------------------
	--level=1
	CALL MTC_COST_PROC_0402_CAL_OWOR_30(:BPLId,:FcCode,:UserCode,1,'');
	
	--chrlis.li 2026.3.6有返工单自己加工自己的情况 返工单号287#、288#、289#
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level9.1写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorType","WorEntry","WorNum","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T1."WorType"='30'	--返工单
	--AND IFNULL(T0."TransCode",'') NOT IN ('59-305')	--305生产报废不参与
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=1
	--AND T1."WorNum" IN (287,288,289,292,293,294,295,296,297,298)
	--AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	
	--level=2

	CALL MTC_COST_PROC_0402_CAL_OWOR_30(:BPLId,:FcCode,:UserCode,2,'');
	
	--chrlis.li 2026.3.6有返工单自己加工自己的情况 返工单号287#、288#、289#
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level9.2写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorType","WorEntry","WorNum","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T1."WorType"='30'	--返工单
	--AND IFNULL(T0."TransCode",'') NOT IN ('59-305')	--305生产报废不参与
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=2
	--AND T1."WorNum" IN (287,288,289,292,293,294,295,296,297,298)
	--AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	
	--level=3

	CALL MTC_COST_PROC_0402_CAL_OWOR_30(:BPLId,:FcCode,:UserCode,3,'');
	
	--chrlis.li 2026.3.6有返工单自己加工自己的情况 返工单号287#、288#、289#
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level9.3写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorType","WorEntry","WorNum","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T1."WorType"='30'	--返工单
	--AND IFNULL(T0."TransCode",'') NOT IN ('59-305')	--305生产报废不参与
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=3
	--AND T1."WorNum" IN (287,288,289,292,293,294,295,296,297,298)
	--AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	
	--level=4

	CALL MTC_COST_PROC_0402_CAL_OWOR_30(:BPLId,:FcCode,:UserCode,4,'');
	
	--chrlis.li 2026.3.6有返工单自己加工自己的情况 返工单号287#、288#、289#
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level9.4写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorType","WorEntry","WorNum","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T1."WorType"='30'	--返工单
	--AND IFNULL(T0."TransCode",'') NOT IN ('59-305')	--305生产报废不参与
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=4
	--AND T1."WorNum" IN (287,288,289,292,293,294,295,296,297,298)
	--AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	--level=5
	CALL MTC_COST_PROC_0402_CAL_OWOR_30(:BPLId,:FcCode,:UserCode,5,'');
	
	--chrlis.li 2026.3.6有返工单自己加工自己的情况 返工单号287#、288#、289#
	UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level9.5写入'
	,T0."IsUpdatePrice"='IN01'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN (SELECT "FcCode","WorType","WorEntry","WorNum","ItemCode","Price","DocType" FROM "MTC_COST_0321_OWOR_SUM"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
			AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry" AND T0."BaseLine" IS NULL
	JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
	WHERE T0."CostCode"='20'
	AND T0."TransCode" IN ('I03','I07','I08','I09')
	AND T1."WorType"='30'	--返工单
	--AND IFNULL(T0."TransCode",'') NOT IN ('59-305')	--305生产报废不参与
	AND T0."FcCode"=:FcCode
	AND T2."iLevel"=5
	--AND T1."WorNum" IN (287,288,289,292,293,294,295,296,297,298)
	--AND IFNULL(T0."IsUpdatePrice",'')=''
	;	
	----------------------------写入其他-----------------------------
	
	
	------chris.li20260927处理计算的尾差（工单的合计与入库单明细的差额）  ----------------
	TMP_DIFF=
	SELECT T0."FcCode",T0."ItemCode",T0."DocType",T0."WorEntry"
	,T0."Amount"			--工单的金额汇总
	,T1."TransAmount"		--每笔入库的金额
	,IFNULL(T0."Amount",0)-IFNULL(T1."TransAmount",0) AS "Diff" --差异金额
	FROM "MTC_COST_0321_OWOR_SUM" T0
	JOIN (SELECT "BaseType","BaseEntry","ItemCode","FcCode",SUM("Amount") AS "TransAmount"
			FROM "MTC_COST_0302_INVNTDETAIL1"
			WHERE "BaseLine" IS NULL
			AND "TransCode" IN ('I03','I07','I08','I09')
			AND "CostCode"='20'
			AND "FcCode"=:FcCode
			AND "BaseType" IN ('202','MTC_OWOR')
			GROUP BY "BaseType","BaseEntry","ItemCode","FcCode"
		) T1 ON T1."FcCode"=T0."FcCode" AND T1."ItemCode"=T0."ItemCode"
			AND T1."BaseType"=T0."DocType" AND T1."BaseEntry"=T0."WorEntry"
	WHERE 1=1;
	
	--处理尾差
	UPDATE T0 SET T0."Amount"=T0."Amount"+IFNULL(T1."Diff",0)
	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.9901尾差处理'
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	JOIN :TMP_DIFF T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
					     AND T0."BaseType"=T1."DocType" AND T0."BaseEntry"=T1."WorEntry"
	JOIN (SELECT "ID","FcCode","ItemCode","BaseType","BaseEntry","Amount"
				,ROW_NUMBER() OVER (PARTITION BY "FcCode","ItemCode","BaseType","BaseEntry" ORDER BY "Amount" DESC) AS "NUMID"
				FROM MTC_COST_0302_INVNTDETAIL1
				WHERE "FcCode" = :FcCode
				AND "BaseLine" IS NULL
				AND "TransCode" IN ('I03','I07','I08','I09')
				AND "CostCode"='20'
				AND "BaseType" IN ('202','MTC_OWOR')
			) T2 ON T0."ID"=T2."ID"
	WHERE 1=1
	--仅对差异小于等于2分钱的处理
	AND ABS(T1."Diff")<=0.02
	AND T0."FcCode"=:FcCode
	AND T2.NUMID=1;
	
	
	
	
	
	 	--更新写入价格至MTC_COST_0302_INVNTDETAIL1
		UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.9001写入(O01,O06)'
	   	,T0."IsUpdatePrice"='SD01'
		FROM MTC_COST_0302_INVNTDETAIL1 T0
		JOIN MTC_COST_0301_INVNT T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
		JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
		WHERE T1."CostCode"='20'
		AND T0."TransCode" IN ('O01','O06','O10')  --O01销售出库,O06销售退货,O10盘点出库
		AND T0."FcCode"=:FcCode
		AND IFNULL(T0."IsUpdatePrice",'')=''
		;
		
		
		
		--MTC_COST_0302_INVNTDETAIL1 销售退货金额为0的，进行再次处理
		UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."U_Price",2),T0."Price"=T1."U_Price"
	   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.9011写入(O06)'
	   	,T0."IsUpdatePrice"='SD03'
		FROM MTC_COST_0302_INVNTDETAIL1 T0
		JOIN (SELECT T0."DocEntry",T0."U_FcCode",T1."U_ItemCode",T1."U_Price"
				FROM "@MTC_COST_QCPRICE" T0
				JOIN "@MTC_COST_QCPRICE1" T1 ON T0."DocEntry"=T1."DocEntry"
				WHERE 1=1
			) T1 ON T0."FcCode"=T1."U_FcCode" AND T0."ItemCode"=T1."U_ItemCode"
		WHERE 1=1
		AND T0."TransCode" IN ('O06')  --O01销售出库,O06销售退货,O10盘点出库
		AND T0."FcCode"=:FcCode
		AND IFNULL(T0."Price",0)=0
		;
		
		--取消的交货单取原始单据的成本,DLN01是取消上期的，DLN02是取消本期的
		UPDATE T0 SET T0."Amount"=-1*T1."Amount",T0."Price"=T1."Price"
	   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.9002取消交货单写入'
	   	,T0."IsUpdatePrice"='DLN02'
		FROM "MTC_COST_0302_INVNTDETAIL1" T0
		JOIN "MTC_COST_0302_INVNTDETAIL1" T1 ON T0."BaseType"=T1."ObjType" AND T0."BaseEntry"=T1."DocEntry" AND T0."BaseLine"=T1."LineNum"
		WHERE 1=1
		AND T0."ObjType"='15'
		AND T0."FcCode"=:FcCode
		AND IFNULL(T0."IsUpdatePrice",'')<>'DLN01'
		;
		
		
		--取消的销售退货单取原始单据的成本,RD01是取消上期的，RD02是取消本期的
		UPDATE T0 SET T0."Amount"=-1*T1."Amount",T0."Price"=T1."Price"
	   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.9003取消退货单写入'
	   	,T0."IsUpdatePrice"='RD02'
		FROM "MTC_COST_0302_INVNTDETAIL1" T0
		JOIN "MTC_COST_0302_INVNTDETAIL1" T1 ON T0."BaseType"=T1."ObjType" AND T0."BaseEntry"=T1."DocEntry" AND T0."BaseLine"=T1."LineNum"
		WHERE 1=1
		AND T0."ObjType"='16'
		AND T0."FcCode"=:FcCode
		AND IFNULL(T0."IsUpdatePrice",'')<>'RD01'
		;
		
		
	 	--更新写入价格至MTC_COST_0302_INVNTDETAIL1
		UPDATE T0 SET T0."Amount"=ROUND(T0."Quantity"*T1."Price",2),T0."Price"=T1."Price"
	   	,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->'||'从MTC_COST_PROC_0401_CAL.9012写入(O01,O06)'
	   	,T0."IsUpdatePrice"='SD04'
		FROM MTC_COST_0302_INVNTDETAIL1 T0
		JOIN (SELECT "FcCode","ItemCode",SUM("Amount")/NULLIF(SUM("Quantity"),0) AS "Price" FROM MTC_COST_0302_INVNTDETAIL1
				WHERE "Quantity">0
				GROUP BY "FcCode","ItemCode"
				) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
		JOIN U_COILV T2 ON T0."FcCode"=T2."FcCode" AND T0."ItemCode"=T2."ItemCode" 
		WHERE 1=1
		AND T0."TransCode" IN ('O01','O06','O10')  --O01销售出库,O06销售退货,O10盘点出库
		AND T0."FcCode"=:FcCode
		AND IFNULL(T0."Price",0)=0
		;
		
		
	
	
	
	------------------------------结论处理---------------------
	--写入进销存列表（最终的加权单价）
    UPDATE T0 SET 
     T0."In_Amount"=ROUND(IFNULL(T1."In_Amt",0),2)
    ,T0."In_Price"=ROUND(IFNULL(T1."In_Amt",0)/NULLIF(IFNULL(T1."In_Qty",0),0),6)
    ,T0."Out_Amount"=ROUND(IFNULL(T1."Out_Amt",0),2)
    ,T0."Out_Price"=ROUND(IFNULL(T1."Out_Amt",0)/NULLIF(IFNULL(T1."Out_Qty",0),0),6)
    ,T0."QM_Amount"=ROUND(ROUND(IFNULL(T0."QC_Amount",0),2)+ROUND(IFNULL(T1."Amt",0),2),2)
    ,T0."Price"=ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF((IFNULL(T0."QC_Qty",0)+IFNULL(T1."Qty",0)),0),6)
    ,T0."QM_Price"=ROUND((IFNULL(T0."QC_Amount",0)+IFNULL(T1."Amt",0))/NULLIF(IFNULL(T0."QM_Qty",0),0),6)
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.91写入'
	FROM "MTC_COST_0301_INVNT" T0
    LEFT JOIN (SELECT T1."FcCode",T1."ItemCode"
			,SUM(T1."Quantity") AS "Qty"
			,SUM(T1."Amount") AS "Amt"
			,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Quantity" ELSE 0 END) AS "In_Qty"
			,SUM(CASE WHEN T2."U_IOType"='I' THEN T1."Amount" ELSE 0 END) AS "In_Amt"
			,SUM(CASE WHEN T2."U_IOType"='O' THEN -1*T1."Quantity" ELSE 0 END) AS "Out_Qty"
			,SUM(CASE WHEN T2."U_IOType"='O' THEN -1*T1."Amount" ELSE 0 END) AS "Out_Amt"
			FROM "MTC_COST_0302_INVNTDETAIL1" T1
			JOIN "@MTC_COST_IOTYPE" T2 ON T1."TransCode"=T2."Code"
			WHERE 1=1 AND T1."FcCode"=:FcCode-- AND T1."ItemCode"='102000095'
			GROUP BY T1."FcCode",T1."ItemCode"
    	) T1 ON T0."FcCode"=T1."FcCode" AND T0."ItemCode"=T1."ItemCode"
    WHERE T0."CostCode"='20'
	AND T0."FcCode"=:FcCode	--20材料
    ;
    /*
	--写入进销存列表的出库和结存单价（最终的加权单价）
    UPDATE T0 SET 
    T0."Out_Price"=T0."Price",T0."Out_Amount"=T0."Out_Qty"*T0."Price"
    ,T0."QM_Price"=T0."Price",T0."QM_Amount"=T0."QM_Qty"*T0."Price"
    ,T0."PriceMemo"=IFNULL(T0."PriceMemo",'')||'->从MTC_COST_PROC_0401_CAL.Level1.81写入'
    FROM "MTC_COST_0301_INVNT" T0
    WHERE T0."CostCode"='20'
	AND T0."FcCode"=:FcCode	--20材料
    ;*/
    /*
    
    UPDATE T0
    SET T0."AdjAmount"=T0."QM_Amount"
    ,T0."In_Amount"=IFNULL(T1."U_Dec3",0)-IFNULL(T0."In_Amount",0)
    ,T0."QM_Amount"=IFNULL(T1."U_Dec3",0)
    FROM "MTC_COST_0301_INVNT" T0
    JOIN
    	(    		
			
			SELECT 
			"U_Text1" AS "ItemCode"
			,"U_Dec3"
			FROM "@MTC_IMPT1" T1 
			WHERE T1."DocEntry"=7
    	) T1 ON T0."ItemCode"=T1."ItemCode"
    WHERE 1=1
    AND T0."FcCode"=:FcCode AND T0."CostCode"='20';
    
    UPDATE T0
    SET T0."QM_Price"=T0."QM_Amount"/NULLIF(T0."QM_Qty",0)
    ,T0."Price"=T0."QM_Amount"/NULLIF(T0."QM_Qty",0)
    FROM "MTC_COST_0301_INVNT" T0
    JOIN
    	(    		
			
			SELECT 
			"U_Text1" AS "ItemCode"
			FROM "@MTC_IMPT1" T1 
			WHERE T1."DocEntry"=7
    	) T1 ON T0."ItemCode"=T1."ItemCode"
    WHERE 1=1
    AND T0."FcCode"=:FcCode AND T0."CostCode"='20';
    
    */
    
	SELECT 0 AS "代码",'成本计算'||:FcCode||',成功！' AS "信息" FROM DUMMY;

END