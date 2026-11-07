-- =====================================================================
-- 新成本框架 第 1 期：P20 输入快照（设计稿 3.4、4）
-- 全部只读 B1，按“截至期末”取数；写 MTC_CA_S_*（带运行键）。
-- 账期范围取 OFPR.F_RefDate–T_RefDate（旧代码用 LEFT(日期,7)=账期，月度账期下等价）。
--   MTC_CA_F_PARAM / MTC_CA_F_ACCT  取参数、科目
--   MTC_CA_P_RUN_CTX                取运行键和账期起止日
--   MTC_CA_P20_ITEM     物料与层级        替代 MTC_CO_001GetItemLevel
--   MTC_CA_P20_LINE     库存变动          替代 0303_INVNTDETAIL2（四段取数）
--   MTC_CA_P20_SUBFEE   委外加工费来源    替代 0306 / MTC_VIEW_ProductDetail ID 3
--   MTC_CA_P20_ORDER    订单与计划用料    替代 0321_OWOR、0106_OWORLIST
--   MTC_CA_P20_EXP      费用来源          替代 0311 的凭证、重估段
--   MTC_CA_P20_MISC     工时、期初维护价
--   MTC_CA_P20_OPEN     物料期初、订单 × 材料期初
--   MTC_CA_P05_CFG_SYNC 费用池 / 计算参数从 B1 自定义表同步到 MTC_CA_C_*（用户 2026-10-14；参数表 2026-10-28 改为 @MTC_CA_PARAM）
--     2026-10-29 起 P_RUN / P_PRECHECK / P_BOOTSTRAP 一开始就先调用它（RunId 为空，不记步骤）；同时刷新 B1 参数快照 MTC_CA_C_PARAM_B1
--   MTC_CA_P_PARAM_B1_SNAP / MTC_CA_P_PARAM_LOCK_CHECK  B1 参数锁定（U_Locked）：快照、保存时检查（2026-10-29）
--   MTC_CA_P20_SNAPSHOT 依次调用以上过程并写步骤日志
-- =====================================================================
CREATE OR REPLACE FUNCTION "MTC_CA_F_PARAM" (IN Code NVARCHAR(50), IN FcCode NVARCHAR(10))
RETURNS Val NVARCHAR(200)
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    SELECT MAX("Value") INTO Val FROM "MTC_CA_C_PARAM"
     WHERE "ParamCode" = :Code AND :FcCode BETWEEN "FromFc" AND "ToFc";
END
@@
CREATE OR REPLACE FUNCTION "MTC_CA_F_ACCT" (IN Usage NVARCHAR(30), IN FcCode NVARCHAR(10))
RETURNS Acct NVARCHAR(15)
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    SELECT MAX("AcctCode") INTO Acct FROM "MTC_CA_C_ACCT"
     WHERE "Usage" = :Usage AND :FcCode BETWEEN "FromFc" AND "ToFc";
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P_RUN_CTX" (
    IN  RunId BIGINT,
    OUT fc    NVARCHAR(10),
    OUT rt    NVARCHAR(1),
    OUT scen  NVARCHAR(30),
    OUT d0    DATE,
    OUT d1    DATE
)
LANGUAGE SQLSCRIPT READS SQL DATA AS
BEGIN
    SELECT MAX(R."FcCode"), MAX(R."RunType"), MAX(R."Scenario"), MAX(TO_DATE(P."F_RefDate")), MAX(TO_DATE(P."T_RefDate"))
      INTO fc, rt, scen, d0, d1
      FROM "MTC_CA_RUN" R JOIN "OFPR" P ON P."Code" = R."FcCode"
     WHERE R."RunId" = :RunId;
END
@@
-- 物料层级：无 BOM = 0；其余 = 子件最高级 + 1；子件缺失、循环引用 = -1（PRE-02 阻断）；最后按 C_LEVEL_OVR 覆盖。
-- 与旧算法的差别：只取 ITT1 中 Type=4（物料）的子件，资源行不参与；不再限制最高 8 级（LEVEL_GUARD 只防死循环）。
CREATE OR REPLACE PROCEDURE "MTC_CA_P20_ITEM" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE guard INT;
    DECLARE i INT := 1;
    DECLARE n BIGINT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    guard := TO_INTEGER(IFNULL("MTC_CA_F_PARAM"('LEVEL_GUARD', :fc), '30'));

    bom = SELECT DISTINCT T1."Father", T1."Code" AS "Child"
            FROM "ITT1" T1 JOIN "OITT" T0 ON T0."Code" = T1."Father"
           WHERE T1."Type" = 4;

    INSERT INTO "MTC_CA_S_ITEM" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "ItemName", "ItmsGrpCod", "GrpType",
                                 "CalType", "InvntItem", "IsBomFather", "iLevel", "LevelSrc")
    SELECT :fc, :rt, :scen, :RunId, I."ItemCode", I."ItemName", TO_NVARCHAR(I."ItmsGrpCod"), G."U_ItemGrpType",
           I."U_ItemProp", I."InvntItem",
           CASE WHEN F."Father" IS NULL THEN 'N' ELSE 'Y' END,
           CASE WHEN F."Father" IS NULL THEN 0 ELSE -1 END,
           CASE WHEN F."Father" IS NULL THEN 'NOBOM' ELSE NULL END
      FROM "OITM" I
      LEFT JOIN "OITB" G ON G."ItmsGrpCod" = I."ItmsGrpCod"
      LEFT JOIN (SELECT DISTINCT "Father" FROM :bom) F ON F."Father" = I."ItemCode";
    RowCnt := ::ROWCOUNT;

    -- 第 i 轮：所有子件都已定级、且子件最高级 = i-1 的父件定为 i 级；某轮没有新定级的就不会再有
    WHILE :i <= :guard DO
        UPDATE "MTC_CA_S_ITEM" SET "iLevel" = :i, "LevelSrc" = 'BOM'
         WHERE "RunId" = :RunId AND "iLevel" = -1
           AND "ItemCode" IN (SELECT B."Father"
                                FROM :bom B
                                LEFT JOIN "MTC_CA_S_ITEM" C ON C."RunId" = :RunId AND C."ItemCode" = B."Child"
                               GROUP BY B."Father"
                              HAVING MIN(IFNULL(C."iLevel", -1)) >= 0 AND MAX(C."iLevel") = :i - 1);
        n := ::ROWCOUNT;
        IF :n = 0 THEN
            BREAK;
        END IF;
        i := :i + 1;
    END WHILE;

    UPDATE "MTC_CA_S_ITEM" SET "LevelNote" = '子件不在物料主数据'
     WHERE "RunId" = :RunId AND "iLevel" = -1
       AND "ItemCode" IN (SELECT B."Father" FROM :bom B
                           WHERE NOT EXISTS (SELECT 1 FROM "OITM" O WHERE O."ItemCode" = B."Child"));
    UPDATE "MTC_CA_S_ITEM"
       SET "LevelNote" = CASE WHEN :i > :guard THEN '超过层级保护上限 ' || :guard ELSE '循环引用，或子件未能定级' END
     WHERE "RunId" = :RunId AND "iLevel" = -1 AND "LevelNote" IS NULL;

    UPDATE T0 SET T0."iLevel" = T1."iLevel", T0."LevelSrc" = 'OVR',
                  T0."LevelNote" = '手工覆盖（原为 ' || T0."iLevel" || '）：' || IFNULL(T1."Reason", '')
      FROM "MTC_CA_S_ITEM" T0
      JOIN "MTC_CA_C_LEVEL_OVR" T1 ON T1."ItemCode" = T0."ItemCode" AND :fc BETWEEN T1."FromFc" AND T1."ToFc"
     WHERE T0."RunId" = :RunId;
