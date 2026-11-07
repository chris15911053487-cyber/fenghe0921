-- 2026-10-27 补丁：代码中写死的业务口径改为参数（MTC_CA_C_PARAM，也可在 B1 @MTC_CA_EXPSET 维护）
--   委外 / 返工 / 试打的订单类型、试打允许的领料业务类型、形态转换 204/205、生产退料 304、样品销售、国内 / 国外客户。
--   默认值与原来写死的值相同，计算结果不变；过程里参数缺失时也按原值兜底。
-- 已部署的库依次执行：本文件，07_snapshot_procs.sql（P20_LINE），08_precheck.sql（P10、F_GOODS_OPEN），
--   09_bootstrap.sql，12_p30_init.sql（P30），16_p70_jdt.sql（P70、P71、F_RECON、P75）。离线改的，还没编译。
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('WW_WORTYPES', '0000-00', '9999-99', ',50,', 'LIST', '委外工单的订单类型（U_OrdType）：在产品记 WW_MAT（140801），完工 WW03、关单 JZ03，不分摊制造费用和人工（PRE-17/19 不查）；改了要同步改费用池分摊范围的订单类型（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('REWORK_WORTYPES', '0000-00', '9999-99', ',30,', 'LIST', '返工单的订单类型：期初承接取旧框架料工费比例时跳过（领料和产出是同一物料）（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('TRIAL_WORTYPES', '0000-00', '9999-99', ',40,', 'LIST', 'PRE-09：试打订单的订单类型（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('TRIAL_ISSUE_BUSITYPES', '0000-00', '9999-99', ',307,305,', 'LIST', 'PRE-09：试打订单允许的领料业务类型（@U_CIOTRN.Code，默认 307 试打领用、305 生产报废）（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CONV_IN_BUSITYPE', '0000-00', '9999-99', '204', 'STR', '形态转换转入的业务类型（@U_CIOTRN.Code，I05）：P20_LINE 按行上 U_BaseType / U_BaseEntry / U_BaseLineGrpNum 配对，不关联订单；PRE-03 查一对一（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CONV_OUT_BUSITYPE', '0000-00', '9999-99', '205', 'STR', '形态转换转出的业务类型（@U_CIOTRN.Code，O05），用法同 CONV_IN_BUSITYPE（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('RETURN_BUSITYPES', '0000-00', '9999-99', ',304,', 'LIST', '生产退料的业务类型：带订单的退料按该订单该材料的平均领料单价（RTN304 / RTN-01）（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('SAMPLE_SALTYPES', '0000-00', '9999-99', ',样品销售,', 'LIST', '样品销售：@MTC_SALORDTYPE.U_BusiType 为这些值的交货 / 退货走 DN02 / DN04（不结转 DN03、不计提 AR03 / AR04）（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CUST_DOM', '0000-00', '9999-99', '国内客户', 'STR', '国内客户的客户类型（@MTC_SALORDTYPE.U_CustType）：DN03 / AR03 记 COGS_DOM，样品 DN02；PRE-27、POST-12 只认 CUST_DOM / CUST_EXP（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
UPSERT "MTC_CA_C_PARAM" ("ParamCode", "FromFc", "ToFc", "Value", "DataType", "Descr") VALUES ('CUST_EXP', '0000-00', '9999-99', '国外客户', 'STR', '国外客户的客户类型（@MTC_SALORDTYPE.U_CustType）：DN03 / AR04 记 COGS_EXP，样品 DN04（销项税按成本 × SAMPLE_EXPORT_FACTOR）（2026-10-27 由代码固定值改为参数）') WITH PRIMARY KEY
@@
