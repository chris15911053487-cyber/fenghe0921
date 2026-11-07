CREATE PROCEDURE "MTC_RPT_FI6003"
(
	IN STYPE NVARCHAR(30),
	IN EDATE DATE,
	IN ItemCode NVARCHAR(50) DEFAULT ''
)
LANGUAGE SQLSCRIPT
AS
Begin

--库龄
	--CALL "MTC_RPT_FI6003"('BatchNum','2025-12-31')
  
  --小于30天	30-59天	60-89天	90-119天	120-359天	大于359天
  
  IF :STYPE = 'BatchNum' OR :STYPE = 'All' THEN 
	TMP_BatchNum=
	SELECT  
	CASE WHEN T2."ManBtchNum"='Y' THEN '批次管理' WHEN T2."ManSerNum"='Y' THEN '序列号管理' ELSE '无' END AS "物料管理类型",
	T0."ItemCode" AS "物料编码", T2."ItemName" AS "物料名称",T3."ItmsGrpNam" AS "物料组",
	T0."WhsCode" AS "仓库编码",
	T0."WhsName" AS "仓库名称",
	T0."BatchEntry" AS "批次ID",
	T0."BatchNumber" AS "批次",
	T4."InDate" AS "批次入库日期",
	DAYS_BETWEEN (T4."InDate",CURRENT_DATE) AS "在库时长",
	T0."小于30天数量",	
	T0."30-59天数量",	
	T0."60-89天数量" ,	
	T0."90-119天数量" ,	
	T0."120-359天数量" ,	
	T0."大于359天数量",
	T0."EQty" AS "数量总计", 
	T9."Price" AS "成本单价",
	ROUND(T0."EQty"*T9."Price",2) AS "成本金额",
	ROW_NUMBER() OVER(PARTITION BY T0."ItemCode" ORDER BY ROUND(T0."EQty"*T9."Price",2) DESC) AS "ID"
	FROM  
	(
	SELECT T0."ItemCode",T2."WhsName" AS "WhsName",T2."WhsCode",T0."BatchEntry",T0."BatchNumber",
	sum(T0."Quantity") AS "EQty",  
	
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<=:EDATE THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		WHEN Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 29) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")>0 
			THEN Sum(CASE WHEN T0."DocDate">=ADD_DAYS(to_date(:EDATE),- 29) AND T0."DocDate"<=:EDATE THEN T0."InQty" ELSE 0 END) 
		ELSE Sum(CASE WHEN T0."DocDate"<=:EDATE THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "小于30天数量",
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 29) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		WHEN Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 59) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")>0 
			THEN Sum(CASE WHEN T0."DocDate" >= ADD_DAYS(to_date(:EDATE ),- 59)  and T0."DocDate" < ADD_DAYS(to_date(:EDATE ),- 29)
			THEN T0."InQty" ELSE 0 END) 
		ELSE Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 29) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "30-59天数量",
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 59) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		WHEN Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 89) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")>0 
			THEN Sum(CASE WHEN T0."DocDate" >= ADD_DAYS(to_date(:EDATE ),- 89)  and T0."DocDate" < ADD_DAYS(to_date(:EDATE ),- 59)
			THEN T0."InQty" ELSE 0 END) 
		ELSE Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 59) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "60-89天数量",
	
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 89) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		WHEN Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 119) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")>0 
			THEN Sum(CASE WHEN T0."DocDate" >= ADD_DAYS(to_date(:EDATE ),- 119)  and T0."DocDate" < ADD_DAYS(to_date(:EDATE ),- 89)
			THEN T0."InQty" ELSE 0 END) 
		ELSE Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 89) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "90-119天数量",
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 119) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		WHEN Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 359) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")>0 
			THEN Sum(CASE WHEN T0."DocDate" >= ADD_DAYS(to_date(:EDATE ),- 359)  and T0."DocDate" < ADD_DAYS(to_date(:EDATE ),- 119)
			THEN T0."InQty" ELSE 0 END) 
		ELSE Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 119) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "120-359天数量",
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 359) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		ELSE Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 359) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "大于359天数量"
	FROM "MTC_VW_DOCLINE_AGING_BATCHNUM" T0
	INNER JOIN OWHS T2 ON T0."WhsCode"=T2."WhsCode" 
	WHERE (T0."DocDate" <= :EDATE )
	AND (T0."ItemCode"=:ItemCode OR :ItemCode='')
	GROUP BY T0."ItemCode", T2."WhsName",T2."WhsCode",T0."BatchEntry",T0."BatchNumber"
	 )T0       
	INNER JOIN OITM T2 ON T0."ItemCode" = T2."ItemCode"
	INNER JOIN OITB T3 ON T2."ItmsGrpCod" = T3."ItmsGrpCod"  
	LEFT JOIN "OBTN" T4 ON T0."BatchEntry"=T4."AbsEntry"
	LEFT JOIN (SELECT "ItemCode","Price" FROM "MTC_COST_0301_INVNT" 
			WHERE 1=1 AND "CostCode"='20' AND "FcCode"=TO_CHAR(:EDATE,'YYYY-MM')) T9 ON T2."ItemCode"=T9."ItemCode"
	WHERE 1=1 AND IFNULL(T0."EQty",0)<>0
	AND T2."ManBtchNum"='Y'
	ORDER BY T0."ItemCode",T0."WhsCode",T0."BatchEntry",T0."BatchNumber",T4."InDate";
  END IF;
  
  IF :STYPE='SerNum' OR :STYPE = 'All' THEN
  	
  	TMP_SerNum=
  	SELECT  
	CASE WHEN T2."ManBtchNum"='Y' THEN '批次管理' WHEN T2."ManSerNum"='Y' THEN '序列号管理' ELSE '无' END AS "物料管理类型",
	T0."ItemCode" AS "物料编码", T2."ItemName" AS "物料名称",T3."ItmsGrpNam" AS "物料组",
	T0."WhsCode" AS "仓库编码",
	T0."WhsName" AS "仓库名称",
	NULL AS "序列号ID",
	T0."SerNum" AS "序列号",
	T0."InDate" AS "序列号入库日期",
	DAYS_BETWEEN (T0."InDate",CURRENT_DATE) AS "在库时长",
	T0."小于30天数量",	
	T0."30-59天数量",	
	T0."60-89天数量" ,	
	T0."90-119天数量" ,	
	T0."120-359天数量" ,	
	T0."大于359天数量",
	T0."EQty" AS "数量总计", 
	T9."Price" AS "成本单价",
	ROUND(T0."EQty"*T9."Price",2) AS "成本金额",
	ROW_NUMBER() OVER(PARTITION BY T0."ItemCode" ORDER BY ROUND(T0."EQty"*T9."Price",2) DESC) AS "ID"
	
	FROM  
	(
	SELECT T0."ItemCode",T2."WhsName" AS "WhsName",T2."WhsCode",LEFT(T0."BatchEntry",6) AS "SerNum",T4."InDate",
	sum(T0."Quantity") AS "EQty",  
	
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<=:EDATE THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		WHEN Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 29) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")>0 
			THEN Sum(CASE WHEN T0."DocDate">=ADD_DAYS(to_date(:EDATE),- 29) AND T0."DocDate"<=:EDATE THEN T0."InQty" ELSE 0 END) 
		ELSE Sum(CASE WHEN T0."DocDate"<=:EDATE THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "小于30天数量",
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 29) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		WHEN Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 59) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")>0 
			THEN Sum(CASE WHEN T0."DocDate" >= ADD_DAYS(to_date(:EDATE ),- 59)  and T0."DocDate" < ADD_DAYS(to_date(:EDATE ),- 29)
			THEN T0."InQty" ELSE 0 END) 
		ELSE Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 29) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "30-59天数量",
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 59) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		WHEN Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 89) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")>0 
			THEN Sum(CASE WHEN T0."DocDate" >= ADD_DAYS(to_date(:EDATE ),- 89)  and T0."DocDate" < ADD_DAYS(to_date(:EDATE ),- 59)
			THEN T0."InQty" ELSE 0 END) 
		ELSE Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 59) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "60-89天数量",
	
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 89) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		WHEN Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 119) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")>0 
			THEN Sum(CASE WHEN T0."DocDate" >= ADD_DAYS(to_date(:EDATE ),- 119)  and T0."DocDate" < ADD_DAYS(to_date(:EDATE ),- 89)
			THEN T0."InQty" ELSE 0 END) 
		ELSE Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 89) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "90-119天数量",
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 119) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		WHEN Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 359) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")>0 
			THEN Sum(CASE WHEN T0."DocDate" >= ADD_DAYS(to_date(:EDATE ),- 359)  and T0."DocDate" < ADD_DAYS(to_date(:EDATE ),- 119)
			THEN T0."InQty" ELSE 0 END) 
		ELSE Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 119) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "120-359天数量",
	CASE 
		WHEN Sum(T0."Quantity")=0 OR 
			 Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 359) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty")<=0 
			 THEN 0 
		ELSE Sum(CASE WHEN T0."DocDate"<ADD_DAYS(to_date(:EDATE),- 359) THEN T0."InQty" ELSE 0 END)-Sum(T0."OutQty") 
		END
	AS "大于359天数量"
	FROM "MTC_VW_DOCLINE_AGING_SERNUM" T0
	INNER JOIN OWHS T2 ON T0."WhsCode"=T2."WhsCode" 
	LEFT JOIN "OSRN" T4 ON T0."BatchNumber"=TO_CHAR(T4."AbsEntry")
	WHERE (T0."DocDate" <= :EDATE )
	AND (T0."ItemCode"=:ItemCode OR :ItemCode='')
	GROUP BY T0."ItemCode", T2."WhsName",T2."WhsCode",LEFT(T0."BatchEntry",6),T4."InDate"
	 )T0       
	INNER JOIN OITM T2 ON T0."ItemCode" = T2."ItemCode"
	INNER JOIN OITB T3 ON T2."ItmsGrpCod" = T3."ItmsGrpCod"  
	LEFT JOIN (SELECT "ItemCode","Price" FROM "MTC_COST_0301_INVNT" 
			WHERE 1=1 AND "CostCode"='20' AND "FcCode"=TO_CHAR(:EDATE,'YYYY-MM')) T9 ON T2."ItemCode"=T9."ItemCode"
	WHERE 1=1 AND IFNULL(T0."EQty",0)<>0
	AND T2."ManSerNum"='Y'
	ORDER BY T0."ItemCode",T0."WhsCode",T0."SerNum"
	;
  	

  END IF;
  
  
  IF :STYPE = 'BatchNum' THEN 
  	SELECT T0."物料管理类型",
	T0."物料编码",T0."物料名称",T0."物料组",
	T0."仓库编码",
	T0."仓库名称",
	T0."批次ID",
	T0."批次",
	T0."批次入库日期",
	T0."在库时长",
	T0."小于30天数量",	
	T0."30-59天数量",	
	T0."60-89天数量" ,	
	T0."90-119天数量" ,	
	T0."120-359天数量" ,	
	T0."大于359天数量",
	T0."数量总计", 
	T0."成本单价",
	CASE WHEN T0."ID"=1 THEN T2."QM_Amount"-IFNULL(T1."ID<>1成本金额",0) ELSE T0."成本金额" END AS "成本金额",
	T0."ID"
	FROM :TMP_BatchNum T0
	LEFT JOIN (SELECT "物料编码",SUM("成本金额") AS "ID<>1成本金额" 
				FROM :TMP_BatchNum WHERE "ID"<>1 GROUP BY "物料编码"
			) T1 ON T0."物料编码"=T1."物料编码"
	LEFT JOIN (SELECT "ItemCode","QM_Amount"
				FROM MTC_COST_0301_INVNT T0 WHERE 1=1 AND "CostCode"='20' AND "FcCode"=TO_CHAR(:EDATE,'YYYY-MM')
			) T2 ON T0."物料编码"=T2."ItemCode"
	ORDER BY T0."物料编码",T0."批次",T0."仓库编码";
	
  ELSEIF :STYPE = 'SerNum' THEN
  	SELECT T0."物料管理类型",
	T0."物料编码",T0."物料名称",T0."物料组",
	T0."仓库编码",
	T0."仓库名称",
	T0."序列号ID",
	T0."序列号",
	T0."序列号入库日期",
	T0."在库时长",
	T0."小于30天数量",	
	T0."30-59天数量",	
	T0."60-89天数量" ,	
	T0."90-119天数量" ,	
	T0."120-359天数量" ,	
	T0."大于359天数量",
	T0."数量总计", 
	T0."成本单价",
	CASE WHEN T0."ID"=1 THEN T2."QM_Amount"-IFNULL(T1."ID<>1成本金额",0) ELSE T0."成本金额" END AS "成本金额",
	T0."ID"
  	FROM :TMP_SerNum T0 
	LEFT JOIN (SELECT "物料编码",SUM("成本金额") AS "ID<>1成本金额" 
				FROM :TMP_BatchNum WHERE "ID"<>1 GROUP BY "物料编码"
			) T1 ON T0."物料编码"=T1."物料编码"
	LEFT JOIN (SELECT "ItemCode","QM_Amount"
				FROM MTC_COST_0301_INVNT T0 WHERE 1=1 AND "CostCode"='20' AND "FcCode"=TO_CHAR(:EDATE,'YYYY-MM')
			) T2 ON T0."物料编码"=T2."ItemCode"
	ORDER BY T0."物料编码",T0."序列号",T0."仓库编码";
  ELSEIF :STYPE = 'All' THEN 
  	SELECT T0."物料管理类型",
	T0."物料编码",T0."物料名称",T0."物料组",
	T0."仓库编码",
	T0."仓库名称",
	T0."批次ID",
	T0."批次",
	T0."批次入库日期",
	T0."在库时长",
	T0."小于30天数量",	
	T0."30-59天数量",	
	T0."60-89天数量" ,	
	T0."90-119天数量" ,	
	T0."120-359天数量" ,	
	T0."大于359天数量",
	T0."数量总计", 
	T0."成本单价",
	CASE WHEN T0."ID"=1 THEN T2."QM_Amount"-IFNULL(T1."ID<>1成本金额",0) ELSE T0."成本金额" END AS "成本金额",
	--T0."成本金额" AS "参考金额",
	T0."ID"
	FROM :TMP_BatchNum T0
	LEFT JOIN (SELECT "物料编码",SUM("成本金额") AS "ID<>1成本金额" 
				FROM :TMP_BatchNum WHERE "ID"<>1 GROUP BY "物料编码"
			) T1 ON T0."物料编码"=T1."物料编码"
	LEFT JOIN (SELECT "ItemCode","QM_Amount"
				FROM MTC_COST_0301_INVNT T0 WHERE 1=1 AND "CostCode"='20' AND "FcCode"=TO_CHAR(:EDATE,'YYYY-MM')
			) T2 ON T0."物料编码"=T2."ItemCode"
  	  	UNION ALL
  	SELECT T0."物料管理类型",
	T0."物料编码",T0."物料名称",T0."物料组",
	T0."仓库编码",
	T0."仓库名称",
	T0."序列号ID",
	T0."序列号",
	T0."序列号入库日期",
	T0."在库时长",
	T0."小于30天数量",	
	T0."30-59天数量",	
	T0."60-89天数量" ,	
	T0."90-119天数量" ,	
	T0."120-359天数量" ,	
	T0."大于359天数量",
	T0."数量总计", 
	T0."成本单价",
	CASE WHEN T0."ID"=1 THEN T2."QM_Amount"-IFNULL(T1."ID<>1成本金额",0) ELSE T0."成本金额" END AS "成本金额",
	--T0."成本金额" AS "参考金额",
	T0."ID"
  	FROM :TMP_SerNum T0 
	LEFT JOIN (SELECT "物料编码",SUM("成本金额") AS "ID<>1成本金额" 
				FROM :TMP_SerNum WHERE "ID"<>1 GROUP BY "物料编码"
			) T1 ON T0."物料编码"=T1."物料编码"
	LEFT JOIN (SELECT "ItemCode","QM_Amount"
				FROM MTC_COST_0301_INVNT T0 WHERE 1=1 AND "CostCode"='20' AND "FcCode"=TO_CHAR(:EDATE,'YYYY-MM')
			) T2 ON T0."物料编码"=T2."ItemCode"
  	ORDER BY "物料编码","批次","仓库编码"
  	  ;
  END IF;
End;