CREATE COLUMN TABLE "FH100"."@MTC_BRPT1" (
    "Code" NVARCHAR(50) NOT NULL,
    "LineId" INTEGER NOT NULL,
    "Object" NVARCHAR(20),
    "LogInst" INTEGER,
    "U_Model" NVARCHAR(10),
    "U_Type" NVARCHAR(10),
    "U_Status" NVARCHAR(10) DEFAULT Y,
    "U_Notes" NVARCHAR(200),
    "U_Proc" NVARCHAR(100),
    "U_RptCode" NVARCHAR(30),
    "U_RptName" NVARCHAR(50),
    "U_OrderBy" INTEGER DEFAULT 0,
    "U_IsRev" NVARCHAR(1) DEFAULT N,
    PRIMARY KEY ("Code", "LineId")
)