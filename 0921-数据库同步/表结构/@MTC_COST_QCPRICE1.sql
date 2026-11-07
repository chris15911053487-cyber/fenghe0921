CREATE COLUMN TABLE "FH100"."@MTC_COST_QCPRICE1" (
    "DocEntry" INTEGER NOT NULL,
    "LineId" INTEGER NOT NULL,
    "VisOrder" INTEGER,
    "Object" NVARCHAR(20),
    "LogInst" INTEGER,
    "U_ItemCode" NVARCHAR(30),
    "U_ItemName" NVARCHAR(254),
    "U_iLevel" INTEGER,
    "U_ItmsGrpCod" NVARCHAR(30),
    "U_ItmsGrpNam" NVARCHAR(30),
    "U_U_KeyItem" NVARCHAR(10),
    "U_Price" DECIMAL(21,6) DEFAULT 0.0,
    "U_LineMemo" NVARCHAR(254),
    "U_IsY" NVARCHAR(10) DEFAULT N,
    PRIMARY KEY ("DocEntry", "LineId")
)