-- =====================================================================
-- 新成本框架：成本报表（用户 2026-10-30，设计稿 8.7；替代旧 MTC_RPT_CO* 报表）
-- 21 个只读存储过程 MTC_CA_RPT_00 … 20，B1 查询管理器里存 CALL "MTC_CA_RPT_xx"('[%0]', …) 打开，
-- 执行台“成本报表”页调同一批过程（actions.json rpt00 … rpt20），口径只有一套。
--
-- 通用约定：
--   · 参数全部 NVARCHAR，留空 = 全部；多个值用英文逗号（中文逗号也认）；物料编码、订单号、业务伙伴等代码按开头匹配，值前加 = 精确匹配（如 =A1）。
--   · 账期 FcFrom / FcTo（OFPR.Code）：FcFrom 空 = 最近一个已计算账期，FcTo 空 = FcFrom。单期报表只有 Fc；对比账期 CmpFc 空 = 上期。
--   · 取哪次运行（MTC_CA_F_RPT_RUN）：账期已生成凭单 → MTC_CA_PERIOD.PostRunId，否则 → CalcRunId（最近一次成功的正式运行）；
--     不跟执行台顶栏所选的运行走，网页和 SAP 看到的永远一样。只覆盖新框架起始账期（2026-09）以后。
--   · STYPE 显示方式：0 汇总 / 1 明细 / 2… 各报表在头注释里写明。NonZero = Y 只显示有数量或金额的行。
--   · 四项成本要素：材料 / 人工 / 制造 / 委外；列名用“·”分组（执行台拆成两行表头）。
--   · 过程只读（READS SQL DATA），只返回一个结果集，不写任何表；执行台在只读事务里 CALL。
--   · 业务口径参数（委外订单类型、样品销售类型、国内 / 国外客户）一律读 MTC_CA_C_PARAM，不写死。
-- 部署：build_deploy.py 把本文件放进部署包（带 -- @needs，B1 表齐了才执行）；单独部署 python3 新框架/tools/hana_exec.py -f 新框架/sql/21_reports.sql。
-- 勾稽语句：21_reports_verify.sql（每段正常返回 0 行）。离线写的，还没编译。
-- =====================================================================

-- 新参数：物料组 → 存货类别（R16 期末存货结构用）。格式 物料组:类别，逗号分隔，如 101:原材料,102:原材料,105:产成品；
-- 没列的物料组按 BOM 判断：层级 0 = 原材料，是别的物料的子件 = 半成品，其余 = 产成品
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('RPT_GRP_CLASS', '0000-00', '9999-99', ',', 'LIST', '成本报表 R16：物料组 → 存货类别（物料组:类别，逗号分隔）；没列的物料组按 BOM 判断（层级 0 原材料 / 是子件的半成品 / 其余产成品），用户 2026-10-30') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('RPT_GRP_CLASS', 'PARAM', '凭证与对账', 520, '成本报表：物料组对应的存货类别', 'LIST', NULL, '物料组:类别，逗号分隔，如 101:原材料,105:产成品；可以为空 = 全部按 BOM 判断') WITH PRIMARY KEY
@@
-- 逗号列表拆成行（空串 → 0 行）；最多 200 个值。V = 值，P = 开头匹配用的 LIKE 模式；值以 = 开头时精确匹配（如 =A1 不会匹配 A10，执行台钻取明细时用）
CREATE OR REPLACE FUNCTION "MTC_CA_F_RPT_LIST" (IN Str NVARCHAR(5000))
RETURNS TABLE ("V" NVARCHAR(200), "P" NVARCHAR(201))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE s NVARCHAR(5000) := REPLACE(IFNULL(:Str, ''), '，', ',');
    RETURN SELECT DISTINCT CASE WHEN LEFT("V", 1) = '=' THEN SUBSTRING("V", 2) ELSE "V" END AS "V",
                           CASE WHEN LEFT("V", 1) = '=' THEN SUBSTRING("V", 2) ELSE "V" || '%' END AS "P"
             FROM (SELECT TRIM(SUBSTR_REGEXPR('[^,]+' IN :s OCCURRENCE TO_INTEGER(G."GENERATED_PERIOD_START"))) AS "V"
                     FROM SERIES_GENERATE_INTEGER(1, 1, 201) G)
            WHERE "V" IS NOT NULL AND "V" <> '' AND "V" <> '=';
END
@@
-- 账期 → 取数运行（所有报表共用“取哪次运行”的规则）：一行 = 区间内一个账期（OFPR），没有成功正式运行的 RunId 为空
CREATE OR REPLACE FUNCTION "MTC_CA_F_RPT_RUN" (IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10))
RETURNS TABLE ("FcCode" NVARCHAR(10), "RunId" BIGINT, "PStatus" NVARCHAR(10), "PStatusName" NVARCHAR(20), "RunSrc" NVARCHAR(30),
               "EndTime" TIMESTAMP, "UserCode" NVARCHAR(50), "Batches" NVARCHAR(1000), "D0" DATE, "D1" DATE, "PrevFc" NVARCHAR(10),
               "Note" NVARCHAR(200))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE f0 NVARCHAR(10); DECLARE f1 NVARCHAR(10); DECLARE t NVARCHAR(10);
    f0 := NULLIF(TRIM(IFNULL(:FcFrom, '')), '');
    f1 := NULLIF(TRIM(IFNULL(:FcTo, '')), '');
    IF :f0 IS NULL THEN
        SELECT MAX("FcCode") INTO f0 FROM "MTC_CA_PERIOD" WHERE IFNULL("PostRunId", "CalcRunId") IS NOT NULL;
    END IF;
    IF :f1 IS NULL THEN f1 := :f0; END IF;
    IF :f1 < :f0 THEN t := :f0; f0 := :f1; f1 := :t; END IF;
    RETURN
    SELECT O."Code" AS "FcCode", COALESCE(P."PostRunId", P."CalcRunId") AS "RunId",
           CASE WHEN O."PeriodStat" = 'Y' THEN 'LOCKED' ELSE IFNULL(P."Status", 'OPEN') END AS "PStatus",
           CASE WHEN P."Status" = 'POSTED' THEN '已生成凭单' WHEN P."Status" = 'CALC' THEN '已计算' ELSE '未计算' END
             || CASE WHEN O."PeriodStat" = 'Y' THEN '（B1 已锁定）' ELSE '' END AS "PStatusName",
           CASE WHEN P."PostRunId" IS NOT NULL THEN '生成凭单所用运行' WHEN P."CalcRunId" IS NOT NULL THEN '最近一次成功正式运行' END AS "RunSrc",
           R."EndTime", R."UserCode", J."Batches",
           TO_DATE(O."F_RefDate") AS "D0", TO_DATE(O."T_RefDate") AS "D1",
           (SELECT MAX(X."Code") FROM "OFPR" X WHERE X."Code" < O."Code") AS "PrevFc",
           CASE WHEN COALESCE(P."PostRunId", P."CalcRunId") IS NULL THEN '本期没有成功的正式计算'
                WHEN R."RunId" IS NULL THEN '运行记录不存在'
                WHEN NOT EXISTS (SELECT 1 FROM "MTC_CA_R_ITEM" I WHERE I."RunId" = R."RunId") THEN '运行明细已清理，报表没有数据' END AS "Note"
      FROM "OFPR" O
      LEFT JOIN "MTC_CA_PERIOD" P ON P."FcCode" = O."Code"
      LEFT JOIN "MTC_CA_RUN" R ON R."RunId" = COALESCE(P."PostRunId", P."CalcRunId")
      LEFT JOIN (SELECT "FcCode", LEFT(STRING_AGG(TO_NVARCHAR("TransCode") || ' #' || TO_NVARCHAR("BatchNum"), ', ' ORDER BY "TransCode"), 1000) AS "Batches"
                   FROM "MTC_CA_JV" WHERE "Status" = 'CREATED' AND "BatchNum" IS NOT NULL GROUP BY "FcCode") J ON J."FcCode" = O."Code"
     WHERE O."Code" BETWEEN :f0 AND :f1;
END
@@
-- ---------------------------------------------------------------------
-- R00 成本报表运行状态：各账期报表取的是哪次运行、什么时候算的、凭单批号。
-- 参数：FcFrom, FcTo（都空 = 最近 12 个账期）
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_00_RUN" (IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE f0 NVARCHAR(10) := NULLIF(TRIM(IFNULL(:FcFrom, '')), '');
    DECLARE f1 NVARCHAR(10) := NULLIF(TRIM(IFNULL(:FcTo, '')), '');
    DECLARE lastFc NVARCHAR(10);
    IF :f0 IS NULL AND :f1 IS NULL THEN
        SELECT MAX("FcCode") INTO lastFc FROM "MTC_CA_PERIOD";
        SELECT MAX("Code") INTO lastFc FROM "OFPR" WHERE "Code" <= IFNULL(:lastFc, TO_NVARCHAR(CURRENT_DATE, 'YYYY-MM'));
        SELECT MIN("Code") INTO f0 FROM (SELECT TOP 12 "Code" FROM "OFPR" WHERE "Code" <= :lastFc ORDER BY "Code" DESC);
        f1 := :lastFc;
    END IF;
    SELECT R."FcCode" AS "账期", R."PStatusName" AS "账期状态", R."RunId" AS "运行号", R."RunSrc" AS "取数来源",
           R."EndTime" AS "计算完成时间", R."UserCode" AS "操作人", R."Batches" AS "凭单批号", R."D0" AS "期初日", R."D1" AS "期末日",
           R."Note" AS "说明"
      FROM "MTC_CA_F_RPT_RUN"(:f0, IFNULL(:f1, :f0)) R
     ORDER BY R."FcCode" DESC;
