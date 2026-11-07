/* =====================================================================
 * 修正稿：MTC_COST_PROC_CAL_1001_CHECK（未部署，仅供审阅）
 * 底稿：0921-数据库同步/存储过程/MTC_COST_PROC_CAL_1001_CHECK.sql（2026-10-07 同步）
 * 背景：全月一次加权时，0311 在 0401 之前就从 0302 取 I04/O04/I10/O10（科目5101）的金额作为公摊材料费用。
 *       若物料没有上期结存、本期也没有采购，入库只有本期生产入库（价格要等 0401 才算出），
 *       此时这些出库行没有价格，所以要在计算前先为它指定一个价格（@MTC_COST_QCPRICE）。
 * 修改（只改“期初单价维护”的收集部分，其余检查项未动）：
 *   1. Onhand_SUM 的本期入库从 ObjType='20' 改为 TransCode IN ('I01','I06','I11')，与 0302 Step1001 一致，
 *      建议价等于计算时 Step1002 实际会用的价格；价格为 0 时仍回退到历史最近一次非 0 单价。
 *   2. 收集的交易类型改为计算时实际读取维护价的范围：I04 O04 I10 O10 O05 O07 O08 O06 + 304 生产退料；
 *      去掉 I05 I07 I08（计算时不读维护价）；排除 NoCost 行。
 *   3. 结存和采购都没有价格的行，备注前加【需确认】。
 *   4.（2026-10-11）新增第 15 项：形态转换单不能跨月。本月每个配对键（行上的 U_BaseType/U_BaseEntry/U_BaseLineGrpNum）
 *      下必须正好一行 205 转出、一行 204 转入；配对键不全、转出或转入在其他月份 / 缺失、不是一对一，都算不通过。
 *      0302 只在同月内配对，跨月的 I05 单价会是 0。明细见 MTC_COST_PROC_CAL_1001_CHECK_DETAIL(FcCode,'15')。
 * 注意：IsInsert='Y' 时，本期已有单据不会重新生成；要按新范围生成，需用 'I'，会覆盖用户已改的价格。
 * ===================================================================== */
