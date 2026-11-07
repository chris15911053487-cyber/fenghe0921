CREATE COLUMN TABLE "FH100"."@MTC_BRPT" (
    "Code" NVARCHAR(50) NOT NULL,
    "Name" NVARCHAR(100),
    "DocEntry" INTEGER NOT NULL,
    "Canceled" NVARCHAR(1) DEFAULT N,
    "Object" NVARCHAR(20),
    "LogInst" INTEGER,
    "UserSign" INTEGER,
    "Transfered" NVARCHAR(1) DEFAULT N,
    "CreateDate" TIMESTAMP,
    "CreateTime" SMALLINT,
    "UpdateDate" TIMESTAMP,
    "UpdateTime" SMALLINT,
    "DataSource" NVARCHAR(1),
    PRIMARY KEY ("Code")
)