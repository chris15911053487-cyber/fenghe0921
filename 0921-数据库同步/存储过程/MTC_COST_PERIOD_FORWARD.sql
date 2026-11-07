CREATE PROCEDURE "MTC_COST_PERIOD_FORWARD" (
    IN iv_FromFcCode NVARCHAR(50),
    IN iv_ToFcCode   NVARCHAR(50)
)
LANGUAGE SQLSCRIPT
SQL SECURITY INVOKER
AS
BEGIN
	DELETE FROM MTC_COST_STOCK WHERE "FcCode"=:iv_ToFcCode;
    MERGE INTO "MTC_COST_STOCK" T
    USING (
        SELECT 
            :iv_ToFcCode        AS "FcCode",
            "ItemCode",
            "ItemName",
            "iLevel",
            "CloseQty"          AS "OpenQty",
            "CloseMaterial"     AS "OpenMaterial",
            "CloseManExp"       AS "OpenManExp",
            "CloseLabAmount"    AS "OpenLabAmount",
            "CloseWWExp"        AS "OpenWWExp",
            "CloseAmount"       AS "OpenAmount"
        FROM "MTC_COST_STOCK"
        WHERE "FcCode" = :iv_FromFcCode
          AND "Status" = 'C'
          AND "CloseQty" > 0
    ) S
    ON T."FcCode" = S."FcCode" AND T."ItemCode" = S."ItemCode"
    WHEN MATCHED THEN UPDATE SET
        T."OpenQty"         = S."OpenQty",
        T."OpenMaterial"    = S."OpenMaterial",
        T."OpenManExp"      = S."OpenManExp",
        T."OpenLabAmount"   = S."OpenLabAmount",
        T."OpenWWExp"       = S."OpenWWExp",
        T."OpenAmount"      = S."OpenAmount"
    WHEN NOT MATCHED THEN INSERT (
        "FcCode", "ItemCode", "ItemName", "iLevel",
        "OpenQty", "OpenMaterial", "OpenManExp", "OpenLabAmount", "OpenWWExp", "OpenAmount"
    ) VALUES (
        S."FcCode", S."ItemCode", S."ItemName", S."iLevel",
        S."OpenQty", S."OpenMaterial", S."OpenManExp", S."OpenLabAmount", S."OpenWWExp", S."OpenAmount"
    );
END;