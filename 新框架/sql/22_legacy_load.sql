-- =====================================================================
-- 新旧报表合并：旧框架历史回填成“历史运行”（RunType H，Scenario LEGACY；方案见 新框架/报表合并方案.md，用户 2026-11-02 确认）
-- CALL "MTC_CA_P_LEGACY_LOAD"('2024-12', '2026-08', 'manager');   -- 账期从早到晚逐期回填，每期提交一次，可重跑
-- 把旧 MTC_COST_* 结果转换写进 MTC_CA_S_* / R_*，成本报表 MTC_CA_RPT_* 经 MTC_CA_F_RPT_RUN 在承接账期（BOOTSTRAP_FC）及以前取这些运行，
-- 从上线（2024-12）起跨期连续可查。只读旧表和 B1 表，只写 MTC_CA_* 表；不改旧数据，旧框架已知缺陷照原样带过来（22_legacy_verify.sql 列出）。
--
-- 各表来源（一期一次 H 运行，RunId 取 MTC_CA_SEQ_RUN）：
--   S_LINE / R_LINE      ← 0302_INVNTDETAIL1（CostCode 20，一行 = 一条库存变动；单号、日期、交易类型、仓库、科目、订单照抄），金额按物料比例拆四项
--   R_ITEM               ← 期初 = 上期 H 运行期末四项（第一期取 0301 期初按本期比例拆）；入库 = 本期入库行；期末 = 0301 期末按本期比例拆；
--                          出库四项倒挤（期初 + 入库 + 出库 = 期末）；旧框架期末 ≠ 期初 + 收发的差额记 TailAmt（R03“尾差结转”列）
--   S_ITEM               ← U_COILV 该期层级 + OITM
--   S_ORDER / R_ORDER    ← 0321_OWOR_SUM（本期完工成本：1Material / 2ManExp 制造 / 3LabAmount 人工 / 4WWExp 委外）+ OWOR / @MTC_OWOR
--   R_ORDER_MAT          ← 期初 = 上期 H 运行（第一期取 0321_OWOR1 累计领料和上期 0322_OWOR_ZCP1 在产品）；本期领料 = 0321_OWOR1；
--                          完工转出 = 1Material 按 0321_OWOR1_REG（各材料完工结转）的比例分到材料；委外加工费一行 '#SUBFEE'（旧框架当期全部转出）；
--                          期末在产品倒挤（同旧 ZCP：累计领料 − 累计完工材料 − 关单差异）；截至期末已关闭的订单，剩余全部转关单差异
--   R_ALLOC / R_POOL     ← 0321_OWOR_SUM 的 2ManExp / 3LabAmount（旧框架没有费用池明细，一个虚拟池 LEGACY，没有工时）
--   R_JDT / R_JDT_SRC    ← 0801_TOOJDT / 0802_OJDTBASEDETAIL；0802 对不上分录的差额补一行来源 LEGACY（V06 来源 = 分录）
-- 料工费比例：MTC_CA_P_LEGACY_RATIO（09_bootstrap.sql，与期初承接共用），每期按截至该期最近一个有完工的账期算；
--   没有完工记录的物料（采购件等）全部记材料。所以历史期的料工费是按旧完工比例估算的，不是逐级算出来的构成。
-- 不回填：发出商品（R_GOODS_*）、应付暂估（S_AP_MOVE / R_AP_ACCR）、计算前后校验（R_CHECK）、新旧比对，相关报表在历史期提示“无此数据”。
-- 只允许账期 ≤ BOOTSTRAP_FC；以后的账期由新框架计算。回填某一期后，它以后已回填的各期要一起重新回填（期初取上期 H 运行）。
-- 离线写的，还没编译（2026-11-02）。部署在 09、21 之后。
-- =====================================================================
CREATE OR REPLACE PROCEDURE "MTC_CA_P_LEGACY_LOAD1" (IN FcCode NVARCHAR(10), IN UserCode NVARCHAR(50), OUT oCode INT, OUT oMsg NVARCHAR(2000))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE boot NVARCHAR(10); DECLARE prevFc NVARCHAR(10);
    DECLARE rid BIGINT; DECLARE prevRid BIGINT;
    DECLARE n0301 BIGINT; DECLARE nLine BIGINT; DECLARE nItem BIGINT; DECLARE nOrd BIGINT; DECLARE nMat BIGINT; DECLARE nJdt BIGINT;
    DECLARE nTail BIGINT; DECLARE nCln BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        oCode := -1;
        oMsg := :FcCode || ' 回填出错：' || ::SQL_ERROR_MESSAGE;
        IF :rid IS NOT NULL THEN
            UPDATE "MTC_CA_RUN" SET "Status" = 'FAIL', "EndTime" = CURRENT_TIMESTAMP, "Msg" = LEFT(:oMsg, 2000) WHERE "RunId" = :rid;
            COMMIT;
        END IF;
    END;
    oCode := -1;
    SELECT MAX(TO_DATE("F_RefDate")), MAX(TO_DATE("T_RefDate")) INTO d0, d1 FROM "OFPR" WHERE "Code" = :FcCode;
    IF :d1 IS NULL THEN
        oMsg := '账期不存在：' || IFNULL(:FcCode, '');
        RETURN;
    END IF;
    boot := "MTC_CA_F_PARAM"('BOOTSTRAP_FC', :FcCode);
    IF :boot IS NULL OR :FcCode > :boot THEN
        oMsg := :FcCode || ' 在承接账期 BOOTSTRAP_FC（' || IFNULL(:boot, '没有配置') || '）以后，由新框架计算，不回填';
        RETURN;
    END IF;
    SELECT COUNT(*) INTO n0301 FROM "MTC_COST_0301_INVNT" WHERE "FcCode" = :FcCode AND "CostCode" = '20';
    IF :n0301 = 0 THEN
        oMsg := :FcCode || ' 旧框架没有结果（MTC_COST_0301_INVNT 没有这一期），先在旧框架算完这一期';
        RETURN;
    END IF;
    SELECT MAX("Code") INTO prevFc FROM "OFPR" WHERE "Code" < :FcCode;
    SELECT MAX("RunId") INTO prevRid FROM "MTC_CA_RUN"
     WHERE "FcCode" = :prevFc AND "RunType" = 'H' AND "Scenario" = 'LEGACY' AND "Status" = 'OK';

    SELECT "MTC_CA_SEQ_RUN".NEXTVAL INTO rid FROM DUMMY;
    -- 运行头单独提交：出错回滚时运行记录仍在（同 MTC_CA_P_RUN_START）
    BEGIN AUTONOMOUS TRANSACTION
        INSERT INTO "MTC_CA_RUN" ("RunId", "FcCode", "RunType", "Scenario", "Initiator", "UserCode", "StartTime", "Status", "Converged", "Msg")
        VALUES (:rid, :FcCode, 'H', 'LEGACY', 'USER', :UserCode, CURRENT_TIMESTAMP, 'RUNNING', 'Y', '旧框架历史回填');
    END;

    -- 料工费比例（与期初承接同一算法）
    CALL "MTC_CA_P_LEGACY_RATIO"(:FcCode, rat);

    -- ---------------- 单据行：0302（CostCode 20） ----------------
    src = SELECT D."ID", IFNULL(D."ObjType", '') AS "ObjType", IFNULL(D."DocEntry", 0) AS "DocEntry", D."DocNum", D."LineNum",
                 IFNULL(D."DocDate", :d1) AS "DocDate", D."TransCode", D."BaseType", D."BaseEntry", D."BaseLine", D."ItemCode", D."WhsCode",
                 IFNULL(D."Quantity", 0) AS "Qty", IFNULL(D."Amount", 0) AS "Amt", D."Price", D."BusiType", D."OcrCode1",
                 COALESCE(NULLIF(D."AcctCode", ''), NULLIF(D."AcctCOde", '')) AS "Acct", D."IsUpdatePrice"
            FROM "MTC_COST_0302_INVNTDETAIL1" D
           WHERE D."FcCode" = :FcCode AND D."CostCode" = '20' AND D."ItemCode" IS NOT NULL;
    ln = SELECT ROW_NUMBER() OVER (ORDER BY S."DocDate", S."ObjType", S."DocEntry", S."LineNum", S."ID") AS "LineId", S.*,
                CASE WHEN S."ObjType" IN ('59', '60') AND S."BaseType" IN ('202', 'MTC_OWOR') AND S."BaseEntry" IS NOT NULL THEN S."BaseType" END AS "OT",
                IFNULL(R."RMfg", 0) AS "rF", IFNULL(R."RLab", 0) AS "rL", IFNULL(R."RSub", 0) AS "rS"
           FROM :src S
           LEFT JOIN :rat R ON R."ItemCode" = S."ItemCode";

    INSERT INTO "MTC_CA_S_LINE" ("FcCode", "RunType", "Scenario", "RunId", "LineId", "Src", "SrcKey", "ObjType", "DocEntry", "DocNum", "LineNum",
                                 "Canceled", "DocDate", "ItemCode", "WhsCode", "Qty", "TransCode", "Dir", "BusiType", "BusiClass",
                                 "BaseType", "BaseEntry", "BaseLine", "OrderType", "OrderEntry", "OrderLine", "AcctCode", "OcrCode", "SharedExp", "NoCost")
    SELECT :FcCode, 'H', 'LEGACY', :rid, L."LineId", 'LEGACY', IFNULL(TO_NVARCHAR(L."ID"), 'L' || TO_NVARCHAR(L."LineId")),
           LEFT(L."ObjType", 20), L."DocEntry", TO_NVARCHAR(L."DocNum"), L."LineNum", 'N', L."DocDate", LEFT(L."ItemCode", 50), LEFT(L."WhsCode", 8), L."Qty",
           LEFT(L."TransCode", 10), T."U_IOType", LEFT(L."BusiType", 20), C."U_TransType",
           LEFT(L."BaseType", 20), TO_NVARCHAR(L."BaseEntry"), TO_NVARCHAR(L."BaseLine"),
           L."OT", CASE WHEN L."OT" IS NOT NULL THEN L."BaseEntry" END, CASE WHEN L."OT" IS NOT NULL THEN L."BaseLine" END,
           LEFT(L."Acct", 15), LEFT(L."OcrCode1", 20), 'N', 'N'
      FROM :ln L
      LEFT JOIN "@MTC_COST_IOTYPE" T ON T."Code" = L."TransCode"
      LEFT JOIN "@U_CIOTRN" C ON C."Code" = L."BusiType" AND L."ObjType" IN ('59', '60');
    nLine := ::ROWCOUNT;

    -- 金额按物料比例拆四项：制造、人工、委外四舍五入到分，材料 = 金额 − 其余三项（合计不变，同期初承接）
    INSERT INTO "MTC_CA_R_LINE" ("FcCode", "RunType", "Scenario", "RunId", "LineId", "ItemCode", "TransCode", "Qty", "Cat", "InVal",
                                 "OrderType", "OrderEntry", "IsShared", "MatAmt", "MfgAmt", "LabAmt", "SubAmt", "Amount", "Price", "PriceSrc", "RuleId", "Iter")
    SELECT :FcCode, 'H', 'LEGACY', :rid, L."LineId", LEFT(L."ItemCode", 50), LEFT(L."TransCode", 10), L."Qty", 'LEGACY', 'N',
           L."OT", CASE WHEN L."OT" IS NOT NULL THEN L."BaseEntry" END, 'N',
           L."Amt" - ROUND(L."Amt" * L."rF", 2) - ROUND(L."Amt" * L."rL", 2) - ROUND(L."Amt" * L."rS", 2),
           ROUND(L."Amt" * L."rF", 2), ROUND(L."Amt" * L."rL", 2), ROUND(L."Amt" * L."rS", 2), L."Amt",
           L."Price", LEFT('旧 0302' || CASE WHEN IFNULL(L."IsUpdatePrice", '') <> '' THEN ' ' || L."IsUpdatePrice" ELSE '' END, 200), 'LEGACY', 0
      FROM :ln L;

    -- ---------------- 物料：R_ITEM、S_ITEM ----------------
    inv = SELECT I."ItemCode", SUM(IFNULL(I."QC_Qty", 0)) AS "QCQ", SUM(IFNULL(I."QC_Amount", 0)) AS "QCA",
                 SUM(IFNULL(I."QM_Qty", 0)) AS "QMQ", SUM(IFNULL(I."QM_Amount", 0)) AS "QMA", MAX(I."iLevel") AS "Lv"
            FROM "MTC_COST_0301_INVNT" I
           WHERE I."FcCode" = :FcCode AND I."CostCode" = '20'
           GROUP BY I."ItemCode";
    -- 期初：有上期 H 运行取它的期末；没有（回填的第一期）取 0301 期初按本期比例拆
    op = SELECT "ItemCode", CAST("EndQty" AS DECIMAL(19,6)) AS "Q", CAST("EndMat" AS DECIMAL(19,6)) AS "M", CAST("EndMfg" AS DECIMAL(19,6)) AS "F",
                CAST("EndLab" AS DECIMAL(19,6)) AS "L", CAST("EndSub" AS DECIMAL(19,6)) AS "S"
           FROM "MTC_CA_R_ITEM" WHERE "RunId" = :prevRid
         UNION ALL
         SELECT I."ItemCode", CAST(I."QCQ" AS DECIMAL(19,6)),
                CAST(I."QCA" - ROUND(I."QCA" * IFNULL(R."RMfg", 0), 2) - ROUND(I."QCA" * IFNULL(R."RLab", 0), 2) - ROUND(I."QCA" * IFNULL(R."RSub", 0), 2) AS DECIMAL(19,6)),
                CAST(ROUND(I."QCA" * IFNULL(R."RMfg", 0), 2) AS DECIMAL(19,6)), CAST(ROUND(I."QCA" * IFNULL(R."RLab", 0), 2) AS DECIMAL(19,6)),
                CAST(ROUND(I."QCA" * IFNULL(R."RSub", 0), 2) AS DECIMAL(19,6))
           FROM :inv I LEFT JOIN :rat R ON R."ItemCode" = I."ItemCode"
          WHERE :prevRid IS NULL;
    -- 入库 = 数量为正（数量为 0 的发票差额、重估按交易类型方向）的行，同 R03 口径
    lin = SELECT L."ItemCode",
                 SUM(CASE WHEN L."Qty" > 0 OR (L."Qty" = 0 AND IFNULL(S."Dir", 'I') = 'I') THEN L."Qty" ELSE 0 END) AS "IQ",
                 SUM(CASE WHEN L."Qty" > 0 OR (L."Qty" = 0 AND IFNULL(S."Dir", 'I') = 'I') THEN L."MatAmt" ELSE 0 END) AS "IM",
                 SUM(CASE WHEN L."Qty" > 0 OR (L."Qty" = 0 AND IFNULL(S."Dir", 'I') = 'I') THEN L."MfgAmt" ELSE 0 END) AS "IFg",
                 SUM(CASE WHEN L."Qty" > 0 OR (L."Qty" = 0 AND IFNULL(S."Dir", 'I') = 'I') THEN L."LabAmt" ELSE 0 END) AS "IL",
                 SUM(CASE WHEN L."Qty" > 0 OR (L."Qty" = 0 AND IFNULL(S."Dir", 'I') = 'I') THEN L."SubAmt" ELSE 0 END) AS "ISb",
                 SUM(L."Amount") AS "Net"
            FROM "MTC_CA_R_LINE" L JOIN "MTC_CA_S_LINE" S ON S."RunId" = L."RunId" AND S."LineId" = L."LineId"
           WHERE L."RunId" = :rid
           GROUP BY L."ItemCode";
    ikey = SELECT "ItemCode" FROM :inv WHERE "QCQ" <> 0 OR "QCA" <> 0 OR "QMQ" <> 0 OR "QMA" <> 0
           UNION SELECT "ItemCode" FROM :op WHERE "Q" <> 0 OR "M" <> 0 OR "F" <> 0 OR "L" <> 0 OR "S" <> 0
           UNION SELECT "ItemCode" FROM :lin;
    it = SELECT K."ItemCode",
                COALESCE(V."iLevel", I."Lv", -1) AS "Lv",
                IFNULL(O."Q", 0) AS "OQ", IFNULL(O."M", 0) AS "OM", IFNULL(O."F", 0) AS "OFg", IFNULL(O."L", 0) AS "OL", IFNULL(O."S", 0) AS "OS",
                IFNULL(N."IQ", 0) AS "IQ", IFNULL(N."IM", 0) AS "IM", IFNULL(N."IFg", 0) AS "IFg", IFNULL(N."IL", 0) AS "IL", IFNULL(N."ISb", 0) AS "ISb",
                IFNULL(N."Net", 0) AS "Net",
                IFNULL(I."QMQ", 0) AS "EQ",
                IFNULL(I."QMA", 0) - ROUND(IFNULL(I."QMA", 0) * IFNULL(R."RMfg", 0), 2) - ROUND(IFNULL(I."QMA", 0) * IFNULL(R."RLab", 0), 2)
                                   - ROUND(IFNULL(I."QMA", 0) * IFNULL(R."RSub", 0), 2) AS "EM",
                ROUND(IFNULL(I."QMA", 0) * IFNULL(R."RMfg", 0), 2) AS "EF", ROUND(IFNULL(I."QMA", 0) * IFNULL(R."RLab", 0), 2) AS "EL",
                ROUND(IFNULL(I."QMA", 0) * IFNULL(R."RSub", 0), 2) AS "ES",
                IFNULL(I."QMA", 0) AS "EA"
           FROM :ikey K
           LEFT JOIN :inv I ON I."ItemCode" = K."ItemCode"
           LEFT JOIN :op O ON O."ItemCode" = K."ItemCode"
           LEFT JOIN :lin N ON N."ItemCode" = K."ItemCode"
           LEFT JOIN :rat R ON R."ItemCode" = K."ItemCode"
           LEFT JOIN (SELECT "ItemCode", MAX("iLevel") AS "iLevel" FROM "U_COILV" WHERE "FcCode" = :FcCode GROUP BY "ItemCode") V ON V."ItemCode" = K."ItemCode";
    it2 = SELECT T.*, T."EQ" - T."OQ" - T."IQ" AS "XQ",
                 T."EM" - T."OM" - T."IM" AS "XM", T."EF" - T."OFg" - T."IFg" AS "XF", T."EL" - T."OL" - T."IL" AS "XL", T."ES" - T."OS" - T."ISb" AS "XS",
                 T."EA" - (T."OM" + T."OFg" + T."OL" + T."OS") - T."Net" AS "Tail"
            FROM :it T;
    INSERT INTO "MTC_CA_R_ITEM" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "iLevel",
        "OpenQty", "OpenMat", "OpenMfg", "OpenLab", "OpenSub", "PMat", "PMfg", "PLab", "PSub", "PriceSrc",
        "InQty", "InMat", "InMfg", "InLab", "InSub", "OutQty", "OutMat", "OutMfg", "OutLab", "OutSub",
        "EndQty", "EndMat", "EndMfg", "EndLab", "EndSub", "EndAmount", "Flags", "TailAmt",
        "RtOpenMat", "RtOpenLab", "RtOpenMfg", "RtOpenSub", "RtInMat", "RtInLab", "RtInMfg", "RtInSub",
        "RtOutMat", "RtOutLab", "RtOutMfg", "RtOutSub", "RtEndMat", "RtEndLab", "RtEndMfg", "RtEndSub")
    SELECT :FcCode, 'H', 'LEGACY', :rid, LEFT(T."ItemCode", 50), T."Lv",
           T."OQ", T."OM", T."OFg", T."OL", T."OS",
           CASE WHEN T."EQ" <> 0 THEN T."EM" / T."EQ" ELSE 0 END, CASE WHEN T."EQ" <> 0 THEN T."EF" / T."EQ" ELSE 0 END,
           CASE WHEN T."EQ" <> 0 THEN T."EL" / T."EQ" ELSE 0 END, CASE WHEN T."EQ" <> 0 THEN T."ES" / T."EQ" ELSE 0 END, 'LEGACY',
           T."IQ", T."IM", T."IFg", T."IL", T."ISb", T."XQ", T."XM", T."XF", T."XL", T."XS",
           T."EQ", T."EM", T."EF", T."EL", T."ES", T."EA",
           CASE WHEN ABS(T."Tail") >= 0.005 THEN '旧框架期末 ≠ 期初 + 收发，差额记尾差' END, T."Tail",
           CASE WHEN T."OM" + T."OFg" + T."OL" + T."OS" <> 0 THEN ROUND(T."OM" / (T."OM" + T."OFg" + T."OL" + T."OS") * 100, 4) END,
           CASE WHEN T."OM" + T."OFg" + T."OL" + T."OS" <> 0 THEN ROUND(T."OL" / (T."OM" + T."OFg" + T."OL" + T."OS") * 100, 4) END,
           CASE WHEN T."OM" + T."OFg" + T."OL" + T."OS" <> 0 THEN ROUND(T."OFg" / (T."OM" + T."OFg" + T."OL" + T."OS") * 100, 4) END,
           CASE WHEN T."OM" + T."OFg" + T."OL" + T."OS" <> 0 THEN ROUND(T."OS" / (T."OM" + T."OFg" + T."OL" + T."OS") * 100, 4) END,
           CASE WHEN T."IM" + T."IFg" + T."IL" + T."ISb" <> 0 THEN ROUND(T."IM" / (T."IM" + T."IFg" + T."IL" + T."ISb") * 100, 4) END,
           CASE WHEN T."IM" + T."IFg" + T."IL" + T."ISb" <> 0 THEN ROUND(T."IL" / (T."IM" + T."IFg" + T."IL" + T."ISb") * 100, 4) END,
           CASE WHEN T."IM" + T."IFg" + T."IL" + T."ISb" <> 0 THEN ROUND(T."IFg" / (T."IM" + T."IFg" + T."IL" + T."ISb") * 100, 4) END,
           CASE WHEN T."IM" + T."IFg" + T."IL" + T."ISb" <> 0 THEN ROUND(T."ISb" / (T."IM" + T."IFg" + T."IL" + T."ISb") * 100, 4) END,
           CASE WHEN T."XM" + T."XF" + T."XL" + T."XS" <> 0 THEN ROUND(T."XM" / (T."XM" + T."XF" + T."XL" + T."XS") * 100, 4) END,
           CASE WHEN T."XM" + T."XF" + T."XL" + T."XS" <> 0 THEN ROUND(T."XL" / (T."XM" + T."XF" + T."XL" + T."XS") * 100, 4) END,
           CASE WHEN T."XM" + T."XF" + T."XL" + T."XS" <> 0 THEN ROUND(T."XF" / (T."XM" + T."XF" + T."XL" + T."XS") * 100, 4) END,
           CASE WHEN T."XM" + T."XF" + T."XL" + T."XS" <> 0 THEN ROUND(T."XS" / (T."XM" + T."XF" + T."XL" + T."XS") * 100, 4) END,
           CASE WHEN T."EA" <> 0 THEN ROUND(T."EM" / T."EA" * 100, 4) END, CASE WHEN T."EA" <> 0 THEN ROUND(T."EL" / T."EA" * 100, 4) END,
           CASE WHEN T."EA" <> 0 THEN ROUND(T."EF" / T."EA" * 100, 4) END, CASE WHEN T."EA" <> 0 THEN ROUND(T."ES" / T."EA" * 100, 4) END
      FROM :it2 T;
    nItem := ::ROWCOUNT;
    SELECT COUNT(*) INTO nTail FROM "MTC_CA_R_ITEM" WHERE "RunId" = :rid AND ABS("TailAmt") >= 0.005;

    INSERT INTO "MTC_CA_S_ITEM" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "ItemName", "ItmsGrpCod", "GrpType",
                                 "CalType", "InvntItem", "IsBomFather", "iLevel", "LevelSrc", "LevelNote")
    SELECT :FcCode, 'H', 'LEGACY', :rid, R."ItemCode", M."ItemName", TO_NVARCHAR(M."ItmsGrpCod"), G."U_ItemGrpType",
           M."U_ItemProp", M."InvntItem",
           CASE WHEN EXISTS (SELECT 1 FROM "OITT" B WHERE B."Code" = R."ItemCode") THEN 'Y' ELSE 'N' END,
           R."iLevel", 'LEGACY', '旧框架 U_COILV 该期层级'
      FROM "MTC_CA_R_ITEM" R
      LEFT JOIN "OITM" M ON M."ItemCode" = R."ItemCode"
      LEFT JOIN "OITB" G ON G."ItmsGrpCod" = M."ItmsGrpCod"
     WHERE R."RunId" = :rid;

    -- ---------------- 订单 ----------------
    -- 本期完工成本（旧 0402 写的 0321_OWOR_SUM；完工材料 = Amount − 制造 − 人工 − 委外，使四项合计 = 旧 Amount）
    osum = SELECT IFNULL("DocType", '202') AS "OT", TO_INTEGER("WorEntry") AS "OE", MAX("WorType") AS "WT", MAX("ItemCode") AS "Item",
                  MAX("iLevel") AS "Lv", SUM(IFNULL("IgnQty", 0)) AS "Rq", SUM(IFNULL("Amount", 0)) AS "A",
                  SUM(IFNULL("2ManExp", 0)) AS "F", SUM(IFNULL("3LabAmount", 0)) AS "L", SUM(IFNULL("4WWExp", 0)) AS "S"
             FROM "MTC_COST_0321_OWOR_SUM"
            WHERE "FcCode" = :FcCode AND TO_NVARCHAR("WorEntry") LIKE_REGEXPR '^[0-9]+$'
            GROUP BY IFNULL("DocType", '202'), TO_INTEGER("WorEntry")
           HAVING SUM(ABS(IFNULL("IgnQty", 0))) + SUM(ABS(IFNULL("Amount", 0))) + SUM(ABS(IFNULL("2ManExp", 0)))
                  + SUM(ABS(IFNULL("3LabAmount", 0))) + SUM(ABS(IFNULL("4WWExp", 0))) <> 0;
    -- 本期领料（0321_OWOR1 出库为负，取反为正；生产退料为负）
    iss = SELECT IFNULL("DocType", '202') AS "OT", TO_INTEGER("WorEntry") AS "OE", "ItemCode",
                 -SUM(IFNULL("IgeQty", 0)) AS "Q", -SUM(IFNULL("Amount", 0)) AS "A"
            FROM "MTC_COST_0321_OWOR1"
           WHERE "FcCode" = :FcCode AND TO_NVARCHAR("WorEntry") LIKE_REGEXPR '^[0-9]+$' AND "ItemCode" IS NOT NULL
           GROUP BY IFNULL("DocType", '202'), TO_INTEGER("WorEntry"), "ItemCode"
          HAVING SUM(IFNULL("IgeQty", 0)) <> 0 OR SUM(IFNULL("Amount", 0)) <> 0;
    -- 各材料本期完工结转（旧 0402 写的 0321_OWOR1_REG），只用来分摊完工材料
    reg = SELECT IFNULL("DocType", '202') AS "OT", TO_INTEGER("WorEntry") AS "OE", "ItemCode", SUM(IFNULL("Amount", 0)) AS "W"
            FROM "MTC_COST_0321_OWOR1_REG"
           WHERE "FcCode" = :FcCode AND TO_NVARCHAR("WorEntry") LIKE_REGEXPR '^[0-9]+$' AND "ItemCode" IS NOT NULL
           GROUP BY IFNULL("DocType", '202'), TO_INTEGER("WorEntry"), "ItemCode"
          HAVING SUM(IFNULL("Amount", 0)) <> 0;
    -- 期初（订单 × 材料）：有上期 H 运行取它（同 P20_OPEN：累计领料 = 期初 + 领料，累计结转 = 期初 + 结转 + 关单差异，上期按关单处理的订单不带入）；
    -- 没有（回填的第一期）取 0321_OWOR1 截至上期累计领料、上期 0322_OWOR_ZCP1 在产品，累计结转 = 累计领料 − 在产品，按材料比例拆四项
    cum = SELECT IFNULL("DocType", '202') AS "OT", TO_INTEGER("WorEntry") AS "OE", "ItemCode",
                 -SUM(IFNULL("IgeQty", 0)) AS "Q", -SUM(IFNULL("Amount", 0)) AS "A"
            FROM "MTC_COST_0321_OWOR1"
           WHERE "FcCode" < :FcCode AND TO_NVARCHAR("WorEntry") LIKE_REGEXPR '^[0-9]+$' AND "ItemCode" IS NOT NULL AND :prevRid IS NULL
           GROUP BY IFNULL("DocType", '202'), TO_INTEGER("WorEntry"), "ItemCode";
    zp = SELECT IFNULL("DocType", '202') AS "OT", "WorEntry" AS "OE", "ItemCode", SUM(IFNULL("Amount", 0)) AS "A"
           FROM "MTC_COST_0322_OWOR_ZCP1"
          WHERE "FcCode" = :prevFc AND "ItemCode" IS NOT NULL AND :prevRid IS NULL
          GROUP BY IFNULL("DocType", '202'), "WorEntry", "ItemCode";
    old0 = SELECT IFNULL(C."OT", Z."OT") AS "OT", IFNULL(C."OE", Z."OE") AS "OE", IFNULL(C."ItemCode", Z."ItemCode") AS "ItemCode",
                  IFNULL(C."Q", 0) AS "Q", IFNULL(C."A", 0) AS "IA", IFNULL(C."A", 0) - IFNULL(Z."A", 0) AS "CA"
             FROM :cum C FULL JOIN :zp Z ON Z."OT" = C."OT" AND Z."OE" = C."OE" AND Z."ItemCode" = C."ItemCode";
    opn = SELECT M."OrderType" AS "OT", M."OrderEntry" AS "OE", M."ItemCode",
                 CAST(M."OpenIssQty" + M."IssQty" AS DECIMAL(19,6)) AS "Q",
                 CAST(M."OpenIssMat" + M."IssMat" AS DECIMAL(19,6)) AS "IM", CAST(M."OpenIssMfg" + M."IssMfg" AS DECIMAL(19,6)) AS "IFg",
                 CAST(M."OpenIssLab" + M."IssLab" AS DECIMAL(19,6)) AS "IL", CAST(M."OpenIssSub" + M."IssSub" AS DECIMAL(19,6)) AS "ISb",
                 CAST(M."OpenCarMat" + M."CarMat" + M."ClsMat" AS DECIMAL(19,6)) AS "CM", CAST(M."OpenCarMfg" + M."CarMfg" + M."ClsMfg" AS DECIMAL(19,6)) AS "CF",
                 CAST(M."OpenCarLab" + M."CarLab" + M."ClsLab" AS DECIMAL(19,6)) AS "CL", CAST(M."OpenCarSub" + M."CarSub" + M."ClsSub" AS DECIMAL(19,6)) AS "CS"
            FROM "MTC_CA_R_ORDER_MAT" M
            JOIN "MTC_CA_R_ORDER" O ON O."RunId" = M."RunId" AND O."OrderType" = M."OrderType" AND O."OrderEntry" = M."OrderEntry"
           WHERE M."RunId" = :prevRid AND O."ClosedInFc" = 'N'
          UNION ALL
          SELECT X."OT", X."OE", X."ItemCode", CAST(X."Q" AS DECIMAL(19,6)),
                 CAST(X."IA" - ROUND(X."IA" * IFNULL(R."RMfg", 0), 2) - ROUND(X."IA" * IFNULL(R."RLab", 0), 2) - ROUND(X."IA" * IFNULL(R."RSub", 0), 2) AS DECIMAL(19,6)),
                 CAST(ROUND(X."IA" * IFNULL(R."RMfg", 0), 2) AS DECIMAL(19,6)), CAST(ROUND(X."IA" * IFNULL(R."RLab", 0), 2) AS DECIMAL(19,6)),
                 CAST(ROUND(X."IA" * IFNULL(R."RSub", 0), 2) AS DECIMAL(19,6)),
                 CAST(X."CA" - ROUND(X."CA" * IFNULL(R."RMfg", 0), 2) - ROUND(X."CA" * IFNULL(R."RLab", 0), 2) - ROUND(X."CA" * IFNULL(R."RSub", 0), 2) AS DECIMAL(19,6)),
                 CAST(ROUND(X."CA" * IFNULL(R."RMfg", 0), 2) AS DECIMAL(19,6)), CAST(ROUND(X."CA" * IFNULL(R."RLab", 0), 2) AS DECIMAL(19,6)),
                 CAST(ROUND(X."CA" * IFNULL(R."RSub", 0), 2) AS DECIMAL(19,6))
            FROM :old0 X LEFT JOIN :rat R ON R."ItemCode" = X."ItemCode"
           WHERE :prevRid IS NULL
             AND (ABS(X."IA" - X."CA") >= 0.005
                  OR EXISTS (SELECT 1 FROM :osum S WHERE S."OT" = X."OT" AND S."OE" = X."OE")
                  OR EXISTS (SELECT 1 FROM :iss S WHERE S."OT" = X."OT" AND S."OE" = X."OE"));

    -- 订单范围：本期有完工成本、领料、期初在产品的订单
    okey = SELECT "OT", "OE" FROM :osum UNION SELECT "OT", "OE" FROM :iss UNION SELECT "OT", "OE" FROM :opn UNION SELECT "OT", "OE" FROM :reg;
    ord = SELECT '202' AS "OT", W."DocEntry" AS "OE", TO_NVARCHAR(W."DocNum") AS "Num", TO_NVARCHAR(W."U_OrdType") AS "WT", W."ItemCode",
                 W."PlannedQty", TO_DATE(W."PostDate") AS "PostDate", TO_NVARCHAR(W."Status") AS "St", TO_DATE(W."CloseDate") AS "CloseDate", W."CardCode"
            FROM "OWOR" W
          UNION ALL
          SELECT 'MTC_OWOR', M."DocEntry", TO_NVARCHAR(M."DocNum"), TO_NVARCHAR(M."U_OrdType"), M."U_ItemCode", M."U_PlannedQty",
                 TO_DATE(M."U_PostDate"), TO_NVARCHAR(M."U_Status"), TO_DATE(M."U_CloseDate"), M."U_CardCode"
            FROM "@MTC_OWOR" M;
    -- 截至上期累计入库：0321_OWOR 以前各期合计（上期没有动静的订单不在上期 H 运行里，所以不从它取）
    prq = SELECT IFNULL("DocType", '202') AS "OT", TO_INTEGER("WorEntry") AS "OE", SUM(IFNULL("IgnQty", 0)) AS "Q"
            FROM "MTC_COST_0321_OWOR"
           WHERE "FcCode" < :FcCode AND TO_NVARCHAR("WorEntry") LIKE_REGEXPR '^[0-9]+$'
           GROUP BY IFNULL("DocType", '202'), TO_INTEGER("WorEntry");
    INSERT INTO "MTC_CA_S_ORDER" ("FcCode", "RunType", "Scenario", "RunId", "OrderType", "OrderEntry", "OrderNum", "WorType",
        "ItemCode", "PlannedQty", "PostDate", "B1Status", "CloseDate", "StatusAtEnd", "ClosedInFc", "InScope", "CardCode", "RecvQty", "PrevRecvQty")
    SELECT :FcCode, 'H', 'LEGACY', :rid, K."OT", K."OE", O."Num", COALESCE(O."WT", S."WT"), COALESCE(O."ItemCode", S."Item"), O."PlannedQty",
           O."PostDate", O."St", O."CloseDate",
           CASE WHEN O."St" = 'L' AND (O."CloseDate" IS NULL OR O."CloseDate" <= :d1) THEN 'CLOSED' ELSE 'OPEN' END,
           CASE WHEN O."St" = 'L' AND O."CloseDate" BETWEEN :d0 AND :d1 THEN 'Y' ELSE 'N' END,
           'Y', O."CardCode", IFNULL(S."Rq", 0), IFNULL(P."Q", 0)
      FROM :okey K
      LEFT JOIN :ord O ON O."OT" = K."OT" AND O."OE" = K."OE"
      LEFT JOIN :osum S ON S."OT" = K."OT" AND S."OE" = K."OE"
      LEFT JOIN :prq P ON P."OT" = K."OT" AND P."OE" = K."OE";
    nOrd := ::ROWCOUNT;

    INSERT INTO "MTC_CA_S_ORDER_LINE" ("FcCode", "RunType", "Scenario", "RunId", "OrderType", "OrderEntry", "OrderLine",
                                       "ItemCode", "BaseQty", "PlannedQty")
    SELECT :FcCode, 'H', 'LEGACY', :rid, '202', L."DocEntry", L."LineNum", L."ItemCode", L."BaseQty", L."PlannedQty"
      FROM "WOR1" L
      JOIN "MTC_CA_S_ORDER" O ON O."RunId" = :rid AND O."OrderType" = '202' AND O."OrderEntry" = L."DocEntry"
     WHERE L."ItemType" = 4
    UNION ALL
    SELECT :FcCode, 'H', 'LEGACY', :rid, 'MTC_OWOR', L."DocEntry", L."LineId", L."U_ItemCode", L."U_BaseQty", L."U_PlannedQty"
      FROM "@MTC_WOR1" L
      JOIN "MTC_CA_S_ORDER" O ON O."RunId" = :rid AND O."OrderType" = 'MTC_OWOR' AND O."OrderEntry" = L."DocEntry";

    -- 订单 × 材料：期初 + 本期领料（按材料比例拆四项）+ 委外加工费行 '#SUBFEE'；完工材料没有任何材料行可分的订单补一行 '#LEGACY'
    mk = SELECT "OT", "OE", "ItemCode" FROM :opn
         UNION SELECT "OT", "OE", "ItemCode" FROM :iss
         UNION SELECT "OT", "OE", "ItemCode" FROM :reg
         UNION SELECT "OT", "OE", '#SUBFEE' FROM :osum WHERE "S" <> 0
         UNION SELECT S."OT", S."OE", '#LEGACY' FROM :osum S
                WHERE S."A" - S."F" - S."L" - S."S" <> 0
                  AND NOT EXISTS (SELECT 1 FROM :opn X WHERE X."OT" = S."OT" AND X."OE" = S."OE" AND X."ItemCode" <> '#SUBFEE')
                  AND NOT EXISTS (SELECT 1 FROM :iss X WHERE X."OT" = S."OT" AND X."OE" = S."OE")
                  AND NOT EXISTS (SELECT 1 FROM :reg X WHERE X."OT" = S."OT" AND X."OE" = S."OE");
    m1 = SELECT K."OT", K."OE", K."ItemCode",
                IFNULL(P."Q", 0) AS "PQ", IFNULL(P."IM", 0) AS "PIM", IFNULL(P."IFg", 0) AS "PIF", IFNULL(P."IL", 0) AS "PIL", IFNULL(P."ISb", 0) AS "PIS",
                IFNULL(P."CM", 0) AS "PCM", IFNULL(P."CF", 0) AS "PCF", IFNULL(P."CL", 0) AS "PCL", IFNULL(P."CS", 0) AS "PCS",
                IFNULL(I."Q", 0) AS "NQ",
                CASE WHEN K."ItemCode" = '#SUBFEE' THEN 0
                     ELSE IFNULL(I."A", 0) - ROUND(IFNULL(I."A", 0) * IFNULL(R."RMfg", 0), 2) - ROUND(IFNULL(I."A", 0) * IFNULL(R."RLab", 0), 2)
                          - ROUND(IFNULL(I."A", 0) * IFNULL(R."RSub", 0), 2) END AS "NM",
                CASE WHEN K."ItemCode" = '#SUBFEE' THEN 0 ELSE ROUND(IFNULL(I."A", 0) * IFNULL(R."RMfg", 0), 2) END AS "NF",
                CASE WHEN K."ItemCode" = '#SUBFEE' THEN 0 ELSE ROUND(IFNULL(I."A", 0) * IFNULL(R."RLab", 0), 2) END AS "NL",
                CASE WHEN K."ItemCode" = '#SUBFEE' THEN IFNULL(S."S", 0) ELSE ROUND(IFNULL(I."A", 0) * IFNULL(R."RSub", 0), 2) END AS "NS",
                IFNULL(G."W", 0) AS "W",
                IFNULL(R."RMat", 1) AS "rM", IFNULL(R."RMfg", 0) AS "rF", IFNULL(R."RLab", 0) AS "rL", IFNULL(R."RSub", 0) AS "rS"
           FROM :mk K
           LEFT JOIN :opn P ON P."OT" = K."OT" AND P."OE" = K."OE" AND P."ItemCode" = K."ItemCode"
           LEFT JOIN :iss I ON I."OT" = K."OT" AND I."OE" = K."OE" AND I."ItemCode" = K."ItemCode"
           LEFT JOIN :reg G ON G."OT" = K."OT" AND G."OE" = K."OE" AND G."ItemCode" = K."ItemCode"
           LEFT JOIN :osum S ON S."OT" = K."OT" AND S."OE" = K."OE"
           LEFT JOIN :rat R ON R."ItemCode" = K."ItemCode";
    -- 可结转 = 期初在产品 + 本期领料（四项）
    m2 = SELECT M.*, M."PIM" - M."PCM" + M."NM" AS "AM", M."PIF" - M."PCF" + M."NF" AS "AF",
                M."PIL" - M."PCL" + M."NL" AS "AL", M."PIS" - M."PCS" + M."NS" AS "ASb"
           FROM :m1 M;
    -- 完工材料（= 旧 Amount − 制造 − 人工 − 委外）分到材料行：有 0321_OWOR1_REG 按它的比例，没有按可结转金额，都没有平均分
    ow = SELECT "OT", "OE", SUM("W") AS "WT", SUM("AM" + "AF" + "AL" + "ASb") AS "AT", COUNT(*) AS "Cnt"
           FROM :m2 WHERE "ItemCode" <> '#SUBFEE' GROUP BY "OT", "OE";
    m3 = SELECT M.*,
                CASE WHEN M."ItemCode" = '#SUBFEE' THEN M."AM" + M."AF" + M."AL" + M."ASb"   -- 委外加工费当期全部转出（旧框架口径）
                     ELSE (IFNULL(S."A", 0) - IFNULL(S."F", 0) - IFNULL(S."L", 0) - IFNULL(S."S", 0))
                          * CASE WHEN W."WT" <> 0 THEN M."W" / W."WT"
                                 WHEN W."AT" <> 0 THEN (M."AM" + M."AF" + M."AL" + M."ASb") / W."AT"
                                 ELSE 1.0 / W."Cnt" END END AS "CT"
           FROM :m2 M
           LEFT JOIN :osum S ON S."OT" = M."OT" AND S."OE" = M."OE"
           LEFT JOIN :ow W ON W."OT" = M."OT" AND W."OE" = M."OE";
    -- 结转四项按本行可结转的构成拆（可结转为 0 时按材料比例），截至期末已关闭的订单剩余全部转关单差异，其余留作期末在产品
    m4 = SELECT M.*,
                CASE WHEN M."AM" + M."AF" + M."AL" + M."ASb" <> 0 THEN M."CT" * M."AM" / (M."AM" + M."AF" + M."AL" + M."ASb")
                     WHEN M."ItemCode" = '#SUBFEE' THEN 0 ELSE M."CT" * M."rM" END AS "CM",
                CASE WHEN M."AM" + M."AF" + M."AL" + M."ASb" <> 0 THEN M."CT" * M."AF" / (M."AM" + M."AF" + M."AL" + M."ASb")
                     WHEN M."ItemCode" = '#SUBFEE' THEN 0 ELSE M."CT" * M."rF" END AS "CF",
                CASE WHEN M."AM" + M."AF" + M."AL" + M."ASb" <> 0 THEN M."CT" * M."AL" / (M."AM" + M."AF" + M."AL" + M."ASb")
                     WHEN M."ItemCode" = '#SUBFEE' THEN 0 ELSE M."CT" * M."rL" END AS "CL",
                CASE WHEN M."AM" + M."AF" + M."AL" + M."ASb" <> 0 THEN M."CT" * M."ASb" / (M."AM" + M."AF" + M."AL" + M."ASb")
                     WHEN M."ItemCode" = '#SUBFEE' THEN M."CT" ELSE M."CT" * M."rS" END AS "CS",
                CASE WHEN O."StatusAtEnd" = 'CLOSED' THEN 'Y' ELSE 'N' END AS "Cls"
           FROM :m3 M
           JOIN "MTC_CA_S_ORDER" O ON O."RunId" = :rid AND O."OrderType" = M."OT" AND O."OrderEntry" = M."OE";
    INSERT INTO "MTC_CA_R_ORDER_MAT" ("FcCode", "RunType", "Scenario", "RunId", "OrderType", "OrderEntry", "ItemCode",
        "OpenIssQty", "OpenIssMat", "OpenIssMfg", "OpenIssLab", "OpenIssSub", "OpenCarMat", "OpenCarMfg", "OpenCarLab", "OpenCarSub",
        "IssQty", "IssMat", "IssMfg", "IssLab", "IssSub", "Ratio", "CarMat", "CarMfg", "CarLab", "CarSub",
        "WipMat", "WipMfg", "WipLab", "WipSub", "ClsMat", "ClsMfg", "ClsLab", "ClsSub")
    SELECT :FcCode, 'H', 'LEGACY', :rid, M."OT", M."OE", LEFT(M."ItemCode", 50),
           M."PQ", M."PIM", M."PIF", M."PIL", M."PIS", M."PCM", M."PCF", M."PCL", M."PCS",
           M."NQ", M."NM", M."NF", M."NL", M."NS",
           CASE WHEN M."AM" + M."AF" + M."AL" + M."ASb" <> 0 THEN M."CT" / (M."AM" + M."AF" + M."AL" + M."ASb") END,
           M."CM", M."CF", M."CL", M."CS",
           CASE WHEN M."Cls" = 'Y' THEN 0 ELSE M."AM" - M."CM" END, CASE WHEN M."Cls" = 'Y' THEN 0 ELSE M."AF" - M."CF" END,
           CASE WHEN M."Cls" = 'Y' THEN 0 ELSE M."AL" - M."CL" END, CASE WHEN M."Cls" = 'Y' THEN 0 ELSE M."ASb" - M."CS" END,
           CASE WHEN M."Cls" = 'Y' THEN M."AM" - M."CM" ELSE 0 END, CASE WHEN M."Cls" = 'Y' THEN M."AF" - M."CF" ELSE 0 END,
           CASE WHEN M."Cls" = 'Y' THEN M."AL" - M."CL" ELSE 0 END, CASE WHEN M."Cls" = 'Y' THEN M."ASb" - M."CS" ELSE 0 END
      FROM :m4 M;
    nMat := ::ROWCOUNT;

    -- 订单：完工成本四项 = 各材料结转 + 本级分摊（制造 2ManExp、人工 3LabAmount）；在产品、关单差异 = 订单 × 材料合计
    INSERT INTO "MTC_CA_R_ORDER" ("FcCode", "RunType", "Scenario", "RunId", "OrderType", "OrderEntry", "WorType", "ItemCode", "iLevel",
        "PlannedQty", "PrevRecvQty", "RecvQty", "Ratio", "ClosedInFc", "AllocMfg", "AllocLab",
        "CostMat", "CostMfg", "CostLab", "CostSub", "CostAmt", "UnitCost", "WipAmt", "CloseDifAmt")
    SELECT :FcCode, 'H', 'LEGACY', :rid, O."OrderType", O."OrderEntry", O."WorType", O."ItemCode",
           COALESCE(S."Lv", V."iLevel", -1), O."PlannedQty", O."PrevRecvQty", O."RecvQty",
           CASE WHEN O."RecvQty" <> 0 AND IFNULL(O."PlannedQty", 0) > 0 THEN LEAST((O."PrevRecvQty" + O."RecvQty") / O."PlannedQty", 1) END,
           CASE WHEN O."StatusAtEnd" = 'CLOSED' THEN 'Y' ELSE 'N' END,
           IFNULL(S."F", 0), IFNULL(S."L", 0),
           IFNULL(M."CM", 0), IFNULL(M."CF", 0) + IFNULL(S."F", 0), IFNULL(M."CL", 0) + IFNULL(S."L", 0), IFNULL(M."CS", 0),
           IFNULL(M."CM", 0) + IFNULL(M."CF", 0) + IFNULL(S."F", 0) + IFNULL(M."CL", 0) + IFNULL(S."L", 0) + IFNULL(M."CS", 0),
           CASE WHEN O."RecvQty" <> 0 THEN (IFNULL(M."CM", 0) + IFNULL(M."CF", 0) + IFNULL(S."F", 0) + IFNULL(M."CL", 0) + IFNULL(S."L", 0) + IFNULL(M."CS", 0)) / O."RecvQty" END,
           IFNULL(M."Wip", 0), IFNULL(M."Cls", 0)
      FROM "MTC_CA_S_ORDER" O
      LEFT JOIN :osum S ON S."OT" = O."OrderType" AND S."OE" = O."OrderEntry"
      LEFT JOIN (SELECT "OrderType", "OrderEntry", SUM("CarMat") AS "CM", SUM("CarMfg") AS "CF", SUM("CarLab") AS "CL", SUM("CarSub") AS "CS",
                        SUM("WipMat" + "WipMfg" + "WipLab" + "WipSub") AS "Wip", SUM("ClsMat" + "ClsMfg" + "ClsLab" + "ClsSub") AS "Cls"
                   FROM "MTC_CA_R_ORDER_MAT" WHERE "RunId" = :rid GROUP BY "OrderType", "OrderEntry") M
             ON M."OrderType" = O."OrderType" AND M."OrderEntry" = O."OrderEntry"
      LEFT JOIN (SELECT "ItemCode", MAX("iLevel") AS "iLevel" FROM "U_COILV" WHERE "FcCode" = :FcCode GROUP BY "ItemCode") V ON V."ItemCode" = O."ItemCode"
     WHERE O."RunId" = :rid;

    -- 费用分配：旧框架没有费用池明细，一个虚拟池 LEGACY，按订单列分摊额（没有工时）
    INSERT INTO "MTC_CA_R_ALLOC" ("FcCode", "RunType", "Scenario", "RunId", "PoolCode", "Elem", "OrderType", "OrderEntry",
                                  "Hours", "RecvQty", "Weight", "Ratio", "Amount")
    SELECT :FcCode, 'H', 'LEGACY', :rid, 'LEGACY', X."Elem", X."OT", X."OE", NULL, X."Rq", NULL,
           X."Amt" / NULLIF(SUM(X."Amt") OVER (PARTITION BY X."Elem"), 0), X."Amt"
      FROM (SELECT "OT", "OE", "Rq", 'MFG' AS "Elem", "F" AS "Amt" FROM :osum WHERE "F" <> 0
            UNION ALL
            SELECT "OT", "OE", "Rq", 'LAB', "L" FROM :osum WHERE "L" <> 0) X;
    INSERT INTO "MTC_CA_R_POOL" ("FcCode", "RunType", "Scenario", "RunId", "PoolCode", "Elem", "Src", "Amount")
    SELECT :FcCode, 'H', 'LEGACY', :rid, 'LEGACY', "Elem", 'LEGACY', SUM("Amount")
      FROM "MTC_CA_R_ALLOC" WHERE "RunId" = :rid GROUP BY "Elem";

    -- ---------------- 凭证底稿：0801 / 0802 ----------------
    INSERT INTO "MTC_CA_R_JDT" ("FcCode", "RunType", "Scenario", "RunId", "TransCode", "LineNo", "TransName", "RefDate",
                                "AcctCode", "Debit", "Credit", "OcrCode", "Project")
    SELECT :FcCode, 'H', 'LEGACY', :rid, LEFT(J."TransCode", 10),
           ROW_NUMBER() OVER (PARTITION BY J."TransCode" ORDER BY J."Line_ID", J."AcctCode"),
           LEFT(J."TransName", 100), IFNULL(J."RefDate", :d1), LEFT(J."AcctCode", 15),
           ROUND(IFNULL(J."Debit", 0), 2), ROUND(IFNULL(J."Credit", 0), 2), LEFT(J."ProfitCode", 20), LEFT(J."Project", 20)
      FROM "MTC_COST_0801_TOOJDT" J
     WHERE J."FcCode" = :FcCode AND J."TransCode" IS NOT NULL;
    nJdt := ::ROWCOUNT;
    js = SELECT LEFT(B."TransCode", 10) AS "TC", LEFT(B."U_AcctCode", 15) AS "Acct", LEFT(B."U_OcrCode1", 20) AS "Ocr", LEFT(B."U_Project", 20) AS "Prj",
                ROUND(IFNULL(B."U_Debit", 0) - IFNULL(B."U_Credit", 0), 2) AS "Amt",
                CASE WHEN B."U_ObjType" IS NOT NULL AND B."U_DocEntry" IS NOT NULL AND B."U_LineNum" IS NOT NULL THEN 'DOC' ELSE 'LEGACY' END AS "ST",
                CASE WHEN B."U_ObjType" IS NOT NULL AND B."U_DocEntry" IS NOT NULL AND B."U_LineNum" IS NOT NULL
                     THEN B."U_ObjType" || '-' || TO_NVARCHAR(B."U_DocEntry") || '-' || TO_NVARCHAR(B."U_LineNum") END AS "SK",
                LEFT(TRIM(IFNULL(B."U_Type", '') || ' ' || IFNULL(B."U_ItemCode", '') || ' ' || IFNULL(B."U_LineMemo", '')), 200) AS "Note"
           FROM "MTC_COST_0802_OJDTBASEDETAIL" B
          WHERE B."FcCode" = :FcCode AND B."TransCode" IS NOT NULL
            AND ROUND(IFNULL(B."U_Debit", 0) - IFNULL(B."U_Credit", 0), 2) <> 0;
    -- 0802 与分录（凭证代码 × 科目 × 成本中心 × 项目）对不上的差额补一行，来源合计 = 分录合计
    jd = SELECT IFNULL(J."TC", S."TC") AS "TC", IFNULL(J."Acct", S."Acct") AS "Acct", IFNULL(J."Ocr", S."Ocr") AS "Ocr", IFNULL(J."Prj", S."Prj") AS "Prj",
                IFNULL(J."Amt", 0) - IFNULL(S."Amt", 0) AS "Amt"
           FROM (SELECT "TransCode" AS "TC", "AcctCode" AS "Acct", "OcrCode" AS "Ocr", "Project" AS "Prj", SUM("Debit" - "Credit") AS "Amt"
                   FROM "MTC_CA_R_JDT" WHERE "RunId" = :rid GROUP BY "TransCode", "AcctCode", "OcrCode", "Project") J
           FULL JOIN (SELECT "TC", "Acct", "Ocr", "Prj", SUM("Amt") AS "Amt" FROM :js GROUP BY "TC", "Acct", "Ocr", "Prj") S
             ON S."TC" = J."TC" AND IFNULL(S."Acct", '') = IFNULL(J."Acct", '') AND IFNULL(S."Ocr", '') = IFNULL(J."Ocr", '') AND IFNULL(S."Prj", '') = IFNULL(J."Prj", '');
    INSERT INTO "MTC_CA_R_JDT_SRC" ("FcCode", "RunType", "Scenario", "RunId", "SrcId", "TransCode", "AcctCode", "OcrCode", "Project",
                                    "Amount", "SrcType", "SrcKey", "Note")
    SELECT :FcCode, 'H', 'LEGACY', :rid, ROW_NUMBER() OVER (ORDER BY X."TC", X."K", X."Acct"), X."TC", X."Acct", X."Ocr", X."Prj", X."Amt", X."ST", X."SK", X."Note"
      FROM (SELECT "TC", "Acct", "Ocr", "Prj", "Amt", "ST", "SK", "Note", 0 AS "K" FROM :js
            UNION ALL
            SELECT "TC", "Acct", "Ocr", "Prj", "Amt", 'LEGACY', NULL, '旧 0802 没有对应来源明细的差额', 1 FROM :jd WHERE ABS("Amt") >= 0.005) X;

    -- ---------------- 收尾 ----------------
    INSERT INTO "MTC_CA_RUN_STEP" ("RunId", "StepNo", "StepCode", "StartTime", "EndTime", "RowCnt", "Status", "Msg")
    SELECT :rid, 1, 'LEGACY', "StartTime", CURRENT_TIMESTAMP, :nLine + :nItem + :nOrd + :nMat + :nJdt, 'OK',
           '旧框架回填：单据行 ' || :nLine || '，物料 ' || :nItem || '，订单 ' || :nOrd || '，订单 × 材料 ' || :nMat || '，凭证分录 ' || :nJdt
      FROM "MTC_CA_RUN" WHERE "RunId" = :rid;
    oMsg := :FcCode || ' 回填完成：单据行 ' || :nLine || '，物料 ' || :nItem || '，订单 ' || :nOrd || '，凭证分录 ' || :nJdt
            || CASE WHEN :prevRid IS NULL THEN '；期初取自旧框架 ' || IFNULL(:prevFc, '（无上期）') ELSE '；期初取自上期历史运行 #' || :prevRid END
            || CASE WHEN :nTail > 0 THEN '；' || :nTail || ' 个物料旧框架期末 ≠ 期初 + 收发，差额记尾差（见 22_legacy_verify.sql L07）' ELSE '' END;
    UPDATE "MTC_CA_RUN" SET "Status" = 'OK', "EndTime" = CURRENT_TIMESTAMP, "Msg" = LEFT(:oMsg, 2000) WHERE "RunId" = :rid;
    -- 只留这一期最后一次回填的明细（同运行键 FcCode × H × LEGACY 的其他运行）
    CALL "MTC_CA_P_RUN_CLEAN"(:rid, 'OK', nCln);
    oCode := 0;
