CREATE COLUMN TABLE "FH100"."MTC_COST_0312_PRODUCTEXP_PRC" (
    "ID" BIGINT,
    "BPLId" INTEGER,
    "FcCode" NVARCHAR(10),
    "CostCode" NVARCHAR(30),
    "ExpType" NVARCHAR(50),
    "ExpCode" NVARCHAR(50),
    "ExpName" NVARCHAR(50),
    "ItemCode" NVARCHAR(50),
    "CJCode" NVARCHAR(50),
    "IgnQty" DECIMAL(19,6),
    "Time" DECIMAL(19,6),
    "TimeTotal" DECIMAL(19,6),
    "Prc" DECIMAL(19,6),
    "CreateDate" DATE,
    "Creator" NVARCHAR(50),
    "WorEntry" NVARCHAR(50),
    "ExpAmt" DECIMAL(19,6)
)