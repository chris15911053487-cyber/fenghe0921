CREATE  PROCEDURE "MTC_MERP_RPT_PMC03"   --批次序列号账龄分析表
(	
	IN EDATE	NVARCHAR(30),   --截止日期
	IN TYP		NVARCHAR(10), 		
	IN ItemCode NVARCHAR(50), 					
	IN WhsCode 	NVARCHAR(50)
	
)
LANGUAGE SQLSCRIPT
AS
BEGIN
DECLARE boot NVARCHAR(10);
DECLARE rid BIGINT;

--2026-11-06 数量列名改成和实际分段、金额列名一致（原 小于30天 / 30-59天 / 60-89天 / 90-119天 / 120-359天 / 大于359天）
--2026-11-06 最新成本改取新框架：最近一个有成本结果的账期（MTC_CA_F_RPT_RUN 不传账期时的默认账期，还没有新框架运行时取最近的回填运行）的 R_ITEM，
--单价 = 期末金额 ÷ 期末数量，期末数量为 0 时取本期单价；都没有时取 BOOTSTRAP_FC 及以前最近一期的旧 0301
boot := IFNULL("MTC_CA_F_PARAM"('BOOTSTRAP_FC', TO_NVARCHAR(CURRENT_DATE,'YYYY-MM')), '0000-00');
SELECT MAX("RunId") INTO rid FROM "MTC_CA_F_RPT_RUN"(NULL, NULL);
ip=
	SELECT "ItemCode"
		,CASE WHEN "EndQty"<>0 THEN "EndAmount"/"EndQty" ELSE "PMat"+"PMfg"+"PLab"+"PSub" END AS "Price"
	FROM "MTC_CA_R_ITEM" WHERE "RunId"=:rid
	UNION ALL
	SELECT "ItemCode",MAX("Price") AS "Price"
	FROM "MTC_COST_0301_INVNT"
	WHERE "CostCode"='20' AND :rid IS NULL
	AND "FcCode"=(SELECT MAX("FcCode") FROM "MTC_COST_0301_INVNT" WHERE "FcCode"<=:boot)
	GROUP BY "ItemCode";

CHECK1=
	SELECT 
		T1."ItemCode",T1."DistNumber",T1."SysNumber",T1."U_BtchNum",T1."InDate",DAYS_BETWEEN (T1."InDate",:EDATE) "DAYS"
		,T0."WhsCode",T0."Quantity"-IFNULL(T0."CommitQty",0)  "Quantity"
	FROM OBTQ T0
	INNER JOIN OBTN T1 ON T1."ItemCode" =T0."ItemCode" AND T0."SysNumber" =T1."SysNumber" 
	WHERE 1=1
	AND (T0."ItemCode" =:ItemCode OR :ItemCode='') AND (T0."WhsCode"=:WhsCode OR :WhsCode='')
	AND T0."Quantity"-IFNULL(T0."CommitQty",0)>0
	AND T1."InDate" <= :EDATE
	UNION ALL
	
	SELECT 
		T1."ItemCode",T1."DistNumber",T1."SysNumber",T1."U_BtchNum",T1."InDate",DAYS_BETWEEN (T1."InDate",:EDATE) "DAYS"
		,T0."WhsCode",T0."Quantity"-IFNULL(T0."CommitQty",0)  "Quantity"
	FROM OSRQ T0  
	INNER JOIN OSRN T1 ON T0."ItemCode"=T1."ItemCode" AND T0."SysNumber" = T1."SysNumber"
	WHERE 1=1
	AND (T0."ItemCode" =:ItemCode OR :ItemCode='') AND (T0."WhsCode"=:WhsCode OR :WhsCode='')
	AND T0."Quantity"-IFNULL(T0."CommitQty",0)>0
	AND T1."InDate" <= :EDATE;
--0-30天
CHECK2=	
	SELECT	"ItemCode","DistNumber","SysNumber","U_BtchNum","InDate","DAYS","WhsCode"
			,"Quantity" "A",0 "B",0 "C",0"D",0 "E",0 "F"
	FROM :CHECK1 WHERE "DAYS"<31
--31-60天
	UNION ALL
	SELECT	"ItemCode","DistNumber","SysNumber","U_BtchNum","InDate","DAYS","WhsCode"
			,0 "A","Quantity"  "B",0 "C",0"D",0 "E",0 "F"
	FROM :CHECK1 WHERE "DAYS">=31 AND "DAYS"<=60
--61-90天
	UNION ALL
	SELECT	"ItemCode","DistNumber","SysNumber","U_BtchNum","InDate","DAYS","WhsCode"
			,0 "A",0 "B","Quantity"  "C",0"D",0 "E",0 "F"
	FROM :CHECK1 WHERE "DAYS">=61 AND "DAYS"<=90
--91-180天
	UNION ALL
	SELECT	"ItemCode","DistNumber","SysNumber","U_BtchNum","InDate","DAYS","WhsCode"
			,0 "A",0 "B",0  "C","Quantity" "D",0 "E",0 "F"
	FROM :CHECK1 WHERE "DAYS">=91 AND "DAYS"<=180
