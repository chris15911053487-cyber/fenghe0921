-- R10 凭证代码、科目编码两列输出英文字段名 TransCode、AcctCode（用户 2026-11-07）。只重建过程 MTC_CA_RPT_10_JV，定义同 21_reports.sql；参数不变，B1 里已登记的 R10 不用重新登记；执行台要同时更新（否则钻取取不到这两列）。
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
        SELECT S."TransCode" AS "TransCode", S."AcctCode" AS "AcctCode", A."AcctName" AS "科目名称", S."OcrCode" AS "成本中心", S."VendorCode" AS "供应商",
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
        SELECT J."TransCode" AS "TransCode", J."TransName" AS "凭证名称", J."LineNo" AS "行号", J."RefDate" AS "过账日期", J."AcctCode" AS "AcctCode", A."AcctName" AS "科目名称",
               J."OcrCode" AS "成本中心", J."Project" AS "项目", J."VendorCode" AS "供应商", J."Debit" AS "借方", J."Credit" AS "贷方"
          FROM "MTC_CA_R_JDT" J LEFT JOIN "OACT" A ON A."AcctCode" = J."AcctCode"
         WHERE J."RunId" = :rid
           AND (:nTc = 0 OR EXISTS (SELECT 1 FROM :lTc X WHERE J."TransCode" = X."V"))
           AND (:nAcct = 0 OR EXISTS (SELECT 1 FROM :lAcct X WHERE J."AcctCode" LIKE X."P"))
         ORDER BY J."TransCode", J."LineNo";
    ELSE
        SELECT J."TransCode" AS "TransCode", MAX(IFNULL(T."TrnsCodDsc", J."TransName")) AS "凭证名称", COUNT(*) AS "分录行数",
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