END
@@
-- 库存变动：OIVL（计价仓库、排除 67 转储）+ MTC_VIEW_Document 识别交易类型、订单、配对键；
-- 采购收货 / 退货、应付发票 / 贷项的金额按旧 0303 规则算出 SrcAmt；再加 @MTC_OMRV 的 MRV1 重估行（I11；WW 改由 P20_AP 计算）。
-- 与旧 0303 的差别：仓库口径改为 U_IsCost（Q1）；18/19 没有基于收货的取发票行金额（#14）；作废的重估单不再计入。
CREATE OR REPLACE PROCEDURE "MTC_CA_P20_LINE" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE mfgp NVARCHAR(15);
    DECLARE convIn NVARCHAR(20); DECLARE convOut NVARCHAR(20);
    DECLARE n BIGINT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    mfgp := IFNULL("MTC_CA_F_ACCT"('MFG_EXP_PREFIX', :fc), '5101');
    convIn := IFNULL("MTC_CA_F_PARAM"('CONV_IN_BUSITYPE', :fc), '204');     -- 形态转换转入 / 转出的业务类型（参数，2026-10-27）
    convOut := IFNULL("MTC_CA_F_PARAM"('CONV_OUT_BUSITYPE', :fc), '205');

    vdoc0 = SELECT TO_NVARCHAR("ObjType") AS "ObjType", TO_NVARCHAR("DocEntry") AS "DocEntry", TO_NVARCHAR("LineNum") AS "LineNum",
                  "CANCELED", "CardCode", TO_NVARCHAR("BaseType") AS "BaseType", TO_NVARCHAR("BaseEntry") AS "BaseEntry",
                  TO_NVARCHAR("BaseRef") AS "BaseRef", TO_NVARCHAR("BaseLine") AS "BaseLine",
                  NULLIF("TransCode", '') AS "TransCode", "U_BusiType", "AcctCode", "OcrCode"
             FROM "MTC_VIEW_Document"
            WHERE "DocDate" BETWEEN :d0 AND :d1;
    -- 收货 / 发货行的订单兜底（用户 2026-10-29，PRE-06“O03（304）没有关联订单”）：视图只在 IGN1 / IGE1.BaseType = -1 时
    -- 看 U_OWORType，BaseType 为空或其他值时关联不上；这里对视图没给出订单（不是 202 / MTC_OWOR）的 59 / 60 行，按行上
    -- U_OWORType 补上：'202' → U_OWORNum（OWOR.DocNum）找 DocEntry、行号 U_OWORLineNum；'MTC_OWOR' → U_MTCOWORNum（DocEntry）、
    -- 行号 U_MTCOWORLineNum。收货、发货同一规则；形态转换不动。不改旧模块共用的 MTC_VIEW_Document。
    gl = SELECT '59' AS "ObjType", TO_NVARCHAR(D."DocEntry") AS "DocEntry", TO_NVARCHAR(D."LineNum") AS "LineNum",
                TRIM(TO_NVARCHAR(D."U_OWORType")) AS "OT", NULLIF(TRIM(TO_NVARCHAR(D."U_OWORNum")), '') AS "ONum",
                TO_NVARCHAR(D."U_OWORLineNum") AS "OLine", NULLIF(TRIM(TO_NVARCHAR(D."U_MTCOWORNum")), '') AS "MNum",
                TO_NVARCHAR(D."U_MTCOWORLineNum") AS "MLine"
           FROM "IGN1" D JOIN "OIGN" H ON H."DocEntry" = D."DocEntry"
          WHERE H."DocDate" BETWEEN :d0 AND :d1 AND TRIM(TO_NVARCHAR(D."U_OWORType")) IN ('202', 'MTC_OWOR')
         UNION ALL
         SELECT '60', TO_NVARCHAR(D."DocEntry"), TO_NVARCHAR(D."LineNum"),
                TRIM(TO_NVARCHAR(D."U_OWORType")), NULLIF(TRIM(TO_NVARCHAR(D."U_OWORNum")), ''),
                TO_NVARCHAR(D."U_OWORLineNum"), NULLIF(TRIM(TO_NVARCHAR(D."U_MTCOWORNum")), ''),
                TO_NVARCHAR(D."U_MTCOWORLineNum")
           FROM "IGE1" D JOIN "OIGE" H ON H."DocEntry" = D."DocEntry"
          WHERE H."DocDate" BETWEEN :d0 AND :d1 AND TRIM(TO_NVARCHAR(D."U_OWORType")) IN ('202', 'MTC_OWOR');
    -- 订单号（DocNum）在不同编号序列里可能重复：对上多张订单时不关联（PRE-06 报出），避免一行变两行
    glo = SELECT G."ObjType", G."DocEntry", G."LineNum", MAX(G."OT") AS "OT",
                 CASE WHEN MAX(G."OT") = 'MTC_OWOR' THEN MAX(G."MNum")
                      WHEN COUNT(DISTINCT W."DocEntry") = 1 THEN TO_NVARCHAR(MAX(W."DocEntry")) END AS "OEntry",
                 CASE WHEN MAX(G."OT") = '202' THEN MAX(G."OLine") ELSE MAX(G."MLine") END AS "OLine"
            FROM :gl G
            LEFT JOIN "OWOR" W ON G."OT" = '202' AND TO_NVARCHAR(W."DocNum") = G."ONum"
           GROUP BY G."ObjType", G."DocEntry", G."LineNum";
    vdoc = SELECT V."ObjType", V."DocEntry", V."LineNum", V."CANCELED", V."CardCode",
                  CASE WHEN F."OEntry" IS NOT NULL THEN F."OT" ELSE V."BaseType" END AS "BaseType",
                  CASE WHEN F."OEntry" IS NOT NULL THEN F."OEntry" ELSE V."BaseEntry" END AS "BaseEntry",
                  V."BaseRef",
                  CASE WHEN F."OEntry" IS NOT NULL THEN F."OLine" ELSE V."BaseLine" END AS "BaseLine",
                  V."TransCode", V."U_BusiType", V."AcctCode", V."OcrCode"
             FROM :vdoc0 V
             LEFT JOIN :glo F ON F."ObjType" = V."ObjType" AND F."DocEntry" = V."DocEntry" AND F."LineNum" = V."LineNum"
                             AND IFNULL(V."BaseType", '') NOT IN ('202', 'MTC_OWOR')
                             AND IFNULL(V."U_BusiType", '') NOT IN (:convIn, :convOut);

    -- 收货 / 退货行的暂估单价（U_InitPrice 优先）
    rec = SELECT '20' AS "ObjType", D."DocEntry", D."LineNum",
                 CASE WHEN IFNULL(D."U_InitPrice", 0) <> 0 THEN D."U_InitPrice" ELSE D."Price" END AS "Price"
            FROM "PDN1" D
          UNION ALL
          SELECT '21', D."DocEntry", D."LineNum",
                 CASE WHEN IFNULL(D."U_InitPrice", 0) <> 0 THEN D."U_InitPrice" ELSE D."Price" END
            FROM "RPD1" D;

    -- 发票 / 贷项：基于收货 / 退货的取差额，否则取行金额；取消单取原单金额的相反数（原单不限日期）
    inv18 = SELECT D."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate", M."CANCELED", D."BaseType", D."BaseEntry", D."BaseLine",
                   CASE WHEN D."BaseType" IN (20, 21) THEN D."LineTotal" - D."Quantity" * IFNULL(R."Price", 0)
                        ELSE D."LineTotal" END AS "Amt"
              FROM "OPCH" M JOIN "PCH1" D ON D."DocEntry" = M."DocEntry"
              LEFT JOIN :rec R ON R."ObjType" = TO_NVARCHAR(D."BaseType") AND R."DocEntry" = D."BaseEntry" AND R."LineNum" = D."BaseLine";
    inv19 = SELECT D."DocEntry", D."LineNum", TO_DATE(M."DocDate") AS "DocDate", M."CANCELED", D."BaseType", D."BaseEntry", D."BaseLine",
                   CASE WHEN D."BaseType" IN (20, 21) THEN D."LineTotal" - D."Quantity" * IFNULL(R."Price", 0)
                        ELSE D."LineTotal" END AS "Amt"
              FROM "ORPC" M JOIN "RPC1" D ON D."DocEntry" = M."DocEntry"
              LEFT JOIN :rec R ON R."ObjType" = TO_NVARCHAR(D."BaseType") AND R."DocEntry" = D."BaseEntry" AND R."LineNum" = D."BaseLine";

    src = SELECT '20' AS "ObjType", D."DocEntry", D."LineNum",
                 CASE WHEN M."CANCELED" = 'C' THEN -1 ELSE 1 END
                 * CASE WHEN IFNULL(D."U_InitPrice", 0) <> 0 THEN D."U_InitPrice" * D."Quantity" ELSE D."Price" * D."Quantity" END AS "Amt"
            FROM "OPDN" M JOIN "PDN1" D ON D."DocEntry" = M."DocEntry"
           WHERE M."DocDate" BETWEEN :d0 AND :d1
          UNION ALL
          SELECT '21', D."DocEntry", D."LineNum",
                 CASE WHEN M."CANCELED" = 'C' THEN 1 ELSE -1 END
                 * CASE WHEN IFNULL(D."U_InitPrice", 0) <> 0 THEN D."U_InitPrice" * D."Quantity" ELSE D."LineTotal" END
            FROM "ORPD" M JOIN "RPD1" D ON D."DocEntry" = M."DocEntry"
           WHERE M."DocDate" BETWEEN :d0 AND :d1
          UNION ALL
          SELECT '18', A."DocEntry", A."LineNum",
                 CASE WHEN A."CANCELED" = 'C' THEN -IFNULL(O."Amt", 0) ELSE A."Amt" END
            FROM :inv18 A
            LEFT JOIN :inv18 O ON A."CANCELED" = 'C' AND A."BaseType" = 18 AND O."DocEntry" = A."BaseEntry" AND O."LineNum" = A."BaseLine"
           WHERE A."DocDate" BETWEEN :d0 AND :d1
          UNION ALL
          SELECT '19', A."DocEntry", A."LineNum",
                 CASE WHEN A."CANCELED" = 'C' THEN IFNULL(O."Amt", 0) ELSE -A."Amt" END
            FROM :inv19 A
            LEFT JOIN :inv19 O ON A."CANCELED" = 'C' AND A."BaseType" = 19 AND O."DocEntry" = A."BaseEntry" AND O."LineNum" = A."BaseLine"
           WHERE A."DocDate" BETWEEN :d0 AND :d1;

    INSERT INTO "MTC_CA_S_LINE" ("FcCode", "RunType", "Scenario", "RunId", "LineId", "Src", "SrcKey", "ObjType", "DocEntry",
        "DocNum", "LineNum", "Canceled", "DocDate", "ItemCode", "WhsCode", "Qty", "B1Amt", "SrcAmt", "TransCode", "Dir",
        "BusiType", "BusiClass", "CardCode", "BaseType", "BaseEntry", "BaseLine", "OrderType", "OrderEntry", "OrderLine",
        "PairKey", "AcctCode", "OcrCode", "SharedExp")
    SELECT :fc, :rt, :scen, :RunId,
           ROW_NUMBER() OVER (ORDER BY P0."TransSeq"),
           'OIVL', TO_NVARCHAR(P0."TransSeq"), TO_NVARCHAR(P0."TransType"), P0."CreatedBy",
           TO_NVARCHAR(P0."BASE_REF"), P0."DocLineNum", V."CANCELED", TO_DATE(P0."DocDate"),
           P0."ItemCode", P0."LocCode", P0."InQty" - P0."OutQty", P0."SumStock", S."Amt",
           V."TransCode", IO."U_IOType", V."U_BusiType", C."U_TransType", V."CardCode",
           -- 销售退货：标准来源不是交货时，取行上 U_BaseType / U_BaseEntry / U_BaseLine 指向的原交货（PRE-04、退货定价）
           CASE WHEN R16."DocEntry" IS NOT NULL THEN '15' ELSE V."BaseType" END,
           CASE WHEN R16."DocEntry" IS NOT NULL THEN TO_NVARCHAR(R16."U_BaseEntry") ELSE V."BaseEntry" END,
           CASE WHEN R16."DocEntry" IS NOT NULL THEN TO_NVARCHAR(R16."U_BaseLine") ELSE V."BaseLine" END,
           -- 订单领料 / 入库：视图已把 59/60 的来源改写为订单（形态转换 CONV_IN_BUSITYPE / CONV_OUT_BUSITYPE 除外）
           -- 只有工单交易 I03/O03/I07/O07/I08/O08/I09/O09 关联订单；其他交易（如 210 其他辅助领用 O04）
           -- 单据上填了订单号也不关联，不计入订单成本，也不触发 PRE-10（用户 2026-10-14）
           CASE WHEN V."ObjType" IN ('59', '60') AND IFNULL(V."U_BusiType", '') NOT IN (:convIn, :convOut) AND V."TransCode" IN ('I03', 'O03', 'I07', 'O07', 'I08', 'O08', 'I09', 'O09')
                 AND V."BaseType" IN ('202', 'MTC_OWOR') THEN V."BaseType" END,
           CASE WHEN V."ObjType" IN ('59', '60') AND IFNULL(V."U_BusiType", '') NOT IN (:convIn, :convOut) AND V."TransCode" IN ('I03', 'O03', 'I07', 'O07', 'I08', 'O08', 'I09', 'O09')
                 AND V."BaseType" IN ('202', 'MTC_OWOR') AND V."BaseEntry" LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(V."BaseEntry") END,
           CASE WHEN V."ObjType" IN ('59', '60') AND IFNULL(V."U_BusiType", '') NOT IN (:convIn, :convOut) AND V."TransCode" IN ('I03', 'O03', 'I07', 'O07', 'I08', 'O08', 'I09', 'O09')
                 AND V."BaseType" IN ('202', 'MTC_OWOR') AND V."BaseLine" LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(V."BaseLine") END,
           CASE WHEN V."U_BusiType" IN (:convIn, :convOut) AND V."BaseType" IS NOT NULL AND V."BaseEntry" IS NOT NULL AND V."BaseLine" IS NOT NULL
                THEN V."BaseType" || '-' || V."BaseEntry" || '-' || V."BaseLine" END,
           V."AcctCode", V."OcrCode",
           CASE WHEN V."ObjType" IN ('59', '60') AND V."TransCode" IN ('I04', 'O04', 'I10', 'O10')
                 AND V."AcctCode" LIKE :mfgp || '%' THEN 'Y' ELSE 'N' END
      FROM "OIVL" P0
      JOIN "MTC_CA_V_WHS" W ON W."WhsCode" = P0."LocCode" AND W."IsCost" = 'Y'
      LEFT JOIN :vdoc V ON V."ObjType" = TO_NVARCHAR(P0."TransType") AND V."DocEntry" = TO_NVARCHAR(P0."CreatedBy")
                       AND V."LineNum" = TO_NVARCHAR(P0."DocLineNum")
      LEFT JOIN :src S ON S."ObjType" = TO_NVARCHAR(P0."TransType") AND S."DocEntry" = P0."CreatedBy" AND S."LineNum" = P0."DocLineNum"
      LEFT JOIN "@MTC_COST_IOTYPE" IO ON IO."Code" = V."TransCode"
      LEFT JOIN "@U_CIOTRN" C ON C."Code" = V."U_BusiType"
      LEFT JOIN "RDN1" R16 ON V."ObjType" = '16' AND IFNULL(V."CANCELED", 'N') <> 'C' AND IFNULL(V."BaseType", '') <> '15'
                          AND R16."DocEntry" = P0."CreatedBy" AND R16."LineNum" = P0."DocLineNum"
                          AND TO_NVARCHAR(R16."U_BaseType") = '15' AND R16."U_BaseEntry" IS NOT NULL AND R16."U_BaseLine" IS NOT NULL
     WHERE P0."DocDate" BETWEEN :d0 AND :d1
       AND P0."TransType" <> 67;
    RowCnt := ::ROWCOUNT;

    -- 库存重估 WW / MRV1 → I11；U_CalType=InvntCost 的只调整结存，不参与当期成本计算
    INSERT INTO "MTC_CA_S_LINE" ("FcCode", "RunType", "Scenario", "RunId", "LineId", "Src", "SrcKey", "ObjType", "DocEntry",
        "DocNum", "LineNum", "Canceled", "DocDate", "ItemCode", "WhsCode", "Qty", "B1Amt", "SrcAmt", "TransCode", "Dir",
        "BaseType", "BaseEntry", "BaseLine", "AcctCode", "NoCost", "NoCostNote")
    SELECT :fc, :rt, :scen, :RunId,
           :RowCnt + ROW_NUMBER() OVER (ORDER BY T1."DocEntry", T1."LineId"),
           'OMRV', T1."DocEntry" || '-' || T1."LineId", IFNULL(T0."Object", 'MTC_OMRV'), T1."DocEntry",
           TO_NVARCHAR(T0."DocNum"), T1."LineId", T0."Canceled", TO_DATE(T0."U_DocDate"),
           IFNULL(T1."U_ItemCode", ''), NULL, 0, NULL, T1."U_Amount", 'I11', IO."U_IOType",
           T1."U_BaseType", TO_NVARCHAR(T1."U_BaseEntry"), TO_NVARCHAR(T1."U_BaseLine"), T1."U_AcctCode",
           CASE WHEN T1."U_CalType" = 'InvntCost' THEN 'Y' ELSE 'N' END,
           CASE WHEN T1."U_CalType" = 'InvntCost' THEN '重估类型 InvntCost：调整结存，不参与当期成本计算' END
      FROM "@MTC_OMRV" T0
      JOIN "@MTC_OMRV1" T1 ON T1."DocEntry" = T0."DocEntry"
      LEFT JOIN "@MTC_COST_IOTYPE" IO ON IO."Code" = 'I11'
     -- WW（委外发票差异，旧 6101_1 PUR3 写入）不再读，由 MTC_CA_P20_AP 从发票直接计算（设计稿 4.6）
     WHERE T0."U_BaseType" = 'MRV1'
       AND IFNULL(T0."Canceled", 'N') = 'N'
       AND T0."U_DocDate" BETWEEN :d0 AND :d1;
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

    INSERT INTO "MTC_CA_S_SUBFEE" ("FcCode", "RunType", "Scenario", "RunId", "FeeId", "Src", "SrcKey", "DocDate", "ItemCode",
                                   "Qty", "Amount", "RcptEntry", "OrderType", "OrderEntry", "MatchNote")
    SELECT :fc, :rt, :scen, :RunId, ROW_NUMBER() OVER (ORDER BY F."Src", F."SrcKey"),
           F."Src", F."SrcKey", F."DocDate", F."ItemCode", F."Qty", F."Amount",
           CASE WHEN F."RcptEntry" LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(F."RcptEntry") END,
           K."OrderType", CASE WHEN K."OrderEntry" LIKE_REGEXPR '^[0-9]+$' THEN TO_INTEGER(K."OrderEntry") END,
           IFNULL(K."Note", CASE WHEN X."RcptEntry" IS NOT NULL
                                 THEN '生产收货对应多张订单，订单号对不上' ELSE '找不到生产收货或其订单' END)
      FROM :fee F
      LEFT JOIN :pick K ON K."Src" = F."Src" AND K."SrcKey" = F."SrcKey"
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
-- 订单：本期范围内的订单（已下达、截至期初未关闭、未取消），加上本期单据引用到的其他订单（InScope='N'，PRE-10）。
-- 截至期末的状态（设计稿 Q4）：当前状态为关闭且关单日期 ≤ 期末 → CLOSED；关单日期在本期 → ClosedInFc。
CREATE OR REPLACE PROCEDURE "MTC_CA_P20_ORDER" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE n BIGINT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);

    ord = SELECT '202' AS "OrderType", W."DocEntry" AS "OrderEntry", TO_NVARCHAR(W."DocNum") AS "OrderNum",
                 TO_NVARCHAR(W."U_OrdType") AS "WorType", W."ItemCode", W."PlannedQty", TO_DATE(W."PostDate") AS "PostDate",
                 TO_NVARCHAR(W."Status") AS "B1Status", TO_DATE(W."CloseDate") AS "CloseDate", W."CardCode"
            FROM "OWOR" W
          UNION ALL
          SELECT 'MTC_OWOR', M."DocEntry", TO_NVARCHAR(M."DocNum"), TO_NVARCHAR(M."U_OrdType"), M."U_ItemCode", M."U_PlannedQty",
                 TO_DATE(M."U_PostDate"), TO_NVARCHAR(M."U_Status"), TO_DATE(M."U_CloseDate"), M."U_CardCode"
            FROM "@MTC_OWOR" M;

    ref = SELECT DISTINCT "OrderType", "OrderEntry" FROM "MTC_CA_S_LINE" WHERE "RunId" = :RunId AND "OrderEntry" IS NOT NULL
          UNION
          SELECT DISTINCT "OrderType", "OrderEntry" FROM "MTC_CA_S_SUBFEE" WHERE "RunId" = :RunId AND "OrderEntry" IS NOT NULL;

    INSERT INTO "MTC_CA_S_ORDER" ("FcCode", "RunType", "Scenario", "RunId", "OrderType", "OrderEntry", "OrderNum", "WorType",
        "ItemCode", "PlannedQty", "PostDate", "B1Status", "CloseDate", "StatusAtEnd", "ClosedInFc", "InScope", "CardCode")
    SELECT :fc, :rt, :scen, :RunId, O."OrderType", O."OrderEntry", O."OrderNum", O."WorType", O."ItemCode", O."PlannedQty",
           O."PostDate", O."B1Status", O."CloseDate",
           CASE WHEN O."B1Status" = 'L' AND (O."CloseDate" IS NULL OR O."CloseDate" <= :d1) THEN 'CLOSED' ELSE 'OPEN' END,
           CASE WHEN O."B1Status" = 'L' AND O."CloseDate" BETWEEN :d0 AND :d1 THEN 'Y' ELSE 'N' END,
           CASE WHEN O."B1Status" <> 'C' AND IFNULL(O."PostDate", :d0) <= :d1
                 AND NOT (O."B1Status" = 'L' AND O."CloseDate" < :d0) THEN 'Y' ELSE 'N' END,
           O."CardCode"
      FROM :ord O
      LEFT JOIN :ref R ON R."OrderType" = O."OrderType" AND R."OrderEntry" = O."OrderEntry"
     WHERE (O."B1Status" <> 'C' AND IFNULL(O."PostDate", :d0) <= :d1 AND NOT (O."B1Status" = 'L' AND O."CloseDate" < :d0))
        OR R."OrderEntry" IS NOT NULL;
    RowCnt := ::ROWCOUNT;

    UPDATE T0 SET T0."RecvQty" = T1."Qty"
      FROM "MTC_CA_S_ORDER" T0
      JOIN (SELECT "OrderType", "OrderEntry", SUM("Qty") AS "Qty"
              FROM "MTC_CA_S_LINE"
             WHERE "RunId" = :RunId AND "BusiClass" = 'B01' AND "OrderLine" IS NULL AND "OrderEntry" IS NOT NULL
             GROUP BY "OrderType", "OrderEntry") T1
        ON T1."OrderType" = T0."OrderType" AND T1."OrderEntry" = T0."OrderEntry"
     WHERE T0."RunId" = :RunId;

    INSERT INTO "MTC_CA_S_ORDER_LINE" ("FcCode", "RunType", "Scenario", "RunId", "OrderType", "OrderEntry", "OrderLine",
                                       "ItemCode", "BaseQty", "PlannedQty")
    SELECT :fc, :rt, :scen, :RunId, '202', L."DocEntry", L."LineNum", L."ItemCode", L."BaseQty", L."PlannedQty"
      FROM "WOR1" L
      JOIN "MTC_CA_S_ORDER" O ON O."RunId" = :RunId AND O."OrderType" = '202' AND O."OrderEntry" = L."DocEntry"
     WHERE L."ItemType" = 4
    UNION ALL
    SELECT :fc, :rt, :scen, :RunId, 'MTC_OWOR', L."DocEntry", L."LineId", L."U_ItemCode", L."U_BaseQty", L."U_PlannedQty"
      FROM "@MTC_WOR1" L
      JOIN "MTC_CA_S_ORDER" O ON O."RunId" = :RunId AND O."OrderType" = 'MTC_OWOR' AND O."OrderEntry" = L."DocEntry";
    n := ::ROWCOUNT;
    RowCnt := :RowCnt + :n;
