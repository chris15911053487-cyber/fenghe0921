CREATE PROCEDURE "MTC_COST_PROC_0105_ITEM"(IN BPLId INT,IN FcCode NVARCHAR(10),IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT
AS
BEGIN
	
	/* created by chri.li 2024.11.23
     * 抽取物料等级 到 明细到静态表 MTC_COST_0105_ITEM
     * CALL "MTC_COST_PROC_0105_ITEM"(0,'2024-01','manager');
    */
    
    DECLARE CNT INT = 0;
    DECLARE ILEVEL INT = 1;
    DECLARE MAXLEVEL INT = 0;
    
    BOM=
    SELECT T0."Code" AS "FatherCode",T1."Code" AS "ChildCode",:ILEVEL AS ILEVEL
    FROM "OITT" T0
    JOIN "ITT1" T1 ON T0."Code"=T1."Father"
    WHERE 1=1;
    
    SELECT COUNT(1) INTO CNT
    FROM :BOM T0
    JOIN :BOM T1 ON T0."FatherCode"=T1."ChildCode"
    WHERE T0."ILEVEL"=:ILEVEL;
    
    WHILE :CNT > 0 DO
    
    	BOM = 
    	SELECT * FROM :BOM
    	UNION ALL
	    SELECT T0."FatherCode",T1."ChildCode",:ILEVEL+1 AS ILEVEL
	    FROM :BOM T0
	    JOIN :BOM T1 ON T0."ChildCode"=T1."FatherCode"
	    WHERE 1=1 AND T0."ILEVEL"=:ILEVEL;
	    
	    ILEVEL := :ILEVEL + 1;
	    
    	SELECT COUNT(1) INTO CNT
		FROM :BOM T0
		JOIN :BOM T1 ON T0."FatherCode"=T1."ChildCode"
		WHERE T0."ILEVEL"=:ILEVEL;
    END WHILE;
    
    
	DELETE FROM MTC_COST_0105_ITEM WHERE "FcCode" = :FcCode;
	
	INSERT INTO MTC_COST_0105_ITEM(
	 "BPLId"
	,"FcCode"
	,"ItemCode"
	,"ItemName"
	,"ItmsGrpCod"
	,"Unit"
	,"CalType"
	,"CostCode"
	,"Level"			--层级 1最后（最高）层级-产成品   2以此减少
	,"CreateDate"		--创建时间
	,"Creator")
	SELECT :BPLId AS "BPLId"
	,:FcCode AS "FcCode"
	,T1."ItemCode"
	,T1."ItemName"
	,T1."ItmsGrpCod"
	,NULL AS "Unit"
	,NULL AS "U_CalType"
	,'A1' AS "CostCode"
	,MAX(T0."ILEVEL") AS "Level"
	,CURRENT_TIMESTAMP
	,:UserCode
	FROM :BOM T0
	JOIN OITM T1 ON T0."FatherCode"=T1."ItemCode"
	WHERE 1=1 GROUP BY T1."ItemCode",T1."ItemName",T1."ItmsGrpCod"
	;
	
	SELECT '写入物料成本计算等级成功！' FROM DUMMY;

END