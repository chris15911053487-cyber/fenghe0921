/* =====================================================================
 * 修正稿：MTC_COST_PROC_CAL_1001_CHECK_DETAIL（未部署，仅供审阅）
 * 底稿：0921-数据库同步/存储过程/MTC_COST_PROC_CAL_1001_CHECK_DETAIL.sql（2026-10-11 同步）
 * 修改：新增 DocType='15' 分支，列出第 15 项“形态转换单不能跨月”不通过的单据行，
 *       给出问题（配对键不全 / 跨月 / 缺转出或转入 / 不是一对一）和同配对键在其他月份的单据。
 *       与 fixes/MTC_COST_PROC_CAL_1001_CHECK.sql 的第 15 项一起部署。
 * ===================================================================== */
CREATE PROCEDURE "MTC_COST_PROC_CAL_1001_CHECK_DETAIL"(IN FcCode NVARCHAR(10),IN DocType NVARCHAR(30))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	--成本检查的明细表
	--6.6.报废仓的库存应该为0

	IF :DocType='4' THEN
		SELECT DISTINCT T0."ObjType",'发货单' AS "单据类型名称",T0."DocEntry" AS "单号Entry",T0."DocNum" AS "单号Num",T0."DocDate" AS "过账日期"
		FROM "OIGE" T0
		JOIN "IGE1" T1 ON T0."DocEntry"=T1."DocEntry"
		JOIN OWOR T2 ON T1."BaseType"='202' AND T1."BaseEntry"=T2."DocEntry"
		WHERE LEFT(T0."DocDate",7)=:FcCode 
		AND T2."U_OrdType"='40'
		AND T0."U_TrsName" NOT IN ('307','305')
		UNION ALL
		SELECT DISTINCT T0."ObjType",'发货单' AS "单据类型名称",T0."DocEntry" AS "单号Entry",T0."DocNum" AS "单号Num",T0."DocDate" AS "过账日期"
		FROM "OIGN" T0
		JOIN "IGN1" T1 ON T0."DocEntry"=T1."DocEntry"
		JOIN OWOR T2 ON T1."BaseType"='202' AND T1."BaseEntry"=T2."DocEntry"
		WHERE LEFT(T0."DocDate",7)=:FcCode 
		AND T2."U_OrdType"='40'
		AND T0."U_TrsName" NOT IN ('307','305');
	
	ELSEIF :DocType='6' THEN
		SELECT T0."ItemCode" AS "物料编码",T1."ItemName" AS "物料名称"
		,SUM(T0."InQty"-T0."OutQty") AS "库存"
		,T0."LocCode" AS "仓库"
		FROM OIVL T0 
		JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
		WHERE TO_CHAR(T0."DocDate",'YYYY-MM')<=:FcCode 
		AND T0."LocCode"='S300'
		GROUP BY T0."ItemCode",T1."ItemName",T0."LocCode"
		HAVING SUM(T0."InQty"-T0."OutQty")<>0;
	
	--7.检查截至到当月尚未关单的
	ELSEIF :DocType='7' THEN
		SELECT '生产工单202' AS "生产订单类型",T1."DocEntry" AS "内部单号",T1."DocNum" AS "订单号Num"
		,T1."U_SupNum" AS "生产订单补充代码"
		,T1."ItemCode" AS "主件编码",T1."ProdName" AS "主件名称"
		,CASE T1."Status" WHEN 'P' THEN '计划' WHEN 'R' THEN '已审批' END AS "订单状态" 
		,T1."PlannedQty" AS "计划数量",T0."WorQty" AS "实际入库数量",T0."DocDate" AS "最后入库日期"
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
		SELECT '返工单MTC_OWOR' AS "WorType",T1."DocEntry",T1."DocNum"
		,T1."U_SupNum" AS "生产订单补充代码"
		,T1."U_ItemCode",T1."U_ProdName"
		,CASE T1."U_Status" WHEN 'P' THEN '计划' WHEN 'R' THEN '已审批' END AS "订单状态" 
		,T1."U_PlannedQty",T0."WorQty",T0."DocDate"
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
		;
	ELSEIF :DocType = '9' THEN
				SELECT '生产订单',A."OWORNum",A."OWOREntry",A."Main_DocDate" AS "入库日期",A."Detail_DocDate" AS "领料日期"
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
				SELECT '返工单',A."BaseEntry",A."BaseLine",A."Main_DocDate" AS "入库日期",A."Detail_DocDate" AS "领料日期"
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
				;
	ELSEIF :DocType='11' THEN
		SELECT DISTINCT '15.1交货引用交货跨月' AS "类型",T0."DocDate" AS "目标单据日期",T2."DocDate" AS "引用源单日期"
				,T0."ObjType" AS "单据类型编码",T0."DocNum" AS "单号Num"
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
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode;
	
	ELSEIF :DocType='12' THEN
		SELECT DISTINCT '20.1收货引用收货跨月' AS "类型",T0."DocDate" AS "目标单据日期",T2."DocDate" AS "引用源单日期",T0."ObjType" AS "单据类型编码",T0."DocNum" AS "单号Num"
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
				AND TO_CHAR(T2."DocDate",'YYYY-MM')<=:FcCode;
	ELSEIF :DocType='13' THEN
		SELECT T0."Type"
				,CASE WHEN T0."ObjType"='59' THEN '其他收货单' WHEN T0."ObjType"='60' THEN '其他发货单' END AS "单据类型"
				,T0."OWOREntry",T0."OWORNum" AS "订单号Num",T0."DocEntry" AS "单号Entry",T0."DocNum" AS "单号Num"
				,T0."DocDate",T1."CloseDate",T0."ItemCode",T0."WhsCode",T0."Quantity"
				FROM "MTC_VIEW_ProductDetail" T0
				INNER JOIN "OWOR" T1 ON T0."OWOREntry"=T1."DocEntry"
				WHERE LEFT(T0."DocDate",7)=:FcCode
				AND T1."Status"='L'
				AND LEFT(T1."CloseDate",7)<LEFT("DocDate",7);	
	ELSEIF :DocType='14' THEN
		SELECT T0."Type"
				,CASE WHEN T0."TransType"='59' THEN '其他收货单' WHEN T0."TransType"='60' THEN '其他发货单' END AS "单据类型"
				,T0."BaseEntry" AS "工单单号Num",T0."CreatedBy" AS "单号Entry",T0."BASE_REF" AS "单号Num"
				,T0."DocDate",T1."U_CloseDate",T0."ItemCode",T0."Quantity"
				FROM "MTC_VIEW_ProductDetail_MTCOWOR" T0
				INNER JOIN "@MTC_OWOR" T1 ON T0."BaseEntry"=T1."DocEntry"
				WHERE LEFT(T0."DocDate",7)=:FcCode
				AND T1."U_Status"='L'
				AND LEFT(T1."U_CloseDate",7)<LEFT("DocDate",7);
	--15.形态转换单不能跨月（修正稿 2026.10.11）
	ELSEIF :DocType='15' THEN
		LT_LINE =
			SELECT '204转入' AS "Side",T0."ObjType",T0."DocEntry",T0."DocNum",T0."DocDate",TO_CHAR(T0."DocDate",'YYYY-MM') AS "Fc"
			,T1."LineNum",T1."ItemCode",T1."Quantity",T1."WhsCode"
			,TO_NVARCHAR(T1."U_BaseType") AS "BT",TO_NVARCHAR(T1."U_BaseEntry") AS "BE",TO_NVARCHAR(T1."U_BaseLineGrpNum") AS "BL"
			FROM "OIGN" T0
			JOIN "IGN1" T1 ON T0."DocEntry"=T1."DocEntry"
			WHERE T0."U_TrsName"='204' AND T0."CANCELED"='N'
			UNION ALL
			SELECT '205转出' AS "Side",T0."ObjType",T0."DocEntry",T0."DocNum",T0."DocDate",TO_CHAR(T0."DocDate",'YYYY-MM') AS "Fc"
			,T1."LineNum",T1."ItemCode",T1."Quantity",T1."WhsCode"
			,TO_NVARCHAR(T1."U_BaseType"),TO_NVARCHAR(T1."U_BaseEntry"),TO_NVARCHAR(T1."U_BaseLineGrpNum")
			FROM "OIGE" T0
			JOIN "IGE1" T1 ON T0."DocEntry"=T1."DocEntry"
			WHERE T0."U_TrsName"='205' AND T0."CANCELED"='N';
		--本月每个配对键下的转入、转出行数
		LT_KEY =
			SELECT IFNULL("BT",'~')||'|'||IFNULL("BE",'~')||'|'||IFNULL("BL",'~') AS "KeyStr"
			,SUM(CASE WHEN "Side"='204转入' THEN 1 ELSE 0 END) AS "NI"
			,SUM(CASE WHEN "Side"='205转出' THEN 1 ELSE 0 END) AS "NO"
			FROM :LT_LINE WHERE "Fc"=:FcCode
			GROUP BY IFNULL("BT",'~')||'|'||IFNULL("BE",'~')||'|'||IFNULL("BL",'~');
		--同配对键在其他月份的单据（判断是跨月还是缺失）
		LT_OTHER =
			SELECT IFNULL("BT",'~')||'|'||IFNULL("BE",'~')||'|'||IFNULL("BL",'~') AS "KeyStr"
			,STRING_AGG("Side"||' '||TO_NVARCHAR("DocNum")||'（'||TO_CHAR("DocDate",'YYYY-MM-DD')||'）','、') AS "Docs"
			FROM :LT_LINE WHERE "Fc"<>:FcCode
			GROUP BY IFNULL("BT",'~')||'|'||IFNULL("BE",'~')||'|'||IFNULL("BL",'~');
		SELECT CASE
				WHEN L."BT" IS NULL OR L."BE" IS NULL OR L."BL" IS NULL THEN '配对键不全：行上的 U_BaseType/U_BaseEntry/U_BaseLineGrpNum 有空值'
				WHEN K."NO"=0 AND O."Docs" IS NOT NULL THEN '跨月：同配对键的205转出单不在本月'
				WHEN K."NI"=0 AND O."Docs" IS NOT NULL THEN '跨月：同配对键的204转入单不在本月'
				WHEN K."NO"=0 THEN '缺转出：本月有204转入，找不到同配对键的205转出单'
				WHEN K."NI"=0 THEN '缺转入：本月有205转出，找不到同配对键的204转入单'
				ELSE '不是一对一：本月同配对键有 '||TO_NVARCHAR(K."NO")||' 行转出、'||TO_NVARCHAR(K."NI")||' 行转入'
				END AS "问题"
		,L."Side" AS "方向"
		,CASE WHEN L."ObjType"='59' THEN '其他收货单' WHEN L."ObjType"='60' THEN '其他发货单' END AS "单据类型"
		,L."DocEntry" AS "单号Entry",L."DocNum" AS "单号Num",L."DocDate" AS "过账日期",L."LineNum" AS "行号"
		,L."ItemCode" AS "物料编码",L."Quantity" AS "数量",L."WhsCode" AS "仓库"
		,IFNULL(L."BT",'(空)')||' / '||IFNULL(L."BE",'(空)')||' / '||IFNULL(L."BL",'(空)') AS "配对键"
		,O."Docs" AS "同配对键其他月份单据"
		FROM :LT_LINE L
		JOIN :LT_KEY K ON K."KeyStr"=IFNULL(L."BT",'~')||'|'||IFNULL(L."BE",'~')||'|'||IFNULL(L."BL",'~')
		LEFT JOIN :LT_OTHER O ON O."KeyStr"=K."KeyStr"
		WHERE L."Fc"=:FcCode
		AND (L."BT" IS NULL OR L."BE" IS NULL OR L."BL" IS NULL OR K."NI"<>1 OR K."NO"<>1)
		ORDER BY 1,L."BE",L."BL",L."Side";
	END IF;


END