END
@@
-- ---------------------------------------------------------------------
-- R03 存货收发存汇总：每个物料（或物料组、存货科目）期初、本期入库、出库、期末的数量和四项金额。
-- 参数：FcFrom, FcTo, Item 物料, ItemGrp 物料组, Lvl 层级, ShowElem 展开四项 Y/N, ByCat 按收发类别分列 Y/N, NonZero Y/N,
--       STYPE 0 按物料 / 1 按物料组 / 2 按存货科目（OGAR.StockAct，物料组的存货科目）
-- 口径：MTC_CA_R_ITEM（P50 定稿）；入 / 出按数量正负（数量为 0 的发票差额、重估按交易类型方向）；多个账期时期初取第一期、期末取最后一期、
--       收发累加。按收发类别分列时“本期收发”各列带符号（增加为正），期初 + 各列合计 = 期末（尾差结转单列）。
-- 勾稽：期末金额合计 = R09 存货科目业务端；生产入库 = R01 / R02 完工成本合计（21_reports_verify.sql V01、V03）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_03_INVSUM" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN Lvl NVARCHAR(100),
    IN ShowElem NVARCHAR(1), IN ByCat NVARCHAR(1), IN NonZero NVARCHAR(1), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE fA NVARCHAR(10); DECLARE fB NVARCHAR(10);
    DECLARE nItem INT; DECLARE nGrp INT; DECLARE nLvl INT;
    DECLARE st NVARCHAR(1) := IFNULL(NULLIF(:STYPE, ''), '0');
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    SELECT MIN("FcCode"), MAX("FcCode") INTO fA, fB FROM :runs;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);    SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp); SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lLvl  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Lvl);     SELECT COUNT(*) INTO nLvl FROM :lLvl;

    it = SELECT R."ItemCode",
                MAX(CASE WHEN U."FcCode" = :fB THEN R."iLevel" END) AS "Lv",
                SUM(CASE WHEN U."FcCode" = :fA THEN R."OpenQty" ELSE 0 END) AS "BQ",
                SUM(CASE WHEN U."FcCode" = :fA THEN R."OpenMat" ELSE 0 END) AS "BMat", SUM(CASE WHEN U."FcCode" = :fA THEN R."OpenLab" ELSE 0 END) AS "BLab",
                SUM(CASE WHEN U."FcCode" = :fA THEN R."OpenMfg" ELSE 0 END) AS "BMfg", SUM(CASE WHEN U."FcCode" = :fA THEN R."OpenSub" ELSE 0 END) AS "BSub",
                SUM(R."InQty") AS "IQ", SUM(R."InMat") AS "IMat", SUM(R."InLab") AS "ILab", SUM(R."InMfg") AS "IMfg", SUM(R."InSub") AS "ISub",
                -SUM(R."OutQty") AS "OQ", -SUM(R."OutMat") AS "OMat", -SUM(R."OutLab") AS "OLab", -SUM(R."OutMfg") AS "OMfg", -SUM(R."OutSub") AS "OSub",
                SUM(CASE WHEN U."FcCode" = :fB THEN R."EndQty" ELSE 0 END) AS "EQ",
                SUM(CASE WHEN U."FcCode" = :fB THEN R."EndMat" ELSE 0 END) AS "EMat", SUM(CASE WHEN U."FcCode" = :fB THEN R."EndLab" ELSE 0 END) AS "ELab",
                SUM(CASE WHEN U."FcCode" = :fB THEN R."EndMfg" ELSE 0 END) AS "EMfg", SUM(CASE WHEN U."FcCode" = :fB THEN R."EndSub" ELSE 0 END) AS "ESub",
                SUM(R."TailAmt") AS "CTail"
           FROM :runs U JOIN "MTC_CA_R_ITEM" R ON R."RunId" = U."RunId"
          GROUP BY R."ItemCode";
    cat = SELECT L."ItemCode",
                 SUM(CASE WHEN L."TransCode" IN ('I01', 'I06') THEN L."Amount" ELSE 0 END) AS "CPur",
                 SUM(CASE WHEN L."TransCode" IN ('I03', 'I07', 'I08', 'I09', 'I90') THEN L."Amount" ELSE 0 END) AS "CPrd",
                 SUM(CASE WHEN L."TransCode" IN ('O03', 'O07', 'O90') THEN L."Amount" ELSE 0 END) AS "CIss",
                 SUM(CASE WHEN L."TransCode" IN ('O08', 'O09') THEN L."Amount" ELSE 0 END) AS "CWw",
                 SUM(CASE WHEN L."TransCode" IN ('O01', 'O06') THEN L."Amount" ELSE 0 END) AS "CSal",
                 SUM(CASE WHEN L."TransCode" IN ('I05', 'O05') THEN L."Amount" ELSE 0 END) AS "CTrf",
                 SUM(CASE WHEN L."TransCode" IN ('I02', 'O02') THEN L."Amount" ELSE 0 END) AS "CMov",
                 SUM(CASE WHEN L."TransCode" IN ('I04', 'O04') THEN L."Amount" ELSE 0 END) AS "COth",
                 SUM(CASE WHEN L."TransCode" IN ('I10', 'O10') THEN L."Amount" ELSE 0 END) AS "CCnt",
                 SUM(CASE WHEN L."TransCode" IS NULL OR L."TransCode" NOT IN ('I01', 'I06', 'I03', 'I07', 'I08', 'I09', 'I90', 'O03', 'O07', 'O90', 'O08', 'O09',
                                                                            'O01', 'O06', 'I05', 'O05', 'I02', 'O02', 'I04', 'O04', 'I10', 'O10')
                          THEN L."Amount" ELSE 0 END) AS "CRev"
            FROM :runs U JOIN "MTC_CA_R_LINE" L ON L."RunId" = U."RunId"
           GROUP BY L."ItemCode";
    base = SELECT I.*, M."ItemName", TO_NVARCHAR(M."ItmsGrpCod") AS "Grp", G."ItmsGrpNam" AS "GrpName",
                  A."StockAct" AS "Acct", AC."AcctName",
                  IFNULL(C."CPur", 0) AS "CPur", IFNULL(C."CPrd", 0) AS "CPrd", IFNULL(C."CIss", 0) AS "CIss", IFNULL(C."CWw", 0) AS "CWw",
                  IFNULL(C."CSal", 0) AS "CSal", IFNULL(C."CTrf", 0) AS "CTrf", IFNULL(C."CMov", 0) AS "CMov", IFNULL(C."COth", 0) AS "COth",
                  IFNULL(C."CCnt", 0) AS "CCnt", IFNULL(C."CRev", 0) AS "CRev"
             FROM :it I
             LEFT JOIN :cat C ON C."ItemCode" = I."ItemCode"
             LEFT JOIN "OITM" M ON M."ItemCode" = I."ItemCode"
             LEFT JOIN "OITB" G ON G."ItmsGrpCod" = M."ItmsGrpCod"
             LEFT JOIN (SELECT "ItmsGrpCod", MAX("StockAct") AS "StockAct" FROM "OGAR" WHERE "PeriodCat" = LEFT(:fB, 4) GROUP BY "ItmsGrpCod") A
                    ON A."ItmsGrpCod" = M."ItmsGrpCod"
             LEFT JOIN "OACT" AC ON AC."AcctCode" = A."StockAct"
            WHERE (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE I."ItemCode" LIKE X."P"))
              AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"))
              AND (:nLvl = 0 OR EXISTS (SELECT 1 FROM :lLvl X WHERE TO_NVARCHAR(I."Lv") = X."V"))
              AND (IFNULL(:NonZero, 'N') <> 'Y' OR I."BQ" <> 0 OR I."IQ" <> 0 OR I."OQ" <> 0 OR I."EQ" <> 0
                   OR I."BMat" + I."BLab" + I."BMfg" + I."BSub" <> 0 OR I."IMat" + I."ILab" + I."IMfg" + I."ISub" <> 0
                   OR I."OMat" + I."OLab" + I."OMfg" + I."OSub" <> 0 OR I."EMat" + I."ELab" + I."EMfg" + I."ESub" <> 0);
    base2 = SELECT B.*, CASE :st WHEN '1' THEN B."Grp" WHEN '2' THEN B."Acct" ELSE B."ItemCode" END AS "KCode",
                  CASE :st WHEN '1' THEN LPAD(IFNULL(B."Grp", ''), 10, '0') WHEN '2' THEN IFNULL(B."Acct", '')
                       ELSE LPAD(IFNULL(B."Grp", ''), 10, '0') || B."ItemCode" END AS "SK"
             FROM :base B;
    o = SELECT CASE WHEN :st = '2' THEN NULL ELSE MAX("Grp") END AS "物料组",
               MAX("Acct") AS "存货科目",
               "KCode" AS "代码",
               CASE :st WHEN '1' THEN MAX("GrpName") WHEN '2' THEN MAX("AcctName") ELSE MAX("ItemName") END AS "名称",
               CASE WHEN :st = '0' THEN MAX("Lv") END AS "层级",
               CAST(SUM("BQ") AS DECIMAL(19,6)) AS "期初·数量",
               CAST(SUM("BMat" + "BLab" + "BMfg" + "BSub") / NULLIF(CASE WHEN :st = '0' THEN SUM("BQ") END, 0) AS DECIMAL(19,6)) AS "期初·单价",
               CAST(SUM("BMat" + "BLab" + "BMfg" + "BSub") AS DECIMAL(19,2)) AS "期初·金额",
               CAST(SUM("BMat") AS DECIMAL(19,2)) AS "期初·材料", CAST(SUM("BLab") AS DECIMAL(19,2)) AS "期初·人工",
               CAST(SUM("BMfg") AS DECIMAL(19,2)) AS "期初·制造", CAST(SUM("BSub") AS DECIMAL(19,2)) AS "期初·委外",
               CAST(SUM("IQ") AS DECIMAL(19,6)) AS "入库·数量",
               CAST(SUM("IMat" + "ILab" + "IMfg" + "ISub") / NULLIF(CASE WHEN :st = '0' THEN SUM("IQ") END, 0) AS DECIMAL(19,6)) AS "入库·单价",
               CAST(SUM("IMat" + "ILab" + "IMfg" + "ISub") AS DECIMAL(19,2)) AS "入库·金额",
               CAST(SUM("IMat") AS DECIMAL(19,2)) AS "入库·材料", CAST(SUM("ILab") AS DECIMAL(19,2)) AS "入库·人工",
               CAST(SUM("IMfg") AS DECIMAL(19,2)) AS "入库·制造", CAST(SUM("ISub") AS DECIMAL(19,2)) AS "入库·委外",
               CAST(SUM("OQ") AS DECIMAL(19,6)) AS "出库·数量",
               CAST(SUM("OMat" + "OLab" + "OMfg" + "OSub") / NULLIF(CASE WHEN :st = '0' THEN SUM("OQ") END, 0) AS DECIMAL(19,6)) AS "出库·单价",
               CAST(SUM("OMat" + "OLab" + "OMfg" + "OSub") AS DECIMAL(19,2)) AS "出库·金额",
               CAST(SUM("OMat") AS DECIMAL(19,2)) AS "出库·材料", CAST(SUM("OLab") AS DECIMAL(19,2)) AS "出库·人工",
               CAST(SUM("OMfg") AS DECIMAL(19,2)) AS "出库·制造", CAST(SUM("OSub") AS DECIMAL(19,2)) AS "出库·委外",
               CAST(SUM("EQ") AS DECIMAL(19,6)) AS "期末·数量",
               CAST(SUM("EMat" + "ELab" + "EMfg" + "ESub") / NULLIF(CASE WHEN :st = '0' THEN SUM("EQ") END, 0) AS DECIMAL(19,6)) AS "期末·单价",
               CAST(SUM("EMat" + "ELab" + "EMfg" + "ESub") AS DECIMAL(19,2)) AS "期末·金额",
               CAST(SUM("EMat") AS DECIMAL(19,2)) AS "期末·材料", CAST(SUM("ELab") AS DECIMAL(19,2)) AS "期末·人工",
               CAST(SUM("EMfg") AS DECIMAL(19,2)) AS "期末·制造", CAST(SUM("ESub") AS DECIMAL(19,2)) AS "期末·委外",
               CAST(SUM("CPur") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·采购", CAST(SUM("CPrd") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·生产入库",
               CAST(SUM("CIss") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·生产领用", CAST(SUM("CWw") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·委外发出",
               CAST(SUM("CSal") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·销售及退货", CAST(SUM("CTrf") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·形态转换",
               CAST(SUM("CMov") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·转储", CAST(SUM("COth") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·其他出入库",
               CAST(SUM("CCnt") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·盘点", CAST(SUM("CRev") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·重估及差异",
               CAST(SUM("CTail") AS DECIMAL(19,2)) AS "本期收发（增 + 减 −）·尾差结转",
               "SK"
          FROM :base2
         GROUP BY "KCode", "SK";
    IF IFNULL(:ShowElem, 'N') = 'Y' AND IFNULL(:ByCat, 'N') = 'Y' THEN
        SELECT "物料组", "存货科目", "代码", "名称", "层级",
               "期初·数量", "期初·单价", "期初·金额", "期初·材料", "期初·人工", "期初·制造", "期初·委外",
               "入库·数量", "入库·单价", "入库·金额", "入库·材料", "入库·人工", "入库·制造", "入库·委外",
               "出库·数量", "出库·单价", "出库·金额", "出库·材料", "出库·人工", "出库·制造", "出库·委外",
               "期末·数量", "期末·单价", "期末·金额", "期末·材料", "期末·人工", "期末·制造", "期末·委外",
               "本期收发（增 + 减 −）·采购", "本期收发（增 + 减 −）·生产入库", "本期收发（增 + 减 −）·生产领用", "本期收发（增 + 减 −）·委外发出",
               "本期收发（增 + 减 −）·销售及退货", "本期收发（增 + 减 −）·形态转换", "本期收发（增 + 减 −）·转储", "本期收发（增 + 减 −）·其他出入库",
               "本期收发（增 + 减 −）·盘点", "本期收发（增 + 减 −）·重估及差异", "本期收发（增 + 减 −）·尾差结转"
          FROM :o ORDER BY "SK";
    ELSEIF IFNULL(:ShowElem, 'N') = 'Y' THEN
        SELECT "物料组", "存货科目", "代码", "名称", "层级",
               "期初·数量", "期初·单价", "期初·金额", "期初·材料", "期初·人工", "期初·制造", "期初·委外",
               "入库·数量", "入库·单价", "入库·金额", "入库·材料", "入库·人工", "入库·制造", "入库·委外",
               "出库·数量", "出库·单价", "出库·金额", "出库·材料", "出库·人工", "出库·制造", "出库·委外",
               "期末·数量", "期末·单价", "期末·金额", "期末·材料", "期末·人工", "期末·制造", "期末·委外"
          FROM :o ORDER BY "SK";
    ELSEIF IFNULL(:ByCat, 'N') = 'Y' THEN
        SELECT "物料组", "存货科目", "代码", "名称", "层级", "期初·数量", "期初·金额",
               "本期收发（增 + 减 −）·采购", "本期收发（增 + 减 −）·生产入库", "本期收发（增 + 减 −）·生产领用", "本期收发（增 + 减 −）·委外发出",
               "本期收发（增 + 减 −）·销售及退货", "本期收发（增 + 减 −）·形态转换", "本期收发（增 + 减 −）·转储", "本期收发（增 + 减 −）·其他出入库",
               "本期收发（增 + 减 −）·盘点", "本期收发（增 + 减 −）·重估及差异", "本期收发（增 + 减 −）·尾差结转",
               "期末·数量", "期末·金额"
          FROM :o ORDER BY "SK";
    ELSE
        SELECT "物料组", "存货科目", "代码", "名称", "层级",
               "期初·数量", "期初·单价", "期初·金额", "入库·数量", "入库·单价", "入库·金额",
               "出库·数量", "出库·单价", "出库·金额", "期末·数量", "期末·单价", "期末·金额"
          FROM :o ORDER BY "SK";
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R04 存货明细账：逐条库存变动，带结存数量和金额。
-- 参数：FcFrom, FcTo, Item 物料, ItemGrp 物料组, Trans 交易类型（I01、O03…）, Dir 方向（I 入 / O 出）, OrderNum 订单号 Num, Whs 仓库
-- 口径：MTC_CA_R_LINE + MTC_CA_S_LINE（单据信息）；结存 = 第一期期初 + 按 账期、日期、行号 累计（先按物料全部行算好再按条件筛选，
--       所以只看某类交易时结存仍是该物料的真实结存）；尾差结转（JZ04）放在每期期末日。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_04_LEDGER" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN Trans NVARCHAR(500),
    IN Dir NVARCHAR(1), IN OrderNum NVARCHAR(5000), IN Whs NVARCHAR(500))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE fA NVARCHAR(10); DECLARE nItem INT; DECLARE nGrp INT; DECLARE nTr INT; DECLARE nOrd INT; DECLARE nWhs INT;
    runs = SELECT "FcCode", "RunId", "D1" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    SELECT MIN("FcCode") INTO fA FROM :runs;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);     SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp);  SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lTr   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Trans);    SELECT COUNT(*) INTO nTr FROM :lTr;
    lOrd  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:OrderNum); SELECT COUNT(*) INTO nOrd FROM :lOrd;
    lWhs  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Whs);      SELECT COUNT(*) INTO nWhs FROM :lWhs;

    items = SELECT DISTINCT R."ItemCode"
              FROM :runs U JOIN "MTC_CA_R_ITEM" R ON R."RunId" = U."RunId"
              LEFT JOIN "OITM" M ON M."ItemCode" = R."ItemCode"
             WHERE (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE R."ItemCode" LIKE X."P"))
               AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"));
    beg = SELECT R."ItemCode", R."OpenQty" AS "Q", R."OpenMat" + R."OpenMfg" + R."OpenLab" + R."OpenSub" AS "A"
            FROM :runs U JOIN "MTC_CA_R_ITEM" R ON R."RunId" = U."RunId" JOIN :items I ON I."ItemCode" = R."ItemCode"
           WHERE U."FcCode" = :fA;
    mv = SELECT U."FcCode", L."ItemCode", D."DocDate", L."LineId", D."ObjType", D."DocNum", D."LineNum", L."TransCode", D."BusiType", D."WhsCode",
                L."OrderType", L."OrderEntry", SO."OrderNum", SO."WorType", L."Qty", L."Amount", L."MatAmt", L."LabAmt", L."MfgAmt", L."SubAmt", L."PriceSrc",
                CASE WHEN L."Qty" > 0 THEN 'I' WHEN L."Qty" < 0 THEN 'O'
                     WHEN LEFT(IFNULL(L."TransCode", 'I'), 1) = 'O' AND L."TransCode" <> 'O06' THEN 'O' ELSE 'I' END AS "Dir"
           FROM :runs U
           JOIN "MTC_CA_R_LINE" L ON L."RunId" = U."RunId"
           JOIN :items I ON I."ItemCode" = L."ItemCode"
           JOIN "MTC_CA_S_LINE" D ON D."RunId" = L."RunId" AND D."LineId" = L."LineId"
           LEFT JOIN "MTC_CA_S_ORDER" SO ON SO."RunId" = L."RunId" AND SO."OrderType" = L."OrderType" AND SO."OrderEntry" = L."OrderEntry"
          WHERE NOT (D."ObjType" IN ('13', '14') AND L."Qty" = 0 AND L."Amount" = 0)
         UNION ALL
         SELECT U."FcCode", R."ItemCode", U."D1", 999999999999, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                0, R."TailAmt", 0, 0, 0, 0, '零库存尾差结转（JZ04，TAIL-01）', 'O'
           FROM :runs U JOIN "MTC_CA_R_ITEM" R ON R."RunId" = U."RunId" JOIN :items I ON I."ItemCode" = R."ItemCode"
          WHERE R."TailAmt" <> 0;
    bal = SELECT M.*,
                 IFNULL(B."Q", 0) + SUM(M."Qty") OVER (PARTITION BY M."ItemCode" ORDER BY M."FcCode", M."DocDate", M."LineId" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "BalQ",
                 IFNULL(B."A", 0) + SUM(M."Amount") OVER (PARTITION BY M."ItemCode" ORDER BY M."FcCode", M."DocDate", M."LineId" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "BalA"
            FROM :mv M LEFT JOIN :beg B ON B."ItemCode" = M."ItemCode";
    SELECT X."账期", X."物料", M."ItemName" AS "名称", X."日期", X."单据类型", X."单号 Num", X."行号", X."交易类型", T."Name" AS "交易类型名称",
           X."业务类型", X."仓库", X."订单号 Num", X."订单类型",
           X."入库·数量", CAST(X."入库·金额" / NULLIF(X."入库·数量", 0) AS DECIMAL(19,6)) AS "入库·单价", X."入库·金额",
           X."出库·数量", CAST(X."出库·金额" / NULLIF(X."出库·数量", 0) AS DECIMAL(19,6)) AS "出库·单价", X."出库·金额",
           X."结存·数量", CAST(X."结存·金额" / NULLIF(X."结存·数量", 0) AS DECIMAL(19,6)) AS "结存·单价", X."结存·金额",
           X."本行·材料", X."本行·人工", X."本行·制造", X."本行·委外", X."定价来源"
      FROM (
        SELECT :fA AS "账期", B."ItemCode" AS "物料", CAST(NULL AS DATE) AS "日期", CAST(NULL AS NVARCHAR(20)) AS "单据类型", CAST('期初结存' AS NVARCHAR(50)) AS "单号 Num",
               CAST(NULL AS INTEGER) AS "行号", CAST(NULL AS NVARCHAR(10)) AS "交易类型", CAST(NULL AS NVARCHAR(20)) AS "业务类型", CAST(NULL AS NVARCHAR(8)) AS "仓库",
               CAST(NULL AS NVARCHAR(50)) AS "订单号 Num", CAST(NULL AS NVARCHAR(10)) AS "订单类型",
               CAST(NULL AS DECIMAL(19,6)) AS "入库·数量", CAST(NULL AS DECIMAL(19,2)) AS "入库·金额", CAST(NULL AS DECIMAL(19,6)) AS "出库·数量", CAST(NULL AS DECIMAL(19,2)) AS "出库·金额",
               CAST(B."Q" AS DECIMAL(19,6)) AS "结存·数量", CAST(B."A" AS DECIMAL(19,2)) AS "结存·金额",
               CAST(NULL AS DECIMAL(19,2)) AS "本行·材料", CAST(NULL AS DECIMAL(19,2)) AS "本行·人工", CAST(NULL AS DECIMAL(19,2)) AS "本行·制造", CAST(NULL AS DECIMAL(19,2)) AS "本行·委外",
               CAST(NULL AS NVARCHAR(200)) AS "定价来源", '0000-00' AS "SF", CAST(NULL AS DATE) AS "SD", CAST(-1 AS BIGINT) AS "SL"
          FROM :beg B
         WHERE :nTr = 0 AND IFNULL(:Dir, '') = '' AND :nOrd = 0 AND :nWhs = 0
           AND EXISTS (SELECT 1 FROM :mv M WHERE M."ItemCode" = B."ItemCode")
        UNION ALL
        SELECT B."FcCode", B."ItemCode", B."DocDate", B."ObjType", B."DocNum", B."LineNum", B."TransCode", B."BusiType", B."WhsCode",
               B."OrderNum", B."WorType",
               CASE WHEN B."Dir" = 'I' THEN CAST(B."Qty" AS DECIMAL(19,6)) END, CASE WHEN B."Dir" = 'I' THEN CAST(B."Amount" AS DECIMAL(19,2)) END,
               CASE WHEN B."Dir" = 'O' THEN CAST(-B."Qty" AS DECIMAL(19,6)) END, CASE WHEN B."Dir" = 'O' THEN CAST(-B."Amount" AS DECIMAL(19,2)) END,
               CAST(B."BalQ" AS DECIMAL(19,6)), CAST(B."BalA" AS DECIMAL(19,2)),
               CAST(B."MatAmt" AS DECIMAL(19,2)), CAST(B."LabAmt" AS DECIMAL(19,2)), CAST(B."MfgAmt" AS DECIMAL(19,2)), CAST(B."SubAmt" AS DECIMAL(19,2)),
               B."PriceSrc", B."FcCode", B."DocDate", B."LineId"
          FROM :bal B
         WHERE (:nTr = 0 OR EXISTS (SELECT 1 FROM :lTr X WHERE B."TransCode" = X."V"))
           AND (IFNULL(:Dir, '') = '' OR B."Dir" = :Dir)
           AND (:nOrd = 0 OR EXISTS (SELECT 1 FROM :lOrd X WHERE B."OrderNum" LIKE X."P"))
           AND (:nWhs = 0 OR EXISTS (SELECT 1 FROM :lWhs X WHERE B."WhsCode" = X."V"))
      ) X
      LEFT JOIN "OITM" M ON M."ItemCode" = X."物料"
      LEFT JOIN "@MTC_COST_IOTYPE" T ON T."Code" = X."交易类型"
     ORDER BY X."物料", X."SF", X."SD", X."SL";
END
@@
-- ---------------------------------------------------------------------
-- R01 产品成本计算单：每张订单期初在产品 + 本期投入 + 本级分摊 = 完工转出 + 关单差异 + 期末在产品（四项）。
-- 参数：FcFrom, FcTo, WorType 订单类型（10/20/30/40/50）, OrderNum 订单号 Num, Item 产品, ItemGrp 产品物料组,
--       Scope 订单范围（空 全部 / 1 本期有完工 / 2 本期按关单处理 / 3 期末有在产品）, STYPE 0 按订单 / 1 订单 × 材料
-- 口径：MTC_CA_R_ORDER（完工成本、分摊、在产品、关单差异）+ MTC_CA_R_ORDER_MAT（期初累计、本期领料、结转、在产品、关单差异）；
--       材料 '#SUBFEE' 行 = 委外加工费。多个账期时每个账期一行。“勾稽差额”应为 0。
-- 勾稽：完工转出合计 = R02 总成本 = R03 生产入库；期末在产品 = R09 生产成本 / 委外加工物资业务端；本级分摊 = R06 已分配（V02–V05）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_01_ORDCALC" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN WorType NVARCHAR(100), IN OrderNum NVARCHAR(5000), IN Item NVARCHAR(5000),
    IN ItemGrp NVARCHAR(5000), IN Scope NVARCHAR(1), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE nWt INT; DECLARE nOrd INT; DECLARE nItem INT; DECLARE nGrp INT;
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    lWt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:WorType);  SELECT COUNT(*) INTO nWt FROM :lWt;
    lOrd  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:OrderNum); SELECT COUNT(*) INTO nOrd FROM :lOrd;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);     SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp);  SELECT COUNT(*) INTO nGrp FROM :lGrp;
    ord = SELECT O.*, S."OrderNum", S."StatusAtEnd", S."CardCode", M."ItemName", TO_NVARCHAR(M."ItmsGrpCod") AS "Grp"
            FROM :runs U
            JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
            LEFT JOIN "MTC_CA_S_ORDER" S ON S."RunId" = O."RunId" AND S."OrderType" = O."OrderType" AND S."OrderEntry" = O."OrderEntry"
            LEFT JOIN "OITM" M ON M."ItemCode" = O."ItemCode"
           WHERE (:nWt = 0 OR EXISTS (SELECT 1 FROM :lWt X WHERE O."WorType" = X."V"))
             AND (:nOrd = 0 OR EXISTS (SELECT 1 FROM :lOrd X WHERE S."OrderNum" LIKE X."P"))
             AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE O."ItemCode" LIKE X."P"))
             AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"))
             AND (IFNULL(:Scope, '') = '' OR (:Scope = '1' AND O."RecvQty" <> 0) OR (:Scope = '2' AND O."ClosedInFc" = 'Y') OR (:Scope = '3' AND O."WipAmt" <> 0));
    IF :STYPE = '1' THEN
        SELECT O."FcCode" AS "账期", O."OrderType" AS "订单单据", O."OrderNum" AS "订单号 Num", O."OrderEntry" AS "订单 Entry", O."WorType" AS "订单类型",
               O."ItemCode" AS "产品", O."ItemName" AS "产品名称",
               M."ItemCode" AS "材料",
               CASE WHEN M."ItemCode" = '#SUBFEE' THEN '委外加工费' ELSE I."ItemName" END AS "材料名称",
               CAST(M."OpenIssQty" AS DECIMAL(19,6)) AS "期初·累计领料数量",
               CAST(M."OpenIssMat" + M."OpenIssLab" + M."OpenIssMfg" + M."OpenIssSub" - M."OpenCarMat" - M."OpenCarLab" - M."OpenCarMfg" - M."OpenCarSub" AS DECIMAL(19,2)) AS "期初·在产品",
               CAST(M."IssQty" AS DECIMAL(19,6)) AS "本期领料·数量",
               CAST(M."IssMat" + M."IssLab" + M."IssMfg" + M."IssSub" AS DECIMAL(19,2)) AS "本期领料·金额",
               CAST(M."Ratio" AS DECIMAL(19,6)) AS "结转比例",
               CAST(M."CarMat" AS DECIMAL(19,2)) AS "完工转出·材料", CAST(M."CarLab" AS DECIMAL(19,2)) AS "完工转出·人工",
               CAST(M."CarMfg" AS DECIMAL(19,2)) AS "完工转出·制造", CAST(M."CarSub" AS DECIMAL(19,2)) AS "完工转出·委外",
               CAST(M."CarMat" + M."CarLab" + M."CarMfg" + M."CarSub" AS DECIMAL(19,2)) AS "完工转出·合计",
               CAST(M."ClsMat" + M."ClsLab" + M."ClsMfg" + M."ClsSub" AS DECIMAL(19,2)) AS "关单差异",
               CAST(M."WipMat" AS DECIMAL(19,2)) AS "期末在产品·材料", CAST(M."WipLab" AS DECIMAL(19,2)) AS "期末在产品·人工",
               CAST(M."WipMfg" AS DECIMAL(19,2)) AS "期末在产品·制造", CAST(M."WipSub" AS DECIMAL(19,2)) AS "期末在产品·委外",
               CAST(M."WipMat" + M."WipLab" + M."WipMfg" + M."WipSub" AS DECIMAL(19,2)) AS "期末在产品·合计"
          FROM :ord O
          JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = O."RunId" AND M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
          LEFT JOIN "OITM" I ON I."ItemCode" = M."ItemCode"
         ORDER BY O."FcCode", O."iLevel", O."OrderType", O."OrderEntry", CASE WHEN M."ItemCode" = '#SUBFEE' THEN 1 ELSE 0 END, M."ItemCode";
    ELSE
        mat = SELECT "RunId", "OrderType", "OrderEntry",
                     SUM("OpenIssMat" - "OpenCarMat") AS "BMat", SUM("OpenIssLab" - "OpenCarLab") AS "BLab",
                     SUM("OpenIssMfg" - "OpenCarMfg") AS "BMfg", SUM("OpenIssSub" - "OpenCarSub") AS "BSub",
                     SUM("IssMat") AS "IMat", SUM("IssLab") AS "ILab", SUM("IssMfg") AS "IMfg", SUM("IssSub") AS "ISub",
                     SUM("ClsMat" + "ClsLab" + "ClsMfg" + "ClsSub") AS "Cls",
                     SUM("WipMat") AS "WMat", SUM("WipLab") AS "WLab", SUM("WipMfg") AS "WMfg", SUM("WipSub") AS "WSub"
                FROM "MTC_CA_R_ORDER_MAT" WHERE "RunId" IN (SELECT "RunId" FROM :runs)
               GROUP BY "RunId", "OrderType", "OrderEntry";
        SELECT O."FcCode" AS "账期", O."OrderType" AS "订单单据", O."OrderNum" AS "订单号 Num", O."OrderEntry" AS "订单 Entry", O."WorType" AS "订单类型",
               O."ItemCode" AS "产品", O."ItemName" AS "产品名称", O."Grp" AS "物料组", O."iLevel" AS "层级", O."CardCode" AS "委外供应商",
               O."StatusAtEnd" AS "期末状态", O."ClosedInFc" AS "按关单处理",
               CAST(O."PlannedQty" AS DECIMAL(19,6)) AS "计划数", CAST(O."PrevRecvQty" AS DECIMAL(19,6)) AS "上期累计完工", CAST(O."RecvQty" AS DECIMAL(19,6)) AS "本期完工",
               CAST(IFNULL(M."BMat", 0) AS DECIMAL(19,2)) AS "期初在产品·材料", CAST(IFNULL(M."BLab", 0) AS DECIMAL(19,2)) AS "期初在产品·人工",
               CAST(IFNULL(M."BMfg", 0) AS DECIMAL(19,2)) AS "期初在产品·制造", CAST(IFNULL(M."BSub", 0) AS DECIMAL(19,2)) AS "期初在产品·委外",
               CAST(IFNULL(M."BMat" + M."BLab" + M."BMfg" + M."BSub", 0) AS DECIMAL(19,2)) AS "期初在产品·合计",
               CAST(IFNULL(M."IMat", 0) AS DECIMAL(19,2)) AS "本期投入·材料", CAST(IFNULL(M."ILab", 0) AS DECIMAL(19,2)) AS "本期投入·人工",
               CAST(IFNULL(M."IMfg", 0) AS DECIMAL(19,2)) AS "本期投入·制造", CAST(IFNULL(M."ISub", 0) AS DECIMAL(19,2)) AS "本期投入·委外",
               CAST(IFNULL(M."IMat" + M."ILab" + M."IMfg" + M."ISub", 0) AS DECIMAL(19,2)) AS "本期投入·合计",
               CAST(O."AllocLab" AS DECIMAL(19,2)) AS "本级分摊·人工", CAST(O."AllocMfg" AS DECIMAL(19,2)) AS "本级分摊·制造",
               CAST(O."CostMat" AS DECIMAL(19,2)) AS "完工转出·材料", CAST(O."CostLab" AS DECIMAL(19,2)) AS "完工转出·人工",
               CAST(O."CostMfg" AS DECIMAL(19,2)) AS "完工转出·制造", CAST(O."CostSub" AS DECIMAL(19,2)) AS "完工转出·委外",
               CAST(O."CostAmt" AS DECIMAL(19,2)) AS "完工转出·合计", CAST(O."UnitCost" AS DECIMAL(19,6)) AS "完工转出·单位成本",
               CAST(O."CloseDifAmt" AS DECIMAL(19,2)) AS "关单差异",
               CAST(IFNULL(M."WMat", 0) AS DECIMAL(19,2)) AS "期末在产品·材料", CAST(IFNULL(M."WLab", 0) AS DECIMAL(19,2)) AS "期末在产品·人工",
               CAST(IFNULL(M."WMfg", 0) AS DECIMAL(19,2)) AS "期末在产品·制造", CAST(IFNULL(M."WSub", 0) AS DECIMAL(19,2)) AS "期末在产品·委外",
               CAST(O."WipAmt" AS DECIMAL(19,2)) AS "期末在产品·合计",
               CAST(IFNULL(M."BMat" + M."BLab" + M."BMfg" + M."BSub", 0) + IFNULL(M."IMat" + M."ILab" + M."IMfg" + M."ISub", 0) + O."AllocLab" + O."AllocMfg"
                    - O."CostAmt" - O."CloseDifAmt" - O."WipAmt" AS DECIMAL(19,2)) AS "勾稽差额"
          FROM :ord O
          LEFT JOIN :mat M ON M."RunId" = O."RunId" AND M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
         ORDER BY O."FcCode", O."iLevel", O."OrderType", O."OrderEntry";
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R02 完工产品成本汇总：每个产品本期完工数量、四项成本、单位成本和构成。
-- 参数：FcFrom, FcTo, Item 产品, ItemGrp 物料组, Lvl 层级, WorType 订单类型, STYPE 0 按产品 / 1 产品 × 订单
-- 口径：MTC_CA_R_ORDER 本期完工成本（Cost*，含本级分摊），只列本期有完工或有完工成本的订单；多个账期累加。
-- 勾稽：总成本 = R01 完工转出合计 = R03 生产入库（V01）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_02_PRODCOST" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN Lvl NVARCHAR(100),
    IN WorType NVARCHAR(100), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE nItem INT; DECLARE nGrp INT; DECLARE nLvl INT; DECLARE nWt INT;
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);    SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp); SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lLvl  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Lvl);     SELECT COUNT(*) INTO nLvl FROM :lLvl;
    lWt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:WorType); SELECT COUNT(*) INTO nWt FROM :lWt;
    ord = SELECT U."FcCode", O."RunId", O."OrderType", O."OrderEntry", S."OrderNum", O."WorType", O."ItemCode", M."ItemName",
                 TO_NVARCHAR(M."ItmsGrpCod") AS "Grp", G."ItmsGrpNam" AS "GrpName", O."iLevel",
                 O."RecvQty", O."CostMat", O."CostLab", O."CostMfg", O."CostSub", O."CostAmt"
            FROM :runs U
            JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
            LEFT JOIN "MTC_CA_S_ORDER" S ON S."RunId" = O."RunId" AND S."OrderType" = O."OrderType" AND S."OrderEntry" = O."OrderEntry"
            LEFT JOIN "OITM" M ON M."ItemCode" = O."ItemCode"
            LEFT JOIN "OITB" G ON G."ItmsGrpCod" = M."ItmsGrpCod"
           WHERE (O."RecvQty" <> 0 OR O."CostAmt" <> 0)
             AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE O."ItemCode" LIKE X."P"))
             AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"))
             AND (:nLvl = 0 OR EXISTS (SELECT 1 FROM :lLvl X WHERE TO_NVARCHAR(O."iLevel") = X."V"))
             AND (:nWt = 0 OR EXISTS (SELECT 1 FROM :lWt X WHERE O."WorType" = X."V"));
    IF :STYPE = '1' THEN
        SELECT "ItemCode" AS "产品", "ItemName" AS "名称", "FcCode" AS "账期", "OrderType" AS "订单单据", "OrderNum" AS "订单号 Num",
               "OrderEntry" AS "订单 Entry", "WorType" AS "订单类型",
               CAST("RecvQty" AS DECIMAL(19,6)) AS "完工数量",
               CAST("CostMat" AS DECIMAL(19,2)) AS "完工成本·材料", CAST("CostLab" AS DECIMAL(19,2)) AS "完工成本·人工",
               CAST("CostMfg" AS DECIMAL(19,2)) AS "完工成本·制造", CAST("CostSub" AS DECIMAL(19,2)) AS "完工成本·委外",
               CAST("CostAmt" AS DECIMAL(19,2)) AS "完工成本·合计",
               CAST("CostAmt" / NULLIF("RecvQty", 0) AS DECIMAL(19,6)) AS "单位成本·合计",
               CAST("CostMat" / NULLIF("RecvQty", 0) AS DECIMAL(19,6)) AS "单位成本·材料", CAST("CostLab" / NULLIF("RecvQty", 0) AS DECIMAL(19,6)) AS "单位成本·人工",
               CAST("CostMfg" / NULLIF("RecvQty", 0) AS DECIMAL(19,6)) AS "单位成本·制造", CAST("CostSub" / NULLIF("RecvQty", 0) AS DECIMAL(19,6)) AS "单位成本·委外"
          FROM :ord ORDER BY "ItemCode", "FcCode", "OrderType", "OrderEntry";
    ELSE
        SELECT "Grp" AS "物料组", MAX("GrpName") AS "物料组名称", "ItemCode" AS "产品", MAX("ItemName") AS "名称", MAX("iLevel") AS "层级",
               COUNT(*) AS "订单数", CAST(SUM("RecvQty") AS DECIMAL(19,6)) AS "完工数量",
               CAST(SUM("CostMat") AS DECIMAL(19,2)) AS "完工成本·材料", CAST(SUM("CostLab") AS DECIMAL(19,2)) AS "完工成本·人工",
               CAST(SUM("CostMfg") AS DECIMAL(19,2)) AS "完工成本·制造", CAST(SUM("CostSub") AS DECIMAL(19,2)) AS "完工成本·委外",
               CAST(SUM("CostAmt") AS DECIMAL(19,2)) AS "完工成本·合计",
               CAST(SUM("CostAmt") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·合计",
               CAST(SUM("CostMat") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·材料", CAST(SUM("CostLab") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·人工",
               CAST(SUM("CostMfg") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·制造", CAST(SUM("CostSub") / NULLIF(SUM("RecvQty"), 0) AS DECIMAL(19,6)) AS "单位成本·委外",
               CAST(SUM("CostMat") * 100 / NULLIF(SUM("CostAmt"), 0) AS DECIMAL(19,2)) AS "构成 %·材料", CAST(SUM("CostLab") * 100 / NULLIF(SUM("CostAmt"), 0) AS DECIMAL(19,2)) AS "构成 %·人工",
               CAST(SUM("CostMfg") * 100 / NULLIF(SUM("CostAmt"), 0) AS DECIMAL(19,2)) AS "构成 %·制造", CAST(SUM("CostSub") * 100 / NULLIF(SUM("CostAmt"), 0) AS DECIMAL(19,2)) AS "构成 %·委外"
          FROM :ord
         GROUP BY "Grp", "ItemCode"
         ORDER BY LPAD(IFNULL("Grp", ''), 10, '0'), "ItemCode";
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R05 材料耗用汇总：材料本期领用到哪里去了（生产 / 委外 / 返工 / 试打 / 其他出入库 / 销售 / 盘点 / 形态转换）。
-- 参数：FcFrom, FcTo, Item 材料, ItemGrp 材料物料组, Dest 去向（中文，逗号分隔）, Prod 产品（只对订单领用有效）,
--       STYPE 0 材料 × 去向 / 1 材料 × 订单或科目 / 2 产品 × 材料（只含订单领用）
-- 口径：MTC_CA_R_LINE 的出库成本（耗用 = −金额，退料冲减）。挂订单的行按订单类型分去向（参数 WW_WORTYPES 委外、REWORK_WORTYPES 返工、
--       TRIAL_WORTYPES 试打，其余生产），不含订单完工入库；不挂订单的按交易类型：O01/O06 销售、O10/I10 盘点、O04/I04 其他出入库（业务类型在
--       TRIAL_ISSUE_BUSITYPES 的算试打）、O05 形态转换；采购、转储、重估不算耗用。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_05_MATUSE" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN Dest NVARCHAR(200),
    IN Prod NVARCHAR(5000), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE fB NVARCHAR(10); DECLARE ww NVARCHAR(200); DECLARE rw NVARCHAR(200); DECLARE tr NVARCHAR(200); DECLARE tbi NVARCHAR(200);
    DECLARE nItem INT; DECLARE nGrp INT; DECLARE nDest INT; DECLARE nProd INT;
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    SELECT MAX("FcCode") INTO fB FROM :runs;
    ww := IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', :fB), ',50,');
    rw := IFNULL("MTC_CA_F_PARAM"('REWORK_WORTYPES', :fB), ',30,');
    tr := IFNULL("MTC_CA_F_PARAM"('TRIAL_WORTYPES', :fB), ',40,');
    tbi := IFNULL("MTC_CA_F_PARAM"('TRIAL_ISSUE_BUSITYPES', :fB), ',307,305,');
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);    SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp); SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lDest = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Dest);    SELECT COUNT(*) INTO nDest FROM :lDest;
    lProd = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Prod);    SELECT COUNT(*) INTO nProd FROM :lProd;
    lnx = SELECT U."FcCode", L."ItemCode", L."Qty", L."Amount", L."MatAmt", L."LabAmt", L."MfgAmt", L."SubAmt", L."OrderType", L."OrderEntry",
                SO."OrderNum", SO."WorType", SO."ItemCode" AS "Prod", D."AcctCode",
                CASE WHEN L."OrderEntry" IS NOT NULL THEN
                          CASE WHEN LOCATE(:ww, ',' || IFNULL(SO."WorType", '') || ',') > 0 THEN '委外'
                               WHEN LOCATE(:rw, ',' || IFNULL(SO."WorType", '') || ',') > 0 THEN '返工'
                               WHEN LOCATE(:tr, ',' || IFNULL(SO."WorType", '') || ',') > 0 THEN '试打' ELSE '生产' END
                     WHEN LOCATE(:tbi, ',' || IFNULL(D."BusiType", '') || ',') > 0 THEN '试打'
                     WHEN L."TransCode" IN ('O01', 'O06') THEN '销售'
                     WHEN L."TransCode" IN ('O10', 'I10') THEN '盘点'
                     WHEN L."TransCode" IN ('O04', 'I04') THEN '其他出入库'
                     WHEN L."TransCode" = 'O05' THEN '形态转换' END AS "Dest"
           FROM :runs U
           JOIN "MTC_CA_R_LINE" L ON L."RunId" = U."RunId"
           JOIN "MTC_CA_S_LINE" D ON D."RunId" = L."RunId" AND D."LineId" = L."LineId"
           LEFT JOIN "MTC_CA_S_ORDER" SO ON SO."RunId" = L."RunId" AND SO."OrderType" = L."OrderType" AND SO."OrderEntry" = L."OrderEntry"
           LEFT JOIN "OITM" M ON M."ItemCode" = L."ItemCode"
          WHERE NOT (L."OrderEntry" IS NOT NULL AND L."TransCode" IN ('I03', 'I07', 'I08', 'I09', 'I90'))
            AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE L."ItemCode" LIKE X."P"))
            AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"));
    lnx2 = SELECT * FROM :lnx
           WHERE "Dest" IS NOT NULL
             AND (:nDest = 0 OR EXISTS (SELECT 1 FROM :lDest X WHERE "Dest" = X."V"))
             AND (:nProd = 0 OR EXISTS (SELECT 1 FROM :lProd X WHERE "Prod" LIKE X."P"));
    IF :STYPE = '2' THEN
        SELECT L."Prod" AS "产品", MAX(P."ItemName") AS "产品名称", L."ItemCode" AS "材料", MAX(M."ItemName") AS "材料名称", COUNT(DISTINCT L."OrderType" || L."OrderEntry") AS "订单数",
               CAST(-SUM(L."Qty") AS DECIMAL(19,6)) AS "耗用·数量", CAST(-SUM(L."Amount") / NULLIF(-SUM(L."Qty"), 0) AS DECIMAL(19,6)) AS "耗用·单价",
               CAST(-SUM(L."Amount") AS DECIMAL(19,2)) AS "耗用·金额",
               CAST(-SUM(L."MatAmt") AS DECIMAL(19,2)) AS "构成·材料", CAST(-SUM(L."LabAmt") AS DECIMAL(19,2)) AS "构成·人工",
               CAST(-SUM(L."MfgAmt") AS DECIMAL(19,2)) AS "构成·制造", CAST(-SUM(L."SubAmt") AS DECIMAL(19,2)) AS "构成·委外"
          FROM :lnx2 L LEFT JOIN "OITM" M ON M."ItemCode" = L."ItemCode" LEFT JOIN "OITM" P ON P."ItemCode" = L."Prod"
         WHERE L."OrderEntry" IS NOT NULL
         GROUP BY L."Prod", L."ItemCode" ORDER BY L."Prod", L."ItemCode";
    ELSEIF :STYPE = '1' THEN
        SELECT L."ItemCode" AS "材料", MAX(M."ItemName") AS "材料名称", L."Dest" AS "去向", L."FcCode" AS "账期",
               L."OrderType" AS "订单单据", L."OrderNum" AS "订单号 Num", L."WorType" AS "订单类型", L."Prod" AS "产品", MAX(P."ItemName") AS "产品名称",
               CASE WHEN L."OrderEntry" IS NULL THEN L."AcctCode" END AS "科目", MAX(A."AcctName") AS "科目名称",
               CAST(-SUM(L."Qty") AS DECIMAL(19,6)) AS "耗用·数量", CAST(-SUM(L."Amount") / NULLIF(-SUM(L."Qty"), 0) AS DECIMAL(19,6)) AS "耗用·单价",
               CAST(-SUM(L."Amount") AS DECIMAL(19,2)) AS "耗用·金额"
          FROM :lnx2 L LEFT JOIN "OITM" M ON M."ItemCode" = L."ItemCode" LEFT JOIN "OITM" P ON P."ItemCode" = L."Prod"
          LEFT JOIN "OACT" A ON L."OrderEntry" IS NULL AND A."AcctCode" = L."AcctCode"
         GROUP BY L."ItemCode", L."Dest", L."FcCode", L."OrderType", L."OrderEntry", L."OrderNum", L."WorType", L."Prod",
                  CASE WHEN L."OrderEntry" IS NULL THEN L."AcctCode" END
         ORDER BY L."ItemCode", L."Dest", L."FcCode", L."OrderNum";
    ELSE
        SELECT TO_NVARCHAR(MAX(M."ItmsGrpCod")) AS "物料组", L."ItemCode" AS "材料", MAX(M."ItemName") AS "材料名称", L."Dest" AS "去向",
               CAST(-SUM(L."Qty") AS DECIMAL(19,6)) AS "耗用·数量", CAST(-SUM(L."Amount") / NULLIF(-SUM(L."Qty"), 0) AS DECIMAL(19,6)) AS "耗用·单价",
               CAST(-SUM(L."Amount") AS DECIMAL(19,2)) AS "耗用·金额",
               CAST(-SUM(L."MatAmt") AS DECIMAL(19,2)) AS "构成·材料", CAST(-SUM(L."LabAmt") AS DECIMAL(19,2)) AS "构成·人工",
               CAST(-SUM(L."MfgAmt") AS DECIMAL(19,2)) AS "构成·制造", CAST(-SUM(L."SubAmt") AS DECIMAL(19,2)) AS "构成·委外"
          FROM :lnx2 L LEFT JOIN "OITM" M ON M."ItemCode" = L."ItemCode"
         GROUP BY L."ItemCode", L."Dest"
         ORDER BY L."ItemCode", CASE L."Dest" WHEN '生产' THEN 1 WHEN '返工' THEN 2 WHEN '委外' THEN 3 WHEN '试打' THEN 4 WHEN '其他出入库' THEN 5
                                              WHEN '销售' THEN 6 WHEN '盘点' THEN 7 ELSE 8 END;
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R06 制造费用 / 人工分配表：费用池归集了多少、按工时分给了哪些产品和订单、没分到的原因。
-- 参数：FcFrom, FcTo, Pool 费用池, Elem 要素（MFG 制造 / LAB 人工，空 = 两项）, Prod 产品,
--       STYPE 0 池汇总 / 1 池 × 产品（含没分到的产品和原因）/ 2 池 × 订单 / 3 归集来源明细
-- 口径：MTC_CA_R_POOL（归集，按来源 JDT 凭证 / MRV 重估 / PROWW 委外重估 / SHARED 公摊材料 / CLOSEDIF 关单差异）、MTC_CA_R_ALLOC
--       （工时 = 单位工时 × 本期入库数，同池按工时比例分）；没分到的原因同执行台“工时分摊”页。
-- 勾稽：已分配合计 = R01 本级分摊人工 + 制造（V04）；未分配应为 0（Q12，未分摊报出不转下期）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_06_EXPALLOC" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Pool NVARCHAR(500), IN Elem NVARCHAR(3), IN Prod NVARCHAR(5000), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE nPool INT; DECLARE nProd INT;
    DECLARE el NVARCHAR(3) := CASE WHEN :Elem IN ('MFG', '制造') THEN 'MFG' WHEN :Elem IN ('LAB', '人工') THEN 'LAB' ELSE '' END;
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    lPool = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Pool); SELECT COUNT(*) INTO nPool FROM :lPool;
    lProd = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Prod); SELECT COUNT(*) INTO nProd FROM :lProd;
    IF :STYPE = '1' THEN
        ord = SELECT U."FcCode", O."RunId", O."ItemCode", O."OrderType", O."OrderEntry", O."WorType", O."RecvQty"
                FROM :runs U JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
               WHERE O."RecvQty" <> 0 AND (:nProd = 0 OR EXISTS (SELECT 1 FROM :lProd X WHERE O."ItemCode" LIKE X."P"));
        al = SELECT "RunId", "OrderType", "OrderEntry", "PoolCode", MAX("Hours") AS "H", MAX("Weight") AS "W",
                    SUM(CASE WHEN "Elem" = 'MFG' THEN "Amount" ELSE 0 END) AS "Mfg", SUM(CASE WHEN "Elem" = 'LAB' THEN "Amount" ELSE 0 END) AS "Lab"
               FROM "MTC_CA_R_ALLOC" WHERE "RunId" IN (SELECT "RunId" FROM :runs)
              GROUP BY "RunId", "OrderType", "OrderEntry", "PoolCode";
        pw = SELECT "RunId", "PoolCode", MAX("W") AS "TotW" FROM (SELECT "RunId", "PoolCode", "Elem", SUM("Weight") AS "W" FROM "MTC_CA_R_ALLOC"
                                                                   WHERE "RunId" IN (SELECT "RunId" FROM :runs) GROUP BY "RunId", "PoolCode", "Elem")
              GROUP BY "RunId", "PoolCode";
        d = SELECT O."FcCode", O."RunId", O."ItemCode", O."RecvQty", A."PoolCode", A."W", A."Mfg", A."Lab", IFNULL(A."H", H."Hours") AS "UH",
                   CASE WHEN A."PoolCode" IS NOT NULL THEN '已分摊' WHEN O."RecvQty" < 0 THEN '本期净入库为负，不分摊'
                        WHEN LOCATE(IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', O."FcCode"), ',50,'), ',' || IFNULL(O."WorType", '') || ',') > 0 THEN '委外工单，不分摊'
                        WHEN H."ItemCode" IS NULL THEN '没有单位工时' WHEN H."Hours" = 0 THEN '单位工时为 0'
                        ELSE '未分摊：不在费用池范围或池内没有金额' END AS "State"
              FROM :ord O
              LEFT JOIN :al A ON A."RunId" = O."RunId" AND A."OrderType" = O."OrderType" AND A."OrderEntry" = O."OrderEntry"
              LEFT JOIN "MTC_CA_S_HOURS" H ON H."RunId" = O."RunId" AND H."ItemCode" = O."ItemCode";
        SELECT D."FcCode" AS "账期", D."PoolCode" AS "费用池", MAX(C."PoolName") AS "费用池名称", D."ItemCode" AS "产品", MAX(M."ItemName") AS "产品名称",
               D."State" AS "分摊状态", CAST(MAX(D."UH") AS DECIMAL(19,6)) AS "单位工时", COUNT(*) AS "订单数", CAST(SUM(D."RecvQty") AS DECIMAL(19,6)) AS "本期入库数",
               CAST(SUM(D."W") AS DECIMAL(19,6)) AS "工时", CAST(SUM(D."W") * 100 / NULLIF(MAX(P."TotW"), 0) AS DECIMAL(19,4)) AS "占池工时 %",
               CAST(SUM(D."Mfg") AS DECIMAL(19,2)) AS "分摊·制造", CAST(SUM(D."Lab") AS DECIMAL(19,2)) AS "分摊·人工",
               CAST(SUM(D."Mfg") + SUM(D."Lab") AS DECIMAL(19,2)) AS "分摊·合计",
               CAST((SUM(D."Mfg") + SUM(D."Lab")) / NULLIF(SUM(D."RecvQty"), 0) AS DECIMAL(19,6)) AS "每件费用",
               CAST((SUM(D."Mfg") + SUM(D."Lab")) / NULLIF(SUM(D."W"), 0) AS DECIMAL(19,6)) AS "每工时费用"
          FROM :d D
          LEFT JOIN :pw P ON P."RunId" = D."RunId" AND P."PoolCode" = D."PoolCode"
          LEFT JOIN "MTC_CA_C_POOL" C ON C."PoolCode" = D."PoolCode"
          LEFT JOIN "OITM" M ON M."ItemCode" = D."ItemCode"
         WHERE :nPool = 0 OR D."PoolCode" IS NULL OR EXISTS (SELECT 1 FROM :lPool X WHERE D."PoolCode" = X."V")
         GROUP BY D."FcCode", D."PoolCode", D."ItemCode", D."State"
         ORDER BY D."FcCode", CASE WHEN D."PoolCode" IS NULL THEN 1 ELSE 0 END, D."PoolCode", D."ItemCode";
    ELSEIF :STYPE = '2' THEN
        SELECT U."FcCode" AS "账期", A."PoolCode" AS "费用池", C."PoolName" AS "费用池名称", CASE A."Elem" WHEN 'MFG' THEN '制造' ELSE '人工' END AS "要素",
               A."OrderType" AS "订单单据", S."OrderNum" AS "订单号 Num", A."OrderEntry" AS "订单 Entry", S."WorType" AS "订单类型",
               S."ItemCode" AS "产品", M."ItemName" AS "产品名称",
               CAST(A."Hours" AS DECIMAL(19,6)) AS "单位工时", CAST(A."RecvQty" AS DECIMAL(19,6)) AS "本期入库数", CAST(A."Weight" AS DECIMAL(19,6)) AS "工时",
               CAST(A."Ratio" * 100 AS DECIMAL(19,4)) AS "占池比例 %", CAST(A."Amount" AS DECIMAL(19,2)) AS "分摊金额"
          FROM :runs U
          JOIN "MTC_CA_R_ALLOC" A ON A."RunId" = U."RunId"
          LEFT JOIN "MTC_CA_S_ORDER" S ON S."RunId" = A."RunId" AND S."OrderType" = A."OrderType" AND S."OrderEntry" = A."OrderEntry"
          LEFT JOIN "MTC_CA_C_POOL" C ON C."PoolCode" = A."PoolCode"
          LEFT JOIN "OITM" M ON M."ItemCode" = S."ItemCode"
         WHERE (:el = '' OR A."Elem" = :el)
           AND (:nPool = 0 OR EXISTS (SELECT 1 FROM :lPool X WHERE A."PoolCode" = X."V"))
           AND (:nProd = 0 OR EXISTS (SELECT 1 FROM :lProd X WHERE S."ItemCode" LIKE X."P"))
         ORDER BY U."FcCode", A."PoolCode", A."Elem", S."ItemCode", S."OrderNum";
    ELSEIF :STYPE = '3' THEN
        src = SELECT U."FcCode", IFNULL(PS."PoolCode", DP."PoolCode") AS "PoolCode", E."Elem", E."Src", E."SrcTrans", E."AcctCode", E."OcrCode", E."DocDate",
                     E."SrcKey", E."SrcObj", CASE WHEN E."Src" = 'JDT' THEN TO_NVARCHAR(H."BaseRef") WHEN E."Src" IN ('MRV', 'PROWW') THEN TO_NVARCHAR(MR."DocNum") END AS "DocNum",
                     CASE WHEN E."Src" = 'JDT' THEN TO_NVARCHAR(H."Number") END AS "JdtNum",
                     CAST(NULL AS NVARCHAR(50)) AS "ItemCode", CAST(NULL AS DECIMAL(19,6)) AS "Qty", E."Amount", E."Note"
                FROM :runs U
                JOIN "MTC_CA_S_EXP" E ON E."RunId" = U."RunId"
                LEFT JOIN "MTC_CA_C_POOL_SRC" PS ON PS."OcrCode" = E."OcrCode" AND E."FcCode" BETWEEN PS."FromFc" AND PS."ToFc"
                LEFT JOIN "OJDT" H ON E."Src" = 'JDT' AND H."TransId" = CASE WHEN E."SrcKey" LIKE_REGEXPR '^[0-9]+-' THEN TO_INTEGER(SUBSTR_BEFORE(E."SrcKey", '-')) END
                LEFT JOIN "@MTC_OMRV" MR ON E."Src" IN ('MRV', 'PROWW') AND MR."DocEntry" = E."SrcDoc"
                CROSS JOIN (SELECT MAX("PoolCode") AS "PoolCode" FROM "MTC_CA_C_POOL" WHERE "IsDefault" = 'Y') DP
              UNION ALL
              SELECT U."FcCode", L."PoolCode", 'MFG', 'SHARED', L."TransCode", D."AcctCode", D."OcrCode", D."DocDate",
                     D."ObjType" || '-' || IFNULL(D."DocNum", TO_NVARCHAR(D."DocEntry")) || '-' || IFNULL(TO_NVARCHAR(D."LineNum"), ''), D."ObjType", D."DocNum",
                     CAST(NULL AS NVARCHAR(20)), L."ItemCode", -L."Qty", -L."Amount", L."PriceSrc"
                FROM :runs U
                JOIN "MTC_CA_R_LINE" L ON L."RunId" = U."RunId" AND L."IsShared" = 'Y'
                JOIN "MTC_CA_S_LINE" D ON D."RunId" = L."RunId" AND D."LineId" = L."LineId"
              UNION ALL
              SELECT U."FcCode", "MTC_CA_F_PARAM"('CLOSE_DIF_POOL', U."FcCode"), 'MFG', 'CLOSEDIF', CAST(NULL AS NVARCHAR(20)), CAST(NULL AS NVARCHAR(15)),
                     CAST(NULL AS NVARCHAR(20)), CAST(NULL AS DATE), O."OrderType" || '-' || TO_NVARCHAR(O."OrderEntry"), O."OrderType", SO."OrderNum",
                     CAST(NULL AS NVARCHAR(20)), O."ItemCode", CAST(NULL AS DECIMAL(19,6)), O."CloseDifAmt", '订单本期关单差异'
                FROM :runs U
                JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId" AND O."CloseDifAmt" <> 0
                LEFT JOIN "MTC_CA_S_ORDER" SO ON SO."RunId" = O."RunId" AND SO."OrderType" = O."OrderType" AND SO."OrderEntry" = O."OrderEntry";
        SELECT S."FcCode" AS "账期", S."PoolCode" AS "费用池", C."PoolName" AS "费用池名称", CASE S."Elem" WHEN 'MFG' THEN '制造' ELSE '人工' END AS "要素",
               CASE S."Src" WHEN 'JDT' THEN '凭证' WHEN 'MRV' THEN '库存重估' WHEN 'PROWW' THEN '委外重估' WHEN 'SHARED' THEN '公摊材料' WHEN 'CLOSEDIF' THEN '关单差异' ELSE S."Src" END AS "来源",
               S."SrcTrans" AS "凭证代码 / 交易类型", S."AcctCode" AS "科目", A."AcctName" AS "科目名称", S."OcrCode" AS "成本中心", S."DocDate" AS "日期",
               S."SrcObj" AS "单据类型", S."DocNum" AS "单号 Num", S."JdtNum" AS "凭证编号 Number", S."SrcKey" AS "来源键",
               S."ItemCode" AS "物料", CAST(S."Qty" AS DECIMAL(19,6)) AS "数量", CAST(S."Amount" AS DECIMAL(19,2)) AS "金额", S."Note" AS "备注"
          FROM :src S
          LEFT JOIN "MTC_CA_C_POOL" C ON C."PoolCode" = S."PoolCode"
          LEFT JOIN "OACT" A ON A."AcctCode" = S."AcctCode"
         WHERE (:el = '' OR S."Elem" = :el)
           AND (:nPool = 0 OR EXISTS (SELECT 1 FROM :lPool X WHERE S."PoolCode" = X."V"))
         ORDER BY S."FcCode", S."PoolCode", S."Elem", S."Src", S."DocDate", S."SrcKey";
    ELSE
        poolT = SELECT U."FcCode", P."RunId", P."PoolCode", P."Elem",
                      SUM(CASE WHEN P."Src" = 'JDT' THEN P."Amount" ELSE 0 END) AS "SJdt", SUM(CASE WHEN P."Src" = 'MRV' THEN P."Amount" ELSE 0 END) AS "SMrv",
                      SUM(CASE WHEN P."Src" = 'PROWW' THEN P."Amount" ELSE 0 END) AS "SWw", SUM(CASE WHEN P."Src" = 'SHARED' THEN P."Amount" ELSE 0 END) AS "SShr",
                      SUM(CASE WHEN P."Src" = 'CLOSEDIF' THEN P."Amount" ELSE 0 END) AS "SCls", SUM(P."Amount") AS "Amt"
                 FROM :runs U JOIN "MTC_CA_R_POOL" P ON P."RunId" = U."RunId"
                GROUP BY U."FcCode", P."RunId", P."PoolCode", P."Elem";
        alP = SELECT "RunId", "PoolCode", "Elem", SUM("Amount") AS "Amt", COUNT(*) AS "Cnt", SUM("Weight") AS "W"
               FROM "MTC_CA_R_ALLOC" WHERE "RunId" IN (SELECT "RunId" FROM :runs) GROUP BY "RunId", "PoolCode", "Elem";
        SELECT P."FcCode" AS "账期", P."PoolCode" AS "费用池", C."PoolName" AS "费用池名称", CASE P."Elem" WHEN 'MFG' THEN '制造' ELSE '人工' END AS "要素",
               CAST(P."SJdt" AS DECIMAL(19,2)) AS "归集·凭证", CAST(P."SMrv" AS DECIMAL(19,2)) AS "归集·库存重估", CAST(P."SWw" AS DECIMAL(19,2)) AS "归集·委外重估",
               CAST(P."SShr" AS DECIMAL(19,2)) AS "归集·公摊材料", CAST(P."SCls" AS DECIMAL(19,2)) AS "归集·关单差异", CAST(P."Amt" AS DECIMAL(19,2)) AS "归集·合计",
               CAST(IFNULL(A."Amt", 0) AS DECIMAL(19,2)) AS "已分配", CAST(P."Amt" - IFNULL(A."Amt", 0) AS DECIMAL(19,2)) AS "未分配",
               IFNULL(A."Cnt", 0) AS "分配订单数", CAST(A."W" AS DECIMAL(19,6)) AS "工时合计",
               CAST(IFNULL(A."Amt", 0) / NULLIF(A."W", 0) AS DECIMAL(19,6)) AS "每工时费用"
          FROM :poolT P
          LEFT JOIN :alP A ON A."RunId" = P."RunId" AND A."PoolCode" = P."PoolCode" AND A."Elem" = P."Elem"
          LEFT JOIN "MTC_CA_C_POOL" C ON C."PoolCode" = P."PoolCode"
         WHERE (:el = '' OR P."Elem" = :el)
           AND (:nPool = 0 OR EXISTS (SELECT 1 FROM :lPool X WHERE P."PoolCode" = X."V"))
         ORDER BY P."FcCode", P."PoolCode", P."Elem";
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R07 委外加工成本表：委外订单发出材料、加工费、完工成本、在产品，按供应商汇总。
-- 参数：FcFrom, FcTo, Vendor 供应商（订单上的业务伙伴）, OrderNum 订单号 Num, Prod 产品, STYPE 0 按供应商 / 1 按订单 / 2 订单 × 材料
-- 口径：订单类型在参数 WW_WORTYPES 的订单（R_ORDER / R_ORDER_MAT）；'#SUBFEE' 行 = 委外加工费（按暂估金额，S_SUBFEE）；
--       不分摊人工和制造费用。期末在产品·材料 = 140801 业务端，期末在产品·加工费 = 140802 业务端（R09 WW_MAT / WW_FEE）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_07_SUBCON" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Vendor NVARCHAR(5000), IN OrderNum NVARCHAR(5000), IN Prod NVARCHAR(5000), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE nVen INT; DECLARE nOrd INT; DECLARE nProd INT; DECLARE fA NVARCHAR(10); DECLARE fB NVARCHAR(10);
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    SELECT MIN("FcCode"), MAX("FcCode") INTO fA, fB FROM :runs;
    lVen  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Vendor);   SELECT COUNT(*) INTO nVen FROM :lVen;
    lOrd  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:OrderNum); SELECT COUNT(*) INTO nOrd FROM :lOrd;
    lProd = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Prod);     SELECT COUNT(*) INTO nProd FROM :lProd;
    ord = SELECT U."FcCode", O."RunId", O."OrderType", O."OrderEntry", S."OrderNum", O."WorType", O."ItemCode", S."CardCode",
                 O."PlannedQty", O."RecvQty", O."CostAmt", O."CostSub", O."CloseDifAmt", O."WipAmt", O."ClosedInFc", S."StatusAtEnd"
            FROM :runs U
            JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
            LEFT JOIN "MTC_CA_S_ORDER" S ON S."RunId" = O."RunId" AND S."OrderType" = O."OrderType" AND S."OrderEntry" = O."OrderEntry"
           WHERE LOCATE(IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', U."FcCode"), ',50,'), ',' || IFNULL(O."WorType", '') || ',') > 0
             AND (:nVen = 0 OR EXISTS (SELECT 1 FROM :lVen X WHERE S."CardCode" LIKE X."P"))
             AND (:nOrd = 0 OR EXISTS (SELECT 1 FROM :lOrd X WHERE S."OrderNum" LIKE X."P"))
             AND (:nProd = 0 OR EXISTS (SELECT 1 FROM :lProd X WHERE O."ItemCode" LIKE X."P"));
    IF :STYPE = '2' THEN
        SELECT O."FcCode" AS "账期", O."CardCode" AS "供应商", O."OrderType" AS "订单单据", O."OrderNum" AS "订单号 Num", O."ItemCode" AS "产品",
               M."ItemCode" AS "材料", CASE WHEN M."ItemCode" = '#SUBFEE' THEN '委外加工费' ELSE I."ItemName" END AS "材料名称",
               CAST(M."OpenIssMat" + M."OpenIssLab" + M."OpenIssMfg" + M."OpenIssSub" - M."OpenCarMat" - M."OpenCarLab" - M."OpenCarMfg" - M."OpenCarSub" AS DECIMAL(19,2)) AS "期初在产品",
               CAST(M."IssQty" AS DECIMAL(19,6)) AS "本期发出·数量", CAST(M."IssMat" + M."IssLab" + M."IssMfg" + M."IssSub" AS DECIMAL(19,2)) AS "本期发出·金额",
               CAST(M."Ratio" AS DECIMAL(19,6)) AS "结转比例",
               CAST(M."CarMat" + M."CarLab" + M."CarMfg" + M."CarSub" AS DECIMAL(19,2)) AS "完工转出",
               CAST(M."ClsMat" + M."ClsLab" + M."ClsMfg" + M."ClsSub" AS DECIMAL(19,2)) AS "关单差异",
               CAST(M."WipMat" + M."WipLab" + M."WipMfg" + M."WipSub" AS DECIMAL(19,2)) AS "期末在产品"
          FROM :ord O
          JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = O."RunId" AND M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
          LEFT JOIN "OITM" I ON I."ItemCode" = M."ItemCode"
         ORDER BY O."FcCode", O."CardCode", O."OrderNum", CASE WHEN M."ItemCode" = '#SUBFEE' THEN 1 ELSE 0 END, M."ItemCode";
    ELSE
        d = SELECT O."FcCode", O."CardCode", O."OrderType", O."OrderEntry", O."OrderNum", O."ItemCode", O."StatusAtEnd", O."ClosedInFc",
                   O."PlannedQty", O."RecvQty", O."CostAmt", O."CloseDifAmt",
                   SUM(CASE WHEN M."ItemCode" <> '#SUBFEE' THEN M."OpenIssMat" + M."OpenIssLab" + M."OpenIssMfg" + M."OpenIssSub" - M."OpenCarMat" - M."OpenCarLab" - M."OpenCarMfg" - M."OpenCarSub" ELSE 0 END) AS "BMat",
                   SUM(CASE WHEN M."ItemCode" = '#SUBFEE' THEN M."OpenIssSub" - M."OpenCarSub" ELSE 0 END) AS "BFee",
                   SUM(CASE WHEN M."ItemCode" <> '#SUBFEE' THEN M."IssMat" + M."IssLab" + M."IssMfg" + M."IssSub" ELSE 0 END) AS "IMat",
                   SUM(CASE WHEN M."ItemCode" = '#SUBFEE' THEN M."IssSub" ELSE 0 END) AS "IFee",
                   SUM(CASE WHEN M."ItemCode" <> '#SUBFEE' THEN M."CarMat" + M."CarLab" + M."CarMfg" + M."CarSub" ELSE 0 END) AS "CMat",
                   SUM(CASE WHEN M."ItemCode" = '#SUBFEE' THEN M."CarSub" ELSE 0 END) AS "CFee",
                   SUM(CASE WHEN M."ItemCode" <> '#SUBFEE' THEN M."WipMat" + M."WipLab" + M."WipMfg" + M."WipSub" ELSE 0 END) AS "WMat",
                   SUM(CASE WHEN M."ItemCode" = '#SUBFEE' THEN M."WipSub" ELSE 0 END) AS "WFee"
              FROM :ord O
              LEFT JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = O."RunId" AND M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
             GROUP BY O."FcCode", O."CardCode", O."OrderType", O."OrderEntry", O."OrderNum", O."ItemCode", O."StatusAtEnd", O."ClosedInFc",
                      O."PlannedQty", O."RecvQty", O."CostAmt", O."CloseDifAmt";
        IF :STYPE = '1' THEN
            SELECT D."FcCode" AS "账期", D."CardCode" AS "供应商", C."CardName" AS "供应商名称", D."OrderType" AS "订单单据", D."OrderNum" AS "订单号 Num",
                   D."OrderEntry" AS "订单 Entry", D."ItemCode" AS "产品", M."ItemName" AS "产品名称", D."StatusAtEnd" AS "期末状态", D."ClosedInFc" AS "按关单处理",
                   CAST(D."PlannedQty" AS DECIMAL(19,6)) AS "计划数", CAST(D."RecvQty" AS DECIMAL(19,6)) AS "本期完工",
                   CAST(D."BMat" AS DECIMAL(19,2)) AS "期初在产品·材料", CAST(D."BFee" AS DECIMAL(19,2)) AS "期初在产品·加工费",
                   CAST(D."IMat" AS DECIMAL(19,2)) AS "本期·发出材料", CAST(D."IFee" AS DECIMAL(19,2)) AS "本期·加工费",
                   CAST(D."CMat" AS DECIMAL(19,2)) AS "完工转出·材料", CAST(D."CFee" AS DECIMAL(19,2)) AS "完工转出·加工费",
                   CAST(D."CostAmt" AS DECIMAL(19,2)) AS "完工转出·合计", CAST(D."CostAmt" / NULLIF(D."RecvQty", 0) AS DECIMAL(19,6)) AS "完工转出·单位成本",
                   CAST(D."CloseDifAmt" AS DECIMAL(19,2)) AS "关单差异",
                   CAST(D."WMat" AS DECIMAL(19,2)) AS "期末在产品·材料", CAST(D."WFee" AS DECIMAL(19,2)) AS "期末在产品·加工费"
              FROM :d D LEFT JOIN "OCRD" C ON C."CardCode" = D."CardCode" LEFT JOIN "OITM" M ON M."ItemCode" = D."ItemCode"
             ORDER BY D."FcCode", D."CardCode", D."OrderNum";
        ELSE
            SELECT D."CardCode" AS "供应商", MAX(C."CardName") AS "供应商名称", COUNT(DISTINCT D."OrderType" || D."OrderEntry") AS "订单数",
                   CAST(SUM(D."RecvQty") AS DECIMAL(19,6)) AS "本期完工数量",
                   CAST(SUM(CASE WHEN D."FcCode" = :fA THEN D."BMat" ELSE 0 END) AS DECIMAL(19,2)) AS "期初在产品·材料",
                   CAST(SUM(CASE WHEN D."FcCode" = :fA THEN D."BFee" ELSE 0 END) AS DECIMAL(19,2)) AS "期初在产品·加工费",
                   CAST(SUM(D."IMat") AS DECIMAL(19,2)) AS "本期·发出材料", CAST(SUM(D."IFee") AS DECIMAL(19,2)) AS "本期·加工费",
                   CAST(SUM(D."CMat") AS DECIMAL(19,2)) AS "完工转出·材料", CAST(SUM(D."CFee") AS DECIMAL(19,2)) AS "完工转出·加工费",
                   CAST(SUM(D."CostAmt") AS DECIMAL(19,2)) AS "完工转出·合计", CAST(SUM(D."CloseDifAmt") AS DECIMAL(19,2)) AS "关单差异",
                   CAST(SUM(CASE WHEN D."FcCode" = :fB THEN D."WMat" ELSE 0 END) AS DECIMAL(19,2)) AS "期末在产品·材料",
                   CAST(SUM(CASE WHEN D."FcCode" = :fB THEN D."WFee" ELSE 0 END) AS DECIMAL(19,2)) AS "期末在产品·加工费"
              FROM :d D LEFT JOIN "OCRD" C ON C."CardCode" = D."CardCode"
             GROUP BY D."CardCode" ORDER BY D."CardCode";
        END IF;
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R08 销售成本计算表：期初发出商品 + 本期发货 − 独立退货 − 本期消耗（开票、贷项、退货、尾差）= 期末发出商品；销售成本 = DN03。
-- 参数：FcFrom, FcTo, Item 物料, ItemGrp 物料组, Cust 客户, CustType 客户类型（@MTC_SALORDTYPE.U_CustType，如 国内客户）,
--       STYPE 0 按产品 / 1 按客户 / 2 按交货（退货）行
-- 口径：期初 / 期末 = R_GOODS_OUT_BEG / R_GOODS_OUT 的未开票成本；发货 = 交货行（15）的出库成本，独立退货 = 不基于交货的销售退货行（16）的入库成本；
--       消耗 = R_GOODS_MOVE（INV 开票、RIN 贷项、RET 基于交货的退货、ADJ 全部消耗完时的尾差）；销售成本（DN03）= 非样品的 INV + RIN + ADJ，
--       样品单列（DN02 / DN04）。“勾稽差额”应为 0。客户和客户类型取交货 / 退货单表头。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_08_SALECOST" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN Cust NVARCHAR(5000),
    IN CustType NVARCHAR(200), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE fA NVARCHAR(10); DECLARE fB NVARCHAR(10); DECLARE nItem INT; DECLARE nGrp INT; DECLARE nCust INT; DECLARE nCt INT;
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    SELECT MIN("FcCode"), MAX("FcCode") INTO fA, fB FROM :runs;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);     SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp);  SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lCust = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Cust);     SELECT COUNT(*) INTO nCust FROM :lCust;
    lCt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:CustType); SELECT COUNT(*) INTO nCt FROM :lCt;
    -- 一行 = 一条交货 / 退货行在某一列上的金额
    f = SELECT G."ObjType", G."DocEntry", G."LineNum", G."ItemCode", CAST(G."CostAmt" AS DECIMAL(19,6)) AS "Beg", CAST(0 AS DECIMAL(19,6)) AS "Iss", CAST(0 AS DECIMAL(19,6)) AS "Ret0", CAST(0 AS DECIMAL(19,6)) AS "Inv",
               CAST(0 AS DECIMAL(19,6)) AS "Rin", CAST(0 AS DECIMAL(19,6)) AS "Ret", CAST(0 AS DECIMAL(19,6)) AS "Adj", CAST(0 AS DECIMAL(19,6)) AS "Smp", CAST(0 AS DECIMAL(19,6)) AS "EndA"
          FROM :runs U JOIN "MTC_CA_R_GOODS_OUT_BEG" G ON G."RunId" = U."RunId" WHERE U."FcCode" = :fA
        UNION ALL
        SELECT G."ObjType", G."DocEntry", G."LineNum", G."ItemCode", 0, 0, 0, 0, 0, 0, 0, 0, G."CostAmt"
          FROM :runs U JOIN "MTC_CA_R_GOODS_OUT" G ON G."RunId" = U."RunId" WHERE U."FcCode" = :fB
        UNION ALL
        SELECT D."ObjType", D."DocEntry", D."LineNum", L."ItemCode", 0,
               CASE WHEN D."ObjType" = '15' THEN -L."Amount" ELSE 0 END, CASE WHEN D."ObjType" = '16' THEN L."Amount" ELSE 0 END, 0, 0, 0, 0, 0, 0
          FROM :runs U
          JOIN "MTC_CA_S_LINE" D ON D."RunId" = U."RunId" AND (D."ObjType" = '15' OR (D."ObjType" = '16' AND IFNULL(D."BaseType", '') <> '15'))
          JOIN "MTC_CA_R_LINE" L ON L."RunId" = D."RunId" AND L."LineId" = D."LineId"
        UNION ALL
        SELECT M."SrcObj", M."SrcEntry", M."SrcLine", NULL, 0, 0, 0,
               CASE WHEN M."K" = 'INV' THEN M."Amount" ELSE 0 END, CASE WHEN M."K" = 'RIN' THEN M."Amount" ELSE 0 END,
               CASE WHEN M."K" = 'RET' THEN M."Amount" ELSE 0 END, CASE WHEN M."K" = 'ADJ' THEN M."Amount" ELSE 0 END,
               CASE WHEN M."IsSample" = 'Y' AND M."K" <> 'RET' THEN M."Amount" ELSE 0 END, 0
          FROM :runs U JOIN "MTC_CA_R_GOODS_MOVE" M ON M."RunId" = U."RunId";
    hd = SELECT '15' AS "ObjType", D."DocEntry", D."LineNum", D."ItemCode", H."DocNum", TO_DATE(H."DocDate") AS "DocDate", H."CardCode", H."U_SalOrdType"
           FROM "ODLN" H JOIN "DLN1" D ON D."DocEntry" = H."DocEntry"
          WHERE H."DocEntry" IN (SELECT "DocEntry" FROM :f WHERE "ObjType" = '15')
         UNION ALL
         SELECT '16', D."DocEntry", D."LineNum", D."ItemCode", H."DocNum", TO_DATE(H."DocDate"), H."CardCode", H."U_SalOrdType"
           FROM "ORDN" H JOIN "RDN1" D ON D."DocEntry" = H."DocEntry"
          WHERE H."DocEntry" IN (SELECT "DocEntry" FROM :f WHERE "ObjType" = '16');
    b = SELECT F."ObjType", F."DocEntry", F."LineNum", COALESCE(H."ItemCode", MAX(F."ItemCode")) AS "ItemCode", H."DocNum", H."DocDate", H."CardCode",
               T."CustType", SUM(F."Beg") AS "Beg", SUM(F."Iss") AS "Iss", SUM(F."Ret0") AS "Ret0", SUM(F."Inv") AS "Inv", SUM(F."Rin") AS "Rin",
               SUM(F."Ret") AS "Ret", SUM(F."Adj") AS "Adj", SUM(F."Smp") AS "Smp", SUM(F."EndA") AS "EndA"
          FROM :f F
          LEFT JOIN :hd H ON H."ObjType" = F."ObjType" AND H."DocEntry" = F."DocEntry" AND H."LineNum" = F."LineNum"
          LEFT JOIN (SELECT "Name", MAX("U_CustType") AS "CustType" FROM "@MTC_SALORDTYPE" GROUP BY "Name") T ON T."Name" = H."U_SalOrdType"
         GROUP BY F."ObjType", F."DocEntry", F."LineNum", H."ItemCode", H."DocNum", H."DocDate", H."CardCode", T."CustType";
    b2 = SELECT B.*, M."ItemName", TO_NVARCHAR(M."ItmsGrpCod") AS "Grp", C."CardName"
           FROM :b B LEFT JOIN "OITM" M ON M."ItemCode" = B."ItemCode" LEFT JOIN "OCRD" C ON C."CardCode" = B."CardCode"
          WHERE (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE B."ItemCode" LIKE X."P"))
            AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"))
            AND (:nCust = 0 OR EXISTS (SELECT 1 FROM :lCust X WHERE B."CardCode" LIKE X."P"))
            AND (:nCt = 0 OR EXISTS (SELECT 1 FROM :lCt X WHERE B."CustType" = X."V"));
    -- 分组键先在子查询里算好（HANA 不认 SELECT / GROUP BY 中带参数的 CASE 是同一表达式）
    o = SELECT "K",
               MAX(CASE :STYPE WHEN '1' THEN "CardName" ELSE "ItemName" END) AS "N",
               MAX(CASE WHEN :STYPE = '2' THEN "ObjType" END) AS "ObjType", MAX(CASE WHEN :STYPE = '2' THEN "DocNum" END) AS "DocNum",
               MAX(CASE WHEN :STYPE = '2' THEN "LineNum" END) AS "LineNum", MAX(CASE WHEN :STYPE = '2' THEN "DocDate" END) AS "DocDate",
               MAX(CASE WHEN :STYPE = '2' THEN "CardCode" END) AS "CardCode", MAX(CASE WHEN :STYPE IN ('1', '2') THEN "CustType" END) AS "CustType",
               MAX(CASE WHEN :STYPE = '2' THEN "ItemCode" END) AS "ItemCode",
               SUM("Beg") AS "Beg", SUM("Iss") AS "Iss", SUM("Ret0") AS "Ret0", SUM("Inv") AS "Inv", SUM("Rin") AS "Rin", SUM("Ret") AS "Ret",
               SUM("Adj") AS "Adj", SUM("Smp") AS "Smp", SUM("EndA") AS "EndA"
          FROM (SELECT B.*, CASE :STYPE WHEN '1' THEN B."CardCode" WHEN '2' THEN B."ObjType" || '-' || TO_NVARCHAR(B."DocEntry") || '-' || TO_NVARCHAR(B."LineNum") ELSE B."ItemCode" END AS "K"
                  FROM :b2 B)
         GROUP BY "K";
    SELECT "K" AS "代码", "N" AS "名称", "ObjType" AS "单据类型", "DocNum" AS "单号 Num", "LineNum" AS "行号", "DocDate" AS "单据日期",
           "CardCode" AS "客户", "CustType" AS "客户类型", "ItemCode" AS "物料",
           CAST("Beg" AS DECIMAL(19,2)) AS "期初发出商品", CAST("Iss" AS DECIMAL(19,2)) AS "本期·发货", CAST("Ret0" AS DECIMAL(19,2)) AS "本期·独立退货",
           CAST("Inv" AS DECIMAL(19,2)) AS "本期消耗·开票", CAST("Rin" AS DECIMAL(19,2)) AS "本期消耗·贷项", CAST("Ret" AS DECIMAL(19,2)) AS "本期消耗·基于交货退货",
           CAST("Adj" AS DECIMAL(19,2)) AS "本期消耗·尾差",
           CAST("Inv" + "Rin" + "Adj" - "Smp" AS DECIMAL(19,2)) AS "销售成本（DN03）", CAST("Smp" AS DECIMAL(19,2)) AS "样品转出",
           CAST("EndA" AS DECIMAL(19,2)) AS "期末发出商品",
           CAST("Beg" + "Iss" - "Ret0" - "Inv" - "Rin" - "Ret" - "Adj" - "EndA" AS DECIMAL(19,2)) AS "勾稽差额"
      FROM :o ORDER BY "K";
