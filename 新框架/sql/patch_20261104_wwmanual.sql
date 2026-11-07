-- =====================================================================
-- 2026-11-04 历史委外差异：标记已手工转出（用户 2026-11-04，设计稿 8.9）
-- 在 patch_20261104_wwhist.sql 之后执行，再执行 07、08、16、19_jv、19_ww_hist、21_reports、18_meta_comments，CALL "MTC_CA_P_META_SYNC"()。
-- 未编译。改前备份 _backup/*_20261104_before_wwmanual.*
-- =====================================================================
ALTER TABLE "MTC_CA_WW_HIST" ADD ("Manual" NVARCHAR(1) DEFAULT 'N' NOT NULL)
@@
