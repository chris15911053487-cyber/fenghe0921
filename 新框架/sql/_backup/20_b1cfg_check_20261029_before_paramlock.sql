-- =====================================================================
-- B1 成本配置校验（用户 2026-10-28）：@MTC_CA_PARAM 计算参数、@MTC_CA_POOL / 1 / 2 费用池
--   MTC_CA_V_B1CFG_ISSUES  问题清单（Obj, KeyCode, Msg）：B1 保存校验、P05 同步、执行台“检查 B1 配置”共用这一个口径
--   MTC_CA_P_B1CFG_TN      给 SBO_SP_TransactionNotification 调用：保存的那条记录有问题时返回 error = 1 和中文提示
--                          （TN 里加的那一段见 20_b1cfg_tn_snippet.sql）
-- 视图直接引用 B1 自定义表，所以不在部署包里（build_deploy.py 只收 0x_ / 1x_）：
--   在 B1 里建好 @MTC_CA_PARAM（和字段）、@MTC_CA_POOL / 1 / 2 之后执行本文件；还要求 OPRC.U_CalType、OITB.U_ItemGrpType 存在。
--   python3 新框架/tools/hana_exec.py -f 新框架/sql/20_b1cfg_check.sql
-- 依赖 MTC_CA_C_PARAM_DEF（02 / 04 或 patch_20261028_param_ui.sql）。离线写的，还没编译。
-- KeyCode = 记录的 Code（参数行的 Code；费用池是池代码，成本中心 / 分摊范围的问题也记在池上，Msg 写明第几行）。
-- 账期为空 = 不限（起始 0000-00、截止 9999-99）。
-- =====================================================================
CREATE OR REPLACE VIEW "MTC_CA_V_B1CFG_ISSUES" AS
-- ---------- 计算参数 @MTC_CA_PARAM ----------
SELECT 'MTC_CA_PARAM' AS "Obj", B."Code" AS "KeyCode",
       CASE WHEN B."P" = 'CLOSE_DIF_POOL' THEN '关单差异池不在这里维护，请在费用池上勾“关单差异池”'
            ELSE '参数代码 ' || B."P" || ' 不认识（Code 应是参数代码，第二段起写 参数代码@起始账期）' END AS "Msg"
  FROM (SELECT TRIM("Code") AS "Code", SUBSTR_BEFORE(TRIM("Code") || '@', '@') AS "P" FROM "@MTC_CA_PARAM") B
 WHERE NOT EXISTS (SELECT 1 FROM "MTC_CA_C_PARAM_DEF" D WHERE D."ParamCode" = B."P")
UNION ALL
SELECT 'MTC_CA_PARAM', TRIM("Code"), 'Code 中 @ 后面应等于起始账期 ' || IFNULL(NULLIF(TRIM("U_FromFc"), ''), '（空）')
  FROM "@MTC_CA_PARAM"
 WHERE SUBSTR_AFTER(TRIM("Code"), '@') <> '' AND SUBSTR_AFTER(TRIM("Code"), '@') <> IFNULL(TRIM("U_FromFc"), '')
UNION ALL
SELECT 'MTC_CA_PARAM', TRIM("Code"), '起始账期 ' || TRIM("U_FromFc") || ' 不是 YYYY-MM 格式（如 2026-11）'
  FROM "@MTC_CA_PARAM"
 WHERE IFNULL(TRIM("U_FromFc"), '') <> '' AND NOT TRIM("U_FromFc") LIKE_REGEXPR '^[0-9]{4}-(0[1-9]|1[0-2])$'
UNION ALL
SELECT 'MTC_CA_PARAM', TRIM("Code"), '截止账期 ' || TRIM("U_ToFc") || ' 不是 YYYY-MM 格式（如 2026-11）'
  FROM "@MTC_CA_PARAM"
 WHERE IFNULL(TRIM("U_ToFc"), '') <> '' AND NOT TRIM("U_ToFc") LIKE_REGEXPR '^[0-9]{4}-(0[1-9]|1[0-2])$'
UNION ALL
SELECT 'MTC_CA_PARAM', TRIM("Code"), '起始账期晚于截止账期'
  FROM "@MTC_CA_PARAM"
 WHERE IFNULL(NULLIF(TRIM("U_FromFc"), ''), '0000-00') > IFNULL(NULLIF(TRIM("U_ToFc"), ''), '9999-99')