END
@@
-- ---------------------------------------------------------------------
-- R09 存货与生产成本对账：业务端（新框架结果）与总账按对账项、科目逐项比较，期初 / 本期 / 期末分开列示。
-- 参数：Fc 账期, Acct 科目（开头匹配）, OnlyDiff 只看有差异 Y/N
-- 口径：MTC_CA_F_RECON（同执行台“财务对账”、POST-06/09/10/11/13）。财务本期 = 本期分录 + 底稿中尚未过账的凭证；手工调整单独一列。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_09_RECON" (IN Fc NVARCHAR(10), IN Acct NVARCHAR(500), IN OnlyDiff NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE rid BIGINT; DECLARE nAcct INT;
    SELECT MAX("RunId") INTO rid FROM "MTC_CA_F_RPT_RUN"(:Fc, :Fc);
    lAcct = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Acct); SELECT COUNT(*) INTO nAcct FROM :lAcct;
    IF :rid IS NULL THEN
        SELECT '这个账期没有成功的正式计算（看 R00）' AS "说明" FROM DUMMY;
        RETURN;
    END IF;
    r = SELECT * FROM "MTC_CA_F_RECON"(:rid);
    SELECT CASE R."Area" WHEN 'STOCK' THEN '存货' WHEN 'WIP_PROD' THEN '生产在产品' WHEN 'WW_MAT' THEN '委外材料' WHEN 'WW_FEE' THEN '委外加工费'
                         WHEN 'GOODS' THEN '发出商品' WHEN 'AP' THEN '应付暂估' ELSE R."Area" END AS "对账项",
           R."AcctCode" AS "科目", A."AcctName" AS "科目名称", R."KeyCode" AS "对象",
           R."BegBiz" AS "期初·业务", R."BegFin" AS "期初·财务", R."BegDiff" AS "期初·差额",
           R."CurBiz" AS "本期·业务", R."CurFin" AS "本期·财务", R."CurDiff" AS "本期·差额",
           R."BizAmt" AS "期末·业务", R."EndFin" AS "期末·财务", R."Diff" AS "期末·差额",
           R."OtherAmt" AS "手工调整·金额", CAST(R."Diff" + R."OtherAmt" AS DECIMAL(19,2)) AS "手工调整·总账差额（含手工）",
           CASE WHEN ABS(R."Diff" - R."BegDiff") <= 0.01 THEN 'Y' ELSE 'N' END AS "手工调整·扣除后 = 期初差额",
           CAST(R."DraftAmt" - R."DupAmt" AS DECIMAL(19,2)) AS "未过账底稿·金额", R."PendCodes" AS "未过账底稿·凭证代码"
      FROM :r R LEFT JOIN "OACT" A ON A."AcctCode" = R."AcctCode"
     WHERE (:nAcct = 0 OR EXISTS (SELECT 1 FROM :lAcct X WHERE R."AcctCode" LIKE X."P"))
       AND (IFNULL(:OnlyDiff, 'N') <> 'Y' OR ABS(R."CurDiff") > 0.01 OR ABS(R."Diff") > 0.01)
     ORDER BY CASE R."Area" WHEN 'STOCK' THEN 1 WHEN 'WIP_PROD' THEN 2 WHEN 'WW_MAT' THEN 3 WHEN 'WW_FEE' THEN 4 WHEN 'GOODS' THEN 5 ELSE 6 END,
              R."AcctCode", R."KeyCode";
