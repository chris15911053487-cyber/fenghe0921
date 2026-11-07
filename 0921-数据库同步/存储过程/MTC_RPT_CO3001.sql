CREATE PROCEDURE "MTC_RPT_CO3001"
(
  UserId INT,
  FromFcCode NVARCHAR(30),
  ToFcCode NVARCHAR(30),
  ItemCode NVARCHAR(50),
  ItmsGrpCod INT
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 
	
	IF :FromFcCode <> :ToFcCode THEN
	
		TMP_Detail=
		SELECT :FromFcCode||'~'||:ToFcCode AS "FcCode",
		NULL AS "成本类型",
		T1."ItemCode",
		T1."ItemName" AS "物料名称",
		T1."InvntryUom" AS "单位",
		T0."QC_Qty" AS "期初数量",
		T0."QC_Price" AS "期初单价", 
		T0."QC_Amount" AS "期初金额",
		T0."In_Qty" AS "入库数量",
		T0."In_Price" AS "入库单价",
		T0."In_Amount" AS "入库金额",
		T0."Out_Qty" AS "出库数量",
		T0."Out_Price" AS "出库单价",
		T0."Out_Amount" AS "出库金额",
		T0."QM_Qty" AS "期末数量",
		T0."QM_Price" AS "期末单价",
		ROUND(T0."QM_Amount",2) AS "期末金额",
		T0."Price" AS "单价",
		NULL AS "创建时间",
		NULL AS "创建人",
		NULL AS "计算类型",
		NULL AS "计算级别",
		T2."ItmsGrpCod" AS "物料组编码" ,
		T2."ItmsGrpNam" AS "物料组名称",
		T4."AcctCode" AS "科目编码",
		T4."AcctName" AS "科目名称",
		NULL AS "价格更新来源"
		FROM 
			(SELECT "ItemCode",SUM("QC_Qty") AS "QC_Qty",SUM("QC_Price") AS "QC_Price",SUM("QC_Amount") AS "QC_Amount"
					,SUM("In_Qty") AS "In_Qty",SUM("In_Amount")/NULLIF(SUM("In_Qty"),0) AS "In_Price",SUM("In_Amount") AS "In_Amount"
					,SUM("Out_Qty") AS "Out_Qty",SUM("Out_Amount")/NULLIF(SUM("Out_Qty"),0) AS "Out_Price",SUM("Out_Amount") AS "Out_Amount"
					,SUM("QM_Qty") AS "QM_Qty",SUM("QM_Price") AS "QM_Price",SUM("QM_Amount") AS "QM_Amount",SUM("Price") AS "Price"
			 FROM 
				(SELECT "ItemCode","QC_Qty","QC_Price","QC_Amount"
					,"In_Qty",0 AS "In_Price","In_Amount"
					,"Out_Qty",0 AS "Out_Price","Out_Amount"
					,0 AS "QM_Qty",0 AS "QM_Price",0 AS "QM_Amount",0 AS "Price"
					FROM MTC_COST_0301_INVNT
					WHERE "FcCode"=:FromFcCode
					AND "CostCode"='20'
				 UNION ALL
				 SELECT  "ItemCode",0 AS "QC_Qty",0 AS "QC_Price",0 AS "QC_Amount"
					,"In_Qty",0 AS "In_Price","In_Amount"
					,"Out_Qty",0 AS "Out_Price","Out_Amount"
					,0 AS "QM_Qty",0 AS "QM_Price",0 AS "QM_Amount",0 AS "Price"
					FROM MTC_COST_0301_INVNT
					WHERE "FcCode">:FromFcCode
					AND "FcCode"<:ToFcCode
					AND "CostCode"='20'
				 UNION ALL
				 SELECT  "ItemCode",0 AS "QC_Qty",0 AS "QC_Price",0 AS "QC_Amount"
					,"In_Qty",0 AS "In_Price","In_Amount"
					,"Out_Qty",0 AS "Out_Price","Out_Amount"
					,"QM_Qty","QM_Price","QM_Amount","Price"
					FROM MTC_COST_0301_INVNT
					WHERE "FcCode"=:ToFcCode
					AND "CostCode"='20'
				) T0 GROUP BY "ItemCode"
			) T0
		JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
		LEFT JOIN OITB T2 ON T1."ItmsGrpCod"=T2."ItmsGrpCod"
		LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct",MAX("ShpdGdsAct") AS "ShpdGdsAct"
				FROM OGAR WHERE "PeriodCat"=LEFT(:ToFcCode,4) GROUP BY "ItmsGrpCod"
			) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
		LEFT JOIN "OACT" T4 ON T3."StockAct"=T4."AcctCode"
		WHERE 1=1
		AND (T1."ItemCode" = :ItemCode OR :ItemCode='')
		AND (T2."ItmsGrpCod"=:ItmsGrpCod OR :ItmsGrpCod=0)
		AND T1."InvntItem"='Y'
