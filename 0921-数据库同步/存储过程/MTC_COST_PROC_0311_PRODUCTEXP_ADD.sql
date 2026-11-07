CREATE PROCEDURE "MTC_COST_PROC_0311_PRODUCTEXP_ADD"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 费用归集表 MTC_COST_0311_PRODUCTEXP_ADD
     * CALL "MTC_COST_PROC_0311_PRODUCTEXP_ADD"(0,'2024-01','manager');
     * 由这几部分构成：
       1.人工费用、制造费用：日记账分录计入人工费用和制造费用的
       2.公摊材料费用：计入当期制造费用5101的物料消耗（其他领用）
       3.委外发票差异：委外费用发票差异计入的当期制造费用
	   4.生成分录计入的科目：人工费用500102 制造费用500103
    */
	
    
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
  	
	DELETE FROM MTC_COST_0311_PRODUCTEXP_ADD WHERE "FcCode" = :FcCode;
	
	INSERT INTO MTC_COST_0311_PRODUCTEXP_ADD("BPLId"
	,"FcCode"
	,"ExpType"	--费用类型
	,"ExpCode" --费用大类编码
	,"ExpName" --费用大类名称
	,"AcctCode" --科目编码
	,"AcctName" --科目名称
	,"OcrCode"
	,"OcrName"
	,"IsCal" --是否计入 Y/N
	,"Amount"	--计入金额
	,"Memo"		--备注	
	,"CalAcctCode"	--计入的科目编码
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,CASE WHEN T2."AcctCode"='500102' THEN '人工费用' ELSE '制造费用' END AS "ExpType"
	,NULL AS "ExpCode"
	,NULL AS "ExpName"
	,T2."AcctCode"
	,T2."AcctName"
	,T3."PrcCode"
	,T3."PrcName"
	,'Y' AS "IsCal"
	,SUM(T1."Debit"-T1."Credit") AS "Amount"
	,'' AS "Memo"
	,CASE WHEN T2."AcctCode"='500102' THEN '500102' ELSE '500103' END AS "CalAcctCode"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM OJDT T0
	JOIN "JDT1" T1 ON T0."TransId"=T1."TransId"
	JOIN OACT T2 ON T1."Account"=T2."AcctCode"
	LEFT JOIN OPRC T3 ON T1."ProfitCode"=T3."PrcCode"
	WHERE 1=1 
	AND LEFT(T0."RefDate",7)=:FcCode
	AND (T1."Account"='500102' OR LEFT(T1."Account",4)='5101')
	AND IFNULL(T0."TransCode",'') IN ('','YF01','PP03','MR11','MR02','MR03','MR12') --后期需要改为排除
	GROUP BY T2."AcctCode"
	,T2."AcctName"
	,T3."PrcCode"
	,T3."PrcName"
	
	--增加关单差异
	UNION ALL
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,'制造费用' AS "ExpType"
	,NULL AS "ExpCode"
	,NULL AS "ExpName"
	,T2."AcctCode"
	,T2."AcctName"
	,T3."PrcCode"
	,T3."PrcName"
	,'Y' AS "IsCal"
	,SUM(T1."Debit"-T1."Credit") AS "Amount"
	,'' AS "Memo"
	,CASE WHEN T2."AcctCode"='500102' THEN '500102' ELSE '500103' END AS "CalAcctCode"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM OBTF T0
	JOIN "BTF1" T1 ON T0."TransId"=T1."TransId" AND T0."BatchNum"=T1."BatchNum"
	JOIN OACT T2 ON T1."Account"=T2."AcctCode"
	LEFT JOIN OPRC T3 ON T1."ProfitCode"=T3."PrcCode"
	WHERE 1=1
	AND T0."BtfStatus"='O'
	AND LEFT(T0."RefDate",7)=:FcCode
	AND LEFT(T1."Account",4)='5101'
	AND IFNULL(T0."TransCode",'') IN ('JZ01','JZ03') 
	GROUP BY T2."AcctCode"
	,T2."AcctName"
	,T3."PrcCode"
	,T3."PrcName"
	
	UNION ALL
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,'公摊材料费用' AS "ExpType"
	,NULL AS "ExpCode"
	,NULL AS "ExpName"
	,T5."AcctCode"
	,T5."AcctName"
	,T0."OcrCode1"
	,P1."PrcName"
	,'Y' AS "IsCal"
	,-1*SUM(ROUND("Amount",2)) AS "Amount"
	,'' AS "Memo"
	,'500103' AS "CalAcctCode"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	LEFT JOIN (
				SELECT "ObjType","DocEntry","LineNum","AcctCode" FROM IGN1
					UNION ALL
				SELECT "ObjType","DocEntry","LineNum","AcctCode" FROM IGE1
				) T4 ON T0."ObjType"=T4."ObjType" AND T0."DocEntry"=T4."DocEntry" AND T0."LineNum"=T4."LineNum"
	LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
	LEFT JOIN OACT T5 ON T4."AcctCode"=T5."AcctCode"
	WHERE T0."FcCode"=:FcCode
	AND T0."CostCode"='20'
	AND T0."ObjType" IN ('59','60')
	AND (T0."TransCode" IN ('I04','O04','I10','O10'))	--I04 O04其他出入库 'I10','O10'盘点出入库
	AND LEFT(T4."AcctCode",4) IN ('5101')
	GROUP BY "OcrCode1",P1."PrcName",T5."AcctCode"
	,T5."AcctName"
	
	UNION ALL
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,'公摊材料费用' AS "ExpType"
	,NULL AS "ExpCode"
	,NULL AS "ExpName"
	,T5."AcctCode"
	,T5."AcctName"||'(生产试打)'
	,T0."OcrCode1"
	,P1."PrcName"
	,'Y' AS "IsCal"
	,CASE WHEN T0."OcrCode1"='P016' THEN 32710.04 WHEN T0."OcrCode1"='P006' THEN 0 END AS "Amount"
	---1*SUM(ROUND("Amount",2)) AS "Amount"
	,'' AS "Memo"
	,'500103' AS "CalAcctCode"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM MTC_COST_0302_INVNTDETAIL1 T0
	LEFT JOIN OPRC P1 ON T0."OcrCode1"=P1."PrcCode"
	LEFT JOIN OACT T5 ON T5."AcctCode"='510109'
	LEFT JOIN OWOR T6 ON T0."BaseType"='202' AND T0."BaseEntry"=T6."DocEntry"
	WHERE 1=0
	AND T0."FcCode"=:FcCode
	AND T0."CostCode"='20'
	AND T0."ObjType" IN ('59','60')
	AND T6."U_OrdType"='40'
	GROUP BY "OcrCode1",P1."PrcName",T5."AcctCode"
	,T5."AcctName"
	;
	--这个还需要再议 重新写
	INSERT INTO MTC_COST_0311_PRODUCTEXP_ADD("BPLId"
	,"FcCode"
	,"ExpType"	--费用类型
	,"ExpCode" --费用大类编码
	,"ExpName" --费用大类名称
	,"AcctCode" --科目编码
	,"AcctName" --科目名称
	,"OcrCode"
	,"OcrName"
	,"IsCal" --是否计入 Y/N
	,"Amount"	--计入金额
	,"Memo"		--备注	
	,"CalAcctCode"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,'库存重估-委外工单差异' AS "ExpType"
	,NULL AS "ExpCode"
	,NULL AS "ExpName"
	,NULL
	,NULL
	,NULL AS "OcrCode1"
	,NULL AS "PrcName"
	,'Y' AS "IsCal"
	,SUM(ROUND(-1*T1."U_Amount",2)) AS "Amount"
	,'' AS "Memo"
	,'500103' AS "CalAcctCode"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "@MTC_OMRV" T0
	JOIN "@MTC_OMRV1" T1 ON T0."DocEntry"=T1."DocEntry"
	LEFT JOIN OITM P1 ON T1."U_ItemCode"=P1."ItemCode"
	LEFT JOIN OITB P2 ON P1."ItmsGrpCod"=P2."ItmsGrpCod"
	LEFT JOIN U_COILV P3 ON P3."FcCode"=:FcCode AND T1."U_ItemCode"=P3."ItemCode"
	JOIN MTC_COST_0101_COSTTYPE P5 ON P5."CostTypeCode"='20'	--材料
	WHERE 1=1
	AND T0."Canceled"='N'
	AND T0."U_BaseType"='ProWW'
	AND IFNULL(T1."U_BaseType",'')<>'202'
	AND LEFT(T0."U_DocDate",7)=:FcCode;
	
	
	--这个还需要再议 重新写
	INSERT INTO MTC_COST_0311_PRODUCTEXP_ADD("BPLId"
	,"FcCode"
	,"ExpType"	--费用类型
	,"ExpCode" --费用大类编码
	,"ExpName" --费用大类名称
	,"AcctCode" --科目编码
	,"AcctName" --科目名称
	,"OcrCode"
	,"OcrName"
	,"IsCal" --是否计入 Y/N
	,"Amount"	--计入金额
	,"Memo"		--备注	
	,"CalAcctCode"
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,CASE WHEN IFNULL(T1."U_CalType",'')='ProCost' THEN '库存重估-手工重估（当期成本）'
		  WHEN IFNULL(T1."U_CalType",'')='InvntCost' THEN '库存重估-手工重估（结存）'
		  ELSE '其他' END
		 AS "ExpType"
	,NULL AS "ExpCode"
	,NULL AS "ExpName"
	,T1."U_AcctCode"
	,T1."U_AcctName"
	,NULL AS "OcrCode1"
	,NULL AS "PrcName"
	,'Y' AS "IsCal"
	,SUM(ROUND(-1*T1."U_Amount",2)) AS "Amount"
	,'' AS "Memo"
	,'500103' AS "CalAcctCode"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM "@MTC_OMRV" T0
	JOIN "@MTC_OMRV1" T1 ON T0."DocEntry"=T1."DocEntry"
	LEFT JOIN OITM P1 ON T1."U_ItemCode"=P1."ItemCode"
	LEFT JOIN OITB P2 ON P1."ItmsGrpCod"=P2."ItmsGrpCod"
	LEFT JOIN U_COILV P3 ON P3."FcCode"=:FcCode AND T1."U_ItemCode"=P3."ItemCode"
	JOIN MTC_COST_0101_COSTTYPE P5 ON P5."CostTypeCode"='20'	--材料
	WHERE 1=1
	AND T0."Canceled"='N'
	AND T0."U_BaseType" IN ('MRV1','MRV2')
	--AND IFNULL(T1."U_CalType",'')='ProCost' chris.li 20250905去掉，期末结存的也需要放入制造费用
	AND LEFT(T0."U_DocDate",7)=:FcCode
	GROUP BY T1."U_AcctCode",T1."U_AcctName"
	,CASE WHEN IFNULL(T1."U_CalType",'')='ProCost' THEN '库存重估-手工重估（当期成本）'
		  WHEN IFNULL(T1."U_CalType",'')='InvntCost' THEN '库存重估-手工重估（结存）'
		  ELSE '其他' END
	;
	
	
	SELECT  "FcCode" AS "期间",
	"ExpType" AS "费用类型",
	"ExpCode" AS "费用编码",
	"ExpName" AS "费用名称",
	"AcctCode" AS "科目编码",
	"AcctName" AS "科目名称",
	"OcrCode" AS "部门编码",
	"OcrName" AS "部门名称",
	"IsCal" AS "计入成本计算",
	"Amount" AS "金额",
	"Memo" AS "备注",
	"CalAcctCode" AS "计入科目",
	"CreateDate" AS "创建日期",
	"Creator" AS "创建人"
	FROM MTC_COST_0311_PRODUCTEXP_ADD WHERE "FcCode"=:FcCode;
	

END