END
@@
-- ---------------------------------------------------------------------
-- R10 成本凭证清单及来源：本期成本模块生成的凭证（每种凭证代码一张）、分录、每笔分录的业务来源。
-- 参数：Fc 账期, TransCode 凭证代码, Acct 科目（开头匹配）, STYPE 0 按凭证代码（含 B1 凭单批号和状态）/ 1 分录 / 2 来源明细
-- 口径：MTC_CA_R_JDT / R_JDT_SRC（凭证底稿）、MTC_CA_JV（已生成的 B1 日记账凭单）。来源明细金额正 = 借、负 = 贷。
-- 勾稽：来源明细合计 = 分录合计（V06）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_10_JV" (IN Fc NVARCHAR(10), IN TransCode NVARCHAR(500), IN Acct NVARCHAR(500), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE rid BIGINT; DECLARE fc NVARCHAR(10); DECLARE nTc INT; DECLARE nAcct INT;
    SELECT MAX("RunId"), MAX("FcCode") INTO rid, fc FROM "MTC_CA_F_RPT_RUN"(:Fc, :Fc);
    lTc   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:TransCode); SELECT COUNT(*) INTO nTc FROM :lTc;
    lAcct = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Acct);      SELECT COUNT(*) INTO nAcct FROM :lAcct;
    IF :rid IS NULL THEN
        SELECT '这个账期没有成功的正式计算（看 R00）' AS "说明" FROM DUMMY;
        RETURN;
    END IF;
    IF :STYPE = '2' THEN
        SELECT S."TransCode" AS "凭证代码", S."AcctCode" AS "科目", A."AcctName" AS "科目名称", S."OcrCode" AS "成本中心", S."VendorCode" AS "供应商",
               CASE S."SrcType" WHEN 'LINE' THEN '单据行' WHEN 'ORDER' THEN '订单' WHEN 'DOC' THEN 'B1 单据行' WHEN 'GL' THEN '总账分录' WHEN 'OMRV' THEN '重估单'
                                WHEN 'ITEM' THEN '物料尾差' ELSE S."SrcType" END AS "来源类型",
               S."SrcKey" AS "来源键",
               CAST(CASE WHEN S."Amount" > 0 THEN S."Amount" ELSE 0 END AS DECIMAL(19,2)) AS "借方",
               CAST(CASE WHEN S."Amount" < 0 THEN -S."Amount" ELSE 0 END AS DECIMAL(19,2)) AS "贷方",
               COALESCE(D."DocDate", CAST(NULL AS DATE)) AS "单据日期",
               COALESCE(D."ObjType", O."OrderType") AS "单据类型", COALESCE(D."DocNum", O."OrderNum") AS "单号 Num", D."LineNum" AS "行号",
               COALESCE(L."ItemCode", O."ItemCode") AS "物料", L."TransCode" AS "交易类型", CAST(L."Qty" AS DECIMAL(19,6)) AS "数量",
               LO."OrderNum" AS "订单号 Num", S."Note" AS "备注"
          FROM "MTC_CA_R_JDT_SRC" S
          LEFT JOIN "MTC_CA_R_LINE" L ON S."SrcType" = 'LINE' AND L."RunId" = S."RunId"
                                     AND L."LineId" = CASE WHEN S."SrcKey" LIKE_REGEXPR '^[0-9]+$' THEN TO_BIGINT(S."SrcKey") END
          LEFT JOIN "MTC_CA_S_LINE" D ON D."RunId" = L."RunId" AND D."LineId" = L."LineId"
          LEFT JOIN "MTC_CA_S_ORDER" LO ON LO."RunId" = L."RunId" AND LO."OrderType" = L."OrderType" AND LO."OrderEntry" = L."OrderEntry"
          LEFT JOIN "MTC_CA_S_ORDER" O ON S."SrcType" = 'ORDER' AND O."RunId" = S."RunId" AND O."OrderType" || '-' || TO_NVARCHAR(O."OrderEntry") = S."SrcKey"
          LEFT JOIN "OACT" A ON A."AcctCode" = S."AcctCode"
         WHERE S."RunId" = :rid
           AND (:nTc = 0 OR EXISTS (SELECT 1 FROM :lTc X WHERE S."TransCode" = X."V"))
           AND (:nAcct = 0 OR EXISTS (SELECT 1 FROM :lAcct X WHERE S."AcctCode" LIKE X."P"))
         ORDER BY S."TransCode", S."AcctCode", S."OcrCode", S."SrcId";
    ELSEIF :STYPE = '1' THEN
        SELECT J."TransCode" AS "凭证代码", J."TransName" AS "凭证名称", J."LineNo" AS "行号", J."RefDate" AS "过账日期", J."AcctCode" AS "科目", A."AcctName" AS "科目名称",
               J."OcrCode" AS "成本中心", J."Project" AS "项目", J."VendorCode" AS "供应商", J."Debit" AS "借方", J."Credit" AS "贷方"
          FROM "MTC_CA_R_JDT" J LEFT JOIN "OACT" A ON A."AcctCode" = J."AcctCode"
         WHERE J."RunId" = :rid
           AND (:nTc = 0 OR EXISTS (SELECT 1 FROM :lTc X WHERE J."TransCode" = X."V"))
           AND (:nAcct = 0 OR EXISTS (SELECT 1 FROM :lAcct X WHERE J."AcctCode" LIKE X."P"))
         ORDER BY J."TransCode", J."LineNo";
    ELSE
        SELECT J."TransCode" AS "凭证代码", MAX(IFNULL(T."TrnsCodDsc", J."TransName")) AS "凭证名称", COUNT(*) AS "分录行数",
               SUM(J."Debit") AS "借方", SUM(J."Credit") AS "贷方", CAST(SUM(J."Debit") - SUM(J."Credit") AS DECIMAL(19,2)) AS "借贷差",
               MAX(V."BatchNum") AS "凭单批号", IFNULL(MAX(V."B1State"), '未生成凭单') AS "B1 状态",
               MAX(V."CreateUser") AS "生成人", MAX(V."CreateTime") AS "生成时间"
          FROM "MTC_CA_R_JDT" J
          LEFT JOIN "OTRC" T ON T."TrnsCode" = J."TransCode"
          LEFT JOIN (SELECT G."TransCode", G."BatchNum", G."CreateUser", G."CreateTime",
                            CASE WHEN EXISTS (SELECT 1 FROM "OBTF" B WHERE B."BatchNum" = G."BatchNum" AND B."BtfStatus" = 'O') THEN '待过账'
                                 WHEN EXISTS (SELECT 1 FROM "OJDT" H WHERE H."BatchNum" = G."BatchNum") THEN '已过账' ELSE '已在 B1 删除' END AS "B1State"
                       FROM (SELECT "TransCode", MAX("BatchNum") AS "BatchNum", MAX("CreateUser") AS "CreateUser", MAX("CreateTime") AS "CreateTime"
                               FROM "MTC_CA_JV" WHERE "FcCode" = :fc AND "RunId" = :rid AND "Status" = 'CREATED' AND "BatchNum" IS NOT NULL
                              GROUP BY "TransCode") G) V ON V."TransCode" = J."TransCode"
         WHERE J."RunId" = :rid
           AND (:nTc = 0 OR EXISTS (SELECT 1 FROM :lTc X WHERE J."TransCode" = X."V"))
           AND (:nAcct = 0 OR EXISTS (SELECT 1 FROM :lAcct X WHERE J."AcctCode" LIKE X."P"))
         GROUP BY J."TransCode" ORDER BY J."TransCode";
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R11 成本异常清单：本期需要人看一眼的物料、订单、费用池和校验项。
-- 参数：Fc 账期, Cat 类别（FLAG 物料标记 / STOCK 期末异常 / PRICE 单价变动 / ORDER 订单 / POOL 费用池 / CHECK 校验）,
--       PricePct 单价变动阈值 %（默认 20）, AmtMin 金额阈值（关单差异绝对值超过它才列，默认 0）
-- 口径：R_ITEM.Flags（负库存 / 兜底价 / 无价 / 尾差无处挤）；期末数量为负、数量为 0 金额不为 0、金额为负；单价（四项合计）与上期最近一次
--       成功正式运行相比变动超过阈值；订单本期有完工但单位成本 ≤ 0、期末在产品为负、关单差异；费用池未分配完；计算后校验不通过或警告（含人工确认）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_11_EXCEPT" (IN Fc NVARCHAR(10), IN Cat NVARCHAR(100), IN PricePct NVARCHAR(20), IN AmtMin NVARCHAR(30))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE rid BIGINT; DECLARE pfc NVARCHAR(10); DECLARE prid BIGINT; DECLARE nCat INT;
    DECLARE th DECIMAL(19,6) := TO_DECIMAL(IFNULL(NULLIF(TRIM(:PricePct), ''), '20'), 19, 6);
    DECLARE am DECIMAL(19,6) := TO_DECIMAL(IFNULL(NULLIF(TRIM(:AmtMin), ''), '0'), 19, 6);
    SELECT MAX("RunId"), MAX("PrevFc") INTO rid, pfc FROM "MTC_CA_F_RPT_RUN"(:Fc, :Fc);
    SELECT MAX("RunId") INTO prid FROM "MTC_CA_F_RPT_RUN"(:pfc, :pfc);
    lCat = SELECT UPPER("V") AS "V" FROM "MTC_CA_F_RPT_LIST"(:Cat); SELECT COUNT(*) INTO nCat FROM :lCat;
    IF :rid IS NULL THEN
        SELECT '这个账期没有成功的正式计算（看 R00）' AS "说明" FROM DUMMY;
        RETURN;
    END IF;
    x = SELECT CAST('FLAG' AS NVARCHAR(10)) AS "C", 1 AS "S", CAST(R."ItemCode" AS NVARCHAR(200)) AS "K", CAST(R."Flags" AS NVARCHAR(2000)) AS "Msg", R."EndAmount" AS "V1", CAST(NULL AS DECIMAL(19,6)) AS "V0", R."EndAmount" AS "Amt"
          FROM "MTC_CA_R_ITEM" R WHERE R."RunId" = :rid AND IFNULL(R."Flags", '') <> ''
        UNION ALL
        SELECT 'STOCK', 2, R."ItemCode",
               CASE WHEN R."EndQty" < 0 THEN '期末数量为负' WHEN R."EndQty" = 0 THEN '期末数量为 0、金额不为 0' ELSE '期末金额为负' END,
               R."EndQty", NULL, R."EndAmount"
          FROM "MTC_CA_R_ITEM" R
         WHERE R."RunId" = :rid AND (R."EndQty" < 0 OR (R."EndQty" = 0 AND ABS(R."EndAmount") > 0.005) OR (R."EndQty" > 0 AND R."EndAmount" < 0))
        UNION ALL
        SELECT 'PRICE', 3, C."ItemCode", '单价比上期变动超过 ' || TO_NVARCHAR(:th) || '%',
               C."PMat" + C."PMfg" + C."PLab" + C."PSub", P."PMat" + P."PMfg" + P."PLab" + P."PSub",
               (C."PMat" + C."PMfg" + C."PLab" + C."PSub" - P."PMat" - P."PMfg" - P."PLab" - P."PSub") * C."EndQty"
          FROM "MTC_CA_R_ITEM" C JOIN "MTC_CA_R_ITEM" P ON P."RunId" = :prid AND P."ItemCode" = C."ItemCode"
         WHERE C."RunId" = :rid AND P."PMat" + P."PMfg" + P."PLab" + P."PSub" > 0 AND C."PMat" + C."PMfg" + C."PLab" + C."PSub" > 0
           AND (C."InQty" <> 0 OR C."OutQty" <> 0)
           AND ABS(C."PMat" + C."PMfg" + C."PLab" + C."PSub" - P."PMat" - P."PMfg" - P."PLab" - P."PSub") * 100
               > :th * (P."PMat" + P."PMfg" + P."PLab" + P."PSub")
        UNION ALL
        SELECT 'ORDER', 4, O."OrderType" || '-' || IFNULL(S."OrderNum", TO_NVARCHAR(O."OrderEntry")),
               CASE WHEN O."RecvQty" > 0 AND IFNULL(O."UnitCost", 0) <= 0 THEN '本期有完工，单位成本 ≤ 0'
                    WHEN O."WipAmt" < -0.005 THEN '期末在产品为负' ELSE '本期关单差异' END,
               CASE WHEN O."RecvQty" > 0 AND IFNULL(O."UnitCost", 0) <= 0 THEN O."UnitCost" WHEN O."WipAmt" < -0.005 THEN O."WipAmt" ELSE O."CloseDifAmt" END,
               NULL, CASE WHEN O."WipAmt" < -0.005 THEN O."WipAmt" WHEN O."RecvQty" > 0 AND IFNULL(O."UnitCost", 0) <= 0 THEN O."CostAmt" ELSE O."CloseDifAmt" END
          FROM "MTC_CA_R_ORDER" O
          LEFT JOIN "MTC_CA_S_ORDER" S ON S."RunId" = O."RunId" AND S."OrderType" = O."OrderType" AND S."OrderEntry" = O."OrderEntry"
         WHERE O."RunId" = :rid
           AND ((O."RecvQty" > 0 AND IFNULL(O."UnitCost", 0) <= 0) OR O."WipAmt" < -0.005 OR (O."CloseDifAmt" <> 0 AND ABS(O."CloseDifAmt") > :am))
        UNION ALL
        SELECT 'POOL', 5, P."PoolCode" || ' ' || P."Elem", '费用池未分配完', P."Amt", A."Amt", P."Amt" - IFNULL(A."Amt", 0)
          FROM (SELECT "PoolCode", "Elem", SUM("Amount") AS "Amt" FROM "MTC_CA_R_POOL" WHERE "RunId" = :rid GROUP BY "PoolCode", "Elem") P
          LEFT JOIN (SELECT "PoolCode", "Elem", SUM("Amount") AS "Amt" FROM "MTC_CA_R_ALLOC" WHERE "RunId" = :rid GROUP BY "PoolCode", "Elem") A
                 ON A."PoolCode" = P."PoolCode" AND A."Elem" = P."Elem"
         WHERE ABS(P."Amt" - IFNULL(A."Amt", 0)) > 0.005
        UNION ALL
        SELECT 'CHECK', 6, K."CheckId", IFNULL(C."Title", '') || '：' || IFNULL(K."Msg", '')
                 || CASE WHEN A."UserCode" IS NOT NULL THEN '（已确认：' || A."UserCode" || '，' || A."Reason" || '）' ELSE '' END,
               K."IssueCnt", NULL, NULL
          FROM "MTC_CA_R_CHECK" K
          LEFT JOIN "MTC_CA_C_CHECK" C ON C."CheckId" = K."CheckId"
          LEFT JOIN "MTC_CA_CHECK_ACK" A ON A."RunId" = K."RunId" AND A."CheckId" = K."CheckId"
         WHERE K."RunId" = :rid AND K."Result" IN ('FAIL', 'WARN');
    SELECT CASE X."C" WHEN 'FLAG' THEN '物料标记' WHEN 'STOCK' THEN '期末异常' WHEN 'PRICE' THEN '单价变动' WHEN 'ORDER' THEN '订单'
                      WHEN 'POOL' THEN '费用池' ELSE '校验' END AS "类别",
           X."C" AS "类别代码", X."K" AS "对象", COALESCE(M."ItemName", PL."PoolName") AS "名称", X."Msg" AS "说明",
           CAST(X."V1" AS DECIMAL(19,6)) AS "本期值", CAST(X."V0" AS DECIMAL(19,6)) AS "上期值",
           CAST(CASE WHEN X."C" = 'PRICE' THEN (X."V1" - X."V0") * 100 / NULLIF(X."V0", 0) END AS DECIMAL(19,2)) AS "变动 %",
           CAST(X."Amt" AS DECIMAL(19,2)) AS "影响金额"
      FROM :x X
      LEFT JOIN "OITM" M ON X."C" IN ('FLAG', 'STOCK', 'PRICE') AND M."ItemCode" = X."K"
      LEFT JOIN "MTC_CA_C_POOL" PL ON X."C" = 'POOL' AND PL."PoolCode" = SUBSTR_BEFORE(X."K", ' ')
     WHERE :nCat = 0 OR EXISTS (SELECT 1 FROM :lCat L WHERE L."V" = X."C")
     ORDER BY X."S", ABS(IFNULL(X."Amt", 0)) DESC, X."K";
