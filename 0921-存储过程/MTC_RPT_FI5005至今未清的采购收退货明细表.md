CREATE PROCEDURE "MTC_RPT_FI5005"
(
  IN sdate DATE,
  IN edate DATE,
  IN CardCode NVARCHAR(50)
)
AS
BEGIN

	SELECT '采购收货单' AS "单据类型",T1."BaseRef" as "采购订单",T7."U_SupNum" as "采购订单号",T0."DocNum" as "收货单"
	,T0."U_SupNum" as "收货单号",NULL AS "退货单",NULL AS "退货单号",T0."CardCode" as "供应商代码",T0."CardName" as "供应商名称"
	,T0."DocDate" as "过账日期",T5."ItemCode" as "物料号"
	,CASE WHEN LEFT(T1."ItemCode",1)='X'THEN T1."U_ItemCode" ELSE '' END "料号"
	,T5."ItemName" as "描述"
	,CASE WHEN LEFT(T1."ItemCode",1)='X'THEN T1."Dscription" ELSE '' END "物料描述"
	,T5."InvntryUom" AS "单位",T5."U_Specs" AS "规格",T1."U_BtchNum" AS "批次号"
	,T1."OpenCreQty" AS "未清数量"
	,T1."Price" AS "未税单价"
	,CAST(CAST(CASE WHEN T5."ItemCode"='X0510001' OR T5."InvntItem"='Y' THEN 1 ELSE 0 END*T1."OpenCreQty" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "计入暂估数量"
	,ROUND(CASE WHEN T5."ItemCode"='X0510001' OR T5."InvntItem"='Y' THEN 1 ELSE 0 END
				*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."OpenCreQty"*T1."U_InitPrice" 
						  WHEN T1."OpenCreQty"<>T1."Quantity" THEN T1."OpenCreQty"*T1."Price" 
						  ELSE T1."LineTotal" END,2) AS "计入暂估金额"
	,CAST(CAST(CASE WHEN T5."ItemCode"='X0510001' OR T5."InvntItem"='Y' THEN 1 ELSE 0 END
				* CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "计入暂估单价"
	,T1."Quantity"-ifnull(T3."FPQTY",0)-ifnull(t4."CGTHQTY",0) AS "参考数量",T6."U_OldSysCode" AS "老系统编码"
	,CASE WHEN T5."ItemCode"='X0510001' THEN '委外费用' ELSE '材料' END AS "类型"
	,T1."LineStatus" AS "状态"
	,T0."DocEntry"
	FROM OPDN T0
	INNER JOIN PDN1 T1 ON T1."DocEntry"=T0."DocEntry"
	LEFT JOIN (
	           ------应付发票数量----
	           SELECT T1."BaseEntry",T1."BaseType",T1."BaseLine",SUM(T1."Quantity") as "FPQTY"
	           FROM OPCH T0
	           INNER JOIN PCH1 T1 ON T1."DocEntry"=T0."DocEntry"
	           WHERE T0."isIns"='N' AND T0."CANCELED"='N'
	           GROUP BY T1."BaseEntry",T1."BaseType",T1."BaseLine" 
	           ) T3 ON T3."BaseEntry"=T1."DocEntry" AND T3."BaseType"=T0."ObjType" AND T3."BaseLine"=T1."LineNum"
	LEFT JOIN (
	           -----采购退货数量------
	           SELECT T1."BaseEntry",T1."BaseLine",T1."BaseType",SUM(T2."CGTHQTY") AS "CGTHQTY"
	           FROM OPRR T0
	           INNER JOIN PRR1 T1 ON T1."DocEntry"=T0."DocEntry"
	           left join (SELECT T1."BaseEntry",T1."BaseType",T1."BaseLine",sum(t1."Quantity") as "CGTHQTY"
	                      FROM ORPD T0
	                      INNER JOIN RPD1 T1 ON T1."DocEntry"=T0."DocEntry"
	                      where T0."CANCELED"='N'
	                      GROUP BY T1."BaseEntry",T1."BaseType",T1."BaseLine"
	                     ) T2 ON T2."BaseEntry"=T1."DocEntry" and T2."BaseType"=T0."ObjType" and T2."BaseLine"=T1."LineNum"
	           where T0."CANCELED"='N'
	           GROUP BY T1."BaseEntry",T1."BaseLine",T1."BaseType"
	           ) T4 ON T4."BaseEntry"=T1."DocEntry" and T4."BaseLine"=T1."LineNum" and T4."BaseType"=T1."ObjType"
	left join OITM T5 ON T5."ItemCode"=T1."ItemCode"  
	LEFT JOIN OCRD T6 ON T0."CardCode"=T6."CardCode"  
	LEFT JOIN OPOR T7 ON T7."DocEntry"=T1."BaseEntry" AND T7."ObjType"= T1."BaseType"
	WHERE T0."CANCELED"='N' 
	AND T1."LineStatus"='O'
--AND T1."Quantity"-ifnull(T3."FPQTY",0)-ifnull(t4."CGTHQTY",0)>0
	AND (T0."DocDate" >= :sdate OR :sdate='17530101')
	AND (T0."DocDate" <= :edate OR :edate='17530101')
	AND (T0."CardCode" LIKE '%'||:CardCode||'%' OR T0."CardName" LIKE '%'||:CardCode||'%' OR ''||:CardCode||''='')
	UNION ALL
	SELECT '采购退货' AS "单据类型",TO_VARCHAR(T9."DocNum") as "采购订单",T9."U_SupNum" as "采购订单号",T8."DocNum" as "收货单",T8."U_SupNum" as "收货单号",T0."DocNum" AS "退货单",T0."U_SupNum" AS "退货单号",T0."CardCode" as "供应商代码",T0."CardName" as "供应商名称"
	,T0."DocDate" as "过账日期",T5."ItemCode" as "物料号"
	,CASE WHEN LEFT(T1."ItemCode",1)='X'THEN T1."U_ItemCode" ELSE '' END "料号"
	,T5."ItemName" as "描述"
	,CASE WHEN LEFT(T1."ItemCode",1)='X'THEN T1."Dscription" ELSE '' END "物料描述"
	,T5."InvntryUom" AS "单位",T5."U_Specs" AS "规格",T1."U_BtchNum" AS "批次号"
	,-1*T1."OpenCreQty" AS "未清数量"
	,T1."Price" AS "未税单价"
	,CAST(CAST(-1*CASE WHEN T5."ItemCode"='X0510001' OR T5."InvntItem"='Y' THEN 1 ELSE 0 END*T1."OpenCreQty" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "计入暂估数量"
	,ROUND(CASE WHEN T5."ItemCode"='X0510001' OR T5."InvntItem"='Y' THEN 1 ELSE 0 END
				*-1*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."OpenCreQty"*T1."U_InitPrice" 
						  WHEN T1."OpenCreQty"<>T1."Quantity" THEN T1."OpenCreQty"*T1."Price" 
						  ELSE T1."LineTotal" END,2) AS "计入暂估金额"
	,CAST(CAST(CASE WHEN T5."ItemCode"='X0510001' OR T5."InvntItem"='Y' THEN 1 ELSE 0 END
				*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "计入暂估单价"
	,-1*(T1."Quantity"-ifnull(T3."FPQTY",0)) AS "参考数量",T6."U_OldSysCode" AS "老系统编码"
	,CASE WHEN T5."ItemCode"='X0510001' THEN '委外费用' ELSE '材料' END AS "类型"
	,T1."LineStatus" AS "状态"
	,T0."DocEntry"
	FROM ORPD T0
	INNER JOIN RPD1 T1 ON T1."DocEntry"=T0."DocEntry"
	LEFT JOIN (
	           ------应付发票数量----
	           SELECT T1."BaseEntry",T1."BaseType",T1."BaseLine",SUM(T1."Quantity") as "FPQTY"
	           FROM ORPC T0
	           INNER JOIN RPC1 T1 ON T1."DocEntry"=T0."DocEntry"
	           WHERE 1=1 AND T0."CANCELED"='N'
	           GROUP BY T1."BaseEntry",T1."BaseType",T1."BaseLine" 
	           ) T3 ON T3."BaseEntry"=T1."DocEntry" AND T3."BaseType"=T0."ObjType" AND T3."BaseLine"=T1."LineNum"
	left join OITM T5 ON T5."ItemCode"=T1."ItemCode"     
	LEFT JOIN OCRD T6 ON T0."CardCode"=T6."CardCode" 
	LEFT JOIN PDN1 T7 ON T7."DocEntry"=T1."U_BaseEntry" AND T7."ObjType"= T1."U_BaseType" AND T7."LineNum"=T1."U_BaseLine"
	LEFT JOIN OPDN T8 ON T8."DocEntry"=T7."DocEntry"
	LEFT JOIN OPOR T9 ON T9."DocEntry"=T7."BaseEntry" AND T9."ObjType"= T7."BaseType"
	WHERE T0."CANCELED"='N'
	AND T1."LineStatus"='O'
	
--AND T1."Quantity"-ifnull(T3."FPQTY",0)>0
	AND (T0."DocDate" >= :sdate OR :sdate='17530101')
	AND (T0."DocDate" <= :edate OR :edate='17530101')
	AND (T0."CardCode" LIKE '%'||:CardCode||'%' OR T0."CardName" LIKE '%'||:CardCode||'%' OR ''||:CardCode||''='')
	ORDER BY "过账日期","收货单";
END
