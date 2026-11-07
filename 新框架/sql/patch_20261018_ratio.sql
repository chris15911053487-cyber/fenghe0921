-- 2026-10-18 补丁：物料料工费占比落表（用户 2026-10-18）
--   MTC_CA_R_ITEM 加 16 列 Rt<Open|In|Out|End><Mat|Lab|Mfg|Sub>：期初、入库、出库、期末各自的材料 / 人工 / 制造 / 委外 ÷ 该项四项合计 × 100（%，保留 4 位），
--   四项合计为 0 时为空；P50 定稿时写入。物料组小计、合计的占比仍由执行台按汇总金额现算。
-- 已部署的库依次执行：本文件（加列，并给已有运行回填），14_p50_p60_p65.sql（P50），18_meta_comments.sql，然后 CALL "MTC_CA_P_META_SYNC"()。
-- 执行台 tools/console/actions.json 的 invSum 读这些列，要在本文件执行之后再换新版执行台。
ALTER TABLE "MTC_CA_R_ITEM" ADD ("RtOpenMat" DECIMAL(19,4), "RtOpenLab" DECIMAL(19,4), "RtOpenMfg" DECIMAL(19,4), "RtOpenSub" DECIMAL(19,4), "RtInMat" DECIMAL(19,4), "RtInLab" DECIMAL(19,4), "RtInMfg" DECIMAL(19,4), "RtInSub" DECIMAL(19,4), "RtOutMat" DECIMAL(19,4), "RtOutLab" DECIMAL(19,4), "RtOutMfg" DECIMAL(19,4), "RtOutSub" DECIMAL(19,4), "RtEndMat" DECIMAL(19,4), "RtEndLab" DECIMAL(19,4), "RtEndMfg" DECIMAL(19,4), "RtEndSub" DECIMAL(19,4))
@@
-- 回填已有运行（与 P50 同一公式）
UPDATE "MTC_CA_R_ITEM"
   SET
       "RtOpenMat" = CASE WHEN ABS("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") > 0.005 THEN ROUND("OpenMat" / ("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") * 100, 4) END,
       "RtOpenLab" = CASE WHEN ABS("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") > 0.005 THEN ROUND("OpenLab" / ("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") * 100, 4) END,
       "RtOpenMfg" = CASE WHEN ABS("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") > 0.005 THEN ROUND("OpenMfg" / ("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") * 100, 4) END,
       "RtOpenSub" = CASE WHEN ABS("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") > 0.005 THEN ROUND("OpenSub" / ("OpenMat" + "OpenMfg" + "OpenLab" + "OpenSub") * 100, 4) END,
       "RtInMat" = CASE WHEN ABS("InMat" + "InMfg" + "InLab" + "InSub") > 0.005 THEN ROUND("InMat" / ("InMat" + "InMfg" + "InLab" + "InSub") * 100, 4) END,
       "RtInLab" = CASE WHEN ABS("InMat" + "InMfg" + "InLab" + "InSub") > 0.005 THEN ROUND("InLab" / ("InMat" + "InMfg" + "InLab" + "InSub") * 100, 4) END,
       "RtInMfg" = CASE WHEN ABS("InMat" + "InMfg" + "InLab" + "InSub") > 0.005 THEN ROUND("InMfg" / ("InMat" + "InMfg" + "InLab" + "InSub") * 100, 4) END,
       "RtInSub" = CASE WHEN ABS("InMat" + "InMfg" + "InLab" + "InSub") > 0.005 THEN ROUND("InSub" / ("InMat" + "InMfg" + "InLab" + "InSub") * 100, 4) END,
       "RtOutMat" = CASE WHEN ABS("OutMat" + "OutMfg" + "OutLab" + "OutSub") > 0.005 THEN ROUND("OutMat" / ("OutMat" + "OutMfg" + "OutLab" + "OutSub") * 100, 4) END,
       "RtOutLab" = CASE WHEN ABS("OutMat" + "OutMfg" + "OutLab" + "OutSub") > 0.005 THEN ROUND("OutLab" / ("OutMat" + "OutMfg" + "OutLab" + "OutSub") * 100, 4) END,
       "RtOutMfg" = CASE WHEN ABS("OutMat" + "OutMfg" + "OutLab" + "OutSub") > 0.005 THEN ROUND("OutMfg" / ("OutMat" + "OutMfg" + "OutLab" + "OutSub") * 100, 4) END,
       "RtOutSub" = CASE WHEN ABS("OutMat" + "OutMfg" + "OutLab" + "OutSub") > 0.005 THEN ROUND("OutSub" / ("OutMat" + "OutMfg" + "OutLab" + "OutSub") * 100, 4) END,
       "RtEndMat" = CASE WHEN ABS("EndMat" + "EndMfg" + "EndLab" + "EndSub") > 0.005 THEN ROUND("EndMat" / ("EndMat" + "EndMfg" + "EndLab" + "EndSub") * 100, 4) END,
       "RtEndLab" = CASE WHEN ABS("EndMat" + "EndMfg" + "EndLab" + "EndSub") > 0.005 THEN ROUND("EndLab" / ("EndMat" + "EndMfg" + "EndLab" + "EndSub") * 100, 4) END,
       "RtEndMfg" = CASE WHEN ABS("EndMat" + "EndMfg" + "EndLab" + "EndSub") > 0.005 THEN ROUND("EndMfg" / ("EndMat" + "EndMfg" + "EndLab" + "EndSub") * 100, 4) END,
       "RtEndSub" = CASE WHEN ABS("EndMat" + "EndMfg" + "EndLab" + "EndSub") > 0.005 THEN ROUND("EndSub" / ("EndMat" + "EndMfg" + "EndLab" + "EndSub") * 100, 4) END
@@