END
@@
-- 费用来源（设计稿 4.4）：
--   JDT   已过账凭证：人工科目（LAB_EXP）与制造费用科目（MFG_EXP_PREFIX 开头），凭证代码在 EXP_JDT_TRANSCODES 中（沿用 0311）
--   MRV   重估单 MRV1（含 InvntCost）：费用 = -U_Amount。旧 0311 还读 MRV2（旧 0501 写的 0 数量尾差），新框架由 TAIL-01 / JZ04 处理，
--         不再读（同 P70 的 MR02、P20_LINE，2026-10-17）
--   PROWW 重估单 ProWW 中找不到订单的行：费用 = -U_Amount（找得到订单的进 S_SUBFEE，不再同时进费用池）
-- 不再读 JZ01 / JZ03 草稿（关单差异由迭代产生）；公摊材料来自 S_LINE.SharedExp，在迭代中按当轮单价计价。
CREATE OR REPLACE PROCEDURE "MTC_CA_P20_EXP" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE lab NVARCHAR(15); DECLARE mfgp NVARCHAR(15); DECLARE codes NVARCHAR(200);
    DECLARE n BIGINT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    lab   := IFNULL("MTC_CA_F_ACCT"('LAB_EXP', :fc), '500102');
    mfgp  := IFNULL("MTC_CA_F_ACCT"('MFG_EXP_PREFIX', :fc), '5101');
    codes := IFNULL("MTC_CA_F_PARAM"('EXP_JDT_TRANSCODES', :fc), ',,');

    INSERT INTO "MTC_CA_S_EXP" ("FcCode", "RunType", "Scenario", "RunId", "ExpId", "Src", "SrcKey", "SrcTrans", "SrcObj", "SrcDoc",
                                "DocDate", "AcctCode", "OcrCode", "Elem", "Amount")
    SELECT :fc, :rt, :scen, :RunId, ROW_NUMBER() OVER (ORDER BY T1."TransId", T1."Line_ID"),
           'JDT', T1."TransId" || '-' || T1."Line_ID", IFNULL(T0."TransCode", ''), TO_NVARCHAR(T0."TransType"), T0."CreatedBy",
           TO_DATE(T0."RefDate"), T1."Account", T1."ProfitCode",
           CASE WHEN T1."Account" = :lab THEN 'LAB' ELSE 'MFG' END,
           T1."Debit" - T1."Credit"
      FROM "OJDT" T0
      JOIN "JDT1" T1 ON T1."TransId" = T0."TransId"
     WHERE T0."RefDate" BETWEEN :d0 AND :d1
       AND (T1."Account" = :lab OR T1."Account" LIKE :mfgp || '%')
       AND LOCATE(:codes, ',' || IFNULL(T0."TransCode", '') || ',') > 0;
    RowCnt := ::ROWCOUNT;

    INSERT INTO "MTC_CA_S_EXP" ("FcCode", "RunType", "Scenario", "RunId", "ExpId", "Src", "SrcKey", "SrcTrans", "SrcObj", "SrcDoc",
                                "DocDate", "AcctCode", "OcrCode", "Elem", "Amount", "Note")
    SELECT :fc, :rt, :scen, :RunId, :RowCnt + ROW_NUMBER() OVER (ORDER BY T1."DocEntry", T1."LineId"),
           CASE WHEN T0."U_BaseType" = 'ProWW' THEN 'PROWW' ELSE 'MRV' END,
           T1."DocEntry" || '-' || T1."LineId", T0."U_BaseType", IFNULL(T0."Object", 'MTC_OMRV'), T1."DocEntry",
           TO_DATE(T0."U_DocDate"), T1."U_AcctCode", NULL, 'MFG', -T1."U_Amount",
           CASE WHEN T0."U_BaseType" = 'ProWW' THEN '没有关联到订单的委外重估' ELSE '重估类型 ' || IFNULL(T1."U_CalType", '') END
      FROM "@MTC_OMRV" T0
      JOIN "@MTC_OMRV1" T1 ON T1."DocEntry" = T0."DocEntry"
      LEFT JOIN "OWOR" W ON T1."U_BaseType" = '202' AND W."DocEntry" = T1."U_BaseEntry"
      LEFT JOIN "@MTC_OWOR" M ON T1."U_BaseType" = 'MTC_OWOR' AND M."DocEntry" = T1."U_BaseEntry"
     WHERE IFNULL(T0."Canceled", 'N') = 'N'
       AND T0."U_DocDate" BETWEEN :d0 AND :d1
       AND (T0."U_BaseType" = 'MRV1'
            OR (T0."U_BaseType" = 'ProWW' AND W."DocEntry" IS NULL AND M."DocEntry" IS NULL));
    n := ::ROWCOUNT;
    RowCnt := :RowCnt + :n;
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P20_MISC" (IN RunId BIGINT, OUT RowCnt BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE n BIGINT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);

    -- 工时全是空的物料取 0（2026-10-30：MAX 为 NULL 时写表报 SQL 287，整个运行失败），由 PRE-14 当作没有工时报出
    INSERT INTO "MTC_CA_S_HOURS" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "Hours", "MinHours", "LineCnt")
    SELECT :fc, :rt, :scen, :RunId, T1."U_ItemCode", IFNULL(MAX(T1."U_Time"), 0), IFNULL(MIN(T1."U_Time"), 0), COUNT(*)
      FROM "@MTC_COST_TIME" T0 JOIN "@MTC_COST_TIME1" T1 ON T1."DocEntry" = T0."DocEntry"
     WHERE T0."U_FcCode" = :fc AND IFNULL(T0."Canceled", 'N') = 'N' AND T1."U_ItemCode" IS NOT NULL
     GROUP BY T1."U_ItemCode";
    RowCnt := ::ROWCOUNT;

    INSERT INTO "MTC_CA_S_QCPRICE" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "Price", "MinPrice", "LineCnt")
    SELECT :fc, :rt, :scen, :RunId, T1."U_ItemCode", MAX(T1."U_Price"), MIN(T1."U_Price"), COUNT(*)
      FROM "@MTC_COST_QCPRICE" T0 JOIN "@MTC_COST_QCPRICE1" T1 ON T1."DocEntry" = T0."DocEntry"
     WHERE T0."U_FcCode" = :fc AND IFNULL(T0."Canceled", 'N') = 'N' AND T1."U_ItemCode" IS NOT NULL
       AND IFNULL(T1."U_Price", 0) <> 0
     GROUP BY T1."U_ItemCode";
    n := ::ROWCOUNT;
    RowCnt := :RowCnt + :n;
