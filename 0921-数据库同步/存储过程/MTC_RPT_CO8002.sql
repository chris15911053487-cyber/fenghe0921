CREATE PROCEDURE "MTC_RPT_CO8002"
(
  BPLId NVARCHAR(10),
  FcCode NVARCHAR(30),
  UserId INT
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 

	DECLARE EndDate DATE;
	SELECT "T_RefDate" INTO EndDate FROM OFPR WHERE "Code"=:FcCode;
	
	SELECT :FcCode AS "FcCode",T1."U_Type" AS "报表类型",T1."U_RptCode",T1."U_RptName" AS "报表名称"
	,CASE WHEN T11."TransId" IS NOT NULL THEN '已冲销,' ELSE '' END || T1."U_RptCode" AS "Re"
	,T11."TransId" AS "ReJDTId"
	,CASE WHEN T1."U_RptCode" LIKE 'JC%' THEN NULL
		WHEN T21."TransId" IS NOT NULL OR T22."TransId" IS NOT NULL THEN '已结转,' ELSE '' END || T1."U_RptCode"
		AS "JZ"
	,COALESCE(T21."TransId",'凭单号'||T22."TransId") AS "JZJDTId"	
	,T1."U_Notes" AS "说明",:EndDate AS "EndDate"
	,CASE WHEN T1."U_RptCode"='AR01' THEN '100' WHEN T1."U_RptCode" IN ('AR02','JE02') THEN '106' END AS "GroupCode"
	,T1."U_OrderBy"
	,T1."U_Proc" AS "来源"
	,T1."U_IsRev"
	FROM "@MTC_BRPT" T0
	JOIN "@MTC_BRPT1" T1 ON T0."Code"=T1."Code"
	LEFT JOIN (SELECT T0."TransCode",STRING_AGG("TransId",',') AS "TransId" FROM "OJDT" T0
				WHERE LEFT(T0."RefDate",7)=:FcCode
						AND EXISTS(SELECT 1 FROM OJDT P0
							WHERE P0."TransId"=T0."StornoToTr") GROUP BY T0."TransCode"
			) T11 ON T1."U_RptCode"=T11."TransCode"
	LEFT JOIN (SELECT "TransCode",STRING_AGG("TransId",',') AS "TransId" FROM "OJDT" T0
				WHERE LEFT("RefDate",7)=:FcCode AND "StornoToTr" IS NULL
				AND NOT EXISTS(SELECT 1 FROM OJDT P0
							WHERE T0."TransId"=P0."StornoToTr")
				AND "TransId">33641
				GROUP BY "TransCode"
			) T21 ON T1."U_RptCode"=T21."TransCode"
	LEFT JOIN (SELECT "TransCode",STRING_AGG("BatchNum",',') AS "TransId" FROM "OBTF" 
				WHERE LEFT("RefDate",7)=:FcCode AND "BatchNum">622 AND "Memo" NOT LIKE '%2026-07%' GROUP BY "TransCode"
			) T22 ON T1."U_RptCode"=T22."TransCode"
	WHERE T0."Code"='JZ'
	AND T1."U_Status"='Y'
--AND EXISTS(SELECT 1 FROM OUSR P0 LEFT JOIN USR7 P1 ON P0."USERID"=P1."UserId" LEFT JOIN "@MTC_BRPT2" P2 ON P1."GroupId"=P2."U_UserCode"      
--WHERE 1=1 AND (P0."SUPERUSER"='Y' OR (IFNULL(P2."U_UserCode",'')<>'' AND P2."Code"=T0."Code")) AND P0."USERID"=$[USER] )
	ORDER BY T1."U_OrderBy";
	
	
END