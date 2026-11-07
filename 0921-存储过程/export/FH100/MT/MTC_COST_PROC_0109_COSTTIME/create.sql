CREATE PROCEDURE "MTC_COST_PROC_0109_COSTTIME"(IN DocEntry INT,IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN

	/* chris.li 
	   加载工时
	   CALL "MTC_COST_PROC_0109_COSTTIME"('3','1')
	*/
	
	DECLARE FcCode NVARCHAR(50);
	SELECT "U_FcCode" INTO FcCode FROM "@MTC_COST_TIME" WHERE "DocEntry"=:DocEntry;
  	IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
  		SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
  		RETURN;
  	END IF;
  	
	DELETE FROM "@MTC_COST_TIME1" WHERE "DocEntry"=:DocEntry;
	
	INSERT INTO "@MTC_COST_TIME1"(
	"DocEntry","LineId","VisOrder","Object"
	,"U_ItemCode","U_ItemName","U_Time","U_Memo")
	SELECT :DocEntry,ROW_NUMBER() OVER (ORDER BY T0."ItemCode") AS "LineId"
	,ROW_NUMBER() OVER (ORDER BY T0."ItemCode") AS "VisOrder",'MTC_COST_TIME'
	,T0."ItemCode",T0."ItemName",T0."Time",'来源'||T0."FcCode"
	FROM 
		(
		SELECT T0."ItemCode",T2."ItemName",MAX(IFNULL(T1."Time",0)) AS "Time",MAX(T1."FcCode") AS "FcCode"
		FROM "MTC_VIEW_Document" T0
		LEFT JOIN (SELECT T1."U_ItemCode" AS "ItemCode",T1."U_Time" AS "Time",T0."U_FcCode" AS "FcCode"
					,ROW_NUMBER() OVER (PARTITION BY T1."U_ItemCode" ORDER BY T0."U_FcCode" DESC,T1."LineId" DESC) AS "ID"
					FROM "@MTC_COST_TIME" T0
					JOIN "@MTC_COST_TIME1" T1 ON T0."DocEntry"=T1."DocEntry" 
				) T1 ON T0."ItemCode"=T1."ItemCode" AND T1."ID"=1
		JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
		WHERE LEFT(T0."DocDate",7)=:FcCode
		AND T0."ObjType" IN ('59','60')
		AND T0."TransCode" IN ('I03','I07')
		GROUP BY T0."ItemCode",T2."ItemName"
		) T0
	ORDER BY T0."ItemCode";
	
	SELECT '引入'||:FcCode||'成功' AS "信息" FROM DUMMY;

END