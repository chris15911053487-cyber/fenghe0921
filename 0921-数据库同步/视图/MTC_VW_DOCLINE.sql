CREATE VIEW "FH100"."MTC_VW_DOCLINE" AS SELECT
	 L0."LogEntry",
	 T0."DocDate",
	 L0."DocType" "ObjType",
	 L0."DocEntry",
	 "DocLine" "LineNum",
	 L0."ItemCode",
	 L0."ItemName",
	 T0."LocCode",
	 L1."MdAbsEntry" "BatchEntry" ,
	 TN."DistNumber" "BatchNumber" ,
	 IFNULL(TL."Quantity",
	 L1."Quantity") "Quantity" ,
	 WH."WhsCode",
	 WH."WhsName" ,
	 BN."AbsEntry" "BinEntry",
	 BN."BinCode" 
FROM OIVL T0 JOIN OITL L0 ON T0."TransType"=L0."DocType" 
AND T0."CreatedBy"=L0."DocEntry" 
AND T0."DocLineNum"=L0."DocLine" 
AND T0."LocCode"=L0."LocCode" JOIN ITL1 L1 ON L1."LogEntry" = L0."LogEntry" JOIN OWHS WH ON WH."WhsCode" = T0."LocCode" 
LEFT JOIN OBTL TL ON TL."ITLEntry" = L1."LogEntry" 
AND L1."MdAbsEntry" = TL."SnBMDAbs" --库位交易日志
JOIN OBTN TN ON TN."AbsEntry" = IFNULL(TL."SnBMDAbs",
	 L1."MdAbsEntry") --批次表
 
LEFT JOIN OBIN BN ON BN."AbsEntry" = TL."BinAbs" ORDER BY L0."DocType" ,
	 L0."DocEntry",
	 L0."DocLine"