--181-365天
	UNION ALL
	SELECT	"ItemCode","DistNumber","SysNumber","U_BtchNum","InDate","DAYS","WhsCode"
			,0 "A",0 "B",0  "C",0"D","Quantity" "E",0 "F"
	FROM :CHECK1 WHERE "DAYS">=181 AND "DAYS"<=365
--大于365天
	UNION ALL
	SELECT	"ItemCode","DistNumber","SysNumber","U_BtchNum","InDate","DAYS","WhsCode"
			,0 "A",0 "B",0  "C",0"D",0 "E","Quantity" "F"
	FROM :CHECK1 WHERE "DAYS">365;
	
IF :TYP='1' THEN	
CHECK3=
	SELECT 
		"ItemCode","U_BtchNum","InDate","DAYS","WhsCode",
		SUM("A")	"A",SUM("B")	"B",SUM("C")	"C",SUM("D")	"D",
		SUM("E")	"E",SUM("F")	"F",SUM("A")+SUM("B")+SUM("C")+SUM("D")+SUM("E")+SUM("F") "G"
	FROM:CHECK2
	GROUP BY "ItemCode","U_BtchNum","InDate","DAYS","WhsCode";

SELECT 
	T0."ItemCode" 			"物料编码"
	,T1."ItemName"			"物料名称"
	,T0."U_BtchNum"			"批号"	
	,LEFT(T0."InDate",10)	"批次入库日期"
	,T0."DAYS"||'天'			"在库时长"
	,T0."WhsCode"			"仓库"
	,T0."A"		"0-30天"	,T0."B"		"31-60天"	,T0."C"		"61-90天"
	,T0."D"		"91-180天"	,T0."E"		"181-365天"	,T0."F"		"大于365天"	,T0."G"		"总计"
	,IFNULL(T2."Price",0)				"最新成本"
	,T3."Name" 				"物料分类6"
	,T0."A" * IFNULL(T2."Price",0)		"0-30天的金额"	,T0."B" * IFNULL(T2."Price",0)		"31-60天的金额"	,T0."C" * IFNULL(T2."Price",0)		"61-90天的金额"
	,T0."D" * IFNULL(T2."Price",0)		"91-180天的金额",T0."E" * IFNULL(T2."Price",0)		"181-365天的金额"	,T0."F" * IFNULL(T2."Price",0)		"大于365天的金额"	,T0."G" * IFNULL(T2."Price",0)		"总计的金额"
FROM :CHECK3 T0
LEFT JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
LEFT JOIN :ip T2 ON T2."ItemCode"=T0."ItemCode"
LEFT JOIN "@MTC_ITMSGRPCOD6" T3 ON T3."Code"=T1."U_ItmsGrpCod6"	 	
ORDER BY T0."ItemCode",T0."WhsCode"
;
END IF;
	
IF :TYP='2' THEN	
CHECK4=
	SELECT 
		"ItemCode","DistNumber","SysNumber","U_BtchNum","InDate","DAYS","WhsCode",
		SUM("A")	"A"	,SUM("B")	"B"	,SUM("C")	"C"	,SUM("D")	"D",
		SUM("E")	"E"	,SUM("F")	"F"	,SUM("A")+SUM("B")+SUM("C")+SUM("D")+SUM("E")+SUM("F") "G"
	FROM:CHECK2
	GROUP BY "ItemCode","DistNumber","SysNumber","U_BtchNum","InDate","DAYS","WhsCode"
	 ;
	
SELECT 	
	T0."ItemCode" 			"物料编码"
	,T1."ItemName"			"物料名称"
	,"DistNumber"			"批次/序列号"
	,"SysNumber"			"系统编号"
	,T0."U_BtchNum"			"批号"	
	,LEFT(T0."InDate",10)	"批次入库日期"
	,T0."DAYS"||'天'			"在库时长"
	,T0."WhsCode"			"仓库"
	,T0."A"		"0-30天"	,T0."B"		"31-60天"	,T0."C"		"61-90天"
	,T0."D"		"91-180天"	,T0."E"		"181-365天"	,T0."F"		"大于365天"	,T0."G"		"总计"
	,IFNULL(T2."Price",0)				"最新成本"
	,T3."Name" 				"物料分类6"
	,T0."A" * IFNULL(T2."Price",0)		"0-30天的金额"	,T0."B" * IFNULL(T2."Price",0)		"31-60天的金额"	,T0."C" * IFNULL(T2."Price",0)		"61-90天的金额"
	,T0."D" * IFNULL(T2."Price",0)		"91-180天的金额",T0."E" * IFNULL(T2."Price",0)		"181-365天的金额"	,T0."F" * IFNULL(T2."Price",0)		"大于365天的金额"	,T0."G" * IFNULL(T2."Price",0)		"总计的金额"
FROM :CHECK4 T0
LEFT JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode"
LEFT JOIN :ip T2 ON T2."ItemCode"=T0."ItemCode"
LEFT JOIN "@MTC_ITMSGRPCOD6" T3 ON T3."Code"=T1."U_ItmsGrpCod6"	 
ORDER BY T0."ItemCode",T0."WhsCode"
;
END IF;
END