-- 修正稿（未部署，用户 2026-10-30，用户自己改库）：MTC_COST_PROC_0306_WW 增加返工单（MTC_OWOR）的委外加工费。以 0921-数据库同步 版为底稿，只在 202 那段之后加一段 INSERT。
-- 原来返工单的加工费只有 ProWW 重估能进订单，加工费收货（PDN1.U_OWORType='MTC_OWOR'）不进订单，PUR4 借了 140802 却没有订单承接。
-- 口径同修正后的视图 ID 3（fixes/MTC_VIEW_ProductDetail.sql）：暂估金额、退货按退货日期、含不基于收货的加工费退货。和视图修正稿一起部署。
-- 新框架 P20_SUBFEE 已覆盖返工单（另外还要求加工费行所指的生产收货 U_BaseEntry 是这张返工单的完工收货，旧版这里只看行上的返工单号）。
CREATE OR REPLACE PROCEDURE "MTC_COST_PROC_0306_WW"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 费用归集表 MTC_COST_0312_PRODUCTEXP_PRC
     * CALL "MTC_COST_PROC_0312_PRODUCTEXP_PRC"(0,'2024-01','manager');
    */
    --w委外

    
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;

    DELETE FROM MTC_COST_0321_OWOR2 WHERE "FcCode"=:FcCode AND "CostCode"='20';
    
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"CostCode"	--制造费用/人工费用
	,"ExpType"  --费用类型
	,"IgeQty"  
	,"Amount"
	,"CreateDate"   --创建时间
	,"Creator"
	)
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,T0."DocType"
	,T0."WorType"
	,T0."WorEntry"
	,T0."WorNum"
	,'20' AS "CostCode"
	,'委外费用' AS "ExpType"
	,-1*"Detail_Qty" AS "IgeQty"
	,-1*ROUND(T1."Detail_Amt",2) AS "ExpAmt"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM MTC_COST_0321_OWOR T0
	JOIN (
			SELECT "OWOREntry"
  			,SUM(-1*"Quantity") AS "Detail_Qty"
  			,SUM(-1*ROUND("Amt",2)) AS "Detail_Amt"
  			FROM "MTC_VIEW_ProductDetail" T0
  			WHERE "Type" = '子件' AND LEFT(T0."DocDate",7)=:FcCode
  			AND "ID" IN (3,4)
  			GROUP BY "OWOREntry"
			) T1 ON T0."WorEntry"=T1."OWOREntry"
	WHERE 1=1
	AND T0."DocType"='202'
	AND T0."FcCode"=:FcCode
	;

	--2026-10-30 返工单（MTC_OWOR）的委外加工费（用户 2026-10-30；原来 MTC_VIEW_ProductDetail ID 3 只关联 202，返工单的加工费不进订单）
	--加工费收货 / 退货行上 U_OWORType='MTC_OWOR'、U_MTCOWORNum = @MTC_OWOR.DocEntry；金额按暂估口径（同 PUR4）；退货按退货日期，
	--基于收货的退货按收货行暂估单价，退货的取消单经原退货行反向；符号同上一段（ExpAmt = −加工费）
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"CostCode"
	,"ExpType"
	,"IgeQty"
	,"Amount"
	,"CreateDate"
	,"Creator"
	)
	SELECT :BPLId,:FcCode,T0."DocType",T0."WorType",T0."WorEntry",T0."WorNum",'20','委外费用'
	,-1*SUM(F."Qty"),-1*ROUND(SUM(F."Amt"),2),CURRENT_TIMESTAMP,:UserCode
	FROM MTC_COST_0321_OWOR T0
	JOIN (
		--收货
		SELECT TO_NVARCHAR(D."U_MTCOWORNum") AS "WorEntry"
		,CASE WHEN M."CANCELED"='C' THEN -1 ELSE 1 END*D."Quantity" AS "Qty"
		,CASE WHEN M."CANCELED"='C' THEN -1 ELSE 1 END*ROUND(CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN D."Quantity"*D."U_InitPrice" WHEN D."U_IsPrice"='Y' THEN D."Quantity"*D."Price" ELSE D."LineTotal" END,2) AS "Amt"
		FROM OPDN M JOIN PDN1 D ON M."DocEntry"=D."DocEntry"
		WHERE D."U_OWORType"='MTC_OWOR' AND TO_NVARCHAR(D."U_BaseType")='59' AND LEFT(M."DocDate",7)=:FcCode
		UNION ALL
		--基于收货的退货（含退货的取消单）
		SELECT TO_NVARCHAR(P."U_MTCOWORNum")
		,CASE WHEN M."CANCELED"='C' THEN 1 ELSE -1 END*D."Quantity"
		,CASE WHEN M."CANCELED"='C' THEN 1 ELSE -1 END*ROUND(D."Quantity"*(CASE WHEN IFNULL(P."U_InitPrice",0)<>0 THEN P."U_InitPrice" WHEN P."U_IsPrice"='Y' THEN P."Price" ELSE P."LineTotal"/NULLIF(P."Quantity",0) END),2)
		FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry"
		LEFT JOIN RPD1 O ON M."CANCELED"='C' AND D."BaseType"=21 AND O."DocEntry"=D."BaseEntry" AND O."LineNum"=D."BaseLine"
		JOIN PDN1 P ON IFNULL(O."BaseType",D."BaseType")=20 AND P."DocEntry"=IFNULL(O."BaseEntry",D."BaseEntry") AND P."LineNum"=IFNULL(O."BaseLine",D."BaseLine")
		WHERE P."U_OWORType"='MTC_OWOR' AND TO_NVARCHAR(P."U_BaseType")='59' AND LEFT(M."DocDate",7)=:FcCode
		UNION ALL
		--不基于收货的加工费退货（物料 X0510001，旧框架没有参数，写死；其他 X 开头物料不是加工费，用户 2026-11-04）
		SELECT TO_NVARCHAR(D."U_MTCOWORNum")
		,CASE WHEN M."CANCELED"='C' THEN 1 ELSE -1 END*D."Quantity"
		,CASE WHEN M."CANCELED"='C' THEN 1 ELSE -1 END*ROUND(CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN D."Quantity"*D."U_InitPrice" WHEN D."U_IsPrice"='Y' THEN D."Quantity"*D."Price" ELSE D."LineTotal" END,2)
		FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry"
		LEFT JOIN RPD1 O ON M."CANCELED"='C' AND D."BaseType"=21 AND O."DocEntry"=D."BaseEntry" AND O."LineNum"=D."BaseLine"
		WHERE IFNULL(CASE WHEN M."CANCELED"='C' THEN O."BaseType" ELSE D."BaseType" END,-1)<>20
		AND D."ItemCode"='X0510001' AND D."U_OWORType"='MTC_OWOR' AND LEFT(M."DocDate",7)=:FcCode
		) F ON TO_NVARCHAR(T0."WorEntry")=F."WorEntry"
	WHERE 1=1
	AND T0."DocType"='MTC_OWOR'
	AND T0."FcCode"=:FcCode
	GROUP BY T0."DocType",T0."WorType",T0."WorEntry",T0."WorNum";
	
	INSERT INTO MTC_COST_0321_OWOR2("BPLId"
	,"FcCode"
	,"DocType"
	,"WorType"
	,"WorEntry"
	,"WorNum"
	,"CostCode"	--制造费用/人工费用
	,"ExpType"  --费用类型
	,"IgeQty"  
	,"Amount"
	,"CreateDate"   --创建时间
	,"Creator"
	)
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,T."DocType"
	,T."WorType"
	,T."WorEntry"
	,T."WorNum"
	,'20' AS "CostCode"
	,'委外费用' AS "ExpType"
	,IFNULL(T1."U_Quantity",0) AS "IgeQty"	--订单数量
	,ROUND(-1*T1."U_Amount",2) AS "ExpAmt"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "@MTC_OMRV" T0
	JOIN "@MTC_OMRV1" T1 ON T0."DocEntry"=T1."DocEntry"
	LEFT JOIN OITM P1 ON T1."U_ItemCode"=P1."ItemCode"
	LEFT JOIN OITB P2 ON P1."ItmsGrpCod"=P2."ItmsGrpCod"
	LEFT JOIN U_COILV P3 ON P3."FcCode"=:FcCode AND T1."U_ItemCode"=P3."ItemCode"
	JOIN MTC_COST_0101_COSTTYPE P5 ON P5."CostTypeCode"='20'	--材料
	JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY "DocType","WorEntry" ORDER BY "FcCode" DESC) AS "ID"
				,"DocType","WorType","WorEntry","WorNum"
				FROM MTC_COST_0321_OWOR
			   WHERE "FcCode"<=:FcCode
		) T ON T1."U_BaseType"=T."DocType" AND T1."U_BaseEntry"=T."WorEntry" AND T."ID"=1
	WHERE 1=1
	AND T0."Canceled"='N'
	AND T0."U_BaseType"='ProWW'
	AND LEFT(T0."U_DocDate",7)=:FcCode;
	
	
	UPDATE T0 SET T0."4WWExp"=IFNULL(T1."Amount",0),T0."Amount"=IFNULL(T0."1Material",0)+IFNULL(T1."Amount",0)
	FROM MTC_COST_0321_OWOR T0
	JOIN (SELECT MAX("FcCode") AS "FcCode","DocType","WorEntry",-1*SUM(ROUND("Amount",2)) AS "Amount"
		FROM MTC_COST_0321_OWOR2 WHERE "CostCode"='20' GROUP BY "DocType","WorEntry"
		) T1 ON T0."FcCode"=T1."FcCode" AND T0."WorEntry"=T1."WorEntry" AND T0."DocType"=T1."DocType"
	WHERE 1=1
	AND T0."FcCode"=:FcCode;
	
	SELECT '委外费用计算成功' FROM DUMMY;
	

END