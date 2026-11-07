-- =====================================================================
-- 新成本框架 第 1 期：配置与规则层、元数据层（设计稿 3.2、3.3）
-- 生效期间：FromFc ≤ 账期 ≤ ToFc（账期 = OFPR."Code"，格式 YYYY-MM）
-- =====================================================================
CREATE COLUMN TABLE "MTC_CA_C_PARAM" (
    "ParamCode"  NVARCHAR(50)   NOT NULL,
    "FromFc"     NVARCHAR(10)   NOT NULL DEFAULT '0000-00',
    "ToFc"       NVARCHAR(10)   NOT NULL DEFAULT '9999-99',
    "Value"      NVARCHAR(200)  NOT NULL,
    "DataType"   NVARCHAR(10)   NOT NULL DEFAULT 'DEC',   -- DEC / INT / STR / LIST（逗号列表，存成 ,A,B,）
    "Descr"      NVARCHAR(500),
    PRIMARY KEY ("ParamCode", "FromFc")
)
@@
COMMENT ON TABLE "MTC_CA_C_PARAM" IS '计算参数：一行 = 一个参数在一段账期内的取值'
@@
CREATE COLUMN TABLE "MTC_CA_C_RULE" (
    "RuleId"   NVARCHAR(20)   NOT NULL,
    "Scene"    NVARCHAR(20),                               -- 重构场景清单编号 S1…/R1…
    "Title"    NVARCHAR(100)  NOT NULL,
    "Descr"    NVARCHAR(2000),
    "Basis"    NVARCHAR(20),                               -- 用户确认 / 读代码 / 建议
    "Active"   NVARCHAR(1)    NOT NULL DEFAULT 'Y',
    "FromFc"   NVARCHAR(10)   NOT NULL DEFAULT '0000-00',
    "ToFc"     NVARCHAR(10)   NOT NULL DEFAULT '9999-99',
    PRIMARY KEY ("RuleId")
)
@@
COMMENT ON TABLE "MTC_CA_C_RULE" IS '规则登记：结果行上的 RuleId 指向这里'
@@
CREATE COLUMN TABLE "MTC_CA_C_ACCT" (
    "Usage"     NVARCHAR(30)   NOT NULL,
    "FromFc"    NVARCHAR(10)   NOT NULL DEFAULT '0000-00',
    "ToFc"      NVARCHAR(10)   NOT NULL DEFAULT '9999-99',
    "AcctCode"  NVARCHAR(15)   NOT NULL,
    "Descr"     NVARCHAR(500),
    PRIMARY KEY ("Usage", "FromFc")
)
@@
COMMENT ON TABLE "MTC_CA_C_ACCT" IS '科目用途 → 科目，替代代码中写死的科目（清单 S15）'
@@
CREATE COLUMN TABLE "MTC_CA_C_LEVEL_OVR" (
    "ItemCode"  NVARCHAR(50)   NOT NULL,
    "FromFc"    NVARCHAR(10)   NOT NULL DEFAULT '0000-00',
    "ToFc"      NVARCHAR(10)   NOT NULL DEFAULT '9999-99',
    "iLevel"    INT            NOT NULL,
    "Reason"    NVARCHAR(500),
    PRIMARY KEY ("ItemCode", "FromFc")
)
@@
COMMENT ON TABLE "MTC_CA_C_LEVEL_OVR" IS '物料层级手工覆盖，替代 MTC_CO_001GetItemLevel 末尾写死的物料（清单 S0）'
@@
CREATE COLUMN TABLE "MTC_CA_C_WHS" (
    "WhsCode"  NVARCHAR(8)    NOT NULL,
    "IsCost"   NVARCHAR(1)    NOT NULL,
    "Reason"   NVARCHAR(500),
    PRIMARY KEY ("WhsCode")
)
@@
COMMENT ON TABLE "MTC_CA_C_WHS" IS '计价仓库例外：默认按 OWHS.U_IsCost=''Y''（设计稿 Q1），这里只登记需要覆盖的仓库及原因'
@@
CREATE COLUMN TABLE "MTC_CA_C_CHECK" (
    "CheckId"      NVARCHAR(20)   NOT NULL,
    "Stage"        NVARCHAR(4)    NOT NULL,                -- PRE / POST / CMP
    "SortNo"       INT            NOT NULL DEFAULT 0,
    "Title"        NVARCHAR(200)  NOT NULL,
    "Purpose"      NVARCHAR(1000),
    "IsBlock"      NVARCHAR(1)    NOT NULL DEFAULT 'N',
    "ProcName"     NVARCHAR(128),                          -- 执行过程；空 = 尚未实现
    "PassRule"     NVARCHAR(500),
    "TroublePath"  NVARCHAR(1000),                         -- 不通过时怎么查
    "Scene"        NVARCHAR(50),
    "Active"       NVARCHAR(1)    NOT NULL DEFAULT 'Y',
    PRIMARY KEY ("CheckId")
)
@@
COMMENT ON TABLE "MTC_CA_C_CHECK" IS '校验登记：计算前（PRE）、计算后（POST）、新旧比对（CMP）'
@@
CREATE COLUMN TABLE "MTC_CA_C_SCENARIO" (
    "Scenario"    NVARCHAR(30)   NOT NULL,
    "Title"       NVARCHAR(100)  NOT NULL,
    "Descr"       NVARCHAR(1000),
    "CreateUser"  NVARCHAR(50),
    "CreateTime"  TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY ("Scenario")
)
@@
COMMENT ON TABLE "MTC_CA_C_SCENARIO" IS '模拟场景，只在 RunType=S 时生效（清单 R4-f）'
@@
CREATE COLUMN TABLE "MTC_CA_C_SCENARIO_OVR" (
    "Scenario"  NVARCHAR(30)   NOT NULL,
    "LineNo"    INT            NOT NULL,
    "OvrType"   NVARCHAR(30)   NOT NULL,                   -- ITEM_PRICE_PCT / POOL_PCT / HOURS_PCT ...
    "KeyCode"   NVARCHAR(100)  NOT NULL DEFAULT '',
    "Value"     DECIMAL(19,6)  NOT NULL,
    "Descr"     NVARCHAR(500),
    PRIMARY KEY ("Scenario", "LineNo")
)
@@
COMMENT ON TABLE "MTC_CA_C_SCENARIO_OVR" IS '模拟场景的假设：一行 = 一项调整'
@@
CREATE COLUMN TABLE "MTC_CA_C_TOOL" (
    "ToolName"     NVARCHAR(50)   NOT NULL,
    "Title"        NVARCHAR(100)  NOT NULL,
    "Descr"        NVARCHAR(1000),
    "ParamSchema"  NCLOB,                                  -- JSON Schema
    "ProcName"     NVARCHAR(128),
    "IsWrite"      NVARCHAR(1)    NOT NULL DEFAULT 'N',
    "NeedConfirm"  NVARCHAR(1)    NOT NULL DEFAULT 'N',
    "ModelOutput"  NVARCHAR(500),                          -- 返回给模型的内容（A 档只给状态）
    "Phase"        INT,
    "Active"       NVARCHAR(1)    NOT NULL DEFAULT 'Y',
    PRIMARY KEY ("ToolName")
)
@@
COMMENT ON TABLE "MTC_CA_C_TOOL" IS 'AI 工具登记：模型只能调用这里登记的工具（清单 R6）'
@@
CREATE COLUMN TABLE "MTC_CA_M_TABLE" (
    "TableName"  NVARCHAR(128)  NOT NULL,
    "CnName"     NVARCHAR(100),
    "Layer"      NVARCHAR(10),                             -- RUN / C / M / S / R
    "Grain"      NVARCHAR(200),                            -- 一行代表什么
    "PKCols"     NVARCHAR(500),
    "Descr"      NVARCHAR(2000),
    "InDb"       NVARCHAR(1)    NOT NULL DEFAULT 'Y',      -- 库中是否还存在（P_META_SYNC 维护）
    "Source"     NVARCHAR(1000),                           -- 数据从哪些 B1 表 / 字段来（快照表）
    PRIMARY KEY ("TableName")
)
@@
COMMENT ON TABLE "MTC_CA_M_TABLE" IS '数据字典：表'
@@
CREATE COLUMN TABLE "MTC_CA_M_COLUMN" (
    "TableName"   NVARCHAR(128)  NOT NULL,
    "ColumnName"  NVARCHAR(128)  NOT NULL,
    "Position"    INT,
    "DataType"    NVARCHAR(50),
    "CnName"      NVARCHAR(100),
    "Descr"       NVARCHAR(2000),
    "Unit"        NVARCHAR(20),
    "SignRule"    NVARCHAR(200),                           -- 正负号约定
    "Source"      NVARCHAR(500),                           -- 取值来源
    "InDb"        NVARCHAR(1)    NOT NULL DEFAULT 'Y',
    PRIMARY KEY ("TableName", "ColumnName")
)
@@
COMMENT ON TABLE "MTC_CA_M_COLUMN" IS '数据字典：字段'
