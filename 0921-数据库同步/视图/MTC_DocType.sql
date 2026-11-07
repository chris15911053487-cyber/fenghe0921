CREATE VIEW "FH100"."MTC_DocType" AS ((((((((((((((((((((((((((((((((((((((((((Select
	 'OPQT' ,
	 '采购报价单' ,
	 '540000006' 
																																									FROM DUMMY) UNION ALL (Select
	 'OPOR',
	 '采购订单',
	 '22' 
																																									FROM DUMMY)) UNION ALL (Select
	 'ODPO',
	 '预付款申请',
	 '204' 
																																								FROM DUMMY)) UNION ALL (SELECT
	 'OPDN' ,
	 '采购收货' ,
	 '20' 
																																							FROM DUMMY)) UNION ALL (SELECT
	 'OPRR' ,
	 '采购退货申请' ,
	 '234000032' 
																																						FROM DUMMY)) UNION ALL (SELECT
	 'ORPD' ,
	 '采购退货' ,
	 '21' 
																																					FROM DUMMY)) UNION ALL (SELECT
	 'OPCH' ,
	 '应付发票' ,
	 '18' 
																																				FROM DUMMY)) UNION ALL (SELECT
	 'ORPC' ,
	 '应付贷项' ,
	 '19' 
																																			FROM DUMMY)) UNION ALL (SELECT
	 'OQUT' ,
	 '销售报价单' ,
	 '23' 
																																		FROM DUMMY)) UNION ALL (SELECT
	 'ORDR' ,
	 '销售订单' ,
	 '17' 
																																	FROM DUMMY)) UNION ALL (SELECT
	 'ODPI' ,
	 '预收款申请' ,
	 '203' 
																																FROM DUMMY)) UNION ALL (SELECT
	 'ODLN' ,
	 '销售交货' ,
	 '15' 
																															FROM DUMMY)) UNION ALL (SELECT
	 'ORRR' ,
	 '销售退货申请' ,
	 '234000031' 
																														FROM DUMMY)) UNION ALL (SELECT
	 'ORDN' ,
	 '销售退货' ,
	 '16' 
																													FROM DUMMY)) UNION ALL (SELECT
	 'OINV' ,
	 '应收发票' ,
	 '13' 
																												FROM DUMMY)) UNION ALL (SELECT
	 'ORIN' ,
	 '应收贷项' ,
	 '14' 
																											FROM DUMMY)) UNION ALL (SELECT
	 'OWTR' ,
	 '库存转储' ,
	 '67' 
																										FROM DUMMY)) UNION ALL (SELECT
	 'OIGN' ,
	 '其他收货' ,
	 '59' 
																									FROM DUMMY)) UNION ALL (SELECT
	 'OIGE' ,
	 '其他发货' ,
	 '60' 
																								FROM DUMMY)) UNION ALL (SELECT
	 'OMRV' ,
	 '库存重估' ,
	 '162' 
																							FROM DUMMY)) UNION ALL (SELECT
	 'OIQR' ,
	 '盘点过帐' ,
	 '10000071' 
																						FROM DUMMY)) UNION ALL (SELECT
	 'OBTD' ,
	 '日记帐凭证' ,
	 '29' 
																					FROM DUMMY)) UNION ALL (SELECT
	 'OJDT' ,
	 '日记帐分录' ,
	 '30' 
																				FROM DUMMY)) UNION ALL (SELECT
	 'OACQ' ,
	 '固定资产资本化' ,
	 '1470000049' 
																			FROM DUMMY)) UNION ALL (SELECT
	 'OACD' ,
	 '固定资产资本化贷项' ,
	 '1470000060' 
																		FROM DUMMY)) UNION ALL (SELECT
	 'ODRN' ,
	 '固定资产折旧运行' ,
	 '1470000071' 
																	FROM DUMMY)) UNION ALL (SELECT
	 'OMDP' ,
	 '固定资产手动折旧' ,
	 '1470000075' 
																FROM DUMMY)) UNION ALL (SELECT
	 'OFAR' ,
	 '固定资产重估' ,
	 '1470000085' 
															FROM DUMMY)) UNION ALL (SELECT
	 'OFTR' ,
	 '固定资产转账' ,
	 '1470000090' 
														FROM DUMMY)) UNION ALL (SELECT
	 'ORTI' ,
	 '固定资产报废' ,
	 '1470000094' 
													FROM DUMMY)) UNION ALL (SELECT
	 'OCRD' ,
	 '业务伙伴主数据' ,
	 '2' 
												FROM DUMMY)) UNION ALL (SELECT
	 'OITM' ,
	 '物料主数据' ,
	 '4' 
											FROM DUMMY)) UNION ALL (SELECT
	 'OVPM' ,
	 '付款单' ,
	 '46' 
										FROM DUMMY)) UNION ALL (SELECT
	 'ORCT' ,
	 '收款单' ,
	 '24' 
									FROM DUMMY)) UNION ALL (SELECT
	 'OPDF' ,
	 '业务单据草稿' ,
	 '112' 
								FROM DUMMY)) UNION ALL (SELECT
	 'ODRF' ,
	 '收付款草稿' ,
	 '140' 
							FROM DUMMY)) UNION ALL (SELECT
	 'OWOR' ,
	 '生产订单' ,
	 '202' 
						FROM DUMMY)) UNION ALL (SELECT
	 'MTC_CSOIGE',
	 '领料申请',
	 'MTC_CSOIGE' 
					FROM DUMMY)) UNION ALL (SELECT
	 'MTC_FHTZ',
	 '发货通知单',
	 'MTC_FHTZ' 
				FROM DUMMY)) UNION ALL (SELECT
	 'MTC_JCTZ',
	 '采购到货单',
	 'MTC_JCTZ' 
			FROM DUMMY)) UNION ALL (SELECT
	 'MTC_OMRV',
	 '库存重估单',
	 'MTC_OMRV' 
		FROM DUMMY)) UNION ALL (SELECT
	 'MTC_OWOR',
	 '生产返工单',
	 'MTC_OWOR' 
		FROM DUMMY))