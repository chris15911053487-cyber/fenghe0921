CREATE COLUMN TABLE "FH100"."@MTC_COST_TIME1" (
    "DocEntry" INTEGER NOT NULL,
    "LineId" INTEGER NOT NULL,
    "VisOrder" INTEGER,
    "Object" NVARCHAR(20),
    "LogInst" INTEGER,
    "U_ItemCode" NVARCHAR(30),
    "U_ItemName" NVARCHAR(254),
    "U_Time" DECIMAL(21,6) DEFAULT 0.0,
    "U_Memo" NVARCHAR(254),
    PRIMARY KEY ("DocEntry", "LineId")
)