UNION ALL
-- 同一参数的账期段重叠（两行各报一次）
SELECT 'MTC_CA_PARAM', A."Code", '与 ' || B."Code" || ' 的账期重叠：同一参数每个账期只能有一个值'
  FROM (SELECT TRIM("Code") AS "Code", SUBSTR_BEFORE(TRIM("Code") || '@', '@') AS "P",
               IFNULL(NULLIF(TRIM("U_FromFc"), ''), '0000-00') AS "F", IFNULL(NULLIF(TRIM("U_ToFc"), ''), '9999-99') AS "T" FROM "@MTC_CA_PARAM") A
  JOIN (SELECT TRIM("Code") AS "Code", SUBSTR_BEFORE(TRIM("Code") || '@', '@') AS "P",
               IFNULL(NULLIF(TRIM("U_FromFc"), ''), '0000-00') AS "F", IFNULL(NULLIF(TRIM("U_ToFc"), ''), '9999-99') AS "T" FROM "@MTC_CA_PARAM") B
    ON B."P" = A."P" AND B."Code" <> A."Code" AND A."F" <= B."T" AND B."F" <= A."T"
UNION ALL
-- 取值：按参数目录的类型检查
SELECT 'MTC_CA_PARAM', B."Code",
       CASE WHEN B."V" = '' THEN '取值不能为空'
            WHEN D."DataType" = 'DEC'  THEN '取值应是数字，实际 ' || B."V"
            WHEN D."DataType" = 'INT'  THEN '取值应是整数，实际 ' || B."V"
            WHEN D."DataType" = 'FC'   THEN '取值应是账期 YYYY-MM，实际 ' || B."V"
            WHEN D."DataType" = 'DATE' THEN '取值应是日期 YYYY-MM-DD，实际 ' || B."V"
            WHEN D."DataType" = 'LIST' THEN '列表太长（最多 196 个字符）'
            ELSE '取值只能是 ' || D."Choices" || '，实际 ' || B."V" END
  FROM (SELECT TRIM("Code") AS "Code", SUBSTR_BEFORE(TRIM("Code") || '@', '@') AS "P", IFNULL(TRIM("U_Value"), '') AS "V" FROM "@MTC_CA_PARAM") B
  JOIN "MTC_CA_C_PARAM_DEF" D ON D."ParamCode" = B."P"
 WHERE (B."V" = '' AND D."DataType" <> 'LIST')
    OR (B."V" <> '' AND D."DataType" = 'DEC'  AND NOT B."V" LIKE_REGEXPR '^-?[0-9]+(\.[0-9]+)?$')
    OR (B."V" <> '' AND D."DataType" = 'INT'  AND NOT B."V" LIKE_REGEXPR '^-?[0-9]+$')
    OR (B."V" <> '' AND D."DataType" = 'FC'   AND NOT B."V" LIKE_REGEXPR '^[0-9]{4}-(0[1-9]|1[0-2])$')
    OR (B."V" <> '' AND D."DataType" = 'DATE' AND NOT B."V" LIKE_REGEXPR '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$')
    OR (D."DataType" = 'LIST' AND LENGTH(B."V") > 196)
    OR (B."V" <> '' AND D."DataType" = 'STR' AND IFNULL(D."Choices", '') <> ''
        AND NOT (',' || D."Choices" || ',') LIKE ('%,' || UPPER(B."V") || ',%'))
UNION ALL
-- ---------- 费用池表头 @MTC_CA_POOL ----------
SELECT 'MTC_CA_POOL', TRIM("Code"), '“默认池”只能填 Y 或 N'
  FROM "@MTC_CA_POOL" WHERE IFNULL("U_IsDefault", 'N') NOT IN ('Y', 'N')
UNION ALL
SELECT 'MTC_CA_POOL', TRIM("Code"), '“关单差异池”只能填 Y 或 N'
  FROM "@MTC_CA_POOL" WHERE IFNULL("U_IsCloseDif", 'N') NOT IN ('Y', 'N')
UNION ALL
-- 正好一个由 PRE-18 在运行时查；保存时只挡“多于一个”，换池时可以先取消原来的再设新的
SELECT 'MTC_CA_POOL', "Code", '默认池只能有一个，现在有 ' || "N" || ' 个'
  FROM (SELECT TRIM("Code") AS "Code", COUNT(*) OVER () AS "N" FROM "@MTC_CA_POOL" WHERE "U_IsDefault" = 'Y') X
 WHERE "N" > 1
UNION ALL
SELECT 'MTC_CA_POOL', "Code", '关单差异池只能有一个，现在有 ' || "N" || ' 个'
  FROM (SELECT TRIM("Code") AS "Code", COUNT(*) OVER () AS "N" FROM "@MTC_CA_POOL" WHERE "U_IsCloseDif" = 'Y') X
 WHERE "N" > 1