END
@@
-- ---------------------------------------------------------------------
-- R17 应付暂估（已收货未开票，含退货）：截至期末未清的收货行（扣已开票、扣基于收货的退货）和不基于收货的退货（为负）。
-- 参数：Fc 账期, Vendor 供应商, AccrType 暂估类型（MAT 材料 / SUBFEE 委外加工费，也认中文）, Item 物料, ItemGrp 物料组, DocNum 收货单号 Num,
--       AgeDays 账龄 ≥ 天数, STYPE 0 按供应商（含账龄分段）/ 1 供应商 × 物料 / 2 单据行 / 3 本期变动 / 4 与总账 220202 按供应商核对
-- 口径：MTC_CA_R_AP_ACCR（截至期末未清）、MTC_CA_S_AP_MOVE（每笔变动对 220202 贷方余额的影响），与 PUR1–PUR5 凭证取自同一次运行；
--       暂估单价：U_InitPrice ≠ 0 → 指定单价；U_IsPrice = Y → 已确认价；否则 LineTotal ÷ 数量。账龄 = 期末日 − 收货日期。
-- 勾稽：未清合计 = R09 应付暂估业务端 = reports/MTC_RPT_FI5005_V2 截至期末合计；STYPE 3 期初 + 变动 = 期末（V07、V08）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_17_APACCR" (
    IN Fc NVARCHAR(10), IN Vendor NVARCHAR(5000), IN AccrType NVARCHAR(20), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000),
    IN DocNum NVARCHAR(5000), IN AgeDays NVARCHAR(10), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE rid BIGINT; DECLARE d0 DATE; DECLARE d1 DATE; DECLARE nVen INT; DECLARE nItem INT; DECLARE nGrp INT; DECLARE nDoc INT;
    DECLARE aty NVARCHAR(10) := CASE WHEN :AccrType IN ('MAT', '材料') THEN 'MAT' WHEN :AccrType IN ('SUBFEE', '委外加工费', '加工费') THEN 'SUBFEE' ELSE '' END;
    DECLARE age INT := TO_INTEGER(IFNULL(NULLIF(TRIM(:AgeDays), ''), '0'));
    SELECT MAX("RunId"), MAX("D0"), MAX("D1") INTO rid, d0, d1 FROM "MTC_CA_F_RPT_RUN"(:Fc, :Fc);
    lVen  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Vendor);  SELECT COUNT(*) INTO nVen FROM :lVen;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);    SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp); SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lDoc  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:DocNum);  SELECT COUNT(*) INTO nDoc FROM :lDoc;
    IF :rid IS NULL THEN
        SELECT '这个账期没有成功的正式计算（看 R00）' AS "说明" FROM DUMMY;
        RETURN;
    END IF;
    IF :STYPE = '3' THEN
        mv3 = SELECT M.* FROM "MTC_CA_S_AP_MOVE" M LEFT JOIN "OITM" I ON I."ItemCode" = M."ItemCode"
              WHERE M."RunId" = :rid AND M."DocDate" <= :d1
                AND (:aty = '' OR M."AccrType" = :aty)
                AND (:nVen = 0 OR EXISTS (SELECT 1 FROM :lVen X WHERE M."CardCode" LIKE X."P"))
                AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE M."ItemCode" LIKE X."P"))
                AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(I."ItmsGrpCod") = X."V"));
        o3 = SELECT IFNULL(M."CardCode", '') AS "CardCode",
                   SUM(CASE WHEN M."DocDate" < :d0 THEN M."AccrAmt" ELSE 0 END) AS "Beg",
                   SUM(CASE WHEN M."DocDate" >= :d0 AND M."IsCancel" = 'N' AND M."MoveType" = 'ACCR' AND M."BaseObj" = '20' THEN M."AccrAmt" ELSE 0 END) AS "Rcv",
                   SUM(CASE WHEN M."DocDate" >= :d0 AND M."IsCancel" = 'N' AND M."MoveType" = 'ACCR' AND M."BaseObj" = '21' THEN M."AccrAmt" ELSE 0 END) AS "Ret0",
                   SUM(CASE WHEN M."DocDate" >= :d0 AND M."IsCancel" = 'N' AND M."MoveType" = 'RET' THEN M."AccrAmt" ELSE 0 END) AS "Ret",
                   SUM(CASE WHEN M."DocDate" >= :d0 AND M."IsCancel" = 'N' AND M."MoveType" = 'INV' THEN M."AccrAmt" ELSE 0 END) AS "Inv",
                   SUM(CASE WHEN M."DocDate" >= :d0 AND M."IsCancel" = 'Y' THEN M."AccrAmt" ELSE 0 END) AS "Cnl",
                   SUM(M."AccrAmt") AS "EndA"
              FROM :mv3 M GROUP BY IFNULL(M."CardCode", '');
        acc3 = SELECT IFNULL(A."CardCode", '') AS "CardCode", SUM(A."OpenAmt") AS "Amt"
                FROM "MTC_CA_R_AP_ACCR" A LEFT JOIN "OITM" I ON I."ItemCode" = A."ItemCode"
               WHERE A."RunId" = :rid AND (:aty = '' OR A."AccrType" = :aty)
                 AND (:nVen = 0 OR EXISTS (SELECT 1 FROM :lVen X WHERE A."CardCode" LIKE X."P"))
                 AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE A."ItemCode" LIKE X."P"))
                 AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(I."ItmsGrpCod") = X."V"))
               GROUP BY IFNULL(A."CardCode", '');
        SELECT O."CardCode" AS "供应商", C."CardName" AS "供应商名称",
               CAST(O."Beg" AS DECIMAL(19,2)) AS "期初未清", CAST(O."Rcv" AS DECIMAL(19,2)) AS "本期·收货暂估", CAST(O."Ret0" AS DECIMAL(19,2)) AS "本期·独立退货",
               CAST(O."Ret" AS DECIMAL(19,2)) AS "本期·基于收货退货", CAST(O."Inv" AS DECIMAL(19,2)) AS "本期·开票冲回", CAST(O."Cnl" AS DECIMAL(19,2)) AS "本期·取消单",
               CAST(O."EndA" AS DECIMAL(19,2)) AS "期末未清", CAST(IFNULL(A."Amt", 0) AS DECIMAL(19,2)) AS "期末未清（逐行）",
               CAST(O."EndA" - IFNULL(A."Amt", 0) AS DECIMAL(19,2)) AS "勾稽差额"
          FROM :o3 O LEFT JOIN :acc3 A ON A."CardCode" = O."CardCode" LEFT JOIN "OCRD" C ON C."CardCode" = O."CardCode"
         WHERE O."Beg" <> 0 OR O."EndA" <> 0 OR O."Rcv" <> 0 OR O."Ret0" <> 0 OR O."Ret" <> 0 OR O."Inv" <> 0 OR O."Cnl" <> 0 OR IFNULL(A."Amt", 0) <> 0
         ORDER BY O."CardCode";
        RETURN;
    END IF;
    IF :STYPE = '4' THEN
        acc4 = SELECT IFNULL("CardCode", '') AS "CardCode", SUM("OpenAmt") AS "Amt" FROM "MTC_CA_R_AP_ACCR" WHERE "RunId" = :rid GROUP BY IFNULL("CardCode", '');
        rc4 = SELECT IFNULL("KeyCode", '') AS "CardCode", SUM("BizAmt") AS "Biz", SUM("EndFin") AS "Fin", SUM("Diff") AS "Diff", SUM("CurDiff") AS "CurDiff"
               FROM "MTC_CA_F_RECON"(:rid) WHERE "Area" = 'AP' GROUP BY IFNULL("KeyCode", '');
        k4 = SELECT "CardCode" FROM :acc4 UNION SELECT "CardCode" FROM :rc4;
        SELECT K."CardCode" AS "供应商", C."CardName" AS "供应商名称",
               CAST(IFNULL(A."Amt", 0) AS DECIMAL(19,2)) AS "报表未清合计", CAST(IFNULL(R."Biz", 0) AS DECIMAL(19,2)) AS "对账·业务端",
               CAST(IFNULL(R."Fin", 0) AS DECIMAL(19,2)) AS "对账·总账 220202", CAST(IFNULL(R."Diff", 0) AS DECIMAL(19,2)) AS "对账·期末差额",
               CAST(IFNULL(R."CurDiff", 0) AS DECIMAL(19,2)) AS "对账·本期差额",
               CAST(IFNULL(A."Amt", 0) - IFNULL(R."Biz", 0) AS DECIMAL(19,2)) AS "报表 − 业务端"
          FROM :k4 K LEFT JOIN :acc4 A ON A."CardCode" = K."CardCode" LEFT JOIN :rc4 R ON R."CardCode" = K."CardCode"
          LEFT JOIN "OCRD" C ON C."CardCode" = K."CardCode"
         WHERE (:nVen = 0 OR EXISTS (SELECT 1 FROM :lVen X WHERE K."CardCode" LIKE X."P"))
         ORDER BY ABS(IFNULL(R."Diff", 0)) DESC, K."CardCode";
        RETURN;
    END IF;
    lnx = SELECT A."ObjType", A."DocEntry", A."LineNum", COALESCE(P."DocNum", R."DocNum") AS "DocNum", A."DocDate", A."CardCode", A."AccrType", A."ItemCode",
                COALESCE(PL."Dscription", RL."Dscription") AS "Dscription", TO_NVARCHAR(I."ItmsGrpCod") AS "Grp",
                A."DocQty", A."InvQty", A."RetQty", A."OpenQty", A."UnitPrice", A."OpenAmt",
                CASE WHEN IFNULL(COALESCE(PL."U_InitPrice", RL."U_InitPrice"), 0) <> 0 THEN '指定单价 U_InitPrice'
                     WHEN COALESCE(PL."U_IsPrice", RL."U_IsPrice") = 'Y' THEN '已确认价' ELSE '行金额 ÷ 数量' END AS "PriceSrc",
                DAYS_BETWEEN(A."DocDate", :d1) AS "Age"
           FROM "MTC_CA_R_AP_ACCR" A
           LEFT JOIN "OPDN" P ON A."ObjType" = '20' AND P."DocEntry" = A."DocEntry"
           LEFT JOIN "PDN1" PL ON A."ObjType" = '20' AND PL."DocEntry" = A."DocEntry" AND PL."LineNum" = A."LineNum"
           LEFT JOIN "ORPD" R ON A."ObjType" = '21' AND R."DocEntry" = A."DocEntry"
           LEFT JOIN "RPD1" RL ON A."ObjType" = '21' AND RL."DocEntry" = A."DocEntry" AND RL."LineNum" = A."LineNum"
           LEFT JOIN "OITM" I ON I."ItemCode" = A."ItemCode"
          WHERE A."RunId" = :rid AND (:aty = '' OR A."AccrType" = :aty)
            AND (:nVen = 0 OR EXISTS (SELECT 1 FROM :lVen X WHERE A."CardCode" LIKE X."P"))
            AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE A."ItemCode" LIKE X."P"))
            AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(I."ItmsGrpCod") = X."V"))
            AND (:nDoc = 0 OR EXISTS (SELECT 1 FROM :lDoc X WHERE TO_NVARCHAR(COALESCE(P."DocNum", R."DocNum")) LIKE X."P"))
            AND DAYS_BETWEEN(A."DocDate", :d1) >= :age;
    IF :STYPE = '2' THEN
        SELECT L."CardCode" AS "供应商", C."CardName" AS "供应商名称", CASE L."ObjType" WHEN '20' THEN '收货' ELSE '退货' END AS "单据",
               L."DocNum" AS "单号 Num", L."DocEntry" AS "单号 Entry", L."LineNum" AS "行号", L."DocDate" AS "收货日期", L."Age" AS "账龄天数",
               CASE L."AccrType" WHEN 'SUBFEE' THEN '委外加工费' ELSE '材料' END AS "暂估类型", L."ItemCode" AS "物料", L."Dscription" AS "物料描述",
               CAST(L."DocQty" AS DECIMAL(19,6)) AS "收货数量", CAST(L."InvQty" AS DECIMAL(19,6)) AS "已开票数量", CAST(L."RetQty" AS DECIMAL(19,6)) AS "已退货数量",
               CAST(L."OpenQty" AS DECIMAL(19,6)) AS "未清数量", CAST(L."UnitPrice" AS DECIMAL(19,6)) AS "暂估单价", L."PriceSrc" AS "暂估单价来源",
               CAST(L."OpenAmt" AS DECIMAL(19,2)) AS "未清金额"
          FROM :lnx L LEFT JOIN "OCRD" C ON C."CardCode" = L."CardCode"
         ORDER BY L."CardCode", L."DocDate", L."DocEntry", L."LineNum";
    ELSEIF :STYPE = '1' THEN
        SELECT L."CardCode" AS "供应商", MAX(C."CardName") AS "供应商名称", L."ItemCode" AS "物料", MAX(L."Dscription") AS "物料描述",
               COUNT(*) AS "行数", CAST(SUM(L."OpenQty") AS DECIMAL(19,6)) AS "未清数量", CAST(SUM(L."OpenAmt") AS DECIMAL(19,2)) AS "未清金额",
               MIN(L."DocDate") AS "最早收货日期", MAX(L."Age") AS "最长账龄天数"
          FROM :lnx L LEFT JOIN "OCRD" C ON C."CardCode" = L."CardCode"
         GROUP BY L."CardCode", L."ItemCode" ORDER BY L."CardCode", L."ItemCode";
    ELSE
        SELECT L."CardCode" AS "供应商", MAX(C."CardName") AS "供应商名称", COUNT(*) AS "行数",
               CAST(SUM(L."OpenAmt") AS DECIMAL(19,2)) AS "未清金额",
               CAST(SUM(CASE WHEN L."Age" <= 30 THEN L."OpenAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "账龄·30 天内",
               CAST(SUM(CASE WHEN L."Age" BETWEEN 31 AND 60 THEN L."OpenAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "账龄·31–60 天",
               CAST(SUM(CASE WHEN L."Age" BETWEEN 61 AND 90 THEN L."OpenAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "账龄·61–90 天",
               CAST(SUM(CASE WHEN L."Age" BETWEEN 91 AND 180 THEN L."OpenAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "账龄·91–180 天",
               CAST(SUM(CASE WHEN L."Age" > 180 THEN L."OpenAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "账龄·180 天以上",
               CAST(SUM(CASE WHEN L."AccrType" = 'SUBFEE' THEN L."OpenAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "其中委外加工费",
               MIN(L."DocDate") AS "最早收货日期"
          FROM :lnx L LEFT JOIN "OCRD" C ON C."CardCode" = L."CardCode"
         GROUP BY L."CardCode" ORDER BY L."CardCode";
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R18 发出商品明细（已发货未开票，含退货）：截至期末未开票的交货行（扣已开票、扣基于交货的退货）和不基于交货的退货（为负）。
-- 参数：Fc 账期, Cust 客户, CustType 客户类型（U_CustType）, SalType 销售订单类型（@MTC_SALORDTYPE.Name）, Item 物料, ItemGrp 物料组,
--       DocNum 交货单号 Num, Sample 样品（空 全部 / Y 只看样品 / N 排除样品）, AgeDays 账龄 ≥ 天数,
--       STYPE 0 按客户（含账龄分段）/ 1 客户 × 物料 / 2 单据行 / 3 本期变动 / 4 与 AR03 / AR04 计提核对
-- 口径：MTC_CA_R_GOODS_OUT（期末）/ R_GOODS_OUT_BEG（期初）/ R_GOODS_MOVE（本期消耗）、R_DNCOST（单位成本）、R_JDT（AR03 国内 / AR04 国外，
--       参数 CUST_DOM / CUST_EXP）；未开票销售金额 = 行金额 ÷ 数量 × 未清数量。账龄 = 期末日 − 交货日期。
-- 勾稽：未清成本合计 = AR03 + AR04 计提（STYPE 4）；STYPE 3 期初 + 变动 = 期末（V09、V10）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_18_GOODSOUT" (
    IN Fc NVARCHAR(10), IN Cust NVARCHAR(5000), IN CustType NVARCHAR(200), IN SalType NVARCHAR(500), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000),
    IN DocNum NVARCHAR(5000), IN Sample NVARCHAR(1), IN AgeDays NVARCHAR(10), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE rid BIGINT; DECLARE fc NVARCHAR(10); DECLARE d1 DATE; DECLARE nCust INT; DECLARE nCt INT; DECLARE nSt INT; DECLARE nItem INT; DECLARE nGrp INT; DECLARE nDoc INT;
    DECLARE goods NVARCHAR(15); DECLARE cDom NVARCHAR(50); DECLARE cExp NVARCHAR(50);
    DECLARE age INT := TO_INTEGER(IFNULL(NULLIF(TRIM(:AgeDays), ''), '0'));
    SELECT MAX("RunId"), MAX("FcCode"), MAX("D1") INTO rid, fc, d1 FROM "MTC_CA_F_RPT_RUN"(:Fc, :Fc);
    lCust = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Cust);     SELECT COUNT(*) INTO nCust FROM :lCust;
    lCt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:CustType); SELECT COUNT(*) INTO nCt FROM :lCt;
    lSt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:SalType);  SELECT COUNT(*) INTO nSt FROM :lSt;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);     SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp);  SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lDoc  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:DocNum);   SELECT COUNT(*) INTO nDoc FROM :lDoc;
    IF :rid IS NULL THEN
        SELECT '这个账期没有成功的正式计算（看 R00）' AS "说明" FROM DUMMY;
        RETURN;
    END IF;
    goods := "MTC_CA_F_ACCT"('GOODS_ISSUED', :fc);
    cDom := IFNULL("MTC_CA_F_PARAM"('CUST_DOM', :fc), '国内客户');
    cExp := IFNULL("MTC_CA_F_PARAM"('CUST_EXP', :fc), '国外客户');
    -- 交货 / 退货行的表头信息（期初、期末、本期消耗和本期新增的行都可能用到）
    hd = SELECT '15' AS "ObjType", D."DocEntry", D."LineNum", D."ItemCode", H."DocNum", H."CardCode", H."U_SalOrdType", D."LineTotal", D."Quantity", D."Dscription"
           FROM "ODLN" H JOIN "DLN1" D ON D."DocEntry" = H."DocEntry"
          WHERE H."DocEntry" IN (SELECT "DocEntry" FROM "MTC_CA_R_GOODS_OUT" WHERE "RunId" = :rid AND "ObjType" = '15'
                                 UNION SELECT "DocEntry" FROM "MTC_CA_R_GOODS_OUT_BEG" WHERE "RunId" = :rid AND "ObjType" = '15'
                                 UNION SELECT "SrcEntry" FROM "MTC_CA_R_GOODS_MOVE" WHERE "RunId" = :rid AND "SrcObj" = '15'
                                 UNION SELECT "DocEntry" FROM "MTC_CA_S_LINE" WHERE "RunId" = :rid AND "ObjType" = '15')
         UNION ALL
         SELECT '16', D."DocEntry", D."LineNum", D."ItemCode", H."DocNum", H."CardCode", H."U_SalOrdType", -D."LineTotal", -D."Quantity", D."Dscription"
           FROM "ORDN" H JOIN "RDN1" D ON D."DocEntry" = H."DocEntry"
          WHERE H."DocEntry" IN (SELECT "DocEntry" FROM "MTC_CA_R_GOODS_OUT" WHERE "RunId" = :rid AND "ObjType" = '16'
                                 UNION SELECT "DocEntry" FROM "MTC_CA_R_GOODS_OUT_BEG" WHERE "RunId" = :rid AND "ObjType" = '16'
                                 UNION SELECT "SrcEntry" FROM "MTC_CA_R_GOODS_MOVE" WHERE "RunId" = :rid AND "SrcObj" = '16'
                                 UNION SELECT "DocEntry" FROM "MTC_CA_S_LINE" WHERE "RunId" = :rid AND "ObjType" = '16');
    hd2 = SELECT H.*, T."CustType", CASE WHEN LOCATE(IFNULL("MTC_CA_F_PARAM"('SAMPLE_SALTYPES', :fc), ',样品销售,'), ',' || IFNULL(T."BusiType", '') || ',') > 0 THEN 'Y' ELSE 'N' END AS "IsSample"
            FROM :hd H
            LEFT JOIN (SELECT "Name", MAX("U_CustType") AS "CustType", MAX("U_BusiType") AS "BusiType" FROM "@MTC_SALORDTYPE" GROUP BY "Name") T ON T."Name" = H."U_SalOrdType"
           WHERE (:nCust = 0 OR EXISTS (SELECT 1 FROM :lCust X WHERE H."CardCode" LIKE X."P"))
             AND (:nCt = 0 OR EXISTS (SELECT 1 FROM :lCt X WHERE T."CustType" = X."V"))
             AND (:nSt = 0 OR EXISTS (SELECT 1 FROM :lSt X WHERE H."U_SalOrdType" = X."V"))
             AND (:nDoc = 0 OR EXISTS (SELECT 1 FROM :lDoc X WHERE TO_NVARCHAR(H."DocNum") LIKE X."P"));
    IF :STYPE = '3' THEN
        f = SELECT G."ObjType", G."DocEntry", G."LineNum", G."ItemCode", CAST(G."CostAmt" AS DECIMAL(19,6)) AS "Beg", CAST(0 AS DECIMAL(19,6)) AS "Iss", CAST(0 AS DECIMAL(19,6)) AS "Ret0", CAST(0 AS DECIMAL(19,6)) AS "Inv",
               CAST(0 AS DECIMAL(19,6)) AS "Rin", CAST(0 AS DECIMAL(19,6)) AS "Ret", CAST(0 AS DECIMAL(19,6)) AS "Adj", CAST(0 AS DECIMAL(19,6)) AS "Smp", CAST(0 AS DECIMAL(19,6)) AS "EndA"
              FROM "MTC_CA_R_GOODS_OUT_BEG" G WHERE G."RunId" = :rid
            UNION ALL
            SELECT G."ObjType", G."DocEntry", G."LineNum", G."ItemCode", 0, 0, 0, 0, 0, 0, 0, 0, G."CostAmt" FROM "MTC_CA_R_GOODS_OUT" G WHERE G."RunId" = :rid
            UNION ALL
            SELECT D."ObjType", D."DocEntry", D."LineNum", L."ItemCode", 0,
                   CASE WHEN D."ObjType" = '15' THEN -L."Amount" ELSE 0 END, CASE WHEN D."ObjType" = '16' THEN L."Amount" ELSE 0 END, 0, 0, 0, 0, 0, 0
              FROM "MTC_CA_S_LINE" D JOIN "MTC_CA_R_LINE" L ON L."RunId" = D."RunId" AND L."LineId" = D."LineId"
             WHERE D."RunId" = :rid AND (D."ObjType" = '15' OR (D."ObjType" = '16' AND IFNULL(D."BaseType", '') <> '15'))
            UNION ALL
            SELECT M."SrcObj", M."SrcEntry", M."SrcLine", NULL, 0, 0, 0,
                   CASE WHEN M."K" = 'INV' THEN M."Amount" ELSE 0 END, CASE WHEN M."K" = 'RIN' THEN M."Amount" ELSE 0 END,
                   CASE WHEN M."K" = 'RET' THEN M."Amount" ELSE 0 END, CASE WHEN M."K" = 'ADJ' THEN M."Amount" ELSE 0 END,
                   CASE WHEN M."IsSample" = 'Y' AND M."K" <> 'RET' THEN M."Amount" ELSE 0 END, 0
              FROM "MTC_CA_R_GOODS_MOVE" M WHERE M."RunId" = :rid;
        SELECT H."CardCode" AS "客户", MAX(C."CardName") AS "客户名称",
               CAST(SUM(F."Beg") AS DECIMAL(19,2)) AS "期初未开票成本", CAST(SUM(F."Iss") AS DECIMAL(19,2)) AS "本期·发货", CAST(SUM(F."Ret0") AS DECIMAL(19,2)) AS "本期·独立退货",
               CAST(SUM(F."Inv") AS DECIMAL(19,2)) AS "本期·开票", CAST(SUM(F."Rin") AS DECIMAL(19,2)) AS "本期·贷项", CAST(SUM(F."Ret") AS DECIMAL(19,2)) AS "本期·基于交货退货",
               CAST(SUM(F."Adj") AS DECIMAL(19,2)) AS "本期·尾差", CAST(SUM(F."Smp") AS DECIMAL(19,2)) AS "其中样品转出",
               CAST(SUM(F."EndA") AS DECIMAL(19,2)) AS "期末未开票成本",
               CAST(SUM(F."Beg" + F."Iss" - F."Ret0" - F."Inv" - F."Rin" - F."Ret" - F."Adj" - F."EndA") AS DECIMAL(19,2)) AS "勾稽差额"
          FROM :f F
          JOIN :hd2 H ON H."ObjType" = F."ObjType" AND H."DocEntry" = F."DocEntry" AND H."LineNum" = F."LineNum"
          LEFT JOIN "OCRD" C ON C."CardCode" = H."CardCode"
          LEFT JOIN "OITM" I ON I."ItemCode" = H."ItemCode"
         WHERE (IFNULL(:Sample, '') = '' OR H."IsSample" = :Sample)
           AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE H."ItemCode" LIKE X."P"))
           AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(I."ItmsGrpCod") = X."V"))
         GROUP BY H."CardCode" ORDER BY H."CardCode";
        RETURN;
    END IF;
    lnx = SELECT G."ObjType", G."DocEntry", G."LineNum", H."DocNum", G."DocDate", H."CardCode", COALESCE(G."CustType", H."CustType") AS "CustType", H."U_SalOrdType",
                G."IsSample", G."ItemCode", H."Dscription", G."DocQty", G."InvQty", G."RetQty", G."OpenQty", G."UnitCost", G."CostSrc", G."CostAmt",
                H."LineTotal" / NULLIF(H."Quantity", 0) * ABS(G."OpenQty") AS "SalAmt",
                DAYS_BETWEEN(G."DocDate", :d1) AS "Age"
           FROM "MTC_CA_R_GOODS_OUT" G
           JOIN :hd2 H ON H."ObjType" = G."ObjType" AND H."DocEntry" = G."DocEntry" AND H."LineNum" = G."LineNum"
           LEFT JOIN "OITM" I ON I."ItemCode" = G."ItemCode"
          WHERE G."RunId" = :rid
            AND (IFNULL(:Sample, '') = '' OR G."IsSample" = :Sample)
            AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE G."ItemCode" LIKE X."P"))
            AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(I."ItmsGrpCod") = X."V"))
            AND DAYS_BETWEEN(G."DocDate", :d1) >= :age;
    IF :STYPE = '4' THEN
        jd = SELECT CASE "TransCode" WHEN 'AR03' THEN :cDom ELSE :cExp END AS "CustType", "TransCode", SUM("Credit" - "Debit") AS "Amt"
               FROM "MTC_CA_R_JDT" WHERE "RunId" = :rid AND "TransCode" IN ('AR03', 'AR04') AND "AcctCode" = :goods
              GROUP BY "TransCode";
        g = SELECT IFNULL("CustType", '') AS "CustType", SUM("CostAmt") AS "Amt", SUM(CASE WHEN "IsSample" = 'Y' THEN "CostAmt" ELSE 0 END) AS "Smp", COUNT(*) AS "Cnt"
              FROM :lnx GROUP BY IFNULL("CustType", '');
        k = SELECT "CustType" FROM :g UNION SELECT "CustType" FROM :jd;
        SELECT K."CustType" AS "客户类型", MAX(J."TransCode") AS "计提凭证代码", MAX(G."Cnt") AS "未清行数",
               CAST(IFNULL(MAX(G."Amt"), 0) AS DECIMAL(19,2)) AS "未开票成本", CAST(IFNULL(MAX(G."Smp"), 0) AS DECIMAL(19,2)) AS "其中样品",
               CAST(IFNULL(MAX(J."Amt"), 0) AS DECIMAL(19,2)) AS "本期计提（贷 140601）",
               CAST(IFNULL(MAX(G."Amt"), 0) - IFNULL(MAX(J."Amt"), 0) AS DECIMAL(19,2)) AS "差额"
          FROM :k K LEFT JOIN :g G ON G."CustType" = K."CustType" LEFT JOIN :jd J ON J."CustType" = K."CustType"
         GROUP BY K."CustType" ORDER BY K."CustType";
    ELSEIF :STYPE = '2' THEN
        SELECT L."CardCode" AS "客户", C."CardName" AS "客户名称", L."CustType" AS "客户类型", L."U_SalOrdType" AS "销售订单类型", L."IsSample" AS "样品",
               CASE L."ObjType" WHEN '15' THEN '交货' ELSE '退货' END AS "单据", L."DocNum" AS "单号 Num", L."DocEntry" AS "单号 Entry", L."LineNum" AS "行号",
               L."DocDate" AS "交货日期", L."Age" AS "账龄天数", L."ItemCode" AS "物料", L."Dscription" AS "物料描述",
               CAST(L."DocQty" AS DECIMAL(19,6)) AS "交货数量", CAST(L."InvQty" AS DECIMAL(19,6)) AS "已开票数量", CAST(L."RetQty" AS DECIMAL(19,6)) AS "已退货数量",
               CAST(L."OpenQty" AS DECIMAL(19,6)) AS "未清数量", CAST(L."UnitCost" AS DECIMAL(19,6)) AS "单位成本", L."CostSrc" AS "单位成本来源",
               CAST(L."CostAmt" AS DECIMAL(19,2)) AS "未清成本", CAST(L."SalAmt" AS DECIMAL(19,2)) AS "未开票销售金额"
          FROM :lnx L LEFT JOIN "OCRD" C ON C."CardCode" = L."CardCode"
         ORDER BY L."CardCode", L."DocDate", L."DocEntry", L."LineNum";
    ELSEIF :STYPE = '1' THEN
        SELECT L."CardCode" AS "客户", MAX(C."CardName") AS "客户名称", L."ItemCode" AS "物料", MAX(L."Dscription") AS "物料描述", COUNT(*) AS "行数",
               CAST(SUM(L."OpenQty") AS DECIMAL(19,6)) AS "未清数量", CAST(SUM(L."CostAmt") AS DECIMAL(19,2)) AS "未清成本",
               CAST(SUM(L."SalAmt") AS DECIMAL(19,2)) AS "未开票销售金额", MIN(L."DocDate") AS "最早交货日期", MAX(L."Age") AS "最长账龄天数"
          FROM :lnx L LEFT JOIN "OCRD" C ON C."CardCode" = L."CardCode"
         GROUP BY L."CardCode", L."ItemCode" ORDER BY L."CardCode", L."ItemCode";
    ELSE
        SELECT L."CardCode" AS "客户", MAX(C."CardName") AS "客户名称", MAX(L."CustType") AS "客户类型", COUNT(*) AS "行数",
               CAST(SUM(L."CostAmt") AS DECIMAL(19,2)) AS "未清成本", CAST(SUM(L."SalAmt") AS DECIMAL(19,2)) AS "未开票销售金额",
               CAST(SUM(CASE WHEN L."Age" <= 30 THEN L."CostAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "账龄（成本）·30 天内",
               CAST(SUM(CASE WHEN L."Age" BETWEEN 31 AND 60 THEN L."CostAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "账龄（成本）·31–60 天",
               CAST(SUM(CASE WHEN L."Age" BETWEEN 61 AND 90 THEN L."CostAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "账龄（成本）·61–90 天",
               CAST(SUM(CASE WHEN L."Age" BETWEEN 91 AND 180 THEN L."CostAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "账龄（成本）·91–180 天",
               CAST(SUM(CASE WHEN L."Age" > 180 THEN L."CostAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "账龄（成本）·180 天以上",
               CAST(SUM(CASE WHEN L."IsSample" = 'Y' THEN L."CostAmt" ELSE 0 END) AS DECIMAL(19,2)) AS "其中样品",
               MIN(L."DocDate") AS "最早交货日期"
          FROM :lnx L LEFT JOIN "OCRD" C ON C."CardCode" = L."CardCode"
         GROUP BY L."CardCode" ORDER BY L."CardCode";
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R12 产品单位成本变动分析：本期与对比期相比单位成本变了多少，拆成材料价格、材料用量、费率、工时、委外加工费因素。
-- 参数：Fc 账期, CmpFc 对比账期（空 = 上期）, Item 产品, ItemGrp 物料组, MinPct 只看单位成本变动超过 %（空 = 全部）,
--       STYPE 0 按产品 / 1 产品 × 材料
-- 口径：两期都有完工的产品（R_ORDER.RecvQty > 0）。单位材料按 R_ORDER_MAT 的本期结转：单耗 = 结转数量 ÷ 完工数量（结转数量 =
--       （期初累计领料 + 本期领料）× 结转比例），单价 = 结转金额 ÷ 结转数量；价格因素 = (本期单价 − 对比期单价) × 本期单耗，
--       用量因素 = (本期单耗 − 对比期单耗) × 对比期单价；只有一期领用的材料全部算用量因素。本级费用：费率 = 分摊额 ÷ 工时（R_ALLOC），
--       费率因素 = (本期费率 − 对比期费率) × 本期单位工时，工时因素 = (本期单位工时 − 对比期单位工时) × 对比期费率。
--       “其他”= 变动额 − 各因素（结转比例变化、关单、四舍五入）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_12_COSTVAR" (
    IN Fc NVARCHAR(10), IN CmpFc NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN MinPct NVARCHAR(20), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE rid BIGINT; DECLARE pfc NVARCHAR(10); DECLARE cfc NVARCHAR(10); DECLARE prid BIGINT; DECLARE nItem INT; DECLARE nGrp INT;
    DECLARE th DECIMAL(19,6) := TO_DECIMAL(IFNULL(NULLIF(TRIM(:MinPct), ''), '0'), 19, 6);
    SELECT MAX("RunId"), MAX("PrevFc") INTO rid, pfc FROM "MTC_CA_F_RPT_RUN"(:Fc, :Fc);
    cfc := IFNULL(NULLIF(TRIM(IFNULL(:CmpFc, '')), ''), :pfc);
    SELECT MAX("RunId") INTO prid FROM "MTC_CA_F_RPT_RUN"(:cfc, :cfc);
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);    SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp); SELECT COUNT(*) INTO nGrp FROM :lGrp;
    IF :rid IS NULL OR :prid IS NULL THEN
        SELECT '本期或对比期没有成功的正式计算（看 R00）' AS "说明" FROM DUMMY;
        RETURN;
    END IF;
    ord = SELECT CASE WHEN O."RunId" = :rid THEN 'C' ELSE 'P' END AS "W", O."RunId", O."OrderType", O."OrderEntry", O."ItemCode", O."RecvQty", O."CostAmt",
                 O."AllocMfg" + O."AllocLab" AS "Fee"
            FROM "MTC_CA_R_ORDER" O LEFT JOIN "OITM" M ON M."ItemCode" = O."ItemCode"
           WHERE O."RunId" IN (:rid, :prid) AND O."RecvQty" > 0
             AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE O."ItemCode" LIKE X."P"))
             AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"));
    hrs = SELECT O."W", O."ItemCode", SUM(A."W") AS "H"
            FROM :ord O
            JOIN (SELECT "RunId", "OrderType", "OrderEntry", "PoolCode", MAX("Weight") AS "W" FROM "MTC_CA_R_ALLOC" WHERE "RunId" IN (:rid, :prid)
                   GROUP BY "RunId", "OrderType", "OrderEntry", "PoolCode") A
              ON A."RunId" = O."RunId" AND A."OrderType" = O."OrderType" AND A."OrderEntry" = O."OrderEntry"
           GROUP BY O."W", O."ItemCode";
    pr = SELECT O."ItemCode",
                SUM(CASE WHEN O."W" = 'C' THEN O."RecvQty" ELSE 0 END) AS "Q1", SUM(CASE WHEN O."W" = 'P' THEN O."RecvQty" ELSE 0 END) AS "Q0",
                SUM(CASE WHEN O."W" = 'C' THEN O."CostAmt" ELSE 0 END) AS "A1", SUM(CASE WHEN O."W" = 'P' THEN O."CostAmt" ELSE 0 END) AS "A0",
                SUM(CASE WHEN O."W" = 'C' THEN O."Fee" ELSE 0 END) AS "F1", SUM(CASE WHEN O."W" = 'P' THEN O."Fee" ELSE 0 END) AS "F0"
           FROM :ord O GROUP BY O."ItemCode"
         HAVING SUM(CASE WHEN O."W" = 'C' THEN O."RecvQty" ELSE 0 END) > 0 AND SUM(CASE WHEN O."W" = 'P' THEN O."RecvQty" ELSE 0 END) > 0;
    pr2 = SELECT P.*, IFNULL(H1."H", 0) AS "H1", IFNULL(H0."H", 0) AS "H0"
            FROM :pr P LEFT JOIN :hrs H1 ON H1."W" = 'C' AND H1."ItemCode" = P."ItemCode" LEFT JOIN :hrs H0 ON H0."W" = 'P' AND H0."ItemCode" = P."ItemCode";
    mt = SELECT O."ItemCode" AS "Prod", M."ItemCode" AS "Mat",
                SUM(CASE WHEN O."W" = 'C' THEN (M."OpenIssQty" + M."IssQty") * IFNULL(M."Ratio", 0) ELSE 0 END) AS "CQ1",
                SUM(CASE WHEN O."W" = 'P' THEN (M."OpenIssQty" + M."IssQty") * IFNULL(M."Ratio", 0) ELSE 0 END) AS "CQ0",
                SUM(CASE WHEN O."W" = 'C' THEN M."CarMat" + M."CarLab" + M."CarMfg" + M."CarSub" ELSE 0 END) AS "CA1",
                SUM(CASE WHEN O."W" = 'P' THEN M."CarMat" + M."CarLab" + M."CarMfg" + M."CarSub" ELSE 0 END) AS "CA0"
           FROM :ord O JOIN "MTC_CA_R_ORDER_MAT" M ON M."RunId" = O."RunId" AND M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
          GROUP BY O."ItemCode", M."ItemCode";
    -- 每个产品 × 材料的单耗、单价和两个因素（每件产品）
    mf = SELECT T."Prod", T."Mat", P."Q1", P."Q0",
                T."CQ1" / P."Q1" AS "U1", T."CQ0" / P."Q0" AS "U0",
                T."CA1" / NULLIF(T."CQ1", 0) AS "P1", T."CA0" / NULLIF(T."CQ0", 0) AS "PP0",
                T."CA1" / P."Q1" AS "UC1", T."CA0" / P."Q0" AS "UC0",
                CASE WHEN T."Mat" <> '#SUBFEE' AND T."CQ1" <> 0 AND T."CQ0" <> 0
                     THEN (T."CA1" / T."CQ1" - T."CA0" / T."CQ0") * (T."CQ1" / P."Q1") ELSE 0 END AS "EP",
                CASE WHEN T."Mat" = '#SUBFEE' THEN 0
                     WHEN T."CQ1" <> 0 AND T."CQ0" <> 0 THEN (T."CQ1" / P."Q1" - T."CQ0" / P."Q0") * (T."CA0" / T."CQ0")
                     ELSE T."CA1" / P."Q1" - T."CA0" / P."Q0" END AS "EU",
                CASE WHEN T."Mat" = '#SUBFEE' THEN T."CA1" / P."Q1" - T."CA0" / P."Q0" ELSE 0 END AS "ES"
           FROM :mt T JOIN :pr P ON P."ItemCode" = T."Prod";
    IF :STYPE = '1' THEN
        SELECT F."Prod" AS "产品", MAX(PM."ItemName") AS "产品名称", F."Mat" AS "材料", MAX(CASE WHEN F."Mat" = '#SUBFEE' THEN '委外加工费' ELSE MM."ItemName" END) AS "材料名称",
               CAST(MAX(F."U1") AS DECIMAL(19,6)) AS "单耗·本期", CAST(MAX(F."U0") AS DECIMAL(19,6)) AS "单耗·对比期",
               CAST(MAX(F."P1") AS DECIMAL(19,6)) AS "材料单价·本期", CAST(MAX(F."PP0") AS DECIMAL(19,6)) AS "材料单价·对比期",
               CAST(MAX(F."UC1") AS DECIMAL(19,6)) AS "每件材料成本·本期", CAST(MAX(F."UC0") AS DECIMAL(19,6)) AS "每件材料成本·对比期",
               CAST(MAX(F."UC1") - MAX(F."UC0") AS DECIMAL(19,6)) AS "每件材料成本·变动",
               CAST(MAX(F."EP") AS DECIMAL(19,6)) AS "因素·价格", CAST(MAX(F."EU") AS DECIMAL(19,6)) AS "因素·用量", CAST(MAX(F."ES") AS DECIMAL(19,6)) AS "因素·委外加工费"
          FROM :mf F LEFT JOIN "OITM" PM ON PM."ItemCode" = F."Prod" LEFT JOIN "OITM" MM ON MM."ItemCode" = F."Mat"
         GROUP BY F."Prod", F."Mat"
        HAVING :th = 0 OR ABS(MAX(F."UC1") - MAX(F."UC0")) * 100 >= :th * NULLIF(ABS(MAX(F."UC0")), 0) OR MAX(F."UC0") = 0
         ORDER BY F."Prod", ABS(MAX(F."UC1") - MAX(F."UC0")) DESC;
    ELSE
        fx = SELECT "Prod", SUM("EP") AS "EP", SUM("EU") AS "EU", SUM("ES") AS "ES" FROM :mf GROUP BY "Prod";
        SELECT TO_NVARCHAR(M."ItmsGrpCod") AS "物料组", P."ItemCode" AS "产品", M."ItemName" AS "产品名称",
               :Fc AS "本期", :cfc AS "对比期",
               CAST(P."Q1" AS DECIMAL(19,6)) AS "完工数量·本期", CAST(P."Q0" AS DECIMAL(19,6)) AS "完工数量·对比期",
               CAST(P."A1" / P."Q1" AS DECIMAL(19,6)) AS "单位成本·本期", CAST(P."A0" / P."Q0" AS DECIMAL(19,6)) AS "单位成本·对比期",
               CAST(P."A1" / P."Q1" - P."A0" / P."Q0" AS DECIMAL(19,6)) AS "单位成本·变动",
               CAST((P."A1" / P."Q1" - P."A0" / P."Q0") * 100 / NULLIF(P."A0" / P."Q0", 0) AS DECIMAL(19,2)) AS "单位成本·变动 %",
               CAST(IFNULL(X."EP", 0) AS DECIMAL(19,6)) AS "因素·材料价格", CAST(IFNULL(X."EU", 0) AS DECIMAL(19,6)) AS "因素·材料用量",
               CAST(CASE WHEN P."H1" <> 0 AND P."H0" <> 0 THEN (P."F1" / P."H1" - P."F0" / P."H0") * (P."H1" / P."Q1") ELSE P."F1" / P."Q1" - P."F0" / P."Q0" END AS DECIMAL(19,6)) AS "因素·费率",
               CAST(CASE WHEN P."H1" <> 0 AND P."H0" <> 0 THEN (P."H1" / P."Q1" - P."H0" / P."Q0") * (P."F0" / P."H0") ELSE 0 END AS DECIMAL(19,6)) AS "因素·工时",
               CAST(IFNULL(X."ES", 0) AS DECIMAL(19,6)) AS "因素·委外加工费",
               CAST(P."A1" / P."Q1" - P."A0" / P."Q0" - IFNULL(X."EP", 0) - IFNULL(X."EU", 0) - IFNULL(X."ES", 0)
                    - (P."F1" / P."Q1" - P."F0" / P."Q0") AS DECIMAL(19,6)) AS "因素·其他",
               CAST(P."H1" / P."Q1" AS DECIMAL(19,6)) AS "单位工时·本期", CAST(P."H0" / P."Q0" AS DECIMAL(19,6)) AS "单位工时·对比期",
               CAST(P."F1" / NULLIF(P."H1", 0) AS DECIMAL(19,6)) AS "每工时费用·本期", CAST(P."F0" / NULLIF(P."H0", 0) AS DECIMAL(19,6)) AS "每工时费用·对比期"
          FROM :pr2 P LEFT JOIN :fx X ON X."Prod" = P."ItemCode" LEFT JOIN "OITM" M ON M."ItemCode" = P."ItemCode"
         WHERE :th = 0 OR ABS(P."A1" / P."Q1" - P."A0" / P."Q0") * 100 >= :th * NULLIF(ABS(P."A0" / P."Q0"), 0)
         ORDER BY ABS(P."A1" / P."Q1" - P."A0" / P."Q0") * P."Q1" DESC;
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R13 材料用量差异（损耗）：订单实际领用与按完工数折算的计划用量之差。
-- 参数：FcFrom, FcTo, Scope 订单范围（空或 2 = 本期按关单处理的订单，1 = 本期有完工的订单）, WorType 订单类型, Item 产品, Mat 材料,
--       MinPct 只看差异超过 %（空 = 全部；计划外领料、计划内未领始终列出）, STYPE 0 产品 × 材料 / 1 订单 × 材料 / 2 按材料
-- 口径：实际 = 截至期末累计领料数量（R_ORDER_MAT 期初累计 + 本期，退料冲减）；标准 = 累计完工数 × 订单行计划用量 ÷ 订单计划数（S_ORDER_LINE，
--       同 P45 结转比例的口径）；差异金额 = 差异数量 × 累计领料平均单价。关单订单的差异就是全部损耗，本期完工未关单的只是阶段数。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_13_USAGE" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Scope NVARCHAR(1), IN WorType NVARCHAR(100), IN Item NVARCHAR(5000), IN Mat NVARCHAR(5000),
    IN MinPct NVARCHAR(20), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE nWt INT; DECLARE nItem INT; DECLARE nMat INT;
    DECLARE th DECIMAL(19,6) := TO_DECIMAL(IFNULL(NULLIF(TRIM(:MinPct), ''), '0'), 19, 6);
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    lWt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:WorType); SELECT COUNT(*) INTO nWt FROM :lWt;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);    SELECT COUNT(*) INTO nItem FROM :lItem;
    lMat  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Mat);     SELECT COUNT(*) INTO nMat FROM :lMat;
    ord = SELECT U."FcCode", O."RunId", O."OrderType", O."OrderEntry", S."OrderNum", O."WorType", O."ItemCode", O."PlannedQty",
                 O."PrevRecvQty" + O."RecvQty" AS "CumQ", O."ClosedInFc"
            FROM :runs U
            JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
            LEFT JOIN "MTC_CA_S_ORDER" S ON S."RunId" = O."RunId" AND S."OrderType" = O."OrderType" AND S."OrderEntry" = O."OrderEntry"
           WHERE (CASE WHEN :Scope = '1' THEN CASE WHEN O."RecvQty" <> 0 THEN 1 ELSE 0 END ELSE CASE WHEN O."ClosedInFc" = 'Y' THEN 1 ELSE 0 END END) = 1
             AND (:nWt = 0 OR EXISTS (SELECT 1 FROM :lWt X WHERE O."WorType" = X."V"))
             AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE O."ItemCode" LIKE X."P"));
    pl = SELECT L."RunId", L."OrderType", L."OrderEntry", L."ItemCode", SUM(L."PlannedQty") AS "PQ"
           FROM "MTC_CA_S_ORDER_LINE" L JOIN :ord O ON O."RunId" = L."RunId" AND O."OrderType" = L."OrderType" AND O."OrderEntry" = L."OrderEntry"
          GROUP BY L."RunId", L."OrderType", L."OrderEntry", L."ItemCode";
    am = SELECT M."RunId", M."OrderType", M."OrderEntry", M."ItemCode", M."OpenIssQty" + M."IssQty" AS "AQ",
                M."OpenIssMat" + M."OpenIssLab" + M."OpenIssMfg" + M."OpenIssSub" + M."IssMat" + M."IssLab" + M."IssMfg" + M."IssSub" AS "AA"
           FROM "MTC_CA_R_ORDER_MAT" M JOIN :ord O ON O."RunId" = M."RunId" AND O."OrderType" = M."OrderType" AND O."OrderEntry" = M."OrderEntry"
          WHERE M."ItemCode" <> '#SUBFEE';
    k = SELECT "RunId", "OrderType", "OrderEntry", "ItemCode" FROM :pl UNION SELECT "RunId", "OrderType", "OrderEntry", "ItemCode" FROM :am;
    d = SELECT O."FcCode", O."OrderType", O."OrderEntry", O."OrderNum", O."WorType", O."ItemCode" AS "Prod", K."ItemCode" AS "Mat", O."CumQ", O."PlannedQty",
               IFNULL(P."PQ", 0) AS "PQ", IFNULL(A."AQ", 0) AS "AQ", IFNULL(A."AA", 0) AS "AA",
               CASE WHEN IFNULL(O."PlannedQty", 0) > 0 THEN O."CumQ" * IFNULL(P."PQ", 0) / O."PlannedQty" ELSE 0 END AS "SQ",
               COALESCE(A."AA" / NULLIF(A."AQ", 0), RI."PMat" + RI."PMfg" + RI."PLab" + RI."PSub") AS "UP",
               CASE WHEN P."ItemCode" IS NULL THEN '计划外领料' WHEN IFNULL(A."AQ", 0) = 0 THEN '计划内未领' END AS "Note"
          FROM :k K
          JOIN :ord O ON O."RunId" = K."RunId" AND O."OrderType" = K."OrderType" AND O."OrderEntry" = K."OrderEntry"
          LEFT JOIN :pl P ON P."RunId" = K."RunId" AND P."OrderType" = K."OrderType" AND P."OrderEntry" = K."OrderEntry" AND P."ItemCode" = K."ItemCode"
          LEFT JOIN :am A ON A."RunId" = K."RunId" AND A."OrderType" = K."OrderType" AND A."OrderEntry" = K."OrderEntry" AND A."ItemCode" = K."ItemCode"
          LEFT JOIN "MTC_CA_R_ITEM" RI ON RI."RunId" = K."RunId" AND RI."ItemCode" = K."ItemCode"
         WHERE (:nMat = 0 OR EXISTS (SELECT 1 FROM :lMat X WHERE K."ItemCode" LIKE X."P"));
    -- 分组键先在子查询里算好（HANA 不认 SELECT / GROUP BY 中带参数的 CASE 是同一表达式）
    o = SELECT "Prod", "Mat", "FcCode", "OrderType", "OrderNum", "OrderEntry",
               COUNT(*) AS "Cnt", SUM("CumQ") AS "CumQ",
               SUM("PQ") AS "PQ", SUM("SQ") AS "SQ", SUM("AQ") AS "AQ", SUM("AA") AS "AA",
               SUM(("AQ" - "SQ") * IFNULL("UP", 0)) AS "DA", MAX("Note") AS "Note"
          FROM (SELECT CASE WHEN :STYPE = '2' THEN NULL ELSE "Prod" END AS "Prod", "Mat",
                       CASE WHEN :STYPE = '1' THEN "FcCode" END AS "FcCode", CASE WHEN :STYPE = '1' THEN "OrderType" END AS "OrderType",
                       CASE WHEN :STYPE = '1' THEN "OrderNum" END AS "OrderNum", CASE WHEN :STYPE = '1' THEN "OrderEntry" END AS "OrderEntry",
                       CASE WHEN :STYPE = '1' THEN "CumQ" END AS "CumQ", "PQ", "SQ", "AQ", "AA", "UP", "Note"
                  FROM :d)
         GROUP BY "Prod", "Mat", "FcCode", "OrderType", "OrderNum", "OrderEntry";
    SELECT X."Prod" AS "产品", PM."ItemName" AS "产品名称", X."FcCode" AS "账期", X."OrderType" AS "订单单据", X."OrderNum" AS "订单号 Num",
           X."Mat" AS "材料", MM."ItemName" AS "材料名称", X."Cnt" AS "订单数", CAST(X."CumQ" AS DECIMAL(19,6)) AS "累计完工数",
           CAST(X."PQ" AS DECIMAL(19,6)) AS "订单计划用量", CAST(X."SQ" AS DECIMAL(19,6)) AS "按完工折算标准用量", CAST(X."AQ" AS DECIMAL(19,6)) AS "实际领用",
           CAST(X."AQ" - X."SQ" AS DECIMAL(19,6)) AS "差异·数量", CAST((X."AQ" - X."SQ") * 100 / NULLIF(X."SQ", 0) AS DECIMAL(19,2)) AS "差异·%",
           CAST(X."AA" / NULLIF(X."AQ", 0) AS DECIMAL(19,6)) AS "平均领料单价", CAST(X."DA" AS DECIMAL(19,2)) AS "差异·金额", X."Note" AS "说明"
      FROM :o X LEFT JOIN "OITM" PM ON PM."ItemCode" = X."Prod" LEFT JOIN "OITM" MM ON MM."ItemCode" = X."Mat"
     WHERE :th = 0 OR X."SQ" = 0 OR X."AQ" = 0 OR ABS(X."AQ" - X."SQ") * 100 >= :th * ABS(X."SQ")
     ORDER BY X."Prod", X."FcCode", X."OrderNum", ABS(X."DA") DESC, X."Mat";
END
@@
-- ---------------------------------------------------------------------
-- R14 产品毛利分析：本期开票收入与结转的销售成本（同 DN03 口径）对比。
-- 参数：FcFrom, FcTo, Item 物料, ItemGrp 物料组, Cust 客户, CustType 客户类型, SalType 销售订单类型, InclSample 含样品 Y/N（默认 N）,
--       STYPE 0 按产品 / 1 按客户 / 2 客户 × 产品 / 3 发票行
-- 口径：收入 = 本期过账的应收发票（OINV/INV1）− 应收贷项（ORIN/RIN1）的行金额（本币、不含税），取消单反号；成本 = 新框架 R_GOODS_MOVE
--       里这张发票 / 贷项行消耗交货（独立退货）的成本，加上交货行全部开完票时的尾差（ADJ，挂在交货行的产品和客户上）。
--       不基于交货的发票行（如服务、直接开票）没有成本，标“无交货成本”。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_14_MARGIN" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000), IN Cust NVARCHAR(5000),
    IN CustType NVARCHAR(200), IN SalType NVARCHAR(500), IN InclSample NVARCHAR(1), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE d0 DATE; DECLARE d1 DATE; DECLARE fB NVARCHAR(10); DECLARE smp NVARCHAR(200);
    DECLARE nItem INT; DECLARE nGrp INT; DECLARE nCust INT; DECLARE nCt INT; DECLARE nSt INT;
    runs = SELECT "FcCode", "RunId", "D0", "D1" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    SELECT MIN("D0"), MAX("D1"), MAX("FcCode") INTO d0, d1, fB FROM :runs;
    smp := IFNULL("MTC_CA_F_PARAM"('SAMPLE_SALTYPES', :fB), ',样品销售,');
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);     SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp);  SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lCust = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Cust);     SELECT COUNT(*) INTO nCust FROM :lCust;
    lCt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:CustType); SELECT COUNT(*) INTO nCt FROM :lCt;
    lSt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:SalType);  SELECT COUNT(*) INTO nSt FROM :lSt;
    st = SELECT "Name", MAX("U_CustType") AS "CustType", MAX("U_BusiType") AS "BusiType" FROM "@MTC_SALORDTYPE" GROUP BY "Name";
    cost = SELECT CASE M."K" WHEN 'INV' THEN '13' ELSE '14' END AS "ObjType", M."DocEntry", M."LineNum", SUM(M."Amount") AS "Cost"
             FROM :runs U JOIN "MTC_CA_R_GOODS_MOVE" M ON M."RunId" = U."RunId" AND M."K" IN ('INV', 'RIN')
            GROUP BY M."K", M."DocEntry", M."LineNum";
    rows0 = SELECT '13' AS "ObjType", D."DocEntry", D."LineNum", H."DocNum", TO_DATE(H."DocDate") AS "DocDate", H."CardCode", H."U_SalOrdType" AS "SalType",
                   D."ItemCode", D."Dscription",
                   CAST(CASE WHEN H."CANCELED" = 'C' THEN -1 ELSE 1 END * D."Quantity" AS DECIMAL(19,6)) AS "Qty",
                   CAST(CASE WHEN H."CANCELED" = 'C' THEN -1 ELSE 1 END * D."LineTotal" AS DECIMAL(19,6)) AS "Rev"
              FROM "OINV" H JOIN "INV1" D ON D."DocEntry" = H."DocEntry"
             WHERE TO_DATE(H."DocDate") BETWEEN :d0 AND :d1
            UNION ALL
            SELECT '14', D."DocEntry", D."LineNum", H."DocNum", TO_DATE(H."DocDate"), H."CardCode", H."U_SalOrdType", D."ItemCode", D."Dscription",
                   CASE WHEN H."CANCELED" = 'C' THEN 1 ELSE -1 END * D."Quantity", CASE WHEN H."CANCELED" = 'C' THEN 1 ELSE -1 END * D."LineTotal"
              FROM "ORIN" H JOIN "RIN1" D ON D."DocEntry" = H."DocEntry"
             WHERE TO_DATE(H."DocDate") BETWEEN :d0 AND :d1;
    al = SELECT R."ObjType", R."DocEntry", R."LineNum", R."DocNum", R."DocDate", R."CardCode", R."SalType", R."ItemCode", R."Dscription", R."Qty", R."Rev",
                C."Cost", T."CustType", CASE WHEN LOCATE(:smp, ',' || IFNULL(T."BusiType", '') || ',') > 0 THEN 'Y' ELSE 'N' END AS "IsSample",
                CAST(CASE WHEN C."Cost" IS NULL THEN '无交货成本' END AS NVARCHAR(100)) AS "Note"
           FROM :rows0 R
           LEFT JOIN :cost C ON C."ObjType" = R."ObjType" AND C."DocEntry" = R."DocEntry" AND C."LineNum" = R."LineNum"
           LEFT JOIN :st T ON T."Name" = R."SalType"
         UNION ALL
         SELECT M."SrcObj", M."SrcEntry", M."SrcLine", COALESCE(DH."DocNum", RH."DocNum"), M."DocDate", COALESCE(DH."CardCode", RH."CardCode"),
                COALESCE(DH."U_SalOrdType", RH."U_SalOrdType"), COALESCE(DL."ItemCode", RL."ItemCode"), COALESCE(DL."Dscription", RL."Dscription"),
                0, 0, M."Amount", M."CustType", M."IsSample", '交货行开票完毕的尾差'
           FROM :runs U
           JOIN "MTC_CA_R_GOODS_MOVE" M ON M."RunId" = U."RunId" AND M."K" = 'ADJ'
           LEFT JOIN "ODLN" DH ON M."SrcObj" = '15' AND DH."DocEntry" = M."SrcEntry"
           LEFT JOIN "DLN1" DL ON M."SrcObj" = '15' AND DL."DocEntry" = M."SrcEntry" AND DL."LineNum" = M."SrcLine"
           LEFT JOIN "ORDN" RH ON M."SrcObj" = '16' AND RH."DocEntry" = M."SrcEntry"
           LEFT JOIN "RDN1" RL ON M."SrcObj" = '16' AND RL."DocEntry" = M."SrcEntry" AND RL."LineNum" = M."SrcLine";
    f = SELECT A.*, TO_NVARCHAR(I."ItmsGrpCod") AS "Grp", I."ItemName", C."CardName"
          FROM :al A LEFT JOIN "OITM" I ON I."ItemCode" = A."ItemCode" LEFT JOIN "OCRD" C ON C."CardCode" = A."CardCode"
         WHERE (IFNULL(:InclSample, 'N') = 'Y' OR A."IsSample" = 'N')
           AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE A."ItemCode" LIKE X."P"))
           AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(I."ItmsGrpCod") = X."V"))
           AND (:nCust = 0 OR EXISTS (SELECT 1 FROM :lCust X WHERE A."CardCode" LIKE X."P"))
           AND (:nCt = 0 OR EXISTS (SELECT 1 FROM :lCt X WHERE A."CustType" = X."V"))
           AND (:nSt = 0 OR EXISTS (SELECT 1 FROM :lSt X WHERE A."SalType" = X."V"));
    IF :STYPE = '3' THEN
        SELECT CASE F."ObjType" WHEN '13' THEN '应收发票' WHEN '14' THEN '应收贷项' WHEN '15' THEN '交货（尾差）' ELSE '退货（尾差）' END AS "单据",
               F."DocNum" AS "单号 Num", F."DocEntry" AS "单号 Entry", F."LineNum" AS "行号", F."DocDate" AS "日期", F."CardCode" AS "客户", F."CardName" AS "客户名称",
               F."CustType" AS "客户类型", F."SalType" AS "销售订单类型", F."IsSample" AS "样品", F."ItemCode" AS "物料", F."Dscription" AS "物料描述",
               F."Qty" AS "数量", CAST(F."Rev" AS DECIMAL(19,2)) AS "销售收入", CAST(F."Cost" AS DECIMAL(19,2)) AS "销售成本",
               CAST(F."Rev" - IFNULL(F."Cost", 0) AS DECIMAL(19,2)) AS "毛利",
               CAST((F."Rev" - IFNULL(F."Cost", 0)) * 100 / NULLIF(F."Rev", 0) AS DECIMAL(19,2)) AS "毛利率 %", F."Note" AS "说明"
          FROM :f F ORDER BY F."DocDate", F."ObjType", F."DocEntry", F."LineNum";
    ELSE
        -- 分组键先在子查询里算好（HANA 不认 SELECT / GROUP BY 中带参数的 CASE 是同一表达式）
        SELECT F."KCard" AS "客户", MAX(CASE WHEN :STYPE IN ('1', '2') THEN F."CardName" END) AS "客户名称",
               MAX(CASE WHEN :STYPE IN ('1', '2') THEN F."CustType" END) AS "客户类型",
               F."KItem" AS "物料",
               MAX(CASE WHEN :STYPE IN ('0', '2') OR IFNULL(:STYPE, '') = '' THEN F."ItemName" END) AS "物料名称",
               CAST(SUM(F."Qty") AS DECIMAL(19,6)) AS "数量", CAST(SUM(F."Rev") AS DECIMAL(19,2)) AS "销售收入", CAST(SUM(IFNULL(F."Cost", 0)) AS DECIMAL(19,2)) AS "销售成本",
               CAST(SUM(F."Rev") - SUM(IFNULL(F."Cost", 0)) AS DECIMAL(19,2)) AS "毛利",
               CAST((SUM(F."Rev") - SUM(IFNULL(F."Cost", 0))) * 100 / NULLIF(SUM(F."Rev"), 0) AS DECIMAL(19,2)) AS "毛利率 %",
               CAST(SUM(F."Rev") / NULLIF(SUM(F."Qty"), 0) AS DECIMAL(19,6)) AS "单位售价", CAST(SUM(IFNULL(F."Cost", 0)) / NULLIF(SUM(F."Qty"), 0) AS DECIMAL(19,6)) AS "单位成本",
               CAST(SUM(CASE WHEN F."Note" = '无交货成本' THEN F."Rev" ELSE 0 END) AS DECIMAL(19,2)) AS "其中无交货成本的收入"
          FROM (SELECT B.*, CASE WHEN :STYPE IN ('1', '2') THEN B."CardCode" END AS "KCard",
                       CASE WHEN :STYPE IN ('0', '2') OR IFNULL(:STYPE, '') = '' THEN B."ItemCode" END AS "KItem"
                  FROM :f B) F
         GROUP BY F."KCard", F."KItem"
         ORDER BY 1, 4;
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R15 费用池费用率趋势：各期每个费用池的归集额、工时、每工时费用及环比。
-- 参数：FcFrom, FcTo（都空 = 最近 12 个已计算账期）, Pool 费用池, Elem 要素（MFG / LAB，空 = 两项）
-- 口径：MTC_CA_R_POOL（归集）、MTC_CA_R_ALLOC（已分配、工时 = 单位工时 × 本期入库数）。每工时费用 = 已分配 ÷ 工时。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_15_POOLTREND" (IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN Pool NVARCHAR(500), IN Elem NVARCHAR(3))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE f0 NVARCHAR(10) := NULLIF(TRIM(IFNULL(:FcFrom, '')), '');
    DECLARE f1 NVARCHAR(10) := NULLIF(TRIM(IFNULL(:FcTo, '')), '');
    DECLARE nPool INT;
    DECLARE el NVARCHAR(3) := CASE WHEN :Elem IN ('MFG', '制造') THEN 'MFG' WHEN :Elem IN ('LAB', '人工') THEN 'LAB' ELSE '' END;
    IF :f0 IS NULL AND :f1 IS NULL THEN
        SELECT MAX("FcCode") INTO f1 FROM "MTC_CA_PERIOD" WHERE IFNULL("PostRunId", "CalcRunId") IS NOT NULL;
        SELECT MIN("FcCode") INTO f0 FROM (SELECT TOP 12 "FcCode" FROM "MTC_CA_PERIOD" WHERE IFNULL("PostRunId", "CalcRunId") IS NOT NULL ORDER BY "FcCode" DESC);
    END IF;
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:f0, IFNULL(:f1, :f0)) WHERE "RunId" IS NOT NULL;
    lPool = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Pool); SELECT COUNT(*) INTO nPool FROM :lPool;
    p = SELECT U."FcCode", P."RunId", P."PoolCode", P."Elem", SUM(P."Amount") AS "Amt"
          FROM :runs U JOIN "MTC_CA_R_POOL" P ON P."RunId" = U."RunId" GROUP BY U."FcCode", P."RunId", P."PoolCode", P."Elem";
    a = SELECT "RunId", "PoolCode", "Elem", SUM("Amount") AS "Amt", SUM("Weight") AS "W", SUM("RecvQty") AS "Q", COUNT(*) AS "Cnt"
          FROM "MTC_CA_R_ALLOC" WHERE "RunId" IN (SELECT "RunId" FROM :runs) GROUP BY "RunId", "PoolCode", "Elem";
    t = SELECT P."FcCode", P."PoolCode", P."Elem", P."Amt", IFNULL(A."Amt", 0) AS "Alloc", A."W", A."Q", IFNULL(A."Cnt", 0) AS "Cnt",
               IFNULL(A."Amt", 0) / NULLIF(A."W", 0) AS "Rate"
          FROM :p P LEFT JOIN :a A ON A."RunId" = P."RunId" AND A."PoolCode" = P."PoolCode" AND A."Elem" = P."Elem"
         WHERE (:el = '' OR P."Elem" = :el) AND (:nPool = 0 OR EXISTS (SELECT 1 FROM :lPool X WHERE P."PoolCode" = X."V"));
    SELECT T."PoolCode" AS "费用池", C."PoolName" AS "费用池名称", CASE T."Elem" WHEN 'MFG' THEN '制造' ELSE '人工' END AS "要素", T."FcCode" AS "账期",
           CAST(T."Amt" AS DECIMAL(19,2)) AS "归集金额", CAST(T."Alloc" AS DECIMAL(19,2)) AS "已分配", CAST(T."Amt" - T."Alloc" AS DECIMAL(19,2)) AS "未分配",
           T."Cnt" AS "分配订单数", CAST(T."Q" AS DECIMAL(19,6)) AS "入库数量", CAST(T."W" AS DECIMAL(19,6)) AS "工时",
           CAST(T."Rate" AS DECIMAL(19,6)) AS "每工时费用",
           CAST(LAG(T."Rate") OVER (PARTITION BY T."PoolCode", T."Elem" ORDER BY T."FcCode") AS DECIMAL(19,6)) AS "上期每工时费用",
           CAST((T."Rate" - LAG(T."Rate") OVER (PARTITION BY T."PoolCode", T."Elem" ORDER BY T."FcCode")) * 100
                / NULLIF(LAG(T."Rate") OVER (PARTITION BY T."PoolCode", T."Elem" ORDER BY T."FcCode"), 0) AS DECIMAL(19,2)) AS "环比 %",
           CAST((T."Amt" - LAG(T."Amt") OVER (PARTITION BY T."PoolCode", T."Elem" ORDER BY T."FcCode")) * 100
                / NULLIF(LAG(T."Amt") OVER (PARTITION BY T."PoolCode", T."Elem" ORDER BY T."FcCode"), 0) AS DECIMAL(19,2)) AS "归集额环比 %"
      FROM :t T LEFT JOIN "MTC_CA_C_POOL" C ON C."PoolCode" = T."PoolCode"
     ORDER BY T."PoolCode", T."Elem", T."FcCode";