CREATE PROCEDURE "MTC_COST_PROC_CAL_1001_CHECK"(IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50),IN IsInsert NVARCHAR(30) DEFAULT 'N')
LANGUAGE SQLSCRIPT
AS
BEGIN
	/*
		CALL "MTC_COST_PROC_CAL_1001_CHECK"('2025-01','1');
	*/
	
	
	DECLARE sdate DATE;
	DECLARE edate DATE;
	DECLARE LastFcCode NVARCHAR(30); --上一期间
	DECLARE MAXEntry INT;
	
	DECLARE CNT INT;
	
	
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
  	
  	CREATE LOCAL TEMPORARY TABLE #LIST("RptCode" NVARCHAR(50),"RptName" NVARCHAR(50),"DocEntry" INT,"Result" NVARCHAR(10));
  	
  	--拉取库存交易明细
    CALL "MTC_COST_PROC_0303_INVNTDETAIL2"(0,:FcCode,:UserCode);
	
	
	SELECT "F_RefDate","T_RefDate" INTO sdate,edate FROM OFPR WHERE "Code"=:FcCode; 
	SELECT MAX("Code") INTO LastFcCode FROM OFPR WHERE "Code"<:FcCode;
	/*
	--当采购退货的价格为空的时候，将上期的价格写入
	UPDATE T1 SET T1."U_InitPrice"=T2."Price"
	FROM ORPD T0
	JOIN RPD1 T1 ON T0."DocEntry"=T1."DocEntry"
	JOIN (SELECT * FROM MTC_COST_0301_INVNT WHERE "CostCode"='20' AND "FcCode"=:LastFcCode) T2 ON T1."ItemCode"=T2."ItemCode"
	WHERE 1=1
	AND T0."DocDate">=:sdate AND T0."DocDate"<=:edate
	AND T1."Price"=0;
	
	
	TMP=
	SELECT 
	 P0."TransType" AS "ObjType"
	,P0."CreatedBy" AS "DocEntry"
	,P0."BASE_REF" AS "DocNum"
	,P0."DocLineNum" AS "LineNum"
	,P0."DocDate"
	,P5."CostTypeCode" AS "CostCode"   --归入成本计价类型
	,P8."TransCode"   --实际交易类型
	,P8."BaseType"
	,P8."BaseEntry"
	,CASE WHEN TO_CHAR(P8."BaseRef") IN ('') THEN NULL ELSE P8."BaseRef" END AS "BaseNum"
	,P8."BaseLine"
	,P0."ItemCode"
	,P1."ItemName"
	,P1."ItmsGrpCod"
	,NULL AS "iLevel"
	,P1."U_ItemProp" AS "CalType" --成本计价类型
	,P0."InQty"-P0."OutQty" AS "Quantity"
	,CASE WHEN P0."TransType" IN ('20','21') THEN P9."Amount" 
		ELSE P0."SumStock" END AS "Amount"
	FROM OIVL P0
	LEFT JOIN OITM P1 ON P0."ItemCode"=P1."ItemCode"
	LEFT JOIN OITB P2 ON P1."ItmsGrpCod"=P2."ItmsGrpCod"
	JOIN MTC_COST_0101_COSTTYPE P5 ON P5."CostTypeCode"='20'	--材料
	LEFT JOIN (SELECT T0."ObjType",T0."DocEntry",T0."LineNum",T0."OcrCode"
				,T0."BaseType",T0."BaseEntry",T0."BaseRef",T0."BaseLine"
				,T0."TransCode"
				FROM "MTC_VIEW_Document" T0
		) P8 ON TO_CHAR(P0."TransType")=P8."ObjType" AND TO_CHAR(P0."CreatedBy")=P8."DocEntry" AND TO_CHAR(P0."DocLineNum")=P8."LineNum"
	LEFT JOIN (SELECT M."ObjType",M."DocEntry",D."LineNum"
				,CASE WHEN M."CANCELED"='C' THEN -1 ELSE 1 END
				 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."LineTotal" END AS "Amount"
				FROM OPDN M JOIN PDN1 D ON M."DocEntry"=D."DocEntry"
				UNION ALL
				SELECT M."ObjType",M."DocEntry",D."LineNum"
				,CASE WHEN M."CANCELED"='C' THEN 1 ELSE -1 END
				 *CASE WHEN IFNULL(D."U_InitPrice",0)<>0 THEN IFNULL(D."U_InitPrice",0)*D."Quantity" ELSE D."LineTotal" END AS "Amount"
				FROM ORPD M JOIN RPD1 D ON M."DocEntry"=D."DocEntry"
			) P9 ON TO_CHAR(P0."TransType")=P9."ObjType" AND P0."CreatedBy"=P9."DocEntry" AND P0."DocLineNum"=P9."LineNum"
	WHERE 1=1
	AND P0."DocDate">=:sdate AND P0."DocDate"<=:edate;
	*/
	
	--上期库存+本期入库
	Onhand_SUM=
	SELECT "ItemCode",SUM("Amount") AS "Amount",SUM("Qty") AS "Qty",SUM("Amount")/NULLIF(SUM("Qty"),0) AS "Price"
	FROM (
			SELECT "ItemCode","QM_Amount" AS "Amount","QM_Qty" AS "Qty" FROM MTC_COST_0301_INVNT T0
			WHERE T0."FcCode"=:LastFcCode AND "CostCode"='20'
			--当期入库
			UNION ALL
			SELECT "ItemCode","Amount","Quantity" FROM MTC_COST_0302_INVNTDETAIL1
			WHERE 1=1
			--AND "ObjType" IN ('20','21','18','19')
			--AND "ObjType" IN ('20')
			--修正稿 2026.10.7 改为与0302 Step1001相同的口径（采购入库、采购退货、库存重估），建议价=计算时Step1002实际取到的价格
			AND "TransCode" IN ('I01','I06','I11')
			AND IFNULL("IsUpdatePrice",'')<>'NoCost'
			AND "FcCode"=:FcCode
		) T0
	GROUP BY "ItemCode"	
	;
	
	--还需要对出入库处理
	TMP_SUM=
	SELECT T0."ItemCode",SUM("Quantity") AS "Quantity",T1."Price"
	,LEFT(STRING_AGG(T2."Name",','),250) AS "IOName"
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	LEFT JOIN :Onhand_SUM T1 ON T0."ItemCode"=T1."ItemCode"
	LEFT JOIN "@MTC_COST_IOTYPE" T2 ON T0."TransCode"=T2."Code"
	--WHERE T0."TransCode" IN ('I04','O04','I05','O06','I10','I07','I08')
	--修正稿 2026.10.7 改为计算时实际读取维护价的交易类型：
	--  0302 Step1003：I04 O04 I10 O10 O05 O07 O08（其中I04 O04 I10 O10在0311计入公摊材料费用，必须在0401之前有价）
	--  0401 9011：O06 销售退货；0401 Step43：O03 O07 中的304生产退料
	--  I05、I07、I08的价格由O05、返工订单计算得出，不读维护价，不再收集
	WHERE (T0."TransCode" IN ('I04','O04','I10','O10','O05','O07','O08','O06')
		OR (T0."TransCode" IN ('O03','O07') AND T0."BusiType"='304'))
	AND IFNULL(T0."IsUpdatePrice",'')<>'NoCost'
	AND T0."FcCode"=:FcCode
	--AND T0."Quantity">0 --入库
	GROUP BY T0."ItemCode",T1."Price";
	
	SELECT COUNT(1) INTO CNT FROM "@MTC_COST_QCPRICE" WHERE "U_FcCode"=:FcCode; 
	
	--DELETE FROM "@MTC_COST_QCPRICE" WHERE "U_FcCode"=:FcCode;
	--DELETE FROM "@MTC_COST_QCPRICE1" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_QCPRICE");
	
	IF :IsInsert = 'Y' OR :IsInsert = 'I' THEN 
		
		IF :IsInsert = 'I' OR :CNT = 0 THEN
	
			DELETE FROM "@MTC_COST_QCPRICE" WHERE "U_FcCode"=:FcCode;
			DELETE FROM "@MTC_COST_QCPRICE1" WHERE "DocEntry" NOT IN (SELECT "DocEntry" FROM "@MTC_COST_QCPRICE");
			
			SELECT IFNULL(MAX("DocEntry"),0) INTO MAXEntry FROM "@MTC_COST_QCPRICE";
			INSERT INTO "@MTC_COST_QCPRICE"("DocEntry","DocNum","Object","U_FcCode","U_Memo")
			SELECT TOP 1 :MAXEntry+1,:MAXEntry+1,'MTC_COST_QCPRICE',:FcCode,'' FROM :TMP_SUM;
		
			INSERT INTO "@MTC_COST_QCPRICE1"("DocEntry","LineId","U_ItemCode","U_ItemName","U_ItmsGrpCod","U_ItmsGrpNam"
			,"U_U_KeyItem","U_Price","U_iLevel","U_LineMemo")
			SELECT :MAXEntry+1
			,ROW_NUMBER() OVER (ORDER BY T0."ItemCode")
			,T1."ItemCode",T1."ItemName",T1."ItmsGrpCod",T2."ItmsGrpNam",T1."U_KeyItem"
			,CASE WHEN IFNULL(T0."Price",0)=0 THEN IFNULL(T5."Price",0) ELSE IFNULL(T0."Price",0) END AS "Price"
			--,CASE WHEN IFNULL(T0."Price",0)=0 THEN IFNULL(T5."U_Price",0) ELSE IFNULL(T0."Price",0) END AS "Price"
			--修正稿 2026.10.7 本期无结存、无采购时，计算前取不到价格，备注前加【需确认】提示用户维护
			,0,LEFT(CASE WHEN IFNULL(T0."Price",0)=0 THEN '【需确认】' ELSE '' END
			||IFNULL(T0."IOName",'')
			|| CASE WHEN IFNULL(T0."Price",0)=0 AND IFNULL(T5."U_FcCode",'')<>'' THEN ','||'上次期间:'||IFNULL(T5."U_FcCode",'') ELSE '' END,254)
			FROM :TMP_SUM T0
			JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
			JOIN OITB T2 ON T1."ItmsGrpCod"=T2."ItmsGrpCod"
			LEFT JOIN (SELECT ROW_NUMBER() OVER(PARTITION BY "ItemCode" ORDER BY "DocDate" DESC) AS "ID"
						,"ItemCode","Price","FcCode" AS "U_FcCode"
						FROM "MTC_COST_0302_INVNTDETAIL1" WHERE 1=1 AND "FcCode"<:FcCode
						--AND "ItemCode"='F01400701'
						AND IFNULL("Price",0)<>0
					) T5 ON T1."ItemCode"=T5."ItemCode" and T5."ID"=1
			/*
		LEFT JOIN (SELECT D."U_ItemCode",D."U_Price",D."DocEntry",M."U_FcCode"
						,ROW_NUMBER() OVER (PARTITION BY D."U_ItemCode" ORDER BY M."U_FcCode" DESC) AS "ID"
						FROM "@MTC_COST_QCPRICE" M
						JOIN "@MTC_COST_QCPRICE1" D ON M."DocEntry"=D."DocEntry"
						WHERE M."Canceled"='N' AND M."U_FcCode"<:FcCode
				) T5 ON T0."ItemCode"=T5."U_ItemCode" AND T5."ID"=1	*/		
			WHERE 1=1
			ORDER BY T0."ItemCode";
		END IF;
	END IF;
	
	--生成期初单价维护
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 2,'期初单价维护',"DocEntry",'Y'
	FROM "@MTC_COST_QCPRICE" WHERE "U_FcCode"=:FcCode;
	
	--3.期初库存检查
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 3,'上期期末库存核对',SUM(CASE WHEN T1."Result">0 THEN 1 ELSE 0 END)
	,CASE WHEN SUM(CASE WHEN T1."Result">0 THEN 1 ELSE 0 END) = 0 THEN 'Y' ELSE 'N' END
	FROM DUMMY T0
	LEFT JOIN
		(SELECT COUNT(1) AS "Result" FROM
			(
				SELECT "ItemCode","QM_Qty",0 AS "OnHand" FROM "MTC_COST_0301_INVNT" WHERE "FcCode"=:LastFcCode AND "CostCode"='20'
				
				UNION ALL
				SELECT "ItemCode",0 AS "QC_Qty",SUM("InQty"-"OutQty") AS "OnHand" FROM OIVL WHERE "DocDate"<:sdate GROUP BY "ItemCode"
			) T0 GROUP BY T0."ItemCode"
			HAVING SUM(T0."QM_Qty")-SUM(T0."OnHand")<>0
		) T1 ON 1=1
	;
	
	--4.生产试打的订单的领料类型，只能是
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 4,'生产试打的生产订单只能选择307试打领用和305生产报废',SUM(CASE WHEN T1."Result">0 THEN 1 ELSE 0 END)
	,CASE WHEN SUM(CASE WHEN T1."Result">0 THEN 1 ELSE 0 END) = 0 THEN 'Y' ELSE 'N' END
	FROM DUMMY T0
	LEFT JOIN
		(SELECT COUNT(1) AS "Result" FROM
			(
				SELECT T0."DocEntry" 
				FROM "OIGE" T0
				JOIN "IGE1" T1 ON T0."DocEntry"=T1."DocEntry"
				JOIN OWOR T2 ON T1."BaseType"='202' AND T1."BaseEntry"=T2."DocEntry"
				WHERE LEFT(T0."DocDate",7)=:FcCode 
				AND T2."U_OrdType"='40'
				AND T0."U_TrsName" NOT IN ('307','305')
				UNION ALL
				SELECT T0."DocEntry" 
				FROM "OIGN" T0
				JOIN "IGN1" T1 ON T0."DocEntry"=T1."DocEntry"
				JOIN OWOR T2 ON T1."BaseType"='202' AND T1."BaseEntry"=T2."DocEntry"
				WHERE LEFT(T0."DocDate",7)=:FcCode 
				AND T2."U_OrdType"='40'
				AND T0."U_TrsName" NOT IN ('307','305')
			) T0 GROUP BY T0."DocEntry"
		) T1 ON 1=1
	;
	
	--5.转换出入库一致
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 5,'转换出入库当期数量一致',SUM(CASE WHEN T1."Result">0 THEN 1 ELSE 0 END)
	,CASE WHEN SUM(CASE WHEN T1."Result">0 THEN 1 ELSE 0 END) = 0 THEN 'Y' ELSE 'N' END
	FROM DUMMY T0
	LEFT JOIN
		(SELECT COUNT(1) AS "Result" FROM
			(
				SELECT -1*T1."Quantity" AS "Quantity"
				FROM "OIGE" T0
				JOIN "IGE1" T1 ON T0."DocEntry"=T1."DocEntry"
				WHERE LEFT(T0."DocDate",7)=:FcCode 
				AND T0."U_TrsName" IN ('204','205')
				UNION ALL
				SELECT T1."Quantity"
				FROM "OIGN" T0
				JOIN "IGN1" T1 ON T0."DocEntry"=T1."DocEntry"
				WHERE LEFT(T0."DocDate",7)=:FcCode 
				AND T0."U_TrsName" IN ('204','205')
			) T0 HAVING SUM("Quantity")<>0
		) T1 ON 1=1
	;
	


	--6.报废仓的库存应该为0
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 6,'S300报废仓的库存为0',SUM(T1."Result")
	,CASE WHEN SUM(T1."Result")>0 THEN 'N' ELSE 'Y' END
	FROM DUMMY T0
	LEFT JOIN
		(SELECT COUNT(1) AS "Result" FROM
			(
				SELECT "ItemCode",SUM("InQty"-"OutQty") AS "OnHand" FROM OIVL WHERE TO_CHAR("DocDate",'YYYY-MM')<=:FcCode AND "LocCode"='S300'
				GROUP BY "ItemCode" HAVING SUM("InQty"-"OutQty")<>0
			) T0
		) T1 ON 1=1
	;
	
	--7.检查截至到当月尚未关单的
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 7,'截至当月已完工但尚未关单的生产工单',SUM(T1."Result")
	,CASE WHEN SUM(T1."Result") > 0 THEN 'N' ELSE 'Y' END
	FROM DUMMY T0
	LEFT JOIN (	
			SELECT COUNT(1) AS "Result"
			FROM (
				SELECT '202' AS "WorType",T1."DocEntry",T1."DocNum",T1."PlannedQty",T0."WorQty",T0."DocDate"
				FROM (
					SELECT T0."OWORNum",SUM(T0."Quantity") AS "WorQty",MAX("DocDate") AS "DocDate"
					FROM "MTC_VIEW_ProductDetail" T0
					LEFT JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
					LEFT JOIN "OITB" T2 ON T1."ItmsGrpCod"=T2."ItmsGrpCod"
					WHERE 1=1
					--AND T0."OWORNum"=39517
					AND T0."Type"='主件'
					AND LEFT(T0."DocDate",7)<=:FcCode
					GROUP BY T0."OWORNum"
					) T0
				JOIN "OWOR" T1 ON T0."OWORNum"=T1."DocNum"
				WHERE T1."Status" IN ('P','R')
				AND T1."PlannedQty"-IFNULL(T0."WorQty",0)<=0 --实际完工数量大于等于计划数量
			
				UNION ALL
				SELECT T1."Object" AS "WorType",T1."DocEntry",T1."DocNum",T1."U_PlannedQty",T0."WorQty",T0."DocDate"
				FROM (
					SELECT T0."BaseEntry" AS "OWORNum",SUM(T0."Quantity") AS "WorQty",MAX("DocDate") AS "DocDate"
					FROM "MTC_VIEW_ProductDetail_MTCOWOR" T0
					LEFT JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
					LEFT JOIN "OITB" T2 ON T1."ItmsGrpCod"=T2."ItmsGrpCod"
					WHERE 1=1
					--AND T0."OWORNum"=39517
					AND T0."Type"='主件'
					AND LEFT(T0."DocDate",7)<=:FcCode
					GROUP BY T0."BaseEntry"
					) T0
				JOIN "@MTC_OWOR" T1 ON T0."OWORNum"=T1."DocNum"
				WHERE T1."U_Status" IN ('P','R')
				AND T1."U_PlannedQty"-IFNULL(T0."WorQty",0)<=0 --实际完工数量大于等于计划数量
			) P
		) T1 ON 1=1;
	
	--8.检查当月的生产工时为0
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 8,'检查当月的生产工时为0',SUM(T1."Result")
	,CASE WHEN SUM(T1."Result")>0 THEN 'N' ELSE 'Y' END
	FROM DUMMY T0
	LEFT JOIN
		(SELECT COUNT(1) AS "Result" FROM
			(
				SELECT T0."ItemCode",T2."ItemName",T1."U_Time"
				FROM "MTC_VIEW_Document" T0
				JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
				LEFT JOIN (SELECT T1."U_ItemCode",T1."U_Time"
							FROM "@MTC_COST_TIME" T0
							JOIN "@MTC_COST_TIME1" T1 ON T0."DocEntry"=T1."DocEntry"
							WHERE 1=1
							AND T0."U_FcCode"=:FcCode
						   ) T1 ON T0."ItemCode"=T1."U_ItemCode"
				WHERE LEFT(T0."DocDate",7)=:FcCode
				AND IFNULL(T1."U_Time",0)=0
				AND T0."ObjType" IN ('59','60')
				AND T0."TransCode" IN ('I03','I07')
				GROUP BY T0."ItemCode",T2."ItemName",T1."U_Time"
			) T0
		) T1 ON 1=1
	;
	
	--9.当月入库次月领料
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 9,'当月入库次月领料',SUM(T1."Result")
	,CASE WHEN SUM(T1."Result")>0 THEN 'N' ELSE 'Y' END
	FROM DUMMY T0
	LEFT JOIN
		(SELECT COUNT(1) AS "Result" FROM
			(
				SELECT A."OWORNum",A."OWOREntry"
				FROM (
					SELECT
					T0."OWORNum",T0."OWOREntry",T1."PlannedQty",T1."CmpltQty"
					,MAX(CASE WHEN T0."Type"='主件' THEN "DocDate" ELSE NULL END) AS "Main_DocDate"
					,MAX(CASE WHEN T0."Type"='子件' THEN "DocDate" ELSE NULL END) AS "Detail_DocDate"
					FROM "MTC_VIEW_ProductDetail" T0
					LEFT JOIN OWOR T1 ON T0."OWORNum"=T1."DocNum"
					WHERE 1=1 AND IFNULL(T1."PlannedQty",0)-IFNULL(T1."CmpltQty",0)<=0
					GROUP BY T0."OWORNum",T0."OWOREntry",T1."PlannedQty",T1."CmpltQty"
				) A 
				WHERE TO_CHAR(A."Main_DocDate",'YYYY-MM')<TO_CHAR(A."Detail_DocDate",'YYYY-MM')
				AND TO_CHAR(A."Main_DocDate",'YYYY-MM')<=:FcCode --当月入库
				AND TO_CHAR(A."Detail_DocDate",'YYYY-MM')>:FcCode --次月领料
				
				UNION ALL
				SELECT A."BaseEntry",A."BaseLine"
				FROM (
					SELECT
					T0."BaseEntry",T0."BaseLine"
					,MAX(CASE WHEN T0."Type"='主件' THEN "DocDate" ELSE NULL END) AS "Main_DocDate"
					,MAX(CASE WHEN T0."Type"='子件' THEN "DocDate" ELSE NULL END) AS "Detail_DocDate"
					FROM "MTC_VIEW_ProductDetail_MTCOWOR" T0
					GROUP BY T0."BaseType",T0."BaseEntry",T0."BaseLine"
				) A 
				WHERE TO_CHAR(A."Main_DocDate",'YYYY-MM')<TO_CHAR(A."Detail_DocDate",'YYYY-MM')
				AND TO_CHAR(A."Main_DocDate",'YYYY-MM')<=:FcCode --当月入库
				AND TO_CHAR(A."Detail_DocDate",'YYYY-MM')>:FcCode --次月领料
			) T0
		) T1 ON 1=1
	;
	
	--10.平台价维护
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 10,'平台价维护',T1."Result"
	,CASE WHEN T1."Result"=0 THEN 'N' ELSE 'Y' END
	FROM DUMMY T0
	LEFT JOIN
		(SELECT COUNT(1) AS "Result" FROM
			(
				SELECT "DocEntry" FROM "@MTC_PTPRICE" WHERE "U_FcCode"=:FcCode
			) T0
		) T1 ON 1=1
	;
	
	
	--11.销售跨月做单
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 11,'销售跨月做单',T1."Result"
	,CASE WHEN T1."Result"=0 THEN 'Y' ELSE 'N' END
	FROM DUMMY T0
	LEFT JOIN
		(SELECT COUNT(1) AS "Result" FROM
			(
				SELECT DISTINCT '15.1交货引用交货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "DLN1" T1
				JOIN "ODLN" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ODLN" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '15.2交货引用退货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "DLN1" T1
				JOIN "ODLN" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ORDN" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '13.1应收发票引用交货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "INV1" T1
				JOIN "OINV" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ODLN" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '13.2应收发票引用发票跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "INV1" T1
				JOIN "OINV" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "OINV" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '16.1销售退货引用交货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "RDN1" T1
				JOIN "ORDN" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ODLN" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '16.2销售退货引用退货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "RDN1" T1
				JOIN "ORDN" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ORDN" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '14.1应收贷项发票引用退货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "RIN1" T1
				JOIN "ORIN" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ORDN" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '14.2应收贷项发票引用应收贷项发票跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "RIN1" T1
				JOIN "ORIN" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ORIN" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '14.3应收贷项发票引用应收发票跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "RIN1" T1
				JOIN "ORIN" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "OINV" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
			) T0
		) T1 ON 1=1
	;
	
	
	--12.采购跨月做单
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 12,'采购跨月做单',T1."Result"
	,CASE WHEN T1."Result"=0 THEN 'Y' ELSE 'N' END
	FROM DUMMY T0
	LEFT JOIN
		(SELECT COUNT(1) AS "Result" FROM
			(
				SELECT DISTINCT '20.1收货引用收货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "PDN1" T1
				JOIN "OPDN" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "OPDN" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '20.2收货引用退货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "PDN1" T1
				JOIN "OPDN" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ORDN" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '18.1应付发票引用收货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "PCH1" T1
				JOIN "OPCH" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "OPCH" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '18.2应付发票引用发票跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "PCH1" T1
				JOIN "OPCH" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "OPCH" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '21.1采购退货引用收货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "RPD1" T1
				JOIN "ORPD" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "OPDN" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '21.2采购退货引用退货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "RPD1" T1
				JOIN "ORPD" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ORPD" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '19.1应付贷项发票引用退货跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "RPC1" T1
				JOIN "ORPC" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ORPD" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '19.2应付贷项发票引用应付贷项发票跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "RPC1" T1
				JOIN "ORPC" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "ORPC" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
				UNION ALL
				SELECT DISTINCT '19.3应付贷项发票引用应付发票跨月' AS "Type",T0."DocDate",T2."DocDate" AS "BaseDate",T0."ObjType",T0."DocNum"
				FROM "RPC1" T1
				JOIN "ORPC" T0 ON T0."DocEntry"=T1."DocEntry"	--本单
				JOIN "OPCH" T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry"	--引用原单
				WHERE 1=1 AND TO_CHAR(T0."DocDate",'YYYY-MM')>:FcCode
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode
			) T0
		) T1 ON 1=1
	;
	
	--13.生产订单，已关单，不能出入库
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 13,'生产订单(订单类型=202正常生产订单)的已在上月关单，但是本月仍有出入库',T1."Result"
	,CASE WHEN T1."Result"=0 THEN 'Y' ELSE 'N' END
	FROM DUMMY T0
	LEFT JOIN
		(
			SELECT COUNT(1) AS "Result" 
			FROM ( 
				SELECT T0."Type",T0."ObjType",T0."OWOREntry",T0."OWORNum",T0."DocEntry",T0."DocNum"
				,T0."DocDate",T1."CloseDate",T0."ItemCode",T0."WhsCode",T0."Quantity"
				FROM "MTC_VIEW_ProductDetail" T0
				INNER JOIN "OWOR" T1 ON T0."OWOREntry"=T1."DocEntry"
				WHERE LEFT(T0."DocDate",7)=:FcCode
				AND T1."Status"='L'
				AND LEFT(T1."CloseDate",7)<LEFT("DocDate",7)
				) P0
		) T1 ON 1=1;
		
	--14.生产订单，已关单，不能出入库
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 14,'生产订单(订单类型=MTC_OWOR返工单)的已在上月关单，但是本月仍有出入库',T1."Result"
	,CASE WHEN T1."Result"=0 THEN 'Y' ELSE 'N' END
	FROM DUMMY T0
	LEFT JOIN
		(
			SELECT COUNT(1) AS "Result" 
			FROM ( 
				SELECT T0."Type",T0."TransType",T0."BaseEntry",T0."CreatedBy",T0."BASE_REF"
				,T0."DocDate",T1."U_CloseDate",T0."ItemCode",T0."Quantity"
				FROM "MTC_VIEW_ProductDetail_MTCOWOR" T0
				INNER JOIN "@MTC_OWOR" T1 ON T0."BaseEntry"=T1."DocEntry"
				WHERE LEFT(T0."DocDate",7)=:FcCode
				AND T1."U_Status"='L'
				AND LEFT(T1."U_CloseDate",7)<LEFT("DocDate",7)
				) P0
		) T1 ON 1=1;
	
	--15.形态转换单不能跨月（修正稿 2026.10.11）
	--本月每个配对键（行上的 U_BaseType/U_BaseEntry/U_BaseLineGrpNum）下，必须正好一行205转出、一行204转入
	--0302 只在同月内按配对键把 I05 对到 O05，转出单在其他月份时 I05 单价为 0
	INSERT INTO #LIST("RptCode","RptName","DocEntry","Result")
	SELECT 15,'形态转换单不能跨月（205转出与204转入同月一对一）',T1."Result"
	,CASE WHEN T1."Result"=0 THEN 'Y' ELSE 'N' END
	FROM DUMMY T0
	LEFT JOIN
		(
			SELECT COUNT(1) AS "Result"
			FROM (
				SELECT P0."BT",P0."BE",P0."BL"
				FROM (
					SELECT 'I' AS "Side",TO_NVARCHAR(T1."U_BaseType") AS "BT",TO_NVARCHAR(T1."U_BaseEntry") AS "BE",TO_NVARCHAR(T1."U_BaseLineGrpNum") AS "BL"
					FROM "OIGN" T0
					JOIN "IGN1" T1 ON T0."DocEntry"=T1."DocEntry"
					WHERE TO_CHAR(T0."DocDate",'YYYY-MM')=:FcCode
					AND T0."U_TrsName"='204'
					AND T0."CANCELED"='N'
					UNION ALL
					SELECT 'O' AS "Side",TO_NVARCHAR(T1."U_BaseType"),TO_NVARCHAR(T1."U_BaseEntry"),TO_NVARCHAR(T1."U_BaseLineGrpNum")
					FROM "OIGE" T0
					JOIN "IGE1" T1 ON T0."DocEntry"=T1."DocEntry"
					WHERE TO_CHAR(T0."DocDate",'YYYY-MM')=:FcCode
					AND T0."U_TrsName"='205'
					AND T0."CANCELED"='N'
				) P0
				GROUP BY P0."BT",P0."BE",P0."BL"
				HAVING P0."BT" IS NULL OR P0."BE" IS NULL OR P0."BL" IS NULL
				OR SUM(CASE WHEN P0."Side"='I' THEN 1 ELSE 0 END)<>1
				OR SUM(CASE WHEN P0."Side"='O' THEN 1 ELSE 0 END)<>1
			) P1
		) T1 ON 1=1;
	
	SELECT :FcCode AS "FcCode","RptCode","RptName","DocEntry","Result" FROM #LIST;
	
	DROP TABLE #LIST; 
	
	
	
END