UNION ALL
-- ---------- 成本中心 @MTC_CA_POOL1 ----------
SELECT 'MTC_CA_POOL', TRIM(S."Code"), '成本中心第 ' || S."LineId" || ' 行：' || TRIM(S."U_OcrCode") || ' 不是成本中心代码，也没有成本中心的成本计入类型（U_CalType）等于它'
  FROM "@MTC_CA_POOL1" S
 WHERE IFNULL(TRIM(S."U_OcrCode"), '') <> ''
   AND NOT EXISTS (SELECT 1 FROM "OPRC" P WHERE P."PrcCode" = TRIM(S."U_OcrCode") OR TRIM(P."U_CalType") = TRIM(S."U_OcrCode"))
UNION ALL
SELECT 'MTC_CA_POOL', TRIM("Code"), '成本中心第 ' || "LineId" || ' 行：起止账期应是 YYYY-MM（如 2026-11），且起始不晚于截止'
  FROM "@MTC_CA_POOL1"
 WHERE (IFNULL(TRIM("U_FromFc"), '') <> '' AND NOT TRIM("U_FromFc") LIKE_REGEXPR '^[0-9]{4}-(0[1-9]|1[0-2])$')
    OR (IFNULL(TRIM("U_ToFc"), '') <> '' AND NOT TRIM("U_ToFc") LIKE_REGEXPR '^[0-9]{4}-(0[1-9]|1[0-2])$')
    OR IFNULL(NULLIF(TRIM("U_FromFc"), ''), '0000-00') > IFNULL(NULLIF(TRIM("U_ToFc"), ''), '9999-99')
UNION ALL
-- 同一成本中心（或成本计入类型）账期重叠，含跨池：一个成本中心同一账期只能进一个池
SELECT 'MTC_CA_POOL', A."Code", '成本中心第 ' || A."LineId" || ' 行：' || A."Ocr" || ' 与费用池 ' || B."Code" || ' 第 ' || B."LineId" || ' 行的账期重叠'
  FROM (SELECT TRIM("Code") AS "Code", "LineId", TRIM("U_OcrCode") AS "Ocr",
               IFNULL(NULLIF(TRIM("U_FromFc"), ''), '0000-00') AS "F", IFNULL(NULLIF(TRIM("U_ToFc"), ''), '9999-99') AS "T"
          FROM "@MTC_CA_POOL1" WHERE IFNULL(TRIM("U_OcrCode"), '') <> '') A
  JOIN (SELECT TRIM("Code") AS "Code", "LineId", TRIM("U_OcrCode") AS "Ocr",
               IFNULL(NULLIF(TRIM("U_FromFc"), ''), '0000-00') AS "F", IFNULL(NULLIF(TRIM("U_ToFc"), ''), '9999-99') AS "T"
          FROM "@MTC_CA_POOL1" WHERE IFNULL(TRIM("U_OcrCode"), '') <> '') B
    ON B."Ocr" = A."Ocr" AND NOT (B."Code" = A."Code" AND B."LineId" = A."LineId") AND A."F" <= B."T" AND B."F" <= A."T"
UNION ALL
-- ---------- 分摊范围 @MTC_CA_POOL2 ----------
SELECT 'MTC_CA_POOL', TRIM("Code"), '分摊范围第 ' || "LineId" || ' 行：匹配方式只能是 GRPTYPE（车间类别）或 GRP（物料组），实际 ' || TRIM("U_MatchBy")
  FROM "@MTC_CA_POOL2"
 WHERE IFNULL(TRIM("U_MatchVal"), '') <> '' AND UPPER(IFNULL(TRIM("U_MatchBy"), '')) NOT IN ('', 'GRP', 'GRPTYPE')
UNION ALL
SELECT 'MTC_CA_POOL', TRIM(T."Code"),
       '分摊范围第 ' || T."LineId" || ' 行：' || CASE WHEN UPPER(IFNULL(TRIM(T."U_MatchBy"), '')) = 'GRP' THEN '物料组 ' ELSE '车间类别（物料组上的 U_ItemGrpType）' END
       || TRIM(T."U_MatchVal") || ' 不存在'
  FROM "@MTC_CA_POOL2" T
 WHERE IFNULL(TRIM(T."U_MatchVal"), '') <> ''
   AND ((UPPER(IFNULL(TRIM(T."U_MatchBy"), '')) = 'GRP'
         AND NOT EXISTS (SELECT 1 FROM "OITB" B WHERE TO_NVARCHAR(B."ItmsGrpCod") = TRIM(T."U_MatchVal")))
     OR (UPPER(IFNULL(TRIM(T."U_MatchBy"), '')) IN ('', 'GRPTYPE')
         AND NOT EXISTS (SELECT 1 FROM "OITB" B WHERE TRIM(B."U_ItemGrpType") = TRIM(T."U_MatchVal"))))
