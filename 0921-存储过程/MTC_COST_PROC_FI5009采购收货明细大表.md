CREATE PROCEDURE "MTC_COST_PROC_FI5009"
(
  IN sdate date,
  IN edate date,
  IN CardCode NVARCHAR(50),
  IN IsOnlyOpen	NVARCHAR(10) DEFAULT 'N'
)
AS
BEGIN

	SELECT *
	FROM (
	SELECT
	'采购收货单' AS "类型"
	,CASE WHEN T0."CANCELED"='C' THEN '抵销单' WHEN T0."CANCELED"='Y' THEN '已抵销' WHEN T1."LineStatus"='O' THEN '未清' WHEN T1."LineStatus"='C' THEN '已清' END AS "状态"
	,T0."DocNum" AS "收退货Num"
	,T0."U_SupNum" AS "收退货单号"
	,T0."U_OldSysNo" AS "老系统单号"
	,T0."NumAtCard" AS "参考号"
	, T0."DocDate" AS "过账日期"
	, T0."DocCur" AS "币种"
	, T0."DocRate" AS "汇率"
	, T3."Name" AS "单据类型"
	, T0."CardCode" AS "供应商编码"
	, T0."CardName" AS "供应商名称"
	, T1."ItemCode" AS "物料编号"
	, T1."U_ItemCode" AS "料号"
	, T1."Dscription" AS "物料名称"
	, T11."InvntryUom" AS "单位"
	, T1."U_Specs" AS "规格"
	, T7."BatchNumber" AS "批次"
	, CAST(CAST(CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."Quantity" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "数量"
	, T1."Price" AS "未税单价"
	, T1."PriceAfVAT" AS "含税单价"
	, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."LineTotal" AS "未税金额（本币）"
	, CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * T1."GTotal"  AS "含税金额（本币）"
	, T1."U_InitPrice" AS "初始单价(未税)"
	,  CAST(CAST(CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END
		*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "暂估单价"
	,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END *
	    CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END *
		ROUND(CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."Quantity"*T1."U_InitPrice" 
				 WHEN T1."U_IsPrice"='Y' THEN T1."Quantity"*T1."Price"
				 ELSE T1."LineTotal" END,2) AS "计入暂估"
	, CASE when T1."LineStatus"='O' then N'未清' when T1."LineStatus"='C' then N'已清'  END  AS "行状态"
	, T4."DocDate" AS "发票日期"
	, CAST(CAST(CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END * T4."Quantity" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "已开票数量"
	, T4."OPCHPrice" AS "已开票未税单价"
	, CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END * T4."LineTotal" AS "已开票未税金额(本币)"
	, CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END * T4."GTotal" AS "已开票含税金额(本币)"
	, T21."DocDate" AS "退货日期"
	, CAST(CAST(CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END * T21."Quantity" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "已退货数量"
	, T21."ORPDPrice" AS "已退货未税单价"
	, CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END * T21."LineTotal" AS "已退货未税金额(本币)"
	, CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END * T21."GTotal" AS "已退货含税金额(本币)"
	, T2."CanceledPDNQty" AS "取消数量"
	, CAST(CAST(
	    	CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END* --排除虚拟物料
			CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END *
			CASE WHEN T0."DocStatus"='C' AND T1."TargetType"=-1 THEN 0 ELSE 1 END *
			CASE WHEN T1."BaseType"='21' THEN 0 ELSE 1 END * T1."Quantity"
			-IFNULL(T4."Quantity",0)
			-IFNULL(T21."Quantity",0)
			-IFNULL(T2."CanceledPDNQty",0) AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "暂估剩余数量"
	,CASE WHEN (T1."Quantity"-IFNULL(T4."Quantity",0)-IFNULL(T21."Quantity",0)-IFNULL(T2."CanceledPDNQty",0))=0 THEN 0 ELSE 1 END
	*CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END
	*CASE WHEN T1."BaseType"='21' THEN 0 ELSE 1 END 
	*CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END --排除虚拟物料
	*CASE when IFNULL(T1."U_InitPrice",0)<>0 
		THEN ROUND((T1."Quantity"-IFNULL(T4."Quantity",0)-IFNULL(T21."Quantity",0)-IFNULL(T2."CanceledPDNQty",0))*T1."U_InitPrice",2)
		ELSE T1."LineTotal"-IFNULL(T4."LineTotal",0)-IFNULL(T21."LineTotal",0)-IFNULL(T2."CanceledPDNAmt",0)
		END AS "暂估剩余金额"
	, ROUND(CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END*CASE WHEN T1."BaseType"='21' THEN 0 ELSE 1 END 
	*(T1."Quantity"-IFNULL(T4."Quantity",0)-IFNULL(T21."Quantity",0)-IFNULL(T2."CanceledPDNQty",0))
	  *CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END --排除虚拟物料
		*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END
		   ,2) AS "暂估剩余金额(老)"
	--当月剩余金额：采购收货金额 - 抵销单的金额 - 采购退货金额 - 应付发票金额 （如果是收货单是抵销单C，则为0）
	, CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END *
		CASE WHEN T1."BaseType"='21' THEN 0 ELSE 1 END *
	    CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END *
		ROUND(CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."Quantity"*T1."U_InitPrice" 
				 WHEN T1."U_IsPrice"='Y' THEN T1."Quantity"*T1."Price"
				 ELSE T1."LineTotal" END,2)
	   - IFNULL(T2."CanceledPDNAmt",0)	--抵销单的金额
	   - IFNULL(T21."RPDAmt",0)			--采购退货金额
	   - IFNULL(T4."LineTotal",0)		--应付发票
	  AS "当月剩余金额"
	, T0."TransId" AS "交易编码"
	, T1."AcctCode" AS "收入科目" 
	, T0."ObjType"  
	, T0."DocEntry"
	, T9."DocNum"  AS "采购订单号Num"
	, T9."U_SupNum"  AS "采购订单号"
	, T12."DocNum"  AS "采购申请单号Num"
	, T12."U_SupNum"  AS "采购申请单号" 
	,T8."Project" AS "项目"
	,T22."OcrName"  AS "部门" 
	, T4."U_CWNum" AS "财务凭证号"
	, T14."U_SupNum" AS "生产收/退货单号"  
	, T1."BaseType"
	,T1."BaseEntry"
	,T1."BaseLine"
	,T91."ItmsGrpNam"
	FROM OPDN T0  
	INNER JOIN PDN1 T1 ON T0."DocEntry" = T1."DocEntry" 
	LEFT JOIN (SELECT T1."BaseType",T1."BaseEntry",T1."BaseLine"
				,SUM(CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END *CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity") AS "CanceledPDNQty"
				,SUM(CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*
					CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END *
					ROUND(CASE WHEN IFNULL(T2."U_InitPrice",0)<>0 THEN T2."Quantity"*T2."U_InitPrice" 
							 WHEN T2."U_IsPrice"='Y' THEN T2."Quantity"*T2."Price"
							 ELSE T2."LineTotal" END,2)) AS "CanceledPDNAmt"	--抵销单的暂估金额
				FROM "OPDN" T0 JOIN PDN1 T1 ON T0."DocEntry"=T1."DocEntry"
				JOIN PDN1 T2 ON T1."BaseType"=T2."ObjType" AND T1."BaseEntry"=T2."DocEntry" AND T1."BaseLine"=T2."LineNum"	--原单
				JOIN OITM T11 ON T1."ItemCode"=T11."ItemCode"
				WHERE T0."DocDate"<=:edate
				GROUP BY T1."BaseType",T1."BaseEntry",T1."BaseLine"
			) T2 ON T0."ObjType"=T2."BaseType" AND T0."DocEntry"=T2."BaseEntry" AND T1."LineNum"=T2."BaseLine"
--LEFT JOIN "MTC_VIEW_CUFD" T2 ON T2."TableID"='OPDN' AND T2."AliasID"='XSDDFL' AND T2."FldValue"=T0."U_XSDDFL"
	LEFT JOIN "@U_CIOTRN" T3 ON T0."U_TrsName"=T3."Code"
	LEFT JOIN (
				SELECT STRING_AGG(TO_CHAR(T0."DocDate",'YYYY.MM.DD'),',') AS "DocDate"
				,STRING_AGG(CAST(CAST(T1."Price" AS DECIMAL(19,6)) AS NVARCHAR(30)),',') AS "OPCHPrice",STRING_AGG(T2."U_CWNum",',') AS "U_CWNum"
				,T1."BaseEntry",T1."BaseLine",SUM(CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END*T1."Quantity") AS "Quantity"
				,SUM(CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END*T1."LineTotal") AS "LineTotal",SUM(T1."GTotal") AS "GTotal",SUM(T1."GTotalFC") AS "GTotalFC"
				FROM "OPCH" T0
				LEFT JOIN "PCH1" T1 ON T0."DocEntry"=T1."DocEntry"
				LEFT JOIN OJDT T2 ON T2."TransId"=T0."TransId"
				JOIN OITM T11 ON T1."ItemCode"=T11."ItemCode"
				WHERE T0."CANCELED"='N'
				AND T0."DocDate"<=:edate
				GROUP BY T1."BaseEntry",T1."BaseLine"
			) T4 ON T4."BaseEntry"=T1."DocEntry" AND T4."BaseLine"=T1."LineNum"
	LEFT JOIN "OCRD" T5 ON T0."CardCode"=T5."CardCode"
	LEFT JOIN 
	(
			 SELECT "ObjType","DocEntry","LineNum","WhsCode" ,STRING_AGG("BatchNumber",',') AS "BatchNumber"
	         FROM "MTC_VW_DOCLINE"
	         GROUP BY "ObjType","DocEntry","LineNum","WhsCode"
	)T7 ON T7."ObjType"=T1."ObjType" and T7."DocEntry"=T1."DocEntry"  AND T7."LineNum"=T1."LineNum" and T7."WhsCode"=T1."WhsCode"
	LEFT JOIN "POR1" T8 ON T1."BaseEntry" =T8."DocEntry" AND T1."BaseLine" =T8."LineNum" 
	LEFT JOIN "OPOR" T9 ON T8."DocEntry" =T9."DocEntry" 
	LEFT JOIN OITM T11 ON T1."ItemCode"=T11."ItemCode"
	LEFT JOIN OITB T91 ON T11."ItmsGrpCod"=T91."ItmsGrpCod"
	LEFT JOIN OPRQ T12 ON T12."DocEntry" =T8."BaseEntry"  
	LEFT JOIN OIGN T14 ON T14."DocEntry" =T1."U_BaseEntry" AND T1."U_BaseType" ='59' 
	LEFT JOIN (
				SELECT STRING_AGG(TO_CHAR(T0."DocDate",'YYYY.MM.DD'),',') AS "DocDate"
				,STRING_AGG(CAST(CAST(T1."Price" AS DECIMAL(19,6)) AS NVARCHAR(30)),',') AS "ORPDPrice"
				,STRING_AGG(T2."U_CWNum",',') AS "U_CWNum"
				,T1."BaseEntry",T1."BaseLine",SUM(T1."Quantity") AS "Quantity",SUM(T1."LineTotal") AS "LineTotal"
				,SUM(T1."GTotal") AS "GTotal",SUM(T1."GTotalFC") AS "GTotalFC"
				,SUM(CASE WHEN T21."ItemCode"='X0510001' OR T21."InvntItem"='Y' THEN 1 ELSE 0 END *
					ROUND(CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."Quantity"*T1."U_InitPrice"
				 	WHEN T1."U_IsPrice"='Y' THEN T1."Quantity"*T1."Price"
					ELSE T1."LineTotal" END,2)) AS "RPDAmt"
				FROM "ORPD" T0
				LEFT JOIN "RPD1" T1 ON T0."DocEntry"=T1."DocEntry"
				LEFT JOIN OJDT T2 ON T2."TransId"=T0."TransId"
				JOIN OITM T21 ON T1."ItemCode"=T21."ItemCode"
				WHERE T0."CANCELED"='N'
				AND T0."DocDate"<=:edate
				GROUP BY T1."BaseEntry",T1."BaseLine"
			) T21 ON T21."BaseEntry"=T1."DocEntry" AND T21."BaseLine"=T1."LineNum"
	LEFT JOIN OOCR T22 ON T22."OcrCode" = T8."OcrCode"  		
	WHERE 1=1 --AND T0."CANCELED"='N'
	AND  (T0."DocDate">=:sdate OR :sdate='17530101')
	AND (T0."DocDate"<=:edate OR :edate='17530101')  
	UNION ALL 
	
	SELECT 
	'采购退货' AS "类型"
	,CASE WHEN T0."CANCELED"='C' THEN '抵销单' WHEN T0."CANCELED"='Y' THEN '已抵销' WHEN T1."LineStatus"='O' THEN '未清' WHEN T1."LineStatus"='C' THEN '已清' END AS "状态"
	,T0."DocNum" AS "收退货Num" /*退货*/ 
	,T0."U_SupNum" AS "收退货单号"
	,T0."U_OldSysNo" AS "老系统单号"
	,T0."NumAtCard" AS "参考号"
	, T0."DocDate" AS "过账日期"
	, T0."DocCur" AS "币种"
	, T0."DocRate" AS "汇率"
	, T3."Name" AS "单据类型"
	, T0."CardCode" AS "供应商编码"
	, T0."CardName" AS "供应商名称"
	, T1."ItemCode" AS "物料编号"
	, T1."U_ItemCode" AS "料号"
	, T1."Dscription" AS "物料名称"
	, T21."InvntryUom" AS "单位"
	, T1."U_Specs" AS "规格"
	, T8."BatchNumber" AS "批次"
	, CAST(CAST(CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "数量"
	, T1."Price" AS "未税单价"
	, T1."PriceAfVAT" AS "含税单价"
	, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."LineTotal" AS "未税金额（本币）"
	, CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."GTotal"  AS "含税金额（本币）"
	, T1."U_InitPrice" AS "初始单价(未税)"
	, CAST(CAST(CASE WHEN T21."ItemCode"='X0510001' OR T21."InvntItem"='Y' THEN 1 ELSE 0 END
		*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "暂估单价"
	, CASE WHEN T21."ItemCode"='X0510001' OR T21."InvntItem"='Y' THEN 1 ELSE 0 END *
		ROUND(CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."Quantity"*T1."U_InitPrice"
				 WHEN T1."U_IsPrice"='Y' THEN T1."Quantity"*T1."Price"
				ELSE T1."LineTotal" END,2) AS "计入暂估"
	, CASE when T1."LineStatus"='O' then N'未清' when T1."LineStatus"='C' then N'已清'  END  AS "行状态"
	, T7."DocDate" AS "发票日期"
	, CAST(CAST(CASE WHEN T0."CANCELED"='C' THEN 0 ELSE -1 END*T7."Quantity" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "已开票数量"
	, T7."OPCHPrice" AS "已开票未税单价"
	, CASE WHEN T0."CANCELED"='C' THEN 0 ELSE -1 END*T7."LineTotal" AS "已开票未税金额(本币)"
	, CASE WHEN T0."CANCELED"='C' THEN 0 ELSE -1 END*T7."GTotal" AS "已开票含税金额(本币)"
	, NULL AS "退货日期"
	, CASE WHEN T0."CANCELED"='C' THEN 0 ELSE -1 END*CASE WHEN T1."BaseType"='20' THEN T1."Quantity" ELSE 0 END AS "已退货数量"
	, NULL AS "已开票未税单价"
	, NULL AS "已开票未税金额(本币)"
	, NULL AS "已开票含税金额(本币)"
	, -1*T2."CanceledPDNQty" AS "取消数量"
	, CAST(CAST(CASE WHEN T21."ItemCode"='X0510001' OR T21."InvntItem"='Y' THEN 1 ELSE 0 END* --排除虚拟物料
	      CASE WHEN T1."TargetType"='20' THEN 0 ELSE 1 END*	--目标是收货单
		  CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END*			--抵销单
		  CASE WHEN T1."BaseType"='20' THEN 0 ELSE 1 END*	--来源是收货单
		  (-1*T1."Quantity"+IFNULL(T7."Quantity",0)+IFNULL(T2."CanceledPDNQty",0)
		) AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "剩余数量"
	
	, CASE WHEN (-1*T1."Quantity"+IFNULL(T7."Quantity",0)+IFNULL(T2."CanceledPDNQty",0))=0 THEN 0 ELSE 1 END
	  *CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END --抵销单
	  *CASE WHEN T1."TargetType"='20' THEN 0 ELSE 1 END --目标是收货单
	  *CASE WHEN T1."BaseType"='20' THEN 0 ELSE 1 END	--来源是收货单
	  *CASE WHEN T21."ItemCode"='X0510001' OR T21."InvntItem"='Y' THEN 1 ELSE 0 END		--排除虚拟物料
		*CASE WHEN T1."BaseType"='20' THEN 0 ELSE 1 END
		*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 
		THEN ROUND((-1*T1."Quantity"+IFNULL(T7."Quantity",0)+IFNULL(T2."CanceledPDNQty",0))*T1."U_InitPrice",2)
		ELSE -1*T1."LineTotal"+IFNULL(T7."LineTotal",0)+IFNULL(T2."CanceledPDNAmt",0) 
		END 
		    AS "暂估剩余金额"
	
	,ROUND((-1*T1."Quantity"+IFNULL(T7."Quantity",0)+IFNULL(T2."CanceledPDNQty",0))
	  *CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END --抵销单
	  *CASE WHEN T1."TargetType"='20' THEN 0 ELSE 1 END --目标是收货单
	  *CASE WHEN T1."BaseType"='20' THEN 0 ELSE 1 END	--来源是收货单
	  *CASE WHEN T21."ItemCode"='X0510001' OR T21."InvntItem"='Y' THEN 1 ELSE 0 END		--排除虚拟物料
		*CASE WHEN T1."BaseType"='20' THEN 0 ELSE 1 END
		*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END
		   ,2) AS "剩余金额（老）"
	--当月剩余金额：-1*采购退货金额 + 抵销单的金额 +  应付贷项发票金额 （如果是收货单是抵销单C，则为0）
	, -1*CASE WHEN T0."CANCELED"='C' THEN 0 ELSE 1 END *
		CASE WHEN T1."TargetType"='20' THEN 0 ELSE 1 END*
		CASE WHEN T1."BaseType"='20' THEN 0 ELSE 1 END* 
	    CASE WHEN T21."ItemCode"='X0510001' OR T21."InvntItem"='Y' THEN 1 ELSE 0 END * --排除虚拟物料
		ROUND(CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."Quantity"*T1."U_InitPrice" 
				 WHEN T1."U_IsPrice"='Y' THEN T1."Quantity"*T1."Price"
				 ELSE T1."LineTotal" END,2) --采购退货金额
	   + IFNULL(T2."CanceledPDNAmt",0)	--抵销单的金额
	   + IFNULL(T7."LineTotal",0)		--应付贷项发票
	  AS "当月剩余金额"
	, T0."TransId" AS "交易编码"
	, T1."AcctCode" AS "收入科目" 
	, T0."ObjType"
	, T0."DocEntry"
	, T11."DocNum"  AS "采购收货单号Num"
	, T11."U_SupNum"  AS "采购收单号"
	, T13."DocNum"  AS "采购申请单号Num"
	, T13."U_SupNum"  AS "采购申请单号" 
	,T12."Project" AS "项目"
	,T16."OcrName"  AS "部门" 
	, T7."U_CWNum" AS "财务凭证号"
	, T15."U_SupNum" AS "生产收/退货单号" 
	, T1."BaseType"
	,T1."BaseEntry"
	,T1."BaseLine"
	,T22."ItmsGrpNam"
	FROM ORPD T0  
	INNER JOIN RPD1 T1 ON T0."DocEntry" = T1."DocEntry" 
	LEFT JOIN (SELECT T1."BaseType",T1."BaseEntry",T1."BaseLine"
				,SUM(CASE WHEN T21."ItemCode"='X0510001' OR T21."InvntItem"='Y' THEN 1 ELSE 0 END *CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*T1."Quantity") AS "CanceledPDNQty"
				,SUM(CASE WHEN T21."ItemCode"='X0510001' OR T21."InvntItem"='Y' THEN 1 ELSE 0 END *
						ROUND(CASE WHEN T0."CANCELED"='C' THEN 1 ELSE -1 END*
						CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."Quantity"*T1."U_InitPrice"
								 WHEN T1."U_IsPrice"='Y' THEN T1."Quantity"*T1."Price"
								ELSE T1."LineTotal" END,2)) AS "CanceledPDNAmt"
				FROM "ORPD" T0 JOIN RPD1 T1 ON T0."DocEntry"=T1."DocEntry"
				JOIN OITM T21 ON T1."ItemCode"=T21."ItemCode"
				WHERE T0."DocDate"<=:edate
				GROUP BY T1."BaseType",T1."BaseEntry",T1."BaseLine"
			) T2 ON T0."ObjType"=T2."BaseType" AND T0."DocEntry"=T2."BaseEntry" AND T1."LineNum"=T2."BaseLine"
--LEFT JOIN "MTC_VIEW_CUFD" T2 ON T2."TableID"='ORDN' AND T2."AliasID"='XSDDFL' AND T2."FldValue"=T0."U_XSDDFL"
	LEFT JOIN "@U_CIOTRN" T3 ON T0."U_TrsName"=T3."Code"
	LEFT JOIN OPRC P1 ON T1."OcrCode"=P1."PrcCode"
	LEFT JOIN "OCRD" T5 ON T0."CardCode"=T5."CardCode"
	LEFT JOIN (
				SELECT STRING_AGG(TO_CHAR(T0."DocDate",'YYYY.MM.DD'),',') AS "DocDate"
				,STRING_AGG(CAST(CAST(T1."Price" AS DECIMAL(19,6)) AS NVARCHAR(30)),',') AS "OPCHPrice",STRING_AGG(T2."U_CWNum",',') AS "U_CWNum"
				,T1."BaseEntry",T1."BaseLine",SUM(CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END*T1."Quantity") AS "Quantity"
				,SUM(CASE WHEN T11."ItemCode"='X0510001' OR T11."InvntItem"='Y' THEN 1 ELSE 0 END*T1."LineTotal") AS "LineTotal",SUM(T1."GTotal") AS "GTotal",SUM(T1."GTotalFC") AS "GTotalFC"
				FROM ORPC T0
				LEFT JOIN RPC1 T1 ON T0."DocEntry"=T1."DocEntry"
				LEFT JOIN OJDT T2 ON T2."TransId"=T0."TransId"
				JOIN OITM T11 ON T1."ItemCode"=T11."ItemCode"
				WHERE T0."CANCELED"='N'
				AND T0."DocDate"<=:edate
				GROUP BY T1."BaseEntry",T1."BaseLine"
			) T7 ON T7."BaseEntry"=T1."DocEntry" AND T7."BaseLine"=T1."LineNum"
	
	LEFT JOIN 
	(
			 SELECT "ObjType","DocEntry","LineNum","WhsCode" ,STRING_AGG("BatchNumber",',') AS "BatchNumber"
	         FROM "MTC_VW_DOCLINE"
	         GROUP BY "ObjType","DocEntry","LineNum","WhsCode"
	) T8 ON T8."ObjType"=T1."ObjType" and T8."DocEntry"=T1."DocEntry"  AND T8."LineNum"=T1."LineNum" and T8."WhsCode"=T1."WhsCode"
	LEFT JOIN "PRR1" T9 ON T1."BaseEntry" =T9."DocEntry" AND T1."BaseLine" =T9."LineNum" 
	LEFT JOIN PDN1 T10 ON T9."BaseEntry" =T10."DocEntry" AND T9."BaseLine" =T10."LineNum"
	LEFT JOIN OPDN T11 ON T10."DocEntry" =T11."DocEntry" 
	LEFT JOIN OITM T21 ON T1."ItemCode"=T21."ItemCode"
	LEFT JOIN OITB T22 ON T21."ItmsGrpCod"=T22."ItmsGrpCod"
	LEFT JOIN PDN1 T14 ON T1."BaseEntry" =T14."DocEntry" AND T1."BaseLine" =T14."LineNum" AND T1."BaseType" ='20'
	LEFT JOIN POR1 T12 ON T14."BaseEntry" =T12."DocEntry" AND T14."BaseLine" =T12."LineNum" AND T14."BaseType" ='22'
	LEFT JOIN OPRQ T13 ON T13."DocEntry" =T12."BaseEntry" 
	LEFT JOIN OIGE T15 ON T15."DocEntry" =T1."U_BaseEntry" AND T1."U_BaseType" ='60'
	LEFT JOIN OOCR T16 ON T16."OcrCode" = T12."OcrCode"  
	WHERE 1=1 --AND T0."CANCELED"='N'
	AND  (T0."DocDate">=:sdate OR :sdate='17530101')
	AND (T0."DocDate"<=:edate OR :edate='17530101')
	) T0
	WHERE  1=1 
	AND (T0."供应商编码" LIKE '%'||:CardCode||'%' OR T0."供应商名称" LIKE '%'||:CardCode||'%' OR :CardCode='')
	AND ((:IsOnlyOpen='Y' AND IFNULL(1.00*T0."暂估剩余数量",'0')<>'0') OR :IsOnlyOpen='N')
	ORDER BY T0."类型",T0."收退货单号";
END
