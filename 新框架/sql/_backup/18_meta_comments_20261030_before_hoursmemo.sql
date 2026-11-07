-- 由 新框架/tools/build_meta_comments.py 从建表语句的行尾注释生成，不要手改；共 378 条。
-- 部署后执行 CALL "MTC_CA_P_META_SYNC"() 同步到数据字典（部署包最后会自动执行）。
COMMENT ON COLUMN "MTC_CA_RUN"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."Scenario" IS '正式运行为空串'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."Initiator" IS 'USER / AI'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."Status" IS 'RUNNING / OK / FAIL / BLOCKED / NOCONV'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."Params" IS '本次运行读到的参数快照（JSON）'
@@
COMMENT ON COLUMN "MTC_CA_RUN_STEP"."StepCode" IS 'P00 / P10 / P20 ...'
@@
COMMENT ON COLUMN "MTC_CA_RUN_STEP"."Status" IS 'RUNNING / OK / WARN / FAIL'
@@
COMMENT ON COLUMN "MTC_CA_RUN_ITER"."MaxPriceDelta" IS '本轮物料单价最大变化'
@@
COMMENT ON COLUMN "MTC_CA_RUN_ITER"."PoolDelta" IS '费用池合计变化'
@@
COMMENT ON COLUMN "MTC_CA_RUN_ITER"."CloseDifDelta" IS '关单差异合计变化'
@@
COMMENT ON COLUMN "MTC_CA_RUN_ITER"."UnconvItems" IS '未达收敛标准的物料数'
@@
COMMENT ON COLUMN "MTC_CA_RUN_KPI"."KpiType" IS 'ITEM_PRICE / ITEM_QM_AMT / ORDER_COST / POOL / WIP ...'
@@
COMMENT ON COLUMN "MTC_CA_RUN_KPI"."KeyCode" IS '物料、订单键等；合计类为空串'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD"."Status" IS 'CALC 已计算 / POSTED 已生成凭单'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD"."CalcRunId" IS '最近一次成功的正式运行'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD"."PostRunId" IS '生成凭单所用的正式运行（POSTED 时有值；下期期初取它）'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD"."PostUser" IS '生成凭单的操作人'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD"."PostTime" IS '生成凭单的时间'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD"."UpdUser" IS '最后一次改状态的操作人'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD"."UpdTime" IS '最后一次改状态的时间'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD_LOG"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD_LOG"."LogTime" IS '改状态的时间'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD_LOG"."FromStatus" IS '原状态 OPEN / CALC / POSTED'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD_LOG"."ToStatus" IS '新状态'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD_LOG"."RunId" IS '相关运行'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD_LOG"."UserCode" IS '操作人'
@@
COMMENT ON COLUMN "MTC_CA_PERIOD_LOG"."Msg" IS '说明'
@@
COMMENT ON COLUMN "MTC_CA_JV"."JvId" IS '记录号'
@@
COMMENT ON COLUMN "MTC_CA_JV"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_JV"."RunId" IS '生成凭单所用的正式运行'
@@
COMMENT ON COLUMN "MTC_CA_JV"."TransCode" IS '凭证代码（OTRC，一种代码一张凭单）'
@@
COMMENT ON COLUMN "MTC_CA_JV"."BatchNum" IS 'B1 日记账凭单批号（OBTF.BatchNum），失败时为空'
@@
COMMENT ON COLUMN "MTC_CA_JV"."Status" IS 'CREATED 已生成 / FAIL 失败 / DELETED 已撤销'
@@
COMMENT ON COLUMN "MTC_CA_JV"."Debit" IS '借方合计'
@@
COMMENT ON COLUMN "MTC_CA_JV"."Credit" IS '贷方合计'
@@
COMMENT ON COLUMN "MTC_CA_JV"."LineCnt" IS '分录行数'
@@
COMMENT ON COLUMN "MTC_CA_JV"."CreateUser" IS '生成人（B1 账号，凭单在 B1 里的创建人）'
@@
COMMENT ON COLUMN "MTC_CA_JV"."CreateTime" IS '生成时间'
@@
COMMENT ON COLUMN "MTC_CA_JV"."DelUser" IS '撤销人'
@@
COMMENT ON COLUMN "MTC_CA_JV"."DelTime" IS '撤销时间'
@@
COMMENT ON COLUMN "MTC_CA_JV"."Msg" IS '说明或 Service Layer 报错'
@@
COMMENT ON COLUMN "MTC_CA_CHECK_ACK"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_CHECK_ACK"."CheckId" IS '校验编号（MTC_CA_C_CHECK，Stage = POST、结果 FAIL）'
@@
COMMENT ON COLUMN "MTC_CA_CHECK_ACK"."UserCode" IS '确认人（B1 账号）'
@@
COMMENT ON COLUMN "MTC_CA_CHECK_ACK"."AckTime" IS '确认时间'
@@
COMMENT ON COLUMN "MTC_CA_CHECK_ACK"."Reason" IS '确认理由'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM"."DataType" IS 'DEC / INT / STR / LIST（逗号列表，存成 ,A,B,）'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_DEF"."ParamCode" IS '参数代码 = B1 @MTC_CA_PARAM.Code（第二段起 代码@起始账期）'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_DEF"."Target" IS '同步到哪：PARAM = MTC_CA_C_PARAM，ACCT = MTC_CA_C_ACCT（Usage = 参数代码）'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_DEF"."Category" IS '分类：费用归集 / 计算控制 / 尾差与校验 / 凭证与对账 / 业务口径'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_DEF"."SortNo" IS '显示顺序'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_DEF"."CnName" IS '中文名（B1 Name）'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_DEF"."DataType" IS 'DEC 数字 / INT 整数 / STR 文字 / LIST 逗号列表 / FC 账期 YYYY-MM / DATE 日期 YYYY-MM-DD'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_DEF"."Choices" IS '只能取这些值（逗号分隔），空 = 不限'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_DEF"."Hint" IS '填法、可选值、单位（B1 U_Hint）'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_B1"."Code" IS '@MTC_CA_PARAM.Code'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_B1"."FromFc" IS 'U_FromFc（原样，空 = 不限）'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_B1"."ToFc" IS 'U_ToFc'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_B1"."Value" IS 'U_Value（原样）'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_B1"."Locked" IS 'U_Locked：Y 锁定；B1 没有这个字段时都是 N'
@@
COMMENT ON COLUMN "MTC_CA_C_PARAM_B1"."SnapSrc" IS 'SYNC = P05 整表刷新，TN = B1 保存时'
@@
COMMENT ON COLUMN "MTC_CA_C_RULE"."Scene" IS '重构场景清单编号 S1…/R1…'
@@
COMMENT ON COLUMN "MTC_CA_C_RULE"."Basis" IS '用户确认 / 读代码 / 建议'
@@
COMMENT ON COLUMN "MTC_CA_C_CHECK"."Stage" IS 'PRE / POST / CMP'
@@
COMMENT ON COLUMN "MTC_CA_C_CHECK"."ProcName" IS '执行过程；空 = 尚未实现'
@@
COMMENT ON COLUMN "MTC_CA_C_CHECK"."TroublePath" IS '不通过时怎么查'
@@
COMMENT ON COLUMN "MTC_CA_C_SCENARIO_OVR"."OvrType" IS 'ITEM_PRICE_PCT / POOL_PCT / HOURS_PCT ...'
@@
COMMENT ON COLUMN "MTC_CA_C_TOOL"."ParamSchema" IS 'JSON Schema'
@@
COMMENT ON COLUMN "MTC_CA_C_TOOL"."ModelOutput" IS '返回给模型的内容（A 档只给状态）'
@@
COMMENT ON COLUMN "MTC_CA_M_TABLE"."Layer" IS 'RUN / C / M / S / R'
@@
COMMENT ON COLUMN "MTC_CA_M_TABLE"."Grain" IS '一行代表什么'
@@
COMMENT ON COLUMN "MTC_CA_M_TABLE"."InDb" IS '库中是否还存在（P_META_SYNC 维护）'
@@
COMMENT ON COLUMN "MTC_CA_M_TABLE"."Source" IS '数据从哪些 B1 表 / 字段来（快照表）'
@@
COMMENT ON COLUMN "MTC_CA_M_COLUMN"."SignRule" IS '正负号约定'
@@
COMMENT ON COLUMN "MTC_CA_M_COLUMN"."Source" IS '取值来源'
@@
COMMENT ON COLUMN "MTC_CA_C_POOL"."IsDefault" IS '成本中心没有配置时进默认池；只能有一个'
@@
COMMENT ON COLUMN "MTC_CA_C_POOL_SRC"."OcrCode" IS '成本中心（OPRC.PrcCode）'
@@
COMMENT ON COLUMN "MTC_CA_C_POOL_TGT"."ItmsGrpCod" IS '匹配值：MatchBy=GRP 时是产品物料组 OITM.ItmsGrpCod，GRPTYPE 时是 OITB.U_ItemGrpType'
@@
COMMENT ON COLUMN "MTC_CA_C_POOL_TGT"."WorTypes" IS '可分摊的订单类型，前后带逗号'
@@
COMMENT ON COLUMN "MTC_CA_C_POOL_TGT"."MatchBy" IS 'GRP 按物料组 / GRPTYPE 按 U_ItemGrpType（Q17，与 PP05 凭证车间一致）'
@@
COMMENT ON COLUMN "MTC_CA_S_ITEM"."GrpType" IS 'OITB.U_ItemGrpType（车间类别，费用池范围和 PP05 车间用，Q17）'
@@
COMMENT ON COLUMN "MTC_CA_S_ITEM"."CalType" IS 'OITM.U_ItemProp'
@@
COMMENT ON COLUMN "MTC_CA_S_ITEM"."LevelSrc" IS 'NOBOM / BOM / OVR'
@@
COMMENT ON COLUMN "MTC_CA_S_ITEM"."LevelNote" IS '-1 的原因'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."LineId" IS '运行内序号'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."Src" IS 'OIVL / OMRV'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."SrcKey" IS 'OIVL.TransSeq；OMRV 为 DocEntry-LineId'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."Canceled" IS 'N 正常 / Y 被取消的原单 / C 取消单'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."B1Amt" IS 'OIVL.SumStock（B1 移动平均下的金额，仅供对照）'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."SrcAmt" IS '有固定来源金额的行：采购收货 / 退货、发票差异、重估；其余为空，由计算定价'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."TransCode" IS '@MTC_COST_IOTYPE.Code；空 = 识别不了（PRE-05）'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."Dir" IS '@MTC_COST_IOTYPE.U_IOType：I / O'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."BusiType" IS '59/60 的业务类型 @U_CIOTRN.Code'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."BusiClass" IS '@U_CIOTRN.U_TransType：B01 订单产出 / B03 订单投入 / K01 / K02'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."BaseType" IS 'MTC_VIEW_Document 改写后的来源（退货 → 原交货；取消单 → 原单）'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."OrderType" IS '202 / MTC_OWOR（59/60 订单领料、入库）'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."OrderLine" IS '订单行；完工入库为空'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."PairKey" IS '形态转换配对键（204/205）'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."SharedExp" IS 'Y = 记 5101 的其他出入库 / 盘点，金额进费用池（公摊材料）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER"."OrderType" IS '202 / MTC_OWOR'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER"."B1Status" IS '当前状态（P/R/L/C）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER"."StatusAtEnd" IS 'OPEN / CLOSED（截至期末，设计稿 Q4）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER"."InScope" IS 'N = 期初前已关闭或已取消，仅因本期有单据引用而列入'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER"."RecvQty" IS '本期完工入库数（S_LINE 中 B01、订单行为空）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER"."PrevRecvQty" IS '截至上期累计入库数（来自期初）'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."Src" IS 'JDT / MRV / PROWW'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."SrcKey" IS 'TransId-Line_ID / DocEntry-LineId'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."SrcTrans" IS '凭证代码 OJDT.TransCode，或重估单类型'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."SrcObj" IS '凭证的来源单据类型 OJDT.TransType（排查重复计入用）'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."SrcDoc" IS '凭证的来源单据 OJDT.CreatedBy'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."Elem" IS 'MFG 制造 / LAB 人工'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."Amount" IS '正数 = 费用增加'
@@
COMMENT ON COLUMN "MTC_CA_S_SUBFEE"."Src" IS 'PDN 加工费收货 / RPD 加工费退货 / PROWW 重估'
@@
COMMENT ON COLUMN "MTC_CA_S_SUBFEE"."ItemCode" IS '加工费物料'
@@
COMMENT ON COLUMN "MTC_CA_S_SUBFEE"."Amount" IS '正数 = 加工费增加'
@@
COMMENT ON COLUMN "MTC_CA_S_SUBFEE"."RcptEntry" IS '关联的生产收货 OIGN.DocEntry'
@@
COMMENT ON COLUMN "MTC_CA_S_SUBFEE"."OrderType" IS '空 = 找不到订单（PRE-12）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."BaseObj" IS '暂估行：20 收货 / 21 不基于收货的退货'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."BaseSign" IS '收货 1 / 退货 -1'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."UnitPrice" IS '暂估单价：U_InitPrice ≠ 0 → U_InitPrice；U_IsPrice=''Y'' → Price；否则 LineTotal ÷ 数量'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."FullAmt" IS '整行暂估金额（正数）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."AccrType" IS 'MAT 材料（PUR1 / PUR2）/ SUBFEE 委外加工费（PUR4 / PUR3）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."MoveType" IS 'ACCR 暂估行本身 / RET 基于暂估行的退货、换货 / INV 基于暂估行的发票、贷项'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."IsCancel" IS 'Y = 取消单（金额、数量取原单的相反数，Q26）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."ObjType" IS '产生这笔变动的单据'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."Qty" IS '对暂估行未清数量的影响（按暂估行方向，正 = 增加未清）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."AccrAmt" IS '对 220202 贷方余额的影响（正 = 增加暂估）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."DocAmt" IS 'INV：发票行金额（发票为正、贷项为负，取消单反向）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."ProdItem" IS '委外加工费发票行 U_ItemCode（发票差异计入的产品）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."AmtRule" IS 'ROUND 数量 × 暂估单价 / LAST 最后一次清余数（Q27）/ FULL 整行 / CANCEL 取消'
@@
COMMENT ON COLUMN "MTC_CA_S_HOURS"."Hours" IS '单位工时（多个值时取最大，同时由 PRE-13 报出）'
@@
COMMENT ON COLUMN "MTC_CA_S_OPEN"."Src" IS 'BOOT 期初承接 / PREV 上期新框架结果'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_OPEN"."ItemCode" IS '材料；''#SUBFEE'' 行 = 未结转的委外加工费'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_OPEN"."CumIssueQty" IS '截至上期累计领料（正数）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_OPEN"."CumCarriedMat" IS '截至上期累计已结转'
@@
COMMENT ON COLUMN "MTC_CA_R_CHECK"."Result" IS 'PASS / FAIL（阻断）/ WARN / SKIP'
@@
COMMENT ON COLUMN "MTC_CA_R_CHECK_DTL"."KeyCode" IS '单据 / 物料 / 订单键，可回查 B1'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_ORDER"."CumRecvQty" IS '旧 0321_OWOR 截至该期 IgnQty 合计'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_ORDER"."ZcpWip" IS '旧 0322_OWOR_ZCP."在产品新"'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_ORDER"."Zcp1Wip" IS '旧 0322_OWOR_ZCP1.Amount 合计'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_ORDER_MAT"."CumIssueQty" IS '旧 0321_OWOR1 截至该期合计，取反为正数'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_ORDER_MAT"."WipQty" IS '旧 0322_OWOR_ZCP1.Quantity / Amount'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_ORDER_MAT"."CumCarriedAmt" IS '= CumIssueAmt − WipAmt'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_RATIO"."FcCode" IS '承接账期'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_RATIO"."RatioFc" IS '取比例的旧框架账期（截至承接账期最近一个有完工的账期）'
@@
COMMENT ON COLUMN "MTC_CA_R_LINE"."LineId" IS '= S_LINE.LineId'
@@
COMMENT ON COLUMN "MTC_CA_R_LINE"."Cat" IS '定价类别，见 MTC_CA_P30_INIT'
@@
COMMENT ON COLUMN "MTC_CA_R_LINE"."InVal" IS 'Y = 计入物料加权单价的入库'
@@
COMMENT ON COLUMN "MTC_CA_R_LINE"."PoolCode" IS '公摊材料行归入的费用池'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."iLevel" IS '计算用层级（-1 的物料放在最高层之后）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."PMat" IS '当前单价（四项）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."PMfg" IS '当前单价（四项）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."LastPMat" IS '上一轮单价'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."LastPMfg" IS '上一轮单价'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."PriceSrc" IS 'WAVG 本期加权 / QCPRICE 维护价兜底 / OPEN 期初单价 / ZERO 无价'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."OutQty" IS '出库为负'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."Flags" IS '负库存 / 兜底价 / 无价 / 尾差无处挤'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."TailAmt" IS '零库存尾差结转（TAIL-01，Q32）：已计入 Out 四项，凭证 JZ04；负数 = 转出'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtOpenMat" IS '期初料工费占比·材料（%）= 期初材料 ÷ 期初四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtOpenLab" IS '期初料工费占比·人工（%）= 期初人工 ÷ 期初四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtOpenMfg" IS '期初料工费占比·制造费用（%）= 期初制造费用 ÷ 期初四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtOpenSub" IS '期初料工费占比·委外加工费（%）= 期初委外加工费 ÷ 期初四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtInMat" IS '入库料工费占比·材料（%）= 入库材料 ÷ 入库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtInLab" IS '入库料工费占比·人工（%）= 入库人工 ÷ 入库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtInMfg" IS '入库料工费占比·制造费用（%）= 入库制造费用 ÷ 入库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtInSub" IS '入库料工费占比·委外加工费（%）= 入库委外加工费 ÷ 入库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtOutMat" IS '出库料工费占比·材料（%）= 出库材料 ÷ 出库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtOutLab" IS '出库料工费占比·人工（%）= 出库人工 ÷ 出库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtOutMfg" IS '出库料工费占比·制造费用（%）= 出库制造费用 ÷ 出库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtOutSub" IS '出库料工费占比·委外加工费（%）= 出库委外加工费 ÷ 出库四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtEndMat" IS '期末料工费占比·材料（%）= 期末材料 ÷ 期末四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtEndLab" IS '期末料工费占比·人工（%）= 期末人工 ÷ 期末四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtEndMfg" IS '期末料工费占比·制造费用（%）= 期末制造费用 ÷ 期末四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RtEndSub" IS '期末料工费占比·委外加工费（%）= 期末委外加工费 ÷ 期末四项合计 × 100；四项合计为 0 时为空（P50，用户 2026-10-18）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER"."Ratio" IS 'min(累计入库 ÷ 计划, 1)；本期无入库为空'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER"."ClosedInFc" IS 'Y = 按关单处理：本期关闭，或截至期初已关闭、本期仍有单据挂上来（Q35）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER"."CostMat" IS '本期完工成本四项'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER"."CostMfg" IS '本期完工成本四项'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER"."WipAmt" IS '期末在产品（四项合计）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER"."CloseDifAmt" IS '本期关单差异（四项合计，进 CLOSE_DIF_POOL）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."ItemCode" IS '材料；''#SUBFEE'' = 委外加工费'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."IssQty" IS '本期领料（正数；生产退料为负）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."CarMat" IS '本期结转'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."CarMfg" IS '本期结转'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."WipMat" IS '期末在产品'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."WipMfg" IS '期末在产品'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."ClsMat" IS '本期关单差异'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."ClsMfg" IS '本期关单差异'
@@
COMMENT ON COLUMN "MTC_CA_R_POOL"."Elem" IS 'MFG / LAB'
@@
COMMENT ON COLUMN "MTC_CA_R_POOL"."Src" IS 'JDT / MRV / PROWW / SHARED 公摊材料 / CLOSEDIF 关单差异'
@@
COMMENT ON COLUMN "MTC_CA_R_ALLOC"."Weight" IS '单位工时 × 本期入库数'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."LineId" IS '取价的行'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."PairType" IS 'TRF 形态转换 / SRT 销售退货 / CNL 取消单'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."SrcLineId" IS '本次运行中的来源行'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."SrcFc" IS '来源在以前账期时的账期'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."SrcTable" IS 'MTC_CA_R_LINE / MTC_COST_0302_INVNTDETAIL1'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."UMat" IS '来源单位成本'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."UMfg" IS '来源单位成本'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."ULab" IS '来源单位成本'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."USub" IS '来源单位成本'
@@
COMMENT ON COLUMN "MTC_CA_R_CMP"."Kind" IS 'ITEM_END 物料期末金额 / ITEM_PRICE 单价 / ORDER_COST 订单完工成本 / WIP 在产品'
@@
COMMENT ON COLUMN "MTC_CA_R_CMP"."Reason" IS 'OLD_BUG 旧缺陷 / RULE 口径变化 / UNEXPLAINED 未解释'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."FirstSeen" IS 'Y = 首次出现：以前各期的新框架结果、期初承接、旧 0301、本期期初都没有这个物料'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."LastFc" IS '以前最近一次出现的账期'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."NeedTrans" IS '本期需要按单价计价的交易类型'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."NeedQty" IS '这些行的数量绝对值合计'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."SuggPrice" IS '建议价（只供参考，不写 B1）'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."SuggSrc" IS 'NEW 新框架期末单价 / OLD 旧 0301 单价 / BOOT 期初承接 / LASTPUR 物料主数据最近采购价'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."Reason" IS '为什么要维护期初成本价（中文一句话），生成 B1 期初单价维护单时写进行备注'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."NeedDocs" IS '触发的单据：按交易类型列单号 Num（每类最多 10 张），完整的见 MTC_CA_R_QCP_LINE'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_LINE"."LineId" IS '快照单据行号（MTC_CA_S_LINE.LineId）'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_LINE"."Qty" IS '数量（正 = 入，负 = 出）'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."ItemCode" IS '产品（订单主件）'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."Pools" IS '应分摊的费用池（逗号分隔）'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."OrderCnt" IS '本期有入库、应分摊的订单数'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."RecvQty" IS '这些订单本期入库数量合计'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."CurHours" IS '本期工时单里的单位工时：空 = 没有录，0 = 录了 0'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."RefHours" IS '参考工时：以前最近一个账期工时单里不为 0 的单位工时（只供参考，不写 B1）'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."RefFc" IS '参考工时的账期'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."TransCode" IS 'OTRC.TrnsCode'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."AcctCode" IS '空 = 取不到科目（POST-08 报出）'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."Amount" IS '正 = 借方，负 = 贷方'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."SrcType" IS 'LINE 单据行（R_LINE.LineId）/ ORDER 订单 / DOC B1 单据行 / GL 总账 / OMRV 重估行'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."VendorCode" IS '220202 应付暂估行的供应商（写入 JDT1.U_VendorCode，PUR1–PUR5）'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT"."VendorCode" IS '供应商（JDT1.U_VendorCode）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT"."ObjType" IS '15 交货 / 16 不基于交货的销售退货'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT"."CustType" IS '@MTC_SALORDTYPE.U_CustType'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT"."InvQty" IS '截至期末已开票（贷项）数量'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT"."RetQty" IS '截至期末已退货数量（基于交货的退货）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT"."OpenQty" IS '带符号：交货为正、独立退货为负'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT_BEG"."ObjType" IS '15 交货 / 16 不基于交货的销售退货'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT_BEG"."InvQty" IS '截至上期末已开票（贷项）数量'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT_BEG"."RetQty" IS '截至上期末已退货数量'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT_BEG"."OpenQty" IS '带符号：交货为正、独立退货为负'
@@
COMMENT ON COLUMN "MTC_CA_R_AP_ACCR"."ObjType" IS '20 收货 / 21 不基于收货的退货'
@@
COMMENT ON COLUMN "MTC_CA_R_AP_ACCR"."AccrType" IS 'MAT 材料 / SUBFEE 委外费用'
@@
COMMENT ON COLUMN "MTC_CA_R_AP_ACCR"."OpenQty" IS '带符号'
@@
COMMENT ON COLUMN "MTC_CA_R_AP_ACCR"."UnitPrice" IS '暂估单价'
@@
COMMENT ON COLUMN "MTC_CA_R_DNCOST"."ObjType" IS '15 交货 / 16 销售退货'
@@
COMMENT ON COLUMN "MTC_CA_R_DNCOST"."UnitCost" IS '空 = 找不到成本（POST-12）'
@@
COMMENT ON COLUMN "MTC_CA_R_DNCOST"."CostSrc" IS 'U_InitPrice / 本期 / 新框架 YYYY-MM / 旧0302'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."SrcObj" IS '被消耗的行：15 交货 / 16 不基于交货的销售退货'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."K" IS 'INV 应收发票 / RIN 应收贷项 / RET 基于交货的退货 / ADJ 全部消耗完的尾差'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."DocEntry" IS '消耗单据（含取消单）；ADJ 为原行'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."DocDate" IS 'ADJ 为期末日'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."CustType" IS '消耗单据的客户类型；ADJ 取原行的'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."IsSample" IS '原行或消耗单据是样品销售：不做 DN03'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."Qty" IS '与原行 DocQty 同号；取消单反号'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."UnitCost" IS 'INV / RIN 取原行单位成本，RET 取退货行自己的'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."Amount" IS 'ROUND(Qty × UnitCost, 2)；ADJ = 行金额 − 已消耗金额（本期新出现的部分）'
@@
COMMENT ON COLUMN "MTC_CA_C_OCR_MAP"."MapType" IS 'ITEMGRPTYPE：产品物料组的 OITB.U_ItemGrpType → 车间成本中心'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_RUN"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_RUN_STEP"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_RUN_ITER"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_RUN_KPI"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_C_SCENARIO"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_C_SCENARIO_OVR"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_ITEM"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_ITEM"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_ITEM"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_ITEM"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_LINE"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_LINE"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_LINE"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_LINE"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_LINE"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_EXP"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_S_SUBFEE"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_SUBFEE"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_SUBFEE"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_SUBFEE"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_AP_MOVE"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_S_HOURS"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_HOURS"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_HOURS"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_HOURS"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_S_QCPRICE"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_QCPRICE"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_QCPRICE"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_QCPRICE"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_S_OPEN"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_OPEN"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_OPEN"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_OPEN"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_OPEN"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_OPEN"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_OPEN"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_S_ORDER_OPEN"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_CHECK"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_CHECK"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_CHECK"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_CHECK"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_CHECK_DTL"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_CHECK_DTL"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_CHECK_DTL"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_CHECK_DTL"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_ITEM"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_ORDER"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_BOOT_ORDER_MAT"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_LINE"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_LINE"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_LINE"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_LINE"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_ITEM"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_ORDER_MAT"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_POOL"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_POOL"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_POOL"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_POOL"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_ALLOC"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_ALLOC"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_ALLOC"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_ALLOC"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_PAIR"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_CMP"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_CMP"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_CMP"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_CMP"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_QCP_NEED"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_HOURS_NEED"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT_SRC"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_JDT"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT_BEG"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT_BEG"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT_BEG"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_OUT_BEG"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_AP_ACCR"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_AP_ACCR"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_AP_ACCR"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_AP_ACCR"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_DNCOST"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_DNCOST"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_DNCOST"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_DNCOST"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."FcCode" IS '账期（OFPR.Code）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."RunType" IS 'F 正式 / S 模拟'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."Scenario" IS '模拟场景（正式运行为空串）'
@@
COMMENT ON COLUMN "MTC_CA_R_GOODS_MOVE"."RunId" IS '运行号（MTC_CA_RUN.RunId）'
