-- =====================================================================
-- 2026-11-11 凭证借贷方向统一同旧框架（用户 2026-11-11）
-- 起因：新框架 P70 按 凭证代码 × 科目 汇总后按净额正负分借贷，和旧 0801 / COJZ / 6101_1 不一样：
--   旧框架每条分录规则自己定借方或贷方，金额为负时在原方向记红字（负数），不换方向；同一科目借贷两边都有时各一行、不轧差。
--   新框架原来只有 YF01 / IO01（参数 JDT_RED_DEBIT_TRANSCODES）、PUR1 / PUR4、JZ05 按旧做法，其他按正负换方向，例如
--   PP04 的 510199 为负时记到借方（旧：贷方红字）、JZ01 / JZ03 记成一借一贷（旧：两行都在借方）、IO02 同一存货科目借贷轧差成一行、
--   PUR5 / PUR2 / PUR3 冲回系统凭证时换到另一方（旧：原方向红字冲销）。
-- ① R_JDT_SRC 加列 Side（D / C）：P70 / P74 每条规则写明方向（对照见设计稿 4.5 “借贷方向”），P70 按 凭证代码 × 方向 × 科目 × 成本中心 × 项目 × 供应商 汇总，
--    借方 = 金额、贷方 = −金额，可为负数。Amount 的符号含义不变（正 = 借方效果），对账、PP04、尾差、校验都不受影响。
-- ② 取消参数 JDT_RED_DEBIT_TRANSCODES（全部凭证代码都固定方向，不再需要）。B1 @MTC_CA_PARAM 里已经加了这一行的，删掉它
--    （否则“检查 B1 配置”报参数代码不认识）。
-- ③ R10 来源明细按 Side 列借贷、分录号按方向匹配（下面重建 MTC_CA_RPT_10_JV，定义同 21_reports.sql）；执行台凭证页来源明细同样（actions.json）。
-- 已部署的库：执行本文件，再执行 16_p70_jdt.sql（重建 P74 / P70），然后重新计算（已生成凭单的账期按设计稿 8.6 先撤销再重算）；
--   服务器模式重新 pack_server.py 打包并重启。B1 公司设置要允许负数金额（2026-11-08 起已需要）。
-- 未编译。改前备份 _backup/*_20261111_before_jdtside.*
-- =====================================================================
DO BEGIN
    DECLARE n INT;
    SELECT COUNT(*) INTO n FROM SYS.TABLE_COLUMNS
     WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = 'MTC_CA_R_JDT_SRC' AND COLUMN_NAME = 'Side';
    IF :n = 0 THEN
        EXEC 'ALTER TABLE "MTC_CA_R_JDT_SRC" ADD ("Side" NVARCHAR(1))';
    END IF;
END
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."Amount" IS '正 = 借方效果，负 = 贷方效果；记在哪一方看 Side'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."Side" IS 'D 记借方（借方 = Amount）/ C 记贷方（贷方 = −Amount）；由规则固定，金额为负时红字不换方向（同旧 0801，用户 2026-11-11）；历史回填为空'
@@
DELETE FROM "MTC_CA_C_PARAM" WHERE "ParamCode" = 'JDT_RED_DEBIT_TRANSCODES'
@@
DELETE FROM "MTC_CA_C_PARAM_DEF" WHERE "ParamCode" = 'JDT_RED_DEBIT_TRANSCODES'
@@
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
    -- B1 交易号（用户 2026-11-11）：MTC_CA_JV 最新已生成的凭单批号 → 过账后的 OJDT（同 BatchNum、TransCode；不含 B1 自动冲销的 StornoToTr 凭证）；
    --   待过账、已在 B1 删除的没有。行：执行台按分录号顺序写凭单，Line_ID = 分录号 − 1，再核对科目（FormatCode 换 AcctCode，同 dev_server SQL_JV_LINES）
    --   和借 − 贷金额，对不上的留空
    jv = SELECT G."TransCode", G."BatchNum", MAX(H."TransId") AS "TransId", MAX(H."Number") AS "Number", MAX(H."U_CWNum") AS "U_CWNum"
           FROM (SELECT "TransCode", MAX("BatchNum") AS "BatchNum" FROM "MTC_CA_JV"
                  WHERE "FcCode" = :fc AND "RunId" = :rid AND "Status" = 'CREATED' AND "BatchNum" IS NOT NULL GROUP BY "TransCode") G
           LEFT JOIN "OJDT" H ON H."BatchNum" = G."BatchNum" AND H."TransCode" = G."TransCode" AND H."StornoToTr" IS NULL
          GROUP BY G."TransCode", G."BatchNum";
    jl = SELECT J."TransCode", J."LineNo", L."TransId", L."Line_ID", V."U_CWNum"
           FROM :jv V
           JOIN "MTC_CA_R_JDT" J ON J."RunId" = :rid AND J."TransCode" = V."TransCode"
           LEFT JOIN "OACT" A1 ON A1."AcctCode" = J."AcctCode"
           LEFT JOIN (SELECT "FormatCode", MAX("AcctCode") AS "AcctCode" FROM "OACT" WHERE IFNULL("FormatCode", '') <> '' GROUP BY "FormatCode") A2
             ON A1."AcctCode" IS NULL AND A2."FormatCode" = J."AcctCode"
           JOIN "JDT1" L ON L."TransId" = V."TransId" AND L."Line_ID" = J."LineNo" - 1
                        AND L."Account" = IFNULL(A1."AcctCode", A2."AcctCode") AND L."Debit" - L."Credit" = J."Debit" - J."Credit";
    IF :STYPE = '2' THEN
        SELECT :fc AS "FcCode", :rid AS "运行号", S."TransCode" AS "TransCode", J."LineNo" AS "分录号", X."TransId" AS "交易号 TransId", X."U_CWNum" AS "财务凭证号 U_CWNum", X."Line_ID" AS "B1 行号 Line_ID", S."AcctCode" AS "AcctCode", A."AcctName" AS "科目名称", S."OcrCode" AS "成本中心", S."VendorCode" AS "供应商",
               CASE S."SrcType" WHEN 'LINE' THEN '单据行' WHEN 'ORDER' THEN '订单' WHEN 'DOC' THEN 'B1 单据行' WHEN 'GL' THEN '总账分录' WHEN 'OMRV' THEN '重估单'
                                WHEN 'ITEM' THEN '物料尾差' ELSE S."SrcType" END AS "来源类型",
               S."SrcKey" AS "来源键",
               -- 借贷方向取 Side（规则固定，可为红字，用户 2026-11-11）；历史回填没有 Side，按正负
               CAST(CASE WHEN IFNULL(S."Side", CASE WHEN S."Amount" > 0 THEN 'D' ELSE 'C' END) = 'D' THEN S."Amount" ELSE 0 END AS DECIMAL(19,2)) AS "借方",
               CAST(CASE WHEN IFNULL(S."Side", CASE WHEN S."Amount" > 0 THEN 'D' ELSE 'C' END) = 'C' THEN -S."Amount" ELSE 0 END AS DECIMAL(19,2)) AS "贷方",
               COALESCE(D."DocDate", CAST(NULL AS DATE)) AS "单据日期",
               "MTC_CA_F_RPT_DTNAME"(COALESCE(D."ObjType", O."OrderType")) AS "单据类型", COALESCE(D."DocNum", O."OrderNum") AS "单号 Num", D."LineNum" AS "行号",
               COALESCE(L."ItemCode", O."ItemCode") AS "物料", L."TransCode" AS "交易类型", CAST(L."Qty" AS DECIMAL(19,6)) AS "数量",
               LO."OrderNum" AS "订单号 Num", S."Note" AS "备注"
          FROM "MTC_CA_R_JDT_SRC" S
          LEFT JOIN "MTC_CA_R_LINE" L ON S."SrcType" = 'LINE' AND L."RunId" = S."RunId"
                                     AND L."LineId" = CASE WHEN S."SrcKey" LIKE_REGEXPR '^[0-9]+$' THEN TO_BIGINT(S."SrcKey") END
          LEFT JOIN "MTC_CA_S_LINE" D ON D."RunId" = L."RunId" AND D."LineId" = L."LineId"
          LEFT JOIN "MTC_CA_S_ORDER" LO ON LO."RunId" = L."RunId" AND LO."OrderType" = L."OrderType" AND LO."OrderEntry" = L."OrderEntry"
          LEFT JOIN "MTC_CA_S_ORDER" O ON S."SrcType" = 'ORDER' AND O."RunId" = S."RunId" AND O."OrderType" || '-' || TO_NVARCHAR(O."OrderEntry") = S."SrcKey"
          LEFT JOIN "OACT" A ON A."AcctCode" = S."AcctCode"
          -- 分录号：R_JDT 由 R_JDT_SRC 按 凭证代码 + 方向 + 科目 + 成本中心 + 项目 + 供应商 汇总（P70，空串当 NULL），同样的键找回；这组来源合计为 0 时没有分录，分录号为空
          --   方向：借方行 Debit <> 0，贷方行 Debit = 0；历史回填的来源没有 Side，不比方向
          LEFT JOIN "MTC_CA_R_JDT" J ON J."RunId" = S."RunId" AND J."TransCode" = S."TransCode" AND IFNULL(J."AcctCode", '') = IFNULL(S."AcctCode", '')
                                    AND IFNULL(J."OcrCode", '') = IFNULL(S."OcrCode", '') AND IFNULL(J."Project", '') = IFNULL(S."Project", '')
                                    AND IFNULL(J."VendorCode", '') = IFNULL(S."VendorCode", '')
                                    AND (S."Side" IS NULL OR S."Side" = CASE WHEN J."Debit" <> 0 THEN 'D' ELSE 'C' END)
          LEFT JOIN :jl X ON X."TransCode" = J."TransCode" AND X."LineNo" = J."LineNo"
         WHERE S."RunId" = :rid
           AND (:nTc = 0 OR EXISTS (SELECT 1 FROM :lTc X WHERE S."TransCode" = X."V"))
           AND (:nAcct = 0 OR EXISTS (SELECT 1 FROM :lAcct X WHERE S."AcctCode" LIKE X."P"))
         ORDER BY S."TransCode", J."LineNo", S."AcctCode", S."OcrCode", S."SrcId";
    ELSEIF :STYPE = '1' THEN
        SELECT :fc AS "FcCode", :rid AS "运行号", J."TransCode" AS "TransCode", J."TransName" AS "凭证名称", J."LineNo" AS "分录号", X."TransId" AS "交易号 TransId", X."U_CWNum" AS "财务凭证号 U_CWNum", X."Line_ID" AS "B1 行号 Line_ID", J."RefDate" AS "过账日期", J."AcctCode" AS "AcctCode", A."AcctName" AS "科目名称",
               J."OcrCode" AS "成本中心", J."Project" AS "项目", J."VendorCode" AS "供应商", J."Debit" AS "借方", J."Credit" AS "贷方"
          FROM "MTC_CA_R_JDT" J LEFT JOIN "OACT" A ON A."AcctCode" = J."AcctCode"
          LEFT JOIN :jl X ON X."TransCode" = J."TransCode" AND X."LineNo" = J."LineNo"
         WHERE J."RunId" = :rid
           AND (:nTc = 0 OR EXISTS (SELECT 1 FROM :lTc X WHERE J."TransCode" = X."V"))
           AND (:nAcct = 0 OR EXISTS (SELECT 1 FROM :lAcct X WHERE J."AcctCode" LIKE X."P"))
         ORDER BY J."TransCode", J."LineNo";
    ELSE
        SELECT :fc AS "FcCode", :rid AS "运行号", J."TransCode" AS "TransCode", MAX(IFNULL(T."TrnsCodDsc", J."TransName")) AS "凭证名称", COUNT(*) AS "分录行数",
               SUM(J."Debit") AS "借方", SUM(J."Credit") AS "贷方", CAST(SUM(J."Debit") - SUM(J."Credit") AS DECIMAL(19,2)) AS "借贷差",
               MAX(V."BatchNum") AS "凭单批号", IFNULL(MAX(V."B1State"), '未生成凭单') AS "B1 状态",
               MAX(X."TransId") AS "交易号 TransId", MAX(X."Number") AS "凭证编号 Number", MAX(X."U_CWNum") AS "财务凭证号 U_CWNum",
               MAX(V."CreateUser") AS "生成人", MAX(V."CreateTime") AS "生成时间"
          FROM "MTC_CA_R_JDT" J
          LEFT JOIN "OTRC" T ON T."TrnsCode" = J."TransCode"
          LEFT JOIN (SELECT G."TransCode", G."BatchNum", G."CreateUser", G."CreateTime",
                            CASE WHEN EXISTS (SELECT 1 FROM "OBTF" B WHERE B."BatchNum" = G."BatchNum" AND B."BtfStatus" = 'O') THEN '待过账'
                                 WHEN EXISTS (SELECT 1 FROM "OJDT" H WHERE H."BatchNum" = G."BatchNum") THEN '已过账' ELSE '已在 B1 删除' END AS "B1State"
                       FROM (SELECT "TransCode", MAX("BatchNum") AS "BatchNum", MAX("CreateUser") AS "CreateUser", MAX("CreateTime") AS "CreateTime"
                               FROM "MTC_CA_JV" WHERE "FcCode" = :fc AND "RunId" = :rid AND "Status" = 'CREATED' AND "BatchNum" IS NOT NULL
                              GROUP BY "TransCode") G) V ON V."TransCode" = J."TransCode"
          LEFT JOIN :jv X ON X."TransCode" = J."TransCode"
         WHERE J."RunId" = :rid
           AND (:nTc = 0 OR EXISTS (SELECT 1 FROM :lTc X WHERE J."TransCode" = X."V"))
           AND (:nAcct = 0 OR EXISTS (SELECT 1 FROM :lAcct X WHERE J."AcctCode" LIKE X."P"))
         GROUP BY J."TransCode" ORDER BY J."TransCode";
    END IF;
END
@@