END
@@
-- ---------------------------------------------------------------------
-- R16 期末存货结构：期末存货按类别（原材料 / 半成品 / 产成品 / 在产品 / 发出商品）、物料组、物料的金额和占比，与对比期比较，带最后动账日期。
-- 参数：Fc 账期, CmpFc 对比账期（空 = 上期）, Cls 存货类别（中文，逗号分隔）, ItemGrp 物料组, STYPE 0 按类别 / 1 类别 × 物料组 / 2 按物料
-- 口径：库存 = R_ITEM 期末四项；类别按参数 RPT_GRP_CLASS（物料组:类别），没列的物料组按 BOM：层级 0 原材料、是别的物料的子件（ITT1）半成品、
--       其余产成品；在产品 = R_ORDER.WipAmt（按订单产品）；发出商品 = R_GOODS_OUT 未开票成本。最后动账日期 = OIVL 截至期末最近一笔（不分仓库）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_16_INVSTRUCT" (
    IN Fc NVARCHAR(10), IN CmpFc NVARCHAR(10), IN Cls NVARCHAR(200), IN ItemGrp NVARCHAR(5000), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE rid BIGINT; DECLARE fc NVARCHAR(10); DECLARE pfc NVARCHAR(10); DECLARE cfc NVARCHAR(10); DECLARE prid BIGINT; DECLARE d1 DATE;
    DECLARE nCls INT; DECLARE nGrp INT; DECLARE tot DECIMAL(19,6);
    SELECT MAX("RunId"), MAX("FcCode"), MAX("PrevFc"), MAX("D1") INTO rid, fc, pfc, d1 FROM "MTC_CA_F_RPT_RUN"(:Fc, :Fc);
    cfc := IFNULL(NULLIF(TRIM(IFNULL(:CmpFc, '')), ''), :pfc);
    SELECT MAX("RunId") INTO prid FROM "MTC_CA_F_RPT_RUN"(:cfc, :cfc);
    lCls = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Cls);     SELECT COUNT(*) INTO nCls FROM :lCls;
    lGrp = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp); SELECT COUNT(*) INTO nGrp FROM :lGrp;
    IF :rid IS NULL THEN
        SELECT '这个账期没有成功的正式计算（看 R00）' AS "说明" FROM DUMMY;
        RETURN;
    END IF;
    gc = SELECT TRIM(SUBSTR_BEFORE("V", ':')) AS "Grp", TRIM(SUBSTR_AFTER("V", ':')) AS "Cls"
           FROM "MTC_CA_F_RPT_LIST"(IFNULL("MTC_CA_F_PARAM"('RPT_GRP_CLASS', :fc), '')) WHERE LOCATE("V", ':') > 0;
    v = SELECT CASE WHEN R."RunId" = :rid THEN 'C' ELSE 'P' END AS "W", 'STOCK' AS "Kind", R."ItemCode", R."iLevel", R."EndQty" AS "Qty", R."EndAmount" AS "Amt"
          FROM "MTC_CA_R_ITEM" R WHERE R."RunId" IN (:rid, IFNULL(:prid, -1)) AND (R."EndQty" <> 0 OR R."EndAmount" <> 0)
        UNION ALL
        SELECT CASE WHEN O."RunId" = :rid THEN 'C' ELSE 'P' END, 'WIP', O."ItemCode", O."iLevel", CAST(NULL AS DECIMAL(19,6)), SUM(O."WipAmt")
          FROM "MTC_CA_R_ORDER" O WHERE O."RunId" IN (:rid, IFNULL(:prid, -1)) AND O."WipAmt" <> 0 GROUP BY O."RunId", O."ItemCode", O."iLevel"
        UNION ALL
        SELECT CASE WHEN G."RunId" = :rid THEN 'C' ELSE 'P' END, 'GOODS', G."ItemCode", NULL, SUM(G."OpenQty"), SUM(G."CostAmt")
          FROM "MTC_CA_R_GOODS_OUT" G WHERE G."RunId" IN (:rid, IFNULL(:prid, -1)) GROUP BY G."RunId", G."ItemCode";
    c = SELECT V.*, TO_NVARCHAR(M."ItmsGrpCod") AS "Grp", M."ItemName",
               CASE V."Kind" WHEN 'WIP' THEN '在产品' WHEN 'GOODS' THEN '发出商品'
                    ELSE COALESCE(G."Cls", CASE WHEN V."iLevel" = 0 THEN '原材料'
                                                WHEN EXISTS (SELECT 1 FROM "ITT1" B WHERE B."Code" = V."ItemCode") THEN '半成品' ELSE '产成品' END) END AS "Cls"
          FROM :v V LEFT JOIN "OITM" M ON M."ItemCode" = V."ItemCode" LEFT JOIN :gc G ON G."Grp" = TO_NVARCHAR(M."ItmsGrpCod");
    c2 = SELECT * FROM :c
          WHERE (:nCls = 0 OR EXISTS (SELECT 1 FROM :lCls X WHERE "Cls" = X."V"))
            AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE "Grp" = X."V"));
    SELECT SUM("Amt") INTO tot FROM :c2 WHERE "W" = 'C';
    IF :STYPE = '2' THEN
        lst = SELECT "ItemCode", MAX(TO_DATE("DocDate")) AS "LastDate" FROM "OIVL"
               WHERE "ItemCode" IN (SELECT "ItemCode" FROM :c2 WHERE "W" = 'C' AND "Kind" = 'STOCK') AND TO_DATE("DocDate") <= :d1
               GROUP BY "ItemCode";
        SELECT X."Cls" AS "存货类别", X."Grp" AS "物料组", X."ItemCode" AS "物料", MAX(X."ItemName") AS "名称",
               CAST(SUM(CASE WHEN X."W" = 'C' THEN X."Qty" END) AS DECIMAL(19,6)) AS "本期末·数量",
               CAST(SUM(CASE WHEN X."W" = 'C' THEN X."Amt" ELSE 0 END) AS DECIMAL(19,2)) AS "本期末·金额",
               CAST(SUM(CASE WHEN X."W" = 'C' THEN X."Amt" ELSE 0 END) * 100 / NULLIF(:tot, 0) AS DECIMAL(19,4)) AS "本期末·占比 %",
               CAST(SUM(CASE WHEN X."W" = 'P' THEN X."Amt" ELSE 0 END) AS DECIMAL(19,2)) AS "对比期末·金额",
               CAST(SUM(CASE WHEN X."W" = 'C' THEN X."Amt" ELSE -X."Amt" END) AS DECIMAL(19,2)) AS "变动",
               MAX(L."LastDate") AS "最后动账日期", MONTHS_BETWEEN(MAX(L."LastDate"), :d1) AS "无动账月数"
          FROM :c2 X LEFT JOIN :lst L ON X."Kind" = 'STOCK' AND L."ItemCode" = X."ItemCode"
         GROUP BY X."Cls", X."Grp", X."ItemCode"
         ORDER BY X."Cls", LPAD(IFNULL(X."Grp", ''), 10, '0'), SUM(CASE WHEN X."W" = 'C' THEN X."Amt" ELSE 0 END) DESC;
    ELSE
        -- 分组键先在子查询里算好（HANA 不认 SELECT / GROUP BY 中带参数的 CASE 是同一表达式）
        SELECT X."Cls" AS "存货类别", X."KGrp" AS "物料组", MAX(G."ItmsGrpNam") AS "物料组名称",
               COUNT(DISTINCT CASE WHEN X."W" = 'C' THEN X."ItemCode" END) AS "物料数",
               CAST(SUM(CASE WHEN X."W" = 'C' THEN X."Amt" ELSE 0 END) AS DECIMAL(19,2)) AS "本期末·金额",
               CAST(SUM(CASE WHEN X."W" = 'C' THEN X."Amt" ELSE 0 END) * 100 / NULLIF(:tot, 0) AS DECIMAL(19,4)) AS "本期末·占比 %",
               CAST(SUM(CASE WHEN X."W" = 'P' THEN X."Amt" ELSE 0 END) AS DECIMAL(19,2)) AS "对比期末·金额",
               CAST(SUM(CASE WHEN X."W" = 'C' THEN X."Amt" ELSE -X."Amt" END) AS DECIMAL(19,2)) AS "变动",
               CAST(SUM(CASE WHEN X."W" = 'C' THEN X."Amt" ELSE -X."Amt" END) * 100 / NULLIF(SUM(CASE WHEN X."W" = 'P' THEN X."Amt" ELSE 0 END), 0) AS DECIMAL(19,2)) AS "变动 %"
          FROM (SELECT C.*, CASE WHEN :STYPE = '1' THEN C."Grp" END AS "KGrp" FROM :c2 C) X
          LEFT JOIN "OITB" G ON TO_NVARCHAR(G."ItmsGrpCod") = X."KGrp"
         GROUP BY X."Cls", X."KGrp"
         ORDER BY CASE X."Cls" WHEN '原材料' THEN 1 WHEN '半成品' THEN 2 WHEN '产成品' THEN 3 WHEN '在产品' THEN 4 WHEN '发出商品' THEN 5 ELSE 6 END,
                  LPAD(IFNULL(X."KGrp", ''), 10, '0');
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R19 在产品汇总表（用户 2026-11-01）：期初在产品 + 本期领料 + 本级分摊 − 完工转出 − 关单差异 = 期末在产品（四项），
--     按订单类型 / 产品 / 材料 / 订单汇总。
-- 参数：FcFrom, FcTo, WorType 订单类型, Item 产品, ItemGrp 产品物料组, Mat 材料, NonZero 只看有在产品或本期有发生（Y / N）,
--       STYPE 0 按订单类型 / 1 按产品 / 2 按材料 / 3 按订单
-- 口径：MTC_CA_R_ORDER_MAT（期初 = 期初累计领料 − 期初累计结转；本期领料、完工转出、关单差异、期末在产品四项；'#SUBFEE' = 委外加工费）
--       + MTC_CA_R_ORDER 本级分摊（人工 + 制造）。本级分摊按本期入库分配，全部随完工转出，不留在在产品里；按材料显示时单列一行“本级分摊”。
--       填了材料条件时只看这些材料，不含本级分摊。核算类别：订单类型在参数 WW_WORTYPES 的为“委外”（期末在产品 = 140801 材料 + 140802 加工费），其余为“生产”。
--       多个账期：期初取第一个账期、期末取最后一个账期，本期各项累加。“勾稽差额”应为 0。
-- 勾稽：期末在产品合计 = R01 期末在产品 = R09 在产品业务端（V12）；订单 × 材料勾稽差额 = 0（V13）；本期期初 = 上期期末（V14）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_19_WIPSUM" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN WorType NVARCHAR(100), IN Item NVARCHAR(5000), IN ItemGrp NVARCHAR(5000),
    IN Mat NVARCHAR(5000), IN NonZero NVARCHAR(1), IN STYPE NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE nWt INT; DECLARE nItem INT; DECLARE nGrp INT; DECLARE nMat INT; DECLARE fA NVARCHAR(10); DECLARE fB NVARCHAR(10);
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    SELECT MIN("FcCode"), MAX("FcCode") INTO fA, fB FROM :runs;
    lWt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:WorType); SELECT COUNT(*) INTO nWt FROM :lWt;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);    SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp); SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lMat  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Mat);     SELECT COUNT(*) INTO nMat FROM :lMat;
    ord = SELECT U."FcCode", O."RunId", O."OrderType", O."OrderEntry", S."OrderNum", O."WorType", O."ItemCode", S."CardCode", S."StatusAtEnd", O."ClosedInFc",
                 O."PlannedQty", O."PrevRecvQty" + O."RecvQty" AS "CumQ", O."AllocLab" + O."AllocMfg" AS "Alloc",
                 CASE WHEN LOCATE(IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', U."FcCode"), ',50,'), ',' || IFNULL(O."WorType", '') || ',') > 0 THEN '委外' ELSE '生产' END AS "Cat"
            FROM :runs U
            JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
            LEFT JOIN "MTC_CA_S_ORDER" S ON S."RunId" = O."RunId" AND S."OrderType" = O."OrderType" AND S."OrderEntry" = O."OrderEntry"
            LEFT JOIN "OITM" M ON M."ItemCode" = O."ItemCode"
           WHERE (:nWt = 0 OR EXISTS (SELECT 1 FROM :lWt X WHERE O."WorType" = X."V"))
             AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE O."ItemCode" LIKE X."P"))
             AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"));
    -- 一行 = 账期 × 订单 × 材料；本级分摊作为材料 '#ALLOC' 的一行（本期投入 = 完工转出 = 分摊额）
    d = SELECT O."FcCode", O."OrderType", O."OrderEntry", O."OrderNum", O."WorType", O."ItemCode", O."CardCode", O."StatusAtEnd", O."ClosedInFc",
               O."PlannedQty", O."CumQ", O."Cat", X."ItemCode" AS "Mat",
               X."OpenIssMat" - X."OpenCarMat" AS "BMat", X."OpenIssLab" - X."OpenCarLab" AS "BLab",
               X."OpenIssMfg" - X."OpenCarMfg" AS "BMfg", X."OpenIssSub" - X."OpenCarSub" AS "BSub",
               X."IssMat" + X."IssLab" + X."IssMfg" + X."IssSub" AS "Iss", CAST(0 AS DECIMAL(19,6)) AS "Alc",
               X."CarMat" + X."CarLab" + X."CarMfg" + X."CarSub" AS "Car", X."ClsMat" + X."ClsLab" + X."ClsMfg" + X."ClsSub" AS "Cls",
               X."WipMat" AS "WMat", X."WipLab" AS "WLab", X."WipMfg" AS "WMfg", X."WipSub" AS "WSub"
          FROM :ord O
          JOIN "MTC_CA_R_ORDER_MAT" X ON X."RunId" = O."RunId" AND X."OrderType" = O."OrderType" AND X."OrderEntry" = O."OrderEntry"
         WHERE (:nMat = 0 OR EXISTS (SELECT 1 FROM :lMat L WHERE X."ItemCode" LIKE L."P"))
        UNION ALL
        SELECT O."FcCode", O."OrderType", O."OrderEntry", O."OrderNum", O."WorType", O."ItemCode", O."CardCode", O."StatusAtEnd", O."ClosedInFc",
               O."PlannedQty", O."CumQ", O."Cat", '#ALLOC',
               CAST(0 AS DECIMAL(19,6)), CAST(0 AS DECIMAL(19,6)), CAST(0 AS DECIMAL(19,6)), CAST(0 AS DECIMAL(19,6)),
               CAST(0 AS DECIMAL(19,6)), O."Alloc", O."Alloc", CAST(0 AS DECIMAL(19,6)),
               CAST(0 AS DECIMAL(19,6)), CAST(0 AS DECIMAL(19,6)), CAST(0 AS DECIMAL(19,6)), CAST(0 AS DECIMAL(19,6))
          FROM :ord O
         WHERE :nMat = 0 AND O."Alloc" <> 0;
    -- 分组键先在子查询里算好（HANA 不认 SELECT / GROUP BY 中带参数的 CASE 是同一表达式）
    g = SELECT "KCat", "KWt", "KProd", "KMat", "KOT", "KOE",
               COUNT(DISTINCT "OrderType" || '-' || TO_NVARCHAR("OrderEntry")) AS "Cnt",
               MAX("OrderNum") AS "OrderNum", MAX("CardCode") AS "CardCode", MAX("ClosedInFc") AS "ClosedInFc",
               MAX(CASE WHEN "FcCode" = :fB THEN "StatusAtEnd" END) AS "StatusAtEnd",
               MAX("PlannedQty") AS "PlannedQty", MAX(CASE WHEN "FcCode" = :fB THEN "CumQ" END) AS "CumQ",
               SUM(CASE WHEN "FcCode" = :fA THEN "BMat" ELSE 0 END) AS "BMat", SUM(CASE WHEN "FcCode" = :fA THEN "BLab" ELSE 0 END) AS "BLab",
               SUM(CASE WHEN "FcCode" = :fA THEN "BMfg" ELSE 0 END) AS "BMfg", SUM(CASE WHEN "FcCode" = :fA THEN "BSub" ELSE 0 END) AS "BSub",
               SUM("Iss") AS "Iss", SUM("Alc") AS "Alc", SUM("Car") AS "Car", SUM("Cls") AS "Cls",
               SUM(CASE WHEN "FcCode" = :fB THEN "WMat" ELSE 0 END) AS "WMat", SUM(CASE WHEN "FcCode" = :fB THEN "WLab" ELSE 0 END) AS "WLab",
               SUM(CASE WHEN "FcCode" = :fB THEN "WMfg" ELSE 0 END) AS "WMfg", SUM(CASE WHEN "FcCode" = :fB THEN "WSub" ELSE 0 END) AS "WSub"
          FROM (SELECT D.*,
                       CASE WHEN :STYPE IN ('0', '3') OR IFNULL(:STYPE, '') = '' THEN "Cat" END AS "KCat",
                       CASE WHEN :STYPE IN ('0', '3') OR IFNULL(:STYPE, '') = '' THEN "WorType" END AS "KWt",
                       CASE WHEN :STYPE IN ('1', '3') THEN "ItemCode" END AS "KProd",
                       CASE WHEN :STYPE = '2' THEN "Mat" END AS "KMat",
                       CASE WHEN :STYPE = '3' THEN "OrderType" END AS "KOT",
                       CASE WHEN :STYPE = '3' THEN "OrderEntry" END AS "KOE"
                  FROM :d D)
         GROUP BY "KCat", "KWt", "KProd", "KMat", "KOT", "KOE";
    r = SELECT G.*, G."BMat" + G."BLab" + G."BMfg" + G."BSub" AS "B", G."WMat" + G."WLab" + G."WMfg" + G."WSub" AS "W"
          FROM :g G
         WHERE IFNULL(:NonZero, 'N') <> 'Y'
            OR ABS(G."BMat") + ABS(G."BLab") + ABS(G."BMfg") + ABS(G."BSub") + ABS(G."Iss") + ABS(G."Alc") + ABS(G."Car") + ABS(G."Cls")
             + ABS(G."WMat") + ABS(G."WLab") + ABS(G."WMfg") + ABS(G."WSub") >= 0.005;
    IF :STYPE = '1' THEN
        SELECT R."KProd" AS "产品", M."ItemName" AS "产品名称", TO_NVARCHAR(M."ItmsGrpCod") AS "物料组", R."Cnt" AS "订单数",
               CAST(R."BMat" AS DECIMAL(19,2)) AS "期初在产品·材料", CAST(R."BLab" AS DECIMAL(19,2)) AS "期初在产品·人工",
               CAST(R."BMfg" AS DECIMAL(19,2)) AS "期初在产品·制造", CAST(R."BSub" AS DECIMAL(19,2)) AS "期初在产品·委外", CAST(R."B" AS DECIMAL(19,2)) AS "期初在产品·合计",
               CAST(R."Iss" AS DECIMAL(19,2)) AS "本期·领料", CAST(R."Alc" AS DECIMAL(19,2)) AS "本期·本级分摊",
               CAST(R."Car" AS DECIMAL(19,2)) AS "本期·完工转出", CAST(R."Cls" AS DECIMAL(19,2)) AS "本期·关单差异",
               CAST(R."WMat" AS DECIMAL(19,2)) AS "期末在产品·材料", CAST(R."WLab" AS DECIMAL(19,2)) AS "期末在产品·人工",
               CAST(R."WMfg" AS DECIMAL(19,2)) AS "期末在产品·制造", CAST(R."WSub" AS DECIMAL(19,2)) AS "期末在产品·委外", CAST(R."W" AS DECIMAL(19,2)) AS "期末在产品·合计",
               CAST(R."B" + R."Iss" + R."Alc" - R."Car" - R."Cls" - R."W" AS DECIMAL(19,2)) AS "勾稽差额"
          FROM :r R LEFT JOIN "OITM" M ON M."ItemCode" = R."KProd"
         ORDER BY R."KProd";
    ELSEIF :STYPE = '2' THEN
        SELECT R."KMat" AS "材料",
               CASE R."KMat" WHEN '#SUBFEE' THEN '委外加工费' WHEN '#ALLOC' THEN '本级分摊（人工 + 制造，随完工全部转出）' ELSE M."ItemName" END AS "材料名称",
               TO_NVARCHAR(M."ItmsGrpCod") AS "物料组", R."Cnt" AS "订单数",
               CAST(R."BMat" AS DECIMAL(19,2)) AS "期初在产品·材料", CAST(R."BLab" AS DECIMAL(19,2)) AS "期初在产品·人工",
               CAST(R."BMfg" AS DECIMAL(19,2)) AS "期初在产品·制造", CAST(R."BSub" AS DECIMAL(19,2)) AS "期初在产品·委外", CAST(R."B" AS DECIMAL(19,2)) AS "期初在产品·合计",
               CAST(R."Iss" AS DECIMAL(19,2)) AS "本期·领料", CAST(R."Alc" AS DECIMAL(19,2)) AS "本期·本级分摊",
               CAST(R."Car" AS DECIMAL(19,2)) AS "本期·完工转出", CAST(R."Cls" AS DECIMAL(19,2)) AS "本期·关单差异",
               CAST(R."WMat" AS DECIMAL(19,2)) AS "期末在产品·材料", CAST(R."WLab" AS DECIMAL(19,2)) AS "期末在产品·人工",
               CAST(R."WMfg" AS DECIMAL(19,2)) AS "期末在产品·制造", CAST(R."WSub" AS DECIMAL(19,2)) AS "期末在产品·委外", CAST(R."W" AS DECIMAL(19,2)) AS "期末在产品·合计",
               CAST(R."B" + R."Iss" + R."Alc" - R."Car" - R."Cls" - R."W" AS DECIMAL(19,2)) AS "勾稽差额"
          FROM :r R LEFT JOIN "OITM" M ON M."ItemCode" = R."KMat"
         ORDER BY CASE R."KMat" WHEN '#SUBFEE' THEN 1 WHEN '#ALLOC' THEN 2 ELSE 0 END, R."KMat";
    ELSEIF :STYPE = '3' THEN
        SELECT R."KCat" AS "核算类别", R."KOT" AS "订单单据", R."OrderNum" AS "订单号 Num", R."KOE" AS "订单 Entry", R."KWt" AS "订单类型",
               R."KProd" AS "产品", M."ItemName" AS "产品名称", R."CardCode" AS "委外供应商", R."StatusAtEnd" AS "期末状态", R."ClosedInFc" AS "按关单处理",
               CAST(R."PlannedQty" AS DECIMAL(19,6)) AS "计划数", CAST(R."CumQ" AS DECIMAL(19,6)) AS "累计完工",
               CAST(R."CumQ" * 100 / NULLIF(R."PlannedQty", 0) AS DECIMAL(19,2)) AS "完工率 %",
               CAST(R."BMat" AS DECIMAL(19,2)) AS "期初在产品·材料", CAST(R."BLab" AS DECIMAL(19,2)) AS "期初在产品·人工",
               CAST(R."BMfg" AS DECIMAL(19,2)) AS "期初在产品·制造", CAST(R."BSub" AS DECIMAL(19,2)) AS "期初在产品·委外", CAST(R."B" AS DECIMAL(19,2)) AS "期初在产品·合计",
               CAST(R."Iss" AS DECIMAL(19,2)) AS "本期·领料", CAST(R."Alc" AS DECIMAL(19,2)) AS "本期·本级分摊",
               CAST(R."Car" AS DECIMAL(19,2)) AS "本期·完工转出", CAST(R."Cls" AS DECIMAL(19,2)) AS "本期·关单差异",
               CAST(R."WMat" AS DECIMAL(19,2)) AS "期末在产品·材料", CAST(R."WLab" AS DECIMAL(19,2)) AS "期末在产品·人工",
               CAST(R."WMfg" AS DECIMAL(19,2)) AS "期末在产品·制造", CAST(R."WSub" AS DECIMAL(19,2)) AS "期末在产品·委外", CAST(R."W" AS DECIMAL(19,2)) AS "期末在产品·合计",
               CAST(R."B" + R."Iss" + R."Alc" - R."Car" - R."Cls" - R."W" AS DECIMAL(19,2)) AS "勾稽差额"
          FROM :r R LEFT JOIN "OITM" M ON M."ItemCode" = R."KProd"
         ORDER BY R."KCat", R."KOT", R."KOE";
    ELSE
        SELECT R."KCat" AS "核算类别", R."KWt" AS "订单类型", R."Cnt" AS "订单数",
               CAST(R."BMat" AS DECIMAL(19,2)) AS "期初在产品·材料", CAST(R."BLab" AS DECIMAL(19,2)) AS "期初在产品·人工",
               CAST(R."BMfg" AS DECIMAL(19,2)) AS "期初在产品·制造", CAST(R."BSub" AS DECIMAL(19,2)) AS "期初在产品·委外", CAST(R."B" AS DECIMAL(19,2)) AS "期初在产品·合计",
               CAST(R."Iss" AS DECIMAL(19,2)) AS "本期·领料", CAST(R."Alc" AS DECIMAL(19,2)) AS "本期·本级分摊",
               CAST(R."Car" AS DECIMAL(19,2)) AS "本期·完工转出", CAST(R."Cls" AS DECIMAL(19,2)) AS "本期·关单差异",
               CAST(R."WMat" AS DECIMAL(19,2)) AS "期末在产品·材料", CAST(R."WLab" AS DECIMAL(19,2)) AS "期末在产品·人工",
               CAST(R."WMfg" AS DECIMAL(19,2)) AS "期末在产品·制造", CAST(R."WSub" AS DECIMAL(19,2)) AS "期末在产品·委外", CAST(R."W" AS DECIMAL(19,2)) AS "期末在产品·合计",
               CAST(R."B" + R."Iss" + R."Alc" - R."Car" - R."Cls" - R."W" AS DECIMAL(19,2)) AS "勾稽差额"
          FROM :r R
         ORDER BY R."KCat", R."KWt";
    END IF;
