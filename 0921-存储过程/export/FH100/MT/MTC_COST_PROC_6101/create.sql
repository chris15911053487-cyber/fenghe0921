CREATE PROCEDURE "MTC_COST_PROC_6101"
(
  UserCode NVARCHAR(50),
  FcCode NVARCHAR(50)
)
AS
BEGIN
 
		TMP=

		SELECT CASE WHEN T5."ItemCode"='X0510001' THEN '委外费用' ELSE '材料' END AS "Type"
		,T0."ObjType",'采购收货单' AS "DocName",T0."DocEntry",T0."DocNum",T1."LineNum",T0."CardCode",T0."CardName"
		,T0."DocDate",T5."ItemCode",T5."ItemName",T1."OpenQty"
		,T1."OpenQty"*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS "Amount"
		,CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS "Price"
		,T1."Quantity"-ifnull(T3."FPQTY",0)-ifnull(t4."CGTHQTY",0)-IFNULL(T9."RPDQty",0) AS "参考数量"
		--,T6."U_OldSysCode" AS "老系统编码"
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
		LEFT JOIN (
		           -----采购退货数量------
		           SELECT T1."BaseEntry",T1."BaseLine",T1."BaseType",SUM(T1."Quantity") AS "RPDQty"
		           FROM ORPD T0
		           INNER JOIN RPD1 T1 ON T1."DocEntry"=T0."DocEntry"
		           where T0."CANCELED"='N'
		           GROUP BY T1."BaseEntry",T1."BaseLine",T1."BaseType"
		           ) T9 ON T9."BaseEntry"=T1."DocEntry" and T9."BaseLine"=T1."LineNum" and T9."BaseType"=T1."ObjType"
		left join OITM T5 ON T5."ItemCode"=T1."ItemCode"  
		LEFT JOIN OCRD T6 ON T0."CardCode"=T6."CardCode"               
		WHERE T0."CANCELED"='N' 
		AND T1."OpenQty">0
		AND T1."LineStatus"='O'
		AND (LEFT(T0."DocDate",7)<=:FcCode)
		
		UNION ALL
		SELECT CASE WHEN T5."ItemCode"='X0510001' THEN '委外费用' ELSE '材料' END AS "Type"
		,T0."ObjType",'采购退货单' AS "DocName",T0."DocEntry",T0."DocNum",T1."LineNum",T0."CardCode",T0."CardName"
		,T0."DocDate",T5."ItemCode",T5."ItemName",-1*T1."OpenQty"
		,-1*T1."OpenQty"*CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS "Amount"
		,CASE WHEN IFNULL(T1."U_InitPrice",0)<>0 THEN T1."U_InitPrice" ELSE T1."Price" END AS "Price"
		,-1*(IFNULL(T1."Quantity",0)-IFNULL(T3."FPQTY",0))
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
		WHERE T0."CANCELED"='N'
		AND T1."OpenQty">0
		AND T1."LineStatus"='O'
		AND (LEFT(T0."DocDate",7)<=:FcCode)
		ORDER BY "DocDate","CardCode";
		
		SELECT * FROM :TMP T0 
		ORDER BY T0."Type",T0."DocDate",T0."CardCode";
END