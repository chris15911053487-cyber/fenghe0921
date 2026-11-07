-- =====================================================================
-- 2026-10-30 PUR1–PUR5（用户 2026-10-30，设计稿 4.6.1）
-- ① POST-15 逐单据勾稽：新函数 MTC_CA_F_PUR_DOC；P75 增加 POST-15；P_CHECK_PUT 允许参数 POST_WARN_IDS 中的计算后校验只警告；
--    新参数 POST_WARN_IDS、INITPRICE_NEW_FROM、PUR_STDVAR_ACCTS（参数目录）。
-- ② 委外加工费方案 B：PUR4 与计入订单的加工费都按暂估口径（指定单价 U_InitPrice → 已确认价 → LineTotal）。
--    P20_AP 不变（材料、加工费同一规则）；P20_SUBFEE 收货 / 退货金额改取 S_AP_MOVE（原来 LineTotal）。旧视图的对应修正见 fixes/MTC_VIEW_ProductDetail.sql。
-- 已部署的库：执行本文件，再执行 18_meta_comments.sql、CALL "MTC_CA_P_META_SYNC"()，然后重新计算。
-- 未编译。改前备份 _backup/*_20261030_before_purchk.*、*_20261030_before_subfeeb.*
-- 【2026-10-31】本文件里的 P20_SUBFEE / P20_LINE 已过期（生产收货 → 订单改用 MTC_CA_F_GI_ORDER），以 07_snapshot_procs.sql / 部署包为准，不要再单独执行本文件。
-- =====================================================================
-- =====================================================================
-- 新成本框架 第 1 期：P10 计算前检查（设计稿第 6 节；替代 CAL_1001_CHECK，只读）
-- 在 P20 快照之后执行，检查快照和 B1 单据；不修改 B1、不重建旧表、不写期初维护价。
-- 结果写 MTC_CA_R_CHECK（每项一行）和 MTC_CA_R_CHECK_DTL（问题明细，每项最多 CHECK_DTL_MAX 行）。
-- 检查项的标题、是否阻断登记在 MTC_CA_C_CHECK；Active='N' 的记为 SKIP。
-- =====================================================================
CREATE OR REPLACE PROCEDURE "MTC_CA_P_CHECK_PUT" (
    IN RunId   BIGINT,
    IN CheckId NVARCHAR(20),
    IN dtl     TABLE ("KeyCode" NVARCHAR(5000), "Info" NVARCHAR(5000)),
    IN Msg     NVARCHAR(1000)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE cnt BIGINT;
    DECLARE blk NVARCHAR(1);
    DECLARE act NVARCHAR(1);
    DECLARE stage NVARCHAR(4);
    DECLARE maxDtl INT;
    DECLARE title NVARCHAR(200);
    DECLARE nDone INT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    maxDtl := TO_INTEGER(IFNULL("MTC_CA_F_PARAM"('CHECK_DTL_MAX', :fc), '200'));
    SELECT IFNULL(MAX("IsBlock"), 'N'), IFNULL(MAX("Active"), 'Y'), IFNULL(MAX("Stage"), 'PRE'), IFNULL(MAX("Title"), '')
      INTO blk, act, stage, title FROM "MTC_CA_C_CHECK" WHERE "CheckId" = :CheckId;
    -- 计算后校验（POST）不通过一律阻断，没有警告（用户 2026-10-14）；
    -- 例外：参数 POST_WARN_IDS 中的检查按 C_CHECK.IsBlock（POST-15 PUR 逐单据勾稽先只警告，用户 2026-10-30）
    IF :stage = 'POST' AND LOCATE(IFNULL("MTC_CA_F_PARAM"('POST_WARN_IDS', :fc), ',POST-15,'), ',' || :CheckId || ',') = 0 THEN blk := 'Y'; END IF;
    SELECT COUNT(*) INTO cnt FROM :dtl;

    INSERT INTO "MTC_CA_R_CHECK" ("FcCode", "RunType", "Scenario", "RunId", "CheckId", "Stage", "Result", "IssueCnt", "IsBlock", "Msg", "CheckTime")
    VALUES (:fc, :rt, :scen, :RunId, :CheckId, :stage,
            CASE WHEN :act = 'N' THEN 'SKIP' WHEN :cnt = 0 THEN 'PASS' WHEN :blk = 'Y' THEN 'FAIL' ELSE 'WARN' END,
            :cnt, :blk, :Msg, CURRENT_TIMESTAMP);

    IF :act = 'Y' AND :cnt > 0 THEN
        INSERT INTO "MTC_CA_R_CHECK_DTL" ("FcCode", "RunType", "Scenario", "RunId", "CheckId", "SeqNo", "KeyCode", "Info")
        SELECT :fc, :rt, :scen, :RunId, :CheckId, "SeqNo", LEFT("KeyCode", 200), LEFT("Info", 1000)
          FROM (SELECT ROW_NUMBER() OVER (ORDER BY "KeyCode", "Info") AS "SeqNo", "KeyCode", "Info" FROM :dtl)
         WHERE "SeqNo" <= :maxDtl;
    END IF;

    -- 执行台进度：已完成几项、刚完成哪一项（不含明细）
    SELECT COUNT(*) INTO nDone FROM "MTC_CA_R_CHECK" WHERE "RunId" = :RunId AND "Stage" = :stage;
    CALL "MTC_CA_P_LOG_NOTE"(:RunId, '已完成 ' || :nDone || ' 项校验，刚完成 ' || :CheckId || ' ' || :title || '：'
         || CASE WHEN :act = 'N' THEN '跳过' WHEN :cnt = 0 THEN '通过' ELSE :cnt || ' 条问题' END);
END
@@
UPSERT "MTC_CA_C_CHECK" ("CheckId", "Stage", "SortNo", "Title", "Purpose", "IsBlock", "Scene") VALUES ('POST-15', 'POST', 215, 'PUR1–PUR5 与业务端逐单据勾稽', 'PUR1–PUR5 把 B1 标准成本自动凭证（收货、退货、发票）在存货、应付暂估、加工费科目上的金额冲掉，按暂估口径（指定单价 U_InitPrice → 已确认价 → LineTotal）重记。逐张单据核对：系统凭证 + PUR 冲回 + PUR 重记（+ MR01）= 业务端（220202 = 暂估变动，存货 = 计入物料成本的金额，140802 = 加工费暂估，140803、价格差异科目、收货单其他科目 = 0）；另报没有系统凭证的单据、已全部开票但暂估没清零的行、PUR4 与订单加工费不一致、非库存收货行、本期新用指定单价的行、已过账 PUR 与底稿不一致（MTC_CA_F_PUR_DOC，用户 2026-10-30）。先只警告（参数 POST_WARN_IDS）', 'N', 'S12') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('POST_WARN_IDS', '0000-00', '9999-99', ',POST-15,', 'LIST', '只警告、不阻断的计算后校验（其余 POST 一律阻断，用户 2026-10-14；POST-15 先只警告，用户 2026-10-30）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('INITPRICE_NEW_FROM', '0000-00', '9999-99', '2026-01-01', 'DATE', '这天及以后的收货 / 退货再用指定单价 U_InitPrice 时 POST-15 报出（期初和上线后系统 Price 有误才用，2026 年起应很少，用户 2026-10-30）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('PUR_STDVAR_ACCTS', 'PARAM', '凭证与对账', 465, 'PUR 勾稽：标准成本差异科目（补充）', 'LIST', NULL, '除物料组的价格差异科目、差异科目外，B1 标准成本凭证还会用到的差异科目；POST-15 要求这些科目在采购单据上净额为 0。逗号分隔，可空') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('INITPRICE_NEW_FROM', 'PARAM', '凭证与对账', 466, '指定单价 U_InitPrice 报出起始日', 'DATE', NULL, 'YYYY-MM-DD；这天及以后的收货 / 退货用了 U_InitPrice 时 POST-15 报出，如 2026-01-01') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM_DEF" ("ParamCode", "Target", "Category", "SortNo", "CnName", "DataType", "Choices", "Hint") VALUES ('POST_WARN_IDS', 'PARAM', '计算控制', 285, '只警告的计算后校验', 'LIST', NULL, '校验编号，逗号分隔，如 POST-15；不在这里的计算后校验一律阻断') WITH PRIMARY KEY
@@
-- 应付暂估变动（替代 6101_1 的 TMP 取数，设计稿 4.6；Q16、Q26–Q28）：
--   暂估行 = 收货行、不基于收货的退货行，物料是库存物料或委外加工费物料（SUBFEE_ITEM）；
--   变动 = 暂估行本身（ACCR）、基于它的退货 / 换货（RET）、发票 / 贷项（INV），以及这些单据的取消单（取原单的相反数，Q26）；
--   开票、退货冲回 = 数量 × 暂估单价，累计数量达到暂估行数量的那一笔 = 整行暂估 − 以前已冲回（Q27）；
--   退货按所基于收货行的暂估单价（Q28）。只保存截至期末仍未清、或本期有变动的暂估行（含其历史变动）。
--   暂估单价（材料、委外加工费相同）：U_InitPrice（期初和上线后系统 Price 有误时的指定单价）→ U_IsPrice='Y' 已确认价 Price × 数量 → LineTotal。
--   委外加工费计入订单的金额（P20_SUBFEE）也取本表，与 PUR4 同一口径（用户 2026-10-30 方案 B）。
-- 委外加工费发票的“发票 − 暂估”差额同时写入 S_LINE（Src='APDIF'，I11，物料 = 发票行 U_ItemCode 的产品），
-- 替代旧 6101_1 PUR3 写的 @MTC_OMRV WW 重估单（新框架不再读 WW 单）。
-- 材料（库存物料）的收货、退货、发票差额：用本表金额覆盖 P20_LINE 按旧 0303 规则算的 S_LINE.SrcAmt，
-- 使物料成本与 PUR1 / PUR2 凭证同一口径（Q29，用户 2026-10-13 同意）；同一单据行有多条 OIVL 时金额放在第一条。
CREATE OR REPLACE PROCEDURE "MTC_CA_P20_AP" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE feeItem NVARCHAR(50); DECLARE difAcct NVARCHAR(15);
    DECLARE maxLine BIGINT; DECLARE n BIGINT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    feeItem := IFNULL("MTC_CA_F_PARAM"('SUBFEE_ITEM', :fc), 'X0510001');
    difAcct := "MTC_CA_F_ACCT"('WW_FEE_DIF', :fc);

    base = SELECT '20' AS "BaseObj", M."DocEntry" AS "BaseEntry", D."LineNum" AS "BaseLine", TO_DATE(M."DocDate") AS "BaseDate",
                  1 AS "BaseSign", D."Quantity" AS "BaseQty", M."CardCode", D."ItemCode",
                  D."U_InitPrice", D."U_IsPrice", D."Price", D."LineTotal"
             FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d1 AND IFNULL(D."BaseType", -1) <> 21
           UNION ALL
           SELECT '21', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), -1, D."Quantity", M."CardCode", D."ItemCode",
                  D."U_InitPrice", D."U_IsPrice", D."Price", D."LineTotal"
             FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d1 AND IFNULL(D."BaseType", -1) <> 20;
    bp = SELECT B."BaseObj", B."BaseEntry", B."BaseLine", B."BaseDate", B."BaseSign", B."BaseQty", B."CardCode", B."ItemCode",
                CASE WHEN B."ItemCode" = :feeItem THEN 'SUBFEE' ELSE 'MAT' END AS "AccrType",
                CASE WHEN IFNULL(B."U_InitPrice", 0) <> 0 THEN B."U_InitPrice" WHEN B."U_IsPrice" = 'Y' THEN B."Price"
                     ELSE B."LineTotal" / NULLIF(B."BaseQty", 0) END AS "UP",
                ROUND(CASE WHEN IFNULL(B."U_InitPrice", 0) <> 0 THEN B."BaseQty" * B."U_InitPrice"
                           WHEN B."U_IsPrice" = 'Y' THEN B."BaseQty" * B."Price" ELSE B."LineTotal" END, 2) AS "FullAmt"
           FROM :base B JOIN "OITM" I ON I."ItemCode" = B."ItemCode"
          WHERE I."InvntItem" = 'Y' OR B."ItemCode" = :feeItem;

    -- 取消单行 → 原单行
    cx = SELECT '20' AS "ObjType", M."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate", '20' AS "OrigObj", D."BaseEntry" AS "OrigEntry", D."BaseLine" AS "OrigLine"
           FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND D."BaseType" = 20 AND M."DocDate" <= :d1
         UNION ALL
         SELECT '21', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '21', D."BaseEntry", D."BaseLine"
           FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND D."BaseType" = 21 AND M."DocDate" <= :d1
         UNION ALL
         SELECT '18', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '18', D."BaseEntry", D."BaseLine"
           FROM "OPCH" M JOIN "PCH1" D ON D."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND D."BaseType" = 18 AND M."DocDate" <= :d1
         UNION ALL
         SELECT '19', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '19', D."BaseEntry", D."BaseLine"
           FROM "ORPC" M JOIN "RPC1" D ON D."DocEntry" = M."DocEntry" WHERE M."CANCELED" = 'C' AND D."BaseType" = 19 AND M."DocDate" <= :d1;

    -- 消耗暂估行的原单：发票 / 贷项（INV）、退货 / 换货（RET）
    cons = SELECT '18' AS "ObjType", M."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate",
                  TO_NVARCHAR(D."BaseType") AS "BaseObj", D."BaseEntry", D."BaseLine", D."Quantity" AS "Q",
                  D."LineTotal" AS "DocAmt", D."U_ItemCode" AS "ProdItem", 'INV' AS "MoveType"
             FROM "OPCH" M JOIN "PCH1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d1 AND D."BaseType" IN (20, 21)
           UNION ALL
           SELECT '19', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), TO_NVARCHAR(D."BaseType"), D."BaseEntry", D."BaseLine", D."Quantity",
                  -D."LineTotal", D."U_ItemCode", 'INV'
             FROM "ORPC" M JOIN "RPC1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d1 AND D."BaseType" IN (20, 21)
           UNION ALL
           SELECT '21', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '20', D."BaseEntry", D."BaseLine", D."Quantity", NULL, NULL, 'RET'
             FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d1 AND D."BaseType" = 20
           UNION ALL
           SELECT '20', M."DocEntry", D."LineNum", TO_DATE(M."DocDate"), '21', D."BaseEntry", D."BaseLine", D."Quantity", NULL, NULL, 'RET'
             FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry"
            WHERE M."CANCELED" <> 'C' AND M."DocDate" <= :d1 AND D."BaseType" = 21;

    -- 原单 + 取消单；先按 数量 × 暂估单价 取整，再找累计数量达到暂估行数量的那一笔
    ev = SELECT B."BaseObj", B."BaseEntry", B."BaseLine", C."ObjType", C."DocEntry", C."LineNum", C."DocDate", 'N' AS "IsCancel",
                C."ObjType" AS "OrigObj", C."DocEntry" AS "OrigEntry", C."LineNum" AS "OrigLine",
                C."Q" AS "CQ", ROUND(C."Q" * B."UP", 2) AS "Simple", C."DocAmt", C."ProdItem", C."MoveType"
           FROM :cons C JOIN :bp B ON B."BaseObj" = C."BaseObj" AND B."BaseEntry" = C."BaseEntry" AND B."BaseLine" = C."BaseLine"
         UNION ALL
         SELECT B."BaseObj", B."BaseEntry", B."BaseLine", X."ObjType", X."DocEntry", X."LineNum", X."DocDate", 'Y',
                C."ObjType", C."DocEntry", C."LineNum",
                -C."Q", -ROUND(C."Q" * B."UP", 2), -C."DocAmt", C."ProdItem", C."MoveType"
           FROM :cx X
           JOIN :cons C ON C."ObjType" = X."OrigObj" AND C."DocEntry" = X."OrigEntry" AND C."LineNum" = X."OrigLine"
           JOIN :bp B ON B."BaseObj" = C."BaseObj" AND B."BaseEntry" = C."BaseEntry" AND B."BaseLine" = C."BaseLine";
    ew = SELECT E.*, B."BaseQty", B."FullAmt",
                SUM(E."CQ") OVER (PARTITION BY E."BaseObj", E."BaseEntry", E."BaseLine"
                                  ORDER BY E."DocDate", E."IsCancel", E."ObjType", E."DocEntry", E."LineNum" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "CumQ",
                SUM(E."Simple") OVER (PARTITION BY E."BaseObj", E."BaseEntry", E."BaseLine"
                                      ORDER BY E."DocDate", E."IsCancel", E."ObjType", E."DocEntry", E."LineNum" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "CumS"
           FROM :ev E JOIN :bp B ON B."BaseObj" = E."BaseObj" AND B."BaseEntry" = E."BaseEntry" AND B."BaseLine" = E."BaseLine";
    eo = SELECT W.*,
                CASE WHEN W."IsCancel" = 'N' AND W."CumQ" >= W."BaseQty" - 0.000001 AND W."CumQ" - W."CQ" < W."BaseQty" - 0.000001
                     THEN W."FullAmt" - (W."CumS" - W."Simple") ELSE W."Simple" END AS "Mag",
                CASE WHEN W."IsCancel" = 'N' AND W."CumQ" >= W."BaseQty" - 0.000001 AND W."CumQ" - W."CQ" < W."BaseQty" - 0.000001
                     THEN 'LAST' ELSE 'ROUND' END AS "Rule"
           FROM :ew W;
    -- 取消单取原单最终金额的相反数（原单若是清余数的那一笔，也按清余数后的金额反向）
    ef = SELECT E."BaseObj", E."BaseEntry", E."BaseLine", E."ObjType", E."DocEntry", E."LineNum", E."DocDate", E."IsCancel",
                E."CQ", CASE WHEN E."IsCancel" = 'Y' THEN -O."Mag" ELSE E."Mag" END AS "Mag",
                CASE WHEN E."IsCancel" = 'Y' THEN 'CANCEL' ELSE E."Rule" END AS "Rule",
                E."DocAmt", E."ProdItem", E."MoveType"
           FROM :eo E
           LEFT JOIN :eo O ON E."IsCancel" = 'Y' AND O."IsCancel" = 'N' AND O."ObjType" = E."OrigObj" AND O."DocEntry" = E."OrigEntry" AND O."LineNum" = E."OrigLine"
                          AND O."BaseObj" = E."BaseObj" AND O."BaseEntry" = E."BaseEntry" AND O."BaseLine" = E."BaseLine";

    mv = SELECT B."BaseObj", B."BaseEntry", B."BaseLine", 'ACCR' AS "MoveType", 'N' AS "IsCancel", B."BaseObj" AS "ObjType",
                B."BaseEntry" AS "DocEntry", B."BaseLine" AS "LineNum", B."BaseDate" AS "DocDate",
                B."BaseQty" AS "Qty", B."BaseSign" * B."FullAmt" AS "AccrAmt", CAST(NULL AS DECIMAL(19,2)) AS "DocAmt",
                CAST(NULL AS NVARCHAR(50)) AS "ProdItem", 'FULL' AS "AmtRule"
           FROM :bp B
         UNION ALL
         SELECT B."BaseObj", B."BaseEntry", B."BaseLine", 'ACCR', 'Y', X."ObjType", X."DocEntry", X."LineNum", X."DocDate",
                -B."BaseQty", -B."BaseSign" * B."FullAmt", NULL, NULL, 'CANCEL'
           FROM :cx X JOIN :bp B ON B."BaseObj" = X."OrigObj" AND B."BaseEntry" = X."OrigEntry" AND B."BaseLine" = X."OrigLine"
         UNION ALL
         SELECT F."BaseObj", F."BaseEntry", F."BaseLine", F."MoveType", F."IsCancel", F."ObjType", F."DocEntry", F."LineNum", F."DocDate",
                -F."CQ", -B."BaseSign" * F."Mag", F."DocAmt", F."ProdItem", F."Rule"
           FROM :ef F JOIN :bp B ON B."BaseObj" = F."BaseObj" AND B."BaseEntry" = F."BaseEntry" AND B."BaseLine" = F."BaseLine";

    keep = SELECT "BaseObj", "BaseEntry", "BaseLine" FROM :mv
            GROUP BY "BaseObj", "BaseEntry", "BaseLine"
           HAVING ABS(SUM("Qty")) > 0.000001 OR ABS(SUM("AccrAmt")) >= 0.005 OR MAX("DocDate") >= :d0;

    INSERT INTO "MTC_CA_S_AP_MOVE" ("FcCode", "RunType", "Scenario", "RunId", "MoveId", "BaseObj", "BaseEntry", "BaseLine", "BaseDate",
        "BaseSign", "BaseQty", "UnitPrice", "FullAmt", "CardCode", "ItemCode", "AccrType", "MoveType", "IsCancel",
        "ObjType", "DocEntry", "LineNum", "DocDate", "Qty", "AccrAmt", "DocAmt", "ProdItem", "AmtRule")
    SELECT :fc, :rt, :scen, :RunId,
           ROW_NUMBER() OVER (ORDER BY M."BaseObj", M."BaseEntry", M."BaseLine", M."DocDate", M."IsCancel", M."ObjType", M."DocEntry", M."LineNum"),
           M."BaseObj", M."BaseEntry", M."BaseLine", B."BaseDate", B."BaseSign", B."BaseQty", B."UP", B."FullAmt", B."CardCode", B."ItemCode",
           B."AccrType", M."MoveType", M."IsCancel", M."ObjType", M."DocEntry", M."LineNum", M."DocDate",
           M."Qty", M."AccrAmt", M."DocAmt", M."ProdItem", M."AmtRule"
      FROM :mv M
      JOIN :keep K ON K."BaseObj" = M."BaseObj" AND K."BaseEntry" = M."BaseEntry" AND K."BaseLine" = M."BaseLine"
      JOIN :bp B ON B."BaseObj" = M."BaseObj" AND B."BaseEntry" = M."BaseEntry" AND B."BaseLine" = M."BaseLine";
    RowCnt := ::ROWCOUNT;

    -- 材料的收货 / 退货 / 发票差额改取暂估口径（Q29）：存货影响 = 暂估、退货的 AccrAmt；发票为 发票 − 暂估
    amv = SELECT "ObjType", "DocEntry", "LineNum",
                 SUM(CASE WHEN "MoveType" = 'INV' THEN IFNULL("DocAmt", 0) + "AccrAmt" ELSE "AccrAmt" END) AS "Amt"
            FROM "MTC_CA_S_AP_MOVE"
           WHERE "RunId" = :RunId AND "AccrType" = 'MAT' AND "DocDate" BETWEEN :d0 AND :d1
           GROUP BY "ObjType", "DocEntry", "LineNum";
    tgt = SELECT L."LineId", A."Amt",
                 ROW_NUMBER() OVER (PARTITION BY L."ObjType", L."DocEntry", L."LineNum" ORDER BY L."LineId") AS "Rn"
            FROM "MTC_CA_S_LINE" L
            JOIN :amv A ON A."ObjType" = L."ObjType" AND A."DocEntry" = L."DocEntry" AND A."LineNum" = L."LineNum"
           WHERE L."RunId" = :RunId AND L."Src" = 'OIVL';
    UPDATE T0 SET T0."SrcAmt" = CASE WHEN X."Rn" = 1 THEN X."Amt" ELSE 0 END
      FROM "MTC_CA_S_LINE" T0
      JOIN :tgt X ON X."LineId" = T0."LineId"
     WHERE T0."RunId" = :RunId;

    -- 委外加工费发票差异 → 产品的 I11（替代 @MTC_OMRV WW 单）；没有产品物料的由 PRE-21 报出
    SELECT IFNULL(MAX("LineId"), 0) INTO maxLine FROM "MTC_CA_S_LINE" WHERE "RunId" = :RunId;
    INSERT INTO "MTC_CA_S_LINE" ("FcCode", "RunType", "Scenario", "RunId", "LineId", "Src", "SrcKey", "ObjType", "DocEntry",
        "LineNum", "Canceled", "DocDate", "ItemCode", "Qty", "SrcAmt", "TransCode", "Dir", "CardCode",
        "BaseType", "BaseEntry", "BaseLine", "AcctCode")
    SELECT :fc, :rt, :scen, :RunId, :maxLine + ROW_NUMBER() OVER (ORDER BY A."MoveId"),
           'APDIF', A."ObjType" || '-' || A."DocEntry" || '-' || A."LineNum", A."ObjType", A."DocEntry",
           A."LineNum", CASE WHEN A."IsCancel" = 'Y' THEN 'C' ELSE 'N' END, A."DocDate", A."ProdItem", 0,
           A."DocAmt" + A."AccrAmt", 'I11', IO."U_IOType", A."CardCode",
           A."BaseObj", TO_NVARCHAR(A."BaseEntry"), TO_NVARCHAR(A."BaseLine"), :difAcct
      FROM "MTC_CA_S_AP_MOVE" A
      JOIN "MTC_CA_S_ITEM" I ON I."RunId" = A."RunId" AND I."ItemCode" = A."ProdItem"
      LEFT JOIN "@MTC_COST_IOTYPE" IO ON IO."Code" = 'I11'
     WHERE A."RunId" = :RunId AND A."AccrType" = 'SUBFEE' AND A."MoveType" = 'INV'
       AND A."DocDate" BETWEEN :d0 AND :d1 AND A."DocAmt" + A."AccrAmt" <> 0;
    n := ::ROWCOUNT;
    RowCnt := :RowCnt + :n;
END
@@
-- 委外加工费：加工费采购收货行（PDN1.U_BaseType='59' 指向生产收货）→ 生产收货所属订单；
-- 加工费退货按退货自己的日期计入（旧视图不分日期扣减）；@MTC_OMRV ProWW 中能找到订单的行也计入订单。
-- 没有关联采购收货的加工费退货（X 开头物料，用户 2026-10-15）：取退货行自己的 U_BaseType/U_BaseEntry（生产收货），
-- 或直接按行上的 U_OWORNum / U_MTCOWORNum 找生产订单 / 返工单；之前漏掉，导致 WW03 多结转 140802（2026-09 POST-06）。
-- 生产收货的订单：202 取视图；返工单（MTC_OWOR）取 IGN1.U_OWORType / U_MTCOWORNum 的主件行（用户 2026-10-13）。
-- 订单匹配：先按 收货单 + 加工费行上的订单匹配（202 比 U_OWORNum = OWOR.DocNum；返工单 U_OWORType='MTC_OWOR' 时 U_OWORNum 为空，
-- 比 U_MTCOWORNum = @MTC_OWOR.DocEntry，用户 2026-10-14）；收货单只对应一张订单时直接用；仍找不到的 OrderEntry 为空（PRE-12 警告，金额不进任何订单）。
-- 金额符号【读代码】：旧 0306 计入 4WWExp 的是 +LineTotal、ProWW 为 +U_Amount。
-- 金额口径（用户 2026-10-30 方案 B）：收货 / 退货改取 S_AP_MOVE 的暂估金额（指定单价 → 已确认价 → LineTotal），与 PUR4 借 140802 同一口径。
CREATE OR REPLACE PROCEDURE "MTC_CA_P20_SUBFEE" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE n BIGINT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);

    fee = SELECT 'PDN' AS "Src", D."DocEntry" || '-' || D."LineNum" AS "SrcKey", TO_DATE(M."DocDate") AS "DocDate",
                 D."ItemCode", CASE WHEN M."CANCELED" = 'C' THEN -1 ELSE 1 END * D."Quantity" AS "Qty",
                 CASE WHEN M."CANCELED" = 'C' THEN -1 ELSE 1 END * D."LineTotal" AS "Amount",
                 TO_NVARCHAR(D."U_BaseEntry") AS "RcptEntry", TO_NVARCHAR(D."U_OWORNum") AS "OWORNum",
                 TO_NVARCHAR(D."U_OWORType") AS "OWORType", TO_NVARCHAR(D."U_MTCOWORNum") AS "MTCOWORNum"
            FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry"
           WHERE TO_NVARCHAR(D."U_BaseType") = '59' AND M."DocDate" BETWEEN :d0 AND :d1
          UNION ALL
          SELECT 'RPD', D."DocEntry" || '-' || D."LineNum", TO_DATE(M."DocDate"),
                 D."ItemCode", CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END * D."Quantity",
                 CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END * D."LineTotal",
                 TO_NVARCHAR(P."U_BaseEntry"), TO_NVARCHAR(P."U_OWORNum"),
                 TO_NVARCHAR(P."U_OWORType"), TO_NVARCHAR(P."U_MTCOWORNum")
            FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry"
            JOIN "PDN1" P ON D."BaseType" = 20 AND P."DocEntry" = D."BaseEntry" AND P."LineNum" = D."BaseLine"
           WHERE TO_NVARCHAR(P."U_BaseType") = '59' AND M."DocDate" BETWEEN :d0 AND :d1
          UNION ALL
          -- 没有关联采购收货的加工费退货（物料 X 开头，用户 2026-10-15）：用退货行自己的 U_ 字段找生产收货 / 订单
          SELECT 'RPD', D."DocEntry" || '-' || D."LineNum", TO_DATE(M."DocDate"),
                 D."ItemCode", CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END * D."Quantity",
                 CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END * D."LineTotal",
                 CASE WHEN TO_NVARCHAR(D."U_BaseType") = '59' THEN TO_NVARCHAR(D."U_BaseEntry") END, TO_NVARCHAR(D."U_OWORNum"),
                 TO_NVARCHAR(D."U_OWORType"), TO_NVARCHAR(D."U_MTCOWORNum")
            FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry"
           WHERE IFNULL(D."BaseType", -1) <> 20 AND D."ItemCode" LIKE 'X%' AND M."DocDate" BETWEEN :d0 AND :d1;

    -- 生产收货 → 订单（完工行：订单行为空）
    -- 202：视图改写后的来源；返工单：IGN1 BaseType<>202 时取 U_OWORType='MTC_OWOR' / U_MTCOWORNum（DocEntry），
    -- U_MTCOWORLineNum 为空的是主件（同 MTC_VIEW_ProductDetail_MTCOWOR；视图中这类行的 BaseLine 是 ''，不是 NULL）
    rcpt = SELECT DISTINCT TO_NVARCHAR(V."DocEntry") AS "RcptEntry", TO_NVARCHAR(V."BaseType") AS "OrderType",
                  TO_NVARCHAR(V."BaseEntry") AS "OrderEntry", TO_NVARCHAR(V."BaseRef") AS "OrderRef"
             FROM "MTC_VIEW_Document" V
            WHERE TO_NVARCHAR(V."ObjType") = '59' AND TO_NVARCHAR(V."BaseType") = '202' AND V."BaseLine" IS NULL
              AND TO_NVARCHAR(V."DocEntry") IN (SELECT "RcptEntry" FROM :fee)
           UNION
           SELECT DISTINCT TO_NVARCHAR(D."DocEntry"), 'MTC_OWOR', TO_NVARCHAR(M."DocEntry"), TO_NVARCHAR(M."DocNum")
             FROM "IGN1" D
             JOIN "@MTC_OWOR" M ON M."Object" = D."U_OWORType" AND TO_NVARCHAR(M."DocEntry") = TO_NVARCHAR(D."U_MTCOWORNum")
            WHERE IFNULL(D."BaseType", -1) <> 202 AND D."U_OWORType" = 'MTC_OWOR' AND IFNULL(TO_NVARCHAR(D."U_MTCOWORLineNum"), '') = ''
              AND TO_NVARCHAR(D."DocEntry") IN (SELECT "RcptEntry" FROM :fee);

    cand = SELECT F."SrcKey", R."OrderType", R."OrderEntry",
                  CASE WHEN R."OrderType" = '202' AND R."OrderRef" = F."OWORNum" THEN 1
                       WHEN R."OrderType" = 'MTC_OWOR' AND F."OWORType" = 'MTC_OWOR' AND R."OrderEntry" = F."MTCOWORNum" THEN 1
                       ELSE 0 END AS "Hit",
                  COUNT(*) OVER (PARTITION BY F."Src", F."SrcKey") AS "Cnt", F."Src"
             FROM :fee F JOIN :rcpt R ON R."RcptEntry" = F."RcptEntry";
    cand2 = SELECT C.*, SUM(C."Hit") OVER (PARTITION BY C."Src", C."SrcKey") AS "Hits" FROM :cand C;
    pick0 = SELECT "Src", "SrcKey", "OrderType", "OrderEntry",
                   CASE WHEN "Hit" = 1 THEN '按生产收货 + 订单号匹配' ELSE '生产收货只对应一张订单' END AS "Note"
              FROM :cand2
             WHERE ("Hits" = 1 AND "Hit" = 1) OR ("Hits" = 0 AND "Cnt" = 1);
    -- 找不到生产收货时（没有关联收货的加工费退货），直接按行上的订单号找订单：
    -- 返工单 U_OWORType='MTC_OWOR' 时 U_MTCOWORNum = @MTC_OWOR.DocEntry，否则 U_OWORNum = OWOR.DocNum（用户 2026-10-15）
    dir = SELECT F."Src", F."SrcKey", 'MTC_OWOR' AS "OrderType", TO_NVARCHAR(R."DocEntry") AS "OrderEntry",
                 '按退货行上的返工单号匹配' AS "Note"
            FROM :fee F JOIN "@MTC_OWOR" R ON TO_NVARCHAR(R."DocEntry") = F."MTCOWORNum"
           WHERE F."OWORType" = 'MTC_OWOR'
          UNION ALL
          SELECT F."Src", F."SrcKey", '202', TO_NVARCHAR(W."DocEntry"), '按退货行上的生产订单号匹配'
            FROM :fee F JOIN "OWOR" W ON TO_NVARCHAR(W."DocNum") = F."OWORNum"
           WHERE IFNULL(F."OWORType", '') <> 'MTC_OWOR';
    -- 单号对应多张订单时不取，避免重复计入
    pick = SELECT "Src", "SrcKey", "OrderType", "OrderEntry", "Note" FROM :pick0
           UNION ALL
           SELECT D."Src", D."SrcKey", D."OrderType", D."OrderEntry", D."Note"
             FROM (SELECT X.*, COUNT(*) OVER (PARTITION BY X."Src", X."SrcKey") AS "Cnt" FROM :dir X) D
            WHERE D."Cnt" = 1
              AND NOT EXISTS (SELECT 1 FROM :pick0 P WHERE P."Src" = D."Src" AND P."SrcKey" = D."SrcKey");

    -- 金额取暂估口径（用户 2026-10-30 方案 B）：与 PUR4 计提同一份 S_AP_MOVE（P20_AP 先执行），指定单价 U_InitPrice → 已确认价 Price × 数量 → LineTotal，
    -- 退货按所基于收货行的暂估单价（含清余数）；S_AP_MOVE 里没有的（不是委外加工费物料 SUBFEE_ITEM）仍取 LineTotal。旧 0306 / 视图 ID 3 一律 LineTotal
    am = SELECT CASE WHEN "ObjType" = '20' THEN 'PDN' ELSE 'RPD' END AS "Src", "DocEntry" || '-' || "LineNum" AS "SrcKey", SUM("AccrAmt") AS "Amt"
           FROM "MTC_CA_S_AP_MOVE"
          WHERE "RunId" = :RunId AND "AccrType" = 'SUBFEE' AND "MoveType" IN ('ACCR', 'RET') AND "DocDate" BETWEEN :d0 AND :d1
          GROUP BY "ObjType", "DocEntry", "LineNum";
    INSERT INTO "MTC_CA_S_SUBFEE" ("FcCode", "RunType", "Scenario", "RunId", "FeeId", "Src", "SrcKey", "DocDate", "ItemCode",
                                   "Qty", "Amount", "RcptEntry", "OrderType", "OrderEntry", "MatchNote")
    SELECT :fc, :rt, :scen, :RunId, ROW_NUMBER() OVER (ORDER BY F."Src", F."SrcKey"),
           F."Src", F."SrcKey", F."DocDate", F."ItemCode", F."Qty", COALESCE(A."Amt", F."Amount"),
           CASE WHEN F."RcptEntry" LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(F."RcptEntry") END,
           K."OrderType", CASE WHEN K."OrderEntry" LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(K."OrderEntry") END,
           IFNULL(K."Note", CASE WHEN X."RcptEntry" IS NOT NULL
                                 THEN '生产收货对应多张订单，订单号对不上' ELSE '找不到生产收货或其订单' END)
      FROM :fee F
      LEFT JOIN :pick K ON K."Src" = F."Src" AND K."SrcKey" = F."SrcKey"
      LEFT JOIN :am A ON A."Src" = F."Src" AND A."SrcKey" = F."SrcKey"
      LEFT JOIN (SELECT DISTINCT "RcptEntry" FROM :rcpt) X ON X."RcptEntry" = F."RcptEntry";
    RowCnt := ::ROWCOUNT;

    INSERT INTO "MTC_CA_S_SUBFEE" ("FcCode", "RunType", "Scenario", "RunId", "FeeId", "Src", "SrcKey", "DocDate", "ItemCode",
                                   "Qty", "Amount", "OrderType", "OrderEntry", "MatchNote")
    SELECT :fc, :rt, :scen, :RunId, :RowCnt + ROW_NUMBER() OVER (ORDER BY T1."DocEntry", T1."LineId"),
           'PROWW', T1."DocEntry" || '-' || T1."LineId", TO_DATE(T0."U_DocDate"), T1."U_ItemCode",
           T1."U_Quantity", T1."U_Amount", T1."U_BaseType", T1."U_BaseEntry", '重估单行上的订单'
      FROM "@MTC_OMRV" T0
      JOIN "@MTC_OMRV1" T1 ON T1."DocEntry" = T0."DocEntry"
      LEFT JOIN "OWOR" W ON T1."U_BaseType" = '202' AND W."DocEntry" = T1."U_BaseEntry"
      LEFT JOIN "@MTC_OWOR" M ON T1."U_BaseType" = 'MTC_OWOR' AND M."DocEntry" = T1."U_BaseEntry"
     WHERE T0."U_BaseType" = 'ProWW' AND IFNULL(T0."Canceled", 'N') = 'N'
       AND T0."U_DocDate" BETWEEN :d0 AND :d1
       AND (W."DocEntry" IS NOT NULL OR M."DocEntry" IS NOT NULL);
    n := ::ROWCOUNT;
    RowCnt := :RowCnt + :n;
END
@@
-- PUR1–PUR5 逐单据勾稽（POST-15，用户 2026-10-30）。只读。
-- PUR1–PUR5 的目的：B1 按标准成本自动生成收货 / 退货 / 发票凭证，金额不是公司要的入账价（期初和上线后部分单据系统 Price 有误、
-- 单据又不能改不能取消，行上另填 U_InitPrice；2026 年起几乎没有，但仍有未开票收货会用到）。PUR 把系统凭证在存货、暂估、加工费科目上的
-- 金额冲掉，按暂估口径（U_InitPrice → U_IsPrice='Y' 已确认价 → LineTotal）重记，开票时冲暂估、差额进存货 / 140803（再经 MR01 进产品）。
-- 所以每张采购单据：系统凭证 + PUR 冲回 + PUR 重记（+ MR01）= 业务端，按 单据 × 科目 逐行比较：
--   AP     应付暂估 220202     业务 = −本单据的暂估变动（S_AP_MOVE.AccrAmt，贷方为负）
--   STOCK  存货（OGAR.StockAct）业务 = 本单据计入物料成本的金额（R_LINE，含委外发票差异进产品的 APDIF）
--   FEE    委外加工费 140802   业务 = 本单据加工费物料的暂估、退货（S_AP_MOVE）
--   FEEDIF 140803              业务 = 0（PUR3 借 = MR01 贷）
--   VAR    价格差异（OGAR.PricDifAct / VariancAct + 参数 PUR_STDVAR_ACCTS）业务 = 0：标准成本留下的差异应全部清掉（Q23 的情况会出现在这里）
--   KEEP   业务伙伴行（ShortName ≠ Account）和税额行（VatLine='Y'）：系统凭证原样保留，不比较
--   OTHER  其他科目：收货 / 退货（20 / 21）业务 = 0（PUR5 全部冲回）；发票 / 贷项（18 / 19）系统凭证原样保留，不比较
-- 范围：本期有暂估变动、有 PUR / MR01 底稿、或计入物料成本的采购单据（含取消单），以及它们本期的系统凭证（OJDT.TransType + CreatedBy）。
CREATE OR REPLACE FUNCTION "MTC_CA_F_PUR_DOC" (IN RunId BIGINT)
RETURNS TABLE ("ObjType" NVARCHAR(2), "DocEntry" INTEGER, "DocNum" INTEGER, "CardCode" NVARCHAR(50), "Role" NVARCHAR(10),
               "AcctCode" NVARCHAR(15), "SysAmt" DECIMAL(19,2), "PurRev" DECIMAL(19,2), "PurBook" DECIMAL(19,2), "Mr01" DECIMAL(19,2),
               "FinAmt" DECIMAL(19,2), "BizAmt" DECIMAL(19,2), "Diff" DECIMAL(19,2), "InitLines" INT, "HasSysJe" NVARCHAR(1))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE apAcct NVARCHAR(15); DECLARE wwFee NVARCHAR(15); DECLARE wwDif NVARCHAR(15); DECLARE varX NVARCHAR(500);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    apAcct := "MTC_CA_F_ACCT"('AP_ACCRUAL', :fc);
    wwFee := "MTC_CA_F_ACCT"('WW_FEE', :fc);
    wwDif := "MTC_CA_F_ACCT"('WW_FEE_DIF', :fc);
    varX := IFNULL("MTC_CA_F_PARAM"('PUR_STDVAR_ACCTS', :fc), ',');

    -- 科目角色（一个科目只取一个，优先级 AP > FEE > FEEDIF > STOCK > VAR）
    stockAct = SELECT TO_NVARCHAR("ItmsGrpCod") AS "ItmsGrpCod", MAX("StockAct") AS "Acct"
                 FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4) GROUP BY "ItmsGrpCod";
    role0 = SELECT :apAcct AS "AcctCode", 1 AS "Pri", 'AP' AS "Role" FROM DUMMY
            UNION ALL SELECT :wwFee, 2, 'FEE' FROM DUMMY
            UNION ALL SELECT :wwDif, 3, 'FEEDIF' FROM DUMMY
            UNION ALL SELECT DISTINCT "StockAct", 4, 'STOCK' FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4)
            UNION ALL SELECT DISTINCT "PricDifAct", 5, 'VAR' FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4)
            UNION ALL SELECT DISTINCT "VariancAct", 5, 'VAR' FROM "OGAR" WHERE "PeriodCat" = LEFT(:fc, 4)
            UNION ALL SELECT "AcctCode", 5, 'VAR' FROM "OACT" WHERE LOCATE(:varX, ',' || "AcctCode" || ',') > 0;
    roles = SELECT "AcctCode", MAX("Role") AS "Role" FROM (
                SELECT "AcctCode", "Role", RANK() OVER (PARTITION BY "AcctCode" ORDER BY "Pri") AS "Rk"
                  FROM :role0 WHERE IFNULL("AcctCode", '') <> '')
             WHERE "Rk" = 1 GROUP BY "AcctCode";

    -- 本期暂估变动（含取消单）
    mv = SELECT * FROM "MTC_CA_S_AP_MOVE" WHERE "RunId" = :RunId AND "DocDate" BETWEEN :d0 AND :d1;

    -- PUR / MR01 底稿 → 单据：GL = 冲回的系统凭证行（TransId-Line_ID）；DOC = 单据行（ObjType-DocEntry-LineNum）；MR01 = APDIF 的 S_LINE
    pur = SELECT "TransCode", "AcctCode", "Amount", "SrcType", "SrcKey" FROM "MTC_CA_R_JDT_SRC"
           WHERE "RunId" = :RunId AND "TransCode" IN ('PUR1', 'PUR2', 'PUR3', 'PUR4', 'PUR5', 'MR01');
    purM = SELECT TO_NVARCHAR(H."TransType") AS "ObjType", H."CreatedBy" AS "DocEntry", P."AcctCode", P."Amount", 'REV' AS "Kind"
             FROM :pur P
             JOIN "JDT1" J ON J."TransId" = TO_INTEGER(SUBSTR_BEFORE(P."SrcKey", '-')) AND J."Line_ID" = TO_INTEGER(SUBSTR_AFTER(P."SrcKey", '-'))
             JOIN "OJDT" H ON H."TransId" = J."TransId"
            WHERE P."SrcType" = 'GL'
           UNION ALL
           SELECT SUBSTR_BEFORE(P."SrcKey", '-'), TO_INTEGER(SUBSTR_BEFORE(SUBSTR_AFTER(P."SrcKey", '-'), '-')), P."AcctCode", P."Amount", 'BOOK'
             FROM :pur P WHERE P."SrcType" = 'DOC'
           UNION ALL
           SELECT S."ObjType", S."DocEntry", P."AcctCode", P."Amount", 'MR01'
             FROM :pur P JOIN "MTC_CA_S_LINE" S ON S."RunId" = :RunId AND TO_NVARCHAR(S."LineId") = P."SrcKey"
            WHERE P."TransCode" = 'MR01' AND P."SrcType" = 'LINE';

    -- 业务端计入物料成本的金额（采购单据行，含 APDIF）
    biz = SELECT S."ObjType", S."DocEntry", SA."Acct" AS "AcctCode", L."Amount"
            FROM "MTC_CA_R_LINE" L
            JOIN "MTC_CA_S_LINE" S ON S."RunId" = L."RunId" AND S."LineId" = L."LineId"
            LEFT JOIN "MTC_CA_S_ITEM" I ON I."RunId" = L."RunId" AND I."ItemCode" = L."ItemCode"
            LEFT JOIN :stockAct SA ON SA."ItmsGrpCod" = I."ItmsGrpCod"
           WHERE L."RunId" = :RunId AND S."ObjType" IN ('18', '19', '20', '21') AND L."Amount" <> 0;

    docs = SELECT DISTINCT "ObjType", "DocEntry" FROM (
               SELECT "ObjType", "DocEntry" FROM :mv
               UNION ALL SELECT "ObjType", "DocEntry" FROM :purM
               UNION ALL SELECT "ObjType", "DocEntry" FROM :biz);

    sys = SELECT TO_NVARCHAR(H."TransType") AS "ObjType", H."CreatedBy" AS "DocEntry", J."Account" AS "AcctCode", J."Debit" - J."Credit" AS "Amt",
                 CASE WHEN J."ShortName" <> J."Account" OR J."VatLine" = 'Y' THEN 'Y' ELSE 'N' END AS "Keep"
            FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
            JOIN :docs D ON D."ObjType" = TO_NVARCHAR(H."TransType") AND D."DocEntry" = H."CreatedBy"
           WHERE H."RefDate" BETWEEN :d0 AND :d1 AND H."TransType" IN ('18', '19', '20', '21');

    -- 指定单价（U_InitPrice ≠ 0）的暂估行：本期变动涉及几条
    init = SELECT M."ObjType", M."DocEntry", COUNT(DISTINCT M."BaseObj" || '-' || M."BaseEntry" || '-' || M."BaseLine") AS "N"
             FROM :mv M
             LEFT JOIN "PDN1" P ON M."BaseObj" = '20' AND P."DocEntry" = M."BaseEntry" AND P."LineNum" = M."BaseLine"
             LEFT JOIN "RPD1" R ON M."BaseObj" = '21' AND R."DocEntry" = M."BaseEntry" AND R."LineNum" = M."BaseLine"
            WHERE IFNULL(COALESCE(P."U_InitPrice", R."U_InitPrice"), 0) <> 0
            GROUP BY M."ObjType", M."DocEntry";

    u = SELECT "ObjType", "DocEntry", CASE WHEN "Keep" = 'Y' THEN 'KEEP' END AS "R0", "AcctCode",
               "Amt" AS "Sys", 0 AS "Rev", 0 AS "Book", 0 AS "Mr", 0 AS "Biz" FROM :sys
        UNION ALL SELECT "ObjType", "DocEntry", NULL, "AcctCode", 0, "Amount", 0, 0, 0 FROM :purM WHERE "Kind" = 'REV'
        UNION ALL SELECT "ObjType", "DocEntry", NULL, "AcctCode", 0, 0, "Amount", 0, 0 FROM :purM WHERE "Kind" = 'BOOK'
        UNION ALL SELECT "ObjType", "DocEntry", NULL, "AcctCode", 0, 0, 0, "Amount", 0 FROM :purM WHERE "Kind" = 'MR01'
        UNION ALL SELECT "ObjType", "DocEntry", NULL, :apAcct, 0, 0, 0, 0, -SUM("AccrAmt") FROM :mv GROUP BY "ObjType", "DocEntry"
        UNION ALL SELECT "ObjType", "DocEntry", NULL, :wwFee, 0, 0, 0, 0, SUM("AccrAmt") FROM :mv
                   WHERE "AccrType" = 'SUBFEE' AND "MoveType" IN ('ACCR', 'RET') GROUP BY "ObjType", "DocEntry"
        UNION ALL SELECT "ObjType", "DocEntry", NULL, "AcctCode", 0, 0, 0, 0, "Amount" FROM :biz;

    g = SELECT U."ObjType", U."DocEntry",
               CASE WHEN U."R0" = 'KEEP' THEN 'KEEP' ELSE IFNULL(R."Role", 'OTHER') END AS "Role", U."AcctCode",
               ROUND(SUM(U."Sys"), 2) AS "Sys", ROUND(SUM(U."Rev"), 2) AS "Rev", ROUND(SUM(U."Book"), 2) AS "Book",
               ROUND(SUM(U."Mr"), 2) AS "Mr", ROUND(SUM(U."Biz"), 2) AS "Biz"
          FROM :u U LEFT JOIN :roles R ON R."AcctCode" = U."AcctCode"
         GROUP BY U."ObjType", U."DocEntry", CASE WHEN U."R0" = 'KEEP' THEN 'KEEP' ELSE IFNULL(R."Role", 'OTHER') END, U."AcctCode";

    hdr = SELECT '20' AS "ObjType", "DocEntry", "DocNum", "CardCode" FROM "OPDN" WHERE "DocEntry" IN (SELECT "DocEntry" FROM :docs WHERE "ObjType" = '20')
          UNION ALL SELECT '21', "DocEntry", "DocNum", "CardCode" FROM "ORPD" WHERE "DocEntry" IN (SELECT "DocEntry" FROM :docs WHERE "ObjType" = '21')
          UNION ALL SELECT '18', "DocEntry", "DocNum", "CardCode" FROM "OPCH" WHERE "DocEntry" IN (SELECT "DocEntry" FROM :docs WHERE "ObjType" = '18')
          UNION ALL SELECT '19', "DocEntry", "DocNum", "CardCode" FROM "ORPC" WHERE "DocEntry" IN (SELECT "DocEntry" FROM :docs WHERE "ObjType" = '19');
    je = SELECT DISTINCT "ObjType", "DocEntry" FROM :sys;

    RETURN SELECT CAST(G."ObjType" AS NVARCHAR(2)) AS "ObjType", G."DocEntry", H."DocNum", CAST(H."CardCode" AS NVARCHAR(50)) AS "CardCode",
                  CAST(G."Role" AS NVARCHAR(10)) AS "Role", CAST(G."AcctCode" AS NVARCHAR(15)) AS "AcctCode",
                  CAST(G."Sys" AS DECIMAL(19,2)) AS "SysAmt", CAST(G."Rev" AS DECIMAL(19,2)) AS "PurRev",
                  CAST(G."Book" AS DECIMAL(19,2)) AS "PurBook", CAST(G."Mr" AS DECIMAL(19,2)) AS "Mr01",
                  CAST(G."Sys" + G."Rev" + G."Book" + G."Mr" AS DECIMAL(19,2)) AS "FinAmt",
                  CAST(CASE WHEN G."Role" = 'KEEP' OR (G."Role" = 'OTHER' AND G."ObjType" IN ('18', '19')) THEN NULL ELSE G."Biz" END AS DECIMAL(19,2)) AS "BizAmt",
                  CAST(CASE WHEN G."Role" = 'KEEP' OR (G."Role" = 'OTHER' AND G."ObjType" IN ('18', '19')) THEN NULL
                            ELSE G."Sys" + G."Rev" + G."Book" + G."Mr" - G."Biz" END AS DECIMAL(19,2)) AS "Diff",
                  CAST(IFNULL(I."N", 0) AS INT) AS "InitLines",
                  CAST(CASE WHEN J."DocEntry" IS NULL THEN 'N' ELSE 'Y' END AS NVARCHAR(1)) AS "HasSysJe"
             FROM :g G
             LEFT JOIN :hdr H ON H."ObjType" = G."ObjType" AND H."DocEntry" = G."DocEntry"
             LEFT JOIN :init I ON I."ObjType" = G."ObjType" AND I."DocEntry" = G."DocEntry"
             LEFT JOIN :je J ON J."ObjType" = G."ObjType" AND J."DocEntry" = G."DocEntry";
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P75_POSTCHECK" (IN RunId BIGINT, OUT FailCnt INT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE basis NVARCHAR(10); DECLARE posted NVARCHAR(1000); DECLARE rmsg NVARCHAR(1000); DECLARE oth DECIMAL(19,2);
    DECLARE blockOn NVARCHAR(10); DECLARE gmsg NVARCHAR(1000); DECLARE wmsg NVARCHAR(1000);
    DECLARE custDom NVARCHAR(50); DECLARE custExp NVARCHAR(50);
    DECLARE nSub INT;
    DECLARE initFrom DATE; DECLARE feeItem NVARCHAR(50);
    DECLARE nPurDoc INT; DECLARE nPurBad INT; DECLARE nInit INT; DECLARE initAmt DECIMAL(19,2);
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    custDom := IFNULL("MTC_CA_F_PARAM"('CUST_DOM', :fc), '国内客户');   -- 客户类型（参数，2026-10-27）
    custExp := IFNULL("MTC_CA_F_PARAM"('CUST_EXP', :fc), '国外客户');

    -- POST-08 借贷平衡、科目齐全
    t08 = SELECT "TransCode" AS "KeyCode", '借方 ' || TO_NVARCHAR(SUM("Debit")) || ' ≠ 贷方 ' || TO_NVARCHAR(SUM("Credit")) AS "Info"
            FROM "MTC_CA_R_JDT" WHERE "RunId" = :RunId GROUP BY "TransCode" HAVING ABS(SUM("Debit") - SUM("Credit")) > 0.001
          UNION ALL
          SELECT "TransCode" || '-' || "SrcType" || '-' || IFNULL("SrcKey", ''), '取不到科目，金额 ' || TO_NVARCHAR("Amount")
            FROM "MTC_CA_R_JDT_SRC" WHERE "RunId" = :RunId AND "AcctCode" IS NULL;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-08', :t08, NULL);

    -- POST-06 / 09 / 10 / 11 / 13 财务端与业务端对账：期初 / 本期 / 期末分开列示（MTC_CA_F_RECON），rec."Diff" = 用来判断的那一列差额
    SELECT MAX("Basis"), MAX("PostedCodes") INTO basis, posted FROM "MTC_CA_F_RECON_STATUS"(:RunId);
    -- 按哪一列阻断：CUR = 本期差额（默认，期初差额是承接前就有的，只列示）/ END = 期末差额（用户 2026-10-15）
    blockOn := IFNULL("MTC_CA_F_PARAM"('RECON_BLOCK_ON', :fc), 'CUR');
    rmsg := LEFT('期初 / 本期 / 期末分开列示，按' || CASE WHEN :blockOn = 'END' THEN '期末' ELSE '本期' END || '差额判断；'
                 || '财务本期 = 本期分录 + 底稿中本期尚未过账的凭证；'
                 || CASE WHEN :basis = 'DRAFT' THEN '本期成本凭证都未过账'
                         ELSE '本期已过账（底稿中这部分不再加）：' || IFNULL(:posted, '无（凭证在未清凭单中）') END, 900);
    rec = SELECT "Area", "AcctCode", "KeyCode",
                 '期初：业务 ' || TO_NVARCHAR("BegBiz") || '，财务 ' || TO_NVARCHAR("BegFin") || '，差额 ' || TO_NVARCHAR("BegDiff")
                 || '；本期：业务 ' || TO_NVARCHAR("CurBiz") || '，财务 ' || TO_NVARCHAR("CurFin")
                 || CASE WHEN "PendCodes" IS NOT NULL THEN '（含未过账底稿 ' || TO_NVARCHAR("DraftAmt" - "DupAmt") || '：' || "PendCodes" || '）' ELSE '' END
                 || '，差额 ' || TO_NVARCHAR("CurDiff")
                 || '；期末：业务 ' || TO_NVARCHAR("BizAmt") || '，财务 ' || TO_NVARCHAR("EndFin") || '，差额 ' || TO_NVARCHAR("Diff")
                 || CASE WHEN "DupCodes" IS NOT NULL THEN '。底稿中 ' || "DupCodes" || ' 本期已过账或已在未清凭单（'
                         || TO_NVARCHAR("DupAmt") || '），没有重复加' ELSE '' END
                 || CASE WHEN ABS("OtherAmt") > 0.01 THEN '。不参与对账的分录 ' || TO_NVARCHAR("OtherAmt") ELSE '' END AS "Info",
                 CASE WHEN :blockOn = 'END' THEN "Diff" ELSE "CurDiff" END AS "Diff"
            FROM "MTC_CA_F_RECON"(:RunId);

    -- POST-06 委外：140801 = 委外在产品（材料），140802 = 订单上未结转加工费
    -- 加工费留在订单上的订单（未关闭、本期没有入库，等下次入库结转）只在说明里列示、不阻断（Q35，用户 2026-10-17）；
    -- 截至期末已关闭的订单不再留加工费（P30 按关单转关单差异）
    t06 = SELECT "AcctCode" AS "KeyCode", "Info" FROM :rec WHERE "Area" IN ('WW_MAT', 'WW_FEE') AND ABS("Diff") > 0.01;
    -- 列出金额最大的 30 张（说明最长 1000 字）。没有这种订单时不能执行带 ORDER BY 的 STRING_AGG … INTO（HANA 报 1299 no data found，
    -- 2026-10-30 FH100_COST_TEST 2026-10 加工费全部结转时遇到），先数一下
    SELECT COUNT(*) INTO nSub FROM "MTC_CA_R_ORDER_MAT"
     WHERE "RunId" = :RunId AND "ItemCode" = '#SUBFEE' AND ABS("WipSub") > 0.01;
    wmsg := :rmsg;
    IF :nSub > 0 THEN
    SELECT LEFT(:rmsg || CASE WHEN MAX("Cnt") IS NULL THEN ''
                         ELSE '。加工费留在订单上（未关闭、待下次入库结转，只列示）' || MAX("Cnt") || ' 张，合计 ' || TO_NVARCHAR(ROUND(MAX("Tot"), 2))
                              || '：' || STRING_AGG("K" || ' ' || TO_NVARCHAR(ROUND("Amt", 2)), '、' ORDER BY ABS("Amt") DESC) END, 1000)
      INTO wmsg
      FROM (SELECT M."OrderType" || '-' || M."OrderEntry" AS "K", M."WipSub" AS "Amt",
                   COUNT(*) OVER () AS "Cnt", SUM(M."WipSub") OVER () AS "Tot",
                   ROW_NUMBER() OVER (ORDER BY ABS(M."WipSub") DESC) AS "Rn"
              FROM "MTC_CA_R_ORDER_MAT" M
             WHERE M."RunId" = :RunId AND M."ItemCode" = '#SUBFEE' AND ABS(M."WipSub") > 0.01)
     WHERE "Rn" <= 30;
    END IF;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-06', :t06, :wmsg);

    -- POST-09 存货科目（替代 JZ04 尾差凭证，Q15）
    t09 = SELECT "AcctCode" AS "KeyCode", "Info" FROM :rec WHERE "Area" = 'STOCK' AND ABS("Diff") > 0.01;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-09', :t09, :rmsg);

    -- POST-10 发出商品（用户 2026-10-15）：140601 期末 = 期初 = 0。本期构成：① 冲销上月计提（B1 自动冲销）② 发货 DN01 ③ 样品转出 DN02 / DN04
    -- ④ 发票 DN03 ⑤ 本月计提 AR03 / AR04；合计应为 0。另核对 ① = 上期末未开票（R_GOODS_OUT_BEG）、⑤ = 本期末未开票（R_GOODS_OUT），哪项不等就是哪边的问题
    -- 手工调整（InRecon='N'：GOODS 在 RECON_COSTONLY_AREAS 中时，本期凭证代码不在 COST_TRANSCODES 的分录）单独列出、不算差异，
    -- 期末差额扣除手工调整后应等于期初差额（用户 2026-10-17）
    gp = SELECT IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'REV' THEN "Amt" END), 0) AS "Rev",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'DN01' THEN "Amt" END), 0) AS "Dn01",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'SAMPLE' THEN "Amt" END), 0) AS "Smp",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'DN03' THEN "Amt" END), 0) AS "Dn03",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'ACCR' THEN "Amt" END), 0) AS "Accr",
                IFNULL(SUM(CASE WHEN "InRecon" = 'Y' AND "Part" = 'OTHER' THEN "Amt" END), 0) AS "Oth",
                IFNULL(SUM(CASE WHEN "InRecon" = 'N' THEN "Amt" END), 0) AS "Man"
           FROM "MTC_CA_F_RECON_LEDGER"(:RunId)
          WHERE "Area" = 'GOODS' AND "Phase" = 'CUR' AND NOT ("Src" = 'DRAFT' AND "Dup" = 'Y');
    gb = SELECT (SELECT IFNULL(SUM("CostAmt"), 0) FROM "MTC_CA_R_GOODS_OUT_BEG" WHERE "RunId" = :RunId AND "IsSample" = 'N') AS "Beg",
                (SELECT IFNULL(SUM("CostAmt"), 0) FROM "MTC_CA_R_GOODS_OUT" WHERE "RunId" = :RunId AND "IsSample" = 'N') AS "End" FROM DUMMY;
    SELECT LEFT('本期构成：① 冲销上月计提 ' || TO_NVARCHAR(G."Rev") || '，② 发货 ' || TO_NVARCHAR(G."Dn01") || '，③ 样品转出 ' || TO_NVARCHAR(G."Smp")
                || '，④ 发票 ' || TO_NVARCHAR(G."Dn03") || '，⑤ 本月计提 ' || TO_NVARCHAR(G."Accr")
                || CASE WHEN G."Oth" <> 0 THEN '，其他凭证 ' || TO_NVARCHAR(G."Oth") ELSE '' END
                || '；合计 ' || TO_NVARCHAR(G."Rev" + G."Dn01" + G."Smp" + G."Dn03" + G."Accr" + G."Oth") || '（应为 0）'
                || CASE WHEN G."Man" <> 0 THEN '；另有手工调整 ' || TO_NVARCHAR(G."Man") || '（不参与对账，期末差额扣除后应等于期初差额）' ELSE '' END || '。'
                || '上期末未开票 ' || TO_NVARCHAR(B."Beg") || '，本期末未开票 ' || TO_NVARCHAR(B."End") || '。' || :rmsg, 1000)
      INTO gmsg FROM :gp G, :gb B;
    t10 = SELECT "AcctCode" AS "KeyCode", "Info" FROM :rec WHERE "Area" = 'GOODS' AND ABS("Diff") > 0.01
          UNION ALL
          SELECT '① 冲销上月计提', '冲销 ' || TO_NVARCHAR(G."Rev") || ' ≠ 上期末未开票 ' || TO_NVARCHAR(B."Beg") || '，差 ' || TO_NVARCHAR(G."Rev" - B."Beg")
                 || '：上月计提与上期末未开票明细不一致（如旧框架按当前未清数量计提），或上月计提没有自动冲销'
            FROM :gp G, :gb B WHERE ABS(G."Rev" - B."Beg") > 0.01
          UNION ALL
          SELECT '⑤ 本月计提', '计提 ' || TO_NVARCHAR(-G."Accr") || ' ≠ 本期末未开票 ' || TO_NVARCHAR(B."End") || '，差 ' || TO_NVARCHAR(-G."Accr" - B."End")
                 || '：有未开票交货没有客户类型（POST-12）或单位成本为空'
            FROM :gp G, :gb B WHERE ABS(-G."Accr" - B."End") > 0.01;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-10', :t10, :gmsg);

    -- POST-11 应付暂估：220202 按 U_VendorCode = 应付暂估（按供应商）
    t11 = SELECT CASE WHEN "KeyCode" = '' THEN '（无供应商）' ELSE "KeyCode" END AS "KeyCode", "Info" FROM :rec WHERE "Area" = 'AP' AND ABS("Diff") > 0.01;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-11', :t11, :rmsg);

    -- POST-13 生产在产品：500101 的成本凭证 = 生产 / 包装 / 返工订单在产品（不含加工费）；
    -- 非成本凭证分录允许存在，不参与比较，金额写进说明（用户 2026-10-13）
    t13 = SELECT "AcctCode" AS "KeyCode", "Info" FROM :rec WHERE "Area" = 'WIP_PROD' AND ABS("Diff") > 0.01;
    SELECT IFNULL(SUM("OtherAmt"), 0) INTO oth FROM "MTC_CA_F_RECON"(:RunId) WHERE "Area" = 'WIP_PROD';
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-13', :t13,
         :rmsg || CASE WHEN ABS(:oth) > 0.01 THEN '；另有非成本凭证分录 ' || TO_NVARCHAR(:oth) || '（本期分录，允许，不参与对账，见执行台“财务对账”）' ELSE '' END);

    -- POST-12 销售成本取价：找不到交货成本、没有客户类型
    t12 = SELECT "MTC_CA_F_DOCKEY"("ObjType", "DocEntry") || '-LineNum ' || "LineNum" AS "KeyCode", '找不到交货 / 退货行成本' AS "Info"
            FROM "MTC_CA_R_DNCOST" WHERE "RunId" = :RunId AND "UnitCost" IS NULL
          UNION ALL
          SELECT "MTC_CA_F_DOCKEY"("ObjType", "DocEntry") || '-LineNum ' || "LineNum", '未开票交货没有客户类型，AR03/AR04 不计提'
            FROM "MTC_CA_R_GOODS_OUT" WHERE "RunId" = :RunId AND "IsSample" = 'N' AND IFNULL("CustType", '') NOT IN (:custDom, :custExp);
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-12', :t12, NULL);

    -- POST-15 PUR1–PUR5 与业务端逐单据勾稽（用户 2026-10-30，只警告：参数 POST_WARN_IDS）。
    -- ① 单据 × 科目：系统凭证 + PUR 冲回 + PUR 重记（+ MR01）≠ 业务端（MTC_CA_F_PUR_DOC，口径见函数头）
    -- ② 有暂估变动的单据本期没有系统凭证（PUR5 / PUR2 没有可冲回的分录）
    -- ③ 暂估行已全部开票 / 退回，暂估金额没有清零（Q27 清余数没生效）
    -- ④ 加工费收货 / 退货：PUR4 记 140802 的金额 ≠ 计入订单的加工费（两边都取 S_AP_MOVE 暂估金额，用户 2026-10-30 方案 B；差额通常是没关联生产收货 U_BaseType=59）
    -- ⑤ 收货 / 退货中既不是库存物料也不是加工费物料的行：PUR5 冲掉了系统分录、不重记（Q25），列出核对
    -- ⑥ 本期新收货 / 退货用了指定单价 U_InitPrice（参数 INITPRICE_NEW_FROM 起；2026 年起应很少出现，确认系统 Price 确实有误）
    -- ⑦ 已过账（OJDT）的 PUR1–PUR5 按 代码 × 科目 × 供应商 ≠ 本次底稿（只比较本期已过账的代码）
    initFrom := TO_DATE(IFNULL("MTC_CA_F_PARAM"('INITPRICE_NEW_FROM', :fc), '2026-01-01'));
    feeItem := IFNULL("MTC_CA_F_PARAM"('SUBFEE_ITEM', :fc), 'X0510001');
    pd = SELECT * FROM "MTC_CA_F_PUR_DOC"(:RunId);
    t15 = SELECT "MTC_CA_F_DOCKEY"("ObjType", "DocEntry") || ' ' || MAP("Role", 'AP', '应付暂估', 'STOCK', '存货', 'FEE', '委外加工费', 'FEEDIF', '加工费差异',
                 'VAR', '价格差异', '其他科目') || ' ' || "AcctCode" AS "KeyCode",
                 '① 系统凭证 ' || TO_NVARCHAR("SysAmt") || '，PUR 冲回 ' || TO_NVARCHAR("PurRev") || '，PUR 重记 ' || TO_NVARCHAR("PurBook")
                 || CASE WHEN "Mr01" <> 0 THEN '，MR01 ' || TO_NVARCHAR("Mr01") ELSE '' END
                 || '，财务合计 ' || TO_NVARCHAR("FinAmt") || '；业务 ' || TO_NVARCHAR("BizAmt") || '；差 ' || TO_NVARCHAR("Diff")
                 || CASE WHEN "Role" = 'VAR' THEN '（标准成本差异没有清掉，见 Q23）'
                         WHEN "Role" = 'OTHER' THEN '（收货 / 退货的系统分录没有全部冲回）' ELSE '' END
                 || CASE WHEN "InitLines" > 0 THEN '；涉及指定单价 U_InitPrice 的暂估行 ' || "InitLines" || ' 条' ELSE '' END
                 || CASE WHEN "HasSysJe" = 'N' THEN '；本期没有系统凭证' ELSE '' END AS "Info"
            FROM :pd WHERE ABS(IFNULL("Diff", 0)) > 0.01
          UNION ALL
          SELECT DISTINCT "MTC_CA_F_DOCKEY"(M."ObjType", M."DocEntry") || ' 没有系统凭证',
                 '② 本期有暂估变动，但找不到 B1 自动生成的凭证（OJDT.TransType = ' || M."ObjType" || '，CreatedBy = DocEntry），PUR5 / PUR2 没有可冲回的分录'
            FROM "MTC_CA_S_AP_MOVE" M
           WHERE M."RunId" = :RunId AND M."DocDate" BETWEEN :d0 AND :d1
             AND NOT EXISTS (SELECT 1 FROM "OJDT" H WHERE TO_NVARCHAR(H."TransType") = M."ObjType" AND H."CreatedBy" = M."DocEntry")
          UNION ALL
          SELECT "MTC_CA_F_DOCKEY"("BaseObj", "BaseEntry") || '-LineNum ' || "BaseLine" || ' 暂估没清零',
                 '③ 已全部开票 / 退回（未清数量 0），暂估余 ' || TO_NVARCHAR(SUM("AccrAmt"))
            FROM "MTC_CA_S_AP_MOVE" WHERE "RunId" = :RunId
           GROUP BY "BaseObj", "BaseEntry", "BaseLine"
          HAVING ABS(SUM("Qty")) <= 0.000001 AND ABS(SUM("AccrAmt")) >= 0.01 AND MAX("DocDate") >= :d0
          UNION ALL
          SELECT "MTC_CA_F_DOCKEY"("ObjType", "DocEntry") || '-LineNum ' || "LineNum" || ' 加工费',
                 '④ PUR4 记 140802 ' || TO_NVARCHAR("Pur") || '，计入订单加工费 ' || TO_NVARCHAR("Ord") || '，差 ' || TO_NVARCHAR("Pur" - "Ord")
                 || CASE WHEN "Init" = 'Y' THEN '（这行用了指定单价 U_InitPrice）' ELSE '' END
                 || CASE WHEN "Ord" = 0 THEN '（没有关联生产收货 U_BaseType=59，加工费没进订单）' ELSE '' END
            FROM (SELECT "ObjType", "DocEntry", "LineNum", SUM("Pur") AS "Pur", SUM("Ord") AS "Ord", MAX("Init") AS "Init" FROM (
                      SELECT M."ObjType", M."DocEntry", M."LineNum", ROUND(M."AccrAmt", 2) AS "Pur", 0 AS "Ord",
                             CASE WHEN IFNULL(COALESCE(P."U_InitPrice", R."U_InitPrice"), 0) <> 0 THEN 'Y' ELSE 'N' END AS "Init"
                        FROM "MTC_CA_S_AP_MOVE" M
                        LEFT JOIN "PDN1" P ON M."BaseObj" = '20' AND P."DocEntry" = M."BaseEntry" AND P."LineNum" = M."BaseLine"
                        LEFT JOIN "RPD1" R ON M."BaseObj" = '21' AND R."DocEntry" = M."BaseEntry" AND R."LineNum" = M."BaseLine"
                       WHERE M."RunId" = :RunId AND M."AccrType" = 'SUBFEE' AND M."MoveType" IN ('ACCR', 'RET') AND M."DocDate" BETWEEN :d0 AND :d1
                      UNION ALL
                      SELECT CASE WHEN "Src" = 'PDN' THEN '20' ELSE '21' END, TO_INTEGER(SUBSTR_BEFORE("SrcKey", '-')),
                             TO_INTEGER(SUBSTR_AFTER("SrcKey", '-')), 0, ROUND("Amount", 2), 'N'
                        FROM "MTC_CA_S_SUBFEE" WHERE "RunId" = :RunId AND "Src" IN ('PDN', 'RPD'))
                  GROUP BY "ObjType", "DocEntry", "LineNum")
           WHERE ABS("Pur" - "Ord") > 0.01
          UNION ALL
          SELECT "MTC_CA_F_DOCKEY"(X."ObjType", X."DocEntry") || '-LineNum ' || X."LineNum" || ' 非库存',
                 '⑤ ' || X."ItemCode" || ' 不是库存物料也不是加工费物料，金额 ' || TO_NVARCHAR(ROUND(X."LineTotal", 2))
                 || '：PUR5 冲掉了收货的系统分录、不重记（Q25 按发票处理），确认开票时费用已入账'
            FROM (SELECT '20' AS "ObjType", M."DocEntry", D."LineNum", D."ItemCode", D."LineTotal"
                    FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry" WHERE M."DocDate" BETWEEN :d0 AND :d1
                  UNION ALL
                  SELECT '21', M."DocEntry", D."LineNum", D."ItemCode", -D."LineTotal"
                    FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry" WHERE M."DocDate" BETWEEN :d0 AND :d1) X
            JOIN "OITM" I ON I."ItemCode" = X."ItemCode"
           WHERE I."InvntItem" <> 'Y' AND X."ItemCode" <> :feeItem AND X."LineTotal" <> 0
          UNION ALL
          SELECT "MTC_CA_F_DOCKEY"(X."ObjType", X."DocEntry") || '-LineNum ' || X."LineNum" || ' 指定单价',
                 '⑥ 本期新单据用了指定单价 U_InitPrice ' || TO_NVARCHAR(X."U_InitPrice") || '（系统 Price ' || TO_NVARCHAR(X."Price")
                 || '），暂估按指定单价计：' || TO_NVARCHAR(:initFrom) || ' 以后应很少出现，确认系统 Price 确实有误'
            FROM (SELECT '20' AS "ObjType", M."DocEntry", D."LineNum", D."U_InitPrice", D."Price", M."DocDate"
                    FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry"
                  UNION ALL
                  SELECT '21', M."DocEntry", D."LineNum", D."U_InitPrice", D."Price", M."DocDate"
                    FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry") X
           WHERE X."DocDate" BETWEEN :d0 AND :d1 AND X."DocDate" >= :initFrom AND IFNULL(X."U_InitPrice", 0) <> 0
          UNION ALL
          SELECT "TransCode" || ' ' || "AcctCode" || CASE WHEN "Vendor" <> '' THEN ' ' || "Vendor" ELSE '' END || ' 已过账',
                 '⑦ B1 已过账 ' || TO_NVARCHAR(SUM("Gl")) || '，本次底稿 ' || TO_NVARCHAR(SUM("Dr")) || '，差 ' || TO_NVARCHAR(SUM("Gl") - SUM("Dr"))
            FROM (SELECT H."TransCode", J."Account" AS "AcctCode", IFNULL(J."U_VendorCode", '') AS "Vendor", J."Debit" - J."Credit" AS "Gl", 0 AS "Dr"
                    FROM "OJDT" H JOIN "JDT1" J ON J."TransId" = H."TransId"
                   WHERE H."RefDate" BETWEEN :d0 AND :d1 AND H."TransCode" IN ('PUR1', 'PUR2', 'PUR3', 'PUR4', 'PUR5') AND H."StornoToTr" IS NULL
                  UNION ALL
                  SELECT "TransCode", "AcctCode", IFNULL("VendorCode", ''), 0, "Debit" - "Credit"
                    FROM "MTC_CA_R_JDT" WHERE "RunId" = :RunId
                     AND "TransCode" IN (SELECT DISTINCT "TransCode" FROM "OJDT"
                                          WHERE "RefDate" BETWEEN :d0 AND :d1 AND "TransCode" IN ('PUR1', 'PUR2', 'PUR3', 'PUR4', 'PUR5') AND "StornoToTr" IS NULL))
           GROUP BY "TransCode", "AcctCode", "Vendor"
          HAVING ABS(SUM("Gl") - SUM("Dr")) > 0.01;
    SELECT COUNT(DISTINCT "ObjType" || '-' || "DocEntry"), IFNULL(SUM(CASE WHEN ABS(IFNULL("Diff", 0)) > 0.01 THEN 1 ELSE 0 END), 0)
      INTO nPurDoc, nPurBad FROM :pd;
    SELECT COUNT(*), IFNULL(SUM("OpenAmt"), 0) INTO nInit, initAmt
      FROM "MTC_CA_R_AP_ACCR" A
      LEFT JOIN "PDN1" P ON A."ObjType" = '20' AND P."DocEntry" = A."DocEntry" AND P."LineNum" = A."LineNum"
      LEFT JOIN "RPD1" R ON A."ObjType" = '21' AND R."DocEntry" = A."DocEntry" AND R."LineNum" = A."LineNum"
     WHERE A."RunId" = :RunId AND IFNULL(COALESCE(P."U_InitPrice", R."U_InitPrice"), 0) <> 0;
    CALL "MTC_CA_P_CHECK_PUT"(:RunId, 'POST-15', :t15,
         LEFT('本期采购单据 ' || :nPurDoc || ' 张，单据 × 科目不一致 ' || :nPurBad || ' 行（逐行见执行台“应付暂估 → 凭证勾稽”）。'
              || '截至期末仍未开票、按指定单价 U_InitPrice 暂估的行 ' || :nInit || ' 条，暂估金额 ' || TO_NVARCHAR(:initAmt)
              || '（期初和上线后系统 Price 有误的单据，开票时按指定单价冲暂估、差额进存货）。只警告，不阻断生成凭单。', 1000));

    SELECT COUNT(*) INTO FailCnt FROM "MTC_CA_R_CHECK"
     WHERE "RunId" = :RunId AND "CheckId" IN ('POST-06', 'POST-08', 'POST-09', 'POST-10', 'POST-11', 'POST-12', 'POST-13') AND "Result" = 'FAIL';
END
@@