END
@@
-- 期初：上期 = 承接账期（BOOTSTRAP_FC）时取 MTC_CA_BOOT_*；否则取上期新框架最近一次成功的正式运行结果（2026-10-18 实现）。
-- 取不到时不报错，由 PRE-16 阻断。模拟运行同样取上期正式结果。
-- 上期正式结果重算后，本期要重新计算（期初在取快照时复制，不随上期变化）。
CREATE OR REPLACE PROCEDURE "MTC_CA_P20_OPEN" (IN RunId BIGINT, OUT RowCnt BIGINT, OUT Msg NVARCHAR(500))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE fc NVARCHAR(10); DECLARE rt NVARCHAR(1); DECLARE scen NVARCHAR(30); DECLARE d0 DATE; DECLARE d1 DATE;
    DECLARE prev NVARCHAR(10); DECLARE boot NVARCHAR(10);
    DECLARE prevRun BIGINT;
    DECLARE n BIGINT;
    CALL "MTC_CA_P_RUN_CTX"(:RunId, fc, rt, scen, d0, d1);
    SELECT MAX("Code") INTO prev FROM "OFPR" WHERE "Code" < :fc;
    boot := "MTC_CA_F_PARAM"('BOOTSTRAP_FC', :fc);
    RowCnt := 0;

    IF :prev = :boot THEN
        INSERT INTO "MTC_CA_S_OPEN" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "Qty",
                                     "MatAmt", "MfgAmt", "LabAmt", "SubAmt", "Amount", "Src")
        SELECT :fc, :rt, :scen, :RunId, "ItemCode", "Qty", "MatAmt", "MfgAmt", "LabAmt", "SubAmt", "Amount", 'BOOT'
          FROM "MTC_CA_BOOT_ITEM" WHERE "FcCode" = :boot;
        RowCnt := ::ROWCOUNT;

        -- 订单 × 材料：旧框架不分料工费，按领用材料的承接比例（MTC_CA_BOOT_RATIO）拆分，没有比例的全部记材料（用户 2026-10-18）；
        -- 制造、人工、委外四舍五入到分，材料 = 金额 − 其余三项
        INSERT INTO "MTC_CA_S_ORDER_OPEN" ("FcCode", "RunType", "Scenario", "RunId", "OrderType", "OrderEntry", "ItemCode",
                                           "CumIssueQty", "CumIssueMat", "CumIssueMfg", "CumIssueLab", "CumIssueSub",
                                           "CumCarriedMat", "CumCarriedMfg", "CumCarriedLab", "CumCarriedSub", "Src")
        SELECT :fc, :rt, :scen, :RunId, B."OrderType", B."OrderEntry", B."ItemCode", B."CumIssueQty",
               B."CumIssueAmt" - ROUND(B."CumIssueAmt" * IFNULL(R."RMfg", 0), 2) - ROUND(B."CumIssueAmt" * IFNULL(R."RLab", 0), 2)
                               - ROUND(B."CumIssueAmt" * IFNULL(R."RSub", 0), 2),
               ROUND(B."CumIssueAmt" * IFNULL(R."RMfg", 0), 2), ROUND(B."CumIssueAmt" * IFNULL(R."RLab", 0), 2),
               ROUND(B."CumIssueAmt" * IFNULL(R."RSub", 0), 2),
               B."CumCarriedAmt" - ROUND(B."CumCarriedAmt" * IFNULL(R."RMfg", 0), 2) - ROUND(B."CumCarriedAmt" * IFNULL(R."RLab", 0), 2)
                                 - ROUND(B."CumCarriedAmt" * IFNULL(R."RSub", 0), 2),
               ROUND(B."CumCarriedAmt" * IFNULL(R."RMfg", 0), 2), ROUND(B."CumCarriedAmt" * IFNULL(R."RLab", 0), 2),
               ROUND(B."CumCarriedAmt" * IFNULL(R."RSub", 0), 2),
               'BOOT'
          FROM "MTC_CA_BOOT_ORDER_MAT" B
          LEFT JOIN "MTC_CA_BOOT_RATIO" R ON R."FcCode" = B."FcCode" AND R."ItemCode" = B."ItemCode"
         WHERE B."FcCode" = :boot;
        n := ::ROWCOUNT;
        RowCnt := :RowCnt + :n;

        UPDATE T0 SET T0."PrevRecvQty" = T1."CumRecvQty"
          FROM "MTC_CA_S_ORDER" T0
          JOIN "MTC_CA_BOOT_ORDER" T1 ON T1."FcCode" = :boot AND T1."OrderType" = T0."OrderType" AND T1."OrderEntry" = T0."OrderEntry"
         WHERE T0."RunId" = :RunId;
        Msg := '期初取自承接账期 ' || :boot;
    ELSE
        -- 上期已生成凭单时取凭单所用的那次运行（账期状态 MTC_CA_PERIOD，2026-10-19）；
        -- 否则取上期最近一次成功的正式运行（只有它保留明细；上期未生成凭单时 P00 已警告）
        SELECT MAX("PostRunId") INTO prevRun FROM "MTC_CA_PERIOD" WHERE "FcCode" = :prev AND "Status" = 'POSTED';
        IF :prevRun IS NULL THEN
            SELECT MAX("RunId") INTO prevRun FROM "MTC_CA_RUN"
             WHERE "FcCode" = :prev AND "RunType" = 'F' AND "Scenario" = '' AND "Status" = 'OK';
        END IF;
        IF :prevRun IS NULL THEN
            Msg := '上期 ' || IFNULL(:prev, '（无）') || ' 没有成功的正式运行，请先计算上期';
        ELSE
            -- 物料：上期期末数量和四项金额
            INSERT INTO "MTC_CA_S_OPEN" ("FcCode", "RunType", "Scenario", "RunId", "ItemCode", "Qty",
                                         "MatAmt", "MfgAmt", "LabAmt", "SubAmt", "Amount", "Src")
            SELECT :fc, :rt, :scen, :RunId, "ItemCode", "EndQty", "EndMat", "EndMfg", "EndLab", "EndSub",
                   "EndMat" + "EndMfg" + "EndLab" + "EndSub", 'PREV'
              FROM "MTC_CA_R_ITEM"
             WHERE "RunId" = :prevRun
               AND ("EndQty" <> 0 OR "EndMat" <> 0 OR "EndMfg" <> 0 OR "EndLab" <> 0 OR "EndSub" <> 0);
            RowCnt := ::ROWCOUNT;

            -- 订单 × 材料（含 '#SUBFEE' 委外加工费）：累计领料 = 上期期初累计 + 上期领料；累计结转 = 上期期初累计 + 上期结转 + 关单差异
            -- （即累计领料 − 累计结转 = 上期期末在产品）。上期按关单处理的订单（ClosedInFc = 'Y'）在产品已转关单差异，不再带入；
            -- 未关闭订单的行全部带入（在产品为 0 的也带，结转比例按累计数算）
            INSERT INTO "MTC_CA_S_ORDER_OPEN" ("FcCode", "RunType", "Scenario", "RunId", "OrderType", "OrderEntry", "ItemCode",
                                               "CumIssueQty", "CumIssueMat", "CumIssueMfg", "CumIssueLab", "CumIssueSub",
                                               "CumCarriedMat", "CumCarriedMfg", "CumCarriedLab", "CumCarriedSub", "Src")
            SELECT :fc, :rt, :scen, :RunId, M."OrderType", M."OrderEntry", M."ItemCode",
                   M."OpenIssQty" + M."IssQty",
                   M."OpenIssMat" + M."IssMat", M."OpenIssMfg" + M."IssMfg", M."OpenIssLab" + M."IssLab", M."OpenIssSub" + M."IssSub",
                   M."OpenCarMat" + M."CarMat" + M."ClsMat", M."OpenCarMfg" + M."CarMfg" + M."ClsMfg",
                   M."OpenCarLab" + M."CarLab" + M."ClsLab", M."OpenCarSub" + M."CarSub" + M."ClsSub",
                   'PREV'
              FROM "MTC_CA_R_ORDER_MAT" M
              JOIN "MTC_CA_R_ORDER" O ON O."RunId" = M."RunId" AND O."OrderType" = M."OrderType" AND O."OrderEntry" = M."OrderEntry"
             WHERE M."RunId" = :prevRun AND O."ClosedInFc" = 'N';
            n := ::ROWCOUNT;
            RowCnt := :RowCnt + :n;

            -- 订单累计入库数 = 上期的截至上期累计 + 上期入库
            UPDATE T0 SET T0."PrevRecvQty" = T1."PrevRecvQty" + T1."RecvQty"
              FROM "MTC_CA_S_ORDER" T0
              JOIN "MTC_CA_R_ORDER" T1 ON T1."RunId" = :prevRun AND T1."OrderType" = T0."OrderType" AND T1."OrderEntry" = T0."OrderEntry"
             WHERE T0."RunId" = :RunId;
            Msg := '期初取自上期 ' || :prev || ' 正式运行 #' || :prevRun;
        END IF;
    END IF;
