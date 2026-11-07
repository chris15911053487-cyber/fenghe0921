CREATE COLUMN TABLE "FH100"."MTC_COST_INVNT_QC" (
    "BPLId" INTEGER,
    "FcCode" NVARCHAR(7),
    "CostCode" NVARCHAR(50),
    "ItemCode" NVARCHAR(100),
    "ItemName" NVARCHAR(254),
    "QC_Qty" DECIMAL(19,6),
    "QC_Price" DECIMAL(19,6),
    "QC_Amount" DECIMAL(19,6),
    "CreateDate" DATE,
    "Creator" NVARCHAR(50)
)