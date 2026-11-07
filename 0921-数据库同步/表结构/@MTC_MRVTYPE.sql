CREATE COLUMN TABLE "FH100"."@MTC_MRVTYPE" (
    "Code" NVARCHAR(50) NOT NULL,
    "Name" NVARCHAR(100) NOT NULL,
    "U_StockCode" NVARCHAR(15),
    "U_StockName" NVARCHAR(50),
    "U_AcctCode" NVARCHAR(15),
    "U_AcctName" NVARCHAR(50),
    PRIMARY KEY ("Code")
)