UNION ALL
SELECT 'MTC_CA_POOL', TRIM("Code"), '分摊范围第 ' || "LineId" || ' 行：订单类型只能填数字，用逗号分隔（如 10,20,30,40），空 = 10,20,30,40'
  FROM "@MTC_CA_POOL2"
 WHERE IFNULL(TRIM("U_WorTypes"), '') <> ''
   AND NOT REPLACE(REPLACE(TRIM("U_WorTypes"), ' ', ''), '，', ',') LIKE_REGEXPR '^[0-9]+(,[0-9]+)*$'
UNION ALL
SELECT 'MTC_CA_POOL', TRIM("Code"), '分摊范围第 ' || "LineId" || ' 行：起止账期应是 YYYY-MM（如 2026-11），且起始不晚于截止'
  FROM "@MTC_CA_POOL2"
 WHERE (IFNULL(TRIM("U_FromFc"), '') <> '' AND NOT TRIM("U_FromFc") LIKE_REGEXPR '^[0-9]{4}-(0[1-9]|1[0-2])$')
    OR (IFNULL(TRIM("U_ToFc"), '') <> '' AND NOT TRIM("U_ToFc") LIKE_REGEXPR '^[0-9]{4}-(0[1-9]|1[0-2])$')
    OR IFNULL(NULLIF(TRIM("U_FromFc"), ''), '0000-00') > IFNULL(NULLIF(TRIM("U_ToFc"), ''), '9999-99')
UNION ALL
-- 同一匹配方式 + 匹配值账期重叠，含跨池（Q22：同一产品只能属于一个池；混用 GRP / GRPTYPE 的重叠由 PRE-18 按产品查）
SELECT 'MTC_CA_POOL', A."Code", '分摊范围第 ' || A."LineId" || ' 行：' || A."MB" || ' ' || A."MV" || ' 与费用池 ' || B."Code" || ' 第 ' || B."LineId" || ' 行的账期重叠'
  FROM (SELECT TRIM("Code") AS "Code", "LineId", UPPER(IFNULL(NULLIF(TRIM("U_MatchBy"), ''), 'GRPTYPE')) AS "MB", TRIM("U_MatchVal") AS "MV",
               IFNULL(NULLIF(TRIM("U_FromFc"), ''), '0000-00') AS "F", IFNULL(NULLIF(TRIM("U_ToFc"), ''), '9999-99') AS "T"
          FROM "@MTC_CA_POOL2" WHERE IFNULL(TRIM("U_MatchVal"), '') <> '') A
  JOIN (SELECT TRIM("Code") AS "Code", "LineId", UPPER(IFNULL(NULLIF(TRIM("U_MatchBy"), ''), 'GRPTYPE')) AS "MB", TRIM("U_MatchVal") AS "MV",
               IFNULL(NULLIF(TRIM("U_FromFc"), ''), '0000-00') AS "F", IFNULL(NULLIF(TRIM("U_ToFc"), ''), '9999-99') AS "T"
          FROM "@MTC_CA_POOL2" WHERE IFNULL(TRIM("U_MatchVal"), '') <> '') B
    ON B."MB" = A."MB" AND B."MV" = A."MV" AND NOT (B."Code" = A."Code" AND B."LineId" = A."LineId") AND A."F" <= B."T" AND B."F" <= A."T"
@@
COMMENT ON VIEW "MTC_CA_V_B1CFG_ISSUES" IS 'B1 成本配置（@MTC_CA_PARAM、@MTC_CA_POOL / 1 / 2）的问题清单：B1 保存校验、P05 同步、执行台“检查 B1 配置”共用'
@@
-- SBO_SP_TransactionNotification 调用（object_type = UDO 代码，KeyVal = list_of_cols_val_tab_del = 记录的 Code）
CREATE OR REPLACE PROCEDURE "MTC_CA_P_B1CFG_TN" (IN ObjType NVARCHAR(30), IN KeyVal NVARCHAR(255),
                                                 OUT err INT, OUT errMsg NVARCHAR(200))
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    DECLARE n INT;
    err := 0; errMsg := '';
    SELECT COUNT(*) INTO n FROM "MTC_CA_V_B1CFG_ISSUES" WHERE "Obj" = :ObjType AND "KeyCode" = TRIM(:KeyVal);
    IF :n > 0 THEN
        SELECT TOP 1 LEFT('[成本配置] ' || "KeyCode" || '：' || "Msg" || CASE WHEN :n > 1 THEN '（共 ' || :n || ' 个问题）' ELSE '' END, 200)
          INTO errMsg
          FROM "MTC_CA_V_B1CFG_ISSUES" WHERE "Obj" = :ObjType AND "KeyCode" = TRIM(:KeyVal) ORDER BY "Msg";
        err := 1;
    END IF;
END
@@