--AND (IFNULL(T0."QC_Qty",0)<>0 OR IFNULL(T0."In_Qty",0)<>0 OR IFNULL(T0."Out_Qty",0)<>0 OR IFNULL(T0."QM_Qty",0)<>0)
		ORDER BY T0."ItemCode";
	else
		TMP_Detail=
		SELECT :FromFcCode||'~'||:ToFcCode AS "FcCode",
		T0."CostCode" AS "成本类型",
		T0."ItemCode",
		T0."ItemName" AS "物料名称",
		T1."InvntryUom" AS "单位",
		T0."QC_Qty" AS "期初数量",
		T0."QC_Price" AS "期初单价", 
		T0."QC_Amount" AS "期初金额",
		T0."In_Qty" AS "入库数量",
		T0."In_Price" AS "入库单价",
		T0."In_Amount" AS "入库金额",
		T0."Out_Qty" AS "出库数量",
		T0."Out_Price" AS "出库单价",
		T0."Out_Amount" AS "出库金额",
		T0."QM_Qty" AS "期末数量",
		T0."QM_Price" AS "期末单价",
		ROUND(T0."QM_Amount",2) AS "期末金额",
		T0."Price" AS "单价",
		T0."CreateDate" AS "创建时间",
		T0."Creator" AS "创建人",
		T0."CalType" AS "计算类型",
		T0."iLevel" AS "计算级别",
		T0."ItmsGrpCod" AS "物料组编码" ,
		T2."ItmsGrpNam" AS "物料组名称",
		T4."AcctCode" AS "科目编码",
		T4."AcctName" AS "科目名称",
		T0."PriceMemo" AS "价格更新来源"
		FROM MTC_COST_0301_INVNT T0
		JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
		LEFT JOIN OITB T2 ON T0."ItmsGrpCod"=T2."ItmsGrpCod"
		LEFT JOIN (SELECT "ItmsGrpCod",MAX("StockAct") AS "StockAct",MAX("ShpdGdsAct") AS "ShpdGdsAct"
				FROM OGAR WHERE "PeriodCat"=LEFT(:ToFcCode,4) GROUP BY "ItmsGrpCod"
			) T3 ON T2."ItmsGrpCod"=T3."ItmsGrpCod"
		LEFT JOIN "OACT" T4 ON T3."StockAct"=T4."AcctCode"
		WHERE T0."FcCode" = :ToFcCode
		AND (T0."ItemCode" = :ItemCode OR :ItemCode='')
		AND (T2."ItmsGrpCod"=:ItmsGrpCod OR :ItmsGrpCod=0)
		AND T1."InvntItem"='Y'
		AND T0."CostCode"='20'
