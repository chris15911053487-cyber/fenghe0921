CREATE COLUMN TABLE "FH100"."@MTC_PTPRICE1" (
    "DocEntry" INTEGER NOT NULL,
    "LineId" INTEGER NOT NULL,
    "VisOrder" INTEGER,
    "Object" NVARCHAR(20),
    "LogInst" INTEGER,
    "U_ItemCode" NVARCHAR(50),
    "U_ItemName" NVARCHAR(254),
    "U_Price" DECIMAL(21,6) DEFAULT 0.0,
    "U_LineMemo" NVARCHAR(254),
    PRIMARY KEY ("DocEntry", "LineId")
)