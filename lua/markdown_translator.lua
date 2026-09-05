-- lua/markdown_translator.lua
-- Markdown 语法全套词库与快速输入翻译器
-- 触发方式: 输入 Md 或 mD + 符号/关键词

local M = {}

local LANG_MAP = {
    ["ts"] = "typescript",
    ["js"] = "javascript",
    ["py"] = "python",
    ["sh"] = "bash",
    ["yml"] = "yaml",
    ["rs"] = "rust",
    ["md"] = "markdown",
}

-- 通用代码块列表生成函数
local function get_code_block_cands(lang)
    if lang and lang ~= "" then
        local full_lang = LANG_MAP[lang] or lang
        local upper = full_lang:upper()
        local res = {
            { text = "```" .. full_lang .. "  ```", comment = upper .. " 代码块", left = 3 },
        }
        if full_lang ~= lang then
            table.insert(res, { text = "```" .. lang .. "  ```", comment = lang:upper() .. " 代码块", left = 3 })
        end
        table.insert(res, { text = "`" .. lang .. "`", comment = upper .. " 行内代码", left = 0 })
        return res
    end
    return {
        { text = "```  ```", comment = "代码块 (``` | ```)", left = 3 },
        { text = "``", comment = "行内代码 `|`", left = 1 },
        { text = "```bash  ```", comment = "Bash 块", left = 3 },
        { text = "```shell  ```", comment = "Shell 块", left = 3 },
        { text = "```php  ```", comment = "PHP 代码块", left = 3 },
        { text = "```python  ```", comment = "Python 代码块", left = 3 },
        { text = "```javascript  ```", comment = "JS 代码块", left = 3 },
        { text = "```typescript  ```", comment = "TS 代码块", left = 3 },
        { text = "```html  ```", comment = "HTML 块", left = 3 },
        { text = "```css  ```", comment = "CSS 块", left = 3 },
        { text = "```json  ```", comment = "JSON 块", left = 3 },
        { text = "```yaml  ```", comment = "YAML 块", left = 3 },
        { text = "```sql  ```", comment = "SQL 块", left = 3 },
        { text = "```cpp  ```", comment = "C/C++ 块", left = 3 },
        { text = "```c  ```", comment = "C 语言块", left = 3 },
        { text = "```java  ```", comment = "Java 块", left = 3 },
        { text = "```go  ```", comment = "Go 块", left = 3 },
        { text = "```rust  ```", comment = "Rust 块", left = 3 },
        { text = "```vue  ```", comment = "Vue 块", left = 3 },
        { text = "```mermaid  ```", comment = "Mermaid 流程图", left = 3 },
        { text = "```markdown  ```", comment = "Markdown 块", left = 3 },
    }
end

-- Markdown 语法词库定义
local MD_DATA = {
    -- 1. 井号 (#): 各级标题 (1~6 级)
    ["#"] = {
        { text = "# ", comment = "H1 一级标题", left = 0 },
        { text = "## ", comment = "H2 二级标题", left = 0 },
        { text = "### ", comment = "H3 三级标题", left = 0 },
        { text = "#### ", comment = "H4 四级标题", left = 0 },
        { text = "##### ", comment = "H5 五级标题", left = 0 },
        { text = "###### ", comment = "H6 六级标题", left = 0 },
    },

    -- 2. 星号 (*): 斜体、粗体、粗斜体、列表、分割线
    ["*"] = {
        { text = "****", comment = "粗体 **|**", left = 2 },
        { text = "**", comment = "斜体 *|*", left = 1 },
        { text = "******", comment = "粗斜体 ***|***", left = 3 },
        { text = "- ", comment = "无序列表", left = 0 },
        { text = "***", comment = "分割线", left = 0 },
    },

    -- 3. 减号 (-): 列表、待办任务、分割线、删除线
    ["-"] = {
        { text = "- ", comment = "无序列表", left = 0 },
        { text = "- [ ] ", comment = "待办事项 (未完成)", left = 0 },
        { text = "- [x] ", comment = "待办事项 (已完成)", left = 0 },
        { text = "---", comment = "水平分割线", left = 0 },
        { text = "~~~~", comment = "删除线 ~~|~~", left = 2 },
    },

    -- 4. 加号 (+): 列表、下划线
    ["+"] = {
        { text = "+ ", comment = "无序列表", left = 0 },
        { text = "++", comment = "下划线 ++|++", left = 1 },
    },

    -- 5. 大于号 (>): 引用与各类 Callout 标注框
    [">"] = {
        { text = "> ", comment = "块级引用", left = 0 },
        { text = "> [!NOTE] ", comment = "Note 提示框", left = 0 },
        { text = "> [!TIP] ", comment = "Tip 技巧框", left = 0 },
        { text = "> [!IMPORTANT] ", comment = "Important 重要框", left = 0 },
        { text = "> [!WARNING] ", comment = "Warning 警告框", left = 0 },
        { text = "> [!CAUTION] ", comment = "Caution 危险框", left = 0 },
        { text = ">> ", comment = "嵌套引用", left = 0 },
    },

    -- 6. 中括号 ([): 超链接、图片、双链、脚注
    ["["] = {
        { text = "[]()", comment = "超链接 [|]()", left = 3 },
        { text = "![]()", comment = "插入图片 ![|]()", left = 3 },
        { text = "[[]]", comment = "Obsidian 双链 [[|]]", left = 2 },
        { text = "![[]]", comment = "嵌入双链 ![[|]]", left = 2 },
        { text = "[^1]", comment = "脚注引用 [^|]", left = 1 },
        { text = "[^1]: ", comment = "脚注定义", left = 0 },
    },
    ["!"] = {
        { text = "![]()", comment = "插入图片 ![|]()", left = 3 },
        { text = "![[]]", comment = "嵌入文件 ![[|]]", left = 2 },
    },

    -- 7. 竖线 (|): 表格模板
    ["|"] = {
        { text = "| 标题1 | 标题2 |", comment = "2列 表格行", left = 0 },
        { text = "| --- | --- |", comment = "两列表格", left = 0 },
        { text = "| 标题1 | 标题2 | 标题3 |", comment = "3列 表格行", left = 0 },
        { text = "| --- | --- | --- |", comment = "三列表格", left = 0 },
        { text = "| :--- | :--- |", comment = "表格左对齐", left = 0 },
        { text = "| :---: | :---: |", comment = "表格居中对齐", left = 0 },
        { text = "| ---: | ---: |", comment = "表格右对齐", left = 0 },
        { text = "| 标题1 | 标题2 | 标题3 | 标题4 |", comment = "4列 表格行", left = 0 },
        { text = "| --- | --- | --- | --- |", comment = "四列表格", left = 0 },
        { text = "| 标题1 | 标题2 | 标题3 | 标题4 | 标题5 |", comment = "5列 表格行", left = 0 },
        { text = "| --- | --- | --- | --- | --- |", comment = "五列表格", left = 0 },
    },

    -- 8. 美元符号 ($): LaTeX 数学公式
    ["$"] = {
        { text = "$$", comment = "行内公式 $|$", left = 1 },
        { text = "$$  $$", comment = "块级公式 $$ | $$", left = 3 },
    },

    -- 9. 等号 (=): 高亮与标题下划线
    ["="] = {
        { text = "====", comment = "高亮 ==|==", left = 2 },
        { text = "===", comment = "H1 底线", left = 0 },
    },

    -- 10. 波浪号 (~): 删除线与下标
    ["~"] = {
        { text = "~~~~", comment = "删除线 ~~|~~", left = 2 },
        { text = "~~", comment = "下标 ~|~", left = 1 },
    },

    -- 11. 插入符号 (^): 上标与脚注
    ["^"] = {
        { text = "^^", comment = "上标 ^|^", left = 1 },
        { text = "[^1]", comment = "脚注引用", left = 1 },
        { text = "[^1]: ", comment = "脚注定义", left = 0 },
    },

    -- 12. 尖括号 (<): HTML 扩展标签
    ["<"] = {
        { text = "<details><summary>标题</summary>内容</details>", comment = "折叠详情块", left = 0 },
        { text = "<!--  -->", comment = "HTML 注释 <!-- | -->", left = 4 },
        { text = "<kbd></kbd>", comment = "按键标签 <kbd>|</kbd>", left = 6 },
        { text = "<u></u>", comment = "下划线 <u>|</u>", left = 4 },
        { text = "<br>", comment = "强制换行", left = 0 },
    },

    -- 13. 反引号 (`): 代码块
    ["`"] = get_code_block_cands(""),
}

-- 助记词别名映射
local ALIAS_MAP = {
    -- 标题
    ["h"] = "#", ["h1"] = "#", ["h2"] = "#", ["h3"] = "#", ["h4"] = "#", ["h5"] = "#", ["h6"] = "#",
    ["bt"] = "#", ["biaoti"] = "#", ["title"] = "#",

    -- 粗体
    ["b"] = { { text = "****", comment = "粗体 **|**", left = 2 } },
    ["ct"] = { { text = "****", comment = "粗体 **|**", left = 2 } },
    ["cu"] = { { text = "****", comment = "粗体 **|**", left = 2 } },
    ["bold"] = { { text = "****", comment = "粗体 **|**", left = 2 } },
    ["cuti"] = { { text = "****", comment = "粗体 **|**", left = 2 } },

    -- 斜体
    ["i"] = { { text = "**", comment = "斜体 *|*", left = 1 } },
    ["xt"] = { { text = "**", comment = "斜体 *|*", left = 1 } },
    ["italic"] = { { text = "**", comment = "斜体 *|*", left = 1 } },
    ["xieti"] = { { text = "**", comment = "斜体 *|*", left = 1 } },

    -- 粗斜体
    ["bi"] = { { text = "******", comment = "粗斜体 ***|***", left = 3 } },
    ["cuxieti"] = { { text = "******", comment = "粗斜体 ***|***", left = 3 } },

    -- 删除线
    ["s"] = { { text = "~~~~", comment = "删除线 ~~|~~", left = 2 } },
    ["sc"] = { { text = "~~~~", comment = "删除线 ~~|~~", left = 2 } },
    ["del"] = { { text = "~~~~", comment = "删除线 ~~|~~", left = 2 } },
    ["strike"] = { { text = "~~~~", comment = "删除线 ~~|~~", left = 2 } },
    ["shanchuxian"] = { { text = "~~~~", comment = "删除线 ~~|~~", left = 2 } },

    -- 高亮
    ["hl"] = { { text = "====", comment = "高亮 ==|==", left = 2 } },
    ["gl"] = { { text = "====", comment = "高亮 ==|==", left = 2 } },
    ["mark"] = { { text = "====", comment = "高亮 ==|==", left = 2 } },
    ["highlight"] = { { text = "====", comment = "高亮 ==|==", left = 2 } },
    ["gaoliang"] = { { text = "====", comment = "高亮 ==|==", left = 2 } },

    -- 各种语言代码块
    ["code"] = "`", ["dm"] = "`", ["daima"] = "`",
    ["php"] = get_code_block_cands("php"),
    ["py"] = get_code_block_cands("python"),
    ["python"] = get_code_block_cands("python"),
    ["js"] = get_code_block_cands("javascript"),
    ["javascript"] = get_code_block_cands("javascript"),
    ["ts"] = get_code_block_cands("typescript"),
    ["typescript"] = get_code_block_cands("typescript"),
    ["json"] = get_code_block_cands("json"),
    ["yaml"] = get_code_block_cands("yaml"),
    ["yml"] = get_code_block_cands("yaml"),
    ["bash"] = get_code_block_cands("bash"),
    ["sh"] = get_code_block_cands("bash"),
    ["shell"] = get_code_block_cands("bash"),
    ["mermaid"] = get_code_block_cands("mermaid"),
    ["sql"] = get_code_block_cands("sql"),
    ["cpp"] = get_code_block_cands("cpp"),
    ["c"] = get_code_block_cands("c"),
    ["cs"] = get_code_block_cands("csharp"),
    ["csharp"] = get_code_block_cands("csharp"),
    ["java"] = get_code_block_cands("java"),
    ["go"] = get_code_block_cands("go"),
    ["golang"] = get_code_block_cands("go"),
    ["rust"] = get_code_block_cands("rust"),
    ["html"] = get_code_block_cands("html"),
    ["css"] = get_code_block_cands("css"),
    ["vue"] = get_code_block_cands("vue"),

    -- 超链接与图片
    ["link"] = { { text = "[]()", comment = "超链接 [|]()", left = 3 } },
    ["lj"] = { { text = "[]()", comment = "超链接 [|]()", left = 3 } },
    ["lianjie"] = { { text = "[]()", comment = "超链接 [|]()", left = 3 } },
    ["url"] = { { text = "[]()", comment = "超链接 [|]()", left = 3 } },
    ["img"] = { { text = "![]()", comment = "插入图片 ![|]()", left = 3 } },
    ["tp"] = { { text = "![]()", comment = "插入图片 ![|]()", left = 3 } },
    ["tupian"] = { { text = "![]()", comment = "插入图片 ![|]()", left = 3 } },
    ["image"] = { { text = "![]()", comment = "插入图片 ![|]()", left = 3 } },
    ["pic"] = { { text = "![]()", comment = "插入图片 ![|]()", left = 3 } },

    -- 表格
    ["table"] = "|", ["bg"] = "|", ["biaoge"] = "|",

    -- 待办任务
    ["task"] = {
        { text = "- [ ] ", comment = "待办事项 (未完成)", left = 0 },
        { text = "- [x] ", comment = "待办事项 (已完成)", left = 0 },
    },
    ["db"] = {
        { text = "- [ ] ", comment = "待办事项 (未完成)", left = 0 },
        { text = "- [x] ", comment = "待办事项 (已完成)", left = 0 },
    },
    ["daiban"] = {
        { text = "- [ ] ", comment = "待办事项 (未完成)", left = 0 },
        { text = "- [x] ", comment = "待办事项 (已完成)", left = 0 },
    },
    ["todo"] = {
        { text = "- [ ] ", comment = "待办事项 (未完成)", left = 0 },
        { text = "- [x] ", comment = "待办事项 (已完成)", left = 0 },
    },

    -- 引用与 Callout
    ["quote"] = ">", ["yy"] = ">", ["yinyong"] = ">",
    ["callout"] = ">", ["ts"] = ">", ["tishi"] = ">",
    ["note"] = { { text = "> [!NOTE] ", comment = "Note 提示框", left = 0 } },
    ["tip"] = { { text = "> [!TIP] ", comment = "Tip 技巧框", left = 0 } },
    ["warn"] = { { text = "> [!WARNING] ", comment = "Warning 警告框", left = 0 } },
    ["warning"] = { { text = "> [!WARNING] ", comment = "Warning 警告框", left = 0 } },
    ["info"] = { { text = "> [!NOTE] ", comment = "Info 信息框", left = 0 } },

    -- 数学公式
    ["math"] = "$", ["gs"] = "$", ["gongshi"] = "$", ["latex"] = "$",

    -- 分割线
    ["hr"] = { { text = "---", comment = "水平分割线", left = 0 } },
    ["fgx"] = { { text = "---", comment = "水平分割线", left = 0 } },
    ["line"] = { { text = "---", comment = "水平分割线", left = 0 } },

    -- 双链
    ["wiki"] = {
        { text = "[[]]", comment = "Obsidian 双链 [[|]]", left = 2 },
        { text = "![[]]", comment = "嵌入双链 ![[|]]", left = 2 },
    },
    ["sl"] = {
        { text = "[[]]", comment = "Obsidian 双链 [[|]]", left = 2 },
        { text = "![[]]", comment = "嵌入双链 ![[|]]", left = 2 },
    },
    ["shuanglian"] = {
        { text = "[[]]", comment = "Obsidian 双链 [[|]]", left = 2 },
    },

    -- 脚注
    ["footnote"] = {
        { text = "[^1]", comment = "脚注引用 [^|]", left = 1 },
        { text = "[^1]: ", comment = "脚注定义", left = 0 },
    },
    ["jz"] = {
        { text = "[^1]", comment = "脚注引用 [^|]", left = 1 },
        { text = "[^1]: ", comment = "脚注定义", left = 0 },
    },
    ["jiaozhu"] = {
        { text = "[^1]", comment = "脚注引用 [^|]", left = 1 },
        { text = "[^1]: ", comment = "脚注定义", left = 0 },
    },

    -- 折叠块
    ["details"] = { { text = "<details><summary>标题</summary>内容</details>", comment = "折叠详情块", left = 0 } },
    ["zd"] = { { text = "<details><summary>标题</summary>内容</details>", comment = "折叠详情块", left = 0 } },
    ["zhedie"] = { { text = "<details><summary>标题</summary>内容</details>", comment = "折叠详情块", left = 0 } },

    -- 目录
    ["toc"] = { { text = "[TOC]", comment = "自动生成目录", left = 0 } },
    ["ml"] = { { text = "[TOC]", comment = "自动生成目录", left = 0 } },
    ["mulu"] = { { text = "[TOC]", comment = "自动生成目录", left = 0 } },

    -- 按键标签
    ["kbd"] = { { text = "<kbd></kbd>", comment = "按键标签 <kbd>|</kbd>", left = 6 } },
    ["aj"] = { { text = "<kbd></kbd>", comment = "按键标签 <kbd>|</kbd>", left = 6 } },
}

-- 默认精选候选 (当仅输入 Md/mD 时展示)
local DEFAULT_CANDS = {
    { text = "# ", comment = "一级标题 H1", left = 0 },
    { text = "****", comment = "粗体 **|**", left = 2 },
    { text = "**", comment = "斜体 *|*", left = 1 },
    { text = "- ", comment = "无序列表", left = 0 },
    { text = "- [ ] ", comment = "待办清单", left = 0 },
    { text = "> ", comment = "块级引用", left = 0 },
    { text = "```  ```", comment = "代码块 (``` | ```)", left = 3 },
    { text = "[]()", comment = "超链接 [|]()", left = 3 },
    { text = "![]()", comment = "插入图片 ![|]()", left = 3 },
    { text = "---", comment = "分割线", left = 0 },
    { text = "| 标题1 | 标题2 |", comment = "2列 表格行", left = 0 },
}

-- 中文全角标点与符号归一化映射
local PUNCT_MAP = {
    ["【"] = "[", ["】"] = "]",
    ["《"] = "<", ["》"] = ">",
    ["！"] = "!",
    ["¥"] = "$", ["￥"] = "$",
    ["……"] = "^",
    ["·"] = "`", ["｀"] = "`",
    ["～"] = "~",
    ["＝"] = "=",
    ["＋"] = "+",
    ["－"] = "-",
    ["＊"] = "*",
    ["＃"] = "#",
    ["｜"] = "|",
}

function M.init(env)
end

function M.func(input, seg, env)
    -- 检查是否属于 markdown tag 或以 Md/mD 开头
    local is_md = seg:has_tag("markdown") or input:match("^Md") or input:match("^mD")
    if not is_md then
        return
    end

    -- 规范化查询串：若前缀未被 affix_segmentor 剥离则剥离，否则直接使用
    local query = input
    if query:match("^Md") or query:match("^mD") then
        query = query:sub(3)
    end

    -- 自动将中文模式下的标点转换为标准 Markdown ASCII 符号
    for cn_p, en_p in pairs(PUNCT_MAP) do
        query = query:gsub(cn_p, en_p)
    end

    local query_lower = query:lower()

    local list = nil
    if query == "" then
        list = DEFAULT_CANDS
    elseif query:match("^`") then
        local count = select(2, query:gsub("`", ""))
        local lang = query:gsub("^`+", ""):lower():gsub("%s+", "")
        if lang ~= "" then
            list = get_code_block_cands(lang)
        elseif count == 2 then
            -- 双反引号 ``: 用户输入行内代码，置顶行内代码 ``
            list = {
                { text = "``", comment = "行内代码 `|`", left = 1 },
                { text = "```  ```", comment = "代码块 (``` | ```)", left = 3 },
            }
            for _, item in ipairs(get_code_block_cands("")) do
                if item.text ~= "``" and item.text ~= "```  ```" then
                    table.insert(list, item)
                end
            end
        elseif count >= 3 then
            -- 三反引号 ``` 或更多: 置顶通用代码块
            list = {
                { text = "```  ```", comment = "代码块 (``` | ```)", left = 3 },
                { text = "``", comment = "行内代码 `|`", left = 1 },
            }
            for _, item in ipairs(get_code_block_cands("")) do
                if item.text ~= "``" and item.text ~= "```  ```" then
                    table.insert(list, item)
                end
            end
        else
            -- 单反引号 `: 默认代码块候选列表
            list = get_code_block_cands("")
        end
    elseif query:match("^#+") then
        local h_count = #query
        list = {}
        for i = math.min(h_count, 6), 6 do
            local hashes = string.rep("#", i) .. " "
            table.insert(list, { text = hashes, comment = "H" .. i .. " " .. i .. "级标题", left = 0 })
        end
        for i = 1, math.min(h_count - 1, 6) do
            local hashes = string.rep("#", i) .. " "
            table.insert(list, { text = hashes, comment = "H" .. i .. " " .. i .. "级标题", left = 0 })
        end
    elseif query:match("^%*+") then
        list = MD_DATA["*"]
    elseif query:match("^%-+") then
        list = MD_DATA["-"]
    elseif query:match("^=+") then
        list = MD_DATA["="]
    elseif query:match("^~+") then
        list = MD_DATA["~"]
    elseif query:match("^%++") then
        list = MD_DATA["+"]
    elseif query:match("^>+") then
        list = MD_DATA[">"]
    elseif query:match("^%[+") then
        list = MD_DATA["["]
    elseif query:match("^%$+") then
        list = MD_DATA["$"]
    elseif MD_DATA[query] then
        list = MD_DATA[query]
    elseif ALIAS_MAP[query_lower] then
        local target = ALIAS_MAP[query_lower]
        if type(target) == "string" and MD_DATA[target] then
            list = MD_DATA[target]
        elseif type(target) == "table" then
            list = target
        end
    else
        -- 前缀模糊匹配
        list = {}
        for key, items in pairs(ALIAS_MAP) do
            if key:sub(1, #query_lower) == query_lower then
                if type(items) == "string" and MD_DATA[items] then
                    for _, item in ipairs(MD_DATA[items]) do
                        table.insert(list, item)
                    end
                elseif type(items) == "table" then
                    for _, item in ipairs(items) do
                        table.insert(list, item)
                    end
                end
            end
        end
        if #list == 0 then
            return
        end
    end

    -- 生成候选词列表
    for idx, item in ipairs(list) do
        local cand = Candidate("markdown", seg.start, seg._end, item.text, "  " .. item.comment)
        cand.quality = 10000 - idx
        if query == "" then
            cand.preedit = "〔Markdown〕"
        else
            cand.preedit = "〔MD〕" .. query
        end
        yield(cand)
    end
end

return M