END
@@
-- ---------------------------------------------------------------------
-- R20 在产品明细表（用户 2026-11-01）：一行 = 账期 × 订单 × 材料，期初在产品 + 本期领料 − 完工转出 − 关单差异 = 期末在产品（四项）。
-- 参数：FcFrom, FcTo, WorType 订单类型, OrderNum 订单号 Num, Item 产品, ItemGrp 产品物料组, Mat 材料,
--       Scope 范围（空 期末有在产品 / 1 期初或期末有在产品 / 2 全部）
-- 口径：MTC_CA_R_ORDER_MAT（'#SUBFEE' 行 = 委外加工费）；计划用量取订单行快照 MTC_CA_S_ORDER_LINE；按完工折算用量 = 累计完工 × 计划用量 ÷ 计划数。
--       本级分摊随完工全部转出，不在在产品里，这里不列（看 R19 按材料 / R01）。
--       “期末在产品·折算数量” = 累计领料数量 × 期末在产品 ÷ 累计领料金额，只是按金额比例折算的参考数，不是盘点数。
-- 勾稽：同一账期、同一条件下合计 = R19 按材料（不含本级分摊行）；每行勾稽差额 = 0（V13）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE "MTC_CA_RPT_20_WIPDTL" (
    IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN WorType NVARCHAR(100), IN OrderNum NVARCHAR(5000), IN Item NVARCHAR(5000),
    IN ItemGrp NVARCHAR(5000), IN Mat NVARCHAR(5000), IN Scope NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE nWt INT; DECLARE nOrd INT; DECLARE nItem INT; DECLARE nGrp INT; DECLARE nMat INT;
    runs = SELECT "FcCode", "RunId" FROM "MTC_CA_F_RPT_RUN"(:FcFrom, :FcTo) WHERE "RunId" IS NOT NULL;
    lWt   = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:WorType);  SELECT COUNT(*) INTO nWt FROM :lWt;
    lOrd  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:OrderNum); SELECT COUNT(*) INTO nOrd FROM :lOrd;
    lItem = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Item);     SELECT COUNT(*) INTO nItem FROM :lItem;
    lGrp  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:ItemGrp);  SELECT COUNT(*) INTO nGrp FROM :lGrp;
    lMat  = SELECT "V", "P" FROM "MTC_CA_F_RPT_LIST"(:Mat);      SELECT COUNT(*) INTO nMat FROM :lMat;
    ord = SELECT U."FcCode", O."RunId", O."OrderType", O."OrderEntry", S."OrderNum", O."WorType", O."ItemCode", M."ItemName", TO_NVARCHAR(M."ItmsGrpCod") AS "Grp",
                 S."CardCode", S."PostDate", S."StatusAtEnd", O."ClosedInFc", O."PlannedQty", O."PrevRecvQty" + O."RecvQty" AS "CumQ",
                 CASE WHEN LOCATE(IFNULL("MTC_CA_F_PARAM"('WW_WORTYPES', U."FcCode"), ',50,'), ',' || IFNULL(O."WorType", '') || ',') > 0 THEN '委外' ELSE '生产' END AS "Cat"
            FROM :runs U
            JOIN "MTC_CA_R_ORDER" O ON O."RunId" = U."RunId"
            LEFT JOIN "MTC_CA_S_ORDER" S ON S."RunId" = O."RunId" AND S."OrderType" = O."OrderType" AND S."OrderEntry" = O."OrderEntry"
            LEFT JOIN "OITM" M ON M."ItemCode" = O."ItemCode"
           WHERE (:nWt = 0 OR EXISTS (SELECT 1 FROM :lWt X WHERE O."WorType" = X."V"))
             AND (:nOrd = 0 OR EXISTS (SELECT 1 FROM :lOrd X WHERE S."OrderNum" LIKE X."P"))
             AND (:nItem = 0 OR EXISTS (SELECT 1 FROM :lItem X WHERE O."ItemCode" LIKE X."P"))
             AND (:nGrp = 0 OR EXISTS (SELECT 1 FROM :lGrp X WHERE TO_NVARCHAR(M."ItmsGrpCod") = X."V"));
    pl = SELECT L."RunId", L."OrderType", L."OrderEntry", L."ItemCode", SUM(L."PlannedQty") AS "PQ"
           FROM "MTC_CA_S_ORDER_LINE" L JOIN :ord O ON O."RunId" = L."RunId" AND O."OrderType" = L."OrderType" AND O."OrderEntry" = L."OrderEntry"
          GROUP BY L."RunId", L."OrderType", L."OrderEntry", L."ItemCode";
    d = SELECT O.*, X."ItemCode" AS "Mat", P."PQ",
               X."OpenIssQty" + X."IssQty" AS "AQ",
               X."OpenIssMat" + X."OpenIssLab" + X."OpenIssMfg" + X."OpenIssSub" + X."IssMat" + X."IssLab" + X."IssMfg" + X."IssSub" AS "AA",
               X."OpenCarMat" + X."OpenCarLab" + X."OpenCarMfg" + X."OpenCarSub" + X."CarMat" + X."CarLab" + X."CarMfg" + X."CarSub" AS "AC",
               X."OpenIssMat" + X."OpenIssLab" + X."OpenIssMfg" + X."OpenIssSub" - X."OpenCarMat" - X."OpenCarLab" - X."OpenCarMfg" - X."OpenCarSub" AS "B",
               X."IssQty", X."IssMat" + X."IssLab" + X."IssMfg" + X."IssSub" AS "Iss", X."Ratio",
               X."CarMat" + X."CarLab" + X."CarMfg" + X."CarSub" AS "Car", X."ClsMat" + X."ClsLab" + X."ClsMfg" + X."ClsSub" AS "Cls",
               X."WipMat", X."WipLab", X."WipMfg", X."WipSub", X."WipMat" + X."WipLab" + X."WipMfg" + X."WipSub" AS "W"
          FROM :ord O
          JOIN "MTC_CA_R_ORDER_MAT" X ON X."RunId" = O."RunId" AND X."OrderType" = O."OrderType" AND X."OrderEntry" = O."OrderEntry"
          LEFT JOIN :pl P ON P."RunId" = X."RunId" AND P."OrderType" = X."OrderType" AND P."OrderEntry" = X."OrderEntry" AND P."ItemCode" = X."ItemCode"
         WHERE (:nMat = 0 OR EXISTS (SELECT 1 FROM :lMat L WHERE X."ItemCode" LIKE L."P"));
    SELECT D."FcCode" AS "账期", D."Cat" AS "核算类别", D."OrderType" AS "订单单据", D."OrderNum" AS "订单号 Num", D."OrderEntry" AS "订单 Entry", D."WorType" AS "订单类型",
           D."ItemCode" AS "产品", D."ItemName" AS "产品名称", D."Grp" AS "物料组", D."CardCode" AS "委外供应商", D."PostDate" AS "订单日期",
           D."StatusAtEnd" AS "期末状态", D."ClosedInFc" AS "按关单处理",
           CAST(D."PlannedQty" AS DECIMAL(19,6)) AS "计划数", CAST(D."CumQ" AS DECIMAL(19,6)) AS "累计完工",
           CAST(D."CumQ" * 100 / NULLIF(D."PlannedQty", 0) AS DECIMAL(19,2)) AS "完工率 %",
           D."Mat" AS "材料", CASE WHEN D."Mat" = '#SUBFEE' THEN '委外加工费' ELSE I."ItemName" END AS "材料名称",
           CAST(D."PQ" AS DECIMAL(19,6)) AS "用量·计划用量",
           CAST(CASE WHEN IFNULL(D."PlannedQty", 0) > 0 AND D."PQ" IS NOT NULL THEN D."CumQ" * D."PQ" / D."PlannedQty" END AS DECIMAL(19,6)) AS "用量·按完工折算",
           CAST(D."AQ" AS DECIMAL(19,6)) AS "用量·累计领料",
           CAST(D."AA" AS DECIMAL(19,2)) AS "累计·领料金额", CAST(D."AC" AS DECIMAL(19,2)) AS "累计·完工转出", CAST(D."Ratio" AS DECIMAL(19,6)) AS "本期结转比例",
           CAST(D."B" AS DECIMAL(19,2)) AS "期初在产品",
           CAST(D."IssQty" AS DECIMAL(19,6)) AS "本期领料·数量", CAST(D."Iss" AS DECIMAL(19,2)) AS "本期领料·金额",
           CAST(D."Car" AS DECIMAL(19,2)) AS "本期完工转出", CAST(D."Cls" AS DECIMAL(19,2)) AS "本期关单差异",
           CAST(D."WipMat" AS DECIMAL(19,2)) AS "期末在产品·材料", CAST(D."WipLab" AS DECIMAL(19,2)) AS "期末在产品·人工",
           CAST(D."WipMfg" AS DECIMAL(19,2)) AS "期末在产品·制造", CAST(D."WipSub" AS DECIMAL(19,2)) AS "期末在产品·委外",
           CAST(D."W" AS DECIMAL(19,2)) AS "期末在产品·合计",
           CAST(CASE WHEN D."Mat" <> '#SUBFEE' THEN D."AQ" * D."W" / NULLIF(D."AA", 0) END AS DECIMAL(19,6)) AS "期末在产品·折算数量",
           CAST(D."B" + D."Iss" - D."Car" - D."Cls" - D."W" AS DECIMAL(19,2)) AS "勾稽差额"
      FROM :d D
      LEFT JOIN "OITM" I ON I."ItemCode" = D."Mat"
     WHERE CASE WHEN IFNULL(:Scope, '') = '' THEN CASE WHEN ABS(D."W") >= 0.005 THEN 1 ELSE 0 END
                WHEN :Scope = '1' THEN CASE WHEN ABS(D."W") >= 0.005 OR ABS(D."B") >= 0.005 THEN 1 ELSE 0 END
                ELSE 1 END = 1
     ORDER BY D."FcCode", D."Cat", D."OrderType", D."OrderEntry", CASE WHEN D."Mat" = '#SUBFEE' THEN 1 ELSE 0 END, D."Mat";
END