END
@@
-- 应付暂估变动（替代 6101_1 的 TMP 取数，设计稿 4.6；Q16、Q26–Q28）：
--   暂估行 = 收货行、不基于收货的退货行，物料是库存物料或委外加工费物料（SUBFEE_ITEM）；
--   变动 = 暂估行本身（ACCR）、基于它的退货 / 换货（RET）、发票 / 贷项（INV），以及这些单据的取消单（取原单的相反数，Q26）；
--   开票、退货冲回 = 数量 × 暂估单价，累计数量达到暂估行数量的那一笔 = 整行暂估 − 以前已冲回（Q27）；
--   退货按所基于收货行的暂估单价（Q28）。只保存截至期末仍未清、或本期有变动的暂估行（含其历史变动）。
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
-- B1 @MTC_CA_PARAM 原样快照 → MTC_CA_C_PARAM_B1（用户 2026-10-29：参数可在 B1 用 UDF U_Locked = Y 锁定，保存时用快照判断有没有被改）
--   KeyVal 为空 = 整表刷新（P05 每次同步时）；否则只刷新这一条 Code（B1 保存时 MTC_CA_P_B1CFG_TN 调用，删除的行同时从快照删掉）。
--   B1 表不存在时什么都不做；没有 U_Locked 字段时都记 N。B1 表在部署时可能还不存在，所以用动态 SQL。
CREATE OR REPLACE PROCEDURE "MTC_CA_P_PARAM_B1_SNAP" (IN KeyVal NVARCHAR(255), IN Src NVARCHAR(10))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE nTab INT; DECLARE nCol INT;
    DECLARE lk NVARCHAR(200); DECLARE w NVARCHAR(600) := '';
    DECLARE k NVARCHAR(255) := TRIM(:KeyVal);
    SELECT COUNT(*) INTO nTab FROM SYS."TABLES" WHERE "SCHEMA_NAME" = CURRENT_SCHEMA AND "TABLE_NAME" = '@MTC_CA_PARAM';
    IF :nTab = 0 THEN
        RETURN;
    END IF;
    SELECT COUNT(*) INTO nCol FROM SYS."TABLE_COLUMNS"
     WHERE "SCHEMA_NAME" = CURRENT_SCHEMA AND "TABLE_NAME" = '@MTC_CA_PARAM' AND "COLUMN_NAME" = 'U_Locked';
    lk := CASE WHEN :nCol > 0 THEN 'CASE WHEN UPPER(TRIM("U_Locked")) = ''Y'' THEN ''Y'' ELSE ''N'' END' ELSE '''N''' END;
    IF :k IS NULL THEN
        DELETE FROM "MTC_CA_C_PARAM_B1";
    ELSE
        DELETE FROM "MTC_CA_C_PARAM_B1" WHERE "Code" = :k;
        w := ' WHERE TRIM("Code") = ''' || REPLACE(:k, '''', '''''') || '''';
    END IF;
    EXEC 'INSERT INTO "MTC_CA_C_PARAM_B1" ("Code", "FromFc", "ToFc", "Value", "Locked", "SnapSrc", "SnapTime")
          SELECT TRIM("Code"), TRIM("U_FromFc"), TRIM("U_ToFc"), TRIM("U_Value"), ' || :lk || ', ''' || IFNULL(:Src, '') || ''', CURRENT_TIMESTAMP
            FROM "@MTC_CA_PARAM"' || :w;
END
@@
-- 锁定检查（B1 保存 @MTC_CA_PARAM 时由 MTC_CA_P_B1CFG_TN 调用，用户 2026-10-29）：快照里这条是锁定的（上一次保存 / 同步时 U_Locked = Y），
-- 这次保存后仍是 Y 而起始账期、截止账期或取值变了 → 拒绝；整条被删掉 → 拒绝。这次把锁定改成 N 的放行（谁能改由 SAP 权限控制）。
-- errMsg 为空 = 通过。
CREATE OR REPLACE PROCEDURE "MTC_CA_P_PARAM_LOCK_CHECK" (IN KeyVal NVARCHAR(255), OUT errMsg NVARCHAR(200))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE k NVARCHAR(255) := TRIM(:KeyVal);
    DECLARE kq NVARCHAR(600);
    DECLARE nPrev INT; DECLARE nCur INT; DECLARE nCol INT;
    DECLARE prevS NVARCHAR(1000); DECLARE curS NVARCHAR(1000);
    DECLARE lk NVARCHAR(200);
    errMsg := '';
    SELECT COUNT(*) INTO nPrev FROM "MTC_CA_C_PARAM_B1" WHERE "Code" = :k AND "Locked" = 'Y';
    IF :nPrev = 0 THEN
        RETURN;
    END IF;
    SELECT MAX(IFNULL("FromFc", '') || '|' || IFNULL("ToFc", '') || '|' || IFNULL("Value", '')) INTO prevS
      FROM "MTC_CA_C_PARAM_B1" WHERE "Code" = :k;
    kq := '''' || REPLACE(:k, '''', '''''') || '''';
    EXEC 'SELECT COUNT(*) FROM "@MTC_CA_PARAM" WHERE TRIM("Code") = ' || :kq INTO nCur;
    IF :nCur = 0 THEN
        errMsg := LEFT('[成本配置] ' || :k || '：已锁定（U_Locked = Y），不能删除；确需删除，先把锁定改成 N 保存后再删', 200);
        RETURN;
    END IF;
    SELECT COUNT(*) INTO nCol FROM SYS."TABLE_COLUMNS"
     WHERE "SCHEMA_NAME" = CURRENT_SCHEMA AND "TABLE_NAME" = '@MTC_CA_PARAM' AND "COLUMN_NAME" = 'U_Locked';
    lk := CASE WHEN :nCol > 0 THEN 'CASE WHEN UPPER(TRIM("U_Locked")) = ''Y'' THEN ''Y'' ELSE ''N'' END' ELSE '''N''' END;
    EXEC 'SELECT MAX(' || :lk || ' || ''|'' || IFNULL(TRIM("U_FromFc"), '''') || ''|'' || IFNULL(TRIM("U_ToFc"), '''') || ''|'' || IFNULL(TRIM("U_Value"), ''''))
            FROM "@MTC_CA_PARAM" WHERE TRIM("Code") = ' || :kq INTO curS;
    IF LEFT(:curS, 1) = 'Y' AND SUBSTRING(:curS, 3) <> :prevS THEN
        errMsg := LEFT('[成本配置] ' || :k || '：已锁定（U_Locked = Y），取值和起止账期不能改；确需修改，先把锁定改成 N', 200);
    END IF;
END
@@
-- P05：费用归集 / 分摊配置从 B1 自定义表同步（用户 2026-10-14：配置在 SAP 里维护，执行台不做编辑页；表结构见 新框架/B1自定义表_费用配置.md）
--   @MTC_CA_POOL    主数据 UDO 表头：Code 池代码、Name 池名称、U_IsDefault 默认池、U_IsCloseDif 关单差异池、U_Descr
--   @MTC_CA_POOL1   成本中心 → 池：U_OcrCode、U_FromFc、U_ToFc、U_Descr
--   @MTC_CA_POOL2   池 → 分摊范围：U_MatchBy（GRPTYPE / GRP）、U_MatchVal、U_WorTypes、U_FromFc、U_ToFc、U_Descr
--   @MTC_CA_PARAM   计算参数（用户 2026-10-28，平铺表格）：一行 = 一个参数的一段账期；Code = 参数代码，第二段起 代码@起始账期；
--                   U_FromFc、U_ToFc、U_Value（Name / U_Category / U_DataType / U_Hint 只是提示）。参数目录见 MTC_CA_C_PARAM_DEF
--   @MTC_CA_EXPSET / @MTC_CA_EXPSET1  旧的参数表（表头 Code + 子表 U_FromFc、U_ToFc、U_Value）：没建 @MTC_CA_PARAM 或它没有数据时才读
-- 表不存在或没有数据时沿用 MTC_CA_C_*（种子值）。B1 有数据时整组覆盖 MTC_CA_C_POOL / _SRC / _TGT 和 C_PARAM.CLOSE_DIF_POOL，
-- 参数只覆盖 B1 里出现的参数代码。结构错误（重复键、默认池 / 关单差异池不是正好 1 个、未知参数代码、账期格式等）时该组不覆盖，
-- 步骤记 FAIL，由 PRE-18 阻断。账期空 = 不限；订单类型空 = 10,20,30,40；凭证代码里的“空”= 没有凭证代码的手工凭证。
-- 2026-10-28：装了 20_b1cfg_check.sql（视图 MTC_CA_V_B1CFG_ISSUES，B1 保存校验同一口径）时，校验以视图为准；
--   费用池没装视图时用下面的内联检查（含账期格式、起止顺序）；@MTC_CA_PARAM 必须装视图。
-- B1 表在部署时可能还不存在，所以全部用动态 SQL。
-- 2026-10-29：主体改名 _X，多返回 oErr（1 = 有配置错误、该组没覆盖）/ oMsg（同步说明），给执行台“从 B1 拉取”用；
--   MTC_CA_P05_CFG_SYNC(RunId) 签名不变，是外壳（在本过程后面）。
CREATE OR REPLACE PROCEDURE "MTC_CA_P05_CFG_SYNC_X" (IN RunId BIGINT, OUT oErr INT, OUT oMsg NVARCHAR(2000))
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE nTab INT; DECLARE nRow INT; DECLARE nBad INT; DECLARE nDef INT; DECLARE nCls INT; DECLARE nView INT;
    DECLARE n1 INT; DECLARE n2 INT; DECLARE n3 INT;
    DECLARE s NVARCHAR(1000);
    DECLARE err NVARCHAR(1000) := '';
    DECLARE msg NVARCHAR(2000) := '';

    SELECT COUNT(*) INTO nView FROM SYS."VIEWS" WHERE "SCHEMA_NAME" = CURRENT_SCHEMA AND "VIEW_NAME" = 'MTC_CA_V_B1CFG_ISSUES';
    -- B1 参数原样快照（锁定判断用，2026-10-29）
    CALL "MTC_CA_P_PARAM_B1_SNAP"(NULL, 'SYNC');

    -- 费用池
    SELECT COUNT(*) INTO nTab FROM "TABLES"
     WHERE "SCHEMA_NAME" = CURRENT_SCHEMA AND "TABLE_NAME" IN ('@MTC_CA_POOL', '@MTC_CA_POOL1', '@MTC_CA_POOL2');
    IF :nTab < 3 THEN
        msg := '费用池：B1 未建 @MTC_CA_POOL / 1 / 2，沿用 MTC_CA_C_POOL*';
    ELSE
        EXEC 'SELECT COUNT(*) FROM "@MTC_CA_POOL"' INTO nRow;
        IF :nRow = 0 THEN
            msg := '费用池：@MTC_CA_POOL 没有数据，沿用 MTC_CA_C_POOL*';
        ELSE
            EXEC 'SELECT COUNT(*) FROM "@MTC_CA_POOL" WHERE "U_IsDefault" = ''Y''' INTO nDef;
            EXEC 'SELECT COUNT(*) FROM "@MTC_CA_POOL" WHERE "U_IsCloseDif" = ''Y''' INTO nCls;
            IF :nDef <> 1 THEN err := :err || '默认池（U_IsDefault=Y）应正好 1 个，实际 ' || :nDef || ' 个；'; END IF;
            IF :nCls <> 1 THEN err := :err || '关单差异池（U_IsCloseDif=Y）应正好 1 个，实际 ' || :nCls || ' 个；'; END IF;
            IF :nView > 0 THEN
                -- 2026-10-28：与 B1 保存校验同一口径（重复、账期格式、起止顺序、账期段重叠、成本中心 / 匹配值存在等）
                EXEC 'SELECT COUNT(*) FROM "MTC_CA_V_B1CFG_ISSUES" WHERE "Obj" = ''MTC_CA_POOL''' INTO nBad;
                IF :nBad > 0 THEN
                    EXEC 'SELECT LEFT(STRING_AGG("KeyCode" || '' '' || "Msg", ''；'' ORDER BY "KeyCode"), 600) FROM "MTC_CA_V_B1CFG_ISSUES" WHERE "Obj" = ''MTC_CA_POOL''' INTO s;
                    err := :err || :nBad || ' 个问题：' || :s || '；';
                END IF;
            ELSE
                EXEC 'SELECT COUNT(*) FROM (SELECT 1 FROM "@MTC_CA_POOL1" WHERE IFNULL(TRIM("U_OcrCode"), '''') <> ''''
                       GROUP BY TRIM("U_OcrCode"), IFNULL(NULLIF(TRIM("U_FromFc"), ''''), ''0000-00'') HAVING COUNT(*) > 1)' INTO nBad;
                IF :nBad > 0 THEN err := :err || '成本中心 + 起始账期重复 ' || :nBad || ' 组；'; END IF;
                EXEC 'SELECT COUNT(*) FROM (SELECT 1 FROM "@MTC_CA_POOL2" WHERE IFNULL(TRIM("U_MatchVal"), '''') <> ''''
                       GROUP BY "Code", TRIM("U_MatchVal"), IFNULL(NULLIF(TRIM("U_FromFc"), ''''), ''0000-00'') HAVING COUNT(*) > 1)' INTO nBad;
                IF :nBad > 0 THEN err := :err || '分摊范围（池 + 匹配值 + 起始账期）重复 ' || :nBad || ' 组；'; END IF;
                -- 2026-10-28：账期格式和起止顺序（格式不对时按字符串比较会悄悄匹配不上）
                EXEC 'SELECT COUNT(*) FROM (SELECT "U_FromFc" AS F, "U_ToFc" AS T FROM "@MTC_CA_POOL1" UNION ALL SELECT "U_FromFc", "U_ToFc" FROM "@MTC_CA_POOL2")
                       WHERE (IFNULL(TRIM(F), '''') <> '''' AND NOT TRIM(F) LIKE_REGEXPR ''^[0-9]{4}-(0[1-9]|1[0-2])$'')
                          OR (IFNULL(TRIM(T), '''') <> '''' AND NOT TRIM(T) LIKE_REGEXPR ''^[0-9]{4}-(0[1-9]|1[0-2])$'')
                          OR IFNULL(NULLIF(TRIM(F), ''''), ''0000-00'') > IFNULL(NULLIF(TRIM(T), ''''), ''9999-99'')' INTO nBad;
                IF :nBad > 0 THEN err := :err || '成本中心 / 分摊范围的起止账期不是 YYYY-MM 或起始晚于截止 ' || :nBad || ' 行；'; END IF;
            END IF;

            IF :err <> '' THEN
                msg := '费用池：B1 配置有误，未同步，沿用上次的 MTC_CA_C_POOL*：' || RTRIM(:err, '；');
            ELSE
                DELETE FROM "MTC_CA_C_POOL_TGT";
                DELETE FROM "MTC_CA_C_POOL_SRC";
                DELETE FROM "MTC_CA_C_POOL";
                EXEC 'INSERT INTO "MTC_CA_C_POOL" ("PoolCode", "PoolName", "IsDefault", "Descr")
                      SELECT TRIM("Code"), IFNULL(NULLIF(TRIM("Name"), ''''), TRIM("Code")),
                             CASE WHEN "U_IsDefault" = ''Y'' THEN ''Y'' ELSE ''N'' END,
                             LEFT(''B1 @MTC_CA_POOL'' || IFNULL(''：'' || "U_Descr", ''''), 500)
                        FROM "@MTC_CA_POOL"';
                EXEC 'INSERT INTO "MTC_CA_C_POOL_SRC" ("OcrCode", "FromFc", "ToFc", "PoolCode", "Descr")
                      SELECT TRIM("U_OcrCode"), IFNULL(NULLIF(TRIM("U_FromFc"), ''''), ''0000-00''),
                             IFNULL(NULLIF(TRIM("U_ToFc"), ''''), ''9999-99''), TRIM("Code"),
                             LEFT(''B1 @MTC_CA_POOL1'' || IFNULL(''：'' || "U_Descr", ''''), 500)
                        FROM "@MTC_CA_POOL1" WHERE IFNULL(TRIM("U_OcrCode"), '''') <> ''''';
                EXEC 'INSERT INTO "MTC_CA_C_POOL_TGT" ("PoolCode", "ItmsGrpCod", "FromFc", "ToFc", "WorTypes", "Descr", "MatchBy")
                      SELECT TRIM("Code"), TRIM("U_MatchVal"), IFNULL(NULLIF(TRIM("U_FromFc"), ''''), ''0000-00''),
                             IFNULL(NULLIF(TRIM("U_ToFc"), ''''), ''9999-99''),
                             CASE WHEN IFNULL(TRIM("U_WorTypes"), '''') = '''' THEN '',10,20,30,40,''
                                  ELSE '','' || REPLACE(REPLACE(TRIM("U_WorTypes"), '' '', ''''), ''，'', '','') || '','' END,
                             LEFT(''B1 @MTC_CA_POOL2'' || IFNULL(''：'' || "U_Descr", ''''), 500),
                             UPPER(IFNULL(NULLIF(TRIM("U_MatchBy"), ''''), ''GRPTYPE''))
                        FROM "@MTC_CA_POOL2" WHERE IFNULL(TRIM("U_MatchVal"), '''') <> ''''';
                DELETE FROM "MTC_CA_C_PARAM" WHERE "ParamCode" = 'CLOSE_DIF_POOL';
                EXEC 'INSERT INTO "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr")
                      SELECT ''CLOSE_DIF_POOL'', ''0000-00'', ''9999-99'', TRIM("Code"), ''STR'', ''关单差异进的费用池（B1 @MTC_CA_POOL.U_IsCloseDif）''
                        FROM "@MTC_CA_POOL" WHERE "U_IsCloseDif" = ''Y''';
                SELECT COUNT(*) INTO n1 FROM "MTC_CA_C_POOL";
                SELECT COUNT(*) INTO n2 FROM "MTC_CA_C_POOL_SRC";
                SELECT COUNT(*) INTO n3 FROM "MTC_CA_C_POOL_TGT";
                msg := '费用池：已从 B1 同步 ' || :n1 || ' 个池、' || :n2 || ' 条成本中心、' || :n3 || ' 条分摊范围';
            END IF;
        END IF;
    END IF;

    -- 计算参数：科目用途 MFG_EXP_PREFIX / LAB_EXP（→ C_ACCT）和 MTC_CA_C_PARAM 中除 CLOSE_DIF_POOL 外的全部参数（→ C_PARAM）
    -- 都可以在 B1 维护（用户 2026-10-14）。B1 中出现的代码整组以 B1 为准（各起止账期行全部替换），没出现的沿用 MTC_CA_C_* 现有值。
    -- 列表型参数在 B1 里直接填 A,B,C，同步时转成 ,A,B,C,；单独一项“空”表示空代码（EXP_JDT_TRANSCODES）。
    -- CLOSE_DIF_POOL 在费用池 @MTC_CA_POOL.U_IsCloseDif 维护，这里不接受。
    -- 2026-10-28 起优先读平铺表 @MTC_CA_PARAM（参数目录 MTC_CA_C_PARAM_DEF，校验 MTC_CA_V_B1CFG_ISSUES）；没有时读旧 @MTC_CA_EXPSET / 1。
    n1 := LENGTH(:err);
    SELECT COUNT(*) INTO nTab FROM "TABLES" WHERE "SCHEMA_NAME" = CURRENT_SCHEMA AND "TABLE_NAME" = '@MTC_CA_PARAM';
    nRow := 0;
    IF :nTab = 1 THEN
        EXEC 'SELECT COUNT(*) FROM "@MTC_CA_PARAM"' INTO nRow;
    END IF;
    IF :nRow > 0 THEN
        IF :nView = 0 THEN
            err := :err || '已建 @MTC_CA_PARAM，但没有安装校验视图 MTC_CA_V_B1CFG_ISSUES（B1 建全 @MTC_CA_POOL / 1 / 2、OPRC.U_CalType 后重新部署，或执行 新框架/sql/20_b1cfg_check.sql）；';
        ELSE
            EXEC 'SELECT COUNT(*) FROM "MTC_CA_V_B1CFG_ISSUES" WHERE "Obj" = ''MTC_CA_PARAM''' INTO nBad;
            IF :nBad > 0 THEN
                EXEC 'SELECT LEFT(STRING_AGG("KeyCode" || '' '' || "Msg", ''；'' ORDER BY "KeyCode"), 600) FROM "MTC_CA_V_B1CFG_ISSUES" WHERE "Obj" = ''MTC_CA_PARAM''' INTO s;
                err := :err || :nBad || ' 个问题：' || :s || '；';
            END IF;
        END IF;
        IF LENGTH(:err) > :n1 THEN
            msg := :msg || '；计算参数：B1 @MTC_CA_PARAM 配置有误，未同步：' || RTRIM(SUBSTRING(:err, :n1 + 1), '；');
        ELSE
            -- B 子查询：参数代码 = Code 中 @ 之前的部分
            EXEC 'DELETE FROM "MTC_CA_C_ACCT" WHERE "Usage" IN (
                    SELECT D."ParamCode" FROM "@MTC_CA_PARAM" B JOIN "MTC_CA_C_PARAM_DEF" D ON D."ParamCode" = SUBSTR_BEFORE(TRIM(B."Code") || ''@'', ''@'')
                     WHERE D."Target" = ''ACCT'')';
            EXEC 'INSERT INTO "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr")
                  SELECT D."ParamCode", IFNULL(NULLIF(TRIM(B."U_FromFc"), ''''), ''0000-00''), IFNULL(NULLIF(TRIM(B."U_ToFc"), ''''), ''9999-99''),
                         TRIM(B."U_Value"), ''B1 @MTC_CA_PARAM：'' || D."CnName"
                    FROM "@MTC_CA_PARAM" B JOIN "MTC_CA_C_PARAM_DEF" D ON D."ParamCode" = SUBSTR_BEFORE(TRIM(B."Code") || ''@'', ''@'')
                   WHERE D."Target" = ''ACCT''';
            -- C_PARAM：B1 中出现的参数，旧行先改名（FromFc 前加 #）保留类型和说明，插入 B1 的行后再删掉旧行
            EXEC 'UPDATE "MTC_CA_C_PARAM" SET "FromFc" = ''#'' || "FromFc"
                   WHERE LEFT("FromFc", 1) <> ''#'' AND "ParamCode" IN (
                         SELECT D."ParamCode" FROM "@MTC_CA_PARAM" B JOIN "MTC_CA_C_PARAM_DEF" D ON D."ParamCode" = SUBSTR_BEFORE(TRIM(B."Code") || ''@'', ''@'')
                          WHERE D."Target" = ''PARAM'')';
            EXEC 'INSERT INTO "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr")
                  SELECT D."ParamCode", IFNULL(NULLIF(TRIM(B."U_FromFc"), ''''), ''0000-00''), IFNULL(NULLIF(TRIM(B."U_ToFc"), ''''), ''9999-99''),
                         CASE WHEN D."DataType" <> ''LIST'' THEN TRIM(B."U_Value")
                              WHEN TRIM(BOTH '','' FROM REPLACE(REPLACE(IFNULL(TRIM(B."U_Value"), ''''), '' '', ''''), ''，'', '','')) = '''' THEN '',''
                              ELSE REPLACE(REPLACE('','' || TRIM(BOTH '','' FROM REPLACE(REPLACE(UPPER(IFNULL(TRIM(B."U_Value"), '''')), '' '', ''''), ''，'', '','')) || '','',
                                                   '',空,'', '',,''), '',空,'', '',,'') END,
                         CASE WHEN D."DataType" = ''LIST'' THEN ''LIST'' WHEN D."DataType" IN (''DEC'', ''INT'') THEN D."DataType" ELSE ''STR'' END,
                         LEFT(''B1 @MTC_CA_PARAM：'' || IFNULL(O."Descr", D."CnName"), 500)
                    FROM "@MTC_CA_PARAM" B
                    JOIN "MTC_CA_C_PARAM_DEF" D ON D."ParamCode" = SUBSTR_BEFORE(TRIM(B."Code") || ''@'', ''@'') AND D."Target" = ''PARAM''
                    LEFT JOIN (SELECT "ParamCode", MAX(REPLACE(REPLACE("Descr", ''B1 @MTC_CA_EXPSET：'', ''''), ''B1 @MTC_CA_PARAM：'', '''')) AS "Descr"
                                 FROM "MTC_CA_C_PARAM" WHERE LEFT("FromFc", 1) = ''#'' GROUP BY "ParamCode") O
                      ON O."ParamCode" = D."ParamCode"';
            DELETE FROM "MTC_CA_C_PARAM" WHERE LEFT("FromFc", 1) = '#';
            msg := :msg || '；计算参数：已从 B1 @MTC_CA_PARAM 同步 ' || :nRow || ' 行';
        END IF;
    ELSE
    -- 旧表 @MTC_CA_EXPSET / 1（2026-10-14 的逻辑；2026-10-28 只改了“空”的替换）
    SELECT COUNT(*) INTO nTab FROM "TABLES"
     WHERE "SCHEMA_NAME" = CURRENT_SCHEMA AND "TABLE_NAME" IN ('@MTC_CA_EXPSET', '@MTC_CA_EXPSET1');
    IF :nTab < 2 THEN
        msg := :msg || '；计算参数：B1 未建 @MTC_CA_PARAM（或旧 @MTC_CA_EXPSET / 1），沿用 MTC_CA_C_ACCT / C_PARAM';
    ELSE
        EXEC 'SELECT COUNT(*) FROM "@MTC_CA_EXPSET1"' INTO nRow;
        IF :nRow = 0 THEN
            msg := :msg || '；计算参数：@MTC_CA_PARAM 和旧 @MTC_CA_EXPSET1 都没有数据，沿用 MTC_CA_C_ACCT / C_PARAM';
        ELSE
            EXEC 'SELECT COUNT(*) FROM "@MTC_CA_EXPSET" E
                   WHERE TRIM(E."Code") NOT IN (''MFG_EXP_PREFIX'', ''LAB_EXP'')
                     AND NOT EXISTS (SELECT 1 FROM "MTC_CA_C_PARAM" P WHERE P."ParamCode" = TRIM(E."Code") AND P."ParamCode" <> ''CLOSE_DIF_POOL'')' INTO nBad;
            IF :nBad > 0 THEN err := :err || '有 ' || :nBad || ' 个参数代码不认识（CLOSE_DIF_POOL 请在费用池的“关单差异池”维护）；'; END IF;
            EXEC 'SELECT COUNT(*) FROM (SELECT 1 FROM "@MTC_CA_EXPSET1"
                   GROUP BY TRIM("Code"), IFNULL(NULLIF(TRIM("U_FromFc"), ''''), ''0000-00'') HAVING COUNT(*) > 1)' INTO nBad;
            IF :nBad > 0 THEN err := :err || '参数 + 起始账期重复 ' || :nBad || ' 组；'; END IF;
            EXEC 'SELECT COUNT(*) FROM "@MTC_CA_EXPSET1"
                   WHERE (IFNULL(TRIM("U_FromFc"), '''') <> '''' AND NOT TRIM("U_FromFc") LIKE_REGEXPR ''^[0-9]{4}-[0-9]{2}$'')
                      OR (IFNULL(TRIM("U_ToFc"), '''') <> '''' AND NOT TRIM("U_ToFc") LIKE_REGEXPR ''^[0-9]{4}-[0-9]{2}$'')' INTO nBad;
            IF :nBad > 0 THEN err := :err || '起止账期不是 YYYY-MM 格式 ' || :nBad || ' 行；'; END IF;
            -- 取值：科目和非列表参数不能为空；DEC 必须是数字、INT 必须是整数
            EXEC 'SELECT COUNT(*) FROM "@MTC_CA_EXPSET1" E
                   WHERE IFNULL(TRIM(E."U_Value"), '''') = ''''
                     AND (TRIM(E."Code") IN (''MFG_EXP_PREFIX'', ''LAB_EXP'')
                          OR EXISTS (SELECT 1 FROM "MTC_CA_C_PARAM" P WHERE P."ParamCode" = TRIM(E."Code")
                                      AND P."DataType" <> ''LIST'' AND LEFT(IFNULL(P."Value", ''''), 1) <> '',''))' INTO nBad;
            IF :nBad > 0 THEN err := :err || '取值为空 ' || :nBad || ' 行；'; END IF;
            EXEC 'SELECT COUNT(*) FROM "@MTC_CA_EXPSET1" E
                   WHERE EXISTS (SELECT 1 FROM "MTC_CA_C_PARAM" P WHERE P."ParamCode" = TRIM(E."Code")
                                  AND ((P."DataType" = ''DEC'' AND NOT IFNULL(TRIM(E."U_Value"), '''') LIKE_REGEXPR ''^-?[0-9]+(\.[0-9]+)?$'')
                                    OR (P."DataType" = ''INT'' AND NOT IFNULL(TRIM(E."U_Value"), '''') LIKE_REGEXPR ''^-?[0-9]+$'')))' INTO nBad;
            IF :nBad > 0 THEN err := :err || '数值参数的取值不是数字 ' || :nBad || ' 行；'; END IF;

            IF LENGTH(:err) > :n1 THEN
                msg := :msg || '；计算参数：B1 配置有误，未同步：' || RTRIM(SUBSTRING(:err, :n1 + 1), '；');
            ELSE
                EXEC 'DELETE FROM "MTC_CA_C_ACCT" WHERE "Usage" IN (SELECT TRIM("Code") FROM "@MTC_CA_EXPSET1" WHERE TRIM("Code") IN (''MFG_EXP_PREFIX'', ''LAB_EXP''))';
                EXEC 'INSERT INTO "MTC_CA_C_ACCT" ("Usage", "FromFc", "ToFc", "AcctCode", "Descr")
                      SELECT TRIM("Code"), IFNULL(NULLIF(TRIM("U_FromFc"), ''''), ''0000-00''), IFNULL(NULLIF(TRIM("U_ToFc"), ''''), ''9999-99''),
                             TRIM("U_Value"), ''B1 @MTC_CA_EXPSET''
                        FROM "@MTC_CA_EXPSET1" WHERE TRIM("Code") IN (''MFG_EXP_PREFIX'', ''LAB_EXP'')';
                -- C_PARAM：B1 中出现的参数，旧行先改名（FromFc 前加 #）保留类型和说明，插入 B1 的行后再删掉旧行
                EXEC 'UPDATE "MTC_CA_C_PARAM" SET "FromFc" = ''#'' || "FromFc"
                       WHERE LEFT("FromFc", 1) <> ''#'' AND "ParamCode" IN (SELECT TRIM("Code") FROM "@MTC_CA_EXPSET1")';
                -- 2026-10-28：“空”只替换单独的一项（原来整串替换，会把带“空”字的值改掉）
                EXEC 'INSERT INTO "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr")
                      SELECT TRIM(E."Code"), IFNULL(NULLIF(TRIM(E."U_FromFc"), ''''), ''0000-00''), IFNULL(NULLIF(TRIM(E."U_ToFc"), ''''), ''9999-99''),
                             CASE WHEN O."IsList" = 1
                                  THEN REPLACE(REPLACE('','' || TRIM(BOTH '','' FROM REPLACE(REPLACE(UPPER(IFNULL(TRIM(E."U_Value"), '''')), '' '', ''''), ''，'', '','')) || '','',
                                                       '',空,'', '',,''), '',空,'', '',,'')
                                  ELSE TRIM(E."U_Value") END,
                             CASE WHEN O."IsList" = 1 THEN ''LIST'' ELSE O."DataType" END,
                             LEFT(''B1 @MTC_CA_EXPSET：'' || O."Descr", 500)
                        FROM "@MTC_CA_EXPSET1" E
                        JOIN (SELECT "ParamCode", MAX("DataType") AS "DataType",
                                     MAX(CASE WHEN "DataType" = ''LIST'' OR LEFT(IFNULL("Value", ''''), 1) = '','' THEN 1 ELSE 0 END) AS "IsList",
                                     MAX(REPLACE(REPLACE("Descr", ''B1 @MTC_CA_EXPSET：'', ''''), ''B1 @MTC_CA_PARAM：'', '''')) AS "Descr"
                                FROM "MTC_CA_C_PARAM" WHERE LEFT("FromFc", 1) = ''#'' GROUP BY "ParamCode") O
                          ON O."ParamCode" = TRIM(E."Code")';
                DELETE FROM "MTC_CA_C_PARAM" WHERE LEFT("FromFc", 1) = '#';
                msg := :msg || '；计算参数：已从 B1 旧 @MTC_CA_EXPSET 同步 ' || :nRow || ' 行';
            END IF;
        END IF;
    END IF;
    END IF;

    -- 成本中心按 OPRC.U_CalType（成本计入类型）归池（用户 2026-10-14）：C_POOL_SRC 的 OcrCode 既可以是成本中心代码，
    -- 也可以是 U_CalType 的取值（如 P017 = 包装车间）。U_CalType 等于某条配置的成本中心，展开成一条同池、同账期的配置
    -- （Descr 标记 'OPRC.U_CalType=<值>'，每次运行先删后建）；本身已单独配置的成本中心不展开；U_CalType 为空的进默认池。
    DELETE FROM "MTC_CA_C_POOL_SRC" WHERE "Descr" LIKE 'OPRC.U\_CalType=%' ESCAPE '\';
    SELECT COUNT(*) INTO nTab FROM "TABLE_COLUMNS"
     WHERE "SCHEMA_NAME" = CURRENT_SCHEMA AND "TABLE_NAME" = 'OPRC' AND "COLUMN_NAME" = 'U_CalType';
    IF :nTab > 0 THEN
        EXEC 'INSERT INTO "MTC_CA_C_POOL_SRC" ("OcrCode", "FromFc", "ToFc", "PoolCode", "Descr")
              SELECT P."PrcCode", S."FromFc", S."ToFc", S."PoolCode", ''OPRC.U_CalType='' || S."OcrCode"
                FROM "OPRC" P
                JOIN "MTC_CA_C_POOL_SRC" S ON S."OcrCode" = TRIM(P."U_CalType")
               WHERE IFNULL(TRIM(P."U_CalType"), '''') <> '''' AND S."OcrCode" <> P."PrcCode"
                 AND NOT EXISTS (SELECT 1 FROM "MTC_CA_C_POOL_SRC" X WHERE X."OcrCode" = P."PrcCode")';
        SELECT COUNT(*) INTO n1 FROM "MTC_CA_C_POOL_SRC" WHERE "Descr" LIKE 'OPRC.U\_CalType=%' ESCAPE '\';
        msg := :msg || '；按 OPRC.U_CalType 归池的成本中心 ' || :n1 || ' 个';
    END IF;

    -- 运行记录里的参数快照在 P00 记下，同步后按本期生效值刷新（B1 改的参数要体现在本次运行记录里）
    UPDATE "MTC_CA_RUN" R
       SET "Params" = (SELECT '{' || IFNULL(STRING_AGG('"' || P."ParamCode" || '":"' || REPLACE(REPLACE(P."Value", '\', '\\'), '"', '\"') || '"', ',' ORDER BY P."ParamCode"), '') || '}'
                         FROM "MTC_CA_C_PARAM" P WHERE R."FcCode" BETWEEN P."FromFc" AND P."ToFc")
     WHERE R."RunId" = :RunId;

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P05', CASE WHEN :err <> '' THEN 'FAIL' ELSE 'OK' END, NULL, LEFT(:msg, 2000));
    oErr := CASE WHEN :err <> '' THEN 1 ELSE 0 END;
    oMsg := LEFT(:msg, 2000);
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P05_CFG_SYNC" (IN RunId BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE e INT; DECLARE m NVARCHAR(2000);
    CALL "MTC_CA_P05_CFG_SYNC_X"(:RunId, e, m);
END
@@
-- 执行台“从 B1 拉取”（用户 2026-10-29）：不算、不建运行记录，只把 B1 @MTC_CA_PARAM / 费用池抽取到 MTC_CA_C_*，返回 Code / Msg。
-- 有运行中的计算时拒绝（会改掉正在用的参数）。
CREATE OR REPLACE PROCEDURE "MTC_CA_P_CFG_PULL" ()
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE n INT; DECLARE e INT; DECLARE m NVARCHAR(2000);
    SELECT COUNT(*) INTO n FROM "MTC_CA_RUN" WHERE "Status" = 'RUNNING';
    IF :n > 0 THEN
        SELECT -1 AS "Code", '有运行中的计算，等它结束再拉取（如确认已中断，先用 MTC_CA_P_RUN_END 把它标为 FAIL）' AS "Msg" FROM DUMMY;
        RETURN;
    END IF;
    CALL "MTC_CA_P05_CFG_SYNC_X"(NULL, e, m);
    SELECT CASE WHEN :e = 0 THEN 0 ELSE -1 END AS "Code",
           CASE WHEN :e = 0 THEN '已从 B1 拉取：' ELSE 'B1 配置有错，出错的那一组没有覆盖：' END || TRIM(LEADING '；' FROM :m) AS "Msg" FROM DUMMY;
END
@@
CREATE OR REPLACE PROCEDURE "MTC_CA_P20_SNAPSHOT" (IN RunId BIGINT)
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE n BIGINT;
    DECLARE m NVARCHAR(500);
    -- 先把 B1 里维护的费用池 / 归集参数同步到 MTC_CA_C_*（用户 2026-10-14）
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P05', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P05_CFG_SYNC"(:RunId);

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_ITEM', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P20_ITEM"(:RunId, n);
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_ITEM', 'OK', :n, '物料与层级');

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_LINE', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P20_LINE"(:RunId, n);
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_LINE', 'OK', :n, '库存变动');

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_AP', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P20_AP"(:RunId, n);
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_AP', 'OK', :n, '应付暂估变动、委外发票差异');

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_SUBFEE', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P20_SUBFEE"(:RunId, n);
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_SUBFEE', 'OK', :n, '委外加工费');

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_ORDER', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P20_ORDER"(:RunId, n);
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_ORDER', 'OK', :n, '订单与计划用料');

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_EXP', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P20_EXP"(:RunId, n);
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_EXP', 'OK', :n, '费用来源');

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_MISC', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P20_MISC"(:RunId, n);
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_MISC', 'OK', :n, '工时、期初维护价');

    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_OPEN', 'RUNNING', NULL, NULL);
    CALL "MTC_CA_P20_OPEN"(:RunId, n, m);
    CALL "MTC_CA_P_LOG_STEP"(:RunId, 'P20_OPEN', CASE WHEN :n > 0 THEN 'OK' ELSE 'WARN' END, :n, :m);
END