--AND (IFNULL(T0."QC_Qty",0)<>0 OR IFNULL(T0."In_Qty",0)<>0 OR IFNULL(T0."Out_Qty",0)<>0 OR IFNULL(T0."QM_Qty",0)<>0)
		ORDER BY T0."ItemCode";
	
	END IF;
	
	SELECT T0."FcCode",
	T0."成本类型",
	T0."ItemCode",
	T0."物料名称",
	T0."单位",
	CAST(CAST(T0."期初数量" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "期初数量",
	CAST(CAST(T0."期初单价" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "期初单价", 
	T0."期初金额",
	CAST(CAST(T0."入库数量" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "入库数量",
	CAST(CAST(T0."入库单价" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "入库单价",
	T0."入库金额",
	CAST(CAST(T0."出库数量" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "出库数量",
	CAST(CAST(T0."出库单价" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "出库单价",
	T0."出库金额" AS "出库金额",
	CAST(CAST(T0."期末数量" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "期末数量",
	CAST(CAST(T0."期末单价" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "期末单价",
	T0."期末金额",
	CAST(CAST(T0."单价" AS DECIMAL(19,6)) AS NVARCHAR(30)) AS "单价",
	T0."创建时间",
	T0."创建人",
	T0."计算类型",
	T0."计算级别",
	T0."物料组编码" ,
	T0."物料组名称",
	T0."科目编码",
	T0."科目名称",
	T0."价格更新来源",
	1 AS "ID",
	:FromFcCode AS "FromFcCode",
	:ToFcCode AS "ToFcCode"
	FROM :TMP_Detail T0
	
	UNION ALL
	SELECT T0."FcCode",
	NULL AS "成本类型",
	NULL AS "ItemCode",
	NULL AS "物料名称",
	NULL AS "单位",
	SUM(T0."期初数量"),
	NULL AS "期初单价", 
	SUM(T0."期初金额"),
	SUM(T0."入库数量"),
	NULL AS "入库单价",
	SUM(T0."入库金额"),
	SUM(T0."出库数量"),
	NULL AS "出库单价",
	SUM(T0."出库金额"),
	SUM(T0."期末数量"),
	NULL AS "期末单价",
	SUM(T0."期末金额"),
	NULL AS "单价",
	NULL AS "创建时间",
	NULL AS "创建人",
	NULL AS "计算类型",
	NULL AS "计算级别",
	T0."物料组编码" ,
	T0."物料组名称" || ' 合计',
	T0."科目编码",
	T0."科目名称" || ' 合计',
	NULL AS "价格更新来源",
	2 AS "ID",
	:FromFcCode AS "FromFcCode",
	:ToFcCode AS "ToFcCode"
	FROM :TMP_Detail T0
	GROUP BY T0."FcCode",T0."成本类型",T0."物料组编码",T0."物料组名称",T0."科目编码",	T0."科目名称"
	
	UNION ALL
	SELECT T0."FcCode",
	NULL AS "成本类型",
	NULL AS "ItemCode",
	NULL AS "物料名称",
	NULL AS "单位",
	SUM(T0."期初数量"),
	NULL AS "期初单价", 
	SUM(T0."期初金额"),
	SUM(T0."入库数量"),
	NULL AS "入库单价",
	SUM(T0."入库金额"),
	SUM(T0."出库数量"),
	NULL AS "出库单价",
	SUM(T0."出库金额"),
	SUM(T0."期末数量"),
	NULL AS "期末单价",
	SUM(T0."期末金额"),
	NULL AS "单价",
	NULL AS "创建时间",
	NULL AS "创建人",
	NULL AS "计算类型",
	NULL AS "计算级别",
	NULL AS "物料组编码" ,
	'合计',
	NULL AS "科目编码",
	NULL AS "科目名称",
	NULL AS "价格更新来源",
	3 AS "ID",
	:FromFcCode AS "FromFcCode",
	:ToFcCode AS "ToFcCode"
	FROM :TMP_Detail T0
	GROUP BY T0."FcCode",T0."成本类型"
	
	ORDER BY "ID","ItemCode"
	;
	
	
END