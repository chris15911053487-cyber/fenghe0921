CREATE PROCEDURE "MTC_CO_001GetItemLevel" --create by yingxian
(
IN FcCode NVARCHAR(20),
IN UserId INT DEFAULT 1
)
LANGUAGE SQLSCRIPT
AS
BEGIN

  /*此存储过程用来提取物料的级别，包括半成品，产成品等
    CALL "MTC_CO_001GetItemLevel"('2024-12')
    */
   DECLARE FLAG INT;
   DECLARE CNT INT;
   DECLARE CNTBOMLEVEL INT;

   DECLARE BeginDate DateTime;
   DECLARE EndDate DateTime;

      IF EXISTS(SELECT 1 FROM "OFPR" WHERE "PeriodStat"='Y' AND "Code"=:FcCode) THEN
          SELECT -1 AS "Code",'账期已锁定，无法计算成本' AS "Msg" FROM DUMMY;
          RETURN;
      END IF;


    --01.当前期间的日期范围
    SELECT T0."F_RefDate", T0."T_RefDate" INTO BeginDate,EndDate
    FROM OFPR T0 WHERE T0."Code"= :FcCode;


     --DROP TABLE #OITMLV;
    CREATE LOCAL TEMPORARY TABLE #OITMLV
     (
     "ItemCode" NVARCHAR(40),
     "ItemName"  NVARCHAR(100),
     "ItmsGrpCod" NVARCHAR(40),
     "ItmsGrpNam" NVARCHAR(40),
     "iLevel" INT
     ) ;

   ----原材料级别
    INSERT INTO #OITMLV SELECT T0."ItemCode",
             T0."ItemName",
             T1."ItmsGrpCod",
             T1."ItmsGrpNam",
             -1 AS "iLevel"
      FROM OITM T0
      INNER JOIN OITB T1 ON T0."ItmsGrpCod" = T1."ItmsGrpCod";
     --WHERE T0."ItmsGrpCod"  IN (108);---(30,40,50)



    --获取BOM情况
   Temp01=
        SELECT T0."Code" "Father", T1."Code" "Child",T2."ItmsGrpCod"
        FROM OITT T0  INNER JOIN ITT1 T1 ON T0."Code" = T1."Father"
        INNER JOIN OITM T2 ON T0."Code" = T2."ItemCode";

   CNT:=0;
   SELECT IFNULL((SELECT COUNT(1)
        FROM :Temp01 T0
       WHERE T0."Father"  = T0."Child"),0) INTO CNT FROM DUMMY;

     --判断并修改0级原料
     UPDATE #OITMLV SET "iLevel"=0 WHERE "ItemCode" NOT IN (SELECT "Father" FROM  :temp01) ;


    --F.3、判断#BOM的Father是否存在下一级别的配方,若存在，则循环#BOM通过当前ILevel+1确定Father的最终级别

    --判断是否存在下一级别

     CNTBOMLEVEL:=1;
 --如果存在，则级别加1
    WHILE :CNTBOMLEVEL <9 DO
            --更新物料等级
            UPDATE #OITMLV SET "iLevel"=:CNTBOMLEVEL WHERE "ItemCode" IN (
                SELECT "Father" FROM (
                SELECT T0."Father",IFNULL(T1."iLevel",-1) "ILV" FROM :Temp01 T0
                  LEFT JOIN #OITMLV T1 ON T0."Child"=T1."ItemCode"
                    LEFT  JOIN #OITMLV T2 ON T0."Father"=T2."ItemCode"
                    WHERE IFNULL(T2."iLevel",-1) =-1 AND IFNULL(T1."iLevel",-1)<:CNTBOMLEVEL
                    GROUP BY T0."Father",T1."iLevel"
                    ) A GROUP BY "Father"
                    HAVING SUM(CASE WHEN "ILV"=-1 THEN 1 ELSE 0 END)=0
            );
            --等级+1
            CNTBOMLEVEL:=(:CNTBOMLEVEL+1);
    END WHILE;



   CNT:=0;
   SELECT IFNULL((SELECT COUNT(1)
        FROM #OITMLV T0
       WHERE T0."iLevel"  = -1),0) INTO CNT FROM DUMMY;


     --最终的结果插入表中。
    DELETE FROM U_COILV WHERE  "FcCode"=:FcCode;

    --将原材料插入到系统中
    INSERT INTO U_COILV("FcCode","ItemCode","ItemName",
                        "ItmsGrpCod","ItmsGrpNam",
                        "iLevel","CalType","CreatedDate","CreatedTime")
    SELECT :FcCode,
            T0."ItemCode",T0."ItemName",
            T0."ItmsGrpCod",T0."ItmsGrpNam",
            T0."iLevel",T1."U_ItemProp",CURRENT_Date,CURRENT_Time
    FROM #OITMLV T0
    JOIN OITM T1 ON T0."ItemCode"=T1."ItemCode";


    DROP TABLE #OITMLV;

    UPDATE U_COILV SET "iLevel"=2 WHERE  "FcCode"=:FcCode AND "ItemCode" IN ('102000058','102000762');
    UPDATE U_COILV SET "iLevel"=3 WHERE  "FcCode"=:FcCode AND "ItemCode" IN ('FH1401101','FH1403501');

    --chris.li 2026.3.6增加
    --UPDATE U_COILV SET "iLevel"=3 WHERE  "FcCode"=:FcCode AND "ItemCode" IN ('102000319');

    SELECT T0."FcCode",T0."ItemCode" AS "物料号",
           T0."ItemName" AS "物料名称",
           T0."ItmsGrpCod" AS "物料组编码",
           T0."ItmsGrpNam" AS "物料组名称",
            T0."iLevel" AS "级别",T0."CalType"
    FROM U_COILV T0
    WHERE T0."FcCode"=:FcCode
    ORDER BY T0."iLevel" DESC,T0."ItemCode";


END;
