CREATE PROCEDURE "MTC_RPT_CO4005"
(
  IN STYPE INT,	--0汇总  1明细
  IN SFcCode NVARCHAR(30),
  IN EFcCode NVARCHAR(30)
 )
LANGUAGE SQLSCRIPT
AS
BEGIN 


	SELECT
	T0."期间",
	SUM(T0."当期成本合计") AS "当期成本合计",
	SUM(T0."当期材料金额") AS "当期材料金额",
	SUM(T0."当期人工费用") AS "当期人工费用",
	SUM(T0."当期制造费用") AS "当期制造费用",
	SUM(T0."生产成本合计") AS "生产成本合计",
	SUM(T0."生产成本-直接材料") AS "生产成本-直接材料",
	SUM(T0."生产成本-人工费用") AS "生产成本-人工费用",
	SUM(T0."生产成本-制造费用") AS "生产成本-制造费用",
	SUM(T0."生产成本-直接材料(入库结转)") AS "生产成本-直接材料(入库结转)",
	SUM(T0."生产成本-人工费用(入库结转)") AS "生产成本-人工费用(入库结转)",
	SUM(T0."生产成本-制造费用(入库结转)") AS "生产成本-制造费用(入库结转)",
	SUM(T0."生产成本-直接材料(其他)") AS "生产成本-直接材料(其他)",
	SUM(T0."生产成本-人工费用(其他)") AS "生产成本-人工费用(其他)",
	SUM(T0."生产成本-制造费用(其他)") AS "生产成本-制造费用(其他)"
	FROM 
		(
		SELECT  
		T0."FcCode" AS "期间",
		SUM(T0."Amount") AS "当期成本合计",
		SUM(T0."1Material") AS "当期材料金额",
		SUM(T0."2ManExp") AS "当期人工费用",
		SUM(T0."3LabAmount") AS "当期制造费用",
		0.00 AS "生产成本合计",
		0.00 AS "生产成本-直接材料",
		0.00 AS "生产成本-人工费用",
		0.00 AS "生产成本-制造费用",
		0.00 AS "生产成本-直接材料(入库结转)",
		0.00 AS "生产成本-人工费用(入库结转)",
		0.00 AS "生产成本-制造费用(入库结转)",
		0.00 AS "生产成本-直接材料(其他)",
		0.00 AS "生产成本-人工费用(其他)",
		0.00 AS "生产成本-制造费用(其他)"
		FROM MTC_COST_0321_OWOR_SUM T0
		JOIN OITM T2 ON T0."ItemCode"=T2."ItemCode"
		WHERE T0."FcCode" BETWEEN :SFcCode AND :EFcCode
		AND T0."WorType" NOT IN ('40','50')
		AND IFNULL(T0."IgnQty",0)<>0
		GROUP BY T0."FcCode"
		
		UNION ALL
		SELECT LEFT(T0."RefDate",7) AS "期间",
		0.00 AS "当期成本合计",
		0.00 AS "当期材料金额",
		0.00 AS "当期人工费用",
		0.00 AS "当期制造费用",
		SUM(T1."Credit") AS "生产成本合计",
		SUM(CASE WHEN T1."Account"='500101' THEN T1."Credit" ELSE 0 END) AS "生产成本-直接材料",
		SUM(CASE WHEN T1."Account"='500102' THEN T1."Credit" ELSE 0 END) AS "生产成本-人工费用",
		SUM(CASE WHEN T1."Account"='500103' THEN T1."Credit" ELSE 0 END) AS "生产成本-制造费用",
		SUM(CASE WHEN T1."Account"='500101' AND T0."TransCode"='PP05' THEN T1."Credit" ELSE 0 END) AS "生产成本-直接材料(入库结转)",
		SUM(CASE WHEN T1."Account"='500102' AND T0."TransCode"='PP05' THEN T1."Credit" ELSE 0 END) AS "生产成本-人工费用(入库结转)",
		SUM(CASE WHEN T1."Account"='500103' AND T0."TransCode"='PP05' THEN T1."Credit" ELSE 0 END) AS "生产成本-制造费用(入库结转)",
		SUM(CASE WHEN T1."Account"='500101' AND IFNULL(T0."TransCode",'')<>'PP05' THEN T1."Credit" ELSE 0 END) AS "生产成本-直接材料(其他)",
		SUM(CASE WHEN T1."Account"='500102' AND IFNULL(T0."TransCode",'')<>'PP05' THEN T1."Credit" ELSE 0 END) AS "生产成本-人工费用(其他)",
		SUM(CASE WHEN T1."Account"='500103' AND IFNULL(T0."TransCode",'')<>'PP05' THEN T1."Credit" ELSE 0 END) AS "生产成本-制造费用(其他)"
		FROM OJDT T0
		JOIN JDT1 T1 ON T0."TransId"=T1."TransId"
		WHERE LEFT(T0."RefDate",7) BETWEEN :SFcCode AND :EFcCode
		AND T1."Account" IN ('500101','500102','500103')
		AND T1."Credit">0
		GROUP BY LEFT(T0."RefDate",7),T0."TransCode"
		
		--
		UNION ALL
		SELECT LEFT(T0."RefDate",7) AS "期间",
		0.00 AS "当期成本合计",
		0.00 AS "当期材料金额",
		0.00 AS "当期人工费用",
		0.00 AS "当期制造费用",
		0.00 AS "生产成本合计",
		0.00 AS "生产成本-直接材料",
		0.00 AS "生产成本-人工费用",
		0.00 AS "生产成本-制造费用",
		0.00 AS "生产成本-直接材料(入库结转)",
		0.00 AS "生产成本-人工费用(入库结转)",
		0.00 AS "生产成本-制造费用(入库结转)",
		0.00 AS "生产成本-直接材料(其他)",
		0.00 AS "生产成本-人工费用(其他)",
		SUM(CASE WHEN LEFT(T1."Account",4)='5101' AND IFNULL(T0."TransCode",'')='MR02' THEN 1*(T1."Debit"-T1."Credit") ELSE 0 END) AS "生产成本-制造费用(其他)"
		FROM OJDT T0
		JOIN JDT1 T1 ON T0."TransId"=T1."TransId"
		WHERE LEFT(T0."RefDate",7) BETWEEN :SFcCode AND :EFcCode
		AND LEFT(T1."Account",4)='5101'
		GROUP BY LEFT(T0."RefDate",7),T0."TransCode"
		
		) T0
		
	GROUP BY T0."期间"
	ORDER BY T0."期间"
	;
END
