-- =====================================================================
-- 新成本框架 第 1 期：运行框架过程（设计稿 2.2、4 的 P00 / P80）
--   MTC_CA_P_LOG_STEP   写步骤日志（自治事务，计算回滚后日志仍在）
--   MTC_CA_P_LOG_NOTE   更新运行中步骤的进度说明（自治事务，执行台轮询时能实时看到）
--   MTC_CA_P_RUN_BEGIN  P00：校验参数、账期、并发，建运行头
--   MTC_CA_P_RUN_END    写运行结束状态（自治事务）
--   MTC_CA_P_RUN_CLEAN  P80：成功删同运行键旧明细 / 失败删本次明细
--   （入口 MTC_CA_P_RUN 在 10_run_entry.sql，依赖 07、08 中的过程）
--   MTC_CA_P_META_SYNC  把库中 MTC_CA_* 表和字段同步到数据字典
--   MTC_CA_V_PERIOD / MTC_CA_P_PERIOD_GUARD / MTC_CA_P_PERIOD_SET  账期状态（2026-10-19：生成凭单后不能正式计算）
-- 替代：旧流程无对应（旧过程每步 DELETE 后 INSERT，无运行日志）。
-- =====================================================================
CREATE OR REPLACE PROCEDURE "MTC_CA_P_LOG_STEP" (
    IN RunId    BIGINT,
    IN StepCode NVARCHAR(20),
    IN Status   NVARCHAR(10),      -- RUNNING 开始；OK / WARN / FAIL 结束
    IN RowCnt   BIGINT,
    IN Msg      NVARCHAR(2000)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    IF :RunId IS NULL THEN
        RETURN;
    END IF;
  BEGIN AUTONOMOUS TRANSACTION
    DECLARE n INT;
    SELECT COUNT(*) INTO n FROM "MTC_CA_RUN_STEP"
     WHERE "RunId" = :RunId AND "StepCode" = :StepCode AND "Status" = 'RUNNING';
    IF :Status = 'RUNNING' OR :n = 0 THEN
        INSERT INTO "MTC_CA_RUN_STEP" ("RunId", "StepNo", "StepCode", "StartTime", "EndTime", "RowCnt", "Status", "Msg")
        SELECT :RunId, IFNULL(MAX("StepNo"), 0) + 1, :StepCode, CURRENT_TIMESTAMP,
               CASE WHEN :Status = 'RUNNING' THEN NULL ELSE CURRENT_TIMESTAMP END, :RowCnt, :Status, :Msg
          FROM "MTC_CA_RUN_STEP" WHERE "RunId" = :RunId;
    ELSE
        UPDATE "MTC_CA_RUN_STEP"
           SET "EndTime" = CURRENT_TIMESTAMP, "Status" = :Status, "RowCnt" = :RowCnt, "Msg" = :Msg
         WHERE "RunId" = :RunId AND "StepCode" = :StepCode AND "Status" = 'RUNNING';
    END IF;
  END;
END
@@
-- 进度说明：只改本次运行中正在执行（RUNNING）的那一步的 Msg，步骤结束时由 LOG_STEP 覆盖成结果说明
CREATE OR REPLACE PROCEDURE "MTC_CA_P_LOG_NOTE" (
    IN RunId BIGINT,
    IN Msg   NVARCHAR(2000)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    IF :RunId IS NULL THEN
        RETURN;
    END IF;
  BEGIN AUTONOMOUS TRANSACTION
    UPDATE "MTC_CA_RUN_STEP" SET "Msg" = LEFT(:Msg, 2000)
     WHERE "RunId" = :RunId AND "Status" = 'RUNNING'
       AND "StepNo" = (SELECT MAX("StepNo") FROM "MTC_CA_RUN_STEP" WHERE "RunId" = :RunId AND "Status" = 'RUNNING');
  END;
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P_RUN_BEGIN" (
    IN  FcCode    NVARCHAR(10),
    IN  RunType   NVARCHAR(1),
    IN  Scenario  NVARCHAR(30),
    IN  UserCode  NVARCHAR(50),
    IN  Initiator NVARCHAR(10),
    OUT RunId     BIGINT,
    OUT Code      INT,
    OUT Msg       NVARCHAR(2000)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE n INT;
    DECLARE stat NVARCHAR(1);
    DECLARE params NCLOB;
    DECLARE scen NVARCHAR(30) := IFNULL(:Scenario, '');
    RunId := NULL;
    Code  := 0;
    Msg   := '';

    IF IFNULL(:RunType, '') NOT IN ('F', 'S') THEN
        Code := -1; Msg := 'RunType 只能是 F（正式）或 S（模拟）'; RETURN;
    END IF;
    IF :RunType = 'F' AND :scen <> '' THEN
        Code := -1; Msg := '正式运行不能带模拟场景'; RETURN;
    END IF;
    IF :RunType = 'S' THEN
        SELECT COUNT(*) INTO n FROM "MTC_CA_C_SCENARIO" WHERE "Scenario" = :scen;
        IF :n = 0 THEN
            Code := -1; Msg := '模拟场景不存在：' || :scen; RETURN;
        END IF;
    END IF;
    IF IFNULL(:Initiator, '') NOT IN ('USER', 'AI') THEN
        Code := -1; Msg := 'Initiator 只能是 USER 或 AI'; RETURN;
    END IF;

    -- 账期：必须存在；正式运行不能算已锁定的账期，模拟运行允许（不写 B1）
    SELECT COUNT(*), MAX("PeriodStat") INTO n, stat FROM "OFPR" WHERE "Code" = :FcCode;
    IF :n = 0 THEN
        Code := -1; Msg := '账期不存在：' || IFNULL(:FcCode, ''); RETURN;
    END IF;
    IF :RunType = 'F' AND :stat = 'Y' THEN
        Code := -1; Msg := '账期已锁定，不能正式计算：' || :FcCode; RETURN;
    END IF;

    -- 同一运行键不能并发
    SELECT COUNT(*) INTO n FROM "MTC_CA_RUN"
     WHERE "FcCode" = :FcCode AND "RunType" = :RunType AND "Scenario" = :scen AND "Status" = 'RUNNING';
    IF :n > 0 THEN
        Code := -1; Msg := '同一账期 / 类型 / 场景已有运行中的计算；如确认已中断，先用 MTC_CA_P_RUN_END 把它标为 FAIL'; RETURN;
    END IF;

    SELECT '{' || IFNULL(STRING_AGG('"' || "ParamCode" || '":"' || REPLACE("Value", '"', '\"') || '"', ',' ORDER BY "ParamCode"), '') || '}'
      INTO params
      FROM "MTC_CA_C_PARAM" WHERE :FcCode BETWEEN "FromFc" AND "ToFc";

    SELECT "MTC_CA_SEQ_RUN".NEXTVAL INTO RunId FROM DUMMY;
    -- 运行头单独提交：计算失败回滚时运行记录仍在
    BEGIN AUTONOMOUS TRANSACTION
        INSERT INTO "MTC_CA_RUN" ("RunId", "FcCode", "RunType", "Scenario", "Initiator", "UserCode", "StartTime", "Status", "Params")
        VALUES (:RunId, :FcCode, :RunType, :scen, :Initiator, :UserCode, CURRENT_TIMESTAMP, 'RUNNING', :params);
    END;
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P_RUN_END" (
    IN RunId     BIGINT,
    IN Status    NVARCHAR(10),
    IN Msg       NVARCHAR(2000)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    BEGIN AUTONOMOUS TRANSACTION
        UPDATE "MTC_CA_RUN"
           SET "Status" = :Status, "EndTime" = CURRENT_TIMESTAMP, "Msg" = :Msg
         WHERE "RunId" = :RunId;
        -- 出错时停在 RUNNING 的步骤就是出错的那一步
        UPDATE "MTC_CA_RUN_STEP"
           SET "Status" = CASE WHEN :Status = 'OK' THEN 'OK' ELSE 'FAIL' END, "EndTime" = CURRENT_TIMESTAMP
         WHERE "RunId" = :RunId AND "Status" = 'RUNNING';
    END;
END
@@
-- 明细表约定：表名以 MTC_CA_S_ / MTC_CA_R_ 开头，且带 FcCode、RunType、Scenario、RunId 四列
CREATE OR REPLACE PROCEDURE "MTC_CA_P_RUN_CLEAN" (
    IN RunId  BIGINT,
    IN Mode   NVARCHAR(4),          -- OK：删同运行键下其他 RunId；FAIL：删本次 RunId；BLK：只删本次的快照（保留校验结果）；
                                    -- NCV：未收敛时保留本次快照和结果，只删同运行键下以前未收敛运行的（2026-10-29，排查用）
                                    --      P40 及以后出错时也用 NCV；以前保留下来的失败运行一并删掉（2026-10-30）
    OUT RowCnt BIGINT
)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc   NVARCHAR(10);
    DECLARE rt   NVARCHAR(1);
    DECLARE scen NVARCHAR(30);
    DECLARE CURSOR c_tab FOR
        SELECT t."TABLE_NAME"
          FROM "TABLES" t
         WHERE t."SCHEMA_NAME" = CURRENT_SCHEMA
           AND (t."TABLE_NAME" LIKE 'MTC\_CA\_S\_%' ESCAPE '\' OR t."TABLE_NAME" LIKE 'MTC\_CA\_R\_%' ESCAPE '\')
           AND 4 = (SELECT COUNT(*) FROM "TABLE_COLUMNS" c
                     WHERE c."SCHEMA_NAME" = t."SCHEMA_NAME" AND c."TABLE_NAME" = t."TABLE_NAME"
                       AND c."COLUMN_NAME" IN ('FcCode', 'RunType', 'Scenario', 'RunId'));
    RowCnt := 0;
    IF :RunId IS NULL THEN
        RETURN;
    END IF;
    SELECT MAX("FcCode"), MAX("RunType"), MAX("Scenario") INTO fc, rt, scen FROM "MTC_CA_RUN" WHERE "RunId" = :RunId;
    FOR r AS c_tab DO
        IF :Mode = 'OK' THEN
            EXEC 'DELETE FROM "' || r."TABLE_NAME" || '" WHERE "FcCode" = ? AND "RunType" = ? AND "Scenario" = ? AND "RunId" <> ?'
                USING :fc, :rt, :scen, :RunId;
        ELSEIF :Mode = 'NCV' THEN
            EXEC 'DELETE FROM "' || r."TABLE_NAME" || '" WHERE "FcCode" = ? AND "RunType" = ? AND "Scenario" = ? AND "RunId" <> ?'
                 || ' AND "RunId" IN (SELECT "RunId" FROM "MTC_CA_RUN" WHERE "Status" IN (''NOCONV'', ''FAIL''))'
                USING :fc, :rt, :scen, :RunId;
        ELSEIF :Mode = 'BLK' THEN
            IF LEFT(r."TABLE_NAME", 9) = 'MTC_CA_S_' THEN
                EXEC 'DELETE FROM "' || r."TABLE_NAME" || '" WHERE "RunId" = ?' USING :RunId;
            END IF;
        ELSE
            EXEC 'DELETE FROM "' || r."TABLE_NAME" || '" WHERE "RunId" = ?' USING :RunId;
        END IF;
        RowCnt := :RowCnt + ::ROWCOUNT;
    END FOR;
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P_META_SYNC" ()
LANGUAGE SQLSCRIPT AS
BEGIN
    MERGE INTO "MTC_CA_M_TABLE" m
    USING (SELECT t."TABLE_NAME", t."COMMENTS",
                  CASE WHEN t."TABLE_NAME" LIKE 'MTC\_CA\_RUN%' ESCAPE '\' THEN 'RUN'
                       ELSE SUBSTR_BEFORE(SUBSTRING(t."TABLE_NAME", 8), '_') END AS "Layer"
             FROM "TABLES" t
            WHERE t."SCHEMA_NAME" = CURRENT_SCHEMA AND t."TABLE_NAME" LIKE 'MTC\_CA\_%' ESCAPE '\') s
       ON m."TableName" = s."TABLE_NAME"
    WHEN MATCHED THEN UPDATE SET m."InDb" = 'Y', m."Layer" = s."Layer",
                                 m."Descr" = IFNULL(s."COMMENTS", m."Descr")
    WHEN NOT MATCHED THEN INSERT ("TableName", "Layer", "Descr", "InDb")
                          VALUES (s."TABLE_NAME", s."Layer", s."COMMENTS", 'Y');

    UPDATE "MTC_CA_M_TABLE" SET "InDb" = 'N'
     WHERE "TableName" NOT IN (SELECT "TABLE_NAME" FROM "TABLES" WHERE "SCHEMA_NAME" = CURRENT_SCHEMA);

    MERGE INTO "MTC_CA_M_COLUMN" m
    USING (SELECT c."TABLE_NAME", c."COLUMN_NAME", c."POSITION", c."COMMENTS",
                  c."DATA_TYPE_NAME" || CASE WHEN c."DATA_TYPE_NAME" IN ('DECIMAL') THEN '(' || c."LENGTH" || ',' || c."SCALE" || ')'
                                             WHEN c."DATA_TYPE_NAME" IN ('NVARCHAR', 'VARCHAR') THEN '(' || c."LENGTH" || ')'
                                             ELSE '' END AS "DataType"
             FROM "TABLE_COLUMNS" c
            WHERE c."SCHEMA_NAME" = CURRENT_SCHEMA AND c."TABLE_NAME" LIKE 'MTC\_CA\_%' ESCAPE '\') s
       ON m."TableName" = s."TABLE_NAME" AND m."ColumnName" = s."COLUMN_NAME"
    WHEN MATCHED THEN UPDATE SET m."Position" = s."POSITION", m."DataType" = s."DataType", m."InDb" = 'Y',
                                 m."Descr" = IFNULL(s."COMMENTS", m."Descr")
    WHEN NOT MATCHED THEN INSERT ("TableName", "ColumnName", "Position", "DataType", "Descr", "InDb")
                          VALUES (s."TABLE_NAME", s."COLUMN_NAME", s."POSITION", s."DataType", s."COMMENTS", 'Y');

    UPDATE "MTC_CA_M_COLUMN" m SET "InDb" = 'N'
     WHERE NOT EXISTS (SELECT 1 FROM "TABLE_COLUMNS" c
                        WHERE c."SCHEMA_NAME" = CURRENT_SCHEMA AND c."TABLE_NAME" = m."TableName" AND c."COLUMN_NAME" = m."ColumnName");

    -- B1 自定义表（OUTB 登记的全部 @ 表，Layer = B1）：表说明取 OUTB.Descr，U_ 字段说明取 CUFD.Descr（用户 2026-10-14：
    -- 在执行台“说明书”里能查到工时等数据存在 B1 哪张表）
    MERGE INTO "MTC_CA_M_TABLE" m
    USING (SELECT '@' || U."TableName" AS "TableName",
                  U."Descr" || CASE U."ObjectType" WHEN 1 THEN '（主数据）' WHEN 2 THEN '（主数据行）' WHEN 3 THEN '（单据）'
                                                   WHEN 4 THEN '（单据行）' ELSE '（无对象）' END AS "Descr"
             FROM "OUTB" U
            WHERE EXISTS (SELECT 1 FROM "TABLES" t WHERE t."SCHEMA_NAME" = CURRENT_SCHEMA AND t."TABLE_NAME" = '@' || U."TableName")) s
       ON m."TableName" = s."TableName"
    WHEN MATCHED THEN UPDATE SET m."InDb" = 'Y', m."Layer" = 'B1', m."Descr" = s."Descr"
    WHEN NOT MATCHED THEN INSERT ("TableName", "Layer", "Descr", "InDb") VALUES (s."TableName", 'B1', s."Descr", 'Y');

    MERGE INTO "MTC_CA_M_COLUMN" m
    USING (SELECT c."TABLE_NAME", c."COLUMN_NAME", c."POSITION", F."Descr",
                  c."DATA_TYPE_NAME" || CASE WHEN c."DATA_TYPE_NAME" IN ('DECIMAL') THEN '(' || c."LENGTH" || ',' || c."SCALE" || ')'
                                             WHEN c."DATA_TYPE_NAME" IN ('NVARCHAR', 'VARCHAR') THEN '(' || c."LENGTH" || ')'
                                             ELSE '' END AS "DataType"
             FROM "TABLE_COLUMNS" c
             JOIN "MTC_CA_M_TABLE" T ON T."TableName" = c."TABLE_NAME" AND T."Layer" = 'B1'
             LEFT JOIN "CUFD" F ON F."TableID" = c."TABLE_NAME" AND 'U_' || F."AliasID" = c."COLUMN_NAME"
            WHERE c."SCHEMA_NAME" = CURRENT_SCHEMA) s
       ON m."TableName" = s."TABLE_NAME" AND m."ColumnName" = s."COLUMN_NAME"
    WHEN MATCHED THEN UPDATE SET m."Position" = s."POSITION", m."DataType" = s."DataType", m."InDb" = 'Y', m."Descr" = s."Descr"
    WHEN NOT MATCHED THEN INSERT ("TableName", "ColumnName", "Position", "DataType", "Descr", "InDb")
                          VALUES (s."TABLE_NAME", s."COLUMN_NAME", s."POSITION", s."DataType", s."Descr", 'Y');

    SELECT 0 AS "Code", '数据字典已同步' AS "Msg" FROM DUMMY;
END
@@
-- ---------------------------------------------------------------------
-- 账期状态（用户 2026-10-19，设计稿 Q36–Q40）
--   OPEN 未计算 → CALC 已计算（正式计算成功，可反复重算）→ POSTED 已生成凭单（OBTF 日记账凭单，待财务过账）
--   POSTED 时不能正式计算、不能重做期初承接；模拟计算和查询照常。撤销凭单（全部未过账才能撤销）后回到 CALC。
--   B1 锁定（OFPR.PeriodStat='Y'）由 P_RUN_BEGIN 拒绝正式计算；其他非 N 状态只提示（Q40）。
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW "MTC_CA_V_PERIOD" AS
SELECT O."Code" AS "FcCode", O."PeriodStat",
       CASE WHEN O."PeriodStat" = 'Y' THEN 'LOCKED' ELSE IFNULL(P."Status", 'OPEN') END AS "Status",
       IFNULL(P."Status", 'OPEN') AS "CostStatus",
       P."CalcRunId", P."PostRunId", P."PostUser", P."PostTime", P."UpdUser", P."UpdTime",
       R."LastOkRunId"
  FROM "OFPR" O
  LEFT JOIN "MTC_CA_PERIOD" P ON P."FcCode" = O."Code"
  LEFT JOIN (SELECT "FcCode", MAX("RunId") AS "LastOkRunId" FROM "MTC_CA_RUN"
              WHERE "RunType" = 'F' AND "Scenario" = '' AND "Status" = 'OK' GROUP BY "FcCode") R ON R."FcCode" = O."Code"
@@
-- 动作前检查：Action = CALC 正式计算 / BOOT 期初承接。Code -1 = 不允许（Msg 是原因）；Code 0 时 Msg 非空是警告（不阻断）。
CREATE OR REPLACE PROCEDURE "MTC_CA_P_PERIOD_GUARD" (
    IN  FcCode NVARCHAR(10),
    IN  Action NVARCHAR(10),
    OUT Code   INT,
    OUT Msg    NVARCHAR(2000)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE tgt NVARCHAR(10) := :FcCode;
    DECLARE st NVARCHAR(10); DECLARE pr BIGINT; DECLARE pu NVARCHAR(50); DECLARE pt TIMESTAMP;
    DECLARE ps NVARCHAR(1); DECLARE prev NVARCHAR(10); DECLARE pst NVARCHAR(10); DECLARE startFc NVARCHAR(10);
    DECLARE n INT;
    Code := 0; Msg := '';
    SELECT MAX("Value") INTO startFc FROM "MTC_CA_C_PARAM" WHERE "ParamCode" = 'START_FC' AND :FcCode BETWEEN "FromFc" AND "ToFc";
    -- 期初承接影响的是起始账期的期初
    IF :Action = 'BOOT' THEN
        tgt := :startFc;
    END IF;
    SELECT MAX("Status"), MAX("PostRunId"), MAX("PostUser"), MAX("PostTime") INTO st, pr, pu, pt
      FROM "MTC_CA_PERIOD" WHERE "FcCode" = :tgt;
    -- 生成到一半失败（有已生成的凭单、状态还没到 POSTED）同样拦
    IF IFNULL(:st, '') <> 'POSTED' THEN
        SELECT COUNT(*), MAX("RunId") INTO n, pr FROM "MTC_CA_JV" WHERE "FcCode" = :tgt AND "Status" = 'CREATED';
        IF :n > 0 THEN
            Code := -1;
            Msg := '账期 ' || :tgt || ' 已生成部分凭单（运行 #' || IFNULL(TO_VARCHAR(:pr), '') || '，' || :n || ' 张），不能'
                   || CASE WHEN :Action = 'BOOT' THEN '重做期初承接' ELSE '正式计算' END || '；请在“生成凭单”页继续生成剩下的，或撤销凭单';
            RETURN;
        END IF;
    END IF;
    IF IFNULL(:st, '') = 'POSTED' THEN
        Code := -1;
        Msg := CASE WHEN :Action = 'BOOT'
                    THEN '起始账期 ' || :tgt || ' 已生成凭单（运行 #' || IFNULL(TO_VARCHAR(:pr), '') || '），不能重做期初承接；需要重做时先撤销该期凭单'
                    ELSE '账期 ' || :tgt || ' 已生成凭单（运行 #' || IFNULL(TO_VARCHAR(:pr), '') || '，' || IFNULL(:pu, '') || ' '
                         || IFNULL(TO_VARCHAR(:pt, 'YYYY-MM-DD HH24:MI'), '') || '），不能正式计算；需要重算时先撤销凭单（凭单全部未过账才能撤销）' END;
        RETURN;
    END IF;
    IF :Action = 'CALC' THEN
        -- Q40：B1 账期除“已锁定”（P_RUN_BEGIN 拒绝）外的其他状态只提示
        SELECT MAX("PeriodStat") INTO ps FROM "OFPR" WHERE "Code" = :FcCode;
        IF IFNULL(:ps, 'N') NOT IN ('N', 'Y') THEN
            Msg := 'B1 账期状态为 ' || :ps || CASE :ps WHEN 'C' THEN '（期末结算）' WHEN 'S' THEN '（除销售外锁定）' ELSE '' END || '，仍允许计算';
        END IF;
        -- Q39：上期（起始账期及以后）还没生成凭单只警告
        SELECT MAX("Code") INTO prev FROM "OFPR" WHERE "Code" < :FcCode;
        IF :prev IS NOT NULL AND :prev >= IFNULL(:startFc, '9999-99') THEN
            SELECT MAX("Status") INTO pst FROM "MTC_CA_PERIOD" WHERE "FcCode" = :prev;
            IF IFNULL(:pst, '') <> 'POSTED' THEN
                Msg := :Msg || CASE WHEN :Msg <> '' THEN '；' ELSE '' END
                       || '上期 ' || :prev || ' 还没有生成凭单，本期期初取上期最近一次成功的正式运行，上期重算后本期要重算';
            END IF;
        END IF;
    END IF;
END
@@
-- 改账期状态并记日志。ToStatus：CALC（正式计算成功 / 撤销凭单）、POSTED（生成凭单）、OPEN（清除）。
-- 由 P_RUN（计算成功）和以后的生成 / 撤销凭单调用，调用方负责提交。
CREATE OR REPLACE PROCEDURE "MTC_CA_P_PERIOD_SET" (
    IN FcCode   NVARCHAR(10),
    IN ToStatus NVARCHAR(10),
    IN RunId    BIGINT,
    IN UserCode NVARCHAR(50),
    IN Msg      NVARCHAR(2000)
)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fromSt NVARCHAR(10);
    DECLARE n INT;
    IF IFNULL(:ToStatus, '') NOT IN ('OPEN', 'CALC', 'POSTED') THEN
        SIGNAL SQL_ERROR_CODE 10001 SET MESSAGE_TEXT = '账期状态只能是 OPEN / CALC / POSTED';
    END IF;
    SELECT COUNT(*), IFNULL(MAX("Status"), 'OPEN') INTO n, fromSt FROM "MTC_CA_PERIOD" WHERE "FcCode" = :FcCode;
    IF :ToStatus = 'OPEN' THEN
        DELETE FROM "MTC_CA_PERIOD" WHERE "FcCode" = :FcCode;
    ELSE
        IF :n = 0 THEN
            INSERT INTO "MTC_CA_PERIOD" ("FcCode", "Status") VALUES (:FcCode, :ToStatus);
        END IF;
        UPDATE "MTC_CA_PERIOD"
           SET "Status"    = :ToStatus,
               "CalcRunId" = CASE WHEN :ToStatus = 'CALC' AND :fromSt <> 'POSTED' THEN :RunId ELSE "CalcRunId" END,
               "PostRunId" = CASE WHEN :ToStatus = 'POSTED' THEN :RunId END,
               "PostUser"  = CASE WHEN :ToStatus = 'POSTED' THEN :UserCode END,
               "PostTime"  = CASE WHEN :ToStatus = 'POSTED' THEN CURRENT_TIMESTAMP END,
               "UpdUser"   = :UserCode,
               "UpdTime"   = CURRENT_TIMESTAMP
         WHERE "FcCode" = :FcCode;
    END IF;
    INSERT INTO "MTC_CA_PERIOD_LOG" ("FcCode", "LogTime", "FromStatus", "ToStatus", "RunId", "UserCode", "Msg")
    VALUES (:FcCode, CURRENT_TIMESTAMP, :fromSt, :ToStatus, :RunId, :UserCode, LEFT(:Msg, 2000));
END