END
@@
-- 入口：FcFrom … FcTo 逐期回填（从早到晚，每期提交；某期出错就停，前面已回填的保留）。执行台“期初承接”页“回填历史”按钮调它（管理权限，后台任务）。
CREATE OR REPLACE PROCEDURE "MTC_CA_P_LEGACY_LOAD" (IN FcFrom NVARCHAR(10), IN FcTo NVARCHAR(10), IN UserCode NVARCHAR(50))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE f0 NVARCHAR(10); DECLARE f1 NVARCHAR(10); DECLARE boot NVARCHAR(10); DECLARE fc NVARCHAR(10);
    DECLARE nPer INT; DECLARE i INT; DECLARE nOk INT := 0; DECLARE nRun INT; DECLARE lastH NVARCHAR(10);
    DECLARE c INT; DECLARE m NVARCHAR(2000); DECLARE msgs NVARCHAR(5000) := '';
    f0 := NULLIF(TRIM(IFNULL(:FcFrom, '')), '');
    f1 := NULLIF(TRIM(IFNULL(:FcTo, '')), '');
    -- 先把 B1 @MTC_CA_PARAM 抽到 MTC_CA_C_PARAM，承接账期以抽取后的为准（同期初承接）
    CALL "MTC_CA_P05_CFG_SYNC"(NULL);
    COMMIT;
    boot := "MTC_CA_F_PARAM"('BOOTSTRAP_FC', IFNULL(:f1, TO_NVARCHAR(CURRENT_DATE, 'YYYY-MM')));
    IF :f1 IS NULL THEN f1 := :boot; END IF;
    IF :f0 IS NULL THEN SELECT MIN("FcCode") INTO f0 FROM "MTC_COST_0301_INVNT"; END IF;
    IF :f0 IS NULL OR :f1 IS NULL OR :boot IS NULL THEN
        SELECT -1 AS "Code", '账期范围不完整，或没有配置承接账期 BOOTSTRAP_FC' AS "Msg" FROM DUMMY;
        RETURN;
    END IF;
    IF :f1 > :boot THEN
        SELECT -1 AS "Code", '截止账期 ' || :f1 || ' 在承接账期 ' || :boot || ' 以后；只回填承接账期及以前，以后的账期由新框架计算' AS "Msg" FROM DUMMY;
        RETURN;
    END IF;
    -- 与成本计算互斥（执行台同一时间也只允许一个后台任务）
    SELECT COUNT(*) INTO nRun FROM "MTC_CA_RUN" WHERE "Status" = 'RUNNING' AND "StartTime" > ADD_SECONDS(CURRENT_TIMESTAMP, -21600);
    IF :nRun > 0 THEN
        SELECT -1 AS "Code", '有正在运行的计算，等它结束后再回填' AS "Msg" FROM DUMMY;
        RETURN;
    END IF;
    per = SELECT "Code", ROW_NUMBER() OVER (ORDER BY "Code") AS "Rn" FROM "OFPR" WHERE "Code" BETWEEN :f0 AND :f1;
    SELECT COUNT(*) INTO nPer FROM :per;
    i := 1;
    WHILE :i <= :nPer DO
        SELECT MAX("Code") INTO fc FROM :per WHERE "Rn" = :i;
        CALL "MTC_CA_P_LEGACY_LOAD1"(:fc, :UserCode, c, m);
        IF :c <> 0 THEN
            msgs := :msgs || CASE WHEN :msgs = '' THEN '' ELSE '；' END || :m;
            BREAK;
        END IF;
        COMMIT;
        nOk := :nOk + 1;
        i := :i + 1;
    END WHILE;
    SELECT MAX("FcCode") INTO lastH FROM "MTC_CA_RUN" WHERE "RunType" = 'H' AND "Status" = 'OK';
    SELECT CASE WHEN :nOk = :nPer THEN 0 ELSE -1 END AS "Code",
           LEFT('历史回填 ' || :f0 || ' … ' || :f1 || '：完成 ' || :nOk || ' / ' || :nPer || ' 期'
                || CASE WHEN :msgs <> '' THEN '；' || :msgs ELSE '' END
                || CASE WHEN :nOk = :nPer AND IFNULL(:lastH, '') > :f1 THEN '；' || :f1 || ' 以后已回填的账期（到 ' || :lastH || '）期初取上期历史运行，要接着重新回填' ELSE '' END
                || CASE WHEN :nOk = :nPer THEN '。接着运行 22_legacy_verify.sql 核对' ELSE '' END, 2000) AS "Msg"
      FROM DUMMY;
END
