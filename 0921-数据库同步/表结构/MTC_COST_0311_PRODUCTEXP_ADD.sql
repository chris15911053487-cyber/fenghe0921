CREATE COLUMN TABLE "FH100"."MTC_COST_0311_PRODUCTEXP_ADD" (
    "BPLId" INTEGER,
    "FcCode" NVARCHAR(10),
    "ExpType" NVARCHAR(50),
    "ExpCode" NVARCHAR(50),
    "ExpName" NVARCHAR(50),
    "AcctCode" NVARCHAR(50),
    "AcctName" NVARCHAR(50),
    "OcrCode" NVARCHAR(50),
    "OcrName" NVARCHAR(100),
    "IsCal" NVARCHAR(10),
    "Amount" DECIMAL(19,2),
    "Memo" NVARCHAR(254),
    "CreateDate" DATE,
    "Creator" NVARCHAR(50),
    "CalAcctCode" NVARCHAR(50)
)