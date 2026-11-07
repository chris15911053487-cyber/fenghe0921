-- =====================================================================
-- 新成本框架 第 1 期：费用池配置（设计稿 4.4，替代 0312 中写死的车间和物料组）
-- 初始值按旧 0312【读代码】。Q9 用户确认：车间划分做成配置，以后在这三张表里改，不改代码。
-- 关单差异固定进 C_PARAM.CLOSE_DIF_POOL（Q10）；没配置的成本中心、没有成本中心的重估进默认池（Q12）。
-- =====================================================================
CREATE COLUMN TABLE "MTC_CA_C_POOL" (
    "PoolCode"   NVARCHAR(20)   NOT NULL,
    "PoolName"   NVARCHAR(100)  NOT NULL,
    "IsDefault"  NVARCHAR(1)    NOT NULL DEFAULT 'N',   -- 成本中心没有配置时进默认池；只能有一个
    "Descr"      NVARCHAR(500),
    PRIMARY KEY ("PoolCode")
)
@@
COMMENT ON TABLE "MTC_CA_C_POOL" IS '费用池（车间）：制造费用和人工按池归集、按池分摊'
@@
CREATE COLUMN TABLE "MTC_CA_C_POOL_SRC" (
    "OcrCode"    NVARCHAR(20)   NOT NULL,               -- 成本中心（OPRC.PrcCode）
    "FromFc"     NVARCHAR(10)   NOT NULL DEFAULT '0000-00',
    "ToFc"       NVARCHAR(10)   NOT NULL DEFAULT '9999-99',
    "PoolCode"   NVARCHAR(20)   NOT NULL,
    "Descr"      NVARCHAR(500),
    PRIMARY KEY ("OcrCode", "FromFc")
)
@@
COMMENT ON TABLE "MTC_CA_C_POOL_SRC" IS '成本中心 → 费用池；没有配置的成本中心进默认池'
@@
CREATE COLUMN TABLE "MTC_CA_C_POOL_TGT" (
    "PoolCode"    NVARCHAR(20)   NOT NULL,
    "ItmsGrpCod"  NVARCHAR(20)   NOT NULL,              -- 匹配值：MatchBy=GRP 时是产品物料组 OITM.ItmsGrpCod，GRPTYPE 时是 OITB.U_ItemGrpType
    "FromFc"      NVARCHAR(10)   NOT NULL DEFAULT '0000-00',
    "ToFc"        NVARCHAR(10)   NOT NULL DEFAULT '9999-99',
    "WorTypes"    NVARCHAR(100)  NOT NULL DEFAULT ',10,20,30,40,',  -- 可分摊的订单类型，前后带逗号
    "Descr"       NVARCHAR(500),
    "MatchBy"     NVARCHAR(10)   NOT NULL DEFAULT 'GRP', -- GRP 按物料组 / GRPTYPE 按 U_ItemGrpType（Q17，与 PP05 凭证车间一致）
    PRIMARY KEY ("PoolCode", "ItmsGrpCod", "FromFc")
)
@@
COMMENT ON TABLE "MTC_CA_C_POOL_TGT" IS '费用池 → 可分摊的产品（按物料组或 U_ItemGrpType）和订单类型；权重 = 单位工时 × 订单本期入库数；同一产品只能属于一个池（Q22）'
@@
-- 已部署的库补列（2026-10-13 Q17 新增 MatchBy）
DO BEGIN
    DECLARE n INT;
    SELECT COUNT(*) INTO n FROM SYS.TABLE_COLUMNS
     WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME = 'MTC_CA_C_POOL_TGT' AND COLUMN_NAME = 'MatchBy';
    IF :n = 0 THEN
        EXEC 'ALTER TABLE "MTC_CA_C_POOL_TGT" ADD ("MatchBy" NVARCHAR(10) NOT NULL DEFAULT ''GRP'')';
    END IF;
END
@@
UPSERT "MTC_CA_C_POOL" ("PoolCode", "PoolName", "IsDefault", "Descr") VALUES ('MFG', '制造车间', 'Y', '旧 0312：成本中心不是 P017 的费用') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_POOL" ("PoolCode", "PoolName", "IsDefault", "Descr") VALUES ('PKG', '包装车间', 'N', '旧 0312：成本中心 P017 的费用') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_POOL_SRC" ("OcrCode", "FromFc", "ToFc", "PoolCode", "Descr") VALUES ('P017', '0000-00', '9999-99', 'PKG', '旧 0312 写死') WITH PRIMARY KEY
@@
-- 分摊范围按 OITB.U_ItemGrpType（Q17，用户 2026-10-13 已维护）：A 包装成品 → PKG；B 生产成品、C → MFG（同旧 0312 的 101 / 102、103）
-- 先删掉早期按物料组写的初值，避免同一产品匹配两条
DELETE FROM "MTC_CA_C_POOL_TGT" WHERE "MatchBy" = 'GRP' AND "Descr" = '旧 0312 写死' AND "ItmsGrpCod" IN ('101', '102', '103')
@@
UPSERT "MTC_CA_C_POOL_TGT" ("PoolCode", "ItmsGrpCod", "FromFc", "ToFc", "WorTypes", "Descr", "MatchBy") VALUES ('PKG', 'A', '0000-00', '9999-99', ',10,20,30,40,', '车间类别 A 包装（旧 0312 物料组 101）', 'GRPTYPE') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_POOL_TGT" ("PoolCode", "ItmsGrpCod", "FromFc", "ToFc", "WorTypes", "Descr", "MatchBy") VALUES ('MFG', 'B', '0000-00', '9999-99', ',10,20,30,40,', '车间类别 B（旧 0312 物料组 102）', 'GRPTYPE') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_POOL_TGT" ("PoolCode", "ItmsGrpCod", "FromFc", "ToFc", "WorTypes", "Descr", "MatchBy") VALUES ('MFG', 'C', '0000-00', '9999-99', ',10,20,30,40,', '车间类别 C（旧 0312 物料组 103）', 'GRPTYPE') WITH PRIMARY KEY