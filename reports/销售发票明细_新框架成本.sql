--销售发票明细（用户 2026-11-05，未部署）：成本从旧 0302 改取新框架，依赖表函数 MTC_RPT_F_SALE_COST（reports/MTC_RPT_F_SALE_COST.sql，先建）
--成本取发票基于的交货 / 退货行单价（取消单经原发票找），不是发票账期的单价；成本金额 = 单价 × 发票数量，保留 2 位
select *
from 
(
select '应收发票' AS "类型"
,CASE T0."DocType" WHEN 'I' THEN '物料' WHEN 'S' THEN '服务' END as  "单据类型"
,CASE WHEN t0."CANCELED" = 'Y' 
    THEN '已取消' WHEN T0."CANCELED"='C' 
    THEN '抵销单' WHEN t1."LineStatus" = 'O' 
    THEN '未清' 
    ELSE '已结算' 
    END AS "状态"
,t0."DocDate" as "过账日期"
,T0."ObjType"
,t0."DocEntry"
,T0."DocNum" AS "单号"
, T0."DocCur" AS "币种"
, T0."DocRate" AS "汇率"
,T1."LineNum" AS "行号"
,T0."U_SalOrdType" AS "销售订单类型"
,t0."CardCode" as "客户编码"
,t0."CardName" as "客户名称"
,T8."GroupName" AS "客户组"
,t1."ItemCode" as "物料编码"
,t3."ItemName" as "物料描述" 
,t1."U_Specs" AS "规格"
,T9."ItmsGrpNam" AS "物料组"
,t1."unitMsr" as "单位" 
,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * t1."Quantity" as "数量"
,t1."PriceAfVAT" as "含税单价"
,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * (t1."LineTotal"+t1."VatSum") as "含税金额(本币)"
,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * (t1."TotalFrgn"+T1."VatSumFrgn") as "含税金额(外币)"
,t1."Price" as "未税单价"
,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * t1."LineTotal" as "未税金额(本币)"
,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * t1."TotalFrgn" as "未税金额(外币)"
,CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * t1."VatSum" as "税额"
,COALESCE(T23."DocDate",T33."DocDate") AS "交货单日期"
,COALESCE(T22."Price",T32."Price") AS "成本单价"
,ROUND(COALESCE(T22."Price",T32."Price")
    *CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END *T1."Quantity",2) AS "成本金额"
,CASE COALESCE(T22."CostSrc",T32."CostSrc") WHEN 'NEW' THEN '新框架' WHEN 'HIST' THEN '历史运行（旧框架回填）'
    WHEN 'INIT' THEN '行上指定单价 U_InitPrice' WHEN 'OLD' THEN '旧框架 0302（该期未回填）' END AS "成本来源"
,t1."VatPrcnt" as "税率%",t1."WhsCode" as "仓库" ,T7."WhsName" as "仓库名称"
,t0."Comments" as "备注"
,P1."PrcCode" AS "成本部门编码"
,P1."PrcName" AS "成本部门名称"
,T1."AcctCode" AS "收入科目" 
,T1."CogsAcct" AS "成本科目"
,t0."TransId" as "分录号"
,T0."U_InvNum" AS "发票号"
,t5."SlpName" as "销售员",t6."U_NAME" as "制单人"
,CASE WHEN T0."CANCELED"='C' THEN T31."ObjType" ELSE t1."BaseType" END as "源单类型"
,CASE WHEN T0."CANCELED"='C' THEN T31."DocEntry" ELSE t1."BaseEntry" END as "源单单号"
,CASE WHEN T0."CANCELED"='C' THEN T31."LineNum" ELSE t1."BaseLine" END as "源单行号" 
FROM OINV t0 
JOIN INV1 t1 ON t0."DocEntry" = t1."DocEntry" 
JOIN OCRD t2 ON t0."CardCode" = t2."CardCode" 
LEFT JOIN OITM t3 ON t1."ItemCode" = t3."ItemCode"
left join OSLP t5 on t0."SlpCode"=t5."SlpCode" 
left join OUSR t6 on t0."UserSign"=t6."USERID"
LEFT JOIN OWHS T7 ON T7."WhsCode"=t1."WhsCode"
JOIN "OCRG" T8 ON T2."GroupCode"=T8."GroupCode"
LEFT JOIN "OITB" T9 ON T3."ItmsGrpCod"=T9."ItmsGrpCod"
LEFT JOIN OPRC P1 ON T1."OcrCode"=P1."PrcCode"
--关联交货单的单价
LEFT JOIN DLN1 T21 ON T1."BaseType"=T21."ObjType" AND T1."BaseEntry"=T21."DocEntry" AND T1."BaseLine"=T21."LineNum"
LEFT JOIN ODLN T23 ON T21."DocEntry"=T23."DocEntry"
LEFT JOIN "MTC_RPT_F_SALE_COST"() T22 ON T21."ObjType"=T22."ObjType" AND T21."DocEntry"=T22."DocEntry" AND T21."LineNum"=T22."LineNum"
--关联取消的发票对应的交货单价
LEFT JOIN INV1 T30 ON T1."BaseType"=T30."ObjType" AND T1."BaseEntry"=T30."DocEntry" AND T1."BaseLine"=T30."LineNum"
LEFT JOIN DLN1 T31 ON T30."BaseType"=T31."ObjType" AND T30."BaseEntry"=T31."DocEntry" AND T30."BaseLine"=T31."LineNum"
LEFT JOIN ODLN T33 ON T31."DocEntry"=T33."DocEntry"
LEFT JOIN "MTC_RPT_F_SALE_COST"() T32 ON T31."ObjType"=T32."ObjType" AND T31."DocEntry"=T32."DocEntry" AND T31."LineNum"=T32."LineNum"
WHERE 1=1


UNION ALL 

select '应收贷项' AS "类型"
,CASE T0."DocType" WHEN 'I' THEN '物料' WHEN 'S' THEN '服务' END as  "单据类型"
,CASE WHEN t0."CANCELED" = 'Y' 
    THEN '已取消' WHEN T0."CANCELED"='C' 
    THEN '抵销单' WHEN t1."LineStatus" = 'O' 
    THEN '未清' 
    ELSE '已结算' 
    END AS "状态"
,t0."DocDate" as "过账日期"
,T0."ObjType"
,t0."DocEntry"
,T0."DocNum" AS "单号"
, T0."DocCur" AS "币种"
, T0."DocRate" AS "汇率"
,T1."LineNum" AS "行号"
,T0."U_SalOrdType" AS "销售订单类型"
,t0."CardCode" as "客户编码",t0."CardName" as "客户名称",T8."GroupName" AS "客户组"
,t1."ItemCode" as "物料编码",t3."ItemName" as "物料描述" ,t1."U_Specs" AS "规格"
,T9."ItmsGrpNam"
,t1."unitMsr" as "单位" 
,-1 * CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * t1."Quantity" as "数量"
,t1."PriceAfVAT" as "含税单价"
,-1 * CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * (t1."LineTotal"+T1."VatSum") as "含税金额(本币)"
,-1 * CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * (t1."TotalFrgn"+T1."VatSumFrgn") as "含税金额(外币)"
,t1."Price" as "未税单价"
,-1 * CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * t1."LineTotal" as "未税金额(本币)"
,-1 * CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * t1."TotalFrgn" as "未税金额(外币)"
,-1 * CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END * t1."VatSum" as "税额"
,T23."DocDate" AS "交货单日期"
,COALESCE(T22."Price",T32."Price") AS "成本单价"
,ROUND(COALESCE(T22."Price",T32."Price")
*-1*CASE WHEN T0."CANCELED"='C' THEN -1 ELSE 1 END*T1."Quantity",2) AS "成本金额"
,CASE COALESCE(T22."CostSrc",T32."CostSrc") WHEN 'NEW' THEN '新框架' WHEN 'HIST' THEN '历史运行（旧框架回填）'
    WHEN 'INIT' THEN '行上指定单价 U_InitPrice' WHEN 'OLD' THEN '旧框架 0302（该期未回填）' END AS "成本来源"
,t1."VatPrcnt" as "税率%",t1."WhsCode" as "仓库" ,T7."WhsName" as "仓库名称"
,t0."Comments" as "备注"
,P1."PrcCode" AS "成本部门编码"
,P1."PrcName" AS "成本部门名称"
,T1."AcctCode" AS "收入科目" 
,T1."CogsAcct" AS "成本科目"
,t0."TransId" as "分录号"
,T0."U_InvNum" AS "发票号"
,t5."SlpName" as "销售员",t6."U_NAME" as "制单人"
,t1."BaseType" as "源单类型",t1."BaseEntry" as "源单单号",t1."BaseLine" as "源单行号" 
FROM ORIN t0 
JOIN RIN1 t1 ON t0."DocEntry" = t1."DocEntry" 
JOIN OCRD t2 ON t0."CardCode" = t2."CardCode" 
LEFT JOIN OITM t3 ON t1."ItemCode" = t3."ItemCode"
left join OSLP t5 on t0."SlpCode"=t5."SlpCode" 
left join OUSR t6 on t0."UserSign"=t6."USERID"
LEFT JOIN OWHS T7 ON T7."WhsCode"=t1."WhsCode"
JOIN "OCRG" T8 ON T2."GroupCode"=T8."GroupCode"
LEFT JOIN "OITB" T9 ON T3."ItmsGrpCod"=T9."ItmsGrpCod"
LEFT JOIN OPRC P1 ON T1."OcrCode"=P1."PrcCode"

--关联退货单的单价
LEFT JOIN RDN1 T21 ON T1."BaseType"=T21."ObjType" AND T1."BaseEntry"=T21."DocEntry" AND T1."BaseLine"=T21."LineNum"
LEFT JOIN ORDN T23 ON T21."DocEntry"=T23."DocEntry"
LEFT JOIN "MTC_RPT_F_SALE_COST"() T22 ON T21."ObjType"=T22."ObjType" AND T21."DocEntry"=T22."DocEntry" AND T21."LineNum"=T22."LineNum"
--关联取消的贷项发票对应的退货单价
LEFT JOIN RIN1 T30 ON T1."BaseType"=T30."ObjType" AND T1."BaseEntry"=T30."DocEntry" AND T1."BaseLine"=T30."LineNum"
LEFT JOIN RDN1 T31 ON T30."BaseType"=T31."ObjType" AND T30."BaseEntry"=T31."DocEntry" AND T30."BaseLine"=T31."LineNum"
LEFT JOIN ORDN T33 ON T31."DocEntry"=T33."DocEntry"
LEFT JOIN "MTC_RPT_F_SALE_COST"() T32 ON T31."ObjType"=T32."ObjType" AND T31."DocEntry"=T32."DocEntry" AND T31."LineNum"=T32."LineNum"
                    

) T0
where 1=1
and (t0."过账日期" >= '[%0]' OR '[%0]' = '17530101')  
and (t0."过账日期" <= '[%1]' OR '[%1]' = '17530101')
and (t0."客户编码"='[%2]' OR '[%2]'='')
ORDER BY T0."过账日期",T0."单号"
