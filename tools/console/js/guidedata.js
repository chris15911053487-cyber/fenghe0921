// 成本执行台 · guidedata.js — “使用手册”页的内容。由 交付文档/tools/build_web.py 从 交付文档/src/*.md 生成，不要手改
"use strict";
const GUIDE = [
{
"id": "00",
"title": "导读",
"subtitle": "成本核算系统由哪几部分组成，各份手册给谁看、什么时候看",
"menu": "导读",
"toc": [
{
"id": "g00-1",
"t": "系统组成",
"lv": 1
},
{
"id": "g00-2",
"t": "手册清单",
"lv": 1
},
{
"id": "g00-3",
"t": "第一次使用",
"lv": 1
},
{
"id": "g00-4",
"t": "版本说明",
"lv": 1
}
],
"html": "<h2 id=\"g00-1\">系统组成</h2>\n<p>成本核算系统在 SAP Business One 之上计算实际成本，由三部分组成：</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>组成</th><th>在哪里</th><th>做什么</th></tr></thead><tbody><tr><td>B1 端的单据和配置</td><td>SAP Business One</td><td>业务单据照常录入；工时、期初价、费用池、计算参数在 B1 中维护</td></tr><tr><td>计算程序</td><td>B1 数据库（HANA）中的存储过程</td><td>按账期取单据快照、检查、计算、写结果、生成凭证底稿</td></tr><tr><td>成本执行台</td><td>浏览器打开的网页</td><td>发起检查和计算，查看结果、校验、对账，生成 B1 日记账凭单，查询成本报表</td></tr></tbody></table></div>\n<p>计算程序只读取 B1 单据，不修改单据。它写入 B1 的只有三类内容，而且都要人工确认：日记账凭单（待过账）、库存重估单，以及期初价和工时维护单据。</p>\n<h2 id=\"g00-2\">手册清单</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>手册</th><th>给谁看</th><th>什么时候看</th></tr></thead><tbody><tr><td><a class=\"gd-ln\" data-doc=\"01\">《成本月结清单》</a></td><td>成本会计、财务主管</td><td>每月结账时逐项勾选</td></tr><tr><td><a class=\"gd-ln\" data-doc=\"02\">《成本月结操作手册》</a></td><td>成本会计、总账会计、财务主管</td><td>第一次结账前通读，以后按需查阅</td></tr><tr><td><a class=\"gd-ln\" data-doc=\"03\">《成本核算规则说明》</a></td><td>成本会计、财务主管、审计</td><td>想知道某个数是怎么算出来的</td></tr><tr><td><a class=\"gd-ln\" data-doc=\"04\">《校验与异常处理手册》</a></td><td>成本会计</td><td>检查或计算后出现阻断、警告时</td></tr><tr><td><a class=\"gd-ln\" data-doc=\"05\">《成本报表使用手册》</a></td><td>财务人员、管理层</td><td>查询和导出成本报表</td></tr><tr><td><a class=\"gd-ln\" data-doc=\"06\">《B1 配置维护手册》</a></td><td>关键用户、成本主管</td><td>费用池、计算参数、权限变化时</td></tr><tr><td><a class=\"gd-ln\" data-doc=\"07\">《部署与运维手册》</a></td><td>系统管理员</td><td>安装、升级、重启、排查故障</td></tr></tbody></table></div>\n<p>左上角的查找框会在全部手册中查找。正文里带下划线的章节号和手册名可以点击跳转。</p>\n<h2 id=\"g00-3\">第一次使用</h2>\n<ol><li>系统管理员按<a class=\"gd-ln\" data-doc=\"07\">《部署与运维手册》</a>完成安装，在 B1 中给每个用户设置执行台权限。</li><li>关键用户按<a class=\"gd-ln\" data-doc=\"06\">《B1 配置维护手册》</a>核对费用池和计算参数。</li><li>成本会计通读<a class=\"gd-ln\" data-doc=\"02\">《成本月结操作手册》</a>第 1、2 章，然后按<a class=\"gd-ln\" data-doc=\"01\">《成本月结清单》</a>做第一次月结。</li></ol>\n<h2 id=\"g00-4\">版本说明</h2>\n<p>本手册适用于当前部署的成本执行台版本。界面或流程有变化时，手册会同时更新，打开本页看到的就是当前版本。</p>"
},
{
"id": "01",
"title": "成本月结清单",
"subtitle": "每月结账时逐项勾选，详细步骤见《月结操作手册》",
"menu": "成本月结清单",
"toc": [],
"html": "<p>账期：________　　成本会计：________　　财务复核：________　　完成日期：________</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>完成</th><th>阶段</th><th>事项</th><th>负责人</th><th>完成标准</th><th>手册</th></tr></thead><tbody><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>B1 准备</td><td>本月收发存、采购、销售、生产单据全部录完</td><td>各业务部门</td><td>业务部门确认无漏单</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-10\">第 3</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>B1 准备</td><td>应付发票、费用凭证已过账</td><td>应付 / 总账会计</td><td>本月费用凭证无遗漏</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-10\">第 3</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>B1 准备</td><td>本月工时单已录入</td><td>生产统计</td><td>“工时维护”清单为空</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-10\">第 3</a>、<a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-14\">4</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>B1 准备</td><td>费用池、计算参数如有变化已维护</td><td>关键用户</td><td>“检查 B1 配置”无问题</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-10\">第 3</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>检查</td><td>执行“只做计算前检查”</td><td>成本会计</td><td>运行状态为“检查通过”</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-14\">第 4</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>检查</td><td>处理全部阻断项，逐条看过警告</td><td>成本会计</td><td>无不通过的阻断项</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-14\">第 4</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>计算</td><td>执行正式计算</td><td>成本会计（管理权限）</td><td>运行状态为“完成”</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-20\">第 5</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>复核</td><td>查看计算后校验</td><td>成本会计</td><td>无未解释的不通过项</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-24\">第 6</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>复核</td><td>抽查物料单价、收发存、订单成本、费用分摊</td><td>成本会计</td><td>异常已解释或已处理</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-24\">第 6</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>对账</td><td>财务对账、科目余额表、应付暂估、发出商品</td><td>成本会计、总账会计</td><td>本期差额为 0，或差额已解释</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-27\">第 7</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>调整</td><td>处理库存重估等调整，调整后重新计算</td><td>成本会计</td><td>重新计算后校验、对账通过</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-31\">第 8</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>凭单</td><td>确认阻断项（如有），生成 SAP 日记账凭单</td><td>财务主管（管理权限）</td><td>账期状态为“已生成凭单”</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-35\">第 9</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>凭单</td><td>在 B1 审核并过账凭单</td><td>总账会计</td><td>凭单全部过账</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-35\">第 9</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>凭单</td><td>过账后重新对账</td><td>成本会计</td><td>总账与业务一致</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-35\">第 9</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>收尾</td><td>导出成本报表、下载计算说明并归档</td><td>成本会计</td><td>报表已归档</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-38\">第 10</a> 章</td></tr><tr><td><input type=\"checkbox\" class=\"gd-ck\"></td><td>收尾</td><td>在 B1 锁定账期</td><td>财务主管</td><td>账期状态为“已锁定”</td><td><a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-38\">第 10</a> 章</td></tr></tbody></table></div>\n<p><b>三条底线</b></p>\n<ol><li>账期生成凭单后不能再正式计算。需要改动时，先按手册<a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-42\">第 11</a> 章撤销或冲销。</li><li>上一账期重新计算过，本账期必须重新计算。</li><li>重新计算后，之前对校验项的确认全部失效，要重新确认。</li></ol>"
},
{
"id": "02",
"title": "成本月结操作手册",
"subtitle": "适用于 SAP Business One 成本执行台",
"menu": "成本月结操作手册",
"toc": [
{
"id": "g02-1",
"t": "关于本手册",
"lv": 1
},
{
"id": "g02-2",
"t": "第 1 章 开始之前",
"lv": 1
},
{
"id": "g02-3",
"t": "1.1 权限",
"lv": 2
},
{
"id": "g02-4",
"t": "1.2 登录",
"lv": 2
},
{
"id": "g02-5",
"t": "1.3 界面",
"lv": 2
},
{
"id": "g02-6",
"t": "1.4 表格操作",
"lv": 2
},
{
"id": "g02-7",
"t": "第 2 章 月结总览",
"lv": 1
},
{
"id": "g02-8",
"t": "2.1 流程",
"lv": 2
},
{
"id": "g02-9",
"t": "2.2 账期状态",
"lv": 2
},
{
"id": "g02-10",
"t": "第 3 章 B1 端准备",
"lv": 1
},
{
"id": "g02-11",
"t": "3.1 单据和凭证",
"lv": 2
},
{
"id": "g02-12",
"t": "3.2 工时",
"lv": 2
},
{
"id": "g02-13",
"t": "3.3 费用池和计算参数",
"lv": 2
},
{
"id": "g02-14",
"t": "第 4 章 只做计算前检查",
"lv": 1
},
{
"id": "g02-15",
"t": "4.1 执行检查",
"lv": 2
},
{
"id": "g02-16",
"t": "4.2 查看结果",
"lv": 2
},
{
"id": "g02-17",
"t": "4.3 常见阻断项",
"lv": 2
},
{
"id": "g02-18",
"t": "4.4 工时维护",
"lv": 2
},
{
"id": "g02-19",
"t": "4.5 期初价维护",
"lv": 2
},
{
"id": "g02-20",
"t": "第 5 章 正式计算",
"lv": 1
},
{
"id": "g02-21",
"t": "5.1 发起计算",
"lv": 2
},
{
"id": "g02-22",
"t": "5.2 查看进度",
"lv": 2
},
{
"id": "g02-23",
"t": "5.3 运行结果",
"lv": 2
},
{
"id": "g02-24",
"t": "第 6 章 计算后复核",
"lv": 1
},
{
"id": "g02-25",
"t": "6.1 计算后校验",
"lv": 2
},
{
"id": "g02-26",
"t": "6.2 业务复核",
"lv": 2
},
{
"id": "g02-27",
"t": "第 7 章 财务对账",
"lv": 1
},
{
"id": "g02-28",
"t": "7.1 财务对账",
"lv": 2
},
{
"id": "g02-29",
"t": "7.2 科目余额表",
"lv": 2
},
{
"id": "g02-30",
"t": "7.3 应付暂估和发出商品",
"lv": 2
},
{
"id": "g02-31",
"t": "第 8 章 调整后重算",
"lv": 1
},
{
"id": "g02-32",
"t": "8.1 库存重估",
"lv": 2
},
{
"id": "g02-33",
"t": "8.2 历史委外差异",
"lv": 2
},
{
"id": "g02-34",
"t": "8.3 模拟计算",
"lv": 2
},
{
"id": "g02-35",
"t": "第 9 章 生成凭单",
"lv": 1
},
{
"id": "g02-36",
"t": "9.1 生成",
"lv": 2
},
{
"id": "g02-37",
"t": "9.2 在 B1 过账",
"lv": 2
},
{
"id": "g02-38",
"t": "第 10 章 结账收尾",
"lv": 1
},
{
"id": "g02-39",
"t": "10.1 成本报表",
"lv": 2
},
{
"id": "g02-40",
"t": "10.2 归档",
"lv": 2
},
{
"id": "g02-41",
"t": "10.3 锁定账期",
"lv": 2
},
{
"id": "g02-42",
"t": "第 11 章 异常处理",
"lv": 1
},
{
"id": "g02-43",
"t": "11.1 运行失败",
"lv": 2
},
{
"id": "g02-44",
"t": "11.2 迭代未收敛",
"lv": 2
},
{
"id": "g02-45",
"t": "11.3 生成凭单后发现问题（凭单未过账）",
"lv": 2
},
{
"id": "g02-46",
"t": "11.4 凭单已过账后发现问题",
"lv": 2
},
{
"id": "g02-47",
"t": "11.5 账期结完后又补了单据",
"lv": 2
},
{
"id": "g02-48",
"t": "11.6 常见问题",
"lv": 2
},
{
"id": "g02-49",
"t": "附录 术语",
"lv": 1
}
],
"html": "<h2 id=\"g02-1\">关于本手册</h2>\n<p>本手册面向负责月度成本结账的成本会计、总账会计和财务主管，按结账的先后顺序说明每一步怎么操作、做到什么程度算完成、出了问题看哪里。本手册在成本执行台左侧菜单“使用手册”中随时可以打开，内容随系统版本更新。</p>\n<p>每月结账时可配合<a class=\"gd-ln\" data-doc=\"01\">《成本月结清单》</a>逐项勾选。核算口径见<a class=\"gd-ln\" data-doc=\"03\">《成本核算规则说明》</a>，校验编号的完整说明见<a class=\"gd-ln\" data-doc=\"04\">《校验与异常处理手册》</a>。</p>\n<blockquote><b>关于截图</b>：本手册的截图经过脱敏处理，物料、业务伙伴、人员名称和金额都不是真实数据，只用于说明界面。</blockquote>\n<h2 id=\"g02-2\">第 1 章 开始之前</h2>\n<h3 id=\"g02-3\">1.1 权限</h3>\n<p>成本执行台使用 B1 账号登录。权限在 B1 用户主数据中设置，分为三级，高级别包含低级别的全部权限。</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>权限</th><th>可以做什么</th><th>建议给谁</th></tr></thead><tbody><tr><td>查看</td><td>查看运行结果、校验、对账和报表</td><td>财务人员、管理层</td></tr><tr><td>操作</td><td>另可执行只做检查、模拟计算、维护模拟场景，生成期初价、工时单据和库存重估单</td><td>成本会计</td></tr><tr><td>管理</td><td>另可执行正式计算、期初承接、生成和撤销凭单、确认校验阻断项</td><td>成本主管、财务主管</td></tr></tbody></table></div>\n<p>权限字段为空的账号不能登录。</p>\n<h3 id=\"g02-4\">1.2 登录</h3>\n<ol><li>在浏览器打开系统管理员提供的成本执行台地址。</li><li>公司有多个时，先选择公司（账套）。</li><li>输入 B1 用户代码和密码，点“登录”。</li></ol>\n<figure class=\"gd-fig\"><img src=\"img/login.png\" alt=\"登录页面\" loading=\"lazy\" data-shot=\"login\"><figcaption>登录页面</figcaption></figure>\n<p>要切换公司，需要退出后重新登录。</p>\n<h3 id=\"g02-5\">1.3 界面</h3>\n<figure class=\"gd-fig\"><img src=\"img/overview.png\" alt=\"成本执行台主界面\" loading=\"lazy\" data-shot=\"overview\"><figcaption>成本执行台主界面</figcaption></figure>\n<ul><li>① <b>运行切换</b>：一次运行是对某个账期的一次计算或检查。点开可看运行记录，选中哪次，左侧菜单各页就显示哪次的结果。</li><li>② <b>左侧菜单</b>：按用途分组，点分组名可以折叠。</li><li>③ <b>发起计算</b>：进入发起计算页。</li><li>④ <b>页签</b>：打开过的页面都留在这里，切换时保留筛选、排序和滚动位置。要重新查询，点“⟳ 刷新”。</li></ul>\n<p>“成本报表”不跟随顶栏所选的运行，取数规则见<a class=\"gd-ln\" data-sec=\"g02-38\">第 10</a> 章。</p>\n<h3 id=\"g02-6\">1.4 表格操作</h3>\n<p>所有表格的用法相同：</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>操作</th><th>方法</th></tr></thead><tbody><tr><td>查看明细</td><td>双击一行，明细在右侧打开，可继续双击往下钻取</td></tr><tr><td>筛选</td><td>用工具条上的筛选框，或点列头的 ▾ 按列筛选</td></tr><tr><td>排序</td><td>点列头</td></tr><tr><td>多行求和</td><td>按住 Ctrl 或 ⌘ 点行，工具条显示已选行数和合计</td></tr><tr><td>复制到 Excel</td><td>点“复制”，然后粘贴到 Excel</td></tr><tr><td>导出</td><td>点“导出 Excel”</td></tr><tr><td>全屏</td><td>点“⛶ 全屏”，按 Esc 退出</td></tr></tbody></table></div>\n<p>表格最多加载 2000 行。行数超出时，用“导出全部 Excel”取得完整数据。</p>\n<h2 id=\"g02-7\">第 2 章 月结总览</h2>\n<h3 id=\"g02-8\">2.1 流程</h3>\n<figure class=\"gd-fig\"><div class=\"gd-flow\"><div class=\"gd-frow\"><span class=\"gd-box\">B1 准备<small>单据、工时、配置</small></span><i>→</i><span class=\"gd-box\">只做检查<small>处理阻断项</small></span><i>→</i><span class=\"gd-box\">正式计算</span><i>→</i><span class=\"gd-box\">计算后复核</span></div><div class=\"gd-frow\"><span class=\"gd-box\">财务对账</span><i>→</i><span class=\"gd-box warn\">需要调整时<small>重估后重新计算</small></span><i>→</i><span class=\"gd-box\">生成凭单</span><i>→</i><span class=\"gd-box\">B1 过账</span></div><div class=\"gd-frow\"><span class=\"gd-box\">重新对账</span><i>→</i><span class=\"gd-box\">成本报表归档</span><i>→</i><span class=\"gd-box\">B1 锁定账期</span></div></div><figcaption>月结流程</figcaption></figure>\n<p>只做检查和正式计算都可以反复执行。在生成凭单之前，发现问题就修改 B1 数据，然后重新计算。</p>\n<h3 id=\"g02-9\">2.2 账期状态</h3>\n<p>每个账期有一个状态，显示在“发起计算”页的账期旁边。</p>\n<figure class=\"gd-fig\"><div class=\"gd-flow\"><div class=\"gd-frow\"><span class=\"gd-box\">未计算</span><i>→</i><span class=\"gd-box\">已计算<small>可反复重算</small></span><i>→</i><span class=\"gd-box\">已生成凭单</span><i>→</i><span class=\"gd-box\">已锁定</span></div><div class=\"hint\">正式计算：未计算 → 已计算　生成凭单：已计算 → 已生成凭单　撤销凭单：已生成凭单 → 已计算　B1 锁账期：已生成凭单 → 已锁定</div></div><figcaption>账期状态</figcaption></figure>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>状态</th><th>含义</th><th>能否正式计算</th></tr></thead><tbody><tr><td>未计算</td><td>本账期还没有成功的正式计算</td><td>可以</td></tr><tr><td>已计算</td><td>已有正式计算结果，可反复重算</td><td>可以</td></tr><tr><td>已生成凭单</td><td>凭单已生成</td><td>不可以，要先撤销凭单</td></tr><tr><td>已锁定</td><td>B1 中账期已锁定</td><td>不可以</td></tr></tbody></table></div>\n<blockquote><b>注意</b>：账期要按顺序结账。下一账期的期初取自上一账期的结果，所以上一账期重新计算后，下一账期也要重新计算。</blockquote>\n<h2 id=\"g02-10\">第 3 章 B1 端准备</h2>\n<p><b>负责人</b>：各业务部门、应付会计、总账会计、关键用户。<b>时间</b>：月末单据截止后。</p>\n<h3 id=\"g02-11\">3.1 单据和凭证</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>确认事项</th><th>说明</th></tr></thead><tbody><tr><td>库存和生产单据</td><td>采购收退货、销售交退货、领料、完工入库、库存转储、其他收发货已录完</td></tr><tr><td>形态转换</td><td>收发两张单据在同一个月，并且一对一配对，不能跨月</td></tr><tr><td>委外加工费</td><td>本月入库的加工费本月暂估，收货与对应的生产入库在同一账期</td></tr><tr><td>生产订单</td><td>该关闭的订单已关闭，工单类型不为空</td></tr><tr><td>费用</td><td>本月费用凭证已过账，成本中心填写正确</td></tr><tr><td>应付发票</td><td>本月发票已录入，发票差额会计入物料成本</td></tr></tbody></table></div>\n<p>计价范围以内的仓库与范围以外的仓库之间不能做库存转储，计算前检查会阻断。</p>\n<h3 id=\"g02-12\">3.2 工时</h3>\n<p>在 B1“生产工时”单据中录入本账期的单位工时。没有单位工时的产品分不到制造费用和人工，计算前检查会阻断。</p>\n<div class=\"gd-todo\">待提供：B1 截图 生产工时单据</div>\n<p>不必一次判断哪些产品缺工时。先执行<a class=\"gd-ln\" data-sec=\"g02-14\">第 4</a> 章的“只做检查”，“工时维护”页会列出清单和参考工时。</p>\n<h3 id=\"g02-13\">3.3 费用池和计算参数</h3>\n<p>费用池和计算参数只在变化时需要维护，在 B1 中修改：</p>\n<ul><li>费用池：主数据“费用池”（<code>@MTC_CA_POOL</code>），维护费用池、所含成本中心和分摊范围。</li><li>计算参数：表格“计算参数”（<code>@MTC_CA_PARAM</code>），一行表示一个参数在一段账期内的取值。</li></ul>\n<div class=\"gd-todo\">待提供：B1 截图 费用池主数据、计算参数表格</div>\n<p>改完后在执行台打开“B1 维护数据”，到“费用池”或“计算参数”页签，点“从 B1 拉取”和“检查 B1 配置”。每次计算开始时系统也会自动读取 B1 的配置。</p>\n<figure class=\"gd-fig\"><img src=\"img/b1cfg.png\" alt=\"计算参数总览\" loading=\"lazy\" data-shot=\"b1cfg\"><figcaption>计算参数总览</figcaption></figure>\n<blockquote><b>注意</b>：已设置锁定的参数行不能修改或删除。缺少某账期适用取值的参数，会在计算前检查中阻断。</blockquote>\n<h2 id=\"g02-14\">第 4 章 只做计算前检查</h2>\n<p><b>负责人</b>：成本会计（操作权限）。<b>目的</b>：在正式计算之前发现数据问题。这一步不计算，也不影响已有结果，可以反复执行。</p>\n<h3 id=\"g02-15\">4.1 执行检查</h3>\n<ol><li>打开左侧菜单“发起计算”。</li><li>在 ① 选择账期，确认账期旁边显示的状态。</li><li>在 ② 选择“正式”。</li><li>确认 ③ 操作人。</li><li>点 ④ “只做计算前检查”。</li></ol>\n<figure class=\"gd-fig\"><img src=\"img/run.png\" alt=\"发起计算页面\" loading=\"lazy\" data-shot=\"run\"><figcaption>发起计算页面</figcaption></figure>\n<p>完成后自动跳到“校验”页。</p>\n<h3 id=\"g02-16\">4.2 查看结果</h3>\n<figure class=\"gd-fig\"><img src=\"img/checks_pre.png\" alt=\"校验页面\" loading=\"lazy\" data-shot=\"checks_pre\"><figcaption>校验页面</figcaption></figure>\n<p>运行状态是“检查通过”时进入<a class=\"gd-ln\" data-sec=\"g02-20\">第 5</a> 章；是“检查阻断”时，表示存在阻断项，必须处理。</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>结果类型</th><th>处理方式</th></tr></thead><tbody><tr><td>阻断</td><td>必须处理。不处理不能完成计算</td></tr><tr><td>警告</td><td>不影响计算。逐条查看，确认业务上合理</td></tr></tbody></table></div>\n<p>双击校验行查看明细，再双击明细行，可以看到对应物料、单据或订单的当月交易。</p>\n<h3 id=\"g02-17\">4.3 常见阻断项</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>问题</th><th>处理</th></tr></thead><tbody><tr><td>缺工时</td><td>见 <a class=\"gd-ln\" data-sec=\"g02-18\">4.4</a></td></tr><tr><td>物料缺少价格来源</td><td>见 <a class=\"gd-ln\" data-sec=\"g02-19\">4.5</a></td></tr><tr><td>形态转换跨月或不是一对一</td><td>在 B1 更正单据</td></tr><tr><td>工单类型为空</td><td>在 B1 补填订单的工单类型</td></tr><tr><td>单据不能识别交易类型</td><td>在 B1 补填业务类型</td></tr><tr><td>计价与非计价仓库之间转储</td><td>在 B1 更正单据</td></tr><tr><td>计算参数缺少本账期的值</td><td>在 B1 补参数行，见 <a class=\"gd-ln\" data-sec=\"g02-13\">3.3</a></td></tr></tbody></table></div>\n<h3 id=\"g02-18\">4.4 工时维护</h3>\n<p>打开“工时维护”页，这里按产品列出需要补录工时的清单，并给出以前账期的参考工时。</p>\n<figure class=\"gd-fig\"><img src=\"img/hrsneed.png\" alt=\"工时维护页面\" loading=\"lazy\" data-shot=\"hrsneed\"><figcaption>工时维护页面</figcaption></figure>\n<p>可以用两种方式补录：</p>\n<ul><li><b>生成 B1 单据</b>：点“生成 B1 单据”，核对确认窗口中的写入内容，输入本人 B1 密码。系统追加到本账期工时单，没有时新建一张。已有非 0 的值不会被覆盖，没有参考工时的产品填 0，需要到 B1 改成实际值。</li><li><b>手工录入</b>：点“复制 B1 录入格式”，粘贴后在 B1 录入。</li></ul>\n<blockquote><b>注意</b>：参考工时只供参考，请核对后再使用。</blockquote>\n<p>录好后重新执行“只做计算前检查”。</p>\n<h3 id=\"g02-19\">4.5 期初价维护</h3>\n<p>有些物料本期有出库、盘盈、其他入库或无原单退货，但计算前没有任何价格来源。这些物料列在“期初价维护”页。</p>\n<figure class=\"gd-fig\"><img src=\"img/qcp.png\" alt=\"期初价维护页面\" loading=\"lazy\" data-shot=\"qcp\"><figcaption>期初价维护页面</figcaption></figure>\n<p>双击一行，可以看到是哪些单据行需要这个价格。系统按以前账期的单价或最近采购价给出建议价，这个价格同样只供参考。补录方式与工时相同，点“生成 B1 单据”或“复制 B1 录入格式”。录好后重新检查，已录入的物料不再出现在清单中。</p>\n<h2 id=\"g02-20\">第 5 章 正式计算</h2>\n<p><b>负责人</b>：成本主管（管理权限）。<b>前提</b>：计算前检查没有阻断项。</p>\n<h3 id=\"g02-21\">5.1 发起计算</h3>\n<ol><li>打开“发起计算”，选择账期，类型选“正式”。</li><li>点“开始计算”。</li><li>在确认窗口核对账套和账期，完整输入账套名，点“确认执行”。</li></ol>\n<figure class=\"gd-fig\"><img src=\"img/run_confirm.png\" alt=\"正式计算确认窗口\" loading=\"lazy\" data-shot=\"run_confirm\"><figcaption>正式计算确认窗口</figcaption></figure>\n<blockquote><b>注意</b>：正式计算会覆盖该账期上一次的正式结果。同一时间只能有一个计算在运行，包括其他公司的计算。</blockquote>\n<h3 id=\"g02-22\">5.2 查看进度</h3>\n<p>计算在服务器后台运行，可以关闭网页，稍后再打开。进度显示在“步骤”页，顶栏也有进度标签。</p>\n<figure class=\"gd-fig\"><img src=\"img/steps.png\" alt=\"步骤页面\" loading=\"lazy\" data-shot=\"steps\"><figcaption>步骤页面</figcaption></figure>\n<p>“计算过程”页以示意图展示同一次运行，点节点可查看这一步做了什么。</p>\n<figure class=\"gd-fig\"><img src=\"img/flow.png\" alt=\"计算过程页面\" loading=\"lazy\" data-shot=\"flow\"><figcaption>计算过程页面</figcaption></figure>\n<h3 id=\"g02-23\">5.3 运行结果</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>状态</th><th>含义</th><th>下一步</th></tr></thead><tbody><tr><td>完成</td><td>计算成功</td><td>进入<a class=\"gd-ln\" data-sec=\"g02-24\">第 6</a> 章</td></tr><tr><td>检查阻断</td><td>计算前检查不通过，没有计算</td><td>回到<a class=\"gd-ln\" data-sec=\"g02-14\">第 4</a> 章</td></tr><tr><td>未收敛</td><td>迭代达到上限，单价仍在变化</td><td>见<a class=\"gd-ln\" data-sec=\"g02-42\">第 11</a> 章</td></tr><tr><td>失败</td><td>运行出错</td><td>见<a class=\"gd-ln\" data-sec=\"g02-42\">第 11</a> 章</td></tr></tbody></table></div>\n<p>运行没有成功时，步骤上方的红框显示完整报错。点“复制报错”，可以把内容发给系统管理员。</p>\n<h2 id=\"g02-24\">第 6 章 计算后复核</h2>\n<p><b>负责人</b>：成本会计。</p>\n<h3 id=\"g02-25\">6.1 计算后校验</h3>\n<p>打开“校验”页，查看计算后校验。这些校验检查数量是否与 B1 一致、收发存是否平衡、费用是否分摊完、订单是否勾稽、凭证是否借贷平衡等。</p>\n<figure class=\"gd-fig\"><img src=\"img/checks_post.png\" alt=\"计算后校验\" loading=\"lazy\" data-shot=\"checks_post\"><figcaption>计算后校验</figcaption></figure>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>结果类型</th><th>处理方式</th></tr></thead><tbody><tr><td>不通过（阻断）</td><td>查明原因。修改数据后重新计算，确属合理的由管理权限在生成凭单时确认</td></tr><tr><td>警告</td><td>查看原因，例如费用波动、入库 0 成本</td></tr></tbody></table></div>\n<h3 id=\"g02-26\">6.2 业务复核</h3>\n<p>建议每月按以下顺序抽查：</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>页面</th><th>看什么</th></tr></thead><tbody><tr><td>物料单价</td><td>单价明显异常的物料，与上期比较</td></tr><tr><td>收发存汇总</td><td>按物料组看期初、入库、出库、期末是否合理</td></tr><tr><td>订单成本</td><td>单位成本、料工费构成，异常订单双击查看构成</td></tr><tr><td>在产品</td><td>长期未完工或金额异常的订单</td></tr><tr><td>费用归集、费用分摊</td><td>各费用池金额是否完整，是否有未分摊的费用</td></tr><tr><td>工时分摊</td><td>哪些产品没有分到费用及其原因</td></tr></tbody></table></div>\n<figure class=\"gd-fig\"><img src=\"img/items.png\" alt=\"物料单价\" loading=\"lazy\" data-shot=\"items\"><figcaption>物料单价</figcaption></figure>\n<figure class=\"gd-fig\"><img src=\"img/inv.png\" alt=\"收发存汇总\" loading=\"lazy\" data-shot=\"inv\"><figcaption>收发存汇总</figcaption></figure>\n<figure class=\"gd-fig\"><img src=\"img/orders.png\" alt=\"订单成本\" loading=\"lazy\" data-shot=\"orders\"><figcaption>订单成本</figcaption></figure>\n<figure class=\"gd-fig\"><img src=\"img/pool.png\" alt=\"费用分摊\" loading=\"lazy\" data-shot=\"pool\"><figcaption>费用分摊</figcaption></figure>\n<p>单价有疑问时，用“成本追溯”从物料或订单出发，逐层展开料工费来源，一直追到采购件。</p>\n<figure class=\"gd-fig\"><img src=\"img/trace.png\" alt=\"成本追溯\" loading=\"lazy\" data-shot=\"trace\"><figcaption>成本追溯</figcaption></figure>\n<h2 id=\"g02-27\">第 7 章 财务对账</h2>\n<p><b>负责人</b>：成本会计、总账会计。</p>\n<h3 id=\"g02-28\">7.1 财务对账</h3>\n<ol><li>打开“财务对账”。</li><li>点“对账（按当前总账计算）”。</li></ol>\n<figure class=\"gd-fig\"><img src=\"img/recon.png\" alt=\"财务对账\" loading=\"lazy\" data-shot=\"recon\"><figcaption>财务对账</figcaption></figure>\n<p>每个对账项分期初、本期、期末列示业务、财务和差额。</p>\n<ul><li>财务本期 = 本期总账分录 + 本期未清凭单 + 本次计算底稿中尚未过账的凭证。因此凭单过账之前就可以对账。</li><li>校验默认按本期差额判断。</li><li>差额 0.01 也算差异。发出商品的小额尾差由系统按参数上限自动结转。</li></ul>\n<p>双击一行查看差额构成。过账或改动总账后，点“重新对账”。</p>\n<h3 id=\"g02-29\">7.2 科目余额表</h3>\n<p>“科目余额表”列出成本相关科目的期初、本期借贷、期末和未过账金额。点科目可看明细账，点分录可看整张凭证或来源。</p>\n<figure class=\"gd-fig\"><img src=\"img/tb.png\" alt=\"科目余额表\" loading=\"lazy\" data-shot=\"tb\"><figcaption>科目余额表</figcaption></figure>\n<h3 id=\"g02-30\">7.3 应付暂估和发出商品</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>页面</th><th>核对内容</th></tr></thead><tbody><tr><td>应付暂估</td><td>截至期末未开票的收货金额，按科目、供应商与总账核对</td></tr><tr><td>暂估凭证 PUR</td><td>逐单据、逐科目核对系统凭证与暂估凭证</td></tr><tr><td>发出商品</td><td>本期发出、开票和未开票计提的情况</td></tr></tbody></table></div>\n<figure class=\"gd-fig\"><img src=\"img/ap.png\" alt=\"应付暂估\" loading=\"lazy\" data-shot=\"ap\"><figcaption>应付暂估</figcaption></figure>\n<figure class=\"gd-fig\"><img src=\"img/goods.png\" alt=\"发出商品\" loading=\"lazy\" data-shot=\"goods\"><figcaption>发出商品</figcaption></figure>\n<p>未开票发货的计提凭证 AR03、AR04 在下月初自动冲销，所以发出商品科目每月期末余额为 0。</p>\n<h2 id=\"g02-31\">第 8 章 调整后重算</h2>\n<p>只有发现需要调整时才做这一章。所有调整都要在生成凭单之前完成，调整后重新计算。</p>\n<h3 id=\"g02-32\">8.1 库存重估</h3>\n<p>应付发票差额可能使结存金额变成负数，或使单价明显失真。“库存重估”页列出两类物料：</p>\n<ul><li>结存数量大于 0，但金额小于等于 0。</li><li>本期发票、贷项差额使加权价偏离较大（默认 10%）。</li></ul>\n<figure class=\"gd-fig\"><img src=\"img/reval.png\" alt=\"库存重估\" loading=\"lazy\" data-shot=\"reval\"><figcaption>库存重估</figcaption></figure>\n<ol><li>勾选要处理的物料，确认或修改目标单价。不勾选的物料不生成。</li><li>查看调整金额，点“生成重估单”。</li><li>重新计算。</li></ol>\n<blockquote><b>注意</b>：重估金额的对方进入制造费用池，会影响其他产品的分摊，所以生成后必须重新计算。要撤销时，先在 B1 取消这张重估单，再重新计算。</blockquote>\n<p>在 B1 手工建的重估单同样生效。</p>\n<h3 id=\"g02-33\">8.2 历史委外差异</h3>\n<p>上线前已关闭、差异留在委外加工物资科目上的委外订单，按整张订单选择账期转出。这项工作只在清理历史差异时使用，需要管理权限，在“历史委外差异”页操作。</p>\n<figure class=\"gd-fig\"><img src=\"img/wwhist.png\" alt=\"历史委外差异\" loading=\"lazy\" data-shot=\"wwhist\"><figcaption>历史委外差异</figcaption></figure>\n<h3 id=\"g02-34\">8.3 模拟计算</h3>\n<p>想先看某项调整的影响，可以用模拟计算：在“模拟场景”页建立假设，发起计算时类型选“模拟”。模拟结果单独保存，不影响正式结果。</p>\n<h2 id=\"g02-35\">第 9 章 生成凭单</h2>\n<p><b>负责人</b>：财务主管（管理权限）。<b>前提</b>：校验和对账已完成。</p>\n<h3 id=\"g02-36\">9.1 生成</h3>\n<p>打开“生成凭单”，选择账期。</p>\n<figure class=\"gd-fig\"><img src=\"img/jv.png\" alt=\"生成凭单\" loading=\"lazy\" data-shot=\"jv\"><figcaption>生成凭单</figcaption></figure>\n<ol><li>查看计划。凭单取本账期最近一次成功的正式运行，每个凭证代码一行，显示借贷金额和状态。本期 B1 已有同一凭证代码的凭证或未清凭单时自动排除。</li><li>有未通过的校验项时，先处理并重新计算；确属合理的，点“确认后仍生成”，写明理由。确认只对这次运行有效。</li><li>勾选凭证代码，点“生成凭单”。</li><li>输入账套名和本人 B1 密码确认。密码不保存，凭单以本人账号在 B1 中创建。</li></ol>\n<p>全部成功后，账期状态变为“已生成凭单”，不能再正式计算。</p>\n<p>部分失败时，已生成的保留。可以重试其余代码；确定不再生成时，点“不再生成其余代码，标记为已生成凭单”；也可以撤销后重来。</p>\n<h3 id=\"g02-37\">9.2 在 B1 过账</h3>\n<p>在 B1“财务 → 日记账凭单”中审核并过账。</p>\n<div class=\"gd-todo\">待提供：B1 截图 日记账凭单列表</div>\n<p>过账后回到“财务对账”，点“重新对账”，确认总账与业务一致。</p>\n<h2 id=\"g02-38\">第 10 章 结账收尾</h2>\n<h3 id=\"g02-39\">10.1 成本报表</h3>\n<p>打开“成本报表”，选择报表，填写条件，点“查询”。</p>\n<figure class=\"gd-fig\"><img src=\"img/rpt.png\" alt=\"成本报表\" loading=\"lazy\" data-shot=\"rpt\"><figcaption>成本报表</figcaption></figure>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>取数规则</th><th>说明</th></tr></thead><tbody><tr><td>已生成凭单的账期</td><td>取凭单所用的那次运行</td></tr><tr><td>其他账期</td><td>取最近一次成功的正式运行</td></tr></tbody></table></div>\n<p>结果上方写明取的是哪次运行。B1 查询管理器中可以打开同样的报表。</p>\n<h3 id=\"g02-40\">10.2 归档</h3>\n<p>打开“计算说明”，这里汇总了本次运行的步骤、校验、费用和凭证。点“下载 HTML”保存。</p>\n<figure class=\"gd-fig\"><img src=\"img/report.png\" alt=\"计算说明\" loading=\"lazy\" data-shot=\"report\"><figcaption>计算说明</figcaption></figure>\n<p>建议每月归档：计算说明、收发存汇总、订单成本、财务对账结果。</p>\n<h3 id=\"g02-41\">10.3 锁定账期</h3>\n<p>确认无误后，由财务主管在 B1 中锁定账期。锁定后执行台的账期状态显示为“已锁定”。</p>\n<div class=\"gd-todo\">待提供：B1 截图 过账期间设置</div>\n<h2 id=\"g02-42\">第 11 章 异常处理</h2>\n<h3 id=\"g02-43\">11.1 运行失败</h3>\n<ol><li>打开“步骤”页，查看红框中的报错和出错步骤。</li><li>点“复制报错”，发给系统管理员。</li><li>修复后重新发起计算。上一次成功运行的结果仍然保留。</li></ol>\n<h3 id=\"g02-44\">11.2 迭代未收敛</h3>\n<p>未收敛表示计算达到迭代上限时单价还在变化。常见原因是物料之间存在循环，例如返工或半成品互相领用。</p>\n<ol><li>在“步骤”页查看迭代过程，看单价变化是否在减小。</li><li>把报错发给系统管理员，由其定位变化最大的物料。</li><li>处理后重新计算。</li></ol>\n<p>未收敛的运行不会写入正式结果，本账期之前成功的运行仍然保留。生成凭单取最近一次成功的正式运行，所以在问题解决之前不要生成凭单。</p>\n<h3 id=\"g02-45\">11.3 生成凭单后发现问题（凭单未过账）</h3>\n<ol><li>在 B1“财务 → 日记账凭单”中删除这些凭单。</li><li>在执行台“生成凭单”页点“撤销凭单”并确认。账期回到“已计算”。</li><li>修改数据，重新计算，走完校验和对账。</li><li>重新生成凭单。</li></ol>\n<h3 id=\"g02-46\">11.4 凭单已过账后发现问题</h3>\n<ol><li>在 B1 冲销已过账的凭证。<b>冲销日期必须选在同一账期内。</b></li><li>在 B1 删除其余未过账的凭单。</li><li>在执行台点“撤销凭单”。</li><li>重新计算，再次生成凭单。</li></ol>\n<blockquote><b>注意</b>：冲销日期落到下一账期时，本账期总账仍含原金额，对账和后续计算都会受影响。这种情况不要继续操作，先联系系统管理员核查。</blockquote>\n<h3 id=\"g02-47\">11.5 账期结完后又补了单据</h3>\n<ul><li>往已生成凭单的账期补重估单时，之后的计算前检查会报出警告。取消后改到未生成凭单的账期重做，或撤销凭单后重新计算。</li><li>毛利走势的“月结固定”口径会报出结账后补单的行数。</li></ul>\n<h3 id=\"g02-48\">11.6 常见问题</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>现象</th><th>原因和处理</th></tr></thead><tbody><tr><td>登录提示没有权限</td><td>B1 用户主数据的权限字段为空，找管理员开通</td></tr><tr><td>“开始计算”是灰色的</td><td>账期已生成凭单或已锁定、正有计算在运行，或者没有管理权限（正式计算需要管理权限，操作权限可以只做检查和模拟），页面上写有原因</td></tr><tr><td>页面提示这次运行没有结果</td><td>所选运行是检查或被阻断的运行，在顶栏换一次成功的运行</td></tr><tr><td>改了 B1 配置后页面没变</td><td>点“从 B1 拉取”，或重新计算</td></tr><tr><td>生成凭单按钮不可用</td><td>需要管理权限，并且要用账号登录的服务器地址</td></tr></tbody></table></div>\n<h2 id=\"g02-49\">附录 术语</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>术语</th><th>含义</th></tr></thead><tbody><tr><td>运行</td><td>对某个账期的一次计算或检查，有唯一的运行号</td></tr><tr><td>正式 / 模拟</td><td>正式结果用于凭单和报表；模拟结果只用于分析</td></tr><tr><td>计算前检查</td><td>计算之前检查数据是否满足条件</td></tr><tr><td>阻断 / 警告</td><td>阻断必须处理；警告需要查看，不影响继续</td></tr><tr><td>费用池</td><td>归集费用并按工时分摊给产品的单位</td></tr><tr><td>期初价</td><td>没有其他价格来源时，在 B1 维护的物料单价</td></tr><tr><td>在产品</td><td>生产订单已投入、尚未完工转出的成本</td></tr><tr><td>关单差异</td><td>订单关闭时留下的在产品余额</td></tr><tr><td>发出商品</td><td>已发货未开票的销售成本</td></tr><tr><td>应付暂估</td><td>已收货未开票的采购金额</td></tr><tr><td>库存重估</td><td>调整物料单价的单据</td></tr><tr><td>迭代 / 收敛</td><td>费用和单价相互影响，要反复计算，直到单价不再变化</td></tr></tbody></table></div>"
},
{
"id": "03",
"title": "成本核算规则说明",
"subtitle": "每个成本数字是怎么算出来的",
"menu": "成本核算规则说明",
"toc": [
{
"id": "g03-1",
"t": "关于本说明",
"lv": 1
},
{
"id": "g03-2",
"t": "第 1 章 总体原则",
"lv": 1
},
{
"id": "g03-3",
"t": "第 2 章 计算流程",
"lv": 1
},
{
"id": "g03-4",
"t": "第 3 章 各类交易的定价",
"lv": 1
},
{
"id": "g03-5",
"t": "第 4 章 订单成本与在产品",
"lv": 1
},
{
"id": "g03-6",
"t": "4.1 结转公式",
"lv": 2
},
{
"id": "g03-7",
"t": "4.2 关单差异",
"lv": 2
},
{
"id": "g03-8",
"t": "4.3 返工单",
"lv": 2
},
{
"id": "g03-9",
"t": "4.4 形态转换",
"lv": 2
},
{
"id": "g03-10",
"t": "4.5 委外订单",
"lv": 2
},
{
"id": "g03-11",
"t": "4.6 本级与成本还原",
"lv": 2
},
{
"id": "g03-12",
"t": "第 5 章 费用归集与分摊",
"lv": 1
},
{
"id": "g03-13",
"t": "5.1 费用来源",
"lv": 2
},
{
"id": "g03-14",
"t": "5.2 归入费用池",
"lv": 2
},
{
"id": "g03-15",
"t": "5.3 分摊",
"lv": 2
},
{
"id": "g03-16",
"t": "第 6 章 期初",
"lv": 1
},
{
"id": "g03-17",
"t": "第 7 章 凭证",
"lv": 1
},
{
"id": "g03-18",
"t": "第 8 章 财务对账",
"lv": 1
},
{
"id": "g03-19",
"t": "第 9 章 库存重估与历史委外差异",
"lv": 1
},
{
"id": "g03-20",
"t": "第 10 章 系统登记的计算规则",
"lv": 1
}
],
"html": "<h2 id=\"g03-1\">关于本说明</h2>\n<p>本说明介绍成本核算的口径：取哪些单据，每类交易怎么定价，订单成本、在产品、费用分摊怎么算，生成哪些凭证，怎样与总账对账。操作步骤见<a class=\"gd-ln\" data-doc=\"02\">《成本月结操作手册》</a>。</p>\n<p>规则编号、校验编号和参数代码以系统登记为准，本说明<a class=\"gd-ln\" data-sec=\"g03-20\">第 10</a> 章从系统中实时列出。</p>\n<h2 id=\"g03-2\">第 1 章 总体原则</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>原则</th><th>含义</th></tr></thead><tbody><tr><td>实际成本、月加权平均</td><td>物料按月计算加权平均单价，材料、人工、制造、委外四项成本分别计算、分别结转</td></tr><tr><td>截至期末</td><td>只取过账日期在期末及以前的单据；订单状态、关单日期、未清数量也按截至期末判断，不看单据现在的状态</td></tr><tr><td>一次运行得出结果</td><td>关单差异、返工、形态转换、期初维护价都在同一次计算中处理，结果与计算次数无关，不需要算两遍</td></tr><tr><td>每个数可追溯</td><td>每行结果都记录价格来源和规则；单价和订单成本可以逐层追到原单据行</td></tr><tr><td>只读单据</td><td>计算不修改 B1 单据，结果写入成本模块自己的表</td></tr></tbody></table></div>\n<p>计价范围：只计算仓库主数据中标记为“计价”的仓库。计价仓库与非计价仓库之间不能做库存转储。</p>\n<h2 id=\"g03-3\">第 2 章 计算流程</h2>\n<figure class=\"gd-fig\"><div class=\"gd-flow\"><div class=\"gd-frow\"><span class=\"gd-box\">取快照<small>截至期末的单据</small></span><i>→</i><span class=\"gd-box\">计算前检查<small>有阻断就停止</small></span><i>→</i><span class=\"gd-box\">固定价格<small>采购、发票差额、重估</small></span></div><div class=\"gd-frow\"><span class=\"gd-box warn\">迭代计算<small>费用池 → 分摊 → 逐级定价</small></span><i>→</i><span class=\"gd-box\">收敛判断<small>单价不再变化</small></span><i>→</i><span class=\"gd-box\">写结果</span></div><div class=\"gd-frow\"><span class=\"gd-box\">计算后校验</span><i>→</i><span class=\"gd-box\">生成凭证底稿</span><i>→</i><span class=\"gd-box\">财务对账</span></div></div><figcaption>计算流程</figcaption></figure>\n<ol><li><b>取快照</b>：把本账期截至期末的单据、订单、工时、期初价、费用凭证、配置复制成快照，之后的计算只用快照。</li><li><b>计算前检查</b>：在快照上检查数据是否满足计算条件，有阻断项就停止，不计算。</li><li><b>固定价格</b>：采购入库、发票差额、库存重估、取消单配对等不随计算变化的金额先定下来。</li><li><b>迭代计算</b>：每一轮依次计算费用池、分摊到订单、按物料层级从下到上逐级给领料定价、结转订单成本、算出完工入库成本和物料加权单价。</li><li><b>收敛判断</b>：本轮单价与上一轮相比不再变化，费用池和关单差异也不再变化，就停止迭代。</li><li><b>写结果、校验、生成凭证底稿</b>：写入物料、订单、在产品、费用分摊等结果，执行计算后校验，生成凭证底稿，与总账对账。</li></ol>\n<p>需要迭代，是因为费用和单价相互影响：公摊材料、关单差异进入费用池，费用池分摊又影响产品单价，产品单价再影响领用它的订单。返工单领用和产出同一个物料，也要通过迭代算到一致。</p>\n<h2 id=\"g03-4\">第 3 章 各类交易的定价</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>交易</th><th>定价</th></tr></thead><tbody><tr><td>采购入库、采购退货</td><td>暂估金额：行上填了指定单价的按指定单价；价格已确认的按单价；否则按行金额。基于收货的退货按收货行的暂估单价</td></tr><tr><td>应付发票、贷项</td><td>发票金额减去冲回的暂估金额，差额计入物料成本；分次开票的最后一次清掉余数</td></tr><tr><td>库存重估</td><td>重估单上的金额</td></tr><tr><td>生产、返工、委外完工入库</td><td>订单本期完工成本 ÷ 本期入库数量 × 行数量，尾差挤到数量最大的行</td></tr><tr><td>生产、返工、委外领料</td><td>子件本期加权单价，四项分别计</td></tr><tr><td>生产退料</td><td>该订单该材料截至本期的平均领料单价；订单没有领料时按物料加权单价</td></tr><tr><td>销售出库</td><td>本期加权单价</td></tr><tr><td>销售退货（有原交货）</td><td>原交货行的成本</td></tr><tr><td>销售退货（无原交货）</td><td>期初维护价；没有维护价按本期加权单价</td></tr><tr><td>形态转换转出</td><td>被转换物料的本期加权单价</td></tr><tr><td>形态转换转入</td><td>等于配对的转出金额（同月、一对一）</td></tr><tr><td>其他出入库、盘点、试打领用</td><td>物料本期加权单价；记入制造费用科目的部分进入费用池</td></tr><tr><td>取消单</td><td>原单成本反向</td></tr><tr><td>报废类业务</td><td>不计价</td></tr></tbody></table></div>\n<p><b>加权单价</b> = （期初金额 + 本期计入加权的入库金额）÷（期初数量 + 本期计入加权的入库数量），材料、人工、制造、委外四项分别计算。每条单据行定价时四项分别保留 2 位小数。</p>\n<p><b>价格来源</b>：本期有出库、其他入库、盘点或无原单退货的物料，计算前必须有价格来源，即期初结存金额、本期有金额的采购 / 完工 / 形态转换入库，或在 B1 维护的期初价。都没有时，计算前检查会列出，在“期初价维护”页补录。0 金额的采购收货不算价格来源。</p>\n<p><b>尾差</b>：物料期末数量为 0、金额不为 0 时，尾差挤进该物料数量最大的出库行。零库存物料的小额尾差在参数上限以内的，由尾差凭证结转。</p>\n<h2 id=\"g03-5\">第 4 章 订单成本与在产品</h2>\n<h3 id=\"g03-6\">4.1 结转公式</h3>\n<p>按“订单 × 材料”计算，四项成本分别计：</p>\n<pre class=\"gd-pre\">累计领料金额 = 截至上期累计 + 本期领料\n结转比例     = min(累计入库数量 ÷ 订单计划数量, 1)\n本期结转     = 累计领料金额 × 结转比例 − 以前各期已结转\n期末在产品   = 累计领料金额 − 累计结转</pre>\n<p>订单本期完工成本 = 各材料本期结转 + 本期分摊的制造费用和人工 + 本期结转的委外加工费。</p>\n<ul><li>制造费用和人工只分摊给本期有入库的订单，不留在在产品中。</li><li>订单全部入库后又补领的材料，在本期没有入库可以承接时留在在产品中，关单时转为关单差异。</li></ul>\n<h3 id=\"g03-7\">4.2 关单差异</h3>\n<p>订单截至期末已关闭、关单日期在本期时，剩余在产品转为关单差异，订单在产品清零。关单差异进入指定的费用池，在同一次计算中分摊给本期完工的产品。</p>\n<h3 id=\"g03-8\">4.3 返工单</h3>\n<p>返工单会领用产品 A，加上其他材料和工费后再入库成 A。领用的 A 与产出的 A 是同一个物料，系统用迭代计算：每一轮按上一轮 A 的单价给领料定价，直到 A 的单价不再变化。返工单与普通订单使用同一个结转公式。</p>\n<h3 id=\"g03-9\">4.4 形态转换</h3>\n<p>形态转换用其他出库单发出 B、其他收货单收入 A，不经过生产订单。A 的入库金额等于 B 的出库金额。收发两张单据必须在同一个月、一对一配对，计算前检查会拦截跨月和一对多。</p>\n<h3 id=\"g03-10\">4.5 委外订单</h3>\n<p>委外订单的成本 = 发出材料 + 委外加工费，不分摊制造费用和人工。</p>\n<ul><li>加工费按加工费收货的暂估金额归集到订单。订单本期有入库时，截至本期归集、尚未结转的加工费全部结转到本期入库；本期没有入库时留在订单上，下次入库时结转；关单时剩余部分转为关单差异。</li><li>业务上要求本月入库的加工费本月暂估。加工费收货与对应的生产入库不在同一账期时，计算前检查给出警告。</li></ul>\n<h3 id=\"g03-11\">4.6 本级与成本还原</h3>\n<p>订单完工成本中的制造费用和人工有两种看法：</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>口径</th><th>含义</th></tr></thead><tbody><tr><td>本级</td><td>本期分摊到这张订单的制造费用和人工，加上这张订单自己的委外加工费；半成品的全部成本都算作材料</td></tr><tr><td>成本还原</td><td>本级部分，加上领用的材料和半成品中所含的制造费用、人工和委外加工费</td></tr></tbody></table></div>\n<p>两种口径的合计相同，都等于完工成本。订单成本页和部分报表可以切换口径。</p>\n<h2 id=\"g03-12\">第 5 章 费用归集与分摊</h2>\n<h3 id=\"g03-13\">5.1 费用来源</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>来源</th><th>内容</th></tr></thead><tbody><tr><td>费用凭证</td><td>本期总账中制造费用科目和人工科目的发生额，只取参数中列出的凭证代码</td></tr><tr><td>公摊材料</td><td>其他出入库、盘点单中记入制造费用科目的物料成本，每轮按最新单价重算</td></tr><tr><td>库存重估</td><td>重估单的对方金额；没有关联到订单的委外加工费重估</td></tr><tr><td>关单差异</td><td>本期关单订单的剩余在产品</td></tr></tbody></table></div>\n<h3 id=\"g03-14\">5.2 归入费用池</h3>\n<p>费用按来源行的成本中心归入费用池。成本中心与费用池的对应关系在 B1 费用池主数据中维护，没有对应关系或没有成本中心的费用进入默认池。关单差异进入指定的“关单差异池”。</p>\n<h3 id=\"g03-15\">5.3 分摊</h3>\n<p>每个费用池按分摊范围（物料组或车间类别、订单类型）分摊给本期有入库的订单：</p>\n<pre class=\"gd-pre\">订单权重 = 产品单位工时 × 订单本期入库数量\n订单分摊额 = 费用池金额 × 订单权重 ÷ 池内全部订单权重之和</pre>\n<ul><li>制造费用和人工用同一个权重，最后一次取整，尾差挤到最大的一行。</li><li>本期净入库为负的订单不分摊。</li><li>委外订单不分摊。</li><li>本期有入库、在分摊范围内、但产品没有单位工时的订单，计算前检查会阻断。同一产品同一账期只能有一个单位工时。</li><li>某个池本期没有可分摊的订单时，金额记为“未分摊”，计算后校验会报出，不转入下期。</li></ul>\n<h2 id=\"g03-16\">第 6 章 期初</h2>\n<ul><li>新系统的第一个账期，物料和订单的期初取自上线前旧系统最后一期的结果（期初承接）。旧系统没有分料工费的部分，按旧系统最近一期完工成本的构成比例拆分。</li><li>以后各期的期初取上一账期最近一次成功的正式计算结果。所以上一账期重新计算后，本账期也要重新计算。</li><li>上线前的账期由历史回填生成，供成本报表查询，不参与新账期的计算。</li></ul>\n<h2 id=\"g03-17\">第 7 章 凭证</h2>\n<p>计算生成凭证底稿，每种凭证代码一张，凭证日期为期末日。底稿在执行台“凭证”页查看，确认后由“生成凭单”写入 B1 日记账凭单，在 B1 审核过账。</p>\n<p>借贷方向与旧系统相同：每种分录的借方、贷方是固定的，金额反向时（退回多于领用、盘盈、差异为负等）在原方向记红字（负数），不换到另一方；同一科目借贷两边都有时分两行列示，不轧差。冲回 B1 系统凭证（PUR2、PUR3、PUR5）时，在原分录同一方记红字。B1 公司设置要允许负数金额。</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>凭证代码</th><th>内容</th></tr></thead><tbody><tr><td>MR01 / MR02</td><td>库存重估</td></tr><tr><td>YF01 / IO01</td><td>其他出入库、盘点：借行上科目，贷存货</td></tr><tr><td>PP01 / WW01</td><td>生产领料 / 委外发料：借订单在产品科目，贷存货</td></tr><tr><td>IO02</td><td>形态转换：借转入物料存货，贷转出物料存货（同一科目借贷各一行）</td></tr><tr><td>PP05</td><td>生产完工入库：借存货，贷生产成本；其中分摊的制造费用、人工贷对应的费用转出科目</td></tr><tr><td>WW03</td><td>委外完工入库：借存货，贷委外加工物资（材料、加工费分别贷）</td></tr><tr><td>PP04</td><td>制造费用科目本期发生额转入生产成本：借生产成本-制造费用，贷各制造费用科目</td></tr><tr><td>JZ01 / JZ03</td><td>生产订单 / 委外订单的关单差异：两行都记借方，关单差异科目正数、在产品科目红字</td></tr><tr><td>JZ04</td><td>零库存尾差、发出商品小额尾差：借存货 / 发出商品，贷主营业务成本</td></tr><tr><td>JZ05</td><td>历史委外差异转出（只在清理历史差异时生成）：两行都记借方</td></tr><tr><td>DN01</td><td>销售交货 / 退货转入发出商品</td></tr><tr><td>DN02 / DN04</td><td>样品销售转出（国内 / 国外），含视同销售销项税</td></tr><tr><td>DN03</td><td>本期开票部分由发出商品转入主营业务成本</td></tr><tr><td>AR03 / AR04</td><td>期末未开票交货计提销售成本（国内 / 国外），下月初由 B1 自动冲销</td></tr><tr><td>PUR1–PUR5</td><td>应付暂估：冲掉 B1 标准成本自动生成的收货、退货、发票凭证，按暂估口径重记。PUR1 / PUR4 借存货 / 140802、贷 220202 应付暂估</td></tr></tbody></table></div>\n<p>存货科目取物料组的存货科目；委外订单的在产品科目是委外加工物资，其他订单是生产成本。</p>\n<h2 id=\"g03-18\">第 8 章 财务对账</h2>\n<p>财务对账逐项比较业务端（计算结果）与财务端（总账）：</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>对账项</th><th>业务端</th></tr></thead><tbody><tr><td>存货科目</td><td>物料期末金额，按物料组的存货科目汇总</td></tr><tr><td>生产成本</td><td>生产、包装、返工订单的在产品</td></tr><tr><td>委外加工物资-材料</td><td>委外订单的在产品（材料）</td></tr><tr><td>委外加工物资-加工费</td><td>委外订单尚未结转的加工费</td></tr><tr><td>发出商品</td><td>期末为 0：月末未开票部分全部计提，下月初冲销</td></tr><tr><td>应付暂估</td><td>截至期末已收货未开票的金额，按供应商</td></tr></tbody></table></div>\n<p><b>财务端</b> = 总账已过账分录 + 未清凭单 + 本次凭证底稿中尚未过账的凭证。同一凭证代码已经过账或已在未清凭单中的，不重复计入。因此凭单过账之前就能对账，过账之后重新对账结果不变。</p>\n<ul><li>期初、本期、期末分开列示业务、财务和差额。默认按本期差额判断。</li><li>生产成本、委外加工物资-材料、发出商品只比较成本模块生成的凭证；手工调整等其他分录单独列出，不算差异。</li><li>差额 0.01 也算差异。</li></ul>\n<h2 id=\"g03-19\">第 9 章 库存重估与历史委外差异</h2>\n<p><b>库存重估</b>：发票差额可能使物料结存金额为负，或使单价明显偏离。系统列出结存数量大于 0 但金额小于等于 0、或发票差额使加权价偏离超过参数阈值的物料，给出建议单价。确认后生成 B1 重估单，重估金额的对方进入费用池，重新计算后生效。</p>\n<p><b>历史委外差异</b>：上线前已关闭、差异留在委外加工物资科目上的委外订单，可以按整张订单选择账期转出。转出金额进入费用池分摊给当月完工产品，同时生成 JZ05 凭证。</p>\n<h2 id=\"g03-20\">第 10 章 系统登记的计算规则</h2>\n<p>以下清单从系统登记表实时读取。</p>\n<div class=\"gd-live\" data-live=\"rules\"><div class=\"empty\">加载中…</div></div>"
},
{
"id": "04",
"title": "校验与异常处理手册",
"subtitle": "校验编号的含义、出现后怎么处理",
"menu": "校验与异常处理",
"toc": [
{
"id": "g04-1",
"t": "第 1 章 校验的种类",
"lv": 1
},
{
"id": "g04-2",
"t": "1.1 阻断和警告",
"lv": 2
},
{
"id": "g04-3",
"t": "1.2 确认阻断项",
"lv": 2
},
{
"id": "g04-4",
"t": "第 2 章 计算前检查的处理",
"lv": 1
},
{
"id": "g04-5",
"t": "2.1 单据问题",
"lv": 2
},
{
"id": "g04-6",
"t": "2.2 工时和费用池",
"lv": 2
},
{
"id": "g04-7",
"t": "2.3 价格和期初",
"lv": 2
},
{
"id": "g04-8",
"t": "2.4 配置和参数",
"lv": 2
},
{
"id": "g04-9",
"t": "2.5 只警告的检查",
"lv": 2
},
{
"id": "g04-10",
"t": "第 3 章 计算后校验的处理",
"lv": 1
},
{
"id": "g04-11",
"t": "第 4 章 对账差异的排查",
"lv": 1
},
{
"id": "g04-12",
"t": "4.1 存货科目有差额",
"lv": 2
},
{
"id": "g04-13",
"t": "4.2 应付暂估有差额",
"lv": 2
},
{
"id": "g04-14",
"t": "4.3 发出商品有差额",
"lv": 2
},
{
"id": "g04-15",
"t": "第 5 章 运行出错和未收敛",
"lv": 1
},
{
"id": "g04-16",
"t": "第 6 章 系统登记的全部校验",
"lv": 1
}
],
"html": "<h2 id=\"g04-1\">第 1 章 校验的种类</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>阶段</th><th>编号</th><th>什么时候执行</th><th>结果</th></tr></thead><tbody><tr><td>计算前检查</td><td>PRE-xx</td><td>只做检查、正式计算、模拟计算开始时</td><td>阻断项不通过时不计算；警告不影响计算</td></tr><tr><td>计算后校验</td><td>POST-xx</td><td>计算完成后</td><td>不通过的阻断项要处理，或在生成凭单时由管理权限确认</td></tr><tr><td>新旧比对</td><td>CMP-xx</td><td>计算完成后</td><td>只用于并行期核对，不影响凭单</td></tr></tbody></table></div>\n<p>“校验”页列出本次运行的全部校验：结果、是否阻断、问题行数和说明。双击一行看明细；明细是物料、单据或订单时，再双击可以看对应的当月交易。</p>\n<h3 id=\"g04-2\">1.1 阻断和警告</h3>\n<ul><li><b>阻断</b>：数据不满足计算条件，或者结果不平。计算前检查有阻断项时，运行状态为“检查阻断”，不计算。</li><li><b>警告</b>：需要人看一眼、确认业务上合理的情况，不影响计算和生成凭单。</li><li>哪些计算后校验只警告，由参数决定（见<a class=\"gd-ln\" data-doc=\"06\">《B1 配置维护手册》</a>）。</li></ul>\n<h3 id=\"g04-3\">1.2 确认阻断项</h3>\n<p>计算后校验不通过时不能生成凭单。确属合理的（例如已知的历史差异），由管理权限在“生成凭单”页逐项点“确认后仍生成”并写明理由。</p>\n<ul><li>确认只对这一次运行有效，重新计算后要重新确认。</li><li>确认记录保留在系统中，可以在“生成凭单”页看到确认人、时间和理由。</li></ul>\n<h2 id=\"g04-4\">第 2 章 计算前检查的处理</h2>\n<h3 id=\"g04-5\">2.1 单据问题</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>编号</th><th>问题</th><th>处理</th></tr></thead><tbody><tr><td>PRE-03</td><td>形态转换跨月、不是一对一、配对信息不完整</td><td>在 B1 更正收发两张单据，使其同月、一对一</td></tr><tr><td>PRE-05</td><td>库存变动识别不了交易类型</td><td>补填其他收发货的业务类型；应收贷项凭证不能直接退货入库</td></tr><tr><td>PRE-06</td><td>领料或入库指向的订单不存在</td><td>核对单据上关联的订单号</td></tr><tr><td>PRE-07</td><td>计价仓库与非计价仓库之间转储</td><td>取消该转储，改为计价仓库之间的转储</td></tr><tr><td>PRE-10</td><td>已关闭或已取消的订单本期仍有出入库</td><td>核对单据是否挂错订单</td></tr><tr><td>PRE-11</td><td>订单已关闭但没有关单日期</td><td>在 B1 核对订单状态</td></tr><tr><td>PRE-24</td><td>订单的工单类型为空</td><td>在 B1 补填订单的工单类型</td></tr><tr><td>PRE-25</td><td>其他收发货的科目与库存交易事务配置不一致</td><td>更正单据科目，或补库存交易事务配置</td></tr><tr><td>PRE-26</td><td>应收发票不基于交货、应收贷项不基于退货</td><td>库存物料必须先交货再开票；改为基于交货 / 退货开票</td></tr><tr><td>PRE-27</td><td>销售单据没有客户类型</td><td>补销售订单类型对应的客户类型</td></tr></tbody></table></div>\n<h3 id=\"g04-6\">2.2 工时和费用池</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>编号</th><th>问题</th><th>处理</th></tr></thead><tbody><tr><td>PRE-13</td><td>同一产品同一账期有多个不同的单位工时</td><td>在 B1 工时单中只保留一个</td></tr><tr><td>PRE-14</td><td>应分摊费用的订单，产品没有单位工时</td><td>在“工时维护”页补录，见<a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-14\">《成本月结操作手册》第 4 章</a></td></tr><tr><td>PRE-17</td><td>有入库的产品不在任何费用池的分摊范围</td><td>核对物料组或车间类别，或调整费用池分摊范围（警告）</td></tr><tr><td>PRE-18</td><td>费用池配置无效</td><td>默认池、关单差异池必须正好各一个；同一产品只能属于一个池</td></tr><tr><td>PRE-19</td><td>订单本期净入库为负</td><td>这类订单不分摊制造费用和人工，核对完工退回（警告）</td></tr></tbody></table></div>\n<h3 id=\"g04-7\">2.3 价格和期初</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>编号</th><th>问题</th><th>处理</th></tr></thead><tbody><tr><td>PRE-02</td><td>物料层级不完整（BOM 子件缺失或循环引用）</td><td>更正 BOM</td></tr><tr><td>PRE-04</td><td>销售退货没有原交货</td><td>允许发生；有期初维护价按维护价，没有按加权价（警告）</td></tr><tr><td>PRE-16</td><td>没有期初</td><td>上一账期先完成正式计算；第一个账期先做期初承接</td></tr><tr><td>PRE-23</td><td>物料需要维护期初价</td><td>在“期初价维护”页补录（警告，但不补会导致 0 成本）</td></tr></tbody></table></div>\n<h3 id=\"g04-8\">2.4 配置和参数</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>编号</th><th>问题</th><th>处理</th></tr></thead><tbody><tr><td>PRE-01</td><td>账期已锁定</td><td>已锁定的账期不能正式计算，可以做模拟</td></tr><tr><td>PRE-28</td><td>B1 计算参数缺少本账期的值</td><td>在 B1 计算参数表补上适用本账期的行</td></tr><tr><td>PRE-30</td><td>历史委外差异转出所需的凭证代码和参数没有配置</td><td>按<a class=\"gd-ln\" data-doc=\"06\">《B1 配置维护手册》</a>补配置</td></tr></tbody></table></div>\n<h3 id=\"g04-9\">2.5 只警告的检查</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>编号</th><th>提示</th><th>看什么</th></tr></thead><tbody><tr><td>PRE-08</td><td>非计价仓库中有生产或采购</td><td>这些行不计成本，确认仓库设置是否正确</td></tr><tr><td>PRE-09</td><td>试打订单用了不允许的领料类型</td><td>核对领料业务类型</td></tr><tr><td>PRE-12</td><td>委外加工费找不到订单</td><td>这笔加工费不会进入任何订单，核对加工费收货的关联</td></tr><tr><td>PRE-15</td><td>制造费用可能重复计入</td><td>同一张其他出入库单既有费用凭证、又作为公摊材料</td></tr><tr><td>PRE-20</td><td>发票不基于收货</td><td>应付发票应基于收货或退货</td></tr><tr><td>PRE-21</td><td>委外发票差额找不到产品</td><td>补发票行上的产品</td></tr><tr><td>PRE-22</td><td>暂估变动没有库存记录</td><td>核对收货是否进了计价仓库</td></tr><tr><td>PRE-29</td><td>已生成凭单的账期有新建的重估单</td><td>取消后改到未生成凭单的账期，或撤销凭单后重新计算</td></tr><tr><td>PRE-31</td><td>委外加工费与入库不在同一账期</td><td>业务要求本月入库本月暂估，核对加工费收货日期</td></tr></tbody></table></div>\n<h2 id=\"g04-10\">第 3 章 计算后校验的处理</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>编号</th><th>内容</th><th>不通过时</th></tr></thead><tbody><tr><td>POST-01</td><td>期末数量 = B1 库存数量</td><td>计价仓库口径与 B1 不一致，联系系统管理员</td></tr><tr><td>POST-02</td><td>收发存四项平衡</td><td>联系系统管理员</td></tr><tr><td>POST-03</td><td>费用池全部分摊</td><td>有未分摊的费用：核对分摊范围和工时</td></tr><tr><td>POST-04</td><td>订单结转勾稽、关单订单在产品为 0</td><td>联系系统管理员</td></tr><tr><td>POST-05</td><td>形态转换、退货、取消单按原单金额</td><td>明细列出找不到原单、按加权价兜底的行</td></tr><tr><td>POST-06</td><td>委外加工物资对账</td><td>双击看差额构成；常见原因是手工调整或加工费没关联订单</td></tr><tr><td>POST-07</td><td>物料异常：负库存、兜底价、无价、0 成本入库</td><td>补期初价或核对单据后重新计算</td></tr><tr><td>POST-08</td><td>凭证借贷平衡、科目齐全</td><td>补科目配置后重新计算</td></tr><tr><td>POST-09</td><td>存货科目总账 = 业务</td><td>见 <a class=\"gd-ln\" data-sec=\"g04-12\">4.1</a></td></tr><tr><td>POST-10</td><td>发出商品对账</td><td>小额尾差按参数自动结转；超过的核对交货和开票</td></tr><tr><td>POST-11</td><td>应付暂估对账</td><td>按供应商看差额，核对暂估凭证</td></tr><tr><td>POST-12</td><td>销售成本取价</td><td>找不到交货成本或客户类型的行</td></tr><tr><td>POST-13</td><td>生产成本对账</td><td>双击看差额构成</td></tr><tr><td>POST-14</td><td>物料成本异常（尾差、单价波动）</td><td>逐项看过即可（警告）</td></tr><tr><td>POST-15</td><td>暂估凭证 PUR 逐单据勾稽</td><td>在“暂估凭证 PUR”页查看（警告）</td></tr><tr><td>POST-16</td><td>制造费用、人工波动</td><td>与前几个月的中位数相比偏离较大，确认费用是否完整（警告）</td></tr><tr><td>POST-17</td><td>按加权价入库的物料单价为 0</td><td>补期初价或核对来源（警告）</td></tr><tr><td>POST-18</td><td>领料完整性：收发存明细的订单领料 = 订单本期领料；生产领料、完工入库没挂订单的行</td><td>核对单据上的订单号，改好后重新计算（警告）</td></tr><tr><td>POST-19</td><td>本期有完工但没有材料</td><td>核对是否漏做领料或领料挂错订单（警告）</td></tr><tr><td>POST-20</td><td>单耗偏离：订单累计领料与按订单用料计划应领相差较大</td><td>核对超领、少领或替代料（警告）</td></tr></tbody></table></div>\n<h2 id=\"g04-11\">第 4 章 对账差异的排查</h2>\n<h3 id=\"g04-12\">4.1 存货科目有差额</h3>\n<ol><li>在“财务对账”双击该科目，看差额落在期初、本期还是期末。</li><li>期初有差额：上一账期没有对平，或上一账期结账后又改了总账。</li><li>本期有差额：看“财务本期”的分录构成，找不是成本模块生成的分录（手工凭证、其他模块的凭证）。</li><li>在“科目余额表”点该科目看明细账，点分录看整张凭证。</li></ol>\n<h3 id=\"g04-13\">4.2 应付暂估有差额</h3>\n<ol><li>在“财务对账”展开应付暂估，按供应商看差额。</li><li>在“应付暂估”页看该供应商截至期末未开票的收货。</li><li>在“暂估凭证 PUR”页逐单据核对系统凭证和暂估凭证。</li></ol>\n<h3 id=\"g04-14\">4.3 发出商品有差额</h3>\n<p>发出商品每月期末应为 0。差额通常来自：上月计提的冲销没有生成、交货或开票的取消单、没有客户类型的销售单据。</p>\n<h2 id=\"g04-15\">第 5 章 运行出错和未收敛</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>现象</th><th>处理</th></tr></thead><tbody><tr><td>运行失败</td><td>在“步骤”页红框中点“复制报错”，发给系统管理员；上一次成功的结果仍然保留</td></tr><tr><td>迭代未收敛</td><td>迭代达到上限时单价还在变化。看“步骤”页的迭代过程，把报错发给系统管理员，由其定位单价变化最大的物料</td></tr><tr><td>计算前检查阻断</td><td>按<a class=\"gd-ln\" data-sec=\"g04-4\">第 2</a> 章处理后重新检查</td></tr></tbody></table></div>\n<p>未收敛或失败的运行不写结果，本账期之前成功的运行仍然保留。生成凭单取最近一次成功的正式运行，问题解决之前不要生成凭单。</p>\n<h2 id=\"g04-16\">第 6 章 系统登记的全部校验</h2>\n<p>以下清单从系统登记表实时读取，包含每项校验的目的和是否阻断。</p>\n<div class=\"gd-live\" data-live=\"checks\"><div class=\"empty\">加载中…</div></div>"
},
{
"id": "05",
"title": "成本报表使用手册",
"subtitle": "报表取哪次计算的数、条件怎么填、各张报表看什么",
"menu": "成本报表",
"toc": [
{
"id": "g05-1",
"t": "第 1 章 在哪里查",
"lv": 1
},
{
"id": "g05-2",
"t": "第 2 章 取数规则",
"lv": 1
},
{
"id": "g05-3",
"t": "第 3 章 条件怎么填",
"lv": 1
},
{
"id": "g05-4",
"t": "第 4 章 查看和导出",
"lv": 1
},
{
"id": "g05-5",
"t": "第 5 章 勾稽关系",
"lv": 1
},
{
"id": "g05-6",
"t": "第 6 章 走势报表",
"lv": 1
},
{
"id": "g05-7",
"t": "6.1 R22 生产成本走势",
"lv": 2
},
{
"id": "g05-8",
"t": "6.2 R23 销售毛利走势",
"lv": 2
},
{
"id": "g05-9",
"t": "第 7 章 报表清单",
"lv": 1
}
],
"html": "<h2 id=\"g05-1\">第 1 章 在哪里查</h2>\n<p>成本报表有两个入口，调用的是同一批报表程序，口径只有一套：</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>入口</th><th>方法</th></tr></thead><tbody><tr><td>成本执行台</td><td>左侧菜单“成本报表”分组。“成本报表”页可以选任意一张；R22 生产成本走势、R23 销售毛利走势另有单独的菜单，带图表</td></tr><tr><td>B1 查询管理器</td><td>B1“工具 → 查询 → 查询管理器”，分类“成本报表（新）”。执行时依次弹出参数框</td></tr></tbody></table></div>\n<p>在执行台“成本报表”页选中报表后点“在 SAP 中打开”，可以看到 B1 查询语句和参数顺序。</p>\n<h2 id=\"g05-2\">第 2 章 取数规则</h2>\n<p>报表不跟随顶栏所选的运行，按账期自动选择：</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>账期</th><th>取哪次运行</th></tr></thead><tbody><tr><td>已生成凭单</td><td>生成凭单所用的那次运行</td></tr><tr><td>已计算、未生成凭单</td><td>最近一次成功的正式运行</td></tr><tr><td>新系统上线前</td><td>旧系统结果回填的历史数据</td></tr><tr><td>没有计算过</td><td>没有数据</td></tr></tbody></table></div>\n<p>查询结果上方写明每个账期取的是哪次运行、什么时候算的。R00“成本报表运行状态”列出全部账期的取数情况。</p>\n<p>上线前的历史数据来自旧系统，料工费按旧系统完工成本的比例拆分，是估算值；部分报表在历史账期只返回提示。</p>\n<h2 id=\"g05-3\">第 3 章 条件怎么填</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>条件类型</th><th>填法</th></tr></thead><tbody><tr><td>账期</td><td>下拉选择，有的报表可以选起止账期</td></tr><tr><td>物料、订单、物料组等代码</td><td>留空 = 全部；按开头匹配；多个用逗号分隔；前面加“=”表示精确匹配</td></tr><tr><td>下拉选项</td><td>按提示选择，例如汇总 / 明细、按产品 / 按订单</td></tr><tr><td>是 / 否</td><td>勾选或选择</td></tr></tbody></table></div>\n<p>执行台中改了条件不会自动查询，点“查询”或在输入框中按 Enter 才查。点“恢复默认条件”回到默认值。条件记在本机浏览器，下次打开仍在。</p>\n<h2 id=\"g05-4\">第 4 章 查看和导出</h2>\n<ul><li>表格的筛选、排序、复制、导出 Excel 与执行台其他表格相同，见<a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-2\">《成本月结操作手册》第 1 章</a>。</li><li>带“双击一行看明细”提示的报表，可以双击钻取到下一层报表，条件自动带过去。</li><li>行数超过 2000 时只加载前 2000 行，底部合计标为“已加载 N 行合计”；用“导出全部 Excel”取得完整数据。</li></ul>\n<h2 id=\"g05-5\">第 5 章 勾稽关系</h2>\n<p>几张报表之间有固定的勾稽关系，可以用来交叉核对：</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>关系</th><th>说明</th></tr></thead><tbody><tr><td>R01 完工转出 = R02 完工成本 = R03 生产入库</td><td>产品成本计算单、完工产品成本汇总、收发存汇总一致</td></tr><tr><td>R01 本级分摊 = R06 已分配</td><td>费用分配表与成本计算单一致，R06 未分配应为 0</td></tr><tr><td>R03 期末合计 = R09 存货业务端</td><td>收发存与财务对账一致</td></tr><tr><td>R07 期末在产品 = 委外加工物资业务端</td><td>委外加工成本表与财务对账一致</td></tr><tr><td>R10 来源明细合计 = 分录合计</td><td>凭证清单与业务来源一致</td></tr><tr><td>R19 期末在产品 = R20 明细合计</td><td>在产品汇总与明细一致</td></tr></tbody></table></div>\n<p>报表程序另有一组自动勾稽，由系统管理员在部署后执行。</p>\n<h2 id=\"g05-6\">第 6 章 走势报表</h2>\n<h3 id=\"g05-7\">6.1 R22 生产成本走势</h3>\n<p>物料每个月的完工数量、单位成本和料工费构成，月份作为列，适合看连续几个月的趋势。</p>\n<ul><li>料工费有两种口径：“本级”只算本订单分摊的制造费用和人工，半成品全部算作材料；“成本还原”把半成品中的料工费也拆出来。两种口径合计相同。</li><li>不同产品的单位成本不能相加，汇总图看的是完工成本和料工费占比。</li><li>双击产品看单位成本构成和完工订单。</li></ul>\n<h3 id=\"g05-8\">6.2 R23 销售毛利走势</h3>\n<p>物料每个月的收入、成本和毛利，属于业务口径，与凭证是否过账无关。有两种口径：</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>口径</th><th>含义</th><th>适用</th></tr></thead><tbody><tr><td>随时看</td><td>当月发票 + 当月交货中至今未开票的部分（暂估）。以后开票时，这笔货移到开票的月份，以前月份的数会变</td><td>日常分析</td></tr><tr><td>月结固定</td><td>当月发票 + 期末暂估 − 期初暂估，只列已结账账期，数字不再变化</td><td>给管理层的月报</td></tr></tbody></table></div>\n<ul><li>样品默认不含，可以勾选包含。</li><li>没有对应交货的发票或贷项归在“(未归属产品)”。</li><li>“月结固定”口径下，往已结账的账期补单时会报出“结账后补单行数”。</li><li>表格每行有迷你走势图；勾选最多 6 个物料，在上方对比图中比较；双击行看单品明细。</li></ul>\n<h2 id=\"g05-9\">第 7 章 报表清单</h2>\n<p>以下清单随系统版本更新。</p>\n<div class=\"gd-live\" data-live=\"reports\"><div class=\"empty\">加载中…</div></div>"
},
{
"id": "06",
"title": "B1 配置维护手册",
"subtitle": "在 SAP Business One 中维护的成本配置：权限、费用池、计算参数、工时、期初价",
"menu": "B1 配置维护",
"toc": [
{
"id": "g06-1",
"t": "第 1 章 维护什么、在哪里维护",
"lv": 1
},
{
"id": "g06-2",
"t": "第 2 章 权限",
"lv": 1
},
{
"id": "g06-3",
"t": "第 3 章 费用池",
"lv": 1
},
{
"id": "g06-4",
"t": "3.1 表头",
"lv": 2
},
{
"id": "g06-5",
"t": "3.2 成本中心（子表）",
"lv": 2
},
{
"id": "g06-6",
"t": "3.3 分摊范围（子表）",
"lv": 2
},
{
"id": "g06-7",
"t": "3.4 成本中心归池",
"lv": 2
},
{
"id": "g06-8",
"t": "第 4 章 计算参数",
"lv": 1
},
{
"id": "g06-9",
"t": "4.1 修改参数",
"lv": 2
},
{
"id": "g06-10",
"t": "4.2 锁定",
"lv": 2
},
{
"id": "g06-11",
"t": "4.3 缺参数",
"lv": 2
},
{
"id": "g06-12",
"t": "4.4 系统参数",
"lv": 2
},
{
"id": "g06-13",
"t": "4.5 参数清单",
"lv": 2
},
{
"id": "g06-14",
"t": "第 5 章 工时和期初价",
"lv": 1
},
{
"id": "g06-15",
"t": "5.1 单位工时",
"lv": 2
},
{
"id": "g06-16",
"t": "5.2 期初成本价",
"lv": 2
},
{
"id": "g06-17",
"t": "第 6 章 凭证代码",
"lv": 1
}
],
"html": "<h2 id=\"g06-1\">第 1 章 维护什么、在哪里维护</h2>\n<p>成本核算的配置都在 B1 中维护，执行台只读取、不修改。每次检查或计算开始时，系统自动从 B1 读取最新配置。</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>配置</th><th>B1 中的位置</th><th>什么时候改</th></tr></thead><tbody><tr><td>执行台权限</td><td>用户主数据的用户定义字段“成本执行台权限”</td><td>新增或调整用户时</td></tr><tr><td>费用池</td><td>主数据“费用池”（<code>@MTC_CA_POOL</code>）</td><td>车间、成本中心、产品范围变化时</td></tr><tr><td>成本中心归池</td><td>成本中心主数据的“成本计入类型”（<code>U_CalType</code>）</td><td>新增成本中心时</td></tr><tr><td>计算参数</td><td>表格“成本计算参数”（<code>@MTC_CA_PARAM</code>）</td><td>科目、凭证代码、阈值、业务口径变化时</td></tr><tr><td>单位工时</td><td>生产工时单据（<code>@MTC_COST_TIME</code>）</td><td>每月</td></tr><tr><td>期初成本价</td><td>期初成本价单据（<code>@MTC_COST_QCPRICE</code>）</td><td>计算前检查提示时</td></tr><tr><td>仓库是否计价</td><td>仓库主数据 <code>U_IsCost</code></td><td>新增仓库时</td></tr><tr><td>交易类型、业务类型</td><td><code>@MTC_COST_IOTYPE</code>、<code>@U_CIOTRN</code></td><td>新增业务类型时</td></tr></tbody></table></div>\n<p>改完后在执行台“B1 维护数据”页点“从 B1 拉取”和“检查 B1 配置”，确认没有问题。</p>\n<div class=\"gd-todo\">待提供：B1 截图 费用池主数据、计算参数表格</div>\n<h2 id=\"g06-2\">第 2 章 权限</h2>\n<p>执行台用 B1 账号登录，权限取用户主数据上的用户定义字段：</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>取值</th><th>权限</th><th>可以做什么</th></tr></thead><tbody><tr><td>R</td><td>查看</td><td>查看运行结果、校验、对账和报表</td></tr><tr><td>O</td><td>操作</td><td>另可只做检查、模拟计算、维护模拟场景，生成期初价、工时和库存重估单据</td></tr><tr><td>A</td><td>管理</td><td>另可正式计算、期初承接、生成和撤销凭单、确认校验阻断项</td></tr><tr><td>空</td><td>无</td><td>不能登录</td></tr></tbody></table></div>\n<p>在 B1“管理 → 设置 → 常规 → 用户”中打开用户，在用户定义字段栏（菜单“视图 → 用户定义字段”）选择权限，用户下次登录执行台时生效。同一个人在不同公司可以有不同的权限。</p>\n<p>字段由系统管理员在部署时添加，方法见<a class=\"gd-ln\" data-doc=\"07\">《部署与运维手册》</a>。</p>\n<h2 id=\"g06-3\">第 3 章 费用池</h2>\n<p>费用池决定费用归到哪里、分摊给哪些产品。</p>\n<h3 id=\"g06-4\">3.1 表头</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>字段</th><th>填法</th></tr></thead><tbody><tr><td>代码、名称</td><td>费用池代码和名称</td></tr><tr><td>默认池</td><td>没有对应成本中心的费用进入默认池，所有费用池中<b>正好一个</b>填 Y</td></tr><tr><td>关单差异池</td><td>关单差异进入这个池，<b>正好一个</b>填 Y</td></tr><tr><td>说明</td><td>备注</td></tr></tbody></table></div>\n<h3 id=\"g06-5\">3.2 成本中心（子表）</h3>\n<p>列出归入本池的成本中心。成本中心可以直接填代码，也可以填成本计入类型（见 <a class=\"gd-ln\" data-sec=\"g06-7\">3.4</a>）。默认池可以不填。</p>\n<h3 id=\"g06-6\">3.3 分摊范围（子表）</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>字段</th><th>填法</th></tr></thead><tbody><tr><td>匹配方式</td><td>按物料组（GRP）或按车间类别（GRPTYPE）</td></tr><tr><td>匹配值</td><td>物料组代码或车间类别</td></tr><tr><td>订单类型</td><td>参与分摊的订单类型，多个用逗号分隔</td></tr><tr><td>起始 / 截止账期</td><td>留空表示全部账期</td></tr></tbody></table></div>\n<p>同一个产品同一时期只能属于一个费用池。</p>\n<h3 id=\"g06-7\">3.4 成本中心归池</h3>\n<p>成本中心主数据上的“成本计入类型”字段（<code>U_CalType</code>）填写费用池子表中登记的值，该成本中心的费用就进入那个池；不填则进入默认池。以后新增同类成本中心，只要填这个字段，不用改费用池。</p>\n<p>在成本中心子表中单独登记了代码的成本中心，以单独登记为准。</p>\n<h2 id=\"g06-8\">第 4 章 计算参数</h2>\n<p>计算参数表一行表示一个参数在一段账期内的取值。</p>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>字段</th><th>填法</th></tr></thead><tbody><tr><td>代码</td><td>参数代码，区分大小写。同一参数的第二段起写成“参数代码@起始账期”</td></tr><tr><td>名称、分类</td><td>参数的中文名和分类，照抄</td></tr><tr><td>起始 / 截止账期</td><td>留空表示全部账期</td></tr><tr><td>取值</td><td>列表用逗号分隔，前后不加逗号；数字只填数字，不带单位或 %</td></tr></tbody></table></div>\n<h3 id=\"g06-9\">4.1 修改参数</h3>\n<p><b>不要直接改原来那一行的取值</b>，否则重算以前的账期时会用上新值。正确做法：</p>\n<ol><li>把原来那一行的截止账期填成上一期。</li><li>新增一行，代码填“参数代码@新账期”，起始账期填新账期，填新取值。</li></ol>\n<p>同一参数的账期段不能重叠，保存时会校验。</p>\n<h3 id=\"g06-10\">4.2 锁定</h3>\n<p>参数行的“锁定”字段为 Y 时，保存时不能修改取值，也不能删除。锁定和解锁的权限由 B1 权限控制。</p>\n<h3 id=\"g06-11\">4.3 缺参数</h3>\n<p>系统登记的参数在 B1 中没有适用于本账期的行时，计算前检查会阻断（PRE-28），需要补上。在 B1 中删除一行参数不会恢复默认值。</p>\n<h3 id=\"g06-12\">4.4 系统参数</h3>\n<p>“计算控制”分类中的收敛标准、最大迭代轮数、起始账期、承接账期等是系统参数，以及“成本模块生成的凭证代码”，录入后不要改。需要调整时先联系成本核算实施人员。</p>\n<h3 id=\"g06-13\">4.5 参数清单</h3>\n<p>以下清单从系统实时读取，显示当前账期适用的取值和来源（B1 或系统默认值）。在执行台“B1 维护数据 → 计算参数”页可以看到更完整的状态和锁定情况。</p>\n<div class=\"gd-live\" data-live=\"params\"><div class=\"empty\">加载中…</div></div>\n<h2 id=\"g06-14\">第 5 章 工时和期初价</h2>\n<h3 id=\"g06-15\">5.1 单位工时</h3>\n<p>在 B1 生产工时单据中录入本账期各产品的单位工时。</p>\n<ul><li>同一产品同一账期只能有一个单位工时。</li><li>本期有入库、在费用池分摊范围内的产品必须有单位工时，否则计算前检查阻断。</li><li>执行台“工时维护”页列出缺工时的产品和参考工时，可以直接生成 B1 单据，也可以复制后手工录入。见<a class=\"gd-ln\" data-doc=\"02\" data-sec=\"g02-14\">《成本月结操作手册》第 4 章</a>。</li></ul>\n<h3 id=\"g06-16\">5.2 期初成本价</h3>\n<p>物料本期有出库等需要单价的变动，但计算前没有任何价格来源时，要在期初成本价单据中维护单价。执行台“期初价维护”页列出这些物料、需要它的单据行和建议价。</p>\n<p>期初价只作为没有其他价格来源时的初始价或兜底价，有采购、完工入库或期初结存时以实际成本为准。</p>\n<h2 id=\"g06-17\">第 6 章 凭证代码</h2>\n<p>成本模块生成的凭证代码（MR01、PP05、DN03、PUR1 等）必须在 B1 凭证代码（交易代码）中存在。新增凭证代码时，同时把它加进计算参数“成本模块生成的凭证代码”。</p>\n<p>使用历史委外差异转出时，要先在 B1 建凭证代码 JZ05，加进上述参数，并且<b>不要</b>加进“计入费用池的凭证代码”参数（否则转出金额会被重复计入费用池）。计算前检查 PRE-30 会核对这些配置。</p>"
},
{
"id": "07",
"title": "部署与运维手册",
"subtitle": "给系统管理员：安装、升级、日常运维和故障排查",
"menu": "部署与运维",
"toc": [
{
"id": "g07-1",
"t": "第 1 章 系统结构",
"lv": 1
},
{
"id": "g07-2",
"t": "1.1 数据库中的表",
"lv": 2
},
{
"id": "g07-3",
"t": "1.2 入口过程",
"lv": 2
},
{
"id": "g07-4",
"t": "第 2 章 安装前准备",
"lv": 1
},
{
"id": "g07-5",
"t": "第 3 章 部署数据库对象",
"lv": 1
},
{
"id": "g07-6",
"t": "第 4 章 安装执行台服务",
"lv": 1
},
{
"id": "g07-7",
"t": "第 5 章 日常运维",
"lv": 1
},
{
"id": "g07-8",
"t": "5.1 重启",
"lv": 2
},
{
"id": "g07-9",
"t": "5.2 升级",
"lv": 2
},
{
"id": "g07-10",
"t": "5.3 日志",
"lv": 2
},
{
"id": "g07-11",
"t": "5.4 查看运行状态",
"lv": 2
},
{
"id": "g07-12",
"t": "5.5 卸载",
"lv": 2
},
{
"id": "g07-13",
"t": "第 6 章 故障排查",
"lv": 1
},
{
"id": "g07-14",
"t": "第 7 章 安全",
"lv": 1
}
],
"html": "<h2 id=\"g07-1\">第 1 章 系统结构</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>组成</th><th>内容</th><th>位置</th></tr></thead><tbody><tr><td>数据库对象</td><td>存储过程、函数、视图和表，前缀 <code>MTC_CA_</code></td><td>B1 公司库（HANA），每个公司一套</td></tr><tr><td>执行台服务</td><td>Python 程序 <code>dev_server.py</code>，提供网页和查询接口</td><td>一台 Windows 服务器，开机自动运行</td></tr><tr><td>网页</td><td><code>index.html</code>、<code>css/</code>、<code>js/</code>，浏览器打开</td><td>由执行台服务提供，不需要外网</td></tr><tr><td>B1 Service Layer</td><td>验证登录密码，写日记账凭单、重估单、工时和期初价单据</td><td>B1 服务器</td></tr></tbody></table></div>\n<p>执行台服务只做两类数据库操作：只读查询（在只读事务中执行，结束后回滚），以及调用登记过的成本过程（计算、检查、承接、场景维护等）。可以执行哪些查询和过程登记在 <code>actions.json</code> 中，网页不能提交任意语句。</p>\n<h3 id=\"g07-2\">1.1 数据库中的表</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>层</th><th>表名前缀</th><th>内容</th></tr></thead><tbody><tr><td>运行日志</td><td><code>MTC_CA_RUN*</code></td><td>每次运行的状态、步骤、迭代过程，全部保留</td></tr><tr><td>配置</td><td><code>MTC_CA_C_*</code></td><td>参数、科目、费用池、校验登记；每次运行从 B1 同步</td></tr><tr><td>元数据</td><td><code>MTC_CA_M_*</code></td><td>表和字段说明，执行台“说明书”页使用</td></tr><tr><td>快照</td><td><code>MTC_CA_S_*</code></td><td>每次运行取的截至期末的输入数据</td></tr><tr><td>结果</td><td><code>MTC_CA_R_*</code></td><td>物料、订单、在产品、费用分摊、凭证底稿、校验结果</td></tr><tr><td>期初承接</td><td><code>MTC_CA_BOOT_*</code></td><td>上线时从旧系统承接的期初</td></tr></tbody></table></div>\n<p>同一账期、同一运行类型和场景，只保留最近一次成功运行的明细；失败、阻断、未收敛的运行保留日志和必要的排查数据。</p>\n<h3 id=\"g07-3\">1.2 入口过程</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>过程</th><th>用途</th></tr></thead><tbody><tr><td><code>MTC_CA_P_RUN</code></td><td>正式或模拟计算</td></tr><tr><td><code>MTC_CA_P_PRECHECK</code></td><td>只做计算前检查</td></tr><tr><td><code>MTC_CA_P_BOOTSTRAP</code></td><td>期初承接（上线时一次）</td></tr><tr><td><code>MTC_CA_P_LEGACY_LOAD</code></td><td>历史回填（把旧系统结果转成报表可查的历史数据）</td></tr><tr><td><code>MTC_CA_RPT_*</code></td><td>成本报表，B1 查询管理器和执行台共用</td></tr></tbody></table></div>\n<p>这些过程一般都由执行台调用，不需要在数据库中直接执行。</p>\n<h2 id=\"g07-4\">第 2 章 安装前准备</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>项目</th><th>要求</th></tr></thead><tbody><tr><td>服务器</td><td>Windows Server，能访问 HANA 和 B1 Service Layer</td></tr><tr><td>Python</td><td>3.8 以上，安装时勾选“所有用户”和“加入 PATH”</td></tr><tr><td>HANA 驱动</td><td>HANA Client（ODBC）。Python 位数要与 HANA Client 一致；装了 hdbcli 时优先用 hdbcli</td></tr><tr><td>数据库账号</td><td>能读当前公司库、执行 <code>MTC_CA_*</code> 过程，能读 <code>OUSR</code>、<code>CUFD</code></td></tr><tr><td>服务账号</td><td>一个专门运行服务的 Windows 本地账号，不要用个人账号</td></tr><tr><td>B1 自定义对象</td><td>成本模块用到的用户定义表和字段（部署包执行时会列出缺少的）</td></tr></tbody></table></div>\n<h2 id=\"g07-5\">第 3 章 部署数据库对象</h2>\n<p>部署包 <code>部署包/</code> 可以单独复制到能连接 HANA 的电脑上执行，包内没有账号密码。</p>\n<ol><li>双击 <code>部署.bat</code>（只装了 32 位 HANA Client 时用 <code>部署_32位.bat</code>），按提示选择连接、输入账号密码。</li><li>程序显示连接的账号、租户和公司库，以及库中已有的成本对象数量；列出缺少的 B1 自定义表和字段。</li><li><b>完整输入目标公司库名</b>确认，不一致时取消。</li><li>程序按依赖顺序执行：已有的表、旧模块对象跳过不覆盖；新框架的表缺列时自动补列；视图、过程更新为本包的版本。</li><li>结束时列出失败语句和无效对象，日志写到 <code>部署日志_&lt;时间&gt;.txt</code>。</li></ol>\n<p>部署后在执行台“期初承接”页执行期初承接（只在上线时做一次），需要时再执行历史回填。</p>\n<blockquote><b>注意</b>：B1 的 <code>SBO_SP_TransactionNotification</code> 不在部署包中。计算参数和费用池的保存校验是一段需要人工合入的代码，合入前先备份原过程。</blockquote>\n<h2 id=\"g07-6\">第 4 章 安装执行台服务</h2>\n<ol><li>把执行台服务器包解压到服务器，例如 <code>D:\\MTC执行台\\</code>。</li><li>复制 <code>console\\server.example.json</code> 为 <code>console\\server.json</code>，填写：</li></ol>\n<p>   - <code>schema</code>：默认公司库；<code>schemas</code>：可选的公司（多个公司时）。</p>\n<p>   - <code>hana</code>：HANA 地址、端口、账号、密码（或 hdbuserstore 键）。</p>\n<p>   - <code>sl.url</code>：Service Layer 地址；<code>sl.company</code>：公司数据库名。</p>\n<p>   - <code>allowNets</code>：允许访问的网段。</p>\n<ol><li>密码加密（建议）：在服务器上执行 <code>python console\\dev_server.py --server --set-password</code>，输入两次密码，<code>server.json</code> 中写成 <code>\"password\": \"dpapi:...\"</code>。加密后只有这台服务器能解开。</li><li>收紧 <code>server.json</code> 的文件权限：只留管理员和服务账号。</li><li>在 B1 中添加权限字段：“工具 → 定制工具 → 用户定义字段 - 管理 → 设置 → 常规 → 用户”，字段名 <code>MTC_CARole</code>，描述“成本执行台权限”，类型“字母数字”，长度 1，有效值 R 查看、O 操作、A 管理，不设默认值。然后给每个用户设置权限（见<a class=\"gd-ln\" data-doc=\"06\" data-sec=\"g06-2\">《B1 配置维护手册》第 2 章</a>）。</li><li>试运行：双击 <code>run_server.bat</code>，看日志中出现“访问地址”，用另一台电脑的浏览器打开并登录。确认后<b>关掉这个窗口</b>。</li><li>正式运行：右键 <code>install_service.bat</code> → 以管理员身份运行，输入服务账号和允许的网段。脚本注册开机任务“MTC Cost Console”并开放防火墙端口。</li><li>需要 HTTPS 时，把证书和私钥（PEM）放在 <code>console\\</code>，<code>server.json</code> 中写 <code>\"tls\": {\"cert\": \"server.crt\", \"key\": \"server.key\"}</code>，然后重启服务。账号密码要经过网络传输，建议启用。</li></ol>\n<p>正式运行后服务在后台运行，开机自动启动，不需要有人登录服务器；程序意外退出会自动重启。</p>\n<h2 id=\"g07-7\">第 5 章 日常运维</h2>\n<h3 id=\"g07-8\">5.1 重启</h3>\n<p>右键 <code>restart_service.bat</code> → 以管理员身份运行。脚本停止任务、结束残留进程、重新启动，并显示日志最后几行。</p>\n<blockquote><b>注意</b>：重启会断开所有人的登录。<b>有人正在计算时不要重启</b>，计算会中断。顶栏有“运行中”提示时先等计算结束。</blockquote>\n<h3 id=\"g07-9\">5.2 升级</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>改了什么</th><th>覆盖哪些文件</th><th>要不要重启</th></tr></thead><tbody><tr><td>页面、使用手册、查询白名单</td><td><code>console\\index.html</code>、<code>login.html</code>、<code>actions.json</code>、<code>console\\css\\</code>、<code>console\\js\\</code>、<code>console\\img\\</code>、<code>console\\srcsql\\</code></td><td>不用，用户刷新浏览器即可</td></tr><tr><td>服务程序</td><td><code>console\\dev_server.py</code>、<code>hana_odbc.py</code>、<code>dpapi.py</code></td><td>要</td></tr><tr><td>配置、证书</td><td><code>console\\server.json</code>、证书文件</td><td>要</td></tr><tr><td>数据库对象</td><td>重新执行部署包</td><td>不用；执行时不要有人在计算</td></tr></tbody></table></div>\n<p>覆盖时不要删除 <code>console\\server.json</code>、<code>console\\logs\\</code>、<code>console\\audit\\</code>。</p>\n<h3 id=\"g07-10\">5.3 日志</h3>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>文件</th><th>内容</th></tr></thead><tbody><tr><td><code>console\\logs\\server.log</code></td><td>服务启动、退出、报错、每次登录的验证过程</td></tr><tr><td><code>console\\logs\\access-年月.jsonl</code></td><td>登录、登录失败、无权限、发起计算、场景维护、计算结束</td></tr><tr><td><code>console\\audit\\</code></td><td>AI 助手的出网审计（目前未接入大模型）</td></tr></tbody></table></div>\n<p>日志只保存在服务器上，不要外发。</p>\n<h3 id=\"g07-11\">5.4 查看运行状态</h3>\n<p>PowerShell 中执行 <code>Get-ScheduledTask -TaskName 'MTC Cost Console'</code>，State 为 Running 表示正在运行；也可以看 <code>server.log</code> 最后几行。</p>\n<h3 id=\"g07-12\">5.5 卸载</h3>\n<pre class=\"gd-pre\">Unregister-ScheduledTask -TaskName &#x27;MTC Cost Console&#x27;\nRemove-NetFirewallRule -DisplayName &#x27;MTC Cost Console&#x27;</pre>\n<h2 id=\"g07-13\">第 6 章 故障排查</h2>\n<div class=\"gd-tw\"><table class=\"gd-t\"><thead><tr><th>现象</th><th>排查</th></tr></thead><tbody><tr><td>浏览器打不开</td><td>服务是否在运行；防火墙端口；访问电脑是否在 <code>allowNets</code> 网段内</td></tr><tr><td>登录一直“正在验证…”</td><td>看 <code>server.log</code>：停在“正在经 Service Layer 验证密码”是 Service Layer 连不上或很慢，检查 <code>sl.url</code> 和 Service Layer 服务；停在“正在读权限”是连不上 HANA</td></tr><tr><td>登录提示没有权限</td><td>用户主数据的权限字段为空</td></tr><tr><td>启动报 -10709</td><td>HANA 地址或端口不对</td></tr><tr><td>启动报 10 或 414</td><td>HANA 账号或密码不对</td></tr><tr><td>启动报 -10104 Invalid value for KEY</td><td>hdbuserstore 键不是用服务账号创建的</td></tr><tr><td>页面提示账套不可用</td><td>该公司库没有部署成本对象，或数据库账号没有权限</td></tr><tr><td>计算失败</td><td>在“步骤”页复制报错；出错步骤和报错原文是排查的起点</td></tr><tr><td>迭代未收敛</td><td>“步骤”页的迭代过程列出每轮单价变化；系统保留最后一轮的中间结果和单价变化最大的物料，供排查</td></tr><tr><td>生成凭单失败</td><td>看“生成凭单”页每个凭证代码的报错；常见原因是科目不能记账、Service Layer 会话过期</td></tr></tbody></table></div>\n<h2 id=\"g07-14\">第 7 章 安全</h2>\n<ul><li>登录密码交给 B1 Service Layer 验证，执行台不保存密码；验证后立即登出。连续失败 5 次暂停 5 分钟。</li><li>空闲超过设定时间（默认 8 小时）要重新登录；服务重启后所有人重新登录。</li><li>操作人一律取登录账号，写进运行记录，页面上不能修改。</li><li>正式计算、期初承接、历史回填要完整输入公司库名确认；生成凭单还要输入本人 B1 密码。</li><li>网页不引用任何外网资源，内网电脑不能上网也可以使用。</li><li>使用手册中的截图经过脱敏处理，不含真实业务数据。</li></ul>